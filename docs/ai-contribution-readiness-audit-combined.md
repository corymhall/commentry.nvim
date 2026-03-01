# AI Contribution Readiness Audit (Combined)

## Target
- Repo: `commentry.nvim` (`/Users/chall/gt/commentry/crew/fiddler`)
- Language/stack: Lua (Neovim plugin), `mini.test`, `mise`, GitHub Actions
- Audit date: 2026-02-28
- Combined from:
  - `docs/ai-contribution-readiness-audit.md`
  - `docs/ai-contribution-readiness-audit-2026-02-28.md`

---

## Part 1: Diagnostic Summary

### Comparison: where both reports agree
- `AGENTS.md` exists but is stale/incomplete as an AI instruction contract.
- `mise.toml` provides a solid command surface and CI mostly matches it.
- CI currently runs lint/test/health.
- PR template is missing.
- Version guidance is inconsistent (`README` says `0.10+`, AGENTS still references `0.9+`).

### Comparison: key conflicts and synthesis decisions
1. **Docs workflow severity**
   - Conflict: one report treated docs as mostly a workflow gap; the other found an immediate script failure.
   - Decision: treat as **P0 fix** because `./scripts/docs` currently fails with `bad interpreter: /bin/env`.
2. **Need for CONTRIBUTING.md**
   - Conflict: one report recommends adding it; one says redundant for repo size.
   - Decision: mark as **optional, lower priority**. Keep AGENTS + PR template as required core controls.
3. **CI improvement focus**
   - Conflict: one prioritizes docs job, the other format-drift guard.
   - Decision: include **both** in combined CI recommendation because both are low-cost and high-signal.

### What exists

| Artifact | Status | Notes |
|---|---|---|
| AGENTS.md / instruction contract | Partial | Present but stale sections and missing explicit guardrails/escalation. |
| Command surface (`mise.toml`) | Strong | `format`, `lint`, `test`, `health`, `ci`, `docs` tasks are defined. |
| CI workflow | Good, incomplete | Runs lint/test/health; does not run docs task; no explicit format-drift gate. |
| PR template | Missing | No default PR template file present. |
| CONTRIBUTING.md | Missing | Optional for this repo size; useful but not required for first pass. |
| Architecture clarity | Partial | README + AGENTS + module/test naming are decent, but AGENTS “start here” can be much sharper. |
| Verification loop | Good | `./scripts/test`, `mise run lint`, `mise run health` execute successfully. |

### Repo-specific mismatches (verified)
1. `scripts/docs` has `#!/bin/env bash` and fails on this environment.
2. `AGENTS.md` references docs generation from `tests/readme.lua`, but that file does not exist.
3. `lua/commentry/docs.lua` is a stub, so “regenerate docs” language is currently misleading.
4. Neovim version guidance differs between files (`0.10+` vs `0.9+`).

### What this repo does well
- Fast, executable verification loop.
- Strong test breadth across core modules.
- CI/local command parity is already close.

### Top 3 gaps (ranked)
1. Broken/ambiguous docs path (failing script + stub generator + stale docs claims).
2. Stale AGENTS contract (missing guardrails, escalation, and consistent command/version truth).
3. Missing PR template requiring validation evidence and risk disclosure.

---

## Part 2: Implementation Packet

### Change 1: `scripts/docs`
**Action:** edit  
**Why:** Immediate fix for broken docs command.

```bash
#!/usr/bin/env bash

nvim -u tests/minit.lua -l lua/commentry/docs.lua
```

**Verify:** `./scripts/docs`  
**Expected:** No interpreter error; command runs (stub warning is acceptable).

---

### Change 2: `AGENTS.md`
**Action:** edit (rewrite sections for instruction contract quality)  
**Why:** Establishes concrete AI safety/verification contract and removes stale guidance.

