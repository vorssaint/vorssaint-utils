# Keep-awake continuity implementation plan

**Goal:** After starting keep-awake, hand off to an iPhone hotspot, gracefully quit selected apps, then dim the built-in display after a cancellable five-second countdown.

**Architecture:** A cancellable workflow owns ordering and deadlines. Platform adapters connect through the System Settings Accessibility interface and request normal application termination. KeepAwakeManager owns brightness capture/recovery so lid dimming and continuity cannot overwrite each other's saved level. SwiftUI adds an active-session button and persistent setup under Options.

**Tech stack:** Swift, SwiftUI, AppKit, Accessibility, existing IOKit brightness recovery; no new dependency or private hotspot API.

- [x] Add standalone asynchronous workflow tests for connection failure, refusal to quit, cancellation, session expiry, exact five-second sequencing, and dim failure; run against missing implementation to establish failure.
- [x] Implement workflow and AX hotspot adapter with bounded polling, explicit target selection and cancellation. Never use credentials or forcibly terminate an application.
- [x] Add options (discover/select iPhone, bundle-ID app list), active-session controls, and all supported translations. Preferences participate in backup; no captured brightness enters portable settings.
- [x] Share the existing brightness recovery marker and restoration path. Stop pending work when keep-awake ends, feature disables, screen locks, or app quits. Restore on explicit return, session end, lid opening, and restart recovery.
- [x] Run workflow tests, keep-awake suite, localization/settings suites, developer build and selftest. Exercise the developer UI and hotspot connection where permissions allow. Record hardware/permission limitations honestly.
- [x] Review diff and edge cases, push feature branch to the user's fork and open an upstream PR with exact validation evidence.

Cancellation prevents future steps; it does not undo network switching or relaunch apps. If an app refuses to quit or the hotspot cannot connect, do not dim. Capture brightness only once and retain recovery information until restoration succeeds. Connecting may briefly interrupt running network requests. The AX adapter opens System Settings and requires Accessibility permission; OS UI changes must fail visibly rather than silently claim success.
