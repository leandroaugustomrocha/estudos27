/**
 * Spec 001: booking rules enforced by RoomBookingTrigger -> RoomBookingService.
 * Bookings are created by collaborators with AccessLevel.USER_MODE, as in the UI.
 * Dates are always the next weekday at least 2 days ahead, built in the running user's time zone.
 */
@IsTest
private class RoomBookingServiceTest {
  private static final String CONFLICT_PREFIX = 'Esta sala já está reservada das ';
  private static final String OUTSIDE_HOURS = 'Esta sala funciona de segunda a sexta, das 08:00 às 18:00.';

  @TestSetup
  static void setup() {
    RoomBookingTestDataFactory.createPersonaUsers();
    System.runAs(RoomBookingTestDataFactory.getUser(
      RoomBookingTestDataFactory.ROOM_ADMIN
    )) {
      RoomBookingTestDataFactory.createStandardRooms();
    }
  }

  // ---------- helpers ----------

  private static User collaboratorA() {
    return RoomBookingTestDataFactory.getUser(
      RoomBookingTestDataFactory.COLLABORATOR_A
    );
  }

  private static User collaboratorB() {
    return RoomBookingTestDataFactory.getUser(
      RoomBookingTestDataFactory.COLLABORATOR_B
    );
  }

  private static Id roomId(String name) {
    return RoomBookingTestDataFactory.getRoom(name).Id;
  }

  private static Room_Booking__c booking(
    Id room,
    Date day,
    Integer startHour,
    Integer startMinute,
    Integer minutes
  ) {
    Datetime startAt = RoomBookingTestDataFactory.at(
      day,
      startHour,
      startMinute
    );
    return RoomBookingTestDataFactory.buildBooking(
      room,
      startAt,
      startAt.addMinutes(minutes),
      5
    );
  }

  private static Database.SaveResult save(Room_Booking__c record) {
    return record.Id == null
      ? Database.insert(record, false, AccessLevel.USER_MODE)
      : Database.update(record, false, AccessLevel.USER_MODE);
  }

  private static String firstError(Database.SaveResult result) {
    return result.getErrors().isEmpty()
      ? null
      : result.getErrors()[0].getMessage();
  }

  private static void assertSaved(Database.SaveResult result, String context) {
    Assert.isTrue(
      result.isSuccess(),
      context + ' should be saved, got: ' + firstError(result)
    );
  }

  private static void assertRejected(
    Database.SaveResult result,
    String expectedMessage,
    String context
  ) {
    Assert.isFalse(result.isSuccess(), context + ' should be rejected');
    Assert.areEqual(
      expectedMessage,
      firstError(result),
      context + ': unexpected error message'
    );
  }

  private static Date monday() {
    return RoomBookingTestDataFactory.nextWeekday(1);
  }

  // ---------- REQ-003 / REQ-004 ----------

  // AC-003 / REQ-003
  @IsTest
  static void collaboratorBooksFreeSlot_AC003() {
    User collaborator = collaboratorA();
    Database.SaveResult result;
    System.runAs(collaborator) {
      Test.startTest();
      result = save(
        booking(
          roomId(RoomBookingTestDataFactory.BLUE_ROOM),
          monday(),
          10,
          0,
          60
        )
      );
      Test.stopTest();
    }
    assertSaved(result, 'Free slot');
    Room_Booking__c saved = [
      SELECT OwnerId, Status__c
      FROM Room_Booking__c
      WHERE Id = :result.getId()
    ];
    Assert.areEqual(
      collaborator.Id,
      saved.OwnerId,
      'The creator must be the organizer (owner)'
    );
    Assert.areEqual('Active', saved.Status__c, 'A new booking must be active');
  }

  // AC-004 / REQ-004
  @IsTest
  static void endBeforeStartRejected_AC004() {
    Room_Booking__c reversed = booking(
      roomId(RoomBookingTestDataFactory.BLUE_ROOM),
      monday(),
      11,
      0,
      60
    );
    reversed.End_Date_Time__c = reversed.Start_Date_Time__c.addHours(-1);
    Room_Booking__c zeroLength = booking(
      roomId(RoomBookingTestDataFactory.GREEN_ROOM),
      monday(),
      11,
      0,
      0
    );
    Database.SaveResult reversedResult;
    Database.SaveResult zeroResult;
    System.runAs(collaboratorA()) {
      Test.startTest();
      reversedResult = save(reversed);
      zeroResult = save(zeroLength);
      Test.stopTest();
    }
    assertRejected(
      reversedResult,
      'O fim da reserva deve ser posterior ao início.',
      'End before start'
    );
    assertRejected(
      zeroResult,
      'O fim da reserva deve ser posterior ao início.',
      'End equal to start'
    );
  }

