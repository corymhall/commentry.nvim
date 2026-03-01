# AI Contribution Readiness Audit

## Target
- **Repo:** commentry.nvim
- **Language/stack:** Lua, Neovim 0.10+ plugin, mini.test, mise task runner
- **Audit date:** 2026-02-28

---

## Part 1: Diagnostic Summary

### What exists

| Artifact | Status | Notes |
|---|---|---|
| AGENTS.md | Present, stale | Missing forbidden actions, escalation triggers, invariants; commands bypass mise; version mismatch (says 0.9, repo requires 0.10) |
| mise.toml (task surface) | Strong | format, lint, test, health, ci — clean targets with good naming |
| CI workflow | Good | Lint + test + health via mise; parity with local commands |
| PR template | Missing | No `.github/PULL_REQUEST_TEMPLATE.md` |
| CONTRIBUTING.md | Missing | No contribution guide |
| Architecture / module docs | Missing | No module map; agent must read full tree to orient |
| Test commands | Good | `mise run test` runs full suite; `mise run ci` runs lint+test+health |
| Health checks | Strong | `lua/commentry/health.lua` checks version, setup, deps, codex |

### What this repo does well
- **Excellent test coverage** — 1.16:1 test-to-source ratio with 11 spec files mirroring the module tree.
- **CI/local parity** — CI runs `mise run lint` / `mise run test` / `mise run health`, same commands you run locally.
- **Comprehensive health.lua** — runtime healthcheck validates Neovim version, plugin setup, diffview, snacks, and codex adapter state.

### Top 3 gaps
1. **AGENTS.md is outdated and incomplete** — commands reference `./scripts/test` instead of `mise run`, version claim is wrong, and it lacks forbidden actions, escalation triggers, and invariants needed for safe AI changes.
2. **No PR template** — AI contributions land without structured evidence of test execution or risk assessment.
3. **No format drift check in CI** — AI can submit unformatted code that passes lint but introduces format inconsistencies (stylua `--check` catches this, but a formatting step with `git diff --exit-code` would be more explicit).

### Concrete mismatches found
1. AGENTS.md references `./scripts/test` and `./scripts/docs` directly instead of `mise run test` / `mise run docs` — the repo uses mise as the canonical task runner but AGENTS.md doesn't mention it.
2. AGENTS.md says "Neovim 0.9+" but `health.lua:55` checks for `nvim-0.10` and README says "Neovim 0.10+ is required".
3. AGENTS.md "Recent Changes" and "Active Technologies" sections contain stale bead metadata (`001-diff-line-comments`) that doesn't help agents orient.

---

## Part 2: Implementation Packet

### Change 1: `AGENTS.md` (rewrite)
**Action:** edit (full rewrite)
**Why:** Addresses gap #1 — stale commands, wrong version, missing safety/escalation sections.

```markdown
# Agent Instructions

## What this repo is
commentry.nvim — Neovim plugin for code review workflows on AI-generated changes.
Lua, Neovim 0.10+, diffview.nvim dependency, mini.test test suite, mise task runner.

## Start here
- `plugin/commentry.lua` — Neovim plugin entrypoint (`:Commentry` command registration)
- `lua/commentry/init.lua` — public API (`M.setup(opts)`)
- `lua/commentry/config.lua` — configuration management, defaults, validation
- `lua/commentry/commands.lua` — command implementations and keymap attachment
- `lua/commentry/comments.lua` — comment CRUD, multiline editor, export
- `lua/commentry/diffview.lua` — diffview.nvim integration, git ops, file review state
- `lua/commentry/store.lua` — persistent JSON store (draft comments, review state)
- `lua/commentry/codex/` — Codex send integration (orchestrator, adapter, payload, send)
- `lua/commentry/health.lua` — `:checkhealth commentry` implementation
- `tests/` — one spec file per module (mini.test)
- `mise.toml` — all dev commands (format, lint, test, health, ci)

## Command canon
All commands use `mise run`. Do not call scripts or tools directly.
- Format: `mise run format`
- Lint: `mise run lint` (runs stylua --check + selene)
- Test: `mise run test` (mini.test suite via headless Neovim)
- Health: `mise run health` (`:checkhealth commentry` headless)
- Full CI: `mise run ci` (lint + test + health)

## Key invariants
- Neovim >= 0.10 is required. `health.lua` enforces this at runtime.
- `config.lua` validates and normalizes all user input; setup must be idempotent.
- Draft store format (`commentry.json`) must remain backwards-compatible. Existing stores must still load.
- Review context identity is branch-scoped (`<root>::review::branch::<branch>`). Do not change the identity scheme without migrating existing stores.
- The `:Commentry` command must remain the single user-facing command entrypoint.
- Comment types are `note`, `suggestion`, `issue`, `praise` — do not add types without updating config validation, store schema, and export formatting.

## Forbidden actions
- Do not run `rm -rf`, `git push --force`, or `git reset --hard` without explicit approval.
- Do not skip linting or formatting checks (`--no-verify`, etc.).
- Do not make network calls in tests — CI runs headless with no network.
- Do not add runtime dependencies beyond diffview.nvim without discussion.
- Do not fabricate test output or claim tests passed without running them.
- Do not modify the store JSON schema in a backwards-incompatible way.

## Escalate immediately if
- Requirements conflict or are ambiguous.
- A change touches the store schema or review context identity scheme.
- A change touches `config.lua` validation/normalization in a way that could reject previously valid configs.
- Tests fail after two debugging attempts.
- A change requires adding a new runtime dependency.

## If you change...
- Any `.lua` file under `lua/` or `plugin/` → run `mise run format && mise run lint && mise run test`
- `lua/commentry/config.lua` (defaults/validation) → verify existing configs still parse; update README if user-facing
- `lua/commentry/store.lua` (schema) → ensure backwards compatibility with existing `commentry.json` files
- `lua/commentry/health.lua` → run `mise run health` to verify
- Test files under `tests/` → run `mise run test`
- `mise.toml` → run `mise run ci` to verify all tasks still work

## Writing tests
- Use `mini.test` assertions (`assert.are.same`, `assert.is_true`, etc.)
- One spec file per module: `tests/commentry_<module>_spec.lua`
- Stub Neovim APIs carefully and restore them in `after_each` hooks
- For upvalue-based helpers, use `debug.setupvalue`
- Prefer table-driven tests for combinatorial cases
- Test fixtures go in `tests/fixtures/`
```

