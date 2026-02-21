# Data Model: Diff Line Comments

## Entities

### Diff View

- **Fields**: id, project_root, base_ref, head_ref, files[]
- **Purpose**: Represents the current local change set being reviewed.
- **Relationships**: Diff View 1 → many Draft Comments

### Draft Comment

- **Fields**: id, diff_id, file_path, line_number, line_side, body, created_at,
  updated_at, status
- **Purpose**: A user-authored note bound to a specific diff line.
- **Relationships**: Draft Comment belongs to Diff View; Draft Comment belongs to
  Comment Thread (optional)
- **Validation**:
  - file_path required
  - line_number required (integer > 0)
  - line_side is one of: base, head
  - body required and non-empty

### Comment Thread

- **Fields**: id, diff_id, file_path, line_number, line_side, comment_ids[]
- **Purpose**: Groups comments attached to the same line.
- **Relationships**: Comment Thread 1 → many Draft Comments

### Comment Store

- **Fields**: project_root, diff_id, comments[], threads[]
- **Purpose**: Persistent storage for draft comments in a project.

## State Transitions

- Draft Comment: created → edited → deleted
- Diff View: opened → closed → reopened

## Notes

- Deleted comments are removed from the store in this initial release.
- Threads are derived from comment location; no explicit user action needed.
