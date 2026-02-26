# Codebase Context: codex-integration

## App Structure
- Single Neovim plugin package under `lua/commentry/` with `tests/` and docs/plans artifacts.
- Runtime modules:
  - `lua/commentry/init.lua`: plugin bootstrap.
  - `lua/commentry/config.lua`: defaults, command registration, state dir setup.
  - `lua/commentry/diffview.lua`: Diffview integration, review-context resolution, lifecycle/autocmd wiring.
  - `lua/commentry/comments.lua`: review state, comment/thread model, persistence orchestration, hover/list/export/render operations.
  - `lua/commentry/store.lua`: local JSON store read/write and schema validation.
  - `lua/commentry/commands.lua`: command routing, keymap attachment, `:Commentry` completions.
  - `lua/commentry/util.lua`, `lua/commentry/health.lua`, `lua/commentry/docs.lua` are support modules.
- Planning/design history is mostly in `docs/plans/` and `docs/archive/speckit/`.

## Existing UI Patterns
- Diff-context actions are driven through:
  - `:Commentry` command router (`lua/commentry/commands.lua`).
  - Buffer-local keymaps attached on `DiffviewDiffBufWinEnter` for add/edit/delete/type/list/review toggles.
- Review rendering uses extmarks:
  - line markers (`render_comment_markers`), file-level reviewed marker (`render_file_review_indicator`), and hover virtual lines (`render_hover_preview`) in `lua/commentry/diffview.lua`.
- Cursor-driven preview lifecycle:
  - `CursorMoved` / `CursorHold` in diff buffers trigger hover refresh/clear via `commentry.diffview`.
- Optional picker path:
  - `:Commentry list-comments` uses Snacks picker if available; command is explicit-failing when missing.

## Related Features
- `:Commentry open` opens/attaches to Diffview and computes/attaches review context.
- Draft comments are persisted per context and rehydrated from `.commentry/contexts/<context-id>/<filename>`.
- Existing context model:
  - working-tree vs commit-range mode in `resolve_review_context`.
  - context id includes root + mode + revisions.
- File reviewed state tracking exists (`file_reviews`) and is rendered as `[reviewed]` / `[unreviewed]`.
- Export path exists today:
  - deterministic markdown export in `lua/commentry/comments.lua:generate_export_markdown`.
  - export destination is stdout or register (`:Commentry export`).
- No current network/API submission path; local-only draft workflow only.
- Archived contract for a REST-like review model exists (`commentry-review.yaml`) but is not wired into runtime now.

## Tech Stack
- Lua + Neovim APIs (Lua runtime), Neovim 0.9+ target.
- `diffview.nvim` required for diff UI.
- `snacks.nvim` optional for picker.
- Filesystem-backed JSON persistence via `vim.fn.readfile/writefile`, `vim.json`.
- Tests: mini.test + luassert in `tests/`.

## Project Conventions
- Module pattern: `local M = {}` + exported functions and local helpers.
- Soft-fail optional integration: `pcall(require, ...)` and capability checks.
- State keyed by logical review id (`context_id`/`diff_id`), not global mutable blobs.
- Aggressive in-session validation, explicit error/warn/info messaging.
- Command registration is centralized and idempotent (`setup` guards + initialized flag).
- No external side effects beyond local persistence and user-facing UI updates.

## Key Files to Reference
- `lua/commentry/comments.lua`
- `lua/commentry/diffview.lua`
- `lua/commentry/store.lua`
- `lua/commentry/commands.lua`
- `lua/commentry/config.lua`
- `lua/commentry/util.lua`
- `lua/commentry/health.lua`
- `README.md`
- `doc/commentry.txt`
- `docs/plans/2026-02-21-diff-line-comments-design.md`
- `docs/archive/speckit/001-diff-line-comments/contracts/commentry-review.yaml`