**Verify:** `cat AGENTS.md | wc -l` — should be ~65 lines
**Expected:** Clean, structured agent instructions with command canon, invariants, forbidden actions, and escalation triggers.

---

### Change 2: `.github/PULL_REQUEST_TEMPLATE.md` (create)
**Action:** create
**Why:** Addresses gap #2 — no structured template for AI contribution evidence.

```markdown
## Summary
<!-- What changed and why. Link to bead/issue if applicable. -->

## Validation
<!-- Commands you ran and their output. Copy-paste, don't paraphrase. -->
- [ ] `mise run format` (no diff)
- [ ] `mise run lint` (clean)
- [ ] `mise run test` (all pass)
- [ ] `mise run health` (all OK)

## Risk
<!-- What could go wrong? Does this touch config validation, store schema, or the review context identity scheme? -->

## Backwards compatibility
<!-- Does this change affect existing commentry.json stores or user-facing config options? -->
```

**Verify:** `cat .github/PULL_REQUEST_TEMPLATE.md`
**Expected:** Template with Summary, Validation checklist, Risk, and Backwards compatibility sections.

---

### Change 3: `.github/workflows/ci.yml` — add format drift check
**Action:** edit
**Why:** Addresses gap #3 — CI checks lint but doesn't catch formatting drift explicitly.

```diff
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
```

**Verify:** `cat .github/workflows/ci.yml`
**Expected:** Lint job runs `mise run format` + `git diff --exit-code` before `mise run lint`.

---

### Change 4: `README.md` — update Development section to reference mise
**Action:** edit
**Why:** README's Development section references `./scripts/test` directly, contradicting the canonical `mise run` commands.

```diff
 ## Development

-- Run tests: `./scripts/test`
-- Generate docs (stub): `./scripts/docs`
-- Canonical feature/design plans: `docs/plans/`
-- Legacy Speckit archive (read-only history): `docs/archive/speckit/`
+All commands use [mise](https://mise.jdx.dev/) as the task runner:
+
+- Format: `mise run format`
+- Lint: `mise run lint`
+- Test: `mise run test`
+- Health: `mise run health`
+- Full CI: `mise run ci` (lint + test + health)
+
+Canonical feature/design plans: `docs/plans/`
```

**Verify:** `grep -A8 '## Development' README.md`
**Expected:** Development section lists mise commands, not raw script paths.

---

## Not recommended (calibrated for small-team Neovim plugin)

- **CONTRIBUTING.md** — AGENTS.md covers the AI workflow; separate file is redundant at this repo size.
- **Architecture docs** — ~5800 lines with clear 1:1 module-to-test mapping. "Start here" in AGENTS.md provides sufficient orientation.
- **Observability/runbook** — Neovim plugin, not a runtime service. health.lua covers diagnostics.
- **Targeted test runner** — mini.test doesn't natively support single-file targeting through mise. Not worth the complexity.
