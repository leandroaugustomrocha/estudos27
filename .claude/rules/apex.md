---
paths:
  - "force-app/**/classes/**"
  - "force-app/**/triggers/**"
---
# Apex Rules

## Structure
- One trigger per object: `<Object>Trigger` (e.g. `AccountTrigger`), handling
  all events, with zero logic — it only calls `<Object>TriggerHandler`.
- Handler routes by `Trigger.operationType` to small methods
  (`beforeInsert(List<SObject>)`, `afterUpdate(Map<Id,SObject>, Map<Id,SObject>)`).
- Business logic lives in service classes (`<Domain>Service`); queries in
  selector classes (`<Object>Selector`) once a query is reused.
- Add a bypass mechanism (e.g. static flag or Custom Permission) in the
  handler so data loads and tests can disable trigger logic.

## Code
- Bulkify everything: no SOQL/DML in loops; use `Set<Id>` + `Map<Id, SObject>`.
- `with sharing` by default; `WITH USER_MODE` in SOQL; `AccessLevel.USER_MODE`
  in `Database` DML for user-facing code (see `agent_docs/security.md`).
- No hardcoded IDs or magic strings — Custom Metadata, Custom Labels, or
  `getRecordTypeInfosByDeveloperName()`.
- Async: prefer Queueable over `@future`; Batch only for large volumes.
- Catch specific exceptions; never swallow an exception silently.

## Tests
- Test class per class: `<ClassName>Test`, annotated `@IsTest`.
- Data in `@TestSetup` or a `TestDataFactory` class — never `SeeAllData=true`.
- Wrap the call under test in `Test.startTest()` / `Test.stopTest()`.
- Use the `Assert` class (`Assert.areEqual`, `Assert.isTrue`) with a message.
- Cover bulk (200 records), positive, negative and permission cases
  (`System.runAs`). Minimum 75% per class; coverage without assertions
  doesn't count.
