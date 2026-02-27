# Keymaps Verification Evidence

## com-1yvo.8 - Confirm command fallback claims remain accurate

Date: 2026-02-27

Source of truth audited: `lua/commentry/commands.lua` command registry (`M.register(...)`).

### Registry proof (exact command entries)

- `M.register("add-range-comment", ...)` -> `Comments.add_range_comment()` (`lua/commentry/commands.lua:210`)
- `M.register("set-comment-type", ...)` -> `Comments.set_comment_type()` (`lua/commentry/commands.lua:214`)
- `M.register("toggle-file-reviewed", ...)` -> `Comments.toggle_file_reviewed()` (`lua/commentry/commands.lua:218`)
- `M.register("next-unreviewed", ...)` -> `Comments.next_unreviewed_file()` (`lua/commentry/commands.lua:222`)

### Fallback-claim alignment audit

- `plans/keymaps/02-spec/spec.md:167` fallback verification list references only command-backed actions and matches the four registry entries above.
- `plans/keymaps/03-plan/plan.md:110` now lists the same exact four command-backed actions.
- `README.md` and `doc/commentry.txt` do not claim fallback behavior for non-command actions (`add_comment`, `edit_comment`, `delete_comment`).

### Command surface regression check

- No `lua/commentry/commands.lua` command registrations were added or removed during this task.
