# AI Contribution Readiness Audit

## Target
- Repo: `commentry.nvim` (`/Users/chall/gt/commentry/crew/fiddler`)
- Language/stack: Lua (Neovim plugin), `mini.test`, `mise`, GitHub Actions
- Audit date: 2026-02-28

---

## Part 1: Diagnostic Summary

### What exists

| Artifact | Status | Notes |
|---|---|---|
| AGENTS.md / instruction contract | Partial | Exists, but missing explicit forbidden actions/escalation, and contains stale docs guidance. |
| Makefile / justfile / command surface | Good (via `mise.toml`) | No Makefile/justfile, but `mise` tasks are clear and CI uses them. |
| CI workflow | Good | `.github/workflows/ci.yml` runs lint/test/health; no docs/drift check. |
| PR template | Missing | No `.github/pull_request_template.md` found. |
| CONTRIBUTING.md | Missing | No contributor workflow file found. |
| Architecture / module docs | Partial | README + AGENTS + plans exist; no concise architecture map doc. |
| Test commands (fast + full) | Good enough | `./scripts/test`, `mise run lint`, `mise run health` all execute successfully. |

### Concrete mismatches / surprises (repo-specific)
1. `./scripts/docs` is broken right now (`bad interpreter: /bin/env`) because `scripts/docs` uses `#!/bin/env bash` instead of `/usr/bin/env`.
2. `AGENTS.md` says docs are regenerated from `tests/readme.lua`, but that file does not exist.
3. README says “Generate docs: `./scripts/docs`”, but docs generator implementation (`lua/commentry/docs.lua`) is currently a stub that only warns.
4. Version guidance conflicts: README says Neovim `0.10+`, AGENTS “Active Technologies” says Neovim `0.9+`.

### What this repo does well
- Local verification loop is fast and real (`test`, `lint`, `health` all executable).
- CI already aligns with local `mise` tasks.
- Test coverage breadth is strong for a Neovim plugin scaffold.

### Top 3 gaps (ranked)
1. Broken/ambiguous docs workflow (script failure + stale guidance) makes AI edits drift and causes false claims about docs updates.
2. Instruction contract lacks concrete safety rails (forbidden actions + escalation triggers), increasing unsafe or low-signal AI edits.
3. Missing CONTRIBUTING + PR template means no enforced validation evidence in AI-generated PRs.

---

## Part 2: Implementation Packet

### Change 1: `scripts/docs`
**Action:** edit  
**Why:** Fixes gap #1 by making the documented docs command actually runnable.

```bash
#!/usr/bin/env bash

nvim -u tests/minit.lua -l lua/commentry/docs.lua
```

**Verify:** `./scripts/docs`  
**Expected:** Command runs without `bad interpreter` error (may show stub warning until docs generator is implemented).

---

### Change 2: `AGENTS.md`
**Action:** edit  
**Why:** Fixes gap #2 by turning AGENTS into a usable AI instruction contract with real safety rails and accurate command/docs behavior.

```markdown
# Agent Cheat Sheet

This repository contains `commentry.nvim`, a Neovim plugin scaffolded from `folke/sidekick.nvim`.
The core structure, scripts, and tests are copied from that repo as a starting point.

## Start Here

- `lua/commentry/init.lua` - plugin setup entrypoint
- `lua/commentry/commands.lua` - `:Commentry` command surface
- `lua/commentry/comments.lua` - draft comment lifecycle and rendering
- `lua/commentry/diffview.lua` - diffview integration
- `lua/commentry/codex/` - Codex send/payload/adapters
- `tests/` - `mini.test` suite mirroring runtime modules
- `README.md` - user-facing behavior and command docs
- `.github/workflows/ci.yml` - canonical CI checks

## Command Canon

- Tests: `./scripts/test` (or `mise run test`)
- Lint: `mise run lint`
- Format: `mise run format`
- Health check: `mise run health`
- Docs command: `./scripts/docs` (currently runs a stub and may only emit a warning)
- CI-equivalent local run: `mise run ci`

## Key Invariants

- Plugin namespace is `commentry`; keep runtime, plugin entrypoint, tests, and docs aligned.
- Draft comment store format and context identity must remain stable unless intentionally migrated.
- Diffview-local keymaps and `:Commentry` command behavior should remain backward compatible.
- Behavior changes must include or update tests in `tests/`.

## Forbidden Actions

- Do not run destructive git commands (`git reset --hard`, `git checkout --`, force-push) without explicit approval.
- Do not claim tests/lint/health passed unless you actually ran the commands.
- Do not edit unrelated files to satisfy formatting or cleanup preferences.
- Do not introduce new tooling/dependencies if current `mise` + script workflow can solve the task.
- Do not change persisted store semantics silently; document and test any migration.

## Escalate Immediately If

- Requirements conflict between README, AGENTS, and implementation.
- A change affects persisted comment store schema or context identity.
- A change requires network-dependent tests/fixtures not available in CI.
- You cannot reproduce or fix failing tests after two focused attempts.

## Everyday Development Guidance

- Prefer table-driven tests for combinatorial behavior.
- Stub Neovim APIs carefully; restore in `after_each`.
- For upvalue helpers, use `debug.setupvalue`.
- Keep edits ASCII unless surrounding code already uses Unicode.

## If You Change...

- `lua/commentry/**/*.lua`:
  run `mise run lint && ./scripts/test`
- `lua/commentry/health.lua`:
  also run `mise run health`
- User-visible behavior or commands:
  update `README.md` and relevant help docs in `doc/commentry.txt`
- Keymaps/config defaults:
  update tests (`tests/commentry_config_spec.lua`, command/keymap specs) and docs

## Current Docs Status (Important)

- `./scripts/docs` currently executes `lua/commentry/docs.lua`.
- `lua/commentry/docs.lua` is a stub today; docs are not auto-regenerated yet.
- If you implement docs generation, wire it to real outputs and add CI drift checks.
```

