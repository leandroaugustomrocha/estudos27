/**
 * Routes Customer__c trigger events to CustomerService (spec 002).
 * Bypass with TriggerHandler.bypass(CustomerTriggerHandler.HANDLER_NAME).
 */
public with sharing class CustomerTriggerHandler extends TriggerHandler {
  public static final String HANDLER_NAME = 'CustomerTriggerHandler';

  private final CustomerService service = new CustomerService();

  protected override String getHandlerName() {
    return HANDLER_NAME;
  }

  protected override void beforeInsert(List<SObject> newRecords) {
    service.beforeSave((List<Customer__c>) newRecords, null);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    service.beforeSave(
      (List<Customer__c>) newRecords,
      (Map<Id, Customer__c>) oldMap
    );
  }

  protected override void afterInsert(
    List<SObject> newRecords,
    Map<Id, SObject> newMap
  ) {
    service.afterSave((List<Customer__c>) newRecords, null);
  }

  protected override void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    service.afterSave(
      (List<Customer__c>) newRecords,
      (Map<Id, Customer__c>) oldMap
    );
  }

  protected override void beforeDelete(
    List<SObject> oldRecords,
    Map<Id, SObject> oldMap
  ) {
    service.deleteDocuments((List<Customer__c>) oldRecords);
  }

  /** Undelete has no before event; Trigger.new is read-only here, addError still works. */
  protected override void afterUndelete(
    List<SObject> newRecords,
    Map<Id, SObject> newMap
  ) {
    service.restoreDocuments((List<Customer__c>) newRecords);
  }
}
