/**
 * Queries on Meeting_Room__c (spec 001).
 */
public with sharing class MeetingRoomSelector {
  /**
   * Rooms by Id, locked with FOR UPDATE so concurrent bookings of the same room are
   * serialized: the second transaction waits and then sees the first one's booking (REQ-005).
   */
  public Map<Id, Meeting_Room__c> selectByIdForUpdate(Set<Id> roomIds) {
    return new Map<Id, Meeting_Room__c>(
      [
        SELECT
          Id,
          Name,
          Capacity__c,
          Is_Active__c,
          Opening_Time__c,
          Closing_Time__c
        FROM Meeting_Room__c
        WHERE Id IN :roomIds
        WITH USER_MODE
        FOR UPDATE
      ]
    );
  }
}