  // ---------- REQ-005 overlap with saved bookings ----------

  // AC-005 / REQ-005
  @IsTest
  static void overlappingBookingRejected_AC005() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    System.runAs(collaboratorB()) {
      insert booking(blue, monday(), 10, 0, 60);
    }
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Test.startTest();
      result = save(booking(blue, monday(), 10, 30, 60));
      Test.stopTest();
    }
    assertRejected(
      result,
      CONFLICT_PREFIX + '10:00 às 11:00.',
      'Partial overlap'
    );
  }

  // AC-006 / REQ-005
  @IsTest
  static void sameSlotOtherRoomAllowed_AC006() {
    System.runAs(collaboratorB()) {
      insert booking(
        roomId(RoomBookingTestDataFactory.BLUE_ROOM),
        monday(),
        10,
        0,
        60
      );
    }
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Test.startTest();
      result = save(
        booking(
          roomId(RoomBookingTestDataFactory.GREEN_ROOM),
          monday(),
          10,
          0,
          60
        )
      );
      Test.stopTest();
    }
    assertSaved(result, 'Same slot in another room');
  }

  // AC-007 / REQ-005
  @IsTest
  static void adjacentBookingAllowed_AC007() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    System.runAs(collaboratorB()) {
      insert booking(blue, monday(), 10, 0, 60);
    }
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Test.startTest();
      result = save(booking(blue, monday(), 11, 0, 60));
      Test.stopTest();
    }
    assertSaved(result, 'Adjacent booking (end is exclusive)');
  }

  // AC-007b / REQ-005
  @IsTest
  static void containedBookingRejected_AC007b() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    System.runAs(collaboratorB()) {
      insert booking(blue, monday(), 10, 0, 120);
    }
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Test.startTest();
      result = save(booking(blue, monday(), 10, 30, 30));
      Test.stopTest();
    }
    assertRejected(
      result,
      CONFLICT_PREFIX + '10:00 às 12:00.',
      'Booking contained in another'
    );
  }

  // ---------- REQ-006 / REQ-007 / REQ-008 room rules ----------

  // AC-008 / REQ-006
  @IsTest
  static void overCapacityRejected_AC008() {
    Room_Booking__c crowded = booking(
      roomId(RoomBookingTestDataFactory.BLUE_ROOM),
      monday(),
      10,
      0,
      60
    );
    crowded.Attendee_Count__c = RoomBookingTestDataFactory.ROOM_CAPACITY + 1;
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Test.startTest();
      result = save(crowded);
      Test.stopTest();
    }
    assertRejected(
      result,
      'A sala comporta no máximo 8 pessoas.',
      'Over capacity'
    );
  }

  // AC-009 / REQ-007
  @IsTest
  static void afterClosingRejected_AC009() {
    Date wednesday = RoomBookingTestDataFactory.nextWeekday(3);
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Test.startTest();
      result = save(
        booking(
          roomId(RoomBookingTestDataFactory.BLUE_ROOM),
          wednesday,
          17,
          30,
          60
        )
      );
      Test.stopTest();
    }
    assertRejected(result, OUTSIDE_HOURS, 'Ends after closing');
  }

  // AC-009b / REQ-007
  @IsTest
  static void weekendRejected_AC009b() {
    Date saturday = RoomBookingTestDataFactory.nextWeekday(6);
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Test.startTest();
      result = save(
        booking(
          roomId(RoomBookingTestDataFactory.BLUE_ROOM),
          saturday,
          10,
          0,
          60
        )
      );
      Test.stopTest();
    }
    assertRejected(result, OUTSIDE_HOURS, 'Saturday booking');
  }

  // AC-009d / REQ-007 — opening and closing limits are inclusive
  @IsTest
  static void exactOpeningHoursAllowed_AC009d() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    Database.SaveResult atOpening;
    Database.SaveResult atClosing;
    System.runAs(collaboratorA()) {
      Test.startTest();
      atOpening = save(booking(blue, monday(), 8, 0, 60));
      atClosing = save(booking(blue, monday(), 17, 0, 60));
      Test.stopTest();
    }
    assertSaved(atOpening, 'Booking starting exactly at opening (08:00)');
    assertSaved(atClosing, 'Booking ending exactly at closing (18:00)');
  }

  // AC-031 / REQ-007 + NFR time zone
  @IsTest
  static void openingHoursUseBookerTimeZone_AC031() {
    Room_Booking__c saoPauloBooking;
    Database.SaveResult saoPauloResult;
    Database.SaveResult losAngelesResult;
    Test.startTest();
    System.runAs(collaboratorA()) {
      saoPauloBooking = booking(
        roomId(RoomBookingTestDataFactory.BLUE_ROOM),
        monday(),
        8,
        0,
        60
      );
      saoPauloResult = save(saoPauloBooking);
    }
    System.runAs(RoomBookingTestDataFactory.getUser(
      RoomBookingTestDataFactory.COLLABORATOR_LA
    )) {
      // Same absolute instant, in another room: 08:00 in Sao Paulo is before 08:00 in Los Angeles.
      losAngelesResult = save(
        RoomBookingTestDataFactory.buildBooking(
          roomId(RoomBookingTestDataFactory.GREEN_ROOM),
          saoPauloBooking.Start_Date_Time__c,
          saoPauloBooking.End_Date_Time__c,
          5
        )
      );
    }
    Test.stopTest();
    assertSaved(saoPauloResult, '08:00-09:00 for a Sao Paulo user');
    assertRejected(
      losAngelesResult,
      OUTSIDE_HOURS,
      'Same instant for a Los Angeles user'
    );
  }

  // AC-010 / REQ-008
  @IsTest
  static void inactiveRoomRejected_AC010() {
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Test.startTest();
      result = save(
        booking(
          roomId(RoomBookingTestDataFactory.INACTIVE_ROOM),
          monday(),
          10,
          0,
          60
        )
      );
      Test.stopTest();
    }
    assertRejected(
      result,
      'Esta sala não está disponível para reservas.',
      'Inactive room'
    );
  }

  // ---------- REQ-009 / REQ-019 / REQ-020 limits ----------

  // AC-011 / REQ-009
  @IsTest
  static void durationLimitsEnforced_AC011() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    String expected = 'A reserva deve durar entre 15 e 240 minutos.';
    Database.SaveResult tooShort;
    Database.SaveResult tooLong;
    Database.SaveResult exactMin;
    Database.SaveResult exactMax;
    System.runAs(collaboratorA()) {
      Test.startTest();
      tooShort = save(booking(blue, monday(), 8, 0, 10));
      tooLong = save(booking(blue, monday(), 8, 0, 300));
      exactMin = save(booking(blue, monday(), 8, 0, 15));
      exactMax = save(booking(blue, monday(), 9, 0, 240));
      Test.stopTest();
    }
    assertRejected(tooShort, expected, '10-minute booking');
    assertRejected(tooLong, expected, '5-hour booking');
    assertSaved(exactMin, '15-minute booking');
    assertSaved(exactMax, '4-hour booking');
  }

  // AC-024 / REQ-019
  @IsTest
  static void pastStartRejected_AC024() {
    Datetime startAt = Datetime.now().addHours(-1);
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Test.startTest();
      result = save(
        RoomBookingTestDataFactory.buildBooking(
          roomId(RoomBookingTestDataFactory.BLUE_ROOM),
          startAt,
          startAt.addHours(1),
          5
        )
      );
      Test.stopTest();
    }
    assertRejected(
      result,
      'Não é possível reservar um horário que já passou.',
      'Booking in the past'
    );
  }

  // AC-025 / REQ-019
  @IsTest
  static void tooFarAheadRejected_AC025() {
    Datetime startAt = Datetime.now().addDays(91);
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Test.startTest();
      result = save(
        RoomBookingTestDataFactory.buildBooking(
          roomId(RoomBookingTestDataFactory.BLUE_ROOM),
          startAt,
          startAt.addHours(1),
          5
        )
      );
      Test.stopTest();
    }
    assertRejected(
      result,
      'As reservas podem ser feitas com no máximo 90 dias de antecedência.',
      'Booking 91 days ahead'
    );
  }

  // AC-026 / REQ-019
  @IsTest
  static void subjectEditOnStartedBookingAllowed_AC026() {
    Room_Booking__c started;
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      // Arrange a booking that already started: only possible with the trigger bypassed.
      started = RoomBookingTestDataFactory.buildBooking(
        roomId(RoomBookingTestDataFactory.BLUE_ROOM),
        Datetime.now().addMinutes(-30),
        Datetime.now().addMinutes(30),
        5
      );
      TriggerHandler.bypass(RoomBookingTriggerHandler.HANDLER_NAME);
      try {
        insert started;
      } finally {
        TriggerHandler.clearBypass(RoomBookingTriggerHandler.HANDLER_NAME);
      }

      Test.startTest();
      result = save(
        new Room_Booking__c(Id = started.Id, Name = 'Novo assunto')
      );
      Test.stopTest();
    }
    assertSaved(result, 'Subject change on a started booking');
  }

  // AC-027 / REQ-020
  @IsTest
  static void configurableMaxDuration_AC027() {
    BookingSettings.overrideSetting = new Booking_Setting__mdt(
      Min_Duration_Minutes__c = 15,
      Max_Duration_Minutes__c = 480,
      Max_Advance_Days__c = 90
    );
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Test.startTest();
      result = save(
        booking(
          roomId(RoomBookingTestDataFactory.BLUE_ROOM),
          monday(),
          9,
          0,
          300
        )
      );
      Test.stopTest();
    }
    assertSaved(result, '5-hour booking with max duration set to 480 minutes');
  }

  // ---------- REQ-010 updates ----------

  // AC-012 / REQ-010
  @IsTest
  static void extendWithoutSelfConflict_AC012() {
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Room_Booking__c existing = booking(
        roomId(RoomBookingTestDataFactory.BLUE_ROOM),
        monday(),
        10,
        0,
        60
      );
      insert existing;
      Test.startTest();
      result = save(
        new Room_Booking__c(
          Id = existing.Id,
          End_Date_Time__c = existing.End_Date_Time__c.addMinutes(30)
        )
      );
      Test.stopTest();
    }
    assertSaved(result, 'Extending a booking must not conflict with itself');
  }

  // AC-013 / REQ-010
  @IsTest
  static void extendIntoNextBookingRejected_AC013() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    System.runAs(collaboratorB()) {
      insert booking(blue, monday(), 11, 0, 60);
    }
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Room_Booking__c bookingA = booking(blue, monday(), 10, 0, 60);
      insert bookingA;
      Test.startTest();
      result = save(
        new Room_Booking__c(
          Id = bookingA.Id,
          End_Date_Time__c = bookingA.End_Date_Time__c.addMinutes(30)
        )
      );
      Test.stopTest();
    }
    assertRejected(
      result,
      CONFLICT_PREFIX + '11:00 às 12:00.',
      'Extending into the next booking'
    );
  }

  // ---------- REQ-011 / REQ-021 cancel and reactivate ----------

  // AC-014 / REQ-011
  @IsTest
  static void cancelStampsAndFreesSlot_AC014() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    Room_Booking__c original = booking(blue, monday(), 10, 0, 60);
    Database.SaveResult cancelResult;
    Database.SaveResult newResult;
    System.runAs(collaboratorA()) {
      insert original;
      Test.startTest();
      cancelResult = save(
        new Room_Booking__c(Id = original.Id, Status__c = 'Cancelled')
      );
      newResult = save(booking(blue, monday(), 10, 0, 60));
      Test.stopTest();
    }
    assertSaved(cancelResult, 'Cancellation');
    assertSaved(newResult, 'New booking in the freed slot');
    Room_Booking__c cancelled = [
      SELECT Status__c, Cancelled_At__c
      FROM Room_Booking__c
      WHERE Id = :original.Id
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(
      'Cancelled',
      cancelled.Status__c,
      'Cancelled booking must still exist'
    );
    Assert.isNotNull(
      cancelled.Cancelled_At__c,
      'Cancellation date/time must be recorded'
    );
  }

  // AC-028 / REQ-021
  @IsTest
  static void reactivateWhenFree_AC028() {
    Room_Booking__c original = booking(
      roomId(RoomBookingTestDataFactory.BLUE_ROOM),
      monday(),
      10,
      0,
      60
    );
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      insert original;
      update new Room_Booking__c(Id = original.Id, Status__c = 'Cancelled');
      Test.startTest();
      result = save(
        new Room_Booking__c(Id = original.Id, Status__c = 'Active')
      );
      Test.stopTest();
    }
    assertSaved(result, 'Reactivation of a free slot');
    Room_Booking__c reactivated = [
      SELECT Status__c, Cancelled_At__c
      FROM Room_Booking__c
      WHERE Id = :original.Id
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(
      'Active',
      reactivated.Status__c,
      'Booking must be active again'
    );
    Assert.isNull(
      reactivated.Cancelled_At__c,
      'Cancellation date/time must be cleared on reactivation'
    );
  }

  // AC-029 / REQ-021
  @IsTest
  static void reactivateIntoConflictRejected_AC029() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    Room_Booking__c original = booking(blue, monday(), 10, 0, 60);
    System.runAs(collaboratorA()) {
      insert original;
      update new Room_Booking__c(Id = original.Id, Status__c = 'Cancelled');
    }
    System.runAs(collaboratorB()) {
      insert booking(blue, monday(), 10, 0, 60);
    }
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Test.startTest();
      result = save(
        new Room_Booking__c(Id = original.Id, Status__c = 'Active')
      );
      Test.stopTest();
    }
    assertRejected(
      result,
      CONFLICT_PREFIX + '10:00 às 11:00.',
      'Reactivation into a taken slot'
    );
  }

  // ---------- REQ-012 / REQ-013 / REQ-025 bulk ----------

  // AC-015 / REQ-012
  @IsTest
  static void bulkInsert200Valid_AC015() {
    List<Room_Booking__c> bookings = RoomBookingTestDataFactory.buildNonOverlappingBookings(
      roomId(RoomBookingTestDataFactory.BLUE_ROOM),
      200
    );
    List<Database.SaveResult> results;
    Integer queriesUsed;
    System.runAs(collaboratorA()) {
      Test.startTest();
      results = Database.insert(bookings, false, AccessLevel.USER_MODE);
      queriesUsed = Limits.getQueries();
      Test.stopTest();
    }
    Integer saved = 0;
    for (Database.SaveResult result : results) {
      if (result.isSuccess()) {
        saved++;
      }
    }
    Assert.areEqual(
      200,
      saved,
      'All 200 non-overlapping bookings should be saved'
    );
    Assert.isTrue(
      queriesUsed <= 4,
      'Bulk insert of 200 must stay at a constant query count, used: ' +
      queriesUsed
    );
  }

  // AC-035 / REQ-025
  @IsTest
  static void bulkFirstInBatchWins_AC035() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    List<Room_Booking__c> batch = new List<Room_Booking__c>{
      booking(blue, monday(), 10, 0, 60),
      booking(blue, monday(), 10, 30, 60)
    };
    List<Database.SaveResult> results;
    System.runAs(collaboratorA()) {
      Test.startTest();
      results = Database.insert(batch, false, AccessLevel.USER_MODE);
      Test.stopTest();
    }
    assertSaved(results[0], 'First booking of the batch');
    assertRejected(
      results[1],
      'Esta reserva conflita com outra reserva do mesmo lote das 10:00 às 11:00.',
      'Second, overlapping booking of the batch'
    );
  }

  // AC-036 / REQ-025
  @IsTest
  static void bulkRejectedDoesNotBlockNext_AC036() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    List<Room_Booking__c> batch = new List<Room_Booking__c>{
      booking(blue, monday(), 10, 0, 60),
      booking(blue, monday(), 10, 30, 60),
      booking(blue, monday(), 11, 0, 60)
    };
    List<Database.SaveResult> results;
    System.runAs(collaboratorA()) {
      Test.startTest();
      results = Database.insert(batch, false, AccessLevel.USER_MODE);
      Test.stopTest();
    }
    assertSaved(results[0], 'A (10:00-11:00)');
    assertRejected(
      results[1],
      'Esta reserva conflita com outra reserva do mesmo lote das 10:00 às 11:00.',
      'B (10:30-11:30) overlapping accepted A'
    );
    assertSaved(
      results[2],
      'C (11:00-12:00) must not be blocked by rejected B'
    );
  }

  // AC-037 / REQ-025
  @IsTest
  static void bulkInvalidDoesNotBlockNext_AC037() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    Room_Booking__c crowded = booking(blue, monday(), 10, 0, 60);
    crowded.Attendee_Count__c = 20;
    List<Room_Booking__c> batch = new List<Room_Booking__c>{
      crowded,
      booking(blue, monday(), 10, 0, 60)
    };
    List<Database.SaveResult> results;
    System.runAs(collaboratorA()) {
      Test.startTest();
      results = Database.insert(batch, false, AccessLevel.USER_MODE);
      Test.stopTest();
    }
    assertRejected(
      results[0],
      'A sala comporta no máximo 8 pessoas.',
      'A (20 attendees)'
    );
    assertSaved(results[1], 'B in the same slot, after an invalid A');
  }

  // AC-016b / REQ-025
  @IsTest
  static void bulkAdjacentAllowed_AC016b() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    List<Room_Booking__c> batch = new List<Room_Booking__c>{
      booking(blue, monday(), 10, 0, 60),
      booking(blue, monday(), 11, 0, 60)
    };
    List<Database.SaveResult> results;
    System.runAs(collaboratorA()) {
      Test.startTest();
      results = Database.insert(batch, false, AccessLevel.USER_MODE);
      Test.stopTest();
    }
    assertSaved(results[0], 'First adjacent booking');
    assertSaved(results[1], 'Second adjacent booking');
  }

  // AC-017 / REQ-013
  @IsTest
  static void bulkPartialSuccess_AC017() {
    List<Room_Booking__c> bookings = RoomBookingTestDataFactory.buildNonOverlappingBookings(
      roomId(RoomBookingTestDataFactory.BLUE_ROOM),
      200
    );
    Room_Booking__c invalid = bookings[100];
    invalid.End_Date_Time__c = invalid.Start_Date_Time__c.addMinutes(-30);
    List<Database.SaveResult> results;
    System.runAs(collaboratorA()) {
      Test.startTest();
      results = Database.insert(bookings, false, AccessLevel.USER_MODE);
      Test.stopTest();
    }
    Integer saved = 0;
    for (Database.SaveResult result : results) {
      if (result.isSuccess()) {
        saved++;
      }
    }
    Assert.areEqual(199, saved, 'The 199 valid bookings should be saved');
    assertRejected(
      results[100],
      'O fim da reserva deve ser posterior ao início.',
      'The invalid booking'
    );
  }

  // ---------- Review findings: robustness and missing cases ----------

  private static Integer countSaved(List<Database.SaveResult> results) {
    Integer saved = 0;
    for (Database.SaveResult result : results) {
      if (result.isSuccess()) {
        saved++;
      }
    }
    return saved;
  }

  // REQ-013 — a blank required field in an API/Apex load must not break the other 199 rows
  @IsTest
  static void blankRequiredFieldDoesNotBreakBatch_REQ013() {
    List<Room_Booking__c> bookings = RoomBookingTestDataFactory.buildNonOverlappingBookings(
      roomId(RoomBookingTestDataFactory.BLUE_ROOM),
      200
    );
    bookings[50].End_Date_Time__c = null;
    bookings[60].Meeting_Room__c = null;
    List<Database.SaveResult> results;
    System.runAs(collaboratorA()) {
      Test.startTest();
      results = Database.insert(bookings, false, AccessLevel.USER_MODE);
      Test.stopTest();
    }
    Assert.areEqual(
      198,
      countSaved(results),
      'Only the 2 rows with blank required fields should fail'
    );
    for (Integer index : new List<Integer>{ 50, 60 }) {
      Assert.isFalse(
        results[index].isSuccess(),
        'Row ' + index + ' has a blank required field'
      );
      Assert.isFalse(
        firstError(results[index]).contains('NullPointerException'),
        'Row ' +
          index +
          ' must fail with the platform required-field error, got: ' +
          firstError(results[index])
      );
    }
  }

  // REQ-010 / REQ-012 — bulk update with partial success: a rejected update keeps its saved slot
  @IsTest
  static void bulkUpdateRejectedKeepsSavedSlot_REQ012() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    List<Database.SaveResult> results;
    System.runAs(collaboratorA()) {
      Room_Booking__c x = booking(blue, monday(), 10, 0, 60);
      Room_Booking__c y = booking(blue, monday(), 14, 0, 60);
      Room_Booking__c z = booking(blue, monday(), 16, 0, 60);
      insert new List<Room_Booking__c>{ x, y, z };
      List<Room_Booking__c> updates = new List<Room_Booking__c>{
        new Room_Booking__c(
          Id = x.Id,
          End_Date_Time__c = x.Start_Date_Time__c.addMinutes(-30)
        ),
        new Room_Booking__c(
          Id = y.Id,
          Start_Date_Time__c = x.Start_Date_Time__c,
          End_Date_Time__c = x.End_Date_Time__c
        ),
        new Room_Booking__c(
          Id = z.Id,
          Start_Date_Time__c = y.Start_Date_Time__c,
          End_Date_Time__c = y.End_Date_Time__c
        )
      };
      Test.startTest();
      results = Database.update(updates, false, AccessLevel.USER_MODE);
      Test.stopTest();
    }
    assertRejected(
      results[0],
      'O fim da reserva deve ser posterior ao início.',
      'X with end before start'
    );
    assertRejected(
      results[1],
      CONFLICT_PREFIX + '10:00 às 11:00.',
      'Y moved onto the slot X still holds'
    );
    assertRejected(
      results[2],
      CONFLICT_PREFIX + '14:00 às 15:00.',
      'Z moved onto the slot Y still holds'
    );
  }

  // REQ-010 / REQ-012 — two bookings swapping slots in the same update
  @IsTest
  static void bulkUpdateSwapSlots_REQ012() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    List<Database.SaveResult> results;
    System.runAs(collaboratorA()) {
      Room_Booking__c first = booking(blue, monday(), 10, 0, 60);
      Room_Booking__c second = booking(blue, monday(), 11, 0, 60);
      insert new List<Room_Booking__c>{ first, second };
      Test.startTest();
      results = Database.update(
        new List<Room_Booking__c>{
          new Room_Booking__c(
            Id = first.Id,
            Start_Date_Time__c = second.Start_Date_Time__c,
            End_Date_Time__c = second.End_Date_Time__c
          ),
          new Room_Booking__c(
            Id = second.Id,
            Start_Date_Time__c = first.Start_Date_Time__c,
            End_Date_Time__c = first.End_Date_Time__c
          )
        },
        false,
        AccessLevel.USER_MODE
      );
      Test.stopTest();
    }
    assertSaved(results[0], 'First booking moved to 11:00');
    assertSaved(results[1], 'Second booking moved to 10:00');
  }

  // REQ-010 — changing the room or the number of attendees re-applies the rules
  @IsTest
  static void roomOrAttendeeChangeRevalidates_REQ010() {
    Id green = roomId(RoomBookingTestDataFactory.GREEN_ROOM);
    System.runAs(collaboratorB()) {
      insert booking(green, monday(), 10, 0, 60);
    }
    Database.SaveResult roomChange;
    Database.SaveResult attendeeChange;
    System.runAs(collaboratorA()) {
      Room_Booking__c mine = booking(
        roomId(RoomBookingTestDataFactory.BLUE_ROOM),
        monday(),
        10,
        0,
        60
      );
      insert mine;
      Test.startTest();
      roomChange = save(
        new Room_Booking__c(Id = mine.Id, Meeting_Room__c = green)
      );
      attendeeChange = save(
        new Room_Booking__c(Id = mine.Id, Attendee_Count__c = 9)
      );
      Test.stopTest();
    }
    assertRejected(
      roomChange,
      CONFLICT_PREFIX + '10:00 às 11:00.',
      'Moving to a room taken in that slot'
    );
    assertRejected(
      attendeeChange,
      'A sala comporta no máximo 8 pessoas.',
      'Raising attendees above capacity'
    );
  }

  // REQ-021 — reactivation re-applies REQ-019: a booking that already started cannot be reactivated
  @IsTest
  static void reactivatePastBookingRejected_REQ021() {
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Room_Booking__c started = RoomBookingTestDataFactory.buildBooking(
        roomId(RoomBookingTestDataFactory.BLUE_ROOM),
        Datetime.now().addMinutes(-30),
        Datetime.now().addMinutes(30),
        5
      );
      started.Status__c = 'Cancelled';
      TriggerHandler.bypass(RoomBookingTriggerHandler.HANDLER_NAME);
      try {
        insert started;
      } finally {
        TriggerHandler.clearBypass(RoomBookingTriggerHandler.HANDLER_NAME);
      }
      Test.startTest();
      result = save(new Room_Booking__c(Id = started.Id, Status__c = 'Active'));
      Test.stopTest();
    }
    assertRejected(
      result,
      'Não é possível reservar um horário que já passou.',
      'Reactivating a started booking'
    );
  }

  // REQ-003 — a booking inserted without Status gets the default (Active) and is validated
  @IsTest
  static void insertWithoutStatusDefaultsToActive_REQ003() {
    Database.SaveResult result;
    System.runAs(collaboratorA()) {
      Datetime startAt = RoomBookingTestDataFactory.at(monday(), 10, 0);
      Room_Booking__c withoutStatus = new Room_Booking__c(
        Name = 'Sem situação',
        Meeting_Room__c = roomId(RoomBookingTestDataFactory.BLUE_ROOM),
        Start_Date_Time__c = startAt,
        End_Date_Time__c = startAt.addHours(1),
        Attendee_Count__c = 5
      );
      Test.startTest();
      result = save(withoutStatus);
      Test.stopTest();
    }
    assertSaved(result, 'Booking without Status');
    Assert.areEqual(
      'Active',
      [
        SELECT Status__c
        FROM Room_Booking__c
        WHERE Id = :result.getId()
        WITH SYSTEM_MODE
      ]
      .Status__c,
      'Status must default to Active'
    );
  }

  // REQ-025 / NFR volume — worst case: 200 bookings for the same slot in one batch
  @IsTest
  static void bulkSameSlotWorstCase_REQ025() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    List<Database.SaveResult> results;
    Integer queriesUsed;
    System.runAs(collaboratorA()) {
      List<Room_Booking__c> sameSlot = new List<Room_Booking__c>();
      for (Integer i = 0; i < 200; i++) {
        sameSlot.add(booking(blue, monday(), 10, 0, 60));
      }
      Test.startTest();
      results = Database.insert(sameSlot, false, AccessLevel.USER_MODE);
      queriesUsed = Limits.getQueries();
      Test.stopTest();
    }
    Assert.areEqual(
      1,
      countSaved(results),
      'Only the first booking of the batch should be saved'
    );
    assertSaved(results[0], 'First booking of the batch');
    assertRejected(
      results[199],
      'Esta reserva conflita com outra reserva do mesmo lote das 10:00 às 11:00.',
      'Last booking of the batch'
    );
    Assert.isTrue(
      queriesUsed <= 4,
      'Query count must stay constant, used: ' + queriesUsed
    );
  }

  // ---------- REQ-026 restore from the Recycle Bin ----------

  // AC-038 / REQ-026
  @IsTest
  static void restoreIntoTakenSlotRejected_AC038() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    Room_Booking__c mine;
    System.runAs(collaboratorA()) {
      mine = booking(blue, monday(), 10, 0, 60);
      insert mine;
      delete mine;
    }
    System.runAs(collaboratorB()) {
      insert booking(blue, monday(), 10, 0, 60);
    }
    Database.UndeleteResult result;
    System.runAs(collaboratorA()) {
      Test.startTest();
      result = Database.undelete(mine.Id, false);
      Test.stopTest();
    }
    Assert.isFalse(
      result.isSuccess(),
      'Restoring into a taken slot must be denied'
    );
    Assert.areEqual(
      CONFLICT_PREFIX + '10:00 às 11:00.',
      result.getErrors()[0].getMessage(),
      'REQ-005 message expected on restore'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Room_Booking__c
        WHERE Id = :mine.Id
        WITH SYSTEM_MODE
      ],
      'The booking must stay deleted'
    );
  }

  // AC-039 / REQ-026
  @IsTest
  static void restoreCancelledBookingAllowed_AC039() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    Room_Booking__c mine;
    System.runAs(collaboratorA()) {
      mine = booking(blue, monday(), 10, 0, 60);
      insert mine;
      update new Room_Booking__c(Id = mine.Id, Status__c = 'Cancelled');
      delete mine;
    }
    System.runAs(collaboratorB()) {
      insert booking(blue, monday(), 10, 0, 60);
    }
    Database.UndeleteResult result;
    System.runAs(collaboratorA()) {
      Test.startTest();
      result = Database.undelete(mine.Id, false);
      Test.stopTest();
    }
    Assert.isTrue(
      result.isSuccess(),
      'A cancelled booking must be restored without checks: ' +
      result.getErrors()
    );
    Assert.areEqual(
      'Cancelled',
      [
        SELECT Status__c
        FROM Room_Booking__c
        WHERE Id = :mine.Id
        WITH SYSTEM_MODE
      ]
      .Status__c,
      'Restored booking stays cancelled'
    );
  }

  // REQ-012 / REQ-013 — an update that blanks a required field fails, so its saved slot stays taken
  @IsTest
  static void bulkUpdateBlankFieldKeepsSavedSlot_REQ012() {
    Id blue = roomId(RoomBookingTestDataFactory.BLUE_ROOM);
    List<Database.SaveResult> results;
    System.runAs(collaboratorA()) {
      Room_Booking__c x = booking(blue, monday(), 10, 0, 60);
      Room_Booking__c y = booking(blue, monday(), 14, 0, 60);
      insert new List<Room_Booking__c>{ x, y };
      List<Room_Booking__c> updates = new List<Room_Booking__c>{
        new Room_Booking__c(Id = x.Id, End_Date_Time__c = null),
        new Room_Booking__c(
          Id = y.Id,
          Start_Date_Time__c = x.Start_Date_Time__c,
          End_Date_Time__c = x.End_Date_Time__c
        )
      };
      Test.startTest();
      results = Database.update(updates, false, AccessLevel.USER_MODE);
      Test.stopTest();
    }
    Assert.isFalse(results[0].isSuccess(), 'X with a blank End must fail');
    assertRejected(
      results[1],
      CONFLICT_PREFIX + '10:00 às 11:00.',
      'Y moved onto the slot X still holds'
    );
  }
}
