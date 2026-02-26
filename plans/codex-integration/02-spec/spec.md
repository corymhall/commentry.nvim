# codex-integration - Design Specification

**Created:** 2026-02-26
**Status:** Validated
**Brainstorming Mode:** With scope questions

---

## Overview

This feature integrates Commentry's stored review artifacts with active Codex sessions so review input can be delivered directly into the current working context. Today, review data is persisted locally in Commentry and can be exported, but there is no first-class handoff path into an attached Codex session. The immediate goal is to close that transport gap with a simple, trustworthy flow.

The design intentionally prioritizes reliable handoff over downstream automation. In v1, users trigger an explicit `Send to Codex Session` action from the existing Commentry review workspace. The payload is built from the full review, filtered to active (non-stale) items, then sent to the currently attached session target. v1 is send-and-forget: send outcomes are shown in-session, but no send history/disposition state is persisted back into Commentry. This keeps semantics familiar to PR review while avoiding claims of automated close-loop state in v1.

This spec also keeps integration boundaries narrow. Commentry remains the source of truth for review state and history, while transport is adapter-based (for example Sidekick attachment flow or Gastown-native send path). Beads integration is explicitly deferred to v2 so v1 can validate core utility in a solo, single-repo workflow.

---

## Scope Questions & Answers

### Summary
- **Questions addressed:** 124 (scope selected: P0+P1)
- **Auto-answered (best practices / verified constraints):** 101
- **Human decisions:** 20
- **Deferred to future:** 3

### P0: Critical Decisions

| # | Question | Answer | How Decided |
|---|----------|--------|-------------|
| 5 | Mandatory guidance vs optional context | PR-style handling: treat as review input; address or justify non-adoption | Human choice |
| 16 | Multi-session routing cues | Route to current attached session only | Human choice |
| 25 | Primary send action | `Send to Codex Session` in Commentry | Human choice |
| 27 | Payload scope granularity | Entire review, active (non-stale) items only | Human choice |
| 28 | Attach context vs request action | Attach context | Human choice |
| 36 | Sidekick semantics | Sidekick is an optional transport adapter only | Human choice |
| 50 | Comment interpretation | Type-based semantics (`issue/suggestion/note/praise`) | Human choice |
| 54 | Guidance horizon | Session-only for Codex session context | Human choice |
| 56 | Blocking mode in v1 | No explicit blocking mode | Human choice |
| 57 | User promise | "Send review context to the active Codex session reliably" | Human choice |
| 60 | Core problem framing | Optimize transport reliability first; outcomes later | Human choice |
| 63 | Target workflow | Solo-only workflow | Human choice |
| 68 | Beads role in v1 | No Beads integration in v1 | Human choice |

### P1: Important Decisions

| # | Question | Answer | How Decided |
|---|----------|--------|-------------|
| 81 | Source of truth | Commentry review store remains canonical | Human choice |
| 84 | Payload model | Send-and-forget in v1 (no persisted send snapshot/disposition model) | Human choice |
| 89 | IA boundary | Unified Commentry review space | Human choice |
| 92 | Cross-session persistence | Codex-session guidance is ephemeral; reviews remain persisted in Commentry for resend | Human choice |
| 98 | Review-to-Beads conversion flow | Deferred (depends on Beads v2 decision) | Deferred by scope |
| 102 | Summarize-only branch mode | No separate mode; always "send review" | Human choice |
| 103 | Multi-person collaboration flow | Deferred/out-of-scope (solo-only product boundary) | Deferred by scope |
| 120 | Initial target segment | Single local user in one repo/workspace | Human choice |
| 121 | Minimum Sidekick support | Optional adapter when attached; not required backend | Human choice |
| 122 | Beads proof artifact | Deferred (depends on Beads v2 decision) | Deferred by scope |

### Deferred Questions

These questions were in-scope but explicitly deferred:

| # | Question | Defer Reason | Revisit When |
|---|----------|--------------|--------------|
| 98 | What is the right flow for converting review findings into tracked work items (beads-aligned)? | Beads integration deferred in v1 | v2 Beads exploration |
| 103 | How should collaboration flows work when multiple people touch the same review artifacts? | Product boundary is solo-only | Only if product boundary changes |
| 122 | What beads-linked artifact demonstrates planning/execution continuity from reviews? | Beads integration deferred in v1 | v2 Beads exploration |

