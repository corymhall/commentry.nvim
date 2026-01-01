---

description: "Task list template for feature implementation"
---

# Tasks: Diff Line Comments

**Input**: Design documents from `/specs/001-diff-line-comments/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: The examples below include test tasks. Tests are REQUIRED when the constitution or spec mandates them; otherwise optional.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Single project**: `lua/commentry/`, `tests/` at repository root
- Paths shown below assume single project - adjust based on plan.md structure

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Create feature module skeletons in lua/commentry/diffview.lua, lua/commentry/comments.lua, lua/commentry/store.lua
- [X] T002 [P] Add feature configuration defaults in lua/commentry/config.lua
- [X] T003 [P] Add feature command entry point wiring in lua/commentry/commands.lua

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Implement comment store read/write and schema validation in lua/commentry/store.lua
- [X] T005 Implement comment identity and line anchor model in lua/commentry/comments.lua
- [X] T006 Implement diff line anchor mapping helpers in lua/commentry/util.lua
- [X] T007 Implement diffview integration adapter in lua/commentry/diffview.lua
- [X] T008 Add persistence path resolution scoped to project root in lua/commentry/store.lua
- [X] T009 Add tests for store persistence and line anchors in tests/commentry_store_spec.lua

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Open diff for local changes (Priority: P1) 🎯 MVP

**Goal**: Open a diff view for local changes to provide a review surface.

**Independent Test**: From a project with local changes, a user can open the diff view and see changed files and lines.

### Implementation for User Story 1

- [X] T010 [US1] Implement diff view open command in lua/commentry/commands.lua
- [X] T011 [US1] Implement diff view open logic and buffer setup in lua/commentry/diffview.lua
- [X] T012 [US1] Add empty-state handling for no local changes in lua/commentry/diffview.lua
- [X] T013 [US1] Wire command to main entry point in lua/commentry/init.lua

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Add and manage draft comments (Priority: P1)

**Goal**: Add, edit, and delete draft comments on diff lines with keymaps.

**Independent Test**: In an open diff view, a user can add a draft comment to a line, edit it, and delete it without leaving the view.

### Implementation for User Story 2

- [ ] T014 [US2] Implement add-comment action and input flow in lua/commentry/comments.lua
- [ ] T015 [US2] Implement edit-comment action in lua/commentry/comments.lua
- [ ] T016 [US2] Implement delete-comment action in lua/commentry/comments.lua
- [ ] T017 [US2] Render draft comment markers for diff lines in lua/commentry/diffview.lua
- [ ] T018 [US2] Register keymaps for add/edit/delete in lua/commentry/commands.lua

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Persist draft comments (Priority: P2)

**Goal**: Preserve draft comments across editor restarts and diff re-open.

**Independent Test**: After restarting the editor, previously created draft comments reappear on the same diff lines.

### Implementation for User Story 3

- [ ] T019 [US3] Load draft comments on diff view open in lua/commentry/diffview.lua
- [ ] T020 [US3] Save draft comments on add/edit/delete actions in lua/commentry/comments.lua
- [ ] T021 [US3] Reconcile missing or moved lines on reload in lua/commentry/comments.lua

**Checkpoint**: All user stories should now be independently functional

---

## Phase N: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T022 [P] Update README usage docs in README.md
- [X] T023 [P] Add health check for diffview dependency in lua/commentry/health.lua
- [ ] T024 [P] Manual test pass and cleanup notes in specs/001-diff-line-comments/quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P1)**: Can start after Foundational (Phase 2) - Depends on US1 diff view in practice
- **User Story 3 (P2)**: Can start after Foundational (Phase 2) - Depends on US2 comment actions

### Within Each User Story

- Data model and store tasks before UI rendering tasks
- Comment actions before persistence integration
- Story complete before moving to next priority

### Parallel Opportunities

- Setup tasks T002 and T003 can run in parallel
- Foundational tasks T004, T005, T006 can run in parallel
- Polish tasks can run in parallel after core stories are done

---

## Parallel Example: User Story 2

```bash
Task: "Implement add-comment action and input flow in lua/commentry/comments.lua"
Task: "Register keymaps for add/edit/delete in lua/commentry/commands.lua"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test User Story 1 independently
5. Demo diff view open flow

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Demo MVP
3. Add User Story 2 → Test independently
4. Add User Story 3 → Test independently
5. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1
   - Developer B: User Story 2
   - Developer C: User Story 3
3. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
