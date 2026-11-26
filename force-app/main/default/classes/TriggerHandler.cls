/**
 * Base class for trigger handlers: one trigger per object calls `new XTriggerHandler().run()`
 * and the handler overrides only the events it needs.
 * Handlers can be bypassed by name (data loads, tests) with TriggerHandler.bypass('XTriggerHandler').
 * `inherited sharing`: the concrete handler decides the sharing mode.
 */
public inherited sharing virtual class TriggerHandler {
  private static final Set<String> BYPASSED_HANDLERS = new Set<String>();

  /** Entry point used by triggers; reads the current trigger context. */
  public void run() {
    run(
      Trigger.operationType,
      Trigger.new,
      Trigger.old,
      Trigger.newMap,
      Trigger.oldMap
    );
  }

  /** Dispatches one trigger event. Visible to tests so the routing can be checked without DML. */
  @TestVisible
  private void run(
    System.TriggerOperation operation,
    List<SObject> newRecords,
    List<SObject> oldRecords,
    Map<Id, SObject> newMap,
    Map<Id, SObject> oldMap
  ) {
    if (operation == null || isBypassed(getHandlerName())) {
      return;
    }
    switch on operation {
      when BEFORE_INSERT {
        beforeInsert(newRecords);
      }
      when BEFORE_UPDATE {
        beforeUpdate(newRecords, oldMap);
      }
      when BEFORE_DELETE {
        beforeDelete(oldRecords, oldMap);
      }
      when AFTER_INSERT {
        afterInsert(newRecords, newMap);
      }
      when AFTER_UPDATE {
        afterUpdate(newRecords, oldMap);
      }
      when AFTER_DELETE {
        afterDelete(oldRecords, oldMap);
      }
      when AFTER_UNDELETE {
        afterUndelete(newRecords, newMap);
      }
    }
  }

  public static void bypass(String handlerName) {
    BYPASSED_HANDLERS.add(handlerName);
  }

  public static void clearBypass(String handlerName) {
    BYPASSED_HANDLERS.remove(handlerName);
  }

  public static Boolean isBypassed(String handlerName) {
    return BYPASSED_HANDLERS.contains(handlerName);
  }

  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void beforeInsert(List<SObject> newRecords) {
  }

  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
  }

  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void beforeDelete(
    List<SObject> oldRecords,
    Map<Id, SObject> oldMap
  ) {
  }

  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void afterInsert(
    List<SObject> newRecords,
    Map<Id, SObject> newMap
  ) {
  }

  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
  }

  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void afterDelete(
    List<SObject> oldRecords,
    Map<Id, SObject> oldMap
  ) {
  }

  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void afterUndelete(
    List<SObject> newRecords,
    Map<Id, SObject> newMap
  ) {
  }

  /**
   * Name used by bypass(). Concrete handlers should override it with a constant: the default
   * derives it from String.valueOf(this), which serializes every member of the handler.
   */
  protected virtual String getHandlerName() {
    return String.valueOf(this).substringBefore(':');
  }
}
