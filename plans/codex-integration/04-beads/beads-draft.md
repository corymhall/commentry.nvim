# Beads Draft: codex-integration

**Generated:** 2026-02-26
**Source:** plans/codex-integration/03-plan/plan.md
**Plan review status:** Reviewed

---

## Structure

### Feature Epic: codex-integration

**Type:** epic
**Priority:** P1
**Description:** Implement v1 Codex handoff from Commentry review context using an explicit send command, send-and-forget semantics, and adapter-based transport with repo-relative provenance and required pre-merge tests.

---

### Sub-Epic: Phase 1 — Foundation & Contracts

**Type:** epic
**Priority:** P1
**Parent:** Feature epic
**Description:** Establish codex integration configuration and transport contract boundaries without changing existing Commentry behavior.

#### Issue: Add Codex config namespace and defaults (1.1)

**Type:** task
**Priority:** P1
**Parent:** Phase 1
**Dependencies:** None
**Description:**
Extend config with codex options (`enabled`, adapter behavior/selection defaults) while preserving backward compatibility. Modify `lua/commentry/config.lua` to add defaults and deterministic merge behavior. Keep codex disabled path explicit and actionable, with no runtime crashes for missing optional adapters.

**Acceptance Criteria:**
- [ ] Existing setup still works without codex config.
- [ ] Config merge is deterministic and idempotent.
- [ ] Disabled codex produces actionable command feedback, not stack traces.

#### Issue: Define adapter contract and error normalization (1.2)

**Type:** task
**Priority:** P1
**Parent:** Phase 1
**Dependencies:** Task 1.1 (Add Codex config namespace and defaults)
**Description:**
Create `lua/commentry/codex/adapter.lua` defining the transport interface and error normalization. Contract shape: `send(payload, target) -> ok, err[, details]`, where `ok` is boolean and `err` is a normalized error table `{ code, message, retryable }`. Define canonical error codes/messages: `NO_TARGET` (`"No active Codex target attached."`), `ADAPTER_UNAVAILABLE` (`"Codex adapter is unavailable."`), `TRANSPORT_FAILED` (`"Codex transport failed."`), and `INTERNAL_ERROR` (`"Unexpected Codex send error."`). Prevent backend-specific error leakage by mapping raw adapter errors into these canonical forms.

**Acceptance Criteria:**
- [ ] Contract is explicit and imported by orchestrator.
- [ ] Unknown/internal errors normalize to `INTERNAL_ERROR` with `retryable=false`.
- [ ] Canonical codes/messages are emitted exactly for missing target, adapter unavailable, and transport failure scenarios.
- [ ] No backend-specific strings leak by default.

#### Issue: Wire codex namespace loading safely (1.3)

**Type:** task
**Priority:** P1
**Parent:** Phase 1
**Dependencies:** Task 1.1 (Add Codex config namespace and defaults), Task 1.2 (Define adapter contract and error normalization)
**Description:**
Update `lua/commentry/init.lua` wiring so codex modules load lazily and optional adapter packages are not hard-required at startup. Preserve current startup and command behavior when codex integration is disabled.

**Acceptance Criteria:**
- [ ] Startup succeeds without adapter installed.
- [ ] No eager hard-require on optional adapter modules.
- [ ] Existing commands unaffected.

---

### Sub-Epic: Phase 2 — Payload Builder & Safety

**Type:** epic
**Priority:** P2
**Parent:** Feature epic
**Description:** Build deterministic payload generation scoped to active review items with provenance safety and parity with existing comment semantics.

#### Issue: Implement payload builder (2.1)

**Type:** task
**Priority:** P2
**Parent:** Phase 2
**Dependencies:** Task 1.1 (Add Codex config namespace and defaults), Task 1.2 (Define adapter contract and error normalization)
**Description:**
Create `lua/commentry/codex/payload.lua` with `build_payload(context, opts) -> payload` to assemble canonical outbound payload from the active review context. Include `context` identity, `review_meta`, `items`, and `provenance` fields. Payload serialization for identical inputs must be byte-stable (same key order and item ordering), and this module must not call store write APIs (`Store.write`, `persist_for_view`, or filesystem writes).