---

## Design

### Architecture Overview

The system is structured as `Commentry review state -> send payload builder -> transport adapter -> attached Codex session`. Commentry remains authoritative for review artifacts, including unresolved/resolved status, comment metadata, and context identity. The send operation is explicit and user-driven from the existing Commentry flow; no background synchronization is introduced in v1.

A transport adapter boundary isolates delivery mechanics from product semantics. The frontend behavior and payload shape stay constant, while backend implementations can vary (for example Sidekick adapter when a session is attached, or a Gastown-native route). This avoids hard-coding the first implementation choice into long-term UX.

Each send is a transient handoff event in v1. The system does not persist send-history/disposition artifacts to the Commentry store in this phase; users continue using existing review state to track resolution.

### Components

**Component 1: Review Payload Builder**
- Responsibility: Build canonical handoff payload from Commentry state.
- Interface: Input: current review context; Output: transient send payload.
- Key considerations: Include active (non-stale) items only; include comment type and provenance fields without absolute-path leakage.

**Component 2: Send Orchestrator**
- Responsibility: Execute `Send to Codex Session`, validate attachment, dispatch payload, and return immediate success/failure feedback.
- Interface: Command/action invoked from Commentry UI.
- Key considerations: Fail fast when no attached session target is present.

**Component 3: Transport Adapter Interface**
- Responsibility: Abstract delivery path to active Codex session.
- Interface: `send(payload, target)` with adapter-specific implementation.
- Key considerations: Sidekick is optional; adapter selection should not alter payload semantics. In v1, adapter choice is global/implicit from the active attachment (no per-send selector), and adapters implement a minimal core contract with normalized errors.

**Component 4: Transient Send Feedback**
- Responsibility: Show immediate send outcome to users (success/failure + next action hint).
- Interface: User-facing notifications/status text in current session.
- Key considerations: No persisted send history in v1.

### Data Model

No disruptive storage migration is required in v1. Existing Commentry persistence remains the primary model and is unchanged for send history/disposition. v1 does not add persisted send snapshot or disposition fields.

Existing constraints to preserve:
- Context identity structure from review context resolution (`working_tree` vs `commit_range`).
- Store pathing and write behavior under `.commentry/contexts/...`.
- File-reviewed boolean remains lightweight signal, not hard execution gate.

### User Flows

**Flow 1: Send Review to Codex Session**
1. User opens Commentry review context.
2. User invokes `Send to Codex Session`.
3. System builds payload from full review, active (non-stale) items only.
4. System validates active attached target.
5. System sends payload via selected adapter.
6. System shows immediate send outcome (success/failure) without persisting send-history artifacts.

**Flow 2: Resend After Review Updates**
1. User resolves/edits comments in Commentry.
2. User sends again.
3. System sends the latest active review content.
4. No send history is persisted in v1.

**Flow 3: No Attached Session**
1. User invokes send with no active target attachment.
2. System returns explicit actionable message (attach first).
3. No payload is lost; user can retry after attach.

### Acceptance Criteria (v1)

| Scenario | Expected Outcome |
|---|---|
| Send with attached session target | Payload from active (non-stale) review items is sent via the selected adapter; user receives immediate success feedback. |
| Send with no attached target | Send is blocked with actionable remediation and no payload dispatch occurs. |
| Transport failure during send | User receives explicit failure with normalized error and can retry from current review context. |
| Resend flow | Re-send from updated review remains deterministic: active items only, no persisted send history in v1. |
| Provenance safety | Outbound payload uses repo-relative provenance only; absolute local paths are not sent. |
| Testing gate | Feature implementation must include required tests before first implementation merge. |

### Error Handling

- **No target attached:** Block send and return explicit remediation.
- **Transport failure:** Return normalized error to user and allow immediate retry.
- **Stale content risk:** Exclude stale/invalidated items from payload; prompt user to reconcile review state before resending.
- **Ambiguous/weak review text:** Preserve content as-is and rely on manual review iteration in v1.

### Constraints

