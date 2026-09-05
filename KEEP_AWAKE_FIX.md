# Fix plan: keep awake deep link doesn't match its docs

Decision: remove the numeric argument from `action.keepAwake` entirely.
Duration is only ever chosen by which row you address — the plain row toggles,
preset rows carry the intervals. No `v`, no snapping, no silent conversion.

## Root cause

Three layers disagree about what `?v=` means for `action.keepAwake`:

1. The docs (docs/DEEP_LINKS.md, keep awake table) promise "Minutes, `1`–`480`,
   clamped to the row's own range".
2. The catalog row accepts that promise (`numericRange: 1...480`,
   Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift:460), and the
   deep link path clamps into it (CommandBarService.swift:498).
3. Keep awake then sanitizes the value
   (KeepAwakeManager.swift:149 → `Defaults.sanitizedDefaultDuration`,
   Defaults.swift:1580), which keeps only
   `[0, 15, 30, 60, 120, 240, 480]` and maps everything else to `0` —
   indefinite.

So `?v=40` runs, clamps to 40, and silently keeps the Mac awake
**indefinitely**. Same for `?v=1`, `?v=479`, any off-list value. The bug
predates the deep link branch; the deep link just makes it reachable from
scripts. The supported intervals are a product decision recorded in
`Defaults.allowedDurations`, not a continuous range, so the row's
`numericRange` is the lie — it should not exist for this row.

## Changes

1. **CommandBarCatalog.swift** (action.keepAwake, line ~450): drop
   `numericRange` / `numericIsOptional` and the minutes branch of the run
   closure. The row becomes a plain toggle, exactly like the menu bar icon and
   the radial menu entry.
2. **docs/DEEP_LINKS.md**: remove the `v` cell from the `action.keepAwake`
   row; the doc's "keeping this page true" test does not check `v` semantics,
   so the table edit is manual. State that durations come from the preset
   rows.
3. **Tests/MetricsTests.swift**, deep link section: pin that
   `vorssaint://run/action.keepAwake?v=40` parses to the row with the
   argument present but runs as a toggle (no numeric range means the dispatch
   ignores `v` — assert the row no longer exposes `numericRange`), and the
   preset rows still activate with their fixed minutes.

That is the whole fix: about a dozen lines, no new strings.

## Preset rows: add the three missing ones

Preset rows exist today for 30 min, 1 h, 2 h. Supported intervals are
`15 min, 30 min, 1 h, 2 h, 4 h, 8 h` (and indefinite via the plain row).
Add `action.keepAwake.15`, `.240`, `.480` so every supported interval stays
reachable by address, as before.

No new strings: the titles reuse `s.minutes15`, `s.hours4`, and `s.hours8`
(Localization.swift:135-140), already translated for the keep awake picker.
The change is three entries in the catalog's `durations` array plus three rows
in the docs table. The docs stay English-only either way — the localized
strings are for the Command Bar UI, where these rows also appear.

## Note on the bar

Removing `numericRange` also removes typed durations from the Command Bar for
this row: "keep awake 45" now toggles instead of activating with a broken
duration. That was the same bug in its other coat, so losing it is the point,
but it is a small behavior change for keyboard users.

## Verification (when you ask for it)

```sh
./build.sh --test      # deep link expectations incl. the new toggle pin
./build/Vorssaint --selftest
open 'vorssaint://run/action.keepAwake?v=40'   # expect toggle, no session
open 'vorssaint://run/action.keepAwake.15'     # expect 15 minute session
open 'vorssaint://run/action.keepAwake.30'     # expect 30 minute session
open 'vorssaint://run/action.keepAwake'        # expect plain toggle
```

Nothing has been built or run for this plan yet.
