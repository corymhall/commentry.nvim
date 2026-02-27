# Beads Draft: keymaps

**Generated:** 2026-02-27
**Source:** plans/keymaps/03-plan/plan.md
**Plan review status:** Reviewed

---

## Structure

### Feature Epic: keymaps

**Type:** epic
**Priority:** P1
**Description:** Deliver explicit, test-backed, and documented per-function keymap configuration for Commentry diffview review flows while preserving existing defaults, scoped disable semantics, and command parity constraints.

---

### Sub-Epic: Phase 1 — Config Contract & Validation

**Type:** epic
**Priority:** P1
**Parent:** Feature epic
**Description:** Stabilize the setup-time keymap contract so all seven mappings are explicit, defaults are preserved, and invalid/scoped-empty values are handled predictably.

#### Issue: Confirm and lock keymap schema/default invariants (1.1)

**Type:** task
**Priority:** P1
**Parent:** Phase 1
**Dependencies:** None
**Description:**
Ensure `commentry.Keymaps` and `defaults.keymaps` explicitly contain all seven supported actions with stable defaults in `lua/commentry/config.lua`. Preserve keys `add_comment`, `add_range_comment`, `edit_comment`, `delete_comment`, `set_comment_type`, `toggle_file_reviewed`, `next_unreviewed_file`. Maintain deep-merge behavior via `M.setup(opts)` and enforce invariants/normalization without changing default behavior.

**Acceptance Criteria:**
- [ ] Setup leaves all seven defaults present when user supplies no keymap overrides.
- [ ] Partial override of one mapping preserves all unrelated mappings.

#### Issue: Implement setup-time keymap validation + scoped-empty warnings (1.2)

**Type:** task
**Priority:** P1
**Parent:** Phase 1
**Dependencies:** Task 1.1 (Confirm and lock keymap schema/default invariants)
**Description:**
Add setup-time validation messaging in `lua/commentry/config.lua` for invalid keymap values and unsupported empty-string disables on remap-only actions. Validation matrix: `toggle_file_reviewed` and `next_unreviewed_file` may use `""` to disable; all other actions must use non-empty strings. Warning messages must include the action key, the provided value, and the allowed shape (`string` and, where relevant, non-empty).

**Acceptance Criteria:**
- [ ] Unsupported empty-string values trigger setup warning.
- [ ] Invalid non-empty keymap values (wrong type or unknown mapping format) trigger setup warnings that name action key, invalid value, and expected value shape.
- [ ] Runtime remains resilient (plugin still loads with warnings).
- [ ] Warning behavior is explicitly verifiable by tests stubbing warning emission and asserting warning payload contents.

---

### Sub-Epic: Phase 2 — Runtime Attachment Behavior

**Type:** epic
**Priority:** P2
**Parent:** Feature epic
**Description:** Ensure diffview-only, buffer-local, idempotent keymap attachment continues to work with the validated config contract.

#### Issue: Harden `maybe_attach_keymaps` behavior with explicit scoped rules (2.1)

**Type:** task
**Priority:** P2
**Parent:** Phase 2
**Dependencies:** Task 1.2 (Implement setup-time keymap validation + scoped-empty warnings)
**Description:**
Update `lua/commentry/commands.lua` so `maybe_attach_keymaps` applies remaps for all seven supported actions (`add_comment`, `add_range_comment`, `edit_comment`, `delete_comment`, `set_comment_type`, `toggle_file_reviewed`, `next_unreviewed_file`), preserves fallback behavior (`add_range_comment` falls back to `add_comment` if unset), preserves selective empty-disable scope for only two actions, keeps diffview gating via `commentry_diffview`, and maintains idempotence via `vim.b[bufnr].commentry_keymaps`.

**Acceptance Criteria:**
- [ ] Keymaps attach only in commentry diffview buffers.
- [ ] Keymaps are attached once per buffer lifecycle (no duplicate mappings).
- [ ] Empty-disable remains accepted only for `toggle_file_reviewed` and `next_unreviewed_file`; other actions ignore empty disable and keep effective mapping.

#### Issue: Confirm command fallback claims remain accurate (2.2)

**Type:** task
**Priority:** P2
**Parent:** Phase 2
**Dependencies:** Task 2.1 (Harden `maybe_attach_keymaps` behavior with explicit scoped rules)
**Description:**
Audit command registrations in `lua/commentry/commands.lua` and ensure docs/plan claims only reference command-backed actions already in the `:Commentry` registry (`toggle-file-reviewed`, `next-unreviewed`, `set-comment-type`, `add-range-comment`). Use the registry table/function in `lua/commentry/commands.lua` as source of truth and record the exact command entries used as fallback evidence. Avoid adding new command surfaces unless explicitly required by spec updates.

