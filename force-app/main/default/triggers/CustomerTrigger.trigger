trigger CustomerTrigger on Customer__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after delete,
  after undelete
) {
  new CustomerTriggerHandler().run();
}