**Acceptance Criteria:**
- [ ] `build_payload(context, opts)` returns byte-identical JSON for identical fixture inputs.
- [ ] Payload is scoped to the active context only.
- [ ] Builder performs no store writes (`Store.write`/`persist_for_view` call count stays zero in tests).

#### Issue: Add active/non-stale item extraction (2.2)

**Type:** task
**Priority:** P2
**Parent:** Phase 2
**Dependencies:** Task 2.1 (Implement payload builder)
**Description:**
Implement filtering and item projection in `lua/commentry/codex/payload.lua` so only active (non-stale) items are included. Preserve `comment_type` (`issue/suggestion/note/praise`) and thread linkage where available. Bind behavior to existing `lua/commentry/comments.lua` active-item semantics (`exportable_comments(context)` path or shared helper extraction) to prevent logic drift. Use fixture-driven parity cases where source comments include `id`, `diff_id`, `file_path`, `line_number`, `line_side`, `comment_type`, `body`, `status`, and optional thread parent linkage.

**Acceptance Criteria:**
- [ ] Items marked stale/invalid are excluded.
- [ ] Active items are preserved with `id`, `comment_type`, `body`, `file_path`, `line_number`, `line_side`, and thread linkage fields.
- [ ] Fixture `tests/fixtures/codex_payload_active_vs_stale.json` produces the same active-item set as `exportable_comments(context)` for the same input.
- [ ] Regression test proves payload active-item extraction stays in parity with existing comments export behavior.

#### Issue: Enforce repo-relative provenance (2.3)

**Type:** task
**Priority:** P2
**Parent:** Phase 2
**Dependencies:** Task 2.1 (Implement payload builder), Task 2.2 (Add active/non-stale item extraction)
**Description:**
Add provenance normalization in `lua/commentry/codex/payload.lua` or `lua/commentry/util.lua` to ensure all outbound paths are repo-relative. Handle missing/unknown roots safely and never emit absolute filesystem paths.

**Acceptance Criteria:**
- [ ] Provenance paths are repo-relative.
- [ ] Fixture path `/Users/chall/gt/commentry/crew/fiddler/lua/commentry/commands.lua` normalizes to `lua/commentry/commands.lua`.
- [ ] Fixture path outside repo root (e.g. `/tmp/external.lua`) is rejected or excluded by explicit documented behavior.
- [ ] Missing/unknown roots degrade safely.

#### Issue: Add payload-focused tests (2.4)

**Type:** task
**Priority:** P2
**Parent:** Phase 2
**Dependencies:** Task 2.1 (Implement payload builder), Task 2.2 (Add active/non-stale item extraction), Task 2.3 (Enforce repo-relative provenance)
**Description:**
Create `tests/commentry_codex_payload_spec.lua` with table-driven tests for filter behavior, provenance safety, deterministic ordering/serialization, and no side effects.

**Acceptance Criteria:**
- [ ] Active-only filter tests pass.
- [ ] Provenance safety tests pass.
- [ ] Deterministic serialization/order checks pass.

---

### Sub-Epic: Phase 3 — Send Orchestration, Adapter, and Command

**Type:** epic
**Priority:** P2
**Parent:** Feature epic
**Description:** Implement explicit send orchestration and optional adapter execution, wired through command and health surfaces.

#### Issue: Implement send orchestrator (3.1)

**Type:** task
**Priority:** P2
**Parent:** Phase 3
**Dependencies:** Task 1.2 (Define adapter contract and error normalization), Task 2.1 (Implement payload builder), Task 2.2 (Add active/non-stale item extraction)
**Description:**
Create `lua/commentry/codex/send.lua` with `send_current_review(opts)` to resolve active context and target, build payload, dispatch through adapter, and normalize outcomes. Use `lua/commentry/diffview.lua` context resolution (`resolve_review_context`, `current_file_context`) and comments context identity keys (`context_id`, `diff_id`) to ensure single active-review scoping. Return schema must be explicit: success `{ ok=true, code=\"OK\", target=<string>, adapter=<string>, dispatched_items=<number> }`; failure `{ ok=false, code=<canonical_error_code>, message=<string>, retryable=<boolean> }`. No persistence write-back or auto retries.

