# Plan Review: codex-integration

**Generated:** 2026-02-26
**Reviewers:** Forward (spec->plan), Reverse (plan->spec), Context (plan->codebase)

---

## Summary

| Category | P0 | P1 | P2 | Total |
|---|---:|---:|---:|---:|
| Coverage Gaps | 0 | 0 | 5 | 5 |
| Scope Creep | 0 | 0 | 2 | 2 |
| Codebase Misalignment | 0 | 3 | 0 | 3 |
| Consistency Issues | 0 | 1 | 4 | 5 |
| **Overall** | **0** | **4** | **11** | **15** |

---

## P0 Findings (Must Fix)

- none

---

## P1 Findings (Should Fix)

- [Codebase Misalignment] `[CORROBORATED]` Fine-grained integration behavior is not explicitly mapped from plan tasks to the concrete module surfaces named in the spec context (`lua/commentry/commands.lua`, `lua/commentry/diffview.lua`, `lua/commentry/store.lua`, `lua/commentry/comments.lua`), leaving traceability gaps between requirements and implementation boundaries. **Recommendation:** Update plan with explicit task-level acceptance rows that map each listed integration surface to exact testable behaviors. **Action:** Update plan.
- [Codebase Misalignment] `tests/commentry_health_spec.lua` is omitted as an explicit verification surface despite the review context calling out health integration points, while plan adds health reporting behavior. **Recommendation:** Update plan and test matrix to include explicit health assertion coverage for enabled/disabled/absence-of-adapter states. **Action:** Update plan.
- [Codebase Misalignment] Payload extraction is planned as new selector logic instead of explicitly reusing/constraining against existing `comments.lua` active-item semantics (`exportable_comments(context)`), risking drift from canonical active/stale behavior. **Recommendation:** Update plan to reference and/or wrap the existing context extraction path and add a regression test proving parity. **Action:** Update plan.

---

## P2 Findings (Consider)

- [Coverage Gaps] Matrix mapping is directionally correct but over-aggregated: spec scope-question IDs, all P0/P1 decision IDs, and per-bullet constraints are not mapped one-to-one to named plan/test artifacts. **Recommendation:** Update plan matrix so every spec question/decision ID has an explicit owning task or acceptance test ID. **Action:** Update plan.
- [Coverage Gaps] Some clarifications/ambiguities are described without explicit linked test assertions, so "covered" items lack immediate verification evidence. **Recommendation:** For each clarification bullet, add explicit assertion-bearing task entries and test names in the plan matrix. **Action:** Update plan.
- [Coverage Gaps] Acceptance criteria are not always cross-linked to concrete test file-level IDs for every scenario, especially around exclusion/compliance edges. **Recommendation:** Expand the acceptance matrix with explicit links to test artifacts and named scenarios. **Action:** Update plan.
- [Scope Creep] Config namespace + adapter-selection plumbing plus additional health/documentation updates are broader than the strict v1 send path and are acceptable but not explicitly marked as non-blocking v1 extras. **Recommendation:** Keep these items but annotate as optional/evolutionary to prevent scope ambiguity and accidental hard requirements. **Action:** Update plan.
- [Consistency Issues] Security hardening is only partially specified in planning context (path normalization present, broader safeguards not); payload redaction/size/PII constraints remain implicit. **Recommendation:** Add explicit security checklist items and tests (or explicitly accept as out-of-scope) to avoid regressions. **Action:** Update plan.
- [Consistency Issues] The spec's "no performance gating in v1" constraint is not converted into an explicit checklist/no-go criterion in execution tasks. **Recommendation:** Add an explicit closure criterion documenting this as a non-blocking constraint for this phase. **Action:** Update plan.
- [Consistency Issues] Multi-repo/segment and cross-person workflow boundaries are discussed but not consistently captured as concrete validation checks. **Recommendation:** Add explicit tests or explicit deferrals for each boundary condition. **Action:** Update plan.
- [Consistency Issues] No-target hard-fail and resend/update user-story edges are described behaviorally but should be captured as named test IDs in a single place in plan matrix for easier audit consistency. **Recommendation:** Add explicit matrix rows for these edge-case flows and acceptance criteria IDs. **Action:** Update plan.
- [Consistency Issues] Out-of-scope bullets (e.g., multi-person/cross-workspace/beads continuity) are noted but not consistently encoded as explicit exclusion constraints, causing future interpretation drift. **Recommendation:** Add explicit "Exclusions" rows and keep them immutable for plan phase. **Action:** Update plan.

---

## Coverage Summary

- Forward review (spec->plan): 25 sections reviewed, 11 fully covered, 14 partially covered, 0 not covered.
- Reverse review (plan->spec): 16 tasks reviewed, 11 spec-backed, 0 unbacked, 5 infrastructure (acceptable), 0 scope creep, 0 gold-plating.
- Context review (plan->codebase): 8 architecture decisions checked, 8 aligned, 0 contradictions, 0 not verifiable.

---

## Resolution Decisions

**Resolved on:** 2026-02-26

- **P0 resolved:** 0 of 0
- **P1 resolved:** 3 of 3
- **P2 resolved:** 0 of 11 (skipped)
- **Plan updated:** Yes
- **Spec updated:** No

Applied plan updates:
- Added explicit integration-surface mapping for `commands.lua`, `diffview.lua`, `comments.lua`, `store.lua`, and `health.lua`.
- Added explicit health test coverage expectations and `tests/commentry_health_spec.lua` in tasking and appendix.
- Bound payload active/non-stale behavior to existing `comments.lua` export semantics and added parity-test requirement.
