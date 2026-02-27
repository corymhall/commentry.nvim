# keymaps - Design Specification

**Created:** 2026-02-27
**Status:** Validated
**Brainstorming Mode:** With scope questions

---

## Overview

This feature expands keymapping configuration so users can configure mappings for each supported Commentry function in diffview review buffers. The current plugin already exposes seven keymap entries in `Config.keymaps`; this spec formalizes behavior, constraints, and acceptance criteria for making that per-function model explicit, predictable, and documented.

The primary user problem is friction from fixed or insufficiently explicit mapping behavior during code review. Users need to preserve muscle memory, avoid editor conflicts, and tailor review actions to their workflow without changing core Commentry behavior.

The target audience is existing Commentry users reviewing diffs in Neovim. Core value: configurable per-function shortcuts that stay fast, safe, and consistent with current command and diffview patterns.

---

## Scope Questions & Answers

### Summary
- **Questions addressed:** 40 (scope selected: P0)
- **Auto-answered (best practices):** 0
- **Human decisions:** 2 explicit, remainder resolved via minimal-path defaults
- **Deferred to future:** 0

### P0: Critical Decisions

| # | Question | Answer | How Decided |
|---|---|---|---|
| 1 | Which actions should have defaults immediately? | All seven existing actions keep defaults. | Minimal-path default |
| 2 | Every function mappable or only frequent ones? | Every supported function is mappable. | Human choice |
| 3 | Match common Neovim conventions? | Yes, favor conventional non-conflicting mappings. | Minimal-path default |
| 4 | Discoverability expectations? | Provide clear docs/help and command parity. | Minimal-path default |
| 5 | Consistent across sessions/repos? | Yes, deterministic config behavior across sessions/repos. | Minimal-path default |
| 6 | Preserve personal keybinding habits? | Yes, user overrides are first-class. | Minimal-path default |
| 7 | Disable individual mappings? | Selective disable is supported in v1 for `toggle_file_reviewed` and `next_unreviewed_file` via empty string; other mappings are remap-only. | Human choice |
| 8 | Behavior when mapping cannot be used? | Show actionable error/warn message; no silent failure. | Minimal-path default |
| 9 | Distinct mappings for similar actions? | Yes for risky/semantically different actions; avoid destructive collisions. | Minimal-path default |
| 10 | Beginner-safe and power-user efficient defaults? | Yes, preserve current concise defaults while allowing overrides. | Minimal-path default |
| 11 | When to teach customization? | At setup/docs and command help touchpoints. | Minimal-path default |
| 12 | First expected customization? | Most likely conflict-driven reassignment of one or two keys. | Minimal-path default |
| 13 | Keep defaults or customize immediately? | Support either path with no required customization. | Minimal-path default |
| 14 | How users verify mappings? | Trigger action in diffview with visible command/result feedback. | Minimal-path default |
| 15 | How users recall mappings later? | Through docs/help and consistent command naming. | Minimal-path default |
| 16 | Most-used mapped actions/order? | Add/edit/navigate flows are primary; defaults prioritize these. | Minimal-path default |
| 17 | Trigger to revisit mappings? | Workflow friction or collision with other plugins. | Minimal-path default |
| 18 | Recovery from broken routine? | Update config and retry immediately; clear messaging on invalid mapping use. | Minimal-path default |
| 19 | Global once or per-project evolution? | Global configuration model (plugin setup), repo-agnostic behavior. | Minimal-path default |
| 20 | One-week success criteria? | Users can execute all review actions via preferred mappings without confusion. | Minimal-path default |
| 21 | Intentionally unmapped functions? | Supported only for `toggle_file_reviewed` and `next_unreviewed_file` in v1 via empty-string disable. | Decision consequence |
| 22 | Similar mappings forgotten/distinguished poorly? | Keep defaults semantically distinct; docs reinforce intent. | Minimal-path default |
| 23 | Shared mapping import mismatch? | Users can override per function in setup. | Minimal-path default |
| 24 | Multiple keyboard layout switching? | Allow simple per-function remapping without assumptions about physical layout. | Minimal-path default |
| 25 | Recover when defaults forgotten? | Keep command parity and docs as fallback path. | Minimal-path default |
| 26 | Partial customization only? | Fully supported; untouched actions use defaults. | Minimal-path default |
| 27 | Preferred mappings collide with broader editor habits? | User override expected; no hardcoded lock-in. | Minimal-path default |
| 28 | Team convention vs personal preference? | Personal config wins; teams can publish recommended setups externally. | Minimal-path default |
| 29 | Accidental destructive action risk? | Keep delete distinct and require explicit action context. | Minimal-path default |
| 30 | Migration from other workflows? | Maintain command parity and simple remap surface. | Minimal-path default |
| 31 | Needs for limited hand mobility/RSI? | Per-function remap supports ergonomic customization. | Minimal-path default |
| 32 | One-handed workflows support? | Allow mappings that fit one-handed reach. | Minimal-path default |
| 33 | Alternative hardware expectations? | No hard dependency on specific key combos. | Minimal-path default |
| 34 | New modal-editing users support? | Clear docs/examples and stable defaults. | Minimal-path default |
| 35 | Keyboard region/language assumptions? | Avoid locale-specific assumptions; user-controlled mappings. | Minimal-path default |
| 36 | Cognitive-load friendly mapping strategy? | Keep defaults small and mnemonic where possible. | Minimal-path default |
| 37 | Screen-reader discoverability expectations? | Ensure textual docs and command names remain clear and consistent. | Minimal-path default |
| 38 | Multi-key chord discomfort support? | Permit simpler remaps with no required chord model. | Minimal-path default |
| 39 | Feedback for intended action confirmation? | Reuse existing Util info/warn/error messaging patterns. | Minimal-path default |
| 40 | Share accessible conventions without forcing one style? | Document recommendations; preserve local override freedom. | Minimal-path default |

