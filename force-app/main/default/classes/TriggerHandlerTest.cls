@IsTest
private class TriggerHandlerTest {
  /** Records which event method was called. */
  private class RecordingHandler extends TriggerHandler {
    public List<String> calls = new List<String>();
    protected override void beforeInsert(List<SObject> newRecords) {
      calls.add('beforeInsert');
    }
    protected override void beforeUpdate(
      List<SObject> newRecords,
      Map<Id, SObject> oldMap
    ) {
      calls.add('beforeUpdate');
    }
    protected override void beforeDelete(
      List<SObject> oldRecords,
      Map<Id, SObject> oldMap
    ) {
      calls.add('beforeDelete');
    }
    protected override void afterInsert(
      List<SObject> newRecords,
      Map<Id, SObject> newMap
    ) {
      calls.add('afterInsert');
    }
    protected override void afterUpdate(
      List<SObject> newRecords,
      Map<Id, SObject> oldMap
    ) {
      calls.add('afterUpdate');
    }
    protected override void afterDelete(
      List<SObject> oldRecords,
      Map<Id, SObject> oldMap
    ) {
      calls.add('afterDelete');
    }
    protected override void afterUndelete(
      List<SObject> newRecords,
      Map<Id, SObject> newMap
    ) {
      calls.add('afterUndelete');
    }
  }

  /** Uses only the base-class defaults. */
  private class EmptyHandler extends TriggerHandler {
  }

  @IsTest
  static void routesEveryOperationToItsMethod() {
    RecordingHandler handler = new RecordingHandler();
    Test.startTest();
    for (System.TriggerOperation operation : System.TriggerOperation.values()) {
      handler.run(operation, null, null, null, null);
    }
    Test.stopTest();
    Assert.areEqual(
      new List<String>{
        'beforeInsert',
        'afterInsert',
        'beforeUpdate',
        'afterUpdate',
        'beforeDelete',
        'afterDelete',
        'afterUndelete'
      },
      handler.calls,
      'Each trigger operation should call exactly its own method, in System.TriggerOperation order'
    );
  }

  @IsTest
  static void baseClassDefaultsDoNothing() {
    EmptyHandler handler = new EmptyHandler();
    Test.startTest();
    for (System.TriggerOperation operation : System.TriggerOperation.values()) {
      handler.run(operation, null, null, null, null);
    }
    handler.run();
    Test.stopTest();
    Assert.isFalse(
      TriggerHandler.isBypassed('TriggerHandlerTest.EmptyHandler'),
      'Nothing should be bypassed'
    );
  }

  @IsTest
  static void bypassSkipsHandler() {
    RecordingHandler handler = new RecordingHandler();
    String handlerName = String.valueOf(handler).substringBefore(':');
    Test.startTest();
    TriggerHandler.bypass(handlerName);
    handler.run(System.TriggerOperation.BEFORE_INSERT, null, null, null, null);
    Boolean bypassedWhileSet = TriggerHandler.isBypassed(handlerName);
    TriggerHandler.clearBypass(handlerName);
    handler.run(System.TriggerOperation.BEFORE_INSERT, null, null, null, null);
    Test.stopTest();
    Assert.isTrue(
      bypassedWhileSet,
      'Handler should report as bypassed after bypass()'
    );
    Assert.areEqual(
      new List<String>{ 'beforeInsert' },
      handler.calls,
      'Only the call made after clearBypass() should run'
    );
  }

  @IsTest
  static void runOutsideTriggerDoesNothing() {
    RecordingHandler handler = new RecordingHandler();
    Test.startTest();
    handler.run();
    Test.stopTest();
    Assert.isTrue(
      handler.calls.isEmpty(),
      'run() outside a trigger must not call any event method'
    );
  }
}
