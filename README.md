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

`commentry.nvim` provides a `:Commentry` command. Subcommands can be registered
by the plugin as features are added.

## Development

- Run tests: `./scripts/test`
- Generate docs (stub): `./scripts/docs`
