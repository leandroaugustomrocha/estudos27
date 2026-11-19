---
paths:
  - "force-app/**/flows/**"
---
# Flow Rules

- Flows are built in Flow Builder and retrieved into source
  (`sf project retrieve start --metadata Flow:<ApiName> --target-org estudos27`);
  don't hand-edit large Flow XML.
- Naming: `<Object>_<Trigger>_<Purpose>` for record-triggered flows
  (e.g. `Account_BeforeSave_SetRating`), descriptive labels on every element.
- Use before-save (Fast Field Updates) for same-record updates; after-save
  only when you need related records or actions.
- No Get Records / Create / Update / Delete elements inside loops — collect
  into a collection variable and do one operation after the loop.
- Use entry conditions to limit when the flow runs.
- Pick one automation tool per object/event: don't mix a record-triggered
  flow and an Apex trigger for the same logic.
- Add a Fault path on every data element.
- Cover record-triggered flows with Apex tests (or Flow tests) before deploy.
