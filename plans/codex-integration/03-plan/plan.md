# codex-integration - Implementation Plan

**Created:** 2026-02-26
**Status:** Draft
**Source Spec:** plans/codex-integration/02-spec/spec.md

---

## Overview
This plan implements a v1 Codex handoff path from Commentry reviews to the active Codex session via an explicit command. It reuses existing review context/state resolution and rendering semantics, introduces a small transport abstraction, and keeps data writes unchanged (no new persisted send state). The delivery is deterministic, scoped to the active review context, and fails loudly when no attached target exists.

The implementation is structured for parallel delivery: shared contracts first, then payload construction, then command/orchestration and adapter behavior, then hardening and docs. This keeps risk concentrated in the transport layer while preserving Commentry as source of truth for review state.

The plan aligns with v1 constraints from the spec: send-and-forget semantics, active (non-stale) item scope, repo-relative provenance only, optional adapter backend, explicit user action, and required tests before merge.

---

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Send model | Send-and-forget | Required by v1; avoids introducing persistence complexity and write-back semantics. |
| Payload scope | Active (non-stale) items in current review context | Matches existing status semantics and prevents stale review data leakage. |
| Trigger model | Explicit `:Commentry send-to-codex` command | Consistent with existing command-driven UX and avoids hidden background behavior. |
| Adapter boundary | Optional `send(payload, target)` transport contract | Allows Sidekick or future backends without changing payload/UX semantics. |
| Provenance policy | Repo-relative paths only | Prevents absolute local path leakage. |
| Feedback model | Immediate in-session success/failure only | Meets v1 requirement without send-history persistence. |
| Failure behavior | Hard fail when no attached target | Avoids silent drops; provides actionable remediation and deterministic retries. |
| Test gate | Required tests before merge | Explicit spec gate for behavior stability. |

---

## Shared Abstractions

- **Name:** `commentry.CodexPayload`
- **Location:** `lua/commentry/codex/payload.lua`
- **Purpose:** Stable payload contract for send handoff (`context`, `review_meta`, `items`, `provenance`).
- **Consumers:** Phase 2 payload tasks, Phase 3 orchestrator/adapter tasks, Phase 4 test tasks.

- **Name:** `CodexTransportAdapter`
- **Location:** `lua/commentry/codex/adapter.lua`
- **Purpose:** Core adapter contract and normalized error mapping for transport implementations.
- **Consumers:** Phase 3 adapter implementation and orchestrator dispatch.

- **Name:** `ActiveItemsSelector`
- **Location:** `lua/commentry/codex/payload.lua`
- **Purpose:** Centralize active/non-stale filter semantics to avoid divergence from existing comment status behavior.
- **Consumers:** Phase 2 payload creation; Phase 4 payload regression tests.

- **Name:** `RepoRelativePath` helper
- **Location:** `lua/commentry/codex/payload.lua` (or `lua/commentry/util.lua` if reuse is broader)
- **Purpose:** Enforce repo-relative provenance in outbound payloads.
- **Consumers:** Phase 2 payload construction; Phase 4 provenance tests.

- **Name:** `CodexSendOrchestrator.send_current_review(opts)`
- **Location:** `lua/commentry/codex/send.lua`
- **Purpose:** Resolve context and target, build payload, dispatch via adapter, normalize user-facing outcome.
- **Consumers:** Phase 3 command integration and tests.

---

## Phased Delivery

### Phase 1: Foundation & Contracts

**Objective:** Establish config and transport contracts with no behavior change to existing flows.  
**Prerequisites:** None

#### Tasks

**1.1 Add Codex config namespace and defaults**
- **What:** Extend config with `codex` options (`enabled`, adapter selection/default behavior) while preserving compatibility.
- **Files:**
  - Modify: `lua/commentry/config.lua` - add default config table + merge behavior.
- **Key details:** Keep defaults backward-safe; command remains explicit and no-op when disabled/unavailable.
- **Acceptance criteria:**
  - [ ] Existing setup still works without codex config.
  - [ ] Config merge is deterministic and idempotent.
  - [ ] Disabled codex produces actionable command feedback, not stack traces.
- **Dependencies:** None

**1.2 Define adapter contract and error normalization**
- **What:** Create adapter interface boundary and normalized error helper.
- **Files:**
  - Create: `lua/commentry/codex/adapter.lua` - interface docs/helpers.
- **Key details:** Interface shape: `send(payload, target) -> ok, err[, details]`; map provider errors to stable user-facing strings.
- **Acceptance criteria:**
  - [ ] Contract is explicit and imported by orchestrator.
  - [ ] Unknown/internal errors normalize to safe generic message.
  - [ ] No backend-specific strings leak by default.
- **Dependencies:** 1.1

