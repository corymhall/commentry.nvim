# Spec Review: keymaps

## Review Configuration

- **Spec:** `plans/keymaps/02-spec/spec.md`
- **Models Used:** OpenAI GPT 5.3 Codex
- **Categories:** All (Codebase Match, Cross-Document Consistency, API/Interface, Security, Design, TDD, Standards, Architecture, Error Handling, Performance, Data/Schema, Acceptance Criteria)
- **Context Source:** Existing `plans/keymaps/01-scope/context.md`

## Model Comparison

| # | Issue | OpenAI GPT 5.3 Codex | Agree? |
|---|---|---|---|
| 1 | Remap-only conflicts with empty-string disable behavior | Found contract/code mismatch; recommends either documenting selective disable behavior or explicitly scoping breaking change + migration. | N/A (single lane) |
| 2 | Actionable feedback requirement not matched by attach path | Found no validation/error path for invalid mappings; recommends defining validation point + warn/error behavior. | N/A (single lane) |
| 3 | Command fallback criterion over-broad | Found `:Commentry` command coverage does not include add/edit/delete; recommends narrowing criterion or adding commands. | N/A (single lane) |
| 4 | Verification checklist exceeds current tests | Found missing tests for keymap attachment/default preservation; recommends explicit attach/skip/idempotency/default retention tests. | N/A (single lane) |
| 5 | Optional-key design inconsistency | Found contradiction between “preserve optional guards” and strict non-empty remap semantics; recommends choosing one model explicitly. | N/A (single lane) |

## All Issues by Severity

### CRITICAL (0 issues)

None.

### HIGH (2 issues)

**1. Remap-Only Contract Conflicts With Current Empty-String Disable Behavior**
- **What:** The spec states v1 remap-only with non-empty strings, but runtime currently allows empty strings to skip key binding for two actions.
- **Where:** `plans/keymaps/02-spec/spec.md`; `lua/commentry/commands.lua:113`; `lua/commentry/commands.lua:119`; `plans/keymaps/01-scope/context.md`
- **Evidence:** Keymaps for `toggle_file_reviewed` and `next_unreviewed_file` are conditionally attached only when non-empty.
- **Recommendation:** Either document selective disable semantics as v1 behavior, or explicitly mark this as breaking behavior change with migration plan.
- **Ambiguity:** Should v1 preserve current empty-string disable for those two keys, or intentionally remove it now?

**2. “No Silent Failure / Actionable Feedback” Not Matched by Current Attach Path**
- **What:** The spec requires actionable feedback for invalid mappings, but code has no validation/reporting path and silently skips some entries.
- **Where:** `plans/keymaps/02-spec/spec.md`; `lua/commentry/commands.lua:113`; `lua/commentry/commands.lua:119`; `lua/commentry/config.lua`
- **Evidence:** No config-time or attach-time validation branch exists for malformed/empty mapping values.
- **Recommendation:** Define validation location (`Config.setup` vs attach), failure mode (warn vs error), and per-key handling.
- **Ambiguity:** Should invalid mappings fail setup, warn at runtime, or both?

### MEDIUM (2 issues)

**3. Fallback Command Criterion Is Over-Broad**
- **What:** Acceptance criterion says underlying commands remain fallback for mapped actions, but not all mapped actions have commands.
- **Where:** `plans/keymaps/02-spec/spec.md`; `lua/commentry/commands.lua`
- **Evidence:** No `:Commentry add-comment`, `edit-comment`, or `delete-comment` command is registered.
- **Recommendation:** Narrow criterion to existing command-covered actions, or add missing commands.
- **Ambiguity:** Should scope expand to add these commands, or should spec narrow to existing command surface?

**4. Verification/TDD Expectations Exceed Current Coverage**
- **What:** The spec’s verification checklist requires keymap-attachment regression tests that do not currently exist.
- **Where:** `plans/keymaps/02-spec/spec.md`; `tests/commentry_commands_spec.lua`
- **Evidence:** Existing tests target command routing/completion/send paths, not attach-keymap behavior.
- **Recommendation:** Add explicit tests for diffview-only attachment, non-diffview skip, idempotent attachment, and default retention under partial overrides.

### LOW (1 issue)

**5. Internal Spec Inconsistency on Optional Keys**
- **What:** The design simultaneously says to preserve optional key guards and enforce strict non-empty remap semantics.
- **Where:** `plans/keymaps/02-spec/spec.md`
- **Evidence:** Conflicting statements in design vs error-handling semantics.
- **Recommendation:** Pick one consistent v1 model and align all sections.

## Reasoning

- Single-lane synthesis: no cross-model disagreement analysis applies in this run.
- Findings are internally consistent and directly traceable to current code/spec artifacts.

## Ambiguities Summary

| # | Issue | Ambiguity | Options |
|---|---|---|---|
| 1 | Remap-only vs current behavior | Preserve or remove empty-string disable for two keys in v1? | A) Preserve current selective disable, B) Remove now (breaking), C) Preserve now and deprecate for v2 |
| 2 | Invalid mapping handling | How strict should validation/feedback be? | A) Warn only, B) Setup error, C) Setup warn + runtime guard |
| 3 | Command fallback scope | Should add/edit/delete get commands? | A) Add commands, B) Narrow criterion to existing command surface |

## Summary

- **Total Issues:** 5 (0 critical, 2 high, 2 medium, 1 low)
- **Ambiguities Requiring Decision:** 3
- **Model Agreement Rate:** N/A (single model lane)
- **Selected Lanes:** Codex
- **Model Lanes That Failed:** None
