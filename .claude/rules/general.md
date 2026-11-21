# General Conventions

- Naming: PascalCase for Apex classes (`AccountService`), camelCase for LWC
  folders (`accountList`), API names in English with `__c` suffix for custom
  fields/objects (`Invoice_Status__c`).
- Commit messages: Conventional Commits (`feat:`, `fix:`, `test:`, `refactor:`,
  `docs:`, `chore:`), optionally scoped by area: `feat(apex): ...`.
- Formatting is owned by Prettier (enforced on commit by Husky) — don't
  hand-format or debate style.
- Org language: the `estudos27` org's default language is English (gender
  neutral). Never set `<gender>` on custom objects — deploy fails with
  "Cannot specify a gender for a gender neutral language". Portuguese labels
  (`<label>`, `<pluralLabel>`) are fine; grammatical gender would require
  Translation Workbench metadata instead.
- Scoped rules in this folder: `apex.md`, `lwc.md`, `flows.md`.