**1.3 Wire codex namespace loading safely**
- **What:** Ensure codex modules can be resolved lazily and optional adapter dependencies do not load at startup.
- **Files:**
  - Modify: `lua/commentry/init.lua` - load path/wiring update if needed.
- **Key details:** Keep startup behavior unchanged when codex integration is disabled.
- **Acceptance criteria:**
  - [ ] Startup succeeds without adapter installed.
  - [ ] No eager hard-require on optional adapter modules.
  - [ ] Existing commands unaffected.
- **Dependencies:** 1.1, 1.2

#### Phase 1 Exit Criteria
- [ ] Config + transport contract exist and are imported cleanly.
- [ ] Plugin startup and existing comment flows are unchanged.

---

### Phase 2: Payload Builder & Safety

**Objective:** Build deterministic, active-only, repo-safe payloads from a single active review context.  
**Prerequisites:** Phase 1 contract/config foundation

#### Tasks

**2.1 Implement payload builder**
- **What:** Build canonical payload from current review context.
- **Files:**
  - Create: `lua/commentry/codex/payload.lua` - payload assembly functions.
- **Key details:** Include context identity, review metadata, item list, provenance; no persistence writes.
- **Acceptance criteria:**
  - [ ] Payload shape is stable across repeated calls.
  - [ ] Payload is scoped to the active context only.
  - [ ] Builder performs no store writes.
- **Dependencies:** 1.1, 1.2, 1.3

**2.2 Add active/non-stale item extraction**
- **What:** Reuse existing status semantics to include only active items.
- **Files:**
  - Modify: `lua/commentry/codex/payload.lua` - filtering and item projection.
- **Key details:** Preserve `comment_type` (`issue/suggestion/note/praise`) and thread linkage where available.
- **Acceptance criteria:**
  - [ ] Items marked stale/invalid are excluded.
  - [ ] Active items are preserved with type/body metadata.
  - [ ] Behavior aligns with existing active comment views.
- **Dependencies:** 2.1

**2.3 Enforce repo-relative provenance**
- **What:** Normalize any path fields in payload provenance.
- **Files:**
  - Modify: `lua/commentry/codex/payload.lua` or `lua/commentry/util.lua` - helper function.
- **Key details:** Never emit absolute local filesystem paths.
- **Acceptance criteria:**
  - [ ] Provenance paths are repo-relative.
  - [ ] Absolute path fixture fails without normalization and passes with it.
  - [ ] Missing/unknown roots degrade safely.
- **Dependencies:** 2.1, 2.2

**2.4 Add payload-focused tests**
- **What:** Add table-driven tests for filter behavior and provenance safety.
- **Files:**
  - Create: `tests/commentry_codex_payload_spec.lua` - payload test suite.
- **Key details:** Verify deterministic output ordering and no side effects.
- **Acceptance criteria:**
  - [ ] Active-only filter tests pass.
  - [ ] Provenance safety tests pass.
  - [ ] Deterministic serialization/order checks pass.
- **Dependencies:** 2.1, 2.2, 2.3

#### Phase 2 Exit Criteria
- [ ] Payload generation is deterministic and context-scoped.
- [ ] Active-only + provenance constraints are enforced and tested.

---

### Phase 3: Send Orchestration, Adapter, and Command

**Objective:** Deliver explicit send command with optional adapter dispatch and normalized outcomes.  
**Prerequisites:** Phase 2 payload readiness

#### Tasks

**3.1 Implement send orchestrator**
- **What:** Add orchestrator entrypoint that resolves context/target, builds payload, and dispatches.
- **Files:**
  - Create: `lua/commentry/codex/send.lua` - `send_current_review(opts)`.
- **Key details:** Hard-fail if no target; no automatic retries; no persistence write-back.
- **Acceptance criteria:**
  - [ ] No-target path blocks dispatch and returns actionable remediation.
  - [ ] Success path returns stable outcome shape.
  - [ ] Send path does not mutate persisted review model.
- **Dependencies:** 1.2, 2.1, 2.2

**3.2 Implement optional Sidekick adapter**
- **What:** Add adapter implementation behind capability checks.
- **Files:**
  - Create: `lua/commentry/codex/adapters/sidekick.lua` - optional backend.
- **Key details:** Soft-require adapter dependency; normalize raw backend errors.
- **Acceptance criteria:**
  - [ ] Missing adapter/runtime returns normalized unavailable message.
  - [ ] Attached target success dispatches once with unchanged payload semantics.
  - [ ] Provider failures normalize cleanly.
- **Dependencies:** 1.2

**3.3 Register explicit send command**
- **What:** Add command route and completion entry.
- **Files:**
  - Modify: `lua/commentry/commands.lua` - command registration, dispatch, completion.