```markdown
# Agent Instructions

## What this repo is
commentry.nvim — Neovim plugin for code review workflows on AI-generated changes.
Lua, Neovim 0.10+, diffview.nvim dependency, mini.test test suite, mise task runner.

## Start here
- `plugin/commentry.lua` — plugin entrypoint and command registration
- `lua/commentry/init.lua` — setup API
- `lua/commentry/config.lua` — option defaults/validation
- `lua/commentry/commands.lua` — command handlers
- `lua/commentry/comments.lua` — comment lifecycle + rendering
- `lua/commentry/diffview.lua` — diffview integration
- `lua/commentry/store.lua` — persistent draft store
- `lua/commentry/codex/` — payload/send/orchestration
- `lua/commentry/health.lua` — health checks
- `tests/` — mini.test specs
- `mise.toml` — canonical tasks

## Command canon
- Format: `mise run format`
- Lint: `mise run lint`
- Test: `mise run test`
- Health: `mise run health`
- CI-equivalent local check: `mise run ci`
- Docs command: `mise run docs` (currently executes a stub generator)

## Key invariants
- Neovim >= 0.10 support floor.
- `:Commentry` remains the user-facing command entrypoint.
- Store schema/context identity changes must be backward-compatible or explicitly migrated.
- Behavior changes require tests.

## Forbidden actions
- No destructive git operations without explicit approval.
- No fabricated test/lint/health claims.
- No unrelated refactors in scoped changes.
- No silent schema-breaking persistence changes.

## Escalate immediately if
- Requirements/docs/implementation conflict.
- Store schema or context identity changes are required.
- Failing tests persist after two focused attempts.
- A new runtime dependency is needed.

## If you change...
- Runtime Lua files: run `mise run format && mise run lint && mise run test`
- `health.lua`: also run `mise run health`
- User-visible behavior: update `README.md` and `doc/commentry.txt`

## Current docs status
- `lua/commentry/docs.lua` is currently a stub.
- Do not claim docs are auto-regenerated until generator behavior is implemented.
```

**Verify:** `rg -n "Command canon|Forbidden actions|Escalate immediately if|Current docs status" AGENTS.md`  
**Expected:** All sections present.

---

### Change 3: `.github/pull_request_template.md`
**Action:** create  
**Why:** Enforces evidence/risk expectations for AI-assisted contributions.

```markdown
## Summary
<!-- What changed and why. -->

## Validation
- [ ] `mise run format` (no diff)
- [ ] `mise run lint`
- [ ] `mise run test`
- [ ] `mise run health` (when applicable)

### Command Output
<!-- Paste key output lines. -->

## Risk
<!-- Potential regressions / blast radius. -->

## Backwards Compatibility
<!-- Any impact to config/store behavior? -->

## Rollback
<!-- How to revert safely. -->
```

**Verify:** `test -f .github/pull_request_template.md`  
**Expected:** Template exists and is used for new PRs.

---

### Change 4: `.github/workflows/ci.yml`
**Action:** edit  
**Why:** Adds explicit checks for docs command viability and formatting drift.

```diff
 jobs:
   lint:
     runs-on: ubuntu-latest
     steps:
       - uses: actions/checkout@v4
       - uses: jdx/mise-action@v3
+      - name: Format check
+        run: |
+          mise run format
+          git diff --exit-code || {
+            echo "::error::Formatting drift detected. Run 'mise run format' and commit."
+            exit 1
+          }
       - name: Run lint tasks
         run: mise run lint
@@
       - name: Run checkhealth
         run: mise run health
+
+  docs:
+    runs-on: ubuntu-latest
+    steps:
+      - uses: actions/checkout@v4
+      - uses: jdx/mise-action@v3
+      - name: Run docs command
+        run: mise run docs
```

**Verify:** `rg -n "Format check|docs:|Run docs command|mise run docs" .github/workflows/ci.yml`  
**Expected:** Lint job has format drift guard; docs job exists.

---

### Change 5 (optional): `CONTRIBUTING.md`
**Action:** create (optional)  
**Why:** Useful contributor ergonomics, but lower priority than the four changes above.

```markdown
# Contributing to commentry.nvim

## Workflow
1. Read `AGENTS.md` before editing.
2. Keep changes scoped.
3. Add/update tests for behavior changes.
4. Run validation commands.
5. Update docs for user-visible behavior.

## Validation
- `mise run format`
- `mise run lint`
- `mise run test`
- `mise run health` (as needed)

## AI-assisted contributions
- Do not claim checks passed unless they were run.
- Include command evidence in PR description.
```

**Verify:** `test -f CONTRIBUTING.md`  
**Expected:** Contributor guidance available at repo root.

---

## Recommended execution order
1. Fix `scripts/docs`.
2. Update `AGENTS.md`.
3. Add PR template.
4. Tighten CI (format + docs job).
5. Optionally add `CONTRIBUTING.md`.
