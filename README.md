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
  -- add configuration here
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

## Development

- Run tests: `./scripts/test`
- Generate docs (stub): `./scripts/docs`
- Canonical feature/design plans: `docs/plans/`
- Legacy Speckit archive (read-only history): `docs/archive/speckit/`

## Behavior Notes

- Draft comments are persisted per review context under `.commentry/contexts/<context-id>/`.
- Context separation covers working-tree and commit-range style review sessions when Diffview provides distinct context identity.
- Draft listing and hover previews remain scoped to the active file + side (`base`/`head`) for the current context.
- File reviewed state is tracked per context and rendered as a lightweight `[reviewed]` / `[unreviewed]` indicator in diff buffers.
