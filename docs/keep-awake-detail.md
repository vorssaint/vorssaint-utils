# Keep Awake detail in the Dynamic Island

Long-pressing the Keep Awake shortcut in the Controls rail opens a detail page inside the island. A short tap still toggles the session. The detail replaces the shortcut rail with a full-height card that shows the current state, exposes configuration normally found only in the app panel, and lets VoiceOver users reach the same page through an accessibility action.

## What the detail shows

**Active session.** A toggle, the remaining time (live countdown) or "until disabled" label, and extend chips (+15 / +30 / +60 min). The extend chips use the same capsule button style as the rest of the island.

**Inactive.** A toggle, a segmented Duration / Until picker matching the app panel's layout, and a single Start button that activates the chosen mode. The Until picker opens its hour and minute grid in a popover; the island stays open while the popover is showing, the same way the files page does for its actions popover. The picker also drops the hold when it disappears, so activating the session while the popover is open (from a global shortcut or an automation rule) does not leave the island stuck open.

**Options (always visible).** Clamshell mode toggle with setup status caption, display sleep toggle, and a button that navigates to the icon picker sub-page. Both toggles carry their title for VoiceOver even though the label is visually hidden. The icon picker replaces the controls page with its own back button; with Reduce Motion enabled, both transitions are instant.

## Layout

The detail card uses `keepAwakeSize(contentHeight:)` on the expanded geometry. Each state computes its own content height from the rows it shows: 215 for an active timed session (toggle, countdown, extend chips), 175 for an active indefinite session (toggle, countdown, options), 285 for the inactive page (toggle, segmented picker, duration or until picker, start button, options), and 170 for the icon picker sub-page (back row, compact picker with padding, scroll view inset). The height is built from `headerTopInset` and `headerChromeHeight`, the same base every other expanded page uses, so the island stays consistent on displays with or without a camera cutout. When a custom height leaves less room, the page scrolls vertically like the metric detail.

## Navigation

`NotchService.showKeepAwakeDetail()` guards on `AppFeature.keepAwake.isAvailable` and calls `open(.controls, keepAwake: true)`. The `open` method sets `showingKeepAwake` only when the feature is available. Going back, collapsing, or syncing preferences when the feature has been disabled all clear the flag. Opening sections from the detail preserves `showingKeepAwake`; returning from sections restores it.

The header shows the localized keep-awake title when the detail is active, using the same `showsDetail` path as the app panel and metric details.

## Long-press button

`NotchActionTile` accepts an optional `longPressAction` closure. When present, the tile uses `NotchLongPressButtonStyle` instead of the standard button style. The style uses a drag gesture to distinguish a short tap from a hold: pressing past the 0.4-second threshold fires the long-press action (open the detail); releasing before that fires the normal toggle. Dragging outside the tile's visible bounds cancels the gesture entirely — neither action fires. The containment check uses the tile's exact rectangle so releasing just outside cancels cleanly. The tile layout itself is unchanged — the same stacked VStack with a circle icon and two-line label that every shortcut rail tile uses.

## Automated checks

Run on a supported Mac:

```sh
./build.sh --test-suite=notch
./build.sh --dev
./build/VorssaintDeveloper --selftest
```

`NotchDestinationTests.keepAwakeDetailContracts` covers:
- Opening with `keepAwake: true` shows the detail on the controls module
- Going back clears the detail without collapsing the island
- Opening and closing sections preserves and restores the detail flag
- Collapsing the island resets the detail
- Opening the detail with the feature disabled does not show it

The `goBack`, `collapse`, `toggleSections` and `showKeepAwakeDetail` methods are extracted from production through the test generator, so the checks exercise the real code paths.

## Manual macOS smoke checks

- Long-press the Keep Awake shortcut in the island's Controls section. The detail page should slide in with the toggle and a segmented Duration/Until picker with a single Start button. Toggle on, verify the countdown and extend chips. Toggle off, switch between Duration and Until, verify the picker updates and Start activates the chosen mode.
- Drag off the Keep Awake tile without releasing — releasing outside should do nothing (no toggle, no detail). A short tap should toggle without opening the detail.
- Open the icon picker from the detail, change the icon, go back. The detail should remain. Open sections from the detail, close sections — the detail should still be there.
- With the Until mode selected, click the time button to open the popover. Click hours and minutes inside the popover; the island should stay open. Close the popover and start the session.
- Disable Keep Awake in settings while the detail is open. The island should fall back to the controls home without the detail.
- Test with VoiceOver: navigate to the Keep Awake shortcut and use the "Keep Awake Options" accessibility action. The detail should open. Navigate to the clamshell and display sleep toggles; VoiceOver should announce their names.
