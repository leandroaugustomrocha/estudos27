# General Conventions

- Naming: PascalCase for Apex classes (`AccountService`), camelCase for LWC
  folders (`accountList`), API names in English with `__c` suffix for custom
  fields/objects (`Invoice_Status__c`).
- Commit messages: Conventional Commits (`feat:`, `fix:`, `test:`, `refactor:`,
  `docs:`, `chore:`), optionally scoped by area: `feat(apex): ...`.
- Formatting is owned by Prettier (enforced on commit by Husky) — don't
  hand-format or debate style.
- Scoped rules in this folder: `apex.md`, `lwc.md`, `flows.md`.
