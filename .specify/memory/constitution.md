<!--
Sync Impact Report
- Version change: N/A -> 0.1.0
- Modified principles: N/A (initial fill from template)
- Added sections: Core Principles (filled), Scope Boundaries & Non-Goals, Intended Workflows & Terminology, Governance (filled)
- Removed sections: None
- Templates requiring updates:
  - ✅ .specify/templates/plan-template.md
  - ✅ .specify/templates/tasks-template.md
  - ✅ .specify/templates/spec-template.md (reviewed, no changes needed)
  - ✅ .specify/templates/checklist-template.md (reviewed, no changes needed)
  - ⚠ .specify/templates/commands/*.md (directory missing)
- Follow-up TODOs:
  - TODO(RATIFICATION_DATE): ratification date not found in repo history
-->
# commentry.nvim Constitution

## Core Principles

### I. Review-First Workflow
Every feature MUST serve the review flow: open a diff, attach comments to line
numbers, submit a review, and make the review readable by an agent. Features
that do not strengthen this flow are out of scope.

### II. Line-Accurate Annotations
Comments MUST be anchored to a specific file path and line reference (base or
head) with enough metadata to survive reloading and display consistently. The
UI MUST make the attachment point visible and unambiguous.

### III. Local-First Review Artifacts
Reviews MUST be stored locally in a transparent, text-based format that is
diff-friendly and can be consumed by other tools. Network calls are forbidden
in core flows unless explicitly enabled by the user.

### IV. Neovim-Native UX
The plugin MUST use Neovim-native primitives (buffers, extmarks, virtual text,
quickfix, signs) and avoid external GUI dependencies. Interaction should be
keyboard-first and fast in headless or offline environments.

### V. Testable, Stable Core
Changes to the data model, annotation mapping, or review export MUST include
tests that validate behavior. Backward-incompatible changes require explicit
migration guidance and a version bump.

## Scope Boundaries & Non-Goals

- Provide a local, PR-style review experience for AI-generated code diffs.
- Do NOT implement a full Git hosting client, authentication, or network sync.
- Do NOT generate AI review content; the plugin only captures and exports it.
- Avoid tight coupling to a single VCS provider; focus on generic diffs.
- Avoid long-lived background services or daemons.

## Intended Workflows & Terminology

**Workflows**
- Open diff buffer for a target change set.
- Add inline comments bound to a file path + line reference.
- Optionally edit or resolve draft comments.
- Submit a review that produces a single exportable artifact.
- Read or re-open the review for agent consumption.

**Terminology**
- Review: A collection of comments for a specific diff.
- Comment: A single annotation bound to a file path and line reference.
- Thread: A grouped set of comments at the same location.
- Draft: A comment/review not yet submitted.
- Submitted Review: An immutable exportable artifact.
- Base/Head Line: The line reference in the pre-change (base) or post-change
  (head) file, as presented in the diff.

## Governance

- This constitution is the top-level authority for specs, plans, and tasks.
- Amendments MUST update this file, record rationale, and bump the version using
  semantic versioning (MAJOR for breaking governance changes, MINOR for new
  principles/sections, PATCH for clarifications).
- All specs and implementation plans MUST include a constitution compliance
  check before design and again before implementation.
- If a change violates a principle, it MUST be rejected or accompanied by a
  documented exception and migration plan.

**Version**: 0.1.0 | **Ratified**: TODO(RATIFICATION_DATE): not found in repo history | **Last Amended**: 2025-12-31
