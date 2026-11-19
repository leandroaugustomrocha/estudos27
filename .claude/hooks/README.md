# Hooks — Real Enforcement (not just instructions in text)

## Why this exists

Every rule written as prose inside CLAUDE.md or the files in `agent_docs/`
is **context**, not **enforcement**. Even written in all caps with
"ALWAYS" or "NEVER," the AI can still skip the rule under context
pressure — it's a strong suggestion, not a hard gate.

Hooks are different: they're real shell commands, triggered automatically
by Claude Code lifecycle events (before a tool runs, after an edit, at
session start). They run **regardless of what the AI decides to do**. It's
the difference between politely asking someone to validate code before
pushing, and having a system that blocks the push if validation fails.

## What this example does

The hook below runs **before** any commit (the `PreToolUse` event,
triggered when the bash tool tries to run `git commit`), executes ESLint and
the LWC Jest tests, and **blocks the commit if anything fails** — the AI gets the
error back and has to fix it before trying again.

## Setup

This project's hook is already active in `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "if grep -q 'git commit'; then npm run lint && npm test || { echo 'Lint or LWC tests failed - fix before committing.' >&2; exit 2; }; fi"
          }
        ]
      }
    ]
  }
}
```

Notes:
- Claude Code passes the tool input as JSON on **stdin**, so `grep` reads it
  directly. Exit code `2` is what blocks the tool call and sends the stderr
  message back to Claude.
- Apex tests are not in the hook: they run in the org and take too long for
  every commit. Run them per the Workflow Rules in `AGENTS.md`.
- Husky + lint-staged (`.husky/pre-commit`) still run Prettier/ESLint/Jest on
  staged files for every commit, including commits made outside Claude Code.

## Adapting to other stacks

The logic is always the same — only the command changes:

| Stack | Example command |
|---|---|
| Node/TypeScript | `npm run lint && npm run typecheck` |
| Python | `ruff check . && mypy .` |
| Go | `golangci-lint run && go vet ./...` |
| Rust | `cargo clippy && cargo check` |

Look up the project's real command (it usually already exists in
`package.json`, a `Makefile`, or similar) instead of assuming.

## This is just the start

This is **one** hook, on the most critical event (pre-commit). The full
hooks system — multiple events (PreToolUse, PostToolUse, SessionStart),
custom slash commands, and subagent orchestration — is out of scope for
this kit. If that's what you need, it's covered in the advanced guide
(upsell).
