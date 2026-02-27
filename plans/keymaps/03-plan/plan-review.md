# Plan Review: keymaps

**Generated:** 2026-02-27
**Reviewers:** Forward (spec->plan), Reverse (plan->spec), Context (plan->codebase)

---

## Summary

| Category | P0 | P1 | P2 | Total |
|----------|----|----|----|----|
| Coverage Gaps | 0 | 1 | 1 | 2 |
| Scope Creep | 0 | 0 | 2 | 2 |
| Codebase Misalignment | 0 | 1 | 1 | 2 |
| Consistency Issues | 0 | 0 | 1 | 1 |
| **Total** | **0** | **2** | **5** | **7** |

---

## P0 Findings (Must Fix)

No P0 findings.

---

## P1 Findings (Should Fix)

### 1. Missing explicit validation coverage for invalid mapping behavior [CORROBORATED]
- **Category:** Coverage Gaps
- **Found by:** Forward + Context (corroborated)
- **What:** The plan states setup warnings/runtime guards, but acceptance/test wording does not explicitly cover invalid non-empty keymap values and no-silent-failure verification.
- **Evidence:** Forward flagged missing explicit verification for actionable warning/no-silent-failure paths; context flagged underspecified invalid non-empty value behavior.
- **Action:** Update plan
- **Recommendation:** Add explicit acceptance criterion and test bullet: invalid keymap values (including invalid non-empty) must emit actionable warnings and preserve resilient runtime behavior.

### 2. Command fallback audit lacks explicit source-of-truth anchor
- **Category:** Codebase Misalignment
- **Found by:** Context
- **What:** Phase 2.2 says to audit fallback claims but does not explicitly require checking against the concrete `:Commentry` subcommand registry.
- **Action:** Update plan
- **Recommendation:** Add a specific verification bullet in Phase 2.2/Phase 4.2 referencing command registry parity checks in `lua/commentry/commands.lua`.

---

## P2 Findings (Consider)

### 3. Scope decision traceability is compressed
- **Category:** Coverage Gaps
- **Found by:** Forward
- **What:** The 40-item scope decision set is summarized into high-level plan decisions without per-decision task mapping.
- **Recommendation:** Add a short appendix mapping key P0 decisions to specific tasks/checks for audit clarity.

### 4. Shared abstractions section may be over-documented
- **Category:** Scope Creep
- **Found by:** Reverse
- **What:** The section mostly restates existing module ownership and may add maintenance overhead.
- **Recommendation:** Keep only if needed for execution handoff; otherwise trim.

### 5. Separate plan coverage matrix may duplicate review artifacts
- **Category:** Scope Creep
- **Found by:** Reverse
- **What:** Matrix duplicates traceability effort and could drift.
- **Recommendation:** Keep one authoritative traceability artifact or tighten upkeep expectations.

### 6. Matrix section reference mismatch
- **Category:** Consistency Issues
- **Found by:** Forward
- **What:** Matrix references `Key Files Reference`, but plan section is `Appendix: Key File Paths`.
- **Recommendation:** Fix the row label to point to the actual section name.

### 7. Wording tension around no-silent-failure path
- **Category:** Codebase Misalignment
- **Found by:** Context
- **What:** Some invalid mapping paths rely on guards; messaging expectations should be explicit across setup/runtime.
- **Recommendation:** Clarify in plan text that guard-only skips still require actionable user feedback when applicable.

---

## Coverage Summary

**Forward (Spec->Plan):**
- Fully covered: 18 sections
- Partially covered: 3 sections
- Not covered: 0 sections

**Reverse (Plan->Spec):**
- Spec-backed: 9 tasks
- Spec-implied: 0 tasks
- Infrastructure: 0 tasks
- Scope creep: 0 tasks

**Context Alignment:**
- Aligned: 9 decisions
- Contradicts: 0 decisions
- Unverifiable: 1 decisions
