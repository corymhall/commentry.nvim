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
