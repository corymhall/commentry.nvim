---
name: neovim-ui-capture
description: Capture and review real Neovim UI states for commentry.nvim using the repo's embedded RPC multigrid workflow. Use this whenever the user asks you to inspect what the plugin looks like, validate a Neovim UI change visually, compare laptop vs desktop layouts, iterate on popup/card/range-comment design, or verify that a Neovim-facing change actually renders the way you think it does. Prefer this skill over guessing from code whenever the task involves Neovim appearance or interaction.
---

# Neovim UI Capture

Use this skill when working on visual or interaction-heavy Commentry changes.

The repo includes two capture paths:

- Preferred: `./scripts/ui-capture-rpc`
  Uses an embedded Neovim plus real multigrid redraw events.
- Fallback: `./scripts/ui-capture`
  Reconstructs UI from windows, buffers, and extmarks. Useful if the RPC path is not enough for a narrow debugging task.

For most design validation, use the RPC path first.

## What this skill is for

Use it to:

- validate popup layout changes
- inspect saved comment cards and range comments
- compare `laptop-small` and `desktop-wide` presets
- confirm Neovim UI behavior after plugin edits
- generate human-viewable PNGs and HTML galleries for design discussion

Do not rely on it yet for every possible Neovim UI feature. The current RPC bridge is strongest for:

- normal windows and splits
- floating windows
- extmark-based inline UI
- line highlights
- cursor placement
- real colors and text from multigrid redraw events

If the new feature depends on:

- popupmenu completion
- cmdline UI
- externalized messages
- mouse-specific behavior

then expect to extend the bridge before the skill fully covers it.

## Default workflow

1. Make the UI change in plugin code.
2. Run repo gates:
   - `mise run lint`
   - `mise run test`
3. Generate RPC captures:
   - single preset: `./scripts/ui-capture-rpc --preset laptop-small`
   - compare both presets: `./scripts/ui-capture-rpc --all-presets`
4. Review the generated images and compare pages.
5. If the captures reveal layout problems, iterate on the plugin code and rerun.

## Commands

### Capture one preset

```bash
./scripts/ui-capture-rpc --preset laptop-small
./scripts/ui-capture-rpc --preset desktop-wide
```

### Capture one scenario

```bash
./scripts/ui-capture-rpc --scenario popup --preset laptop-small
./scripts/ui-capture-rpc --scenario card --preset laptop-small
./scripts/ui-capture-rpc --scenario range --preset laptop-small
```

### Capture and compare both presets

```bash
./scripts/ui-capture-rpc --all-presets --out-dir tmp/ui-capture-rpc-presets
```

## Output locations

Single gallery:

- `tmp/ui-capture-rpc-gallery/index.html`

Multi-preset gallery:

- `tmp/ui-capture-rpc-presets/index.html`

Side-by-side compare pages:

- `tmp/ui-capture-rpc-presets/compare/popup.html`
- `tmp/ui-capture-rpc-presets/compare/card.html`
- `tmp/ui-capture-rpc-presets/compare/range.html`

Common image outputs:

- `tmp/ui-capture-rpc-gallery/popup/rpc-comment-popup.png`
- `tmp/ui-capture-rpc-gallery/card/rpc-comment-card.png`
- `tmp/ui-capture-rpc-gallery/range/rpc-range-comment.png`

## Presets

Current presets:

- `laptop-small` = `220x18`
- `desktop-wide` = `320x54`

Treat `laptop-small` as the stricter baseline when making layout decisions.

## Design review guidance

When reviewing captures, pay attention to:

- whether the popup is too tall or visually noisy on `laptop-small`
- whether saved cards overpower the code they annotate
- whether range comment rails feel connected to the card
- whether text wrapping makes cards feel like second documents instead of inline review notes
- whether the desktop preset still feels balanced after optimizing for the small preset

If the remaining mismatch is about how the screenshot looks rather than how Commentry is laid out, prefer improving the RPC renderer over changing plugin behavior.

## When to extend the bridge

Extend the RPC bridge if:

- the visual feature exists in Neovim but does not appear in captures
- the relevant UI uses an event family the bridge does not currently consume
- the screenshot structure is correct but missing important visual nuance from highlights or borders

Current bridge files:

- `lua/commentry/dev/ui_bridge.lua`
- `scripts/ui-capture-rpc.lua`
- `scripts/ui-capture-rpc`

## Expected reporting

When using this skill, report:

- the command you ran
- which preset(s) you checked
- which image or compare page best shows the result
- whether the issue is in plugin layout or in capture fidelity
