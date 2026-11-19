# Business Rules & Non-Negotiables

This is a study project, so there is no business domain yet. These are the
rules the codebase must never violate. Add real domain rules here as study
exercises introduce them (e.g. "an Opportunity can't be Closed Won without
a Contact Role").

## Org safety
- The only valid target org is the alias `estudos27` (Developer Edition).
  Never deploy, retrieve, run tests or execute anonymous Apex against any
  other org, even if one is authenticated in the CLI.
- Never delete metadata — local files or org components — without explicit
  confirmation from the user in the current conversation.

## Code rules (violations are bugs, not style issues)
- **No SOQL or DML inside loops.** Query once into a Map/Set, collect records
  in a List, then do one DML statement.
- **No hardcoded IDs** (record IDs, RecordType IDs, profile/user IDs, org IDs).
  Use `Schema.SObjectType.X.getRecordTypeInfosByDeveloperName()`, queries by
  DeveloperName, Custom Metadata Types or Custom Labels.
- **One trigger per object**, with no logic inside — it only delegates to a
  handler class.
- **All code must be bulk-safe** for 200+ records per transaction.
- **Minimum 75% test coverage per class**, with meaningful `Assert` calls.
  Coverage without assertions does not count.

## Study workflow
- Spec first, then code: read the project, present the spec, wait for
  approval, then implement.
