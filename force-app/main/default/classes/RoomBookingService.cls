/**
 * Booking rules for Room_Booking__c (spec 001-meeting-room-booking).
 * Runs in before insert / before update (validate + stamp) and in after undelete (validate only,
 * REQ-026). Errors use addError, so partial success keeps working (REQ-013); no DML.
 */
public with sharing class RoomBookingService {
  public static final String STATUS_ACTIVE = 'Active';
  public static final String STATUS_CANCELLED = 'Cancelled';

  /** 1900-01-01 was a Monday; used to compute the ISO day of week (1=Mon..7=Sun). */
  private static final Date KNOWN_MONDAY = Date.newInstance(1900, 1, 1);
  private static final Integer LAST_WEEKDAY = 5;
  private static final Long MILLIS_PER_MINUTE = 60000L;

  private final MeetingRoomSelector roomSelector = new MeetingRoomSelector();
  private final RoomBookingSelector bookingSelector = new RoomBookingSelector();

  /**
   * REQ-011 / REQ-021: records when a booking is cancelled and clears it when it is active again.
   */
  public void stampCancellation(
    List<Room_Booking__c> bookings,
    Map<Id, Room_Booking__c> oldMap
  ) {
    Datetime now = System.now();
    for (Room_Booking__c booking : bookings) {
      Room_Booking__c old = oldMap == null ? null : oldMap.get(booking.Id);
      if (
        booking.Status__c == STATUS_CANCELLED &&
        (old == null ||
        old.Status__c != STATUS_CANCELLED)
      ) {
        booking.Cancelled_At__c = now;
      } else if (booking.Status__c == STATUS_ACTIVE) {
        booking.Cancelled_At__c = null;
      }
    }
  }

  /**
   * Applies REQ-004 to REQ-010, REQ-019, REQ-021, REQ-025 and REQ-026 to the bookings that need it.
   * Bookings are processed in the order received: within a batch, the first one wins (REQ-025).
   * `oldMap` is null on insert and undelete.
   */
  public void validate(
    List<Room_Booking__c> bookings,
    Map<Id, Room_Booking__c> oldMap
  ) {
    Datetime now = System.now();
    String timeZoneId = UserInfo.getTimeZone().getID();
    BookingLimits limits = new BookingLimits();

    List<Room_Booking__c> passedTimeRules = new List<Room_Booking__c>();
    List<Room_Booking__c> stillOccupied = new List<Room_Booking__c>();
    Set<Id> roomIds = new Set<Id>();
    for (Room_Booking__c booking : bookings) {
      Room_Booking__c old = oldMap == null ? null : oldMap.get(booking.Id);
      if (hasMissingRequiredFields(booking)) {
        // Platform required-field validation reports it after the before trigger (API/Apex loads).
        continue;
      }
      if (!needsValidation(booking, old)) {
        if (booking.Status__c == STATUS_ACTIVE) {
          stillOccupied.add(booking);
        }
        continue;
      }
      String error = checkTimeRules(
        booking,
        needsDateWindowCheck(booking, old),
        now,
        limits
      );
      if (error != null) {
        booking.addError(error);
        addSavedVersionIfActive(old, stillOccupied);
      } else {
        passedTimeRules.add(booking);
        roomIds.add(booking.Meeting_Room__c);
      }
    }
    if (passedTimeRules.isEmpty()) {
      return;
    }

    Map<Id, Meeting_Room__c> rooms = roomSelector.selectByIdForUpdate(roomIds);
    List<Room_Booking__c> candidates = new List<Room_Booking__c>();
    for (Room_Booking__c booking : passedTimeRules) {
      String error = checkRoomRules(
        booking,
        rooms.get(booking.Meeting_Room__c),
        timeZoneId
      );
      if (error != null) {
        booking.addError(error);
        addSavedVersionIfActive(oldOf(booking, oldMap), stillOccupied);
      } else {
        candidates.add(booking);
      }
    }
    if (candidates.isEmpty()) {
      return;
    }

    Map<Id, List<Room_Booking__c>> savedByRoom = loadSavedActiveBookings(
      candidates,
      bookings,
      stillOccupied
    );
    Map<Id, List<Room_Booking__c>> acceptedByRoom = new Map<Id, List<Room_Booking__c>>();
    for (Room_Booking__c booking : candidates) {
      String error = conflictError(
        booking,
        savedByRoom,
        acceptedByRoom,
        timeZoneId
      );
      if (error != null) {
        booking.addError(error);
        // The rejected update keeps its saved slot: later bookings of the batch must respect it.
        Room_Booking__c old = oldOf(booking, oldMap);
        if (old != null && old.Status__c == STATUS_ACTIVE) {
          addToRoomMap(savedByRoom, old);
        }
      } else {
        addToRoomMap(acceptedByRoom, booking);
      }
    }
  }

  /** REQ-005 (saved bookings) first, then REQ-025 (earlier accepted bookings of the batch). */
  private String conflictError(
    Room_Booking__c booking,
    Map<Id, List<Room_Booking__c>> savedByRoom,
    Map<Id, List<Room_Booking__c>> acceptedByRoom,
    String timeZoneId
  ) {
    Room_Booking__c savedConflict = findOverlap(
      booking,
      savedByRoom.get(booking.Meeting_Room__c)
    );
    if (savedConflict != null) {
      return conflictMessage(
        System.Label.Room_Booking_Room_Conflict,
        savedConflict,
        timeZoneId
      );
    }
    Room_Booking__c batchConflict = findOverlap(
      booking,
      acceptedByRoom.get(booking.Meeting_Room__c)
    );
    if (batchConflict != null) {
      return conflictMessage(
        System.Label.Room_Booking_Batch_Conflict,
        batchConflict,
        timeZoneId
      );
    }
    return null;
  }

  private Boolean hasMissingRequiredFields(Room_Booking__c booking) {
    return booking.Start_Date_Time__c == null ||
      booking.End_Date_Time__c == null ||
      booking.Meeting_Room__c == null ||
      booking.Attendee_Count__c == null;
  }

  private Room_Booking__c oldOf(
    Room_Booking__c booking,
    Map<Id, Room_Booking__c> oldMap
  ) {
    return oldMap == null ? null : oldMap.get(booking.Id);
  }

  /** A rejected update leaves its saved (old) version in place; if it was active, it still occupies its slot. */
  private void addSavedVersionIfActive(
    Room_Booking__c old,
    List<Room_Booking__c> stillOccupied
  ) {
    if (old != null && old.Status__c == STATUS_ACTIVE) {
      stillOccupied.add(old);
    }
  }

  private void addToRoomMap(
    Map<Id, List<Room_Booking__c>> bookingsByRoom,
    Room_Booking__c booking
  ) {
    if (!bookingsByRoom.containsKey(booking.Meeting_Room__c)) {
      bookingsByRoom.put(booking.Meeting_Room__c, new List<Room_Booking__c>());
    }
    bookingsByRoom.get(booking.Meeting_Room__c).add(booking);
  }

  /** REQ-010 / REQ-021: only active bookings that are new, reactivated or had a rule field changed. */
  private Boolean needsValidation(
    Room_Booking__c booking,
    Room_Booking__c old
  ) {
    if (booking.Status__c != STATUS_ACTIVE) {
      return false;
    }
    if (old == null || old.Status__c != STATUS_ACTIVE) {
      return true;
    }
    return booking.Meeting_Room__c != old.Meeting_Room__c ||
      booking.Start_Date_Time__c != old.Start_Date_Time__c ||
      booking.End_Date_Time__c != old.End_Date_Time__c ||
      booking.Attendee_Count__c != old.Attendee_Count__c;
  }

  /** REQ-019: past / advance limits apply on create, reactivation, or when start or end change. */
  private Boolean needsDateWindowCheck(
    Room_Booking__c booking,
    Room_Booking__c old
  ) {
    return old == null ||
      old.Status__c != STATUS_ACTIVE ||
      booking.Start_Date_Time__c != old.Start_Date_Time__c ||
      booking.End_Date_Time__c != old.End_Date_Time__c;
  }

  /** REQ-004, REQ-009, REQ-019 — rules that need no other record. */
  private String checkTimeRules(
    Room_Booking__c booking,
    Boolean checkDateWindow,
    Datetime now,
    BookingLimits limits
  ) {
    Datetime startAt = booking.Start_Date_Time__c;
    Datetime endAt = booking.End_Date_Time__c;
    if (endAt <= startAt) {
      return System.Label.Room_Booking_End_Before_Start;
    }
    Long durationMinutes =
      (endAt.getTime() - startAt.getTime()) / MILLIS_PER_MINUTE;
    if (
      durationMinutes < limits.minMinutes ||
      durationMinutes > limits.maxMinutes
    ) {
      return String.format(
        System.Label.Room_Booking_Invalid_Duration,
        new List<Object>{
          String.valueOf(limits.minMinutes),
          String.valueOf(limits.maxMinutes)
        }
      );
    }
    if (checkDateWindow) {
      if (startAt < now) {
        return System.Label.Room_Booking_Start_In_Past;
      }
      if (startAt > now.addDays(limits.maxAdvanceDays)) {
        return String.format(
          System.Label.Room_Booking_Too_Far_Ahead,
          new List<Object>{ String.valueOf(limits.maxAdvanceDays) }
        );
      }
    }
    return null;
  }

  /** Booking limits (REQ-020), read once per trigger execution. */
  private class BookingLimits {
    final Integer minMinutes = BookingSettings.minDurationMinutes();
    final Integer maxMinutes = BookingSettings.maxDurationMinutes();
    final Integer maxAdvanceDays = BookingSettings.maxAdvanceDays();
  }

  /** REQ-008, REQ-006, REQ-007 — rules that need the room. Times are read in the booker's time zone. */
  private String checkRoomRules(
    Room_Booking__c booking,
    Meeting_Room__c room,
    String timeZoneId
  ) {
    if (room == null || !room.Is_Active__c) {
      return System.Label.Room_Booking_Room_Inactive;
    }
    if (booking.Attendee_Count__c > room.Capacity__c) {
      return String.format(
        System.Label.Room_Booking_Capacity_Exceeded,
        new List<Object>{ String.valueOf(room.Capacity__c.intValue()) }
      );
    }
    if (!isWithinOpeningHours(booking, room, timeZoneId)) {
      return String.format(
        System.Label.Room_Booking_Outside_Hours,
        new List<Object>{
          formatTime(room.Opening_Time__c),
          formatTime(room.Closing_Time__c)
        }
      );
    }
    return null;
  }

  /** Same local day, Monday to Friday, start >= opening and end <= closing (limits inclusive). */
  private Boolean isWithinOpeningHours(
    Room_Booking__c booking,
    Meeting_Room__c room,
    String timeZoneId
  ) {
    if (room.Opening_Time__c == null || room.Closing_Time__c == null) {
      return false;
    }
    Date startDay = Date.valueOf(
      booking.Start_Date_Time__c.format('yyyy-MM-dd', timeZoneId)
    );
    Date endDay = Date.valueOf(
      booking.End_Date_Time__c.format('yyyy-MM-dd', timeZoneId)
    );
    if (startDay != endDay || isoDayOfWeek(startDay) > LAST_WEEKDAY) {
      return false;
    }
    Integer startSeconds = localSecondsOfDay(
      booking.Start_Date_Time__c,
      timeZoneId
    );
    Integer endSeconds = localSecondsOfDay(
      booking.End_Date_Time__c,
      timeZoneId
    );
    return startSeconds >= secondsOfDay(room.Opening_Time__c) &&
      endSeconds <= secondsOfDay(room.Closing_Time__c);
  }

  /**
   * Active bookings already saved for the candidates' rooms and time window. Every record of
   * the current batch is excluded from the query (its saved version may be stale) and the
   * batch records that stay active without changes, plus the saved versions of rejected updates,
   * are added back (`stillOccupied`).
   */
  private Map<Id, List<Room_Booking__c>> loadSavedActiveBookings(
    List<Room_Booking__c> candidates,
    List<Room_Booking__c> batch,
    List<Room_Booking__c> stillOccupied
  ) {
    Set<Id> roomIds = new Set<Id>();
    Datetime windowStart = candidates[0].Start_Date_Time__c;
    Datetime windowEnd = candidates[0].End_Date_Time__c;
    for (Room_Booking__c candidate : candidates) {
      roomIds.add(candidate.Meeting_Room__c);
      if (candidate.Start_Date_Time__c < windowStart) {
        windowStart = candidate.Start_Date_Time__c;
      }
      if (candidate.End_Date_Time__c > windowEnd) {
        windowEnd = candidate.End_Date_Time__c;
      }
    }
    Set<Id> batchIds = new Set<Id>();
    for (Room_Booking__c record : batch) {
      if (record.Id != null) {
        batchIds.add(record.Id);
      }
    }

    List<Room_Booking__c> saved = new List<Room_Booking__c>(stillOccupied);
    saved.addAll(
      bookingSelector.selectActiveOverlapping(
        roomIds,
        windowStart,
        windowEnd,
        batchIds
      )
    );

    Map<Id, List<Room_Booking__c>> savedByRoom = new Map<Id, List<Room_Booking__c>>();
    for (Room_Booking__c booking : saved) {
      if (!savedByRoom.containsKey(booking.Meeting_Room__c)) {
        savedByRoom.put(booking.Meeting_Room__c, new List<Room_Booking__c>());
      }
      savedByRoom.get(booking.Meeting_Room__c).add(booking);
    }
    return savedByRoom;
  }

  /** First booking in `others` whose interval overlaps `booking` (end is exclusive, REQ-005). */
  private Room_Booking__c findOverlap(
    Room_Booking__c booking,
    List<Room_Booking__c> others
  ) {
    if (others == null) {
      return null;
    }
    for (Room_Booking__c other : others) {
      if (
        booking.Start_Date_Time__c < other.End_Date_Time__c &&
        other.Start_Date_Time__c < booking.End_Date_Time__c
      ) {
        return other;
      }
    }
    return null;
  }

  private String conflictMessage(
    String label,
    Room_Booking__c conflict,
    String timeZoneId
  ) {
    return String.format(
      label,
      new List<Object>{
        conflict.Start_Date_Time__c.format('HH:mm', timeZoneId),
        conflict.End_Date_Time__c.format('HH:mm', timeZoneId)
      }
    );
  }

  @TestVisible
  private static Integer isoDayOfWeek(Date day) {
    return Math.mod(KNOWN_MONDAY.daysBetween(day), 7) + 1;
  }

  private static Integer localSecondsOfDay(Datetime value, String timeZoneId) {
    List<String> parts = value.format('HH:mm:ss', timeZoneId).split(':');
    return Integer.valueOf(parts[0]) * 3600 +
      Integer.valueOf(parts[1]) * 60 +
      Integer.valueOf(parts[2]);
  }

  private static Integer secondsOfDay(Time value) {
    return value.hour() * 3600 + value.minute() * 60 + value.second();
  }

  private static String formatTime(Time value) {
    return String.valueOf(value.hour()).leftPad(2, '0') +
      ':' +
      String.valueOf(value.minute()).leftPad(2, '0');
  }
}
