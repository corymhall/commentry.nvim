# Codebase Context: keymaps

## Feature Brief
Add keymapping options so the user can configure mapping for each of the functions

## App Structure
- `lua/commentry/` is the plugin runtime under a single module namespace and contains all business logic and integration layers.
- `init.lua` is the entry point called by `require("commentry").setup(opts)`.
- `config.lua` stores defaults, command registration, and state directory initialization.
- `commands.lua` handles command routing and binds buffer-local keymaps in diffview buffers.
- `comments.lua` contains most business logic: draft comment model/state, persistence orchestration, list/prompt navigation, file review state, export.
- `diffview.lua` handles Diffview wiring, review-context resolution, lifecycle autocmds, marker rendering, and file navigation hooks.
- `store.lua` owns filesystem-backed persistence and schema validation.
- `health.lua`, `util.lua`, `codex/` are support modules for diagnostics, notifications, and optional send adapter behavior.
- Tests live in `tests/` (mini.test + luassert), scripts in `scripts/`.
- Plans/docs are in `plans/`, `docs/`, and historical artifacts in `docs/archive/speckit/`.
- Entry points for users are `require("commentry").setup(opts)` and the `:Commentry` user command.

## Existing UI Patterns
- No traditional app-level screens/pages/routes exist; this is a Neovim plugin UX.
- UI is buffer-centric:
  - Diffview buffers render inline markers/cards with extmarks (`lua/commentry/diffview.lua`, `render_comment_markers`, `render_file_review_indicator`).
  - `:Commentry list-comments` opens a Snacks picker list (optional dependency).
  - Comment compose/edit uses a floating centered Neovim window in `prompt_comment_body` (`lua/commentry/comments.lua`).
- Key interaction patterns are command-driven and keyboard-first:
  - `:Commentry` subcommands in `commands.lua`.
  - Buffer-local mappings attached on `DiffviewDiffBufWinEnter`.
- Mapping attachment pattern:
  - `vim.keymap.set` with descriptions.
  - Functions are looked up from `Config.keymaps` values.
  - Optional/disable-able mappings use empty string checks (e.g., `toggle_file_reviewed`, `next_unreviewed_file`).
- Repeated UX flow is stateful but local: comment actions operate on current diff context/file/side and emit Util info/warn/error messages.

## Related Features
- Existing configurable keymaps already exist in `lua/commentry/config.lua` under `keymaps`:
  - `add_comment`, `add_range_comment`, `edit_comment`, `delete_comment`, `set_comment_type`, `toggle_file_reviewed`, `next_unreviewed_file`.
- Bound in `lua/commentry/commands.lua` by `maybe_attach_keymaps` for normal and visual modes.
- Navigation-adjacent features that share patterns:
  - `toggle-file-reviewed` and `next-unreviewed` commands (`Commands.register`) map directly to the same underlying functions as keymaps.
  - `:Commentry list-comments` already offers jump navigation (`Diffview.focus_file`, `Diffview.list_view_files`) and therefore has a natural precedent for key-driven navigation features.
- Data/state ready for keymap-driven behavior:
  - Review context object (`Diffview.resolve_review_context`) and stable context IDs for persistence.
  - In-memory review state by context (`comments.lua` `state.diffs`).
  - Persistence hooks (`Store.read/write`) keyed by context and root.
  - File review status and next-unreviewed traversal state in `file_reviews`.

## Tech Stack
- Language/runtime: Lua plugin running in Neovim (Neovim 0.9+ per docs/spec).
- Diff UI dependency: `diffview.nvim` (required).
- Optional dependency: `snacks.nvim` for picker-based listing.
- No component library/framework (no React/Vue/Next app layers).
- Local filesystem JSON persistence via uv/fs + vim JSON helpers.
- Tests: mini.test harness with Luassert; minimal style via `stylua`/`selene`.
- GitHub/CI-facing workflow tooling is not in runtime path.

## Project Conventions
- Configure via `require("commentry").setup(opts)` and merge options through `vim.tbl_deep_extend("force", ...)` in `config.lua`.
- Plugin init should be idempotent (`commands.lua` and `diffview.lua` use setup guards).
- Optional integrations should be guarded with `pcall(require, ...)` and explicit user-facing failure paths.
- Keep state and behavior moduleized: rendering logic in `diffview.lua`, domain logic in `comments.lua`, persistence in `store.lua`.
- Existing docs conventions note a stub docs pipeline (`./scripts/docs`, `lua/commentry/docs.lua`) and a scaffolded structure inherited from sidekick.
- No `CLAUDE.md` file in this repo; instructions here come from `AGENTS.md`, `README.md`, and `doc/commentry.txt`.
- Anti-patterns to avoid:
  - Avoid editing docs generation assumptions (`lua/commentry/docs.lua` is placeholder).
  - Avoid hard failures when optional features are missing (especially snacks/codex).
  - Keep buffer-local mapping behavior consistent (diff-only attachment via `commentry_diffview` marker/autocmd).

## Key Files to Reference
- `lua/commentry/config.lua`
- `lua/commentry/commands.lua`
- `lua/commentry/diffview.lua`
- `lua/commentry/comments.lua`
- `lua/commentry/store.lua`
- `lua/commentry/health.lua`
- `lua/commentry/util.lua`
- `README.md`
- `AGENTS.md`
- `doc/commentry.txt`
- `docs/plans/2026-02-21-diff-line-comments-design.md`
