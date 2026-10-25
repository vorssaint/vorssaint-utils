# Scroll Zoom review and manual testing

Keyboard Zoom activates the exact window under the pointer before sending its
standard Command-plus or Command-minus shortcut. Holding the modifier alone
does not activate a window. Pinch Zoom continues to simulate a pointer-located
magnification gesture; it does not use the keyboard activation path.

## Install the test build

```sh
./build.sh --dev --install
./build/VorssaintDeveloper --selftest
```

1. Quit other Vorssaint instances. Disable LinearMouse, Mac Mouse Fix and other
   wheel-modifying utilities for the baseline test.
2. Check the build output for successful stable signing. Do not claim a permission
   regression from an ad-hoc build with stale permission grants.
3. Grant the Developer app Accessibility and any permissions requested by the
   other features used below. It has separate settings and permissions from the
   official app.
4. Install Zoom in the feature catalog, open its Mouse settings card, then enable
   both controls: Zoom = Command and Pinch Zoom = Control. Option is also
   available for either action; Shift is not. A saved Shift assignment shows
   None, consistently in the picker and runtime. Other assignments are preserved.
5. Use a browser where Command-plus and Command-minus already change its zoom
   level. For Pinch, choose an app/document where a real trackpad pinch works.
6. Record the Mac model, macOS version, mouse model, app versions, display layout
   and Spaces configuration. A physical horizontal wheel or tilt wheel is needed
   to verify horizontal Pinch; do not count vertical-wheel tests as horizontal
   hardware coverage.

Target resolution and window activation are asynchronous. A keyboard Zoom tick
while there is no confirmed target remains ordinary scrolling. It is not queued
for replay. Subsequent ticks should zoom after focus is confirmed. Record how
many ticks or how much time activation takes; repeated failure is not a pass.
While a keyboard Zoom modifier stays held, a background timer refreshes the
target so pausing between ticks does not leave every subsequent tick unresolved.
Releasing the modifier or disabling Zoom stops that work.

## Baseline and direction

1. With inversion and Smooth Scrolling off, hold Command and turn the vertical
   wheel both ways. Verify the browser zoom level changes in opposite directions.
2. Assign Option to Zoom. Keep Option held while zooming in and out repeatedly.
   Verify it does not stop after the first tick or leave Command or Shift stuck.
3. Hold Control and turn each wheel slowly, including one or two isolated ticks.
   Verify Pinch magnification responds without requiring rapid scrolling.
4. Enable vertical inversion only. Repeat vertical Zoom and vertical Pinch;
   their directions must reverse, without changing horizontal Pinch behavior.
5. Enable horizontal inversion only. Repeat horizontal Pinch;
   their directions must reverse, without changing vertical behavior.
6. Repeat these checks with Smooth Scrolling on. Enabling Linear Scrolling must
   not turn Zoom into normal scrolling or a synthetic glide.

## Hovered-window activation and cache

1. Put two browser windows side by side. Activate the left, hover over the right,
   then press the keyboard Zoom modifier without scrolling. Focus must stay left.
2. Scroll while holding the modifier. The right window must activate before it
   zooms; the left must not zoom. Repeat with different apps and a native app that
   supports the standard keyboard Zoom shortcuts.
3. Put a smaller window over a larger browser window. Start Zoom over an exposed
   part of the browser, keep the modifier held, move into the smaller window and
   scroll. The browser behind it must stop receiving Zoom.
4. Keep the pointer stationary and bring another window beneath it. Wait more
   than 0.5 seconds and scroll. Targeting must reflect the new window.
5. Move rapidly between windows while scrolling. Release the modifier, disable
   Zoom, or close the target during activation. There must be no delayed return
   to an obsolete window, stuck gesture or crash.
6. Repeat on a second display and on the current visible Space. Zoom must not
   unexpectedly travel to a hidden Space.

## Switcher and Vorssaint panels

1. Temporarily assign Command to Pinch (Zoom changes to None) and enable vertical
   inversion. Open the switcher with
   Command-Tab, keep Command held, and scroll through its selection.