**Acceptance Criteria:**
- [ ] Runtime and docs claims align with actual `:Commentry` subcommand registry entries.
- [ ] Verification records which registry entries back each documented fallback claim.
- [ ] No new `:Commentry` subcommands are added or removed while implementing this task.

---

### Sub-Epic: Phase 3 — Regression Coverage

**Type:** epic
**Priority:** P2
**Parent:** Feature epic
**Description:** Add focused automated tests that lock required keymap behavior and prevent regressions.

#### Issue: Add config contract tests for defaults and partial overrides (3.1)

**Type:** task
**Priority:** P2
**Parent:** Phase 3
**Dependencies:** Task 1.2 (Implement setup-time keymap validation + scoped-empty warnings)
**Description:**
Expand `tests/commentry_config_spec.lua` to assert all seven defaults exist, single-entry overrides do not mutate unrelated mappings, warnings fire for unsupported empty-string usage, and warnings fire for invalid non-empty keymap values.

**Acceptance Criteria:**
- [ ] Tests assert all seven key names exist in merged config after `setup({})`.
- [ ] Tests assert overriding one keymap leaves each of the other six defaults unchanged.
- [ ] Tests assert empty-string on a non-disable action emits warning with action key + allowed shape.
- [ ] Tests assert invalid type (for example boolean/table) emits warning with action key + provided value.

#### Issue: Add attach-path tests for diffview-only, idempotence, and selective disable (3.2)

**Type:** task
**Priority:** P2
**Parent:** Phase 3
**Dependencies:** Task 2.1 (Harden `maybe_attach_keymaps` behavior with explicit scoped rules)
**Description:**
Add targeted tests in `tests/commentry_commands_spec.lua` for non-diffview no-attach behavior, one-time attach per diffview buffer, selective disable support only for `toggle_file_reviewed` and `next_unreviewed_file`, and default binding behavior when no remaps are configured.

**Acceptance Criteria:**
- [ ] Automated tests verify all acceptance criteria tied to attachment behavior.
- [ ] Tests explicitly stub/restore Neovim APIs and do not depend on test execution order.

#### Issue: Run full suite and resolve regressions (3.3)

**Type:** task
**Priority:** P2
**Parent:** Phase 3
**Dependencies:** Task 3.1 (Add config contract tests for defaults and partial overrides), Task 3.2 (Add attach-path tests for diffview-only, idempotence, and selective disable)
**Description:**
Run `./scripts/test` and resolve failures introduced by this feature in `lua/commentry/config.lua`, `lua/commentry/commands.lua`, `tests/commentry_config_spec.lua`, and `tests/commentry_commands_spec.lua` only. Use existing mini.test + luassert patterns.

**Acceptance Criteria:**
- [ ] `./scripts/test` passes.

---

### Sub-Epic: Phase 4 — Docs & Verification

**Type:** epic
**Priority:** P2
**Parent:** Feature epic
**Description:** Publish accurate user-facing docs and verify behavior manually and via test suite.

#### Issue: Document keymap configuration matrix and examples (4.1)

**Type:** task
**Priority:** P2
**Parent:** Phase 4
**Dependencies:** Task 2.2 (Confirm command fallback claims remain accurate)
**Description:**
Update `README.md` and `doc/commentry.txt` to list configurable functions, defaults, override examples, selective empty-disable scope, and accurate fallback expectations for command-backed actions.

**Acceptance Criteria:**
- [ ] Docs clearly explain configuration behavior and fallback expectations.
- [ ] Docs do not claim unsupported disable/command behavior.

#### Issue: Final verification sweep (automated + manual smoke checks) (4.2)

**Type:** task
**Priority:** P2
**Parent:** Phase 4
**Dependencies:** Task 3.3 (Run full suite and resolve regressions)
**Description:**
Run automated tests (`./scripts/test`) and perform manual checks: keymaps active in diffview buffers, absent in non-diffview buffers, and command-backed fallback commands still operate. Capture evidence in `plans/keymaps/04-beads/verification-evidence.md`, including the test command output summary and the command-registry proof source in `lua/commentry/commands.lua`.

