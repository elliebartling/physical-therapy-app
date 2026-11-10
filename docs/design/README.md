# Design

The live design canvas is here:

**https://claude.ai/artifact/KfaaDQ5nDabCfxp5GeTJ9P**

It's private by default. To give a collaborator access, open it and use
**Share** in the top-right of the page.

The written spec (visual system, screens, flows, delivery plan) is
[`docs/superpowers/specs/2026-11-10-swiss-glass-redesign-design.md`](../superpowers/specs/2026-11-10-swiss-glass-redesign-design.md).

## What's on the canvas

| Page | What it is |
|---|---|
| **v3 · UX** | The current direction: the v1 UX map (structure + flows) and the new/changed screens in flow order: import review, what changed, Today with several routines, rate exercise, session summary, prepare for your visit. |
| **v2 · Directions** | The exploration that got us here: A · Native Liquid Glass, B · Editorial / Swiss, **C · Swiss + Liquid Glass (chosen)**, the accent color study, and the in-app color picker. |
| **v1 · Dark** | The first, rejected dark direction. Kept for reference. |

## `canvas/`

A snapshot of the canvas source: one `.dc.html` file per artboard plus
`canvas.json` (layout) and `tokens.css`. These render inside the canvas
editor (they load its `support.js`), so treat them as reference, not as
pages to open directly. The canvas link is the source of truth; refresh
this folder when the design changes meaningfully.
