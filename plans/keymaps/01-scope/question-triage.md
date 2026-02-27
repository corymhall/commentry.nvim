# Question Triage: keymaps

**Scope selected:** P0 only
**Questions in scope:** 40
**Auto-answerable:** 0
**Branch points for human:** 40

---

## ID Normalization

Source IDs were already sequential for P0. Normalized IDs are unchanged:
- Q1..Q40 (was: 1..40 in source)

---

## Auto-Answerable Questions

None for this scope.

Reason: P0 questions are mostly product/user-preference decisions where wrong assumptions are expensive. They need explicit human decisions rather than inferred defaults.

---

## Branch Points (Human Decision Required)

All P0 questions are branch points. Grouped for dialogue flow:

| IDs | Theme | Why Human Needed |
|---|---|---|
| Q1-Q10 | Baseline expectations/defaults | Defines UX contract and “complete enough” bar for v1. |
| Q11-Q20 | Onboarding and lifecycle journey | Determines where/when users configure and how success is measured. |
| Q21-Q30 | Behavioral edge cases and conflict recovery | Tradeoffs between flexibility, safety, and team conventions. |
| Q31-Q40 | Accessibility and inclusion | Depends on audience priorities and support commitments. |

---

## Question Dependencies

Early decisions unlock later answers:

- **Q2 (all functions mappable vs subset)** unlocks Q4, Q12, Q16, Q20.
- **Q7 (disable-per-function support)** unlocks Q21, Q26, Q31-Q40 impact level.
- **Q9 (distinct mappings for similar actions)** unlocks Q22, Q27, Q29.
- **Q11 (onboarding moment)** unlocks Q12, Q13, Q14, Q15.
- **Q19 (global vs per-project evolution)** unlocks Q5, Q17, Q18.
- **Q31/Q32 (ergonomic constraints)** unlock Q33, Q38, Q39.

---

## Interview Plan

**Round 1: Core product shape** (~6 questions)
1. Q2 - Full per-function coverage vs subset
2. Q7 - Remap-only vs remap+disable
3. Q9 - Distinct mappings for similar actions
4. Q11 - Onboarding/configuration entry point
5. Q19 - Global vs per-project configuration model
6. Q31 - Accessibility commitment level

**Round 2: Cascaded confirmations** (~10 questions)
- Confirm defaults/discoverability/safety implied by Round 1: Q1, Q3, Q4, Q5, Q8, Q10, Q12, Q14, Q16, Q21.

**Round 3: Remaining standalone branch points** (~24 questions)
- Complete remaining journey/edge/accessibility items: Q6, Q13, Q15, Q17, Q18, Q20, Q22-Q30, Q32-Q40.

---

**Estimated dialogue:** ~40 human questions, 0 auto-noted