2. Disable Pinch and repeat. Selection direction must be identical in both
   cases, and no underlying app may receive magnification. Repeat with Smooth
   Scrolling off and on.
3. Put Settings, Dynamic Island, a dock preview, and a screenshot editor or
   shielding panel over a zoomable browser. Modifier-wheel must preserve the
   interactive panel's controls, not zoom the browser behind it.
4. Assign Option to Pinch and test the screenshot loupe's Option-wheel
   fast/stepped control. The existing control must still work.
5. Test a click-through overlay separately. It must not prevent Zoom reaching
   an eligible underlying window.

## Modifiers, wheel speed and exclusions

1. Assign Control, Option and Command to each of the two actions in turn.
   Verify the new key works and the previous key stops triggering that action.
   For Zoom, cycle Command → Option → Control → Command without restarting.
   After each change, leave Settings active, hover over a browser without
   clicking it, and hold the newly selected key while scrolling. The browser
   must activate and subsequent ticks must zoom, rather than remaining raw
   indefinitely. Repeat after explicitly clicking the browser first. Merely
   holding the key without scrolling must never activate it.
2. Assign a key already used by another action. Its previous owner must change
   to None, regardless of which of the two actions owned it.
3. Verify None, disabled actions, and extra held modifiers do not trigger Zoom.
   Change assignments repeatedly; the app must not crash or restart.
4. Turn the wheel one tick at a time with pauses, then rapidly or in free-spin
   mode. Pinch must respond to small ticks. Keyboard Zoom should limit a burst
   to roughly ten steps per second rather than one step per high-resolution event.
   Reverse immediately; reversal must not wait for the burst limit.
5. Add an app to the scroll-direction exception list. Its wheel must keep its
   existing behavior instead of being converted into Zoom.
6. Check ordinary unmodified mouse scrolling and real trackpad scrolling/pinch.
   These must not acquire the configured mouse Zoom behavior.
7. Enable macOS Accessibility modifier-scroll screen Zoom and test its overlap
   with an assigned Control modifier. The card explains that application Zoom
   takes precedence for handled ticks; pending/unhandled ticks remain unchanged.

## Settings and localization

1. Search Settings for Zoom and Pinch in English. The
   results must reach the Zoom card, and the sidebar must place Zoom alongside
   scrolling features rather than after click debounce.
2. Disable both inversion axes while leaving Zoom or sideways scrolling enabled.
   The card must not claim that mouse scrolling is being inverted.
3. Check all supported languages, especially German/Russian for longer labels
   and Japanese/Chinese for different scripts. Verify the three aligned columns,
   translated modifier names, disabled picker state, screen-Zoom warning and
   window-activation explanation. Search using each language's actual row names.

## Review regression coverage

| Concern | Automated check | Manual evidence still required |
| --- | --- | --- |
| Switcher loses inversion | Extracted production handler receives Command-wheel with inversion and an open switcher | Actual switcher, Smooth Scrolling off/on |
| Overlapping or stale targets | Front-to-back snapshot, pointer movement, 0.5-second expiry, modifier change, clock rollback, idle refresh and release cancellation | Changing real window stacking and displays |
| Own panels at high window levels | Own-window targets at multiple levels; click-through and transparency | Actual Island, previews and capture panels |
| Keyboard Zoom reaches the wrong window | Production consumer refuses unresolved/unfocused targets and posts only for a confirmed one | Native activation and real application Zoom |
| Experimental migration | Obsolete keys and migration removed; final preferences remain covered by existing preference/backup tests | Existing Developer preferences if applicable |
| Incorrect inversion badge | Inversion-specific UI condition restored | Visual badge with inversion off |
| Pinch steals own controls | Production consumer preserves own-panel ticks and still handles an external single tick | Screenshot loupe with Option Pinch |
| Missing discovery/order | Production directory sections feed localized search and sidebar tests | Clicking actual search results |
| Control screen-Zoom overlap | Warning coverage for every supported locale | macOS screen Zoom interaction |

Use Pass, Fail or Untested for every scenario. Include the exact app, configuration,
steps and observed result for failures. Tests and selftest do not establish real
hardware or UI behavior. Do not mark a review item complete without the evidence
needed for its scenario.
