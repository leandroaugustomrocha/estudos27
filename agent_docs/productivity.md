# Productivity & Tooling

- **Salesforce CLI (`sf`)** — the org alias is `estudos27`. Useful extras:
  - `sf org open --target-org estudos27` — open the org in the browser
  - `sf apex run --file scripts/apex/<file>.apex --target-org estudos27` —
    run anonymous Apex snippets kept in `scripts/apex/`
  - `sf data query --file scripts/soql/<file>.soql --target-org estudos27` —
    run saved SOQL from `scripts/soql/`
  - `sf apex tail log --target-org estudos27` — stream debug logs while testing
  - `sf project retrieve start --metadata Flow:<ApiName> --target-org estudos27`
    — pull a Flow built in Flow Builder into source control
- **VS Code + Salesforce Extension Pack**, including **Agentforce Vibes**.
  Vibes reads `.vibes/rules/project-context.md`, which points it to
  `AGENTS.md` (single source of truth shared with Claude Code).
- **Husky + lint-staged** run Prettier, ESLint and related Jest tests on
  every commit automatically.
