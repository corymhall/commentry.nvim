# keymaps - Implementation Plan

**Created:** 2026-02-27
**Status:** Draft
**Source Spec:** plans/keymaps/02-spec/spec.md

---

## Overview

This plan delivers explicit, test-backed, and documented per-function keymap configuration for Commentry review flows in diffview buffers. The implementation stays inside the current architecture: keymap contract/defaults in `lua/commentry/config.lua`, runtime attachment in `lua/commentry/commands.lua`, and action behavior in `lua/commentry/comments.lua`.

The approach is intentionally additive. We preserve all seven default mappings, preserve current selective empty-string disable behavior for `toggle_file_reviewed` and `next_unreviewed_file`, and keep command fallback claims scoped to actions already exposed via `:Commentry` subcommands. We avoid persistence/schema changes and avoid adding unrelated runtime subsystems.

Delivery is phased to maximize parallelism after shared foundations are set. Phase 1 locks the config contract and validation behavior. Phase 2 hardens attach/runtime behavior in diffview buffers. Phase 3 adds regression coverage. Phase 4 updates docs and performs final verification.

---

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Keymap contract location | `lua/commentry/config.lua` (`commentry.Keymaps`, `defaults.keymaps`, `M.setup`) | Existing contract boundary already lives here; keeps setup-time behavior centralized. |
| Runtime keymap binding location | `lua/commentry/commands.lua` (`maybe_attach_keymaps`) | Existing diffview-only, buffer-local attach path and idempotency guard already exist here. |
| Action execution layer | Keep all action behavior in `lua/commentry/comments.lua` | Maintains separation: keymaps trigger actions but do not alter domain logic. |
| Selective disable semantics | Keep v1 behavior: empty-string disable only for `toggle_file_reviewed` and `next_unreviewed_file` | Matches reviewed spec and current runtime behavior; avoids broad behavior change. |
| Invalid keymap handling | Setup-time warnings + runtime guard behavior (no silent failure) | Aligns with spec error-handling guidance and existing util messaging patterns. |
| Command fallback scope | Limit to command-backed actions already in `:Commentry` registry | Spec narrowed fallback to existing command surface; prevents scope creep. |
| Persistence strategy | No persistence/model changes | Keymaps are runtime configuration only; `store.lua` schema remains untouched. |

---

## Implementation Contracts

- `lua/commentry/config.lua` remains the single contract for keymap schema/defaults and setup-time validation.
- `lua/commentry/commands.lua` (`maybe_attach_keymaps`) remains the single runtime attach path for diffview-only/idempotent bindings and fallback behavior.
- `README.md` and `doc/commentry.txt` remain the user-facing contract for keymap defaults, remaps, and selective disable semantics.

---

## Phased Delivery

### Phase 1: Config Contract & Validation

**Objective:** Stabilize setup-time contract so all seven mappings are explicit, defaults are preserved, and invalid/scoped-empty values are handled predictably.
**Prerequisites:** None (first phase)

#### Tasks

**1.1 Confirm and lock keymap schema/default invariants**
- **What:** Ensure `commentry.Keymaps` and `defaults.keymaps` explicitly contain all seven supported actions with stable defaults.
- **Files:**
  - Modify: `lua/commentry/config.lua` — enforce invariant checks/normalization without changing default behavior.
- **Key details:**
  - Preserve keys: `add_comment`, `add_range_comment`, `edit_comment`, `delete_comment`, `set_comment_type`, `toggle_file_reviewed`, `next_unreviewed_file`.
  - Maintain deep-merge behavior via `M.setup(opts)`.
- **Acceptance criteria:**
  - [ ] Setup leaves all seven defaults present when user supplies no keymap overrides.
  - [ ] Partial override of one mapping preserves all unrelated mappings.
- **Dependencies:** None

**1.2 Implement setup-time keymap validation + scoped-empty warnings**
- **What:** Add setup-time validation messaging for invalid keymap values and unsupported empty-string disable on remap-only actions.
- **Files:**
  - Modify: `lua/commentry/config.lua` — validation and warning logic.
  - Modify: `lua/commentry/util.lua` (only if needed for reusable warning helper behavior).
- **Key details:**
  - Empty-string allowed only for `toggle_file_reviewed`, `next_unreviewed_file`.
  - Other invalid values warn with actionable message; do not silently fail.
- **Acceptance criteria:**
  - [ ] Unsupported empty-string values trigger setup warning.
  - [ ] Invalid non-empty keymap values (wrong type/unsupported value) trigger actionable setup warnings.
  - [ ] Runtime remains resilient (plugin still loads with warnings).
  - [ ] Warning behavior is explicitly verifiable (no silent failure path for invalid mappings).
- **Dependencies:** Task 1.1

#### Phase 1 Exit Criteria
- [ ] All seven keymap defaults are explicit and preserved.
- [ ] Setup-time validation/warning behavior matches spec.

---

### Phase 2: Runtime Attachment Behavior

