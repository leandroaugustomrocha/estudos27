# Project Context

`estudos27` is Leandro's personal Salesforce study project: a single Developer
Edition org where all Apex, LWC and Flow learning exercises are centralized.
There is no production org and no team — but code must still follow
enterprise-grade Salesforce best practices, because it doubles as practice
for real client work.

# Stack

- Salesforce Platform — Developer Edition org, alias `estudos27`
- Salesforce DX project, `sourceApiVersion` 68.0 (Winter '27)
- Apex (classes + triggers), Lightning Web Components, Aura (legacy only), Flows
- Salesforce CLI (`sf`), Node/npm for tooling
- Jest via `@salesforce/sfdx-lwc-jest` 7, ESLint 9 (`@salesforce/eslint-config-lwc`),
  Prettier 3 + `prettier-plugin-apex`, Husky 9 + lint-staged (pre-commit)

# Commands

```
# Install tooling
npm install

# Lint (LWC/Aura JS)
npm run lint

# Format check / fix
npm run prettier:verify
npm run prettier

# LWC unit tests (Jest)
npm test
npm run test:unit:coverage
npm test -- force-app/main/default/lwc/myComponent   # single component
npm test -- -t "test name"                           # single test by name

# Apex tests in the org (with coverage)
sf apex run test --target-org estudos27 --code-coverage --result-format human --wait 10
sf apex run test --target-org estudos27 --class-names MyClassTest --code-coverage --result-format human --wait 10
sf apex run test --target-org estudos27 --tests MyClassTest.myMethod --result-format human --wait 10

# Validate a deploy without saving (dry run)
sf project deploy start --source-dir force-app --target-org estudos27 --dry-run

# Deploy / retrieve
sf project deploy start --source-dir force-app --target-org estudos27
sf project retrieve start --source-dir force-app --target-org estudos27
```

# File Structure

```
force-app/main/default/
  classes/        Apex classes + test classes (*Test.cls)
  triggers/       One trigger per object, logic-free
  lwc/            Lightning Web Components (+ __tests__/ for Jest)
  aura/           Legacy Aura — do not create new Aura components
  flows/          Flows (created when first Flow is retrieved)
  objects/        Custom objects/fields metadata
  permissionsets/ Access is granted via permission sets, not profiles
config/           Scratch org definition (not used day-to-day)
manifest/         package.xml for targeted retrieve/deploy
scripts/apex/     Anonymous Apex snippets   scripts/soql/  SOQL snippets
agent_docs/       Deeper context for AI agents (see below)
.claude/rules/    Path-scoped conventions (Apex, LWC, Flow)
```

# Workflow Rules

- **Spec first, then code.** Before writing any code: read the relevant existing
  files, then present a short spec (goal, objects/fields, classes/components to
  create or change, test plan, risks). Wait for approval, then implement.
- Only ever target the org alias `estudos27`. Never deploy, retrieve or run
  commands against any other org.
- Never delete metadata (files or in the org) without asking first.
- Every Apex change ships with its test class; run Apex tests before calling a
  task done. Minimum 75% coverage per class, with real assertions.
- After LWC/JS changes run `npm run lint` and `npm test`.
- Run a `--dry-run` deploy before a real deploy.
- Fix bugs test-first: reproduce with a failing test, then fix.
- When editing Apex, LWC or Flows, follow the matching file in `.claude/rules/`
  (`apex.md`, `lwc.md`, `flows.md`).

# Deeper Context (read when relevant)

- Non-negotiable rules for this codebase: `agent_docs/business-rules.md`
- Salesforce security practices: `agent_docs/security.md`
- Engineering standards and quality philosophy: `agent_docs/engineering-standards.md`
- Productivity tools and workflows: `agent_docs/productivity.md`

# Keeping This File Current

This is a living system. If you hit something during real work that should be
a permanent rule — a convention, a security constraint, a mistake worth never
repeating — don't apply it silently: ask whether it should be added, and add
it to the right file (not dumped into this one).

# Response Language

Always respond in Brazilian Portuguese, regardless of the language used in the
prompt. Code, comments and these config files stay in English.
