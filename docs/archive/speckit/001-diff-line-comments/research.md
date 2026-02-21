# Research: Diff Line Comments

## Decision 1: Diff view implementation reuse

**Decision**: Use `diffview.nvim` as a required dependency for the diff UI.

**Rationale**: `diffview.nvim` already provides robust diff rendering and
navigation in Neovim. `octo.nvim` demonstrates how to reuse those components for
PR-style review. Making it a hard dependency removes the need to maintain a
custom diff implementation.

**Alternatives considered**:
- Implement custom diff UI from scratch (higher cost, more bugs).
- Hard dependency on `diffview.nvim` (limits adoption).
- Copy only `octo.nvim` comment UX without diff reuse (misses proven diff UX).

## Decision 2: Comment interaction model

**Decision**: Start with `octo.nvim`-style line comment interactions (keymap to
add/edit/delete drafts), but keep the comment storage and UI decoupled so we can
iterate independently of `octo.nvim` internals.

**Rationale**: The user wants the comment flow inspired by `octo.nvim` but is
open to changes. A decoupled model lets us iterate while maintaining a familiar
UX.

**Alternatives considered**:
- Reuse `octo.nvim` comment storage directly (tight coupling).
- Build a novel UI without existing patterns (higher UX risk).