**Objective:** Ensure diffview-only, buffer-local, idempotent mapping attachment continues to work with the validated config contract.
**Prerequisites:** Phase 1 — stable keymap contract and validation behavior

#### Tasks

**2.1 Harden `maybe_attach_keymaps` behavior with explicit scoped rules**
- **What:** Ensure attach logic applies remaps for all supported actions, preserves fallback behavior, and respects selective disable scope.
- **Files:**
  - Modify: `lua/commentry/commands.lua` — keymap attachment logic.
- **Key details:**
  - Keep diffview gating via `commentry_diffview` buffer marker.
  - Keep idempotence guard via `vim.b[bufnr].commentry_keymaps`.
  - Preserve fallback: `add_range_comment` falls back to `add_comment` if unset.
  - Preserve selective empty disable only for two supported actions.
- **Acceptance criteria:**
  - [ ] Keymaps attach only in commentry diffview buffers.
  - [ ] Keymaps are attached once per buffer lifecycle (no duplicate mappings).
  - [ ] Unsupported disable behavior is not silently introduced for other actions.
- **Dependencies:** Task 1.2

**2.2 Confirm command fallback claims remain accurate**
- **What:** Audit command registrations and ensure docs/plan only claim fallback for command-backed actions.
- **Files:**
  - Modify: `lua/commentry/commands.lua` (only if corrections are needed to maintain parity).
- **Key details:**
  - Command-backed actions are exactly: `toggle-file-reviewed`, `next-unreviewed`, `set-comment-type`, `add-range-comment`.
  - Treat `:Commentry` subcommand registration in `lua/commentry/commands.lua` as source of truth for fallback claims.
  - Do not expand scope by adding new command surfaces unless required by updated spec.
- **Acceptance criteria:**
  - [ ] Runtime and docs claims align with actual `:Commentry` subcommand registry entries.
  - [ ] Verification records which registry entries back each documented fallback claim.
  - [ ] No unintended command-surface regressions.
- **Dependencies:** Task 2.1

#### Phase 2 Exit Criteria
- [ ] Diffview-only + idempotent attach behavior is preserved with new validation assumptions.
- [ ] Runtime keymap behavior aligns with selective-disable and fallback requirements.

---

### Phase 3: Regression Coverage

**Objective:** Add focused automated tests that lock behavior required by the spec and prevent regressions.
**Prerequisites:** Phase 2 — runtime behavior finalized

#### Tasks

**3.1 Add config contract tests for defaults and partial overrides**
- **What:** Expand config tests for seven-key defaults and override isolation.
- **Files:**
  - Modify: `tests/commentry_config_spec.lua`
- **Key details:**
  - Assert all seven defaults exist.
  - Assert changing one keymap entry does not mutate others.
  - Assert validation warnings for unsupported empty-string usage.
  - Assert validation warnings for invalid non-empty keymap values.
- **Acceptance criteria:**
  - [ ] Tests fail before behavior and pass after behavior.
  - [ ] Assertions cover defaults, partial override, and validation scope.
- **Dependencies:** Task 1.2

**3.2 Add attach-path tests for diffview-only, idempotence, and selective disable**
- **What:** Add targeted tests around mapping attachment behavior.
- **Files:**
  - Modify: `tests/commentry_commands_spec.lua`
- **Key details:**
  - Assert no keymap attachment when not in diffview.
  - Assert single attachment per diffview buffer.
  - Assert selective disable for `toggle_file_reviewed` and `next_unreviewed_file` only.
  - Assert default binding behavior when no remaps are configured.
- **Acceptance criteria:**
  - [ ] Automated tests verify all acceptance criteria tied to attachment behavior.
  - [ ] Tests are deterministic and isolated with existing test stubbing patterns.
- **Dependencies:** Task 2.1

**3.3 Run full suite and resolve regressions**
- **What:** Run `./scripts/test`, then fix any test failures introduced by this feature work.
- **Files:**
  - Modify: impacted test/runtime files only if failures require adjustments.
- **Key details:**
  - Use existing mini.test + luassert patterns.
- **Acceptance criteria:**
  - [ ] `./scripts/test` passes.
- **Dependencies:** Tasks 3.1, 3.2

#### Phase 3 Exit Criteria
- [ ] Regression tests cover spec-critical keymap behavior.
- [ ] Full test suite passes.

---

### Phase 4: Docs & Verification

**Objective:** Ship clear user-facing docs and confirm end-to-end behavior manually and via tests.
**Prerequisites:** Phase 3 — behavior and tests stable

#### Tasks

**4.1 Document keymap configuration matrix and examples**
- **What:** Update docs to list configurable functions, defaults, override examples, and scoped disable semantics.
- **Files:**
  - Modify: `README.md`
  - Modify: `doc/commentry.txt`
- **Key details:**
  - Include setup examples for remapping one action and multiple actions.
  - Explicitly call out selective empty disable scope (two actions only).
- **Acceptance criteria:**
  - [ ] Docs clearly explain configuration behavior and fallback expectations.
  - [ ] Docs do not claim unsupported disable/command behavior.
- **Dependencies:** Task 2.2

