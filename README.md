# commentry.nvim

Neovim plugin scaffold for code review workflows on AI-generated changes.

## Install

Using lazy.nvim:

```lua
{
  "commentry/commentry.nvim",
  dependencies = { "sindrets/diffview.nvim" },
  opts = {},
}
```

`diffview.nvim` is required for the diff UI.

## Setup

```lua
require("commentry").setup({
  diffview = {
    comment_cards = {
      max_width = 88,
      max_body_lines = 8,
      show_markers = true,
    },
    comment_ranges = {
      enabled = true,
      line_highlight = true,
    },
  },
})
```

## Commands

`commentry.nvim` provides a `:Commentry` command with subcommands.

- `:Commentry open` opens a diffview for local changes (shortcut).
- `:Commentry list-comments` opens a picker for draft comments on the current file/side.
- `:Commentry set-comment-type` sets default or per-comment type (`note`, `suggestion`, `issue`, `praise`).
- `:Commentry toggle-file-reviewed` toggles reviewed status for the current diff file.
- `:Commentry next-unreviewed` jumps to the next unreviewed diff file in panel order.
- `:Commentry export` prints deterministic markdown for active draft comments.
- `:Commentry export register` writes markdown to the unnamed register.
- `:Commentry export register:<name>` writes markdown to a specific register (for example `register:a`).
- `:Commentry debug-store` prints the active review context and the exact on-disk store path.
- `:Commentry send-to-codex` sends the current review payload to Codex using the attached Sidekick session target.

If you open diffview directly (for example `:DiffviewOpen main`), Commentry will
auto-attach to diff buffers by default.

You can disable auto-attach with:

```lua
require("commentry").setup({
  diffview = {
    auto_attach = false,
  },
})
```

## Keymap Configuration

Commentry supports seven configurable diffview-local keymap actions:

| Action | Default | Mode | Empty-string disable (`""`) | Command fallback |
| --- | --- | --- | --- | --- |
| `add_comment` | `mc` | Normal | No | None |
| `add_range_comment` | `mc` | Visual | No | `:Commentry add-range-comment` |
| `edit_comment` | `me` | Normal | No | None |
| `delete_comment` | `md` | Normal | No | None |
| `set_comment_type` | `mt` | Normal | No | `:Commentry set-comment-type` |
| `toggle_file_reviewed` | `mr` | Normal | Yes | `:Commentry toggle-file-reviewed` |
| `next_unreviewed_file` | `]r` | Normal | Yes | `:Commentry next-unreviewed` |

Notes:

- Keymaps attach only in buffers marked as Commentry diffview buffers.
- Empty-string disable is intentionally scoped to `toggle_file_reviewed` and `next_unreviewed_file`.
- For remap-only actions (`add_comment`, `add_range_comment`, `edit_comment`, `delete_comment`, `set_comment_type`), `""` is invalid and setup warns, then default/effective mapping remains active.
- `add_range_comment` mapping falls back to the resolved `add_comment` mapping when unset; if that is also unavailable, it falls back to its default (`mc`).

Example override (partial remap + selective disable):

```lua
require("commentry").setup({
  keymaps = {
    add_comment = "gc",
    add_range_comment = "gc",
    edit_comment = "ge",
    delete_comment = "gd",
    set_comment_type = "gt",
    toggle_file_reviewed = "",
    next_unreviewed_file = "]u",
  },
})
```

Example keep defaults except one mapping:

```lua
require("commentry").setup({
  keymaps = {
    next_unreviewed_file = "]n",
  },
})
```

## Development

- Run tests: `./scripts/test`
- Generate docs (stub): `./scripts/docs`
- Canonical feature/design plans: `docs/plans/`
- Legacy Speckit archive (read-only history): `docs/archive/speckit/`

## Behavior Notes

- Draft comments are persisted per review context under `~/.commentry/repos/<repo>/contexts/<context-id>/`.
- Review context identity is stable per repository review scope (`<root>::review`), so comments persist across
  different `:DiffviewOpen` range lenses until anchors become outdated by code changes.
- Add/edit/range comment actions open a floating multiline editor (`Enter` for newline, `Ctrl-s` to save, `q`/`Esc` in normal mode to cancel, `Tab` to cycle type).
- Draft comment bodies are rendered as persistent boxed cards on commented lines, even when the cursor moves away.
- Range comments render start/mid/end gutter signs (`╭`, `│`, `╰`) with subtle line tinting to show covered lines.
- File reviewed state is tracked per context and rendered as a lightweight `[reviewed]` / `[unreviewed]` indicator in diff buffers.
- Send flow is explicit: open/attach a review (`:Commentry open` or auto-attach), ensure Codex integration is enabled, then run
  `:Commentry send-to-codex`.
- Adapter behavior is global/implicit in v1: the configured adapter resolves the currently attached session target.
  A valid adapter runtime and attached target are required.
- `send-to-codex` requires an attached active review context. Running it outside an attached review buffer/context fails.
- Send is send-and-forget in v1: Commentry dispatches a compact human-readable payload (`COMMENTRY_REVIEW_V1`) once
  and reports success/failure in Neovim messages.
- v1 does not persist send history, delivery receipts, retries, or any outbound queue state.

## Troubleshooting

- Draft store file does not exist yet:
  Commentry creates `~/.commentry/repos/<repo>/contexts/<context-id>/commentry.json` lazily on first successful write
  (add/edit/delete comment, set type, toggle reviewed). If no writes happened in that context yet, the file is absent.
- Wrong context:
  review context is repository-scoped (`<root>::review`) and shared across diff ranges. Comments become stale/outdated
  when anchor reconciliation detects code drift. Use `:Commentry debug-store` to confirm the active context id/path.
- Sidekick attached but send fails:
  ensure a Codex Sidekick session is attached and run `:Commentry send-to-codex` from an attached review buffer/context.
