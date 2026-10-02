---
name: Order Lab
description: The async order pipeline, read live from the emulator and shown as a split-flap departures board.
colors:
  flap-gold: "#F2C230"
  go-green: "#3DBE6E"
  stop-red: "#E5484D"
  stop-tint: "#F58A8D"
  alarm-ink: "#F7B4B6"
  board-black: "#0B0B0C"
  terminal-wall: "#161718"
  cell-face: "#242528"
  cell-top: "#2C2D30"
  bezel: "#2B2C2E"
  held-bezel: "#4A3D12"
  hover-edge: "#55575B"
  hover-fill: "#121213"
  signage-white: "#ECECEC"
  muted: "#A0A3A8"
typography:
  display:
    fontFamily: "Barlow Condensed, Arial Narrow, sans-serif"
    fontSize: "2.7rem"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "0.01em"
  headline:
    fontFamily: "Barlow Condensed, Arial Narrow, sans-serif"
    fontSize: "1.05rem"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "0.04em"
  flap:
    fontFamily: "Barlow Condensed, Arial Narrow, sans-serif"
    fontSize: "1.2rem"
    fontWeight: 600
    lineHeight: 1
  title:
    fontFamily: "Barlow Condensed, Arial Narrow, sans-serif"
    fontSize: "1.1rem"
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: "0.02em"
  body:
    fontFamily: "Barlow, Segoe UI, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.5
    fontFeature: "tnum"
  label:
    fontFamily: "Barlow Condensed, Arial Narrow, sans-serif"
    fontSize: "0.8rem"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "0.1em"
  proof:
    fontFamily: "ui-monospace, Cascadia Mono, Consolas, monospace"
    fontSize: "0.82rem"
    fontWeight: 400
    lineHeight: 1.45
rounded:
  cell: "3px"
  board: "4px"
spacing:
  cell-gap: "2px"
  xs: "6px"
  sm: "10px"
  md: "12px"
  column: "18px"
  lg: "20px"
  page: "24px"
components:
  flap-cell:
    backgroundColor: "{colors.cell-face}"
    textColor: "{colors.flap-gold}"
    typography: "{typography.flap}"
    rounded: "{rounded.cell}"
    width: "1.3rem"
    height: "1.9rem"
  flap-cell-small:
    backgroundColor: "{colors.cell-face}"
    textColor: "{colors.flap-gold}"
    rounded: "{rounded.cell}"
    width: "1.05rem"
    height: "1.55rem"
  sign-header:
    backgroundColor: "{colors.flap-gold}"
    textColor: "{colors.board-black}"
    typography: "{typography.headline}"
    padding: "7px 12px 6px"
  sign-header-held:
    backgroundColor: "{colors.signage-white}"
    textColor: "{colors.board-black}"
  board:
    backgroundColor: "{colors.board-black}"
    rounded: "{rounded.board}"
    padding: "10px 14px 14px"
  button-desk:
    backgroundColor: "{colors.board-black}"
    textColor: "{colors.signage-white}"
    typography: "{typography.title}"
    rounded: "{rounded.cell}"
    padding: "0 20px"
    height: "46px"
  button-desk-hover:
    backgroundColor: "{colors.hover-fill}"
  button-poison:
    backgroundColor: "{colors.board-black}"
    textColor: "{colors.stop-tint}"
    rounded: "{rounded.cell}"
    padding: "0 20px"
    height: "46px"
  lever-throw:
    backgroundColor: "{colors.board-black}"
    rounded: "{rounded.cell}"
    width: "46px"
    height: "92px"
---

# Design System: Order Lab

## Overview

**Creative North Star: "The Departures Board"**

Every order is a flight. The page is a terminal wall (dark grey) holding one backlit black board in a thick housing, with wayfinding signs above it. The board speaks in split-flap cells: one character per tile, hinged across the middle, gold ink on near-black. Statuses are board words (AT GATE, HOLD, BOARDING, DELAYED, DIVERTING, DIVERTED, DEPARTED); everything the operator needs to *understand* is written beside them in plain prose. The board is the fixed vocabulary, the prose is the explanation.

