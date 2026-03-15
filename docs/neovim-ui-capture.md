# Neovim UI Capture Workflow

This repo includes a reusable Neovim UI capture workflow for validating
Commentry's visual changes against real Neovim redraw state instead of
guessing from source code.

## Preferred path

Use the embedded RPC capture path first:

```bash
./scripts/ui-capture-rpc --preset laptop-small
./scripts/ui-capture-rpc --preset desktop-wide
./scripts/ui-capture-rpc --all-presets
```

This path uses an embedded Neovim instance and consumes real multigrid redraw
events before rendering screenshots.

## Presets

- `laptop-small`: `220x18`
- `desktop-wide`: `320x54`

Use `laptop-small` as the stricter baseline.

## Common scenarios

```bash
./scripts/ui-capture-rpc --scenario popup --preset laptop-small
./scripts/ui-capture-rpc --scenario card --preset laptop-small
./scripts/ui-capture-rpc --scenario range --preset laptop-small
```

## Output locations

Single gallery:

- `tmp/ui-capture-rpc-gallery/index.html`

Multi-preset gallery:

- `tmp/ui-capture-rpc-presets/index.html`

Compare pages:

- `tmp/ui-capture-rpc-presets/compare/popup.html`
- `tmp/ui-capture-rpc-presets/compare/card.html`
- `tmp/ui-capture-rpc-presets/compare/range.html`

## When this should just work

The current RPC capture flow is reliable for:

- normal windows and splits
- floating windows
- extmark-based inline UI
- line highlights
- cursor placement
- color/text changes visible through multigrid redraw events

## When to extend the bridge

Extend the bridge when the UI relies on a surface the current renderer does not
yet model well, such as:

- popupmenu completion
- cmdline UI
- externalized messages
- mouse-specific behavior
- richer border/blend fidelity than the current renderer provides

## Related files

- `.codex/skills/neovim-ui-capture/SKILL.md`
- `lua/commentry/dev/ui_bridge.lua`
- `scripts/ui-capture-rpc.lua`
- `scripts/ui-capture-rpc`
