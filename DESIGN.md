# Squeek Odometer: design system

Taken from the source: `dist/style.css` (tokens and all component CSS), `dist/index.html`, `dist/led.js` (the LED
board) and `dist/app.js`. There is no build step; `dist/` is the site.

## Overview

A one-page mint site on a pure black page. The main visual idea comes from the product: an LED dot-matrix board in the
first screen that reads like an odometer, with two readouts, **WHEEL** (everything Squeektoshi has run on this core) and
**YOURS** (your token, since your mint). The gap between the two is the product. The odometer art the contract draws is
the receipt beside the mint button, and the stage ruler further down.

It belongs to Squeekchain's world through its fonts (IBM Plex Mono, Barlow Condensed), the uppercase tracked labels and
the LED board, without its logo, its floating rounded chrome or its light palette.

Order of the page: header strip, hero (pitch and mint on the left, the board on the right), How it counts, Newbie to
Legend (stage ruler and rolled traits), Latest odometers, One contract no owner, Questions, footer.

## Colors

All colors are custom properties in `:root` of `dist/style.css`. One theme, dark.

| Token | Value | Use |
| --- | --- | --- |
| `--page` | `#000000` | page, header strip (at 86% with a blur), board |
| `--sunk` | `#141418` | inline `code` |
| `--line` | `#1c1c22` | section rules, list and table rules |
| `--line-strong` | `#2c2c35` | board border, button borders, image outlines, disabled mint (dashed) |
| `--ink` | `#f3f3f6` | headings, values |
| `--text` | `#cfcfd8` | body text |
| `--muted` | `#8d8d9b` | labels, fine print, nav, status messages before deploy |
| `--accent` / `--accent-hover` | `#f6a63b` / `#ffb85c` | the mint button, ruler ticks, FAQ hover; nothing else |
| `--on-accent` | `#120d05` | text on the mint button |
| `--link` | `#a7b5ff` | links, focus outline |
| `--good` / `--bad` | `#7fe08a` / `#ff8573` | success and error messages, the connected wallet light |

LED colors live in `dist/led.js` (`C`): unlit dot `#131316`, dim drums and empty readout `#34343e`, labels `#5c5c68`,
cream digits `#f3e9cc`, red hundredths `#ff5a3c`, status green `#7fe08a` (running) or blue `#8fa2ff` (napping), wheel
rim `#8a8a96`. Trait chips use the contract's own display colors.

## Typography

- `--font-mono`: IBM Plex Mono 400 and 500 (WOFF2 in `dist/fonts/`, SIL OFL 1.1, licenses alongside). Body, labels,
  buttons, nav, numbers.
- `--font-head`: Barlow Condensed 700 (WOFF2 in `dist/fonts/`, SIL OFL 1.1), uppercase, line-height 0.95. h1 to h3, the
  brand, ruler distances, FAQ questions.
- Scale: `--fs-1` 12px (labels, nav, small buttons, board note), `--fs-2` 14px (fine print, lists), `--fs-3` 16px
  (body), `--fs-4` 22px (brand, ruler km), `--fs-5` 40px (h2), `--fs-6` 64px (h1; 56px under 1080px, 46px under 640px).
- Labels (`dt`, nav, buttons, ruler captions) are uppercase with `--track` 0.12em. Sentences never are. Headings and the
  wordmark are one color.

## Layout

- Spacing: `--s-1` 4, `--s-2` 8, `--s-3` 12, `--s-4` 16, `--s-5` 24, `--s-6` 40, `--s-7` 88 (56 on phones) between
  sections.
- Content is at most `--wrap` 1240px wide with a `--gutter` of 24px (16px on phones). Sections are separated by a 1px
  `--line` rule and `--s-7` of space; there are no cards around sections.
- Hero: 5fr text, 7fr board; one column under 1080px (board after the text). How it counts and Contract: two columns,
  one under 900px. Rolled traits: three columns, two under 1080px, one under 640px.
- The stage ruler is one row that scrolls sideways (136px items on phones).
- Phones (760px and narrower): the header is just the brand and the wallet button; the nav is hidden. Checked at 390px
  with no horizontal page scroll, before and after a mint.

## Elevation & depth

Flat. Depth comes from rules and the board's 1px `--line-strong` border on black. The header strip blurs what scrolls
under it; that is the only blur and there are no shadows except the connected wallet light's glow.

## Shapes

The board: 10px radius. Buttons: 6px. Images: 4px, `image-rendering: pixelated`. Swatches 3px.

## Components

- **Button** `.btn` + `.solid` (orange, the only one: Mint) or `.line` (outlined: wallet, Ask marketplaces to redraw),
  `.small` 36px, default 44px, `.solid` 52px. Before deployment the mint button reads "Mint opens at deploy" and is
  dashed and muted, not faded; after a mint it reads "Minted". A running write sets `aria-busy`. The wallet button has a
  7px round light that turns green once connected and then shows the short address.
- **LED board** (`dist/led.js`, `window.LedBoard.set({ state, km, mine, rpm, block })`): a canvas of round dots that
  sizes itself to its rows (6px pitch on wide boards, 5px from 520px, 4.4px on phones). Rows: his state in one color
  (green running, blue napping, cream off air), then WHEEL and YOURS as odometers that share one digit size and number
  of drums (leading drums dim, whole km cream, hundredths red, KM small), then RPM and the Squeek block. Labels sit
  beside the readouts when there is room, above them otherwise. YOURS shows dim dashes until the connected wallet has a
  token. A dot wheel fills free space on the right on very wide boards, turning with the RPM; with reduced motion it is
  still. The canvas `aria-label` carries the same facts, and the sentence under the board repeats them as text.
- **Receipt** `.mine`: the placeholder or your token at 112px beside its caption (168px once minted, stacked on phones),
  with the redraw button after a mint.
- **Spec plate** `.plate`: two columns of label and sentence rows for How it counts.
- **Stage ruler** `.ruler`: the seven sample odometers from `dist/samples/` (rendered by the contract through
  `script/Gallery.s.sol`) above a rule with an orange tick per stage, the distance in Barlow and the stage name below.
- **Rolled traits** `.roll`: lists with a swatch or a display chip in the contract's colors, name, and odds or rule.
- **Cards** `.card`: a minted odometer with `#id`, km and status.
- **FAQ**: native `details`/`summary`, `+` / `-` marker.
- **Messages** `#msg`: one `role="status"` line under the mint button: muted for information, green or red for results.

## Do's and Don'ts

- Do keep orange for the mint button and the ruler ticks; numbers that matter go on the board, not in colored text.
- Do separate sections with a rule and space, not with cards.
- Do put new live facts on the board and repeat them in a sentence for screen readers.
- Do show the contract's art pixelated and outlined, never on a colored card.
- Don't add a light theme, a floating rounded header, a pill above the headline, two-color headings, stat boxes or
  numbered feature cards.
- Don't copy Squeekchain's logo or dot-matrix wordmark; the board's words are ours.

Recipe: add a `section.block` with an `h2`, fill it with `.plate`, `.kv`, `.roll` or `.grid`, and read the chain through
`call()` / `rpc()` in `dist/app.js`.