**Acceptance Criteria:**
- [ ] `plans/keymaps/04-beads/verification-evidence.md` contains automated test result summary.
- [ ] `plans/keymaps/04-beads/verification-evidence.md` contains manual diffview/non-diffview checks and fallback verification notes tied to command registry entries.

---

## Dependencies

| Blocked Task | Blocked By | Reason |
|-------------|------------|--------|
| Task 1.2 (Implement setup-time keymap validation + scoped-empty warnings) | Task 1.1 (Confirm and lock keymap schema/default invariants) | Validation depends on finalized keymap schema/default invariants. |
| Task 2.1 (Harden `maybe_attach_keymaps` behavior with explicit scoped rules) | Task 1.2 (Implement setup-time keymap validation + scoped-empty warnings) | Runtime attach assumptions depend on setup-time validation semantics. |
| Task 2.2 (Confirm command fallback claims remain accurate) | Task 2.1 (Harden `maybe_attach_keymaps` behavior with explicit scoped rules) | Fallback parity audit must match finalized attach/runtime behavior. |
| Task 3.1 (Add config contract tests for defaults and partial overrides) | Task 1.2 (Implement setup-time keymap validation + scoped-empty warnings) | Tests require completed validation behavior. |
| Task 3.2 (Add attach-path tests for diffview-only, idempotence, and selective disable) | Task 2.1 (Harden `maybe_attach_keymaps` behavior with explicit scoped rules) | Attach-path tests require finalized attach logic. |
| Task 3.3 (Run full suite and resolve regressions) | Task 3.1 (Add config contract tests for defaults and partial overrides) | Full suite run must include completed config regression tests. |
| Task 3.3 (Run full suite and resolve regressions) | Task 3.2 (Add attach-path tests for diffview-only, idempotence, and selective disable) | Full suite run must include completed attach-path regression tests. |
| Task 4.1 (Document keymap configuration matrix and examples) | Task 2.2 (Confirm command fallback claims remain accurate) | Docs must reflect verified command fallback surface. |
| Task 4.2 (Final verification sweep (automated + manual smoke checks)) | Task 3.3 (Run full suite and resolve regressions) | Final verification requires passing automated baseline. |

**Reading this table:** each row means the "Blocked Task" cannot start until
"Blocked By" completes. This matches `bd dep add` argument order:
`bd dep add <blocked-task-id> <blocked-by-id>`.

## Coverage Matrix

| Plan Task | Bead Title | Sub-Epic |
|-----------|------------|----------|
| 1.1 Confirm and lock keymap schema/default invariants | Confirm and lock keymap schema/default invariants | Phase 1: Config Contract & Validation |
| 1.2 Implement setup-time keymap validation + scoped-empty warnings | Implement setup-time keymap validation + scoped-empty warnings | Phase 1: Config Contract & Validation |
| 2.1 Harden `maybe_attach_keymaps` behavior with explicit scoped rules | Harden `maybe_attach_keymaps` behavior with explicit scoped rules | Phase 2: Runtime Attachment Behavior |
| 2.2 Confirm command fallback claims remain accurate | Confirm command fallback claims remain accurate | Phase 2: Runtime Attachment Behavior |
| 3.1 Add config contract tests for defaults and partial overrides | Add config contract tests for defaults and partial overrides | Phase 3: Regression Coverage |
| 3.2 Add attach-path tests for diffview-only, idempotence, and selective disable | Add attach-path tests for diffview-only, idempotence, and selective disable | Phase 3: Regression Coverage |
| 3.3 Run full suite and resolve regressions | Run full suite and resolve regressions | Phase 3: Regression Coverage |
| 4.1 Document keymap configuration matrix and examples | Document keymap configuration matrix and examples | Phase 4: Docs & Verification |
| 4.2 Final verification sweep (automated + manual smoke checks) | Final verification sweep (automated + manual smoke checks) | Phase 4: Docs & Verification |

**Plan tasks:** 9
**Beads mapped:** 9
**Coverage:** 100%

## Cross-Cutting Coverage

- Error Handling: Captured in Task 1.2 acceptance criteria and description (setup-time warnings for unsupported empty values and invalid mappings, resilient runtime behavior).
- Testing Strategy: Captured in Phase 3 tasks (3.1, 3.2, 3.3) with deterministic automated coverage and full suite execution.
- Migration: No migration needed. Keymap behavior is runtime configuration only; no store schema or persisted data contract changes.

## Summary

- Feature epic: 1
- Sub-epics (phases): 4
- Issues (tasks): 9
- Blocker dependencies: 9
- Items ready immediately (no blockers): 1
