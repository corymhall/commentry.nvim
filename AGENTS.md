# AI Agent Contract

This file defines the operating contract for humans and AI agents working in this repository.

## Ground Truth

- Project: `commentry.nvim` Neovim plugin.
- Runtime target: Neovim `0.10+`.
- Primary language: Lua.
- Test framework: `mini.test`.
- Task runner: `mise` (`mise run <task>` is canonical).
- Docs are maintained manually; `lua/commentry/docs.lua` validates README/vimdoc/help parity for release-facing surfaces.

## Start Here Module Map

- `plugin/commentry.lua`: Neovim plugin entrypoint.
- `lua/commentry/init.lua`: public Lua module entrypoint.
- `lua/commentry/config.lua`: user-facing configuration surface and defaults.
- `lua/commentry/docs.lua`: docs validation hook for README/vimdoc/help tags.
- `tests/`: `mini.test` test suite.
- `tests/minit.lua`: test harness/bootstrap.
- `scripts/test`: local test runner wrapper.
- `scripts/docs`: docs runner wrapper.

## Command Canon (Use These)

Run commands from repo root.

- Format code: `mise run format`
- Lint code: `mise run lint`
- Run tests: `mise run test`
- Validate docs: `mise run docs`
- Run health checks: `mise run health`
- Full local gate: `mise run ci` (runs lint + test + health + docs)

## Key Invariants

- Draft store format (`commentry.json`) must remain backwards-compatible. Existing stores must still load after changes to `lua/commentry/store.lua`.
- Review context identity is branch-scoped (`<root>::review::branch::<branch>`). Do not change the identity scheme without migrating existing stores.
- Comment types are `note`, `suggestion`, `issue`, `praise`. Do not add types without updating config validation, store schema, and export formatting.
- `:Commentry` must remain the single user-facing command entrypoint.
- `config.lua` validates and normalizes all user input; setup must be idempotent.
- Keep module namespace aligned (`commentry`) across `plugin/`, `lua/`, `tests/`, and docs.
- Keep changes deterministic and offline-safe for CI/headless runs.
- Keep README/docs claims aligned with actual behavior.
- Preserve ASCII unless a file already requires Unicode.

## Forbidden Actions

- Do not add network-dependent behavior to tests.
- Do not silently change public API shape without updating tests and docs.
- Do not edit unrelated files for task-local changes.
- Do not bypass `mise` task canon in CI/PR guidance unless a task is missing.
- Do not claim docs are generated from source; `mise run docs` is a validator for manually maintained release docs.

## Escalation Triggers

Stop and ask for direction when any of these occur:

- Behavior change requires breaking config/API compatibility.
- Conflicting expected behavior between tests, README, and implementation.
- A task needs new dependencies or external tooling not in `mise.toml`.
- CI/headless constraints force tradeoffs not documented in repo.
- You detect unrelated, concurrent edits that create merge-risk in touched files.

## If You Change X, Verify Y

- If you change formatting/style config or broad Lua edits, run: `mise run format` then `mise run lint`.
- If you change runtime/plugin behavior, run: `mise run test`.
- If you change docs/readme generation paths, run: `mise run docs`.
- If you change plugin wiring/health surfaces, run: `mise run health`.
- Before handoff, report exact commands run and pass/fail results.

## PR Hygiene Expectations

- Keep PRs scoped and reversible.
- Include risk and rollback notes for behavior changes.
- Prefer adding/updating tests in the same PR as behavior changes.
- Include command output summary for `format`, `lint`, `test`, and `health`.