**Verify:** `rg -n "Forbidden Actions|Escalate Immediately If|Current Docs Status" AGENTS.md`  
**Expected:** All three sections are present and discoverable.

---

### Change 3: `CONTRIBUTING.md`
**Action:** create  
**Why:** Fixes gap #3 by defining contributor and AI workflow expectations with evidence-based verification.

```markdown
# Contributing to commentry.nvim

## Scope

This repository is a Neovim plugin scaffold with active feature development.
Keep changes minimal and task-scoped.

## Development Workflow

1. Read `AGENTS.md` and the relevant module(s) before editing.
2. Make focused changes only; avoid opportunistic refactors.
3. Add or update tests for behavior changes.
4. Run verification commands locally.
5. Update docs for user-visible behavior changes.

## Verification Commands

- `mise run lint`
- `./scripts/test`
- `mise run health`
- Optional aggregate: `mise run ci`

## AI-Assisted Contributions

If using an AI coding assistant:

1. Ground edits in existing files and command outputs.
2. Do not claim checks passed without running them.
3. Include exact validation commands and outcomes in PR description.
4. Flag uncertainty explicitly (especially around store schema or diffview behavior).

## Pull Request Expectations

Include these sections in each PR:

- Summary: what changed and why
- Validation: exact commands run
- Risk: possible regressions/blast radius
- Rollback: how to revert safely

## Docs Notes

`./scripts/docs` currently runs a stub generator. If your change affects user-facing behavior, update `README.md` and `doc/commentry.txt` directly unless/until docs generation is implemented.
```

**Verify:** `test -f CONTRIBUTING.md && rg -n "Verification Commands|AI-Assisted Contributions" CONTRIBUTING.md`  
**Expected:** File exists and both sections are present.

---

### Change 4: `.github/pull_request_template.md`
**Action:** create  
**Why:** Fixes gap #3 by forcing validation evidence and risk disclosure on PRs.

```markdown
## Summary

<!-- What changed and why. Link issue/plan/bead when applicable. -->

## Validation

<!-- Copy-paste exact commands you ran. -->
- [ ] `mise run lint`
- [ ] `./scripts/test`
- [ ] `mise run health` (when health/runtime integration touched)

### Command Output

<!-- Paste key output lines or note "pass" with timestamps. -->

## Risk

<!-- What could regress? Mention behavior, persistence, keymaps, or integration impact. -->

## Rollback

<!-- Exact rollback approach (for example: revert commit X, restore previous behavior). -->

## Docs

- [ ] README/doc updates included for user-visible changes
- [ ] No docs change needed (explain why)
```

**Verify:** `test -f .github/pull_request_template.md`  
**Expected:** GitHub picks it up automatically for new PR descriptions.

---

### Change 5: `.github/workflows/ci.yml`
**Action:** edit  
**Why:** Closes gap #1/#3 by adding docs command execution to CI so broken scripts are caught immediately.

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v3
      - name: Run lint tasks
        run: mise run lint

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v3
      - name: Install Linux test dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y libreadline-dev
      - name: Run tests
        run: mise run test

      - name: Run checkhealth
        run: mise run health

  docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v3
      - name: Run docs command
        run: mise run docs
```

**Verify:** `rg -n "^  docs:|Run docs command|mise run docs" .github/workflows/ci.yml`  
**Expected:** CI workflow includes a `docs` job that executes the docs command.
