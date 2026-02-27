# Beads Report: keymaps

**Generated:** 2026-02-27
**Source plan:** plans/keymaps/03-plan/plan.md

---

## Creation Summary

| Level | Count |
|-------|-------|
| Feature epic | 1 |
| Phase sub-epics | 4 |
| Task issues | 9 |
| Blocker dependencies | 9 |
| Ready immediately (no blockers) | 1 |

---

## Bead ID Mapping

| Plan Reference | Bead ID | Type | Title |
|---------------|---------|------|-------|
| Feature | com-1yvo | epic | keymaps |
| Phase 1 | com-1yvo.1 | epic | Phase 1: Config Contract & Validation |
| Task 1.1 | com-1yvo.5 | task | Confirm and lock keymap schema/default invariants |
| Task 1.2 | com-1yvo.6 | task | Implement setup-time keymap validation + scoped-empty warnings |
| Phase 2 | com-1yvo.2 | epic | Phase 2: Runtime Attachment Behavior |
| Task 2.1 | com-1yvo.7 | task | Harden maybe_attach_keymaps behavior with explicit scoped rules |
| Task 2.2 | com-1yvo.8 | task | Confirm command fallback claims remain accurate |
| Phase 3 | com-1yvo.3 | epic | Phase 3: Regression Coverage |
| Task 3.1 | com-1yvo.9 | task | Add config contract tests for defaults and partial overrides |
| Task 3.2 | com-1yvo.10 | task | Add attach-path tests for diffview-only, idempotence, and selective disable |
| Task 3.3 | com-1yvo.11 | task | Run full suite and resolve regressions |
| Phase 4 | com-1yvo.4 | epic | Phase 4: Docs & Verification |
| Task 4.1 | com-1yvo.12 | task | Document keymap configuration matrix and examples |
| Task 4.2 | com-1yvo.13 | task | Final verification sweep (automated + manual smoke checks) |

---

## Dependency Graph

```text
Phase 1
  1.1 com-1yvo.5 -> 1.2 com-1yvo.6

Phase 2
  1.2 com-1yvo.6 -> 2.1 com-1yvo.7 -> 2.2 com-1yvo.8

Phase 3
  1.2 com-1yvo.6 -> 3.1 com-1yvo.9
  2.1 com-1yvo.7 -> 3.2 com-1yvo.10
  3.1 com-1yvo.9 + 3.2 com-1yvo.10 -> 3.3 com-1yvo.11

Phase 4
  2.2 com-1yvo.8 -> 4.1 com-1yvo.12
  3.3 com-1yvo.11 -> 4.2 com-1yvo.13
```

---

## Ready Queue

Items with no blockers (can start immediately):

| Bead ID | Title | Phase |
|---------|-------|-------|
| com-1yvo.5 | Confirm and lock keymap schema/default invariants | Phase 1 |

---

## Integration Branch

Feature epic: com-1yvo
Integration branch: integration/keymaps

---

## Coverage Verification

| Plan Task | Bead ID | Status |
|-----------|---------|--------|
| 1.1 Confirm and lock keymap schema/default invariants | com-1yvo.5 | Created ✓ |
| 1.2 Implement setup-time keymap validation + scoped-empty warnings | com-1yvo.6 | Created ✓ |
| 2.1 Harden `maybe_attach_keymaps` behavior with explicit scoped rules | com-1yvo.7 | Created ✓ |
| 2.2 Confirm command fallback claims remain accurate | com-1yvo.8 | Created ✓ |
| 3.1 Add config contract tests for defaults and partial overrides | com-1yvo.9 | Created ✓ |
| 3.2 Add attach-path tests for diffview-only, idempotence, and selective disable | com-1yvo.10 | Created ✓ |
| 3.3 Run full suite and resolve regressions | com-1yvo.11 | Created ✓ |
| 4.1 Document keymap configuration matrix and examples | com-1yvo.12 | Created ✓ |
| 4.2 Final verification sweep (automated + manual smoke checks) | com-1yvo.13 | Created ✓ |

**Plan tasks:** 9
**Beads created:** 9
**Coverage:** 100%

---

## Review Passes

| Pass | Result | Fixes Applied |
|------|--------|---------------|
| 1. Completeness | PASS | 1 |
| 2. Dependencies | PASS | 1 |
| 3. Clarity | PASS | 4 |