- **Key details:** Command path delegates to orchestrator only; no direct adapter coupling in commands layer.
- **Acceptance criteria:**
  - [ ] `:Commentry send-to-codex` appears in completion.
  - [ ] Command invokes orchestrator exactly once.
  - [ ] Failure states are actionable and user-visible.
- **Dependencies:** 3.1

**3.4 Add adapter health reporting**
- **What:** Extend health checks for optional codex adapter readiness.
- **Files:**
  - Modify: `lua/commentry/health.lua` - codex status checks.
- **Key details:** Non-blocking when integration disabled.
- **Acceptance criteria:**
  - [ ] Health passes when codex disabled.
  - [ ] Health warns when command enabled but adapter/target unavailable.
  - [ ] Health output is explicit and actionable.
- **Dependencies:** 3.1, 3.2

**3.5 Add command/orchestrator integration tests**
- **What:** Extend tests covering command routing and send outcomes.
- **Files:**
  - Modify: `tests/commentry_commands_spec.lua` - command dispatch cases.
  - Create: `tests/commentry_codex_send_spec.lua` - orchestrator behavior.
- **Key details:** Cover no-target, success, adapter failure, retry-ready failure outputs.
- **Acceptance criteria:**
  - [ ] No-target behavior blocks and reports correctly.
  - [ ] Success path verifies adapter call.
  - [ ] Failure path returns normalized retryable message.
- **Dependencies:** 3.3, 3.1

#### Phase 3 Exit Criteria
- [ ] Explicit send command works through orchestrator.
- [ ] Optional adapter behavior is isolated and normalized.
- [ ] Core no-target/success/failure scenarios are tested.

---

### Phase 4: Hardening, Docs, and Merge Gate

**Objective:** Finalize regression coverage, docs, and release-readiness with required tests before merge.  
**Prerequisites:** Phase 3 complete

#### Tasks

**4.1 Add adapter-focused tests**
- **What:** Add contract/error normalization tests for adapter layer.
- **Files:**
  - Create: `tests/commentry_codex_adapter_spec.lua` - adapter behavior tests.
- **Key details:** Validate normalized errors and capability-gated loading.
- **Acceptance criteria:**
  - [ ] Adapter unavailable path is deterministic.
  - [ ] Error normalization cases are covered.
  - [ ] Adapter contract remains stable under mock failures.
- **Dependencies:** 3.2

**4.2 Add end-to-end payload safety regression**
- **What:** Validate stale filtering + provenance constraints through send path.
- **Files:**
  - Modify: `tests/commentry_codex_payload_spec.lua` - e2e-style payload fixtures.
- **Key details:** Mixed stale/active + mixed path fixtures.
- **Acceptance criteria:**
  - [ ] Only active items are emitted.
  - [ ] No absolute paths appear in final payload.
  - [ ] Repeat sends over updated review remain deterministic.
- **Dependencies:** 2.4, 3.1

**4.3 Update user and help documentation**
- **What:** Document command, behavior, and v1 constraints.
- **Files:**
  - Modify: `README.md` - usage and examples.
  - Modify: `doc/commentry.txt` - help docs for new command/options.
- **Key details:** Call out send-and-forget and out-of-scope boundaries clearly.
- **Acceptance criteria:**
  - [ ] Docs describe explicit send flow.
  - [ ] Docs state no persisted send history in v1.
  - [ ] Docs mention optional adapter and required attachment.
- **Dependencies:** 3.3

**4.4 Record migration/deferred scope notes**
- **What:** Record no-migration stance and deferred v2 scope items.
- **Files:**
  - Modify: `plans/codex-integration/03-plan/plan.md` - migration/deferred sections (this document).
- **Key details:** Keep v1 scope strict; no Beads integration or multi-user routing.
- **Acceptance criteria:**
  - [ ] No storage migration is required/implemented.
  - [ ] Deferred items remain explicitly deferred.
  - [ ] Constraints remain aligned with source spec.
- **Dependencies:** 4.1, 4.2

#### Phase 4 Exit Criteria
- [ ] Required test gate scenarios are fully covered and passing.
- [ ] Documentation reflects v1 semantics and constraints.
- [ ] No persistence migration or send-history writeback introduced.

---

## Cross-Cutting Concerns

### Error Handling
- Missing target: fail fast with explicit remediation (`attach session first`) and no dispatch.
- Adapter unavailable/failure: normalize to user-safe errors with retry guidance.
- Payload build failures: return explicit failure reason without backend leakage.
- Stale content handling: filter stale items at payload build time.

### Testing Strategy
- Unit tests for payload shape/filtering/provenance.
- Orchestrator tests for no-target/success/failure/retry behaviors.
- Command integration tests for explicit routing and user feedback.
- Adapter contract tests for capability gating and normalized errors.
- Required pre-merge gate: tests must cover no-target, success, transport failure, resend determinism, active-item scope, and provenance safety.

