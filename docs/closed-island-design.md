# Closed island while agents work: Direction 2B

Approved design for the closed (not hovered) Dynamic Island while an agent
works. Design canvas: <https://claude.ai/artifact/3YUttYbGU8zd7Q4fuQUPeW>,
board "Direction 2 refined · B · Two badges, counts inside". The expanded
page is final and does not change.

The left wing shows the working agent's mark inside its limit ring, with a
badge for each place it works set on the ring itself. The right wing shows the
timer. This replaces the capsules beside the ring from commit `b82db1c9`.

## What changes, by file

| File | Today | 2B |
|---|---|---|
| `Services/Notch/NotchAgentSupport.swift`, `NotchAgentWorkingLayout` | `ring = clamp(10…20, budget)`; capsule badges in a column beside the ring (`gap`, `badgeGap`, `badgeHeight`, `badgeIcon`, `countSize`, `badgeWidth`) | `ring = clamp(10…22, budget)`; badge geometry on the ring (below); `gap` and `badgeGap` go |
| `UI/Notch/NotchAgentComponents.swift`, `NotchAgentWorkingMark` | `HStack` of ring + `VStack` of capsules (white 20%) | One `ZStack` of the ring box, with the badges as offset overlays that may overhang it |
| `UI/Notch/NotchAgentComponents.swift`, `NotchAgentRing` | Track hardcoded at white 18% | Add `var track: Double = 0.18`; the working mark passes `0.24`. The session rings on the expanded page keep the default |
| `UI/Notch/NotchAgentStrip.swift` | Timer at `.medium`, in `working.first?.tint` | Timer at `.semibold`, in `.white` |
| `Services/Notch/NotchService.swift`, `agentStripWing` | Measures the reading with `.medium` | Measures it with `.semibold`, so the wing still fits the text |
| `UI/Settings/NotchAgentsSettings.swift`, preview | 12 pt `.medium` reading in the agent's color | 12 pt `.semibold`, white; the mark scales from its ring (budget 16) |

Leave the wing range (44–80 pt), the camera gap, the edge insets, the
accessibility label and value, and the Used / Left reading as they are.

## Sizes

Everything in the mark scales from `ring`. The values below are for the usual
32 pt strip, where `budget = compactActivityContentHeight - 2 × compactEdgeGap = 22`,
so `ring = 22`. The Settings preview passes budget 16 and gets the same
proportions.

### Ring and mark

| Part | Rule | At ring 22 |
|---|---|---|
| Ring diameter | `min(22, max(10, budget))` | 22 pt |
| Stroke | `max(1.6, ring × 0.114)`, round cap, starting at 12 o'clock, clockwise | 2.5 pt |
| Track | white, 24% opacity, same stroke | — |
| Fill | `used ? usedFraction : remainingFraction` (unchanged) | — |
| Ring color | white; `#FFD60A` from 80% used; `#FF453A` from 95% used (`ringTint`, unchanged, always by used fraction) | — |
| No limit known | the track alone (unchanged) | — |
| Agent mark | `NotchAgentMark(size: ring × 0.48, tint: provider.tint)`, centred | 10.5 pt |

### Badges

There is one badge per place that has a session. The terminal badge is
grey, `#3A3A3C`, with the white `>_` (`NotchAgentTerminalMark`). The app badge
is filled with the agent's color (Claude `#D97757`, Codex `#7D99FF`, from
`AgentProvider.tint`) and carries the agent's mark in white
(`NotchAgentMark(tint: .white)`, with no inner tile, because the badge is the
tile).

| Part | Rule | One place | Both places |
|---|---|---|---|
| Badge height `h` | `ring × 0.5` for one place, `ring × 0.4545` for both | 11 pt | 10 pt |
| Corner radius | `h × 0.3`, `.continuous` | 3.3 pt | 3 pt |
| Terminal glyph | `h × 0.8`, stroke `max(1, glyph × 0.13)` | 8.8 pt | 8 pt |
| App glyph | `h × 0.68` | 7.5 pt | 6.8 pt |
| Black cut | 1.5 pt of black around the badge, drawn under it and over the ring (e.g. a black `RoundedRectangle` of radius `h × 0.3 + 1.5`, 1.5 pt larger on every side) | 1.5 pt | 1.5 pt |

