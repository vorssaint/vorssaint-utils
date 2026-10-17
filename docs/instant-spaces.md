# Instant Spaces

Install Instant Spaces from Settings → Features → Windows and Dock. A first
install enables keyboard switching; trackpad swipes are a separate control on
its settings page. Accessibility is required. The feature starts uninstalled,
and reinstalling it preserves saved control choices.

Keyboard switching reads the enabled macOS shortcuts for moving left or right
and switching to Desktop 1–10 on each key-down. Remapping or disabling a shortcut
takes effect without switching away from System Settings. It does not rewrite
the system shortcut table.
Desktop numbers omit fullscreen Spaces; adjacent navigation includes them.
Numbered shortcuts targeting another display retain native macOS handling.

Trackpad switching follows the system's configured three- or four-finger gesture.
Small initial movement is held until its direction is clear. Moving back far
enough before lifting the fingers reverses the switch. An uncommitted gesture is
returned to macOS if it is cancelled or cannot be replaced.

Mission Control, App Exposé, Show Desktop and keyboard switching while dragging
a window retain native handling. Unknown display topology and unsupported macOS
versions also leave input alone. The supported range is macOS 15–27; this depends
on private DockSwipe events, so future versions need verification before that
range is extended.

## Implementation and licensing

`InstantSpacesService` owns the input taps and bounded desktop navigation. It uses
the existing `SpaceWindowBridge`, `SymbolicHotKeys`, `SessionActivity`, feature
catalog and permission lifecycle. The generic gesture tap is enabled only during
a horizontal swipe. Disabling the controls or uninstalling the feature releases
the taps and cancels pending navigation. Preferences participate in settings
backup; no Dock preferences are changed.

`InstantSpacesGesture` isolates the event encoding adapted from Space Rabbit at
revision `54d6eb40574a04be678f943132aa0117c9078ba5`. The macOS 27 path includes the
serialized HID payload absent from older synthetic-gesture implementations.
Attribution and distribution terms are in
[the bundled notice](../Resources/Licenses/SpaceRabbit.txt). The rest of the
integration follows the repository's GPL-3.0-or-later license.

## Validation

Run `./build.sh --test-suite=instant-spaces` for shortcut matching, display-order
navigation, swipe intent, event serialization, settings backup and localization
checks. Build the app separately and run its `--selftest`. Build and test commands
must run sequentially: a release build cleans the shared `build` directory.

Before submitting, record the Mac model, macOS build, display arrangement,
“Displays have separate Spaces” setting and Natural scrolling setting, then
verify these interactions with the Developer app:

- Keyboard and physical trackpad navigation both remove the slide animation.
  Check both directions, edges, fullscreen Spaces, quick flicks and reversals.
- Remap and disable the macOS shortcuts while the app runs. Check numbered
  desktop shortcuts with fullscreen Spaces between ordinary desktops.
- Check each display, including a numbered shortcut targeting another display.
- Confirm Mission Control, App Exposé, Show Desktop, window dragging, ordinary
  scrolling and shortcut recording retain their expected behavior.
- Disable each control, uninstall the feature, revoke Accessibility, and test
  again after sleep and fast user switching. Native navigation should remain
  available; reinstalling should restore the saved controls.
- Check Natural scrolling both on and off. Space Rabbit reports that macOS 27's
  Dock samples this preference at launch; changing it can require a Dock restart
  before the event direction and Dock agree. This integration does not restart it.

These automated checks do not demonstrate that the Dock accepts the events or
that a physical trackpad swipe is animation-free. That distinction matters for
[upstream issue #252](https://github.com/vorssaint/vorssaint-utils/issues/252),
which was closed after an earlier synthetic-gesture implementation stopped
working on macOS 27.

### Local smoke test — September 23, 2026

Tested with the Developer app on a Mac14,12 (M2 Pro), macOS 27.0 build 26A428,
with two extended displays, four desktops on one and three on the other.
Natural scrolling and the configured “Displays have separate Spaces” preference
were on. Space Rabbit's active features were disabled during the test.

The initial test failed: intentionally disabling the companion gesture tap
triggered recovery that repeatedly rebuilt both listeners. Recovery now checks
whether a required live tap is actually disabled before rebuilding it, and
redundant envelope enable/disable calls are skipped.

After that fix, the tester confirmed that Control–Left/Right and trackpad swipes
both switched instantly. Read-only WindowServer observations independently
confirmed adjacent keyboard navigation in both directions on both displays.
Those observations establish desktop changes, not animation duration; the
animation and physical swipe result are the tester's report. Temporary input
tracing was removed after diagnosis.

The remaining manual cases above, including fullscreen Spaces, swipe reversal,
shortcut remapping, sleep, fast user switching and Natural scrolling off, have
not been verified in this session.