### Migration
No migration needed in v1. Existing `.commentry/contexts/...` storage model remains unchanged. v2 can revisit persistence or Beads-related continuity if requirements expand.

---

## Technical Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Active/non-stale semantics diverge from existing behavior | M | H | Centralize predicate in payload builder and mirror existing status tests. |
| Optional adapter becomes implicit hard dependency | M | H | Soft-require adapter, feature gate in config/health, and explicit no-target/no-adapter guidance. |
| Absolute path provenance leaks | M | H | Enforce repo-relative normalization and add dedicated test coverage. |
| Target resolution ambiguity in non-diff contexts | M | M | Use existing context resolution path and hard-fail with actionable messaging. |
| Users assume persisted send state exists | M | M | Document send-and-forget semantics in command feedback and docs. |
| Regression in existing command flows | L | H | Keep command wiring isolated and extend existing commands tests for safety. |

---

## Spec Coverage Matrix

| Spec Section | Plan Section | Phase |
|-------------|-------------|-------|
| Overview | Overview; Architecture Decisions | 1-4 |
| Scope Questions & Answers (P0/P1) | Architecture Decisions; phased tasks enforcing command/adapter/scope constraints | 1-4 |
| Design: Architecture Overview | Shared Abstractions; Phase 3 orchestrator/adapter | 1-3 |
| Design: Components | Shared Abstractions; Phase tasks 2.1, 3.1, 3.2, 3.3 | 2-3 |
| Design: Data Model | Migration; Phase 4.4 | 4 |
| Design: User Flows (Send/Resend/No Target) | Phase 3 tasks + testing strategy | 3-4 |
| Design: Acceptance Criteria (v1) | Phase acceptance criteria and test gates | 2-4 |
| Design: Error Handling | Cross-Cutting Error Handling; Phase 3/4 tasks | 3-4 |
| Design: Constraints | Architecture Decisions; Migration; risks | 1-4 |
| Design: Integration Points | Phase 2/3 file-level tasks | 2-3 |
| Out of Scope | Phase 4.4 deferred scope notes | 4 |
| Spec Review: Clarifications Added | Architecture Decisions + task specifics (adapter contract, active scope, provenance, tests) | 1-4 |
| Spec Review: Deferred Items | Migration/Deferred handling | 4 |
| Multi-Model Review: Findings Addressed | Tasks 2.2, 2.3, 3.1, 3.2, 4.x tests | 2-4 |
| Multi-Model Review: Ambiguities Resolved | Architecture Decisions table | 1 |
| Multi-Model Review: Deferred Items | Migration/Deferred handling | 4 |
| Next Steps | This plan + downstream beads decomposition | 1-4 |
| Appendix: Source Files | Appendix file map below | 1-4 |
| Deferred Q98 (Review-to-Beads conversion) | Explicitly deferred in v1; not implemented in phases | 4 |
| Deferred Q103 (multi-person collaboration) | Explicitly deferred in v1; not implemented in phases | 4 |
| Deferred Q122 (Beads continuity artifact) | Explicitly deferred in v1; not implemented in phases | 4 |

---

## Appendix: Key File Paths

### New Files
| Path | Phase | Purpose |
|------|-------|---------|
| `lua/commentry/codex/adapter.lua` | 1 | Adapter contract and error normalization |
| `lua/commentry/codex/payload.lua` | 2 | Payload assembly, active-item filtering, provenance normalization |
| `lua/commentry/codex/send.lua` | 3 | Orchestrator for explicit send flow |
| `lua/commentry/codex/adapters/sidekick.lua` | 3 | Optional Sidekick transport adapter |
| `tests/commentry_codex_payload_spec.lua` | 2 | Payload-focused tests |
| `tests/commentry_codex_send_spec.lua` | 3 | Orchestrator and flow tests |
| `tests/commentry_codex_adapter_spec.lua` | 4 | Adapter contract/normalization tests |

### Modified Files
| Path | Phase | Changes |
|------|-------|---------|
| `lua/commentry/config.lua` | 1 | Add codex integration options/defaults |
| `lua/commentry/init.lua` | 1 | Optional codex module wiring/load behavior |
| `lua/commentry/commands.lua` | 3 | Register explicit send command and completion |
| `lua/commentry/health.lua` | 3 | Optional adapter readiness checks |
| `lua/commentry/util.lua` | 2 | Shared path/provenance helpers (if extracted) |
| `tests/commentry_commands_spec.lua` | 3 | Extend command routing tests |
| `README.md` | 4 | Usage docs and v1 constraints |
| `doc/commentry.txt` | 4 | Help docs for new command |
| `plans/codex-integration/03-plan/plan.md` | 4 | Migration/deferred scope note completeness |