**Acceptance Criteria:**
- [ ] No-target path blocks dispatch and returns actionable remediation.
- [ ] Success returns `{ ok=true, code=\"OK\", target, adapter, dispatched_items }` with correct types.
- [ ] Failure returns `{ ok=false, code, message, retryable }` with canonical codes from adapter contract.
- [ ] Send path does not mutate persisted review model.
- [ ] Context resolution path is explicitly tested for active review scoping behavior.

#### Issue: Implement optional Sidekick adapter (3.2)

**Type:** task
**Priority:** P2
**Parent:** Phase 3
**Dependencies:** Task 1.2 (Define adapter contract and error normalization)
**Description:**
Create `lua/commentry/codex/adapters/sidekick.lua` using soft dependency checks (`pcall(require, ...)`) and normalized adapter response/error handling. Define minimal target spec consumed by adapter as `{ session_id=<string>, workspace=<string|nil> }`. Treat adapter as unavailable unless required module entrypoints are present and target has `session_id`. Preserve payload semantics and avoid hard dependency failures when adapter/runtime is unavailable.

**Acceptance Criteria:**
- [ ] Missing adapter/runtime returns normalized unavailable message.
- [ ] Attached target success dispatches once with unchanged payload semantics.
- [ ] Provider failures normalize cleanly.

#### Issue: Register explicit send command (3.3)

**Type:** task
**Priority:** P2
**Parent:** Phase 3
**Dependencies:** Task 3.1 (Implement send orchestrator)
**Description:**
Modify `lua/commentry/commands.lua` to register `:Commentry send-to-codex`, wire command completion, and delegate execution strictly to orchestrator logic. Keep actionable user feedback and avoid direct adapter calls in command layer.

**Acceptance Criteria:**
- [ ] `:Commentry send-to-codex` appears in completion.
- [ ] Command invokes orchestrator exactly once.
- [ ] Failure states are actionable and user-visible.

#### Issue: Add adapter health reporting (3.4)

**Type:** task
**Priority:** P2
**Parent:** Phase 3
**Dependencies:** Task 3.2 (Implement optional Sidekick adapter)
**Description:**
Extend `lua/commentry/health.lua` to report codex adapter readiness as a non-blocking check. Ensure disabled codex mode remains clean and enabled-but-unavailable states are explicit and actionable.

**Acceptance Criteria:**
- [ ] Health passes when codex disabled.
- [ ] Health warns when command enabled but adapter/target unavailable.
- [ ] Health output is explicit and actionable.

#### Issue: Add command/orchestrator/health integration tests (3.5)

**Type:** task
**Priority:** P2
**Parent:** Phase 3
**Dependencies:** Task 3.3 (Register explicit send command), Task 3.1 (Implement send orchestrator)
**Description:**
Expand integration coverage by modifying `tests/commentry_commands_spec.lua`, creating `tests/commentry_codex_send_spec.lua`, and modifying `tests/commentry_health_spec.lua` for enabled/disabled/unavailable states. Include no-target, success, adapter-failure, and retry-ready messaging checks with explicit message assertions (`No active Codex target attached.`, `Codex transport failed. Retry from current review context.`).

**Acceptance Criteria:**
- [ ] No-target behavior blocks and reports correctly.
- [ ] Success path verifies adapter call.
- [ ] Failure path returns normalized retryable message matching `Codex transport failed.*Retry`.
- [ ] Health checks cover disabled codex, enabled-but-unavailable adapter, and available adapter states.

---

### Sub-Epic: Phase 4 — Hardening, Docs, and Merge Gate

**Type:** epic
**Priority:** P2
**Parent:** Feature epic
**Description:** Finalize contract hardening, regression checks, docs updates, and migration/deferred-scope validation for merge readiness.

#### Issue: Add adapter-focused tests (4.1)

**Type:** task
**Priority:** P2
**Parent:** Phase 4
**Dependencies:** Task 3.2 (Implement optional Sidekick adapter)
**Description:**
Create `tests/commentry_codex_adapter_spec.lua` with deterministic cases for adapter-unavailable behavior, error normalization, and contract stability under mock failures.

**Acceptance Criteria:**
- [ ] Adapter unavailable path is deterministic.
- [ ] Error normalization cases are covered for timeout, missing target, and malformed adapter response.
- [ ] Adapter contract remains stable under mock failures by asserting exact return schema `{ ok, code, message, retryable }`.

