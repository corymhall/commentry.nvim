# Spec Review: codex-integration

## Review Configuration

- **Spec:** `plans/codex-integration/02-spec/spec.md`
- **Models Used:** OpenAI GPT 5.3 Codex (successful)
- **Categories:** All (Codebase Match, Cross-Document Consistency, API/Interface, Security, Design, TDD, Standards, Architecture, Error Handling, Performance, Data/Schema, Acceptance Criteria)
- **Context Source:** Existing `plans/codex-integration/01-scope/context.md`

## Model Comparison

| # | Issue | OpenAI GPT 5.3 Codex | Agree? |
|---|-------|------------------------|--------|
| 1 | Snapshot immutability not achievable with current store write model | Current store serialization persists only narrow fields and rewrites data, so snapshot/disposition metadata would be lost unless schema/read-write paths are extended. Recommended explicit persisted send schema and round-trip support. | N/A (single lane) |
| 2 | "Unresolved items only" conflicts with existing status semantics | `unresolved` currently indicates drift/stale invalidation and is filtered from active render/export. Recommended separate lifecycle states from drift integrity states. | N/A (single lane) |
| 3 | Missing attachment/transport contract definition | No existing attachment/session send abstraction is present in command/runtime surfaces. Recommended explicit adapter contract (target discovery, identity, retries, error taxonomy). | N/A (single lane) |
| 4 | Provenance fields may leak local filesystem identity | Context identity includes absolute root-derived identifiers. Recommended outbound provenance sanitization (hashed IDs/repo-relative only). | N/A (single lane) |
| 5 | TDD/verification plan underspecified | Acceptance scenarios exist but concrete test matrix and fixture strategy are missing. Recommended required tests for snapshots, retries, supersede, and disposition independence. | N/A (single lane) |

## All Issues by Severity

### CRITICAL (1 issues)

**1. Snapshot Immutability Is Not Achievable With Current Store Write Model**
- **What:** Spec promises immutable send snapshots/disposition history in existing store, but current persistence model rewrites a constrained schema that would drop non-modeled metadata.
- **Where:** `spec.md` Design/Architecture + Data Model assumptions; runtime persistence in `lua/commentry/comments.lua`.
- **Evidence:** `save_store` rebuilds store with fixed keys and serializer/hydrator flows only cover known comment/thread fields.
- **Recommendation:** Define explicit persisted send schema (for example top-level `sends[]` or equivalent within store schema) and update read/write projections so new metadata survives round trips.
- **Ambiguity:** Should send snapshots be represented as a dedicated top-level collection in the existing store versus nested under context records?

### HIGH (2 issues)

**2. "Unresolved Items Only" Conflicts With Existing Comment Status Semantics**
- **What:** Current `status="unresolved"` appears to represent stale/invalidated comments after reconciliation, not open actionable review findings.
- **Where:** `spec.md` Overview, Payload Builder, Acceptance Criteria; comment lifecycle handling in `lua/commentry/comments.lua`.
- **Evidence:** Reconciliation marks drifted comments `unresolved`; active rendering/export filters those statuses.
- **Recommendation:** Split states into lifecycle intent (`open`, `resolved`, `deferred`, etc.) and integrity state (`fresh`, `stale`) and filter send payload by lifecycle intent.
- **Ambiguity:** Should existing `status` be migrated to a dual-field model (`lifecycle_status`, `integrity_status`) or should lifecycle be inferred from existing fields plus migration rules?

**3. Missing Attachment/Transport Contract Definition (UNVERIFIED External API)**
- **What:** Spec relies on active attached session routing and transport behavior, but no concrete runtime contract is defined.
- **Where:** `spec.md` Architecture Overview, Send Orchestrator, Transport Adapter Interface, User Flows.
- **Evidence:** Runtime command set and local-review/export workflows do not expose a send/session abstraction today.
- **Recommendation:** Add an explicit adapter contract: target discovery API, target identity format, attachment freshness validation, idempotency key behavior, retry semantics, and required error taxonomy.
- **Ambiguity:** Should v1 define one required adapter contract implemented by all backends, or a minimal core contract with adapter-specific extensions?

### MEDIUM (2 issues)

**4. Provenance Fields Risk Leaking Local Filesystem Identity**
- **What:** Provenance requirements may transmit absolute-root-derived context identifiers to external adapters.
- **Where:** `spec.md` Payload Builder + Data Model; context identity construction in `lua/commentry/diffview.lua`.
- **Evidence:** Context IDs include root/mode/revision-derived identity and drive on-disk context paths.
- **Recommendation:** Specify outbound provenance normalization/redaction (hashed context IDs, repo-relative paths, explicit opt-in for raw absolute paths).
- **Ambiguity:** Is hashing context identity sufficient for v1, or is a fully detached outbound ID namespace required?

**5. TDD Alignment Is Underspecified For New Behavioral Surface**
- **What:** Spec includes acceptance scenarios but not an implementation-grade test plan.
- **Where:** `spec.md` Acceptance Criteria + Next Steps; project test suite conventions under `tests/`.
- **Evidence:** No required test file/case matrix is called out for no-target block, transport failure/retry, supersede chains, disposition persistence, and resend determinism.
- **Recommendation:** Add a mandatory test matrix and fixtures for store round-trips, adapter mocks, failure paths, and disposition/delivery independence.
- **Ambiguity:** Should these tests be required before first implementation merge, or staged across follow-up tasks with gating milestones?

### LOW (0 issues)

None.

## Reasoning

- Multi-model disagreement analysis is not applicable because only one lane was selected and executed.
- Findings are retained exactly from the successful lane and prioritized by implementation risk.

## Ambiguities Summary

| # | Issue | Ambiguity | Options |
|---|-------|-----------|---------|
| 1 | Snapshot immutability/store model | Where to persist immutable send snapshots in existing store model | A) Top-level `sends[]` (recommended) B) Nested per-context snapshots C) Separate artifact schema in same store |
| 2 | Unresolved status semantics | How to represent actionable vs stale states | A) Introduce dual-field model (`lifecycle_status` + `integrity_status`) (recommended) B) Reuse `status` with stricter enum/migration C) Infer lifecycle from multiple existing fields |
| 3 | Adapter contract | Contract strictness across transport backends | A) Single mandatory v1 contract (recommended) B) Minimal core + adapter extensions C) Adapter-specific contracts only |
| 4 | Provenance safety | Outbound identity policy | A) Hashed context ID + repo-relative paths (recommended) B) Adapter-specific redaction policy C) Raw IDs with opt-in warnings |
| 5 | Test gating | When to require full test matrix | A) Required before first implementation merge (recommended) B) Staged across follow-up tasks C) Post-v1 hardening |

## Summary

- **Total Issues:** 5 (1 critical, 2 high, 2 medium, 0 low)
- **Ambiguities Requiring Decision:** 5
- **Model Agreement Rate:** 100% (single-lane review)
- **Selected Lanes:** Codex
- **Model Lanes That Failed:** None