---

## Design

### Architecture Overview

No new runtime subsystem is required. The feature is an explicit extension of the current keymap configuration contract in `lua/commentry/config.lua` and binding behavior in `lua/commentry/commands.lua`.

The architecture remains:
- `Config.keymaps` defines per-function mapping strings.
- `commands.maybe_attach_keymaps()` binds mappings buffer-locally for diffview buffers.
- Comment actions route through existing `Comments.*` functions.

This preserves current plugin structure and keeps behavior deterministic.

### Components

**Component 1: Keymap Config Contract (`config.lua`)**
- Responsibility: Canonical per-function keymap schema and defaults.
- Interface: `require("commentry").setup({ keymaps = { ... }})`.
- Key considerations: all supported functions must have explicit keys in schema/defaults.

**Component 2: Keymap Attachment (`commands.lua`)**
- Responsibility: Buffer-local binding only in commentry diffview buffers.
- Interface: `maybe_attach_keymaps(bufnr)` and `vim.keymap.set` calls.
- Key considerations: preserve guard behavior for optional keys and idempotent attach.

**Component 3: Command Parity / Fallback Path**
- Responsibility: ensure command-based workflows still work independent of mappings.
- Interface: `:Commentry <subcommand>` registry.
- Key considerations: mappings enhance UX; fallback claims are limited to actions with existing `:Commentry` commands.

### Data Model

No persistence schema or storage format changes.

- Existing state file and review/comment data structures stay unchanged.
- Keymapping behavior is configuration-only.
- No migration required.

### User Flows

**Flow 1: Configure mappings at setup**
1. User sets `keymaps` overrides in plugin setup.
2. Plugin merges overrides with defaults.
3. On diffview buffer entry, keymaps attach buffer-locally.
4. User triggers actions with configured mappings.

**Flow 2: Resolve mapping conflict**
1. User notices key collision during review.
2. User updates one or more keymap values in setup.
3. Reopen/reload session.
4. New mappings apply without behavior regression in underlying actions.

### Error Handling

- Invalid or conflicting user choices are not auto-resolved by this feature; users keep control.
- If an action cannot run due to context/state, existing action-level error messaging remains authoritative.
- Never fail silently when mapped actions are invoked and cannot complete.
- Keymap validation uses setup-time warnings plus runtime guard behavior:
  - Setup-time: warn for unsupported empty-string values on remap-only actions.
  - Runtime: keep attach-time guards for optional mappings and emit actionable warnings for invalid mappings.

### Integration Points

