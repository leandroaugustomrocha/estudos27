/**
 * Routes Room_Booking__c trigger events to RoomBookingService (spec 001).
 * Bypass with TriggerHandler.bypass('RoomBookingTriggerHandler').
 */
public with sharing class RoomBookingTriggerHandler extends TriggerHandler {
  private final RoomBookingService service = new RoomBookingService();

  protected override void beforeInsert(List<SObject> newRecords) {
    process((List<Room_Booking__c>) newRecords, null);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    process(
      (List<Room_Booking__c>) newRecords,
      (Map<Id, Room_Booking__c>) oldMap
    );
  }

  /**
   * REQ-026: undelete fires no before trigger, so the rules run here. Trigger.new is read-only
   * in after events: only validate (addError rolls back the restore), never stamp fields.
   */
  protected override void afterUndelete(
    List<SObject> newRecords,
    Map<Id, SObject> newMap
  ) {
    service.validate((List<Room_Booking__c>) newRecords, null);
  }

  private void process(
    List<Room_Booking__c> bookings,
    Map<Id, Room_Booking__c> oldMap
  ) {
    service.stampCancellation(bookings, oldMap);
    service.validate(bookings, oldMap);
  }
}