**Where the badges sit.** Each badge is anchored to a point on a circle of
radius `ring × 0.523` (11.5 pt) around the ring's centre, just outside the
stroke:

- One place: the badge is at **4:30** (135° clockwise from 12).
- Both places: the terminal is at **1:30** (45°) and the app at **4:30**.

With `k = ring × 0.523 × 0.7071` (8.13 pt), the anchor in the ring box's
coordinates (origin at the top left, `ring × ring`) is:

- 4:30: `(ring/2 + k, ring/2 + k)` = (19.13, 19.13)
- 1:30: `(ring/2 + k, ring/2 - k)` = (19.13, 2.87)

The badge's leading edge is at `anchor.x - h/2`, and it is vertically centred
on `anchor.y`. A count makes the badge wider to the right only, so its left
edge and its glyph never move.

**Counts.** A count appears from 2 sessions up, inside the badge after the
glyph:

- Font: `.system(size: h × 0.78, weight: .bold, design: .rounded)`, `.monospacedDigit()`, white. That is 8.6 pt for one place and 7.8 pt for both.
- Spacing: 1 pt between the glyph and the digits.
- Padding: `pad = (h - glyph) / 2` on the leading side, and `pad + 0.5` on the trailing side.
- Width: `h` with no count (a square tile), else `pad + glyph + 1 + digitsWidth + pad + 0.5`. Measure `digitsWidth` as today (`digits × fontSize × 0.62`) or with the real text.

**Drawing order:** track, arc, mark, terminal badge, app badge. The ring box
keeps its `ring × ring` frame. The badges overhang it to the right (and, at
1:30, up by about 3.6 pt with the cut). Nothing in the chain may clip:
no `.clipped()` and no `.drawingGroup()` bounds tighter than the overhang. At
ring 22 in a 32 pt strip, the ring box starts 5 pt from the top, so the upper
badge and its cut stay about 1.4 pt inside the strip, and the lower one ends at
about 30.6 pt.

### Layout width (`NotchAgentWorkingLayout.width`)

`width = max(ring, max over badges of (anchor.x - h/2 + badgeWidth))`

At ring 22 that is:

- one place, no count: 24.6 pt
- both, no counts: 24.1 pt
- both with single-digit counts: about 31 pt

`agentStripWing` adds the edge inset and the 6 pt camera air as it does today,
so in practice the timer sets the wing (about 44–52 pt). The edge inset is
still computed from `boxHeight: ring, radius: ring / 2`. The badges overhang
toward the camera, not toward the outer edge, so the inset does not change.

### Timer (right wing)

- `Text(reading)` at `NotchAgentSupport.stripTextSize(height:)` (15 pt on a 32 pt strip), `.semibold`, `.monospacedDigit()`, `.foregroundStyle(.white)`.
- Trailing aligned with `textInset`, as today. `lineLimit(1)` and `minimumScaleFactor(0.6)` stay.
- The only color on the closed island is the agent's mark, the app badge and the ring's yellow or red. The timer no longer takes the agent's color.

## Alignment summary

- Left wing: the ring box is leading-aligned at `iconInset` and vertically centred in the strip. The badges are positioned from the ring's centre, not stacked in a column.
- Right wing: the timer is trailing-aligned at `textInset`, on the strip's vertical centre.
- Both wings are the same width, as today: the wider of the two sides.

## Accepted trade-off

A badge covers part of the arc around its anchor: roughly 31–44% of the way
round for the 4:30 badge, and 6–19% for the 1:30 badge when both places work.
Readings in those bands show their end under the badge. This was reviewed on
the canvas (the "Arc under a badge" row at 38%) and accepted with 2B.

## Tests to update (`Tests/AgentSessionPlaceTests.swift`)

- `alone.ring == 22` at budget 30, and `alone.width <= 44 - 11` (it must fit a 44 pt wing with the inset and camera air).
- A count widens its badge: `badgeWidth(count: 2) > badgeWidth(count: 1)`, and `badgeWidth(count: 1) == badgeHeight`.
- Both places use the smaller badge (`badgeHeight` is `ring × 0.4545`), and the terminal's anchor is above the app's.
- Remove the `badgeGap` stacking expectation.
