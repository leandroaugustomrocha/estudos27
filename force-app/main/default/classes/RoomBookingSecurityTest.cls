/**
 * Spec 001: who can see, edit, cancel and delete bookings (REQ-014, 015, 016, 023).
 * DML runs in AccessLevel.USER_MODE so CRUD, FLS and sharing are enforced as in the UI.
 */
@IsTest
private class RoomBookingSecurityTest {
  @TestSetup
  static void setup() {
    RoomBookingTestDataFactory.createPersonaUsers();
    User collaboratorA = RoomBookingTestDataFactory.getUser(
      RoomBookingTestDataFactory.COLLABORATOR_A
    );
    System.runAs(RoomBookingTestDataFactory.getUser(
      RoomBookingTestDataFactory.ROOM_ADMIN
    )) {
      RoomBookingTestDataFactory.createStandardRooms();
    }
    Id blueRoomId = RoomBookingTestDataFactory.getRoom(
        RoomBookingTestDataFactory.BLUE_ROOM
      )
      .Id;
    System.runAs(collaboratorA) {
      Date monday = RoomBookingTestDataFactory.nextWeekday(1);
      insert RoomBookingTestDataFactory.buildBooking(
        blueRoomId,
        RoomBookingTestDataFactory.at(monday, 10, 0),
        RoomBookingTestDataFactory.at(monday, 11, 0),
        5
      );
    }
  }

  private static Room_Booking__c bookingOfA() {
    return [
      SELECT Id, Name, Status__c, OwnerId
      FROM Room_Booking__c
      WITH SYSTEM_MODE
      LIMIT 1
    ];
  }

  private static User userNamed(String lastName) {
    return RoomBookingTestDataFactory.getUser(lastName);
  }

  // AC-018 / REQ-014
  @IsTest
  static void otherCollaboratorCannotEdit_AC018() {
    Room_Booking__c booking = bookingOfA();
    Database.SaveResult editResult;
    Database.SaveResult cancelResult;
    System.runAs(userNamed(RoomBookingTestDataFactory.COLLABORATOR_B)) {
      Test.startTest();
      editResult = Database.update(
        new Room_Booking__c(Id = booking.Id, Name = 'Assunto alterado'),
        false,
        AccessLevel.USER_MODE
      );
      cancelResult = Database.update(
        new Room_Booking__c(Id = booking.Id, Status__c = 'Cancelled'),
        false,
        AccessLevel.USER_MODE
      );
      Test.stopTest();
    }
    Assert.isFalse(
      editResult.isSuccess(),
      'Collaborator B must not edit a booking organized by A'
    );
    Assert.isFalse(
      cancelResult.isSuccess(),
      'Collaborator B must not cancel a booking organized by A'
    );
    Assert.areEqual(
      'Active',
      bookingOfA().Status__c,
      'Booking must remain active'
    );
  }

  // AC-019 / REQ-014
  @IsTest
  static void collaboratorSeesOthersBookings_AC019() {
    List<Room_Booking__c> visible;
    System.runAs(userNamed(RoomBookingTestDataFactory.COLLABORATOR_B)) {
      Test.startTest();
      visible = [SELECT Id FROM Room_Booking__c WITH USER_MODE];
      Test.stopTest();
    }
    Assert.areEqual(
      1,
      visible.size(),
      'Collaborator B must see the booking organized by A'
    );
  }

  // AC-021 / REQ-015
  @IsTest
  static void adminEditsAnyBooking_AC021() {
    Room_Booking__c booking = bookingOfA();
    Database.SaveResult editResult;
    Database.SaveResult cancelResult;
    System.runAs(userNamed(RoomBookingTestDataFactory.ROOM_ADMIN)) {
      Test.startTest();
      editResult = Database.update(
        new Room_Booking__c(Id = booking.Id, Name = 'Ajustado pelo admin'),
        false,
        AccessLevel.USER_MODE
      );
      cancelResult = Database.update(
        new Room_Booking__c(Id = booking.Id, Status__c = 'Cancelled'),
        false,
        AccessLevel.USER_MODE
      );
      Test.stopTest();
    }
    Assert.isTrue(
      editResult.isSuccess(),
      'Room admin must edit any booking: ' + editResult.getErrors()
    );
    Assert.isTrue(
      cancelResult.isSuccess(),
      'Room admin must cancel any booking: ' + cancelResult.getErrors()
    );
    Assert.areEqual(
      'Cancelled',
      bookingOfA().Status__c,
      'Booking should be cancelled by the admin'
    );
  }

  // AC-022 / REQ-016
  @IsTest
  static void userWithoutAccessDenied_AC022() {
    Id blueRoomId = RoomBookingTestDataFactory.getRoom(
        RoomBookingTestDataFactory.BLUE_ROOM
      )
      .Id;
    Boolean denied = false;
    System.runAs(userNamed(RoomBookingTestDataFactory.NO_ACCESS)) {
      Date tuesday = RoomBookingTestDataFactory.nextWeekday(2);
      Room_Booking__c booking = RoomBookingTestDataFactory.buildBooking(
        blueRoomId,
        RoomBookingTestDataFactory.at(tuesday, 10, 0),
        RoomBookingTestDataFactory.at(tuesday, 11, 0),
        5
      );
      Test.startTest();
      try {
        denied = !Database.insert(booking, false, AccessLevel.USER_MODE)
          .isSuccess();
      } catch (SecurityException e) {
        denied = true;
      }
      Test.stopTest();
    }
    Assert.isTrue(
      denied,
      'A user without the permission sets must not create bookings'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Room_Booking__c],
      'No booking should have been created'
    );
  }

  // AC-032 / REQ-023
  @IsTest
  static void organizerDeletesOwnOnly_AC032() {
    Id bookingId = bookingOfA().Id;
    Database.DeleteResult deletedByB;
    Database.DeleteResult deletedByA;
    Test.startTest();
    System.runAs(userNamed(RoomBookingTestDataFactory.COLLABORATOR_B)) {
      deletedByB = Database.delete(bookingId, false, AccessLevel.USER_MODE);
    }
    System.runAs(userNamed(RoomBookingTestDataFactory.COLLABORATOR_A)) {
      deletedByA = Database.delete(bookingId, false, AccessLevel.USER_MODE);
    }
    Test.stopTest();
    Assert.isFalse(
      deletedByB.isSuccess(),
      'Collaborator B must not delete a booking organized by A'
    );
    Assert.isTrue(
      deletedByA.isSuccess(),
      'The organizer must delete own booking: ' + deletedByA.getErrors()
    );
  }

  // AC-033 / REQ-023
  @IsTest
  static void adminDeletesAnyBooking_AC033() {
    Id bookingId = bookingOfA().Id;
    Database.DeleteResult result;
    System.runAs(userNamed(RoomBookingTestDataFactory.ROOM_ADMIN)) {
      Test.startTest();
      result = Database.delete(bookingId, false, AccessLevel.USER_MODE);
      Test.stopTest();
    }
    Assert.isTrue(
      result.isSuccess(),
      'Room admin must delete any booking: ' + result.getErrors()
    );
  }
}