Density is operational: many rows, tight cell grid, restrained type ramp, no decoration that is not a physical part of a real board (bezel, hinge line, flap faces, gold signage headers, the lever). Colour is a signal system, not an atmosphere: gold is the board's ink, and green, red and white each mean exactly one thing. Motion is the board's own: only characters that change turn over.

The world refuses the category default for pipeline dashboards: an architecture diagram with counters and a status-badge table. It also stays distinct from the sibling mesh-lab console (cool grey-blue bench instrument).

**Key Characteristics:**
- Split-flap cells in a strict character grid; column widths are exact multiples of the cell width.
- Gold (#F2C230) as the single ink; green, red and white strictly role-bound.
- Flat black surfaces in a bezel housing; depth only from the cells' own hinge and flap faces.
- Condensed signage type for board words and labels; Barlow prose for explanation.
- Controls sit above the board so they stay in the first viewport.

## Colors

A black board and grey wall carrying one gold ink, with green, red and white reserved as signals.

### Primary
- **Board Gold** (flap-gold): the board's ink. Every flap cell's character by default, the h1, the sign header bars (as fill, with board-black text), the route arrows, the selection highlight, and an 8% tint on the expanded row. The thrown lever handle turns a gold gradient (#F0C33A to #C8961A) so the one physical control reads as the board's own.

### Secondary
- **Departure Green** (go-green): delivered, and nothing else. DEPARTED status cells, and the matching "Notify sent" step in an order's trace.

### Tertiary
- **Diversion Red** (stop-red): the failure family. DIVERTING and DIVERTED status cells, the dead-letter branch name when it holds messages or the alarm fires, the alarm line, and the failed and dead-lettered trace steps. Poison controls and error text use its lighter tints for legibility on black: **Poison Tint** (stop-tint) for the poison-order button text, **Alarm Ink** (alarm-ink) on the error banner over an 8% red wash with a 50% red border. The poison button's hover edge is full stop-red.

### Neutral
- **Board Black** (board-black): the board, sign bodies, desk buttons, the lever housing, and the hinge line through every cell. The darkest thing on the page.
- **Terminal Wall** (terminal-wall): the page background around the board.
- **Bezel** (bezel): the board's 10px housing, sign and button borders, dashed branch dividers. When departures are held the housing warms to **Held Bezel** (held-bezel).
- **Cell Face / Cell Top** (cell-face, cell-top): the lower and upper flap halves of each cell, split hard at 50%.
- **Signage White** (signage-white): primary text, customer names, bold figures in prose, and the HOLD state (see rule below). Also the header clock's flap ink.
- **Muted** (muted): lede, remarks, units, column headers, notes, footer.
- **Hover Edge / Hover Fill** (hover-edge, hover-fill): desk button hover only.

### Named Rules
**The One Ink Rule.** Gold is the board's ink and every flap's default colour. Any other flap colour is a signal: green for DEPARTED, red for DIVERTING/DIVERTED, white for HOLD and held-state signage (HOLD status cells, the ALL DEPARTURES HELD notice, the HELD cells and header on the Lambda sign) and the header clock.

**The Signal Reservation Rule.** Green means delivered. Red means failure or the dead-letter path. Neither appears as decoration, as a brand colour, or on a state that is merely waiting. DELAYED stays gold: it is a wait with a countdown, not a failure of the order.

## Typography

**Display Font:** Barlow Condensed (with Arial Narrow, sans-serif), self-hosted, 500/600/700
**Body Font:** Barlow (with Segoe UI, system-ui, sans-serif), self-hosted, 400/500/600
**Label/Mono Font:** ui-monospace (Cascadia Mono, Consolas) for trace proof lines only

**Character:** Barlow Condensed is terminal signage: narrow, upright, legible at flap size. Barlow is its humanist sibling for the plain-language explanations. Tabular figures are on for the whole page so counts and timestamps never jitter.

### Hierarchy
- **Display** (700, 2.7rem, 2.2rem at 520px and below, line-height 1): the page title, in gold.
- **Headline** (700, 1.05rem, 0.04em, uppercase): sign header bars.
- **Flap** (600, 1.2rem; small cells 1rem; 1.05rem at 520px and below): characters inside flap cells, always uppercase.
- **Title** (600, 1.1-1.2rem, 0.02-0.03em): customer names, desk buttons, the lever label, empty-state heading. Sentence case.
- **Body** (400, 15px, 1.5): lede (72ch max), desk note (62ch), remarks (500, 0.9rem), footer (100ch). Small prose sits at 0.82-0.9rem.
- **Label** (600, 0.8rem, 0.1em): board column headers in muted. Branch names use 600 0.95rem, 0.03em, uppercase, with a Barlow sentence-case aside.
- **Proof** (0.82rem, 1.45): raw log and queue evidence under each trace step, wrapping anywhere.

### Named Rules
**The Board Word Rule.** Uppercase belongs to the board's own vocabulary: flap cells, sign headers, branch names, column headers, each one to four words. Explanations, buttons and remarks are sentence case Barlow or Barlow Condensed. (The detector's all-caps-body rule is suppressed for flow/index.html in .impeccable/config.json on exactly this basis.)

**The Plain Column Rule.** Variable-length human text (customer, item, remarks) is never set in flap cells. Flaps carry fixed-width codes only: TIME (5), ORDER (6), STATUS (10), clock (8), countdown (4, small) and sign counts (3-4).

## Layout

A single centred column (max 1260px, 28px 24px 40px padding) in fixed order: header (title and lede left, white flap clock right), the route strip, the error banner, the check-in desk and lever, then the board, then the footer.

The route strip is four equal signs (ALB and API, SQS orders queue, Notify Lambda, Customer) joined by 34px gold arrows. Branches (Postgres, Dead-letter queue) sit inside their parent sign under a dashed divider rather than as extra signs.

The desk sits above the board, not below it: the board keeps up to 25 rows of history, so controls below it would leave the first viewport, and the task is to place orders and watch. Desk buttons are on the left; the lever group sits right (grid `1fr auto`, 20px 48px gap).

Board columns are measured in cells: TIME = 5 cells, ORDER = 6 cells, CUSTOMER AND ITEM = minmax(7rem, 1fr), STATUS = 10 cells, REMARKS = minmax(13rem, 1.5fr), with an 18px column gap. The cell width is a rem variable (1.3rem, 1.12rem at 520px and below) so headers and tracks line up exactly. Trace panels indent to align with the ORDER column.

At 1020px and below: signs stack with vertical arrows, column headers hide, each row becomes a two-column card (time and order, then status, customer, remarks), the desk stacks. At 520px and below: padding 20px 16px, the header clock hides, the board bezel thins to 6px.

## Elevation & Depth

Flat. Surfaces are black planes separated by the bezel and the grey wall, not by shadow. The only depth is physical and belongs to the board's hardware: each flap cell carries a 1px drop line and a faint top highlight with a hard hinge through the middle, and the lever's handle sits in a recessed slot.

### Shadow Vocabulary
- **Cell seat** (`box-shadow: 0 1px 0 rgba(0,0,0,.6), inset 0 1px 0 rgba(255,255,255,.05)`): every flap cell.
- **Board inner edge** (`box-shadow: inset 0 0 0 1px #000`): the line between bezel and board.
- **Lever slot** (`box-shadow: inset 0 1px 2px rgba(0,0,0,.9)`): the recess the handle rides in.
- **Lever handle** (`box-shadow: 0 2px 3px rgba(0,0,0,.6), inset 0 1px 0 rgba(255,255,255,.25)`): the one raised object on the page.

### Named Rules
**The Hardware-Only Depth Rule.** Shadows exist only where a real board has physical parts: cells, hinge, slot, handle. Signs, buttons, the board and panels stay flat.

## Shapes

Near-square everywhere: 3px corners on cells, signs, buttons, the lever housing and the banner; 4px on the board. Borders are 1px bezel lines; the board housing is a heavy 10px bezel. Dividers inside signs are dashed. Arrows are solid 3px gold bars with a CSS triangle head.

## Components

### Flap Cell (signature)
One character per tile. Upper and lower halves in cell-top and cell-face split at 50%, a 1px hinge line with 2px notches at each edge, gold condensed character centred. A small variant (1.05 x 1.55rem, 1rem type) is used for the countdown and the lever readout. Cells sit in a flex row with a 2px gap and 420px perspective.
- **Motion:** only a cell whose character changes turns: rotateX from -88deg with brightness 0.55 to flat, 240ms, cubic-bezier(0.23, 1, 0.32, 1), staggered 26ms per changed cell left to right. A new row turns once on arrival, then only what changes. The clock and countdown update without turning. Reduced motion replaces the turn with a 140ms opacity crossfade (0.25 to 1). DELAYED does not blink.

### Route Sign
Board-black body with a 1px bezel border and a gold header bar in uppercase condensed type. Body holds a muted role line, then counts as flap cells with a muted unit. When departures are held, the Notify Lambda sign's header turns signage white and its count reads HELD in white cells.

### Departures Board
Board-black panel in a 10px bezel housing (held-bezel while held). Rows are full-width buttons with 3px corners: hover 4% white wash, expanded 8% gold wash, 120ms background transition. When held, a notice line opens above the columns with ALL DEPARTURES HELD in white cells and a muted explanation.

### Trace
Opens under its row. Each step is a three-column line: millisecond timestamp (600), elapsed since the 201 (muted), step name (600; green for sent, red for failed and dead-lettered) with its proof in monospace beneath. Closes with a note restating that Postgres still says accepted.

### Desk Buttons
- **Shape:** 3px corners, 46px tall, 20px side padding, 1px bezel border on board black.
- **Primary:** signage-white condensed title type. There is no filled button; the lever is the only accent control.
- **Hover / Focus:** border to hover-edge, fill to hover-fill (fine pointers only); press scales to 0.97 over 140ms ease-out. Focus is the global 2px signage-white outline at 3px offset. While placing, the label reads "Placing…" at 55% opacity.
- **Poison:** same shape, stop-tint text, stop-red border on hover.

### Hold Lever
A 46 x 92px housing with a black recessed slot and a grey gradient handle; a switch role. Thrown, the handle drops 44px and turns gold over 240ms ease-out, and its small flap readout turns from RUN to HOLD. Label "Hold departures" in condensed title type, a muted note beneath that changes with state.

### Banner
Error-only: red wash, alarm-ink text, monospace for paths and source names.

## Do's and Don'ts

### Do:
- **Do** size every board column as a whole number of cells plus gaps, so headers, rows and trace indents align.
- **Do** keep flap cells for fixed-width codes and counts; write names, items and remarks as plain prose beside them.
- **Do** turn only the cells whose character changed, 240ms, 26ms stagger, and fall back to a 140ms crossfade under reduced motion.
- **Do** keep the desk and lever above the board so the controls stay in the first viewport while history grows.
- **Do** say what waiting means in words next to the board word (the countdown, the attempt number), so a slow state never looks stuck.

### Don't:
- **Don't** use green anywhere except DEPARTED and the matching sent step.
- **Don't** use red except for DIVERTING/DIVERTED, the dead-letter path and alarm, failed trace steps, the poison control and error text.
- **Don't** flip the clock or countdown every second, and don't blink DELAYED.
- **Don't** add shadows to signs, buttons or panels; depth belongs to the board's hardware.
- **Don't** replace the board with an architecture diagram of counters and status badges.
- **Don't** set long or variable-length text in uppercase or in flap cells.

Detector exceptions for flow/index.html, recorded with reasons in .impeccable/config.json: **cramped-padding** (a flap cell holds one character edge to edge by design; bordered containers keep real padding) and **all-caps-body** (uppercase is confined to board words of one to four words).