- v1 has no performance-specific requirements; do not block release on latency/throughput targets.
- Behavior must stay compatible with existing local store semantics and context identity model.
- Transport adapter behavior must preserve payload semantics across implementations.
- Outbound payload provenance must be repo-relative only (no absolute local filesystem paths).
- Required tests must land before first implementation merge.

### Integration Points

- Reuse existing `:Commentry` command architecture (`lua/commentry/commands.lua`).
- Leverage existing context identity and review-context resolution (`lua/commentry/diffview.lua`).
- Reuse existing store-backed review state without adding send-history persistence in v1 (`lua/commentry/store.lua`, `lua/commentry/comments.lua`).
- Keep optional integrations (like Sidekick) behind adapter boundaries.

---

## Out of Scope

The following are explicitly excluded from v1:

- Beads integration and review-to-beads conversion
- Beads continuity proof artifacts
- Multi-person collaboration workflows
- Cross-repo or multi-workspace routing
- Hard blocking/governance mode
- Separate summarize-only product mode

---

## Spec Review

**Reviewed:** 2026-02-26
**Gaps identified:** 6
**Gaps resolved:** 6

### Clarifications Added

| Topic | Clarification |
|---|---|
| Acceptance criteria | Added scenario matrix for send/no-target/failure/retry behavior and explicit v1 test gate. |
| Adapter selection | v1 uses global/implicit adapter selection from active attachment; no per-send selector. |
| Metadata storage | Multi-model follow-up simplified v1 to send-and-forget; no send snapshot/disposition persistence in v1. |
| Payload scope wording | Clarified to active (non-stale) items, avoiding conflict with current `unresolved` status semantics. |
| Constraints | Explicitly no performance gating requirements in v1. |
| Safety | Added outbound provenance constraint (repo-relative only) and normalized adapter errors. |

### Deferred Items

| Item | Rationale | Revisit When |
|---|---|---|
| Q98: Review-to-Beads conversion | Beads integration deferred in v1 | v2 Beads exploration |
| Q103: Multi-person collaboration flow | Product boundary is solo-only | If product boundary changes |
| Q122: Beads continuity proof artifact | Depends on Beads integration strategy | v2 Beads exploration |

---

## Multi-Model Review

**Reviewed:** 2026-02-26
**Models:** OpenAI GPT 5.3 Codex
**Issues Found:** 5 (1 critical, 2 high, 2 medium, 0 low)

### Findings Addressed

| # | Issue | Resolution |
|---|-------|------------|
| 1 | Snapshot/disposition persistence mismatch with current store model | v1 simplified to send-and-forget; no persisted send snapshot/disposition model. |
| 2 | `unresolved` status semantic mismatch | Spec now uses active (non-stale) item wording for payload scope. |
| 3 | Missing adapter contract clarity | v1 now specifies minimal core adapter contract (`send(payload, target)` + normalized errors). |
| 4 | Provenance leakage risk | Spec now requires repo-relative-only outbound provenance and no absolute paths. |
| 5 | Test-plan underspecified | Spec now requires tests before first implementation merge. |

### Ambiguities Resolved

| Topic | Decision | Rationale |
|-------|----------|-----------|
| Snapshot/disposition model | Send-and-forget v1; no persistence | Lowest-complexity v1 cut and aligns with current no write-back integration. |
| Adapter strictness | Minimal core contract | Keeps consistency while allowing adapter-specific internals. |
| Provenance policy | Repo-relative only | Prevents leaking local filesystem identity. |
| Test gating | Required pre-merge | Prevents behavior drift and regression risk. |

### Deferred Items

- Send/disposition persistence can be revisited in a later phase if write-back integration is introduced.
- Existing deferred scope items (Q98, Q103, Q122) remain deferred to v2/future scope.

---

## Next Steps

- [ ] Review this spec for alignment with transport-first scope.
- [x] Run spec review (questions interview) and resolve critical gaps.
- [ ] Define minimal adapter interface contract and payload schema for v1 send-and-forget flow.
- [ ] Create implementation plan and split into beads issues.

---

## Appendix: Source Files

- `plans/codex-integration/01-scope/questions.md` - Original scope questions
- `plans/codex-integration/01-scope/context.md` - Codebase context
- `plans/codex-integration/01-scope/question-triage.md` - Question analysis
