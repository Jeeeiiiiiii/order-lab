---
version: 1
slug: "flow-index-html"
primary_target: "flow/index.html"
related_targets: []
---

Scope: flow/index.html, the order flow view. Mode: Operate.
Audience: one DevOps engineer learning the lab; job: place orders, break the notifier, and watch each order's real journey.

## Direction contract

THESIS: Orders are flights on a split-flap departures board. The API checks them in, SQS holds them at the gate, the Lambda boards them; failures show as DELAYED with a live countdown (the 60s visibility timeout), DIVERTED is the DLQ. Refuses the category default of an architecture diagram with counters and a status-badge table.

OWN-WORLD: Backlit black board, flap cells in a strict character grid, amber-gold flap text, white secondary, green only for DEPARTED, red reserved for DIVERTED and the alarm. One gold lever (HOLD ALL DEPARTURES = pause notifier) is the only accent control. A route strip ALB > API > DB > SQS > NOTIFY > DLQ with live counts sits above the board like terminal signage. Rows stay as history.

STORY: Place orders at the check-in desk; watch them check in instantly (201), wait at the gate, depart; send a poison order and watch it get delayed three times and diverted; hold departures and see check-in keep working while the gate fills.

FIRST VIEWPORT: Signage strip across the top; the board fills the middle (columns: TIME, FLIGHT = order, PASSENGER x ITEM, STATUS, REMARKS); the check-in desk (place order, poison, burst) and the gold hold lever across the bottom. Clicking a row opens its trace: each step with its real timestamp and proof.

FORM: Departures Board, 5 of 7 on the ordered list. Seed key 33e82a37. Raises: teletext cell grid + red reserved; sleeve history persists; product-marketing claim+proof per status; cape single transforming control.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
