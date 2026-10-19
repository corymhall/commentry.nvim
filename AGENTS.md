# AI Agent Contract

This file defines the operating contract for humans and AI agents working in this repository.

## Ground Truth

- Project: `commentry.nvim` Neovim plugin.
- Runtime target: Neovim `0.10+`.
- Languages: Lua for Neovim, Go for the local CLI, TypeScript for the Executor app.
- Test frameworks: `mini.test` for Lua, `go test` for Go, Node tests for Executor SQL.
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
- `main.go`: standalone Go CLI entrypoint.
- `cmd/`: Cobra command factories. Keep inbox logic independent of Cobra.
- `inbox/`: Go inbox protocol/client and legacy SQLite export backend.
- `executor/`: Authenticated Executor API client and browser device login.
- `integrations/executor/`: TypeScript app, SQL migrations, and agent skill.
- `lua/commentry/inbox/store.lua`: Neovim adapter to the Go JSON interface.
- `.golangci.yml`: Go lint, modernization, and formatter configuration.
- `hk.pkl`: Go checks and optional git hooks, adapted from Evaler.
- `.agents/skills/cobra-viper/`: Go CLI architecture guidance, shared with Claude via symlink.

## Command Canon (Use These)

Run commands from repo root.

- Format code: `mise run format`
- Lint code: `mise run lint`
- Run tests: `mise run test`
- Validate docs: `mise run docs`
- Run health checks: `mise run health`
- Full local gate: `mise run ci` (runs lint + test + health + docs)
- Build the Go CLI: `mise run build` (Go lint + tests, outputs `bin/commentry`)
- Compile the backend only: `mise run build_go`
- Run the Go CLI: `mise run run -- --help`
- Install the Go CLI: `mise run install-commentry`
- Executor setup: `mise run setup_executor`
- Executor checks: `mise run test_executor`, `mise run lint_executor`
- Go-only checks: `mise run format_go`, `mise run lint_go`, `mise run test_go`
- Apply Go lint fixes: `mise run lint:fix`

## Go Workflow

- Use Go 1.26.5 and golangci-lint v2 through mise, matching Evaler's scaffold.
- Read `.agents/skills/cobra-viper/SKILL.md` when implementing commands.
- Build commands with factories and pass command contexts into domain code.
- Add Viper when configuration requires it. Commands currently use Cobra flags and environment variables.
- Executor owns the configured inbox database. Each mutation and change record must share a transaction. `modernc.org/sqlite` remains for legacy export and offline tests.
- The Executor app uses its pinned `apps` version and synchronous `ctx.sql.transaction`. Keep local Git and Rex operations in the client.
- Run `mise run setup_executor` before formatting or linting on a fresh checkout. Node tests use isolated SQLite and never need the network.
- Keep original captures immutable, incoming versions distinct from read acknowledgements, and queue claims atomic.
- Lua tests build the Go binary automatically. Tests use isolated data directories and never mutate the user's inbox.
- `mise run lint_go` includes the modernize analyzer and the configured formatters.
- Before changing Go files, inspect planned checks with `mise exec -- hk run check --safe --plan --json`.
- Scope agent checks to changed Go files. For exact paths, pass a NUL-delimited file list with `--files0-from`.
- Use `--safe` for read-only hk checks and inspect command effects before applying fixes.
- Consume hk JSON or JSONL diagnostics and retain raw output when investigating failures.
- Git hooks are optional. Install explicitly with `mise exec -- hk install`.

## Visual Validation

- When validating Neovim UI changes, prefer the embedded RPC capture workflow over reasoning from code alone.
- Use the repo-local skill at `.codex/skills/neovim-ui-capture/SKILL.md` when the task involves Commentry appearance or interaction.
- Preferred command: `./scripts/ui-capture-rpc`
- Compare presets with: `./scripts/ui-capture-rpc --all-presets`
- Treat `laptop-small` as the stricter baseline when judging layout changes.

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
- If you change Go code or tooling, run: `mise run format_go`, `mise run lint_go`, and `mise run build`.
- If you change docs/readme generation paths, run: `mise run docs`.
- If you change plugin wiring/health surfaces, run: `mise run health`.
- Before handoff, report exact commands run and pass/fail results.

## PR Hygiene Expectations

- Keep PRs scoped and reversible.
- Include risk and rollback notes for behavior changes.
- Prefer adding/updating tests in the same PR as behavior changes.
- Include command output summary for `format`, `lint`, `test`, and `health`.
