# Implementation Plan: Diff Line Comments

**Branch**: `001-diff-line-comments` | **Date**: 2025-12-31 | **Spec**: /Users/chall/plugins/commentry.nvim/specs/001-diff-line-comments/spec.md
**Input**: Feature specification from `/specs/001-diff-line-comments/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Deliver a Neovim diff view for local changes with line-anchored draft comments
that can be added, edited, deleted, and persisted. The diff UI is provided by
`diffview.nvim` as a hard dependency; comment interactions mirror `octo.nvim`
UX while keeping storage decoupled.

## Technical Context

**Language/Version**: Lua (Neovim 0.9+)  
**Primary Dependencies**: Neovim runtime, `mini.test` (tests), `diffview.nvim`
for diff UI  
**Storage**: Local filesystem (project-scoped draft comment store)  
**Testing**: `mini.test` via `tests/minit.lua`  
**Target Platform**: Neovim on macOS/Linux/Windows  
**Project Type**: Single Neovim plugin  
**Performance Goals**: Diff view opens in under 1s for moderate changes; comment
create/edit operations complete under 100ms  
**Constraints**: Offline-capable, no network calls by default  
**Scale/Scope**: Dozens of files and thousands of diff lines per review

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Review-first workflow preserved (diff -> comment -> submit -> export).
- Line-accurate annotation model defined (file path + base/head line reference).
- Local-first artifacts (text-based, diff-friendly, no network by default).
- Neovim-native UX (buffers/extmarks/virtual text, keyboard-first).
- Test coverage planned for data model and export behavior changes.

## Phase 0: Research

- Created /Users/chall/plugins/commentry.nvim/specs/001-diff-line-comments/research.md
  with decisions on diff reuse and comment interaction model.
- All clarifications resolved; no outstanding questions.

## Phase 1: Design & Contracts

- Created /Users/chall/plugins/commentry.nvim/specs/001-diff-line-comments/data-model.md
  defining Diff View, Draft Comment, Comment Thread, and Comment Store.
- Created /Users/chall/plugins/commentry.nvim/specs/001-diff-line-comments/contracts/commentry-review.yaml
  for diff and draft comment actions.
- Created /Users/chall/plugins/commentry.nvim/specs/001-diff-line-comments/quickstart.md
  for the expected user flow.
- Updated agent context using the repository script.

## Constitution Re-check (Post-Design)

- All gates remain satisfied; design aligns with review-first workflow and
  local-first artifacts. No exceptions required.

## Project Structure

### Documentation (this feature)

```text
specs/001-diff-line-comments/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/
│   └── commentry-review.yaml
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
lua/commentry/
├── commands.lua
├── config.lua
├── docs.lua
├── health.lua
├── init.lua
└── util.lua

tests/
├── init_spec.lua
└── minit.lua
```

**Structure Decision**: Single Neovim plugin under `lua/commentry/` with tests in
`tests/`.

## Complexity Tracking

No constitution violations identified.
