/**
 * Spec 001: room rules (validation rules, permissions and delete restriction).
 */
@IsTest
private class MeetingRoomValidationTest {
  @TestSetup
  static void setup() {
    RoomBookingTestDataFactory.createPersonaUsers();
  }

  private static User admin() {
    return RoomBookingTestDataFactory.getUser(
      RoomBookingTestDataFactory.ROOM_ADMIN
    );
  }

  private static String firstError(Database.SaveResult result) {
    return result.getErrors().isEmpty()
      ? null
      : result.getErrors()[0].getMessage();
  }

  // AC-001 / REQ-001
  @IsTest
  static void adminCreatesActiveRoom_AC001() {
    Meeting_Room__c room = new Meeting_Room__c(
      Name = 'Sala Azul',
      Capacity__c = 8,
      Opening_Time__c = Time.newInstance(8, 0, 0, 0),
      Closing_Time__c = Time.newInstance(18, 0, 0, 0)
    );
    Database.SaveResult result;
    System.runAs(admin()) {
      Test.startTest();
      result = Database.insert(room, false, AccessLevel.USER_MODE);
      Test.stopTest();
    }
    Assert.isTrue(
      result.isSuccess(),
      'Admin should create the room, got: ' + firstError(result)
    );
    Meeting_Room__c saved = [
      SELECT Is_Active__c
      FROM Meeting_Room__c
      WHERE Id = :result.getId()
      WITH SYSTEM_MODE
    ];
    Assert.isTrue(saved.Is_Active__c, 'A new room should be active by default');
  }

  // AC-002 / REQ-002
  @IsTest
  static void zeroCapacityRejected_AC002() {
    Meeting_Room__c zeroCapacity = RoomBookingTestDataFactory.buildRoom(
      'Sala Zero',
      0
    );
    Meeting_Room__c blankCapacity = RoomBookingTestDataFactory.buildRoom(
      'Sala Vazia',
      null
    );
    List<Database.SaveResult> results;
    System.runAs(admin()) {
      Test.startTest();
      results = Database.insert(
        new List<Meeting_Room__c>{ zeroCapacity, blankCapacity },
        false,
        AccessLevel.USER_MODE
      );
      Test.stopTest();
    }
    for (Database.SaveResult result : results) {
      Assert.isFalse(
        result.isSuccess(),
        'Room with zero or blank capacity must be rejected'
      );
      Assert.areEqual(
        'A capacidade da sala deve ser maior que zero.',
        firstError(result),
        'REQ-002 message expected'
      );
    }
  }

  // AC-023 / REQ-017
  @IsTest
  static void closingBeforeOpeningRejected_AC023() {
    Meeting_Room__c reversed = RoomBookingTestDataFactory.buildRoom(
      'Sala Invertida',
      8
    );
    reversed.Opening_Time__c = Time.newInstance(18, 0, 0, 0);
    reversed.Closing_Time__c = Time.newInstance(8, 0, 0, 0);
    Meeting_Room__c noClosing = RoomBookingTestDataFactory.buildRoom(
      'Sala Sem Fechamento',
      8
    );
    noClosing.Closing_Time__c = null;
    List<Database.SaveResult> results;
    System.runAs(admin()) {
      Test.startTest();
      results = Database.insert(
        new List<Meeting_Room__c>{ reversed, noClosing },
        false,
        AccessLevel.USER_MODE
      );
      Test.stopTest();
    }
    for (Database.SaveResult result : results) {
      Assert.isFalse(
        result.isSuccess(),
        'Room with closing not after opening must be rejected'
      );
      Assert.areEqual(
        'O horário de fechamento deve ser posterior ao de abertura.',
        firstError(result),
        'REQ-017 message expected'
      );
    }
  }

  // AC-020 / REQ-015
  @IsTest
  static void collaboratorCannotEditRoom_AC020() {
    Meeting_Room__c existing = RoomBookingTestDataFactory.buildRoom(
      'Sala Existente',
      8
    );
    System.runAs(admin()) {
      insert existing;
    }
    User collaborator = RoomBookingTestDataFactory.getUser(
      RoomBookingTestDataFactory.COLLABORATOR_A
    );
    Boolean createDenied = false;
    Boolean updateDenied = false;
    System.runAs(collaborator) {
      Test.startTest();
      try {
        Database.SaveResult created = Database.insert(
          RoomBookingTestDataFactory.buildRoom('Sala Nova', 8),
          false,
          AccessLevel.USER_MODE
        );
        createDenied = !created.isSuccess();
      } catch (SecurityException e) {
        createDenied = true;
      }
      try {
        Database.SaveResult updated = Database.update(
          new Meeting_Room__c(Id = existing.Id, Capacity__c = 20),
          false,
          AccessLevel.USER_MODE
        );
        updateDenied = !updated.isSuccess();
      } catch (SecurityException e) {
        updateDenied = true;
      }
      Test.stopTest();
    }
    Assert.isTrue(createDenied, 'A collaborator must not create rooms');
    Assert.isTrue(updateDenied, 'A collaborator must not edit rooms');
    Assert.areEqual(
      8,
      [
        SELECT Capacity__c
        FROM Meeting_Room__c
        WHERE Id = :existing.Id
        WITH SYSTEM_MODE
      ]
      .Capacity__c,
      'Room capacity must stay unchanged'
    );
  }

  // AC-034 / REQ-024
  @IsTest
  static void roomWithBookingsCannotBeDeleted_AC034() {
    Meeting_Room__c withBooking = RoomBookingTestDataFactory.buildRoom(
      'Sala Com Reserva',
      8
    );
    Meeting_Room__c empty = RoomBookingTestDataFactory.buildRoom(
      'Sala Livre',
      8
    );
    User roomAdmin = admin();
    System.runAs(roomAdmin) {
      insert new List<Meeting_Room__c>{ withBooking, empty };
      Date monday = RoomBookingTestDataFactory.nextWeekday(1);
      Room_Booking__c cancelled = RoomBookingTestDataFactory.buildBooking(
        withBooking.Id,
        RoomBookingTestDataFactory.at(monday, 10, 0),
        RoomBookingTestDataFactory.at(monday, 11, 0),
        4
      );
      cancelled.Status__c = 'Cancelled';
      insert cancelled;
    }
    List<Database.DeleteResult> results;
    System.runAs(roomAdmin) {
      Test.startTest();
      results = Database.delete(
        new List<Id>{ withBooking.Id, empty.Id },
        false,
        AccessLevel.USER_MODE
      );
      Test.stopTest();
    }
    Assert.isFalse(
      results[0].isSuccess(),
      'A room with bookings (even cancelled) must not be deleted'
    );
    Assert.isTrue(
      results[1].isSuccess(),
      'A room without bookings can be deleted by the admin'
    );
  }
}
