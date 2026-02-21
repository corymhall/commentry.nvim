# Agent Cheat Sheet

This repository contains `commentry.nvim`, a Neovim plugin scaffolded from `folke/sidekick.nvim`.
The core structure, scripts, and tests are copied from that repo to serve as a starting point.

## Project Overview

- Core modules currently live under `lua/commentry/` (rename as the plugin evolves).
- Tests are written with `mini.test` and live in `tests/`.
- Docs are currently stubbed via `./scripts/docs` and `lua/commentry/docs.lua`.
- Code style uses `stylua` / `selene` configs copied from the base (add or adjust as needed).

## Everyday Commands

- `./scripts/test` – runs the `mini.test` suite using the Lazy.nvim harness; set `LAZY_OFFLINE=1` to skip bootstrap downloads.
- `./scripts/docs` – regenerates docs in `README.md` from the snippets in `tests/readme.lua`.
- `stylua lua tests` – format Lua source and tests when needed.
- `selene` – lint Lua files (if selene is installed in the environment).

## Adding Features

- Add new config options in `lua/commentry/config.lua` and update docs as they evolve.
- Prefer table-driven tests for combinatorial cases.
- If you rename the module namespace, keep tests and docs aligned with the new path.

## Writing Tests

- Use `mini.test` assertions (`assert.are.same`, `assert.is_true`, etc.).
- Stub Neovim APIs carefully and restore them in `after_each` hooks.
- For upvalue-based helpers, use `debug.setupvalue`.

## Things to Watch

- The repo may run in headless CI where network calls are blocked; avoid external fetches in tests.
- Docs generation is currently a stub; update `lua/commentry/docs.lua` as needed.
- Maintain ASCII unless the surrounding context already uses Unicode.

## Useful Paths

- Core module tree: `lua/commentry/`
- Tests entry point: `tests/minit.lua`

Keep this sheet handy when automating changes or onboarding new agents.

## Active Technologies
- Lua (Neovim 0.9+) + Neovim runtime, `mini.test` (tests), optional (001-diff-line-comments)
- Local filesystem (project-scoped draft comment store) (001-diff-line-comments)

## Recent Changes
- 001-diff-line-comments: Added Lua (Neovim 0.9+) + Neovim runtime, `mini.test` (tests), optional
