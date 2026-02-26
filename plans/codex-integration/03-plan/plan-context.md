# Codebase Analysis: codex-integration

**Generated:** 2026-02-26
**Source:** 3-agent parallel exploration

---

## Architecture Overview
- `commentry.nvim` is a runtime-only Neovim plugin (no build step) with modules under `lua/commentry/` and tests under `tests/`.
- Bootstrap flow: `lua/commentry/init.lua` loads `commentry.config`, `commentry.commands`, and `commentry.diffview`.
- Plugin state model is local-first and persisted under `.commentry/contexts/<context-id>/commentry.json` via `lua/commentry/store.lua`.
- Runtime data pipeline is:
  - `Neovim events / :Commentry` -> `lua/commentry/commands.lua`
  - context/view resolution in `lua/commentry/diffview.lua`
  - state read/write and payload-shaping logic in `lua/commentry/comments.lua`
  - persistence in `lua/commentry/store.lua` and utility behavior in `lua/commentry/util.lua`.
- Core module roles:
  - `lua/commentry/config.lua`: defaults/options, `:Commentry` command creation, `Config.state` path setup.
  - `lua/commentry/commands.lua`: command router and keymap injectors, existing commands (`open`, `list-comments`, etc.), `M.register`, `M.complete`, diff-buffer attach hooks.
  - `lua/commentry/diffview.lua`: Diffview integration, `resolve_review_context`, `current_file_context`, lifecycle hooks, hover updates.
  - `lua/commentry/comments.lua`: in-memory state, CRUD for comments/threads, reconcile logic, rendering, export helpers, and persistence orchestration calls.
  - `lua/commentry/store.lua`: schema validation + read/write for `.commentry/contexts/...`.
  - `lua/commentry/util.lua`: diff helper/notification utilities.
  - `lua/commentry/health.lua`: external dependency checks for `:checkhealth`.
  - `lua/commentry/docs.lua`: docs generator stub.
- Test and script surface:
  - `scripts/test` invokes `nvim -l tests/minit.lua --minitest` (offline with `LAZY_OFFLINE=1`).
  - `scripts/docs` runs docs generation via `lua/commentry/docs.lua`.
  - module specs include `tests/commentry_commands_spec.lua`, `tests/commentry_comments_spec.lua`, `tests/commentry_diffview_spec.lua`, `tests/commentry_store_spec.lua`, `tests/commentry_health_spec.lua`, `tests/commentry_util_spec.lua`, and `tests/init_spec.lua`.
- Design/requirements references centralizing intent:
  - `plans/codex-integration/01-scope/context.md`
  - `plans/codex-integration/02-spec/spec.md`
- Deployment model is plugin-manager dependent (e.g., README documents `lazy.nvim` style install); no extra compilation layer.

## Integration Surface
- Proposed command entrypoint (v1): add `:Commentry send-to-codex` or `:Commentry send-to-codex-session` in `lua/commentry/commands.lua` (edit regions `100-154`, `199-214`) and route through existing command map/completion path.
- Suggested integration module locations:
  - `lua/commentry/codex/integration.lua` (or similar orchestrator + adapter dispatch),
  - `lua/commentry/codex/adapters/sidekick.lua` (optional adapter),
  - `lua/commentry/codex/payload.lua` (optional payload normalizer/builder).
- Existing seams for integration:
  - `lua/commentry/diffview.lua` context resolution for review target selection:
    - `M.resolve_review_context(args, view) -> table|nil, string|nil`
    - `M.current_file_context() -> table|nil, string|nil`
    - `context_id_for_view` usage in `lua/commentry/comments.lua:197`.
  - `lua/commentry/comments.lua` already provides export-style deterministic traversal:
    - `M.generate_export_markdown(context?) -> string|nil, string|nil` (used as precedent for payload shaping)
  - `lua/commentry/config.lua` for v1 config knobs (`adapter namespace/name`, optional hints, no default flow changes).
  - `lua/commentry/util.lua` for normalized feedback (`info/error/warn`) on send outcomes.
- v1 interface contracts proposed in the design:
  - `commentry.CodexPayload` = `{ context, review, items, provenance }`
  - `commentry.CodexTransportAdapter` = `send(payload: commentry.CodexPayload, target: string|table): boolean, string|nil`
  - `commentry.CodexSendOrchestrator.send_current_review(opts?): { ok: boolean, error?: string, target?: string }`
- Exact extension points:
  - command registration is centralized/idempotent in `lua/commentry/commands.lua`.
  - `M.commands` is extensible and completion is automatic via `M.complete`.
  - `register_commands` hook exists as a concept, but no active implementation in `diffview`/`comments`.
- Data-layer integration constraints:
  - send is conceptualized as send-and-forget in v1: do not introduce new persisted send snapshots/disposition fields.
  - persistence should continue through existing `load_for_view` / `persist_for_view` / `Store.write` paths only.
