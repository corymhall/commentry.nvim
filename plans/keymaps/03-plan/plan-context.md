# Codebase Analysis: keymaps

**Generated:** 2026-02-27T15:15:09Z
**Source:** 3-agent parallel exploration

---

## Architecture Overview

Runtime layers and boundaries:
- Bootstrap wiring: `lua/commentry/init.lua`
- Config/runtime contract: `lua/commentry/config.lua`
- Command surface and keymap attachment: `lua/commentry/commands.lua`
- Diffview context lifecycle: `lua/commentry/diffview.lua`
- Domain actions/state: `lua/commentry/comments.lua`
- Persistence: `lua/commentry/store.lua`
- Utility/health: `lua/commentry/util.lua`, `lua/commentry/health.lua`
- Optional integration: `lua/commentry/codex/*`

Dependency shape:
- `init.lua` orchestrates `config`, `commands`, `diffview`, optional `codex`.
- `commands.lua` depends on `comments`, `config`, `diffview`, `util`.
- `comments.lua` depends on `diffview`, `config`, `store`, `util`.
- `store.lua` depends on `config`, `util`.

Feature fit:
- Keymap schema/contract belongs in `config.lua` (`M.keymaps`, setup merge path).
- Binding behavior/idempotency belongs in `commands.lua` (`local function maybe_attach_keymaps(bufnr)`).
- Action semantics remain in `comments.lua` and should stay behaviorally stable.
- Diffview-only scope is enforced through `commentry_diffview` buffer marker from `diffview.lua`.

Build/test/deploy:
- No new subsystem required; keymaps are a config-to-binding extension.
- Test runner remains `./scripts/test` (`tests/minit.lua`, `mini.test`).
- Manual docs updates required (`README.md`, `doc/commentry.txt`).

## Integration Surface

Primary touchpoints:
- `lua/commentry/config.lua`
  - Type contract: `---@class commentry.Keymaps`.
  - Defaults: `defaults.keymaps`.
  - Merge entrypoint: `M.setup(opts)` using `vim.tbl_deep_extend("force", {}, vim.deepcopy(defaults), opts or {})`.
- `lua/commentry/commands.lua`
  - Attach function: `local function maybe_attach_keymaps(bufnr)`.
  - Guards:
    - Diffview guard via `commentry_diffview` marker.
    - Idempotence guard via `vim.b[bufnr].commentry_keymaps`.
  - Existing selective disable behavior:
    - empty mapping for `toggle_file_reviewed`
    - empty mapping for `next_unreviewed_file`
  - Existing fallback behavior:
    - `add_range_comment` falls back to `add_comment`.
- `lua/commentry/comments.lua`
  - Actions invoked by keymaps/commands:
    - `add_comment`
    - `add_range_comment`
    - `edit_comment`
    - `delete_comment`
    - `set_comment_type`
    - `toggle_file_reviewed`
    - `next_unreviewed_file`
- `lua/commentry/diffview.lua`
  - Sets buffer scope marker `commentry_diffview` used by attach logic.

Requirement-to-surface implications:
1. Seven functions configurable: keep `commentry.Keymaps` and `defaults.keymaps` authoritative.
2. Defaults retained: preserve all seven defaults.
3. Partial override isolation: rely on deep-merge semantics plus explicit tests.
4. Selective disable semantics: keep scoped to two supported actions unless spec expands.
5. Diffview-only attach: preserve marker-based gating path.
6. Command fallback parity: review command coverage for `add_comment`/`edit_comment`/`delete_comment` if parity requires command forms.
7. Documentation: add keymap matrix and disable guidance in `README.md` and `doc/commentry.txt`.
8. Regression coverage: expand tests in `tests/commentry_commands_spec.lua` and `tests/commentry_config_spec.lua`.
9. Data layer: no persistence or schema migration expected.

## Patterns & Conventions

Precedent:
- Existing keymap + command stack is the template (`config.lua` defaults, `commands.lua` attach, `comments.lua` actions).

Coding patterns:
- Centralized defaults + deep merge (`config.lua`).
- Idempotent setup guards (`initialized` in `commands.lua`).
- Buffer-scoped state markers (`vim.b[bufnr]`, buffer vars) for attach control.
- LuaLS annotations (`---@class`, `---@field`, `---@param`).

Error/observability patterns:
- Use `lua/commentry/util.lua` notification helpers (`info`, `warn`, `error`, `debug`).
- Guard optional dependencies with `pcall(require, ...)`.
- Prefer precondition checks with explicit, actionable user-facing messages.

Testing patterns:
- `mini.test` suite with module-scoped specs in `tests/`.
- `before_each`/`after_each` cleanup and `package.loaded` stubbing are established patterns.
- Existing gap: direct attach-path tests for `maybe_attach_keymaps` behavior.

Style/review standards:
- Follow `AGENTS.md`, `stylua.toml`, `selene.toml` expectations.
- Keep docs synced in `README.md` and `doc/commentry.txt` when behavior changes.

## Key Files Reference

- `lua/commentry/config.lua`: keymap type contract, defaults, setup merge.
- `lua/commentry/commands.lua`: keymap attach logic and command routing/completion.
- `lua/commentry/comments.lua`: action implementations bound to keymaps/commands.
- `lua/commentry/diffview.lua`: diff buffer marking (`commentry_diffview`) and integration hooks.
- `lua/commentry/store.lua`: persistence boundary; confirms no keymap schema impact.
- `lua/commentry/util.lua`: notification/logging helpers for user-facing errors.
- `tests/commentry_commands_spec.lua`: keymap attach and command behavior regression surface.
- `tests/commentry_config_spec.lua`: config merge/default/keymap contract regression surface.
- `README.md`: user-facing setup and behavior docs.
- `doc/commentry.txt`: vim help docs for commands/config.
- `scripts/test`, `tests/minit.lua`: test invocation and harness entrypoint.

## Constraints & Considerations

- Keep implementation additive in `config.lua` + `commands.lua`; avoid domain/persistence drift.
- Preserve existing behavioral contracts unless spec explicitly changes them.
- Enforce diffview-only attachment and idempotency.
- Preserve/clarify `add_range_comment` fallback behavior.
- Prefer explicit validation/warnings over silent coercion for invalid keymap values.
- Verify command fallback coverage decisions before implementation to avoid scope creep.
