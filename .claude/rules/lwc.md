---
paths:
  - "force-app/**/lwc/**"
---
# LWC Rules

- New UI is always LWC — never create new Aura components.
- Prefer Lightning Data Service (`lightning-record-form`, `getRecord`,
  `updateRecord`) and `lightning/graphql` before writing Apex. Use Apex only
  when LDS can't do it.
- Apex calls: `@wire` for reactive reads (`cacheable=true`), imperative calls
  for writes; call `refreshApex` / `notifyRecordUpdateAvailable` after writes.
- Always handle errors: show a toast (`ShowToastEvent`) with a user-safe
  message, never a raw stack trace.
- Use Salesforce Lightning Design System (SLDS) classes and base components
  before custom CSS. No hardcoded labels — use Custom Labels for user text.
- Component communication: `@api` props down, `CustomEvent` up, Lightning
  Message Service across the page.
- Every component gets Jest tests in `__tests__/<component>.test.js`,
  mocking `@wire` adapters and Apex imports.
- Keep `apiVersion` in `.js-meta.xml` aligned with `sourceApiVersion` (68.0).