#### Issue: Add end-to-end payload safety regression (4.2)

**Type:** task
**Priority:** P2
**Parent:** Phase 4
**Dependencies:** Task 2.4 (Add payload-focused tests), Task 3.1 (Implement send orchestrator)
**Description:**
Extend `tests/commentry_codex_payload_spec.lua` with mixed stale/active and mixed path fixtures through full send payload path. Validate active-item scoping, provenance safety, and deterministic resend behavior after updates by checking payload equality/hash for identical post-update state.

**Acceptance Criteria:**
- [ ] Only active items are emitted.
- [ ] No absolute paths appear in final payload.
- [ ] Repeat sends over the same updated fixture state produce identical payload JSON/hash.

#### Issue: Update user and help documentation (4.3)

**Type:** task
**Priority:** P2
**Parent:** Phase 4
**Dependencies:** Task 3.3 (Register explicit send command)
**Description:**
Modify `README.md` and `doc/commentry.txt` with command usage, adapter expectations, send-and-forget semantics, required attachment behavior, and v1 out-of-scope boundaries.

**Acceptance Criteria:**
- [ ] Docs describe explicit send flow.
- [ ] Docs state no persisted send history in v1.
- [ ] Docs mention optional adapter and required attachment.

#### Issue: Record migration/deferred scope notes (4.4)

**Type:** task
**Priority:** P2
**Parent:** Phase 4
**Dependencies:** Task 4.1 (Add adapter-focused tests), Task 4.2 (Add end-to-end payload safety regression)
**Description:**
Update `plans/codex-integration/03-plan/plan.md` migration and deferred-scope sections to preserve no-migration stance and explicit v2 deferrals (beads conversion continuity, multi-person collaboration, and broader scope items). Keep constraints aligned with source spec.

**Acceptance Criteria:**
- [ ] No storage migration is required/implemented.
- [ ] Deferred items remain explicitly deferred.
- [ ] Constraints remain aligned with source spec.

---

## Dependencies

| Blocked Task | Blocked By | Reason |
|-------------|------------|--------|
| Task 1.2 (Define adapter contract and error normalization) | Task 1.1 (Add Codex config namespace and defaults) | Adapter contract is introduced after baseline config/default behavior is established. |
| Task 1.3 (Wire codex namespace loading safely) | Task 1.1 (Add Codex config namespace and defaults) | Loader behavior depends on codex config gating. |
| Task 1.3 (Wire codex namespace loading safely) | Task 1.2 (Define adapter contract and error normalization) | Loader references adapter contract boundaries. |
| Task 2.1 (Implement payload builder) | Task 1.1 (Add Codex config namespace and defaults) | Payload behavior needs codex feature configuration defaults. |
| Task 2.1 (Implement payload builder) | Task 1.2 (Define adapter contract and error normalization) | Payload shape aligns with adapter contract boundary. |
| Task 2.2 (Add active/non-stale item extraction) | Task 2.1 (Implement payload builder) | Filtering/projection extends payload builder implementation. |
| Task 2.3 (Enforce repo-relative provenance) | Task 2.1 (Implement payload builder) | Provenance normalization is part of payload assembly path. |
| Task 2.3 (Enforce repo-relative provenance) | Task 2.2 (Add active/non-stale item extraction) | Final payload safety relies on filtered item list semantics. |
| Task 2.4 (Add payload-focused tests) | Task 2.1 (Implement payload builder) | Tests require payload builder implementation. |
| Task 2.4 (Add payload-focused tests) | Task 2.2 (Add active/non-stale item extraction) | Tests cover active/non-stale extraction behavior. |
| Task 2.4 (Add payload-focused tests) | Task 2.3 (Enforce repo-relative provenance) | Tests cover provenance normalization outcomes. |
| Task 3.1 (Implement send orchestrator) | Task 1.2 (Define adapter contract and error normalization) | Orchestrator dispatches through adapter contract. |
| Task 3.1 (Implement send orchestrator) | Task 2.1 (Implement payload builder) | Orchestrator constructs and dispatches payload. |
| Task 3.1 (Implement send orchestrator) | Task 2.2 (Add active/non-stale item extraction) | Orchestrator relies on active-item payload semantics. |
| Task 3.2 (Implement optional Sidekick adapter) | Task 1.2 (Define adapter contract and error normalization) | Adapter must implement finalized transport contract. |
| Task 3.3 (Register explicit send command) | Task 3.1 (Implement send orchestrator) | Command delegates to orchestrator entrypoint. |
| Task 3.4 (Add adapter health reporting) | Task 3.2 (Implement optional Sidekick adapter) | Health readiness depends on adapter availability behavior. |
| Task 3.5 (Add command/orchestrator/health integration tests) | Task 3.3 (Register explicit send command) | Command tests require command registration. |
| Task 3.5 (Add command/orchestrator/health integration tests) | Task 3.1 (Implement send orchestrator) | Orchestrator behavior is under test. |
| Task 4.1 (Add adapter-focused tests) | Task 3.2 (Implement optional Sidekick adapter) | Adapter tests require adapter implementation. |
| Task 4.2 (Add end-to-end payload safety regression) | Task 2.4 (Add payload-focused tests) | Regression suite extends baseline payload test harness. |
| Task 4.2 (Add end-to-end payload safety regression) | Task 3.1 (Implement send orchestrator) | End-to-end payload checks run through orchestrator flow. |
| Task 4.3 (Update user and help documentation) | Task 3.3 (Register explicit send command) | Documentation depends on finalized command surface. |
| Task 4.4 (Record migration/deferred scope notes) | Task 4.1 (Add adapter-focused tests) | Migration/deferred notes should reflect test-backed adapter behavior. |
| Task 4.4 (Record migration/deferred scope notes) | Task 4.2 (Add end-to-end payload safety regression) | Final notes should reflect completed regression hardening. |

