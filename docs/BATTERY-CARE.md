# Battery Care

Battery Care is an optional beta feature under Features → Energy and display. Install
it, open its Energy settings, authorize the existing signed helper, choose a
limit and enable charge control, then click Apply. It starts disabled. Existing
fan control and battery monitoring remain available.

Quit other charge controllers before enabling it. The Developer and release
apps share a battery ownership lock, so only one can control charging.

## Controls

- Charge limit from 20–100%, with a configurable recharge range (hysteresis).
- One-time top-up, pause/resume and discharge to a target while plugged in.
- Optional automatic discharge above the limit and discharge with the lid closed.
- Battery-temperature protection with a 2°C recovery band. Missing temperature
  is reported; calibration does not bypass heat protection.
- Explicit calibration: full charge → 10% → full charge → saved limit.
  The displayed 100% alone does not complete a charge phase. Cancellation,
  unplugging and a 48-hour deadline end temporary operations.
- Pause charging while sleeping, optionally keep the Mac awake while charging,
  pause charging when Vorssaint closes, or optionally continue control after it closes.
  Pause-on-close takes precedence over continuing the usual policy; use Resume
  to resume charging after reopening. Forced discharge
  always reconnects the adapter before sleep.
- MagSafe LED automatic, green, orange, blinking and off, when supported.
- One-time, daily, weekday, weekly, fortnightly, monthly and yearly schedules.
  Scheduled actions include charge limits, top-up, calibration, discharge,
  pause and Low Power Mode. Recent missed jobs run once after wake; jobs more
  than ten minutes late are skipped and advanced.
- Battery charge, temperature, power, cycles and capacity-ratio estimate in the
  settings card; the existing Power panel retains its graphs and monitoring.
  Battery Care adds status and quick actions to that panel. Existing menu-bar
  battery display customization continues to apply.

Settings and schedules participate in settings backup. Enabling hardware control
is local to this Mac and is not imported from a backup. Helper recovery records
are root-owned and are not exported. No telemetry leaves the Mac.

## Shortcuts

Use **Run Shell Script** in Apple Shortcuts. For the installed Developer app:

```sh
"/Applications/Vorssaint (Developer).app/Contents/MacOS/VorssaintDeveloper" --battery-care status
"/Applications/Vorssaint (Developer).app/Contents/MacOS/VorssaintDeveloper" --battery-care setLimit 80
"/Applications/Vorssaint (Developer).app/Contents/MacOS/VorssaintDeveloper" --battery-care topUp
```

The release executable is `/Applications/Vorssaint.app/Contents/MacOS/Vorssaint`.
Other commands: `discharge 80`, `pause`, `resume`, `calibrate`, `cancel`,
`lowPowerOn`, `lowPowerOff`, and `setLED automatic|green|orange|blinking|off`. Status returns JSON including percentage, temperature,
state, configuration and capabilities; Shortcuts can extract these dictionary
values. Commands require the installed, signed app and an approved helper.
They never request administrator privileges themselves. CLI and schedules use
exactly the same helper policy as the settings controls.

## Hardware behavior and limits

The helper discovers available controls at runtime. Modern systems use the
native PowerUI charge-limit interface. Legacy systems use the paired one-byte
SMC charge-inhibit controls or the four-byte CHTE control when present. Adapter disconnection and the MagSafe
light are separate capabilities. Every SMC write is constrained to an enumerated
key and followed by readback. No XPC method accepts an arbitrary key, executable
or file path.

PowerUI and SMC control are private interfaces, so firmware can reject a control
even when its key exists. Such a rejection is an error, never a reported success.
The native backend cannot enforce a pause below its 20% minimum limit.
The native interface may allow its own full-charge calibration and is not an
absolute guarantee that the battery never exceeds the selected percentage.
A configured limit and physical charge behavior are different observations.
This implementation does not defeat Apple's firmware safeguards.

A root-owned baseline is saved before modifying charging. Disabling the feature,
normal helper shutdown and explicit uninstall restore it, including the original
native limit, adapter and LED state. Restore failures retain the recovery record
and retry. Crash recovery restores the baseline before optionally resuming a
persistent policy; unfinished calibration/discharge jobs are not resumed.

## Diagnosing a failed operation

The settings card displays the failed PowerUI operation or SMC key below the
error message. The same diagnostic appears as `errorDetail` in CLI status JSON.
A visible battery percentage only confirms telemetry; it does not prove charge
control is writable. A failed control operation disables the policy and attempts
to restore the original settings. If restoration also fails, its diagnostic is
included and the helper keeps retrying recovery. Keep external power connected
and retry disabling control in that case.

Automatic MagSafe mode leaves the system light alone until an explicit color
has been applied. Native top-up disables the active limit without first enabling
another limit. Private-interface behavior still needs verification on the Mac.

## Validation

Run `./build.sh --test-suite=battery-care`, the related `features`, `settings`,
`preferences` and `localization` suites, a developer build and its selftest.
Policy tests use synthetic readings and do not write hardware. They cover
limits, hysteresis, temperature, calibration, unplug/sleep, timeout, schedules
and localization coverage. They do not establish hardware compatibility.

Before treating a Mac as supported, manually verify charging stops/resumes,
adapter reconnection, sleep/wake, clamshell, heat protection, helper restart,
app exit, disable and uninstall on that exact Mac/firmware. Verify with an
independent battery reading, not solely the requested setting. Do not run two
charge controllers during these tests.

## References

Behavior was compared with [AlDente's published feature descriptions](https://apphousekitchen.com/aldente-overview/features/).
Private interface names and firmware limitations were checked against
[Chargectl's source](https://github.com/tyldra-org/chargectl) and
[Apple's charge-limit guidance](https://support.apple.com/102338).
The implementation reuses Vorssaint's SMC client and helper authentication; it
adds no external package dependency.