- `lua/commentry/config.lua` keymap schema/defaults.
- `lua/commentry/commands.lua` keymap binding and command registration.
- `lua/commentry/comments.lua` action handlers (`add_comment`, `edit_comment`, etc.).
- `README.md` / `doc/commentry.txt` for user-facing mapping docs.

---

## Acceptance Criteria

1. All seven supported functions are configurable through `Config.keymaps`.
2. Default keymaps remain defined for all seven functions.
3. Overriding one function mapping does not alter others.
4. Remap-only behavior is preserved for core comment actions; selective empty-string disable remains supported only for `toggle_file_reviewed` and `next_unreviewed_file`.
5. Mappings attach only for commentry diffview buffers.
6. Underlying commands remain available as fallback behavior for actions that already expose `:Commentry` subcommands.
7. Documentation clearly lists configurable functions and override examples.
8. Regression coverage verifies buffer-local attachment and default keymap preservation when no remaps are provided.

## Verification Checklist

1. Run `./scripts/test` after adding/adjusting keymap coverage tests.
2. Automated checks should assert:
   - All seven `Config.keymaps` entries remain present by default.
   - Overriding one mapping does not mutate unrelated mappings.
   - `maybe_attach_keymaps(bufnr)` only binds keys when `commentry_diffview` is true.
   - Existing defaults still bind when no user remaps are provided.
   - Optional empty-string disable behavior remains scoped to `toggle_file_reviewed` and `next_unreviewed_file`.
3. Manual smoke checks:
   - Open a diffview review buffer and confirm configured mappings execute expected commands.
   - Open a non-diffview buffer and confirm commentry keymaps are not attached.
   - Verify command fallback for existing command-backed actions (`:Commentry toggle-file-reviewed`, `:Commentry next-unreviewed`, `:Commentry set-comment-type`, `:Commentry add-range-comment`) still works when keymaps are remapped.

---

## Out of Scope

- New comment actions beyond current seven-function surface.
- Per-project keymap profiles or automatic team sync.
- UI wizard for interactive keymap editing.
- Persistence/schema migrations related to keymaps.

---

## Open Questions

- [ ] Should v2 add explicit per-function disable semantics in addition to remap?
- [ ] Do we want a built-in `:Commentry help keymaps` quick-reference command?

## Multi-Model Review

**Reviewed:** 2026-02-27
**Models:** Codex
**Issues Found:** 5 (0 critical, 2 high, 2 medium, 1 low)

### Findings Addressed

| # | Issue | Resolution |
|---|---|
| 1 | Remap-only vs empty-string runtime behavior | Aligned spec with current selective disable behavior for `toggle_file_reviewed` and `next_unreviewed_file`. |
| 2 | Missing validation policy for invalid mappings | Added setup-time warning + runtime guard strategy with actionable feedback. |
| 3 | Command fallback criterion over-broad | Narrowed fallback criterion to existing command-backed actions. |
| 4 | Verification gap for keymap attach behavior | Added explicit automated checks for diffview-only attach, default preservation, and scoped optional-disable behavior. |
| 5 | Optional-key internal inconsistency | Unified wording across design/error handling/acceptance criteria. |

### Ambiguities Resolved

| Topic | Decision | Rationale |
|---|---|---|
| Empty-string mappings in v1 | Preserve selective disable for `toggle_file_reviewed` and `next_unreviewed_file`. | Matches current runtime behavior and avoids unnecessary breaking change. |
| Invalid mapping handling | Setup-time warn + runtime guard. | Balances user guidance with resilient runtime behavior. |
| Fallback command scope | Narrow to existing command surface. | Keeps v1 scope focused without adding unrelated command work. |

### Deferred Items

| Item | Rationale | Revisit When |
|---|---|---|
| Full per-function disable semantics | Keep v1 behavior scoped to existing selective disable support only. | v2 planning |

---

## Next Steps

- [ ] Commit reviewed spec artifacts.

---

## Appendix: Source Files

- `plans/keymaps/01-scope/questions.md`
- `plans/keymaps/01-scope/context.md`
- `plans/keymaps/01-scope/question-triage.md`
- `lua/commentry/config.lua`
- `lua/commentry/commands.lua`
