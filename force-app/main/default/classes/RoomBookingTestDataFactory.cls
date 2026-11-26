/**
 * Test data for spec 001 (meeting room booking).
 * Personas are Minimum Access users whose only access comes from the spec permission sets.
 * Named apart from the org TestDataFactory (another app) to avoid overwriting it.
 */
@IsTest
public class RoomBookingTestDataFactory {
  public static final String COLLABORATOR_A = 'RoomBookingCollabA';
  public static final String COLLABORATOR_B = 'RoomBookingCollabB';
  public static final String COLLABORATOR_LA = 'RoomBookingCollabLA';
  public static final String ROOM_ADMIN = 'RoomBookingAdmin';
  public static final String NO_ACCESS = 'RoomBookingNoAccess';

  public static final String SAO_PAULO = 'America/Sao_Paulo';
  public static final String LOS_ANGELES = 'America/Los_Angeles';

  public static final String BLUE_ROOM = 'Sala Azul';
  public static final String GREEN_ROOM = 'Sala Verde';
  public static final String INACTIVE_ROOM = 'Sala Inativa';
  public static final Integer ROOM_CAPACITY = 8;

  public static final String USER_PERMISSION_SET = 'Meeting_Room_User';
  public static final String ADMIN_PERMISSION_SET = 'Meeting_Room_Admin';

  /** Least-privilege profile; its name is not translated in localized orgs. */
  private static final String MINIMUM_ACCESS_PROFILE = 'Minimum Access - Salesforce';
  /** 1900-01-01 was a Monday; used to compute the ISO day of week of any Date. */
  private static final Date KNOWN_MONDAY = Date.newInstance(1900, 1, 1);

