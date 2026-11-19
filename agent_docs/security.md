# Security Considerations (Salesforce, API 68.0)

Even in a Developer Edition study org, write code as if it were going to a
client's production org.

## Sharing and access
- Classes default to `with sharing`. Use `inherited sharing` for utility
  classes called from multiple contexts. `without sharing` only with a
  comment explaining why, isolated in a small, dedicated class.
- Enforce CRUD/FLS in user-facing code:
  - SOQL: `WITH USER_MODE` (preferred over `WITH SECURITY_ENFORCED`).
  - DML: `Database.insert(records, AccessLevel.USER_MODE)` etc., or
    `Security.stripInaccessible()` when you need to drop fields silently.
- Grant access through permission sets (`permissionsets/`), not profiles.

## @AuraEnabled methods are public endpoints
- Any `@AuraEnabled` method can be called directly by any user with access
  to the class. Validate every parameter and enforce user-mode access.
- Use `@AuraEnabled(cacheable=true)` only for read-only methods.
- Throw `AuraHandledException` with a user-safe message; never return stack
  traces or internal details to the client.

## Injection
- Prefer static SOQL with bind variables.
- Dynamic SOQL: use `Database.queryWithBinds()`; never concatenate user
  input. If concatenation is unavoidable, whitelist field/object names and
  use `String.escapeSingleQuotes()`.
- LWC: never build HTML from user input (`innerHTML` / `lwc:dom="manual"`
  with untrusted data).

## Secrets
- No credentials, tokens or endpoints in code or Custom Labels. Use Named
  Credentials + External Credentials for callouts.
- Never commit `.sf/`, `.sfdx/` or auth files (already in `.gitignore` —
  keep it that way).