**4.2 Final verification sweep (automated + manual smoke checks)**
- **What:** Run automated tests and perform manual diffview/non-diffview checks.
- **Files:**
  - No code changes expected unless issues are found.
- **Key details:**
  - Automated: `./scripts/test`.
  - Manual: diffview buffer keymaps active; non-diffview keymaps absent; command-backed fallback commands still operate.
- **Acceptance criteria:**
  - [ ] Automated and manual verification evidence captured.
- **Dependencies:** Tasks 3.3, 4.1

#### Phase 4 Exit Criteria
- [ ] Docs are updated and accurate.
- [ ] Feature is verified against acceptance criteria.

---

## Cross-Cutting Concerns

### Error Handling
- Use existing `lua/commentry/util.lua` messaging (`warn`/`error`) for setup/runtime feedback.
- Setup-time warnings for unsupported keymap values (including unsupported empty disables and invalid non-empty values).
- Keep runtime guards in attach/action paths, and ensure invalid mapping paths surface actionable user feedback instead of silent skips.

### Testing Strategy
- Extend `tests/commentry_config_spec.lua` for contract/default/override/validation behavior.
- Extend `tests/commentry_commands_spec.lua` for attach-path behavior.
- Run full suite via `./scripts/test`.
- Preserve existing testing conventions: module stubbing, `before_each`/`after_each`, deterministic assertions.

### Migration
No migration needed. Keymap behavior is runtime configuration only; no store schema or persisted data contract changes.

---

## Technical Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Validation logic accidentally breaks existing valid setups | M | H | Add config tests for default config and partial overrides before/with changes. |
| Attach logic regresses diffview-only scoping | M | H | Add explicit non-diffview vs diffview attach tests in `tests/commentry_commands_spec.lua`. |
| Selective disable semantics unintentionally broaden | M | M | Enforce/verify scoped-empty behavior in setup validation and tests. |
| Docs drift from runtime behavior | M | M | Couple docs updates with command/attach audit and final verification checklist. |
| Hidden behavior dependency in optional integrations | L | M | Keep changes isolated to config/commands keymap paths and preserve `pcall`/graceful patterns. |

---

## Spec Coverage Matrix

This matrix is the canonical spec-to-plan map for implementation. `plan-review.md`
is a point-in-time audit and should reference this matrix rather than duplicate it.

| Spec Section | Plan Section | Phase |
|-------------|-------------|-------|
| Overview | Overview; Architecture Decisions | 1-4 |
| Scope Questions & Answers | Architecture Decisions; Phase 1.2; Phase 2.2; Phase 4.1 | 1,2,4 |
| Design: Architecture Overview | Architecture Decisions; Phase 1; Phase 2 | 1,2 |
| Design: Components | Implementation Contracts; Phase 1; Phase 2 | 1,2 |
| Design: Data Model | Architecture Decisions (Persistence strategy); Migration | 1-4 |
| Design: User Flows | Phase 2.1; Phase 4.2 | 2,4 |
| Design: Error Handling | Cross-Cutting Concerns: Error Handling; Phase 1.2 | 1 |
| Design: Integration Points | Appendix: Key File Paths; Tasks across Phases 1-4 | 1-4 |
| Acceptance Criteria (1-8) | Tasks 1.1, 1.2, 2.1, 2.2, 3.1, 3.2, 4.1, 4.2 | 1-4 |
| Verification Checklist | Phase 3.3; Phase 4.2 | 3,4 |
| Out of Scope | Architecture Decisions (fallback scope/persistence); task scoping notes | 1-4 |
| Open Questions | Deferred to future; no implementation in this plan | N/A |
| Multi-Model Review: Findings Addressed | Phase 1.2, Phase 2.2, Phase 3.1, Phase 3.2 | 1-3 |
| Multi-Model Review: Ambiguities Resolved | Architecture Decisions; Phase 1.2; Phase 2.1 | 1,2 |
| Multi-Model Review: Deferred Items | Out-of-scope controls; future work notes | N/A |
| Next Steps | Phase 4 completion and commit task downstream | 4 |
| Appendix: Source Files | Appendix: Key File Paths | 1-4 |

---

## Appendix: Key File Paths

### New Files
| Path | Phase | Purpose |
|------|-------|---------|
| None expected | N/A | Implementation is expected to modify existing runtime/tests/docs only. |

### Modified Files
| Path | Phase | Changes |
|------|-------|---------|
| `lua/commentry/config.lua` | 1 | Keymap contract/default invariants and setup-time validation/warnings |
| `lua/commentry/commands.lua` | 2 | Attach behavior hardening, selective-disable/fallback enforcement, parity audit |
| `tests/commentry_config_spec.lua` | 3 | Defaults/override/validation regression coverage |
| `tests/commentry_commands_spec.lua` | 3 | Diffview-only attach/idempotence/selective-disable regression coverage |
| `README.md` | 4 | Keymap matrix, remap examples, scoped disable docs |
| `doc/commentry.txt` | 4 | Vim help updates for keymaps and fallback behavior |
