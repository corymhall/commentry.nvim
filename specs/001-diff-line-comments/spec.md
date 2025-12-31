# Feature Specification: Diff Line Comments

**Feature Branch**: `001-diff-line-comments`  
**Created**: 2025-12-31  
**Status**: Draft  
**Input**: User description: "initial neovim plugin implemenation that allows the user to open a diff view of the changes in the current local project repo. The user can use a keymap to interact with specific lines in the diff e.g. add comment. The user can add comments to the line which will be persisted so the user can edit/delete before submitting. The initial implementation does not include the submit piece"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Open diff for local changes (Priority: P1)

As a user, I can open a diff view of changes in the current local project so I
can review what changed before adding comments.

**Why this priority**: Without a diff view there is no review surface to work on.

**Independent Test**: From a project with local changes, I can open the diff view
and see the changed files and lines.

**Acceptance Scenarios**:

1. **Given** a project with local changes, **When** I open the diff view, **Then**
   I see a diff for those changes.
2. **Given** a project with no local changes, **When** I open the diff view,
   **Then** I see an empty state indicating no changes.

---

### User Story 2 - Add and manage draft comments (Priority: P1)

As a user, I can attach a comment to a specific diff line and edit or delete it
before submission so I can refine feedback.

**Why this priority**: Line comments are the core interaction for review.

**Independent Test**: I can add a comment to a line, edit it, and delete it
without leaving the diff view.

**Acceptance Scenarios**:

1. **Given** an open diff view, **When** I trigger the add-comment keymap on a
   line, **Then** a draft comment is created for that line.
2. **Given** an existing draft comment, **When** I edit it, **Then** the updated
   text replaces the prior draft content.
3. **Given** an existing draft comment, **When** I delete it, **Then** it is
   removed from the draft list and from the line display.

---

### User Story 3 - Persist draft comments (Priority: P2)

As a user, I can close and reopen the project and still see my draft comments so
I do not lose review work in progress.

**Why this priority**: Persistence prevents accidental loss and enables longer
review sessions.

**Independent Test**: After restarting the editor, my previously created draft
comments reappear on the same diff lines.

**Acceptance Scenarios**:

1. **Given** draft comments exist, **When** I close and reopen the editor,
   **Then** the comments reappear in the diff view.
2. **Given** draft comments exist, **When** I open the diff view in the same
   project, **Then** comments appear at their original locations.

---

### Edge Cases

- What happens when the diff is empty and the user tries to add a comment?
- What happens when a previously commented line no longer exists in the diff?
- How does the system handle multiple comments on the same line?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST open a diff view of local project changes on demand.
- **FR-002**: User MUST be able to focus a specific line in the diff and invoke
  an add-comment action via a keymap.
- **FR-003**: System MUST create a draft comment bound to the selected diff line.
- **FR-004**: System MUST allow users to edit and delete draft comments.
- **FR-005**: System MUST persist draft comments across editor restarts.
- **FR-006**: System MUST show draft comments in the diff view at their bound
  lines.
- **FR-007**: System MUST NOT include a submit/review publishing flow in this
  release.

Assumptions:
- The current project has local changes that can be displayed as a diff.
- Draft comments are scoped to the current project.

Dependencies:
- Access to local project changes within the current project context.
- `diffview.nvim` installed and available in Neovim.

### Key Entities *(include if feature involves data)*

- **Diff View**: The view of current local project changes shown to the user.
- **Draft Comment**: A user-authored note attached to a specific diff line.
- **Comment Thread**: A collection of draft comments on the same line.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can open a diff view and add a comment to a line in under
  60 seconds in a typical project.
- **SC-002**: 100% of draft comments persist across closing and reopening the
  editor for the same project.
- **SC-003**: 95% of comments remain attached to the intended line when the diff
  is reopened without further code changes.
- **SC-004**: Users report they can locate and edit an existing draft comment
  without leaving the diff view.