**Reading this table:** each row means the "Blocked Task" cannot start until
"Blocked By" completes. This matches `bd dep add` argument order:
`bd dep add <blocked-task-id> <blocked-by-id>`.

## Coverage Matrix

| Plan Task | Bead Title | Sub-Epic |
|-----------|------------|----------|
| 1.1 Add Codex config namespace and defaults | Add Codex config namespace and defaults | Phase 1: Foundation & Contracts |
| 1.2 Define adapter contract and error normalization | Define adapter contract and error normalization | Phase 1: Foundation & Contracts |
| 1.3 Wire codex namespace loading safely | Wire codex namespace loading safely | Phase 1: Foundation & Contracts |
| 2.1 Implement payload builder | Implement payload builder | Phase 2: Payload Builder & Safety |
| 2.2 Add active/non-stale item extraction | Add active/non-stale item extraction | Phase 2: Payload Builder & Safety |
| 2.3 Enforce repo-relative provenance | Enforce repo-relative provenance | Phase 2: Payload Builder & Safety |
| 2.4 Add payload-focused tests | Add payload-focused tests | Phase 2: Payload Builder & Safety |
| 3.1 Implement send orchestrator | Implement send orchestrator | Phase 3: Send Orchestration, Adapter, and Command |
| 3.2 Implement optional Sidekick adapter | Implement optional Sidekick adapter | Phase 3: Send Orchestration, Adapter, and Command |
| 3.3 Register explicit send command | Register explicit send command | Phase 3: Send Orchestration, Adapter, and Command |
| 3.4 Add adapter health reporting | Add adapter health reporting | Phase 3: Send Orchestration, Adapter, and Command |
| 3.5 Add command/orchestrator/health integration tests | Add command/orchestrator/health integration tests | Phase 3: Send Orchestration, Adapter, and Command |
| 4.1 Add adapter-focused tests | Add adapter-focused tests | Phase 4: Hardening, Docs, and Merge Gate |
| 4.2 Add end-to-end payload safety regression | Add end-to-end payload safety regression | Phase 4: Hardening, Docs, and Merge Gate |
| 4.3 Update user and help documentation | Update user and help documentation | Phase 4: Hardening, Docs, and Merge Gate |
| 4.4 Record migration/deferred scope notes | Record migration/deferred scope notes | Phase 4: Hardening, Docs, and Merge Gate |

**Plan tasks:** 16
**Beads mapped:** 16
**Coverage:** 100%

## Summary

- Feature epic: 1
- Sub-epics (phases): 4
- Issues (tasks): 16
- Blocker dependencies: 25
- Items ready immediately (no blockers): 1
