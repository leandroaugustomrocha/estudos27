trigger RoomBookingTrigger on Room_Booking__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after delete,
  after undelete
) {
  new RoomBookingTriggerHandler().run();
}
