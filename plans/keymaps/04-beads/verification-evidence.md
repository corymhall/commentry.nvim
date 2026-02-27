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

## com-1yvo.13 - Final verification sweep (automated + manual smoke checks)

Date: 2026-02-27

### Automated suite

- Command: `./scripts/test`
- Result: pass (`124` cases, `12` groups, `Fails (0) and Notes (0)`).
- Notes: first run bootstrapped test deps (`lazy.nvim`, `mini.test`, `luassert`, `hererocks`) and then completed successfully.

### Manual smoke checks

- Command: `nvim --headless -u NONE -n -l /tmp/commentry_manual_smoke.lua`
- Result: `MANUAL_SMOKE_OK`
- Captured output:
  - `non_diff_keymaps=nil`
  - `diff_keymaps=true`
  - `diff_maps_before=6 diff_maps_after=6`
  - `fallback_calls=1,1,1,1`

### Manual check interpretation

- Non-diffview buffer check passed: no keymaps attached when `commentry_diffview` is false (`lua/commentry/commands.lua:114`, `lua/commentry/commands.lua:121`).
- Diffview buffer check passed: keymaps attach when `commentry_diffview` is true, and a second trigger does not add duplicate mappings (`lua/commentry/commands.lua:125`, `lua/commentry/commands.lua:130`, `lua/commentry/commands.lua:154`).
- Command-backed fallback entrypoints are present and callable through the command registry:
  - `add-range-comment` (`lua/commentry/commands.lua:210`)
  - `set-comment-type` (`lua/commentry/commands.lua:214`)
  - `toggle-file-reviewed` (`lua/commentry/commands.lua:218`)
  - `next-unreviewed` (`lua/commentry/commands.lua:222`)