  /** Setup DML: call before any data DML, then create data inside System.runAs. */
  public static void createPersonaUsers() {
    Id profileId = [
      SELECT Id
      FROM Profile
      WHERE Name = :MINIMUM_ACCESS_PROFILE
      LIMIT 1
    ]
    .Id;
    Map<String, User> usersByLastName = new Map<String, User>{
      COLLABORATOR_A => buildUser(COLLABORATOR_A, SAO_PAULO, profileId),
      COLLABORATOR_B => buildUser(COLLABORATOR_B, SAO_PAULO, profileId),
      COLLABORATOR_LA => buildUser(COLLABORATOR_LA, LOS_ANGELES, profileId),
      ROOM_ADMIN => buildUser(ROOM_ADMIN, SAO_PAULO, profileId),
      NO_ACCESS => buildUser(NO_ACCESS, SAO_PAULO, profileId)
    };
    insert usersByLastName.values();

    Map<String, Id> permissionSetIds = new Map<String, Id>();
    for (PermissionSet permissionSet : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE Name IN (:USER_PERMISSION_SET, :ADMIN_PERMISSION_SET)
    ]) {
      permissionSetIds.put(permissionSet.Name, permissionSet.Id);
    }
    Id userPermissionSetId = permissionSetIds.get(USER_PERMISSION_SET);
    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = usersByLastName.get(COLLABORATOR_A).Id,
        PermissionSetId = userPermissionSetId
      ),
      new PermissionSetAssignment(
        AssigneeId = usersByLastName.get(COLLABORATOR_B).Id,
        PermissionSetId = userPermissionSetId
      ),
      new PermissionSetAssignment(
        AssigneeId = usersByLastName.get(COLLABORATOR_LA).Id,
        PermissionSetId = userPermissionSetId
      ),
      new PermissionSetAssignment(
        AssigneeId = usersByLastName.get(ROOM_ADMIN).Id,
        PermissionSetId = permissionSetIds.get(ADMIN_PERMISSION_SET)
      )
    };
  }

  /** Blue and Green rooms (active) plus one inactive room, 08:00-18:00, capacity 8. */
  public static void createStandardRooms() {
    Meeting_Room__c inactiveRoom = buildRoom(INACTIVE_ROOM, ROOM_CAPACITY);
    inactiveRoom.Is_Active__c = false;
    insert new List<Meeting_Room__c>{
      buildRoom(BLUE_ROOM, ROOM_CAPACITY),
      buildRoom(GREEN_ROOM, ROOM_CAPACITY),
      inactiveRoom
    };
  }

  public static User getUser(String lastName) {
    return [
      SELECT Id, TimeZoneSidKey
      FROM User
      WHERE LastName = :lastName
      LIMIT 1
    ];
  }

  /** Test-side lookup: SYSTEM_MODE because the user running the tests has no FLS on the new fields. */
  public static Meeting_Room__c getRoom(String name) {
    return [
      SELECT
        Id,
        Name,
        Capacity__c,
        Is_Active__c,
        Opening_Time__c,
        Closing_Time__c
      FROM Meeting_Room__c
      WHERE Name = :name
      WITH SYSTEM_MODE
      LIMIT 1
    ];
  }

  public static Meeting_Room__c buildRoom(String name, Integer capacity) {
    return new Meeting_Room__c(
      Name = name,
      Capacity__c = capacity,
      Is_Active__c = true,
      Opening_Time__c = Time.newInstance(8, 0, 0, 0),
      Closing_Time__c = Time.newInstance(18, 0, 0, 0)
    );
  }

  public static Room_Booking__c buildBooking(
    Id roomId,
    Datetime startAt,
    Datetime endAt,
    Integer attendees
  ) {
    return new Room_Booking__c(
      Name = 'Reunião de teste',
      Meeting_Room__c = roomId,
      Start_Date_Time__c = startAt,
      End_Date_Time__c = endAt,
      Attendee_Count__c = attendees,
      Status__c = 'Active'
    );
  }

  /**
   * `count` bookings of 30 minutes, back to back from 08:00 to 18:00 (20 per day),
   * on consecutive weekdays starting at the next Monday at least 2 days ahead.
   */
  public static List<Room_Booking__c> buildNonOverlappingBookings(
    Id roomId,
    Integer count
  ) {
    List<Room_Booking__c> bookings = new List<Room_Booking__c>();
    Date day = nextWeekday(1);
    Integer slotsPerDay = 20;
    while (bookings.size() < count) {
      if (isoDayOfWeek(day) <= 5) {
        for (
          Integer slot = 0;
          slot < slotsPerDay &&
          bookings.size() < count;
          slot++
        ) {
          Datetime startAt = at(day, 8, 0).addMinutes(slot * 30);
          bookings.add(
            buildBooking(roomId, startAt, startAt.addMinutes(30), 5)
          );
        }
      }
      day = day.addDays(1);
    }
    return bookings;
  }

  /** Next date (at least 2 days from today in Sao Paulo) on the ISO day 1=Mon..7=Sun. */
  public static Date nextWeekday(Integer isoDay) {
    Date todayInSaoPaulo = Date.valueOf(
      Datetime.now().format('yyyy-MM-dd', SAO_PAULO)
    );
    Date day = todayInSaoPaulo.addDays(2);
    while (isoDayOfWeek(day) != isoDay) {
      day = day.addDays(1);
    }
    return day;
  }

  /**
   * Sao Paulo wall-clock date time (the time zone of the collaborator personas), independent of
   * the time zone of the user running the tests. Sao Paulo has no daylight saving time.
   */
  public static Datetime at(Date day, Integer hour, Integer minute) {
    Datetime asGmt = Datetime.newInstanceGmt(
      day,
      Time.newInstance(hour, minute, 0, 0)
    );
    Integer offsetMillis = TimeZone.getTimeZone(SAO_PAULO).getOffset(asGmt);
    return asGmt.addSeconds(-offsetMillis / 1000);
  }

  public static Integer isoDayOfWeek(Date day) {
    return Math.mod(KNOWN_MONDAY.daysBetween(day), 7) + 1;
  }

  private static User buildUser(
    String lastName,
    String timeZone,
    Id profileId
  ) {
    String uniqueKey = String.valueOf(Crypto.getRandomInteger())
      .replace('-', '');
    return new User(
      LastName = lastName,
      Alias = lastName.right(8),
      Email = lastName.toLowerCase() + '@example.com',
      Username = lastName.toLowerCase() + '.' + uniqueKey + '@example.com',
      ProfileId = profileId,
      TimeZoneSidKey = timeZone,
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
  }
}