- Integration tests to add/extend:
  - `tests/commentry_commands_spec.lua` (command routing),
  - `tests/commentry_comments_spec.lua` (payload extraction/filtering and stale rules),
  - `tests/commentry_health_spec.lua` (optional adapter precondition checks).
- Existing gap to close:
  - no session-attached transport contract/adapter API exists today.

## Patterns & Conventions
- Command-driven behavior is expected; no implicit background synchronization for outgoing handoff.
- State is review-context keyed, not globally mutated:
  - context uses `context_id`, `diff_id`, and file review identity over global mutable blobs.
- Module convention is `local M = {}` with local helpers + explicit exports; style consistent in core modules.
- Context-bound actions dominate existing behavior:
  - attached/active context from diff buffers, then operate within that scope.
- Optional integration pattern is already present and conservative:
  - feature behavior guarded by capability checks (example: optional `snacks.nvim.picker.select` path).
- Explicit user feedback style:
  - do not silently fail; emit clear, actionable command-visible outcomes.
- Active/non-stale filtering reuse pattern already exists and should be preserved:
  - paths filter on `comment.status ~= "unresolved"` in:
    - `render_for_context` (`lua/commentry/comments.lua:627`)
    - `active_comments_for_line` (`lua/commentry/comments.lua:648`)
    - `jumpable_comments_for_context` (`lua/commentry/comments.lua:660`)
    - `exportable_comments` (`lua/commentry/comments.lua:1200`)
    - reconcile marks stale as `status == "unresolved"` (`lua/commentry/comments.lua:544`).
- No-new-persistence for v1 and minimal adapter seam are explicit review standards.
- Existing module dependencies for codex surface are internal-first (`commentry.*` + Neovim APIs), no new external runtime requirement unless adapter present.

## Key Files Reference
- `lua/commentry/diffview.lua:223`
  - `M.resolve_review_context(args, view) -> table|nil, string|nil`
- `lua/commentry/diffview.lua:437`
  - `M.current_file_context() -> table|nil, string|nil`
- `lua/commentry/comments.lua:197`
  - `M.context_id_for_view(view) -> string|nil, string|nil`
- `lua/commentry/comments.lua:861`
  - `commentry.DraftComment` fields: `id`, `diff_id`, `file_path`, `line_number`, `line_start`, `line_end`, `line_side`, `comment_type`, `body`, `created_at`, `updated_at`, optional `status`, optional `line_content`
- `lua/commentry/comments.lua:959`
  - `commentry.CommentThread` fields: `id`, `diff_id`, `file_path`, `line_start`, `line_end`, `line_side`, `comment_ids`
- `lua/commentry/comments.lua:1200`
  - `exportable_comments(context)` used as active-item precedent
- `lua/commentry/comments.lua:1236`
  - `M.generate_export_markdown(context?) -> string|nil, string|nil`
- `lua/commentry/store.lua:186`
  - persisted schema includes `project_root`, `context_id`, `comments`, `threads`, `file_reviews`
- `lua/commentry/store.lua:234`
  - `M.path_for_context(project_root, context_id, filename?)`
- `lua/commentry/store.lua:279`
  - `M.read(path)`
- `lua/commentry/store.lua:292`
  - `M.write(path, store)`
- `lua/commentry/commands.lua:100-154`
  - command registration route for subcommands
- `lua/commentry/commands.lua:199-214`
  - completion path for command keys
- `lua/commentry/config.lua:17-43,63`
  - default/config surface candidates for v1 transport knobs
- `lua/commentry/util.lua:1-22`
  - notification helper usage for user messaging
- `lua/commentry/health.lua`
  - dependency checks where optional adapter checks can be added
- `tests/commentry_commands_spec.lua`
  - command dispatch behavior regression area
- `tests/commentry_comments_spec.lua`
  - active/non-stale/filter and payload projection behavior
- `tests/commentry_health_spec.lua`
  - optional adapter readiness checks

## Constraints & Considerations
- Hard failure is required when no attached target/session exists; remediation should be explicit ("attach first"), no partial dispatch or retry loop without target.
- Transport failures must be normalized into user-safe strings and preserve retryability signals; avoid surfacing raw adapter internals.
- Payload scope must be explicit to one active review context (via active diff view / context identity), not all-open-reviews fanout.
- Use existing stale model cautiously:
  - stale = `status == "unresolved"` in current reconcile path; active/non-stale projection should be explicit and auditable.
- Provenance safety: outbound payload fields must be repository-relative (no absolute paths).
- v1 must avoid writing any send-disposition/snapshot artifacts to store; keep persistence as pure local review state.
- Command path should remain optional/orthogonal: plugin works without adapter present; optional integration should not block core review workflows.
- `plans/codex-integration/02-spec/spec.md` and related scope/docs require required tests for:
  - missing target,
  - attached success dispatch,
  - adapter failure,
  - stale filtering,
  - deterministic resend without persistence side effects,
  - provenance safety.
