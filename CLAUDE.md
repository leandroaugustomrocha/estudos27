@AGENTS.md

# Claude Code specifics

- `AGENTS.md` (imported above) is the single source of truth, shared with
  Agentforce Vibes. Put shared rules there, not here.
- Load deeper context on demand: @agent_docs/business-rules.md is always
  relevant; read `agent_docs/security.md` for any `@AuraEnabled`, SOQL,
  DML or sharing work.
- For non-trivial tasks, use Plan Mode to deliver the spec required by the
  "Spec first, then code" workflow rule.
- A `PreToolUse` hook in `.claude/settings.json` blocks `git commit` if lint
  or LWC tests fail — fix the errors, don't bypass the hook.
