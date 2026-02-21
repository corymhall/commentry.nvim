# Diff Line Comments Design (Crew Canonical)

Date: 2026-02-21
Status: Completed
Feature: Diff line comments for local project changes
Branch intent: non-main/non-master (`001-diff-line-comments`)

## Purpose

Provide a Neovim-native review flow for local diffs where users can add, edit,
delete, persist, preview, and list draft comments attached to diff lines.

## Problem and Affected Users

Users reviewing local changes need line-anchored draft comments without leaving
Neovim. Before this effort, there was no integrated local-diff comment workflow.
Affected users are plugin users doing code review before publishing feedback.

## Scope

- Open local diff view and handle empty diffs.
- Add/edit/delete draft comments on diff lines.
- Persist and reload draft comments across restarts.
- Preview comment text on hover/cursor movement.
- List comments in a Snacks picker and jump to selected lines.
- Dependency health checks for required/optional integrations.

## Non-goals

- Submit/publish review comments to remote services.
- Network-backed sync.
- Replacing `diffview.nvim` with a custom diff renderer.

## Constraints and Invariants

- Neovim 0.9+.
- Offline-capable local-first storage.
- `diffview.nvim` is required for diff UI.
- Preserve line-anchored comment identity model.
- Preserve behavior from completed US1-US3 slices.

## Architecture Decisions

1. Reuse `diffview.nvim` for diff rendering and navigation.
2. Keep comment domain/storage decoupled from diff rendering.
3. Store drafts on local filesystem scoped to project root.
4. Prefer keyboard-first interactions in diff buffers.

## PlanRef Work Packages

| PlanRef | Slice | Files | Speckit Mapping | Status |
| --- | --- | --- | --- | --- |
| WP-F10 | Foundation scaffolding and core model/store/helpers | `lua/commentry/{store.lua,comments.lua,util.lua,diffview.lua,config.lua,commands.lua}` `tests/commentry_store_spec.lua` | T001-T009 | Completed |
| WP-F20 | US1 diff-open command and view behavior | `lua/commentry/{commands.lua,diffview.lua,init.lua}` `tests/commentry_util_spec.lua` | T010-T013,T030 | Completed |
| WP-F30 | US2 draft comment CRUD and marker rendering | `lua/commentry/{comments.lua,diffview.lua,commands.lua}` `tests/commentry_comments_spec.lua` | T014-T018,T031 | Completed |
| WP-F40 | US3 persistence load/save/reconcile | `lua/commentry/{comments.lua,diffview.lua,store.lua}` `tests/commentry_{comments,store}_spec.lua` | T019-T021,T032,T033 | Completed |
| WP-R10 | US4 hover preview rendering and cursor wiring | `lua/commentry/{diffview.lua,comments.lua}` `tests/commentry_diffview_spec.lua` | T025,T026,T034 | Completed |
| WP-R20 | US5 Snacks picker entries, command, health | `lua/commentry/{comments.lua,commands.lua,health.lua}` | T027,T028,T029 | Completed |
| WP-R30 | Tests for picker/command/health + manual validation notes | `tests/commentry_{comments,commands,health}_spec.lua` `docs/plans/2026-02-21-diff-line-comments-design.md` | T035,T024 | Completed |

## Decomposition Constraints for Bead Planning

- One independently verifiable behavior per task.
- Each task must include exact files/symbols and explicit non-goals.
- Each task must define one verification command and expected success signal.
- Required review gates per task:
  - Spec compliance gate.
  - Code quality gate.

## Verification Expectations

Global verification command:
- Run: `./scripts/test`
- Expect: all test cases pass, no failures.

Slice-specific verification:
- WP-R10: add/extend tests validating preview shown only on commented lines.
- WP-R20: add/extend tests validating picker entry build and command dispatch.
- WP-R30: add/extend tests validating health behavior and update manual notes.

## Acceptance Criteria (Observable)

- Cursor on a commented diff line shows preview text.
- Cursor on a non-commented line shows no preview.
- Running list-comments opens a Snacks picker of jumpable draft comments for the current diff file/side.
- Selecting a picker item moves cursor to the target diff line.
- Existing add/edit/delete/persist behavior remains intact.
- Full suite passes via `./scripts/test`.

## Manual Validation Outcomes (2026-02-21)

- Environment: Neovim 0.9+, local repo with uncommitted changes, `diffview.nvim` installed.
- Hover preview:
  - Opened diff with `:Commentry open`.
  - Added draft comment on current diff line with `mc`.
  - Moved cursor away and back to commented line.
  - Observed inline hover preview render on commented line only.
  - Moved cursor to non-commented line and observed preview clear immediately.
- List comments:
  - Ran `:Commentry list-comments` with Snacks installed.
  - Observed picker entries formatted with file, line, side, and body preview.
  - Selected an entry for current diff file/side and observed cursor jump to target line.
  - Confirmed non-current-context comments are not listed (only jumpable entries shown).
  - In environment without Snacks, observed clear command error and health warning.
- Regression confidence:
  - Verified no observed regressions in add/edit/delete/persist during above flow.
  - Automated verification confirmed via `./scripts/test` passing.

## Risks and Escalation Triggers

- Escalate if hover behavior requires invasive diffview internals not already used.
- Escalate if Snacks API assumptions are incompatible with target environments.
- Escalate if remaining tasks force broad rewrites of completed US1-US3 slices.

## Integration and Execution Policy

- Planning and execution must not occur on `main`/`master`.
- Planning handoff must create/register integration branch via:
  - `gt mq integration create <epic-id>`
  - `gt mq integration status <epic-id>`
- Execution wave must use convoy strategy:
  - `--owned --merge=local`

## Provenance (Legacy Speckit Archive)

Archived source artifacts:
- `docs/archive/speckit/001-diff-line-comments/spec.md`
- `docs/archive/speckit/001-diff-line-comments/plan.md`
- `docs/archive/speckit/001-diff-line-comments/tasks.md`
- `docs/archive/speckit/001-diff-line-comments/research.md`
- `docs/archive/speckit/001-diff-line-comments/data-model.md`
- `docs/archive/speckit/001-diff-line-comments/contracts/commentry-review.yaml`
- `docs/archive/speckit/001-diff-line-comments/quickstart.md`
- `docs/archive/speckit/001-diff-line-comments/checklists/requirements.md`
- `docs/archive/speckit/.specify/*`

Migration reference:
- Migrated from Speckit on 2026-02-21 from commit `3d1ab91`.
