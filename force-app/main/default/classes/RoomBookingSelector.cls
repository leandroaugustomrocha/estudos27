/**
 * Queries on Room_Booking__c (spec 001).
 */
public with sharing class RoomBookingSelector {
  /**
   * Active bookings of the given rooms that overlap the window [windowStart, windowEnd).
   * USER_MODE is correct here only because Room_Booking__c sharing is Public Read Only:
   * every user with access sees every booking. If the OWD becomes Private, overlap
   * detection would miss bookings the user cannot see — that change needs a new spec.
   */
  public List<Room_Booking__c> selectActiveOverlapping(
    Set<Id> roomIds,
    Datetime windowStart,
    Datetime windowEnd,
    Set<Id> excludedIds
  ) {
    return [
      SELECT Id, Meeting_Room__c, Start_Date_Time__c, End_Date_Time__c
      FROM Room_Booking__c
      WHERE
        Meeting_Room__c IN :roomIds
        AND Status__c = :RoomBookingService.STATUS_ACTIVE
        AND Start_Date_Time__c < :windowEnd
        AND End_Date_Time__c > :windowStart
        AND Id NOT IN :excludedIds
      WITH USER_MODE
    ];
  }
}
