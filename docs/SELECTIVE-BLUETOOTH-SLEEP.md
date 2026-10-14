# Selective Bluetooth disconnection on sleep

The current Bluetooth-on-sleep feature powers off the controller, disconnecting
input devices together with headphones. This extension adds a selected-device
mode for issue [#2406](https://github.com/vorssaint/vorssaint-utils/issues/2406).

## Implementation plan

1. Preserve the existing power-off mode and its restore-on-wake behavior as the
   upgrade default. Add an explicit selected-device mode with an empty selection.
2. Match selected paired devices by normalized Bluetooth address, checking fresh
   connection state at sleep. Never infer selection from a device's name or type,
   and never turn off the radio as a fallback.
3. Close selected connections using IOBluetooth on a serial worker. Bound the
   sleep-notification wait to two seconds and cancel queued calls on wake,
   disable, removal, or a mode change. An in-flight native call cannot be cancelled.
4. Add an on-demand paired-device checklist, refresh control, empty-selection
   guidance, and a disconnect-failure report. Keep unavailable selections visible
   so they can be removed. Selection changes do not disconnect devices immediately.
5. Save the mode in settings backups. Keep device addresses local to this Mac's
   pairings, preserving its selection when importing a backup.
6. Translate the controls in every supported language; verify selection,
   cancellation, failures, compatibility, settings backup, app build and selftest.

## Behavior and verification boundaries

The mode applies to system sleep with either an open or closed lid. Display-only
sleep does not trigger it. Unselected devices are untouched by Vorssaint; macOS
still owns their power and wake behavior.

Selected devices remain paired. This mode does not request reconnection on wake
or continuously suppress reconnection while the process is suspended. macOS or
the accessory can subsequently reconnect them.

Automated verification uses simulated device connections and does not switch
off Bluetooth or disconnect the user's peripherals. Hardware verification must
cover actual headphones, keyboard/mouse wake with the lid open, a closed-lid
sleep, and repeated sleep/wake cycles.

API references: [closeConnection](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/closeconnection())
and [willSleepNotification](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification).

## Completed validation

Implemented on `feat/selective-bluetooth-sleep`, based on upstream `main` and
independent of the scroll-reversal pull request.

- Six affected suites passed: `bluetooth-sleep`, `app-management`, `features`,
  `preferences`, `localization`, and `settings` (9,975 checks).
- Final Bluetooth, localization and settings recheck passed (8,367 checks).
- `./build.sh` completed with no compiler warnings and produced the app bundle.
- `./build/Vorssaint --selftest` returned `SELFTEST OK`.
- The main plist and all 14 localized permission plists passed `plutil -lint`.
- `git diff --check` passed.

These automated checks ran on an arm64 Mac with macOS 27.0.1 and the macOS 26 SDK
without changing real Bluetooth connections. The user subsequently tested the
local build and reported that the feature works. Headphone models and individual
sleep/wake scenarios were not supplied, so those details remain unverified.
Native calls already in flight can complete after cancellation.
