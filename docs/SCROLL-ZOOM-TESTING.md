# Pinch Zoom review and manual testing

Pinch Zoom turns a modifier and mouse-wheel movement into a magnification gesture
at the pointer. Use an app or document that supports a real trackpad pinch.

## Install the test build

```sh
./build.sh --dev --install
./build/VorssaintDeveloper --selftest
```

1. Quit other Vorssaint instances. Disable other wheel-modifying utilities for
   the baseline test.
2. Check the build output for stable signing and grant Developer Accessibility.
   It has separate settings and permissions from the official app.
3. Install Zoom in the feature catalog, open its Mouse settings card, and enable
   Pinch Zoom. Control is the default; Option and Command are also available.
   Shift is unavailable, and a saved Shift assignment shows None.
4. Record the Mac model, macOS version, mouse model, app versions, display layout
   and Spaces configuration. A physical horizontal or tilt wheel is needed to
   verify horizontal Pinch; vertical-wheel tests do not cover that hardware.

## Baseline and direction

1. With inversion and Smooth Scrolling off, hold the selected modifier and turn
   each wheel slowly in both directions, including isolated ticks. Verify Pinch
   magnification responds without requiring rapid scrolling.
2. Enable vertical inversion only. Vertical Pinch must reverse without changing
   horizontal Pinch behavior. Repeat with horizontal inversion only.
3. Repeat with Smooth Scrolling and Linear Scrolling on. Neither should turn
   Pinch into normal scrolling or a synthetic glide.
4. Move between supported views while zooming, then release the modifier.
   The old view must stop receiving magnification and no gesture may remain stuck.
5. Repeat on a second display and the current visible Space. Holding a modifier
   without scrolling must not activate a window or switch Spaces.

## Switcher and Vorssaint panels

1. Assign Command to Pinch, enable vertical inversion, and open the switcher with
   Command-Tab. Keep Command held and scroll through its selection.
2. Disable Pinch and repeat. Selection direction must match, and no underlying
   app may receive magnification. Repeat with Smooth Scrolling off and on.
3. Put Settings, Dynamic Island, a dock preview, and a screenshot editor or
   shielding panel over a zoomable browser. Modifier-wheel must preserve each
   panel's controls without zooming the browser behind it.
4. Assign Option to Pinch and test the screenshot loupe's Option-wheel control.
   A click-through overlay must still allow Pinch to reach the underlying app.

## Modifiers and exceptions

1. Assign Control, Option and Command in turn. Verify the new key works and the
   previous key stops triggering Pinch.
2. Verify None, disabling or uninstalling Zoom, and extra held modifiers do not
   trigger Pinch. Changing the modifier or disabling it must end an active gesture.
3. Turn the wheel one tick at a time, then rapidly or in free-spin mode.
4. Add an app to the scroll-direction exception list. Its wheel must keep its
   existing behavior instead of being converted into Pinch.
5. Check ordinary unmodified scrolling and real trackpad scrolling/pinch.
6. Enable macOS Accessibility modifier-scroll screen Zoom and check its overlap
   with Control Pinch. The card explains that handled ticks zoom app content.

## Settings and localization

1. Search for Zoom and Pinch in English and other supported languages. Results
   must reach the Zoom card, which offers only Pinch Zoom.
2. Check longer labels and different scripts. Verify the aligned control row,
   translated modifier names, disabled picker state and screen-Zoom explanation.
3. Disable both inversion axes while leaving Pinch or sideways scrolling enabled.
   The card must not claim that mouse scrolling is being inverted.

Use Pass, Fail or Untested for each scenario. Record the exact app, configuration,
steps and observed result for failures. Automated tests cover modifier selection,
gesture transitions, own-window targeting and the raw and
smoothed wheel paths. They do not establish real hardware or UI behavior.
