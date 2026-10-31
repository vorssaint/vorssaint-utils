# Vorssaint Audio

Local build of main plus PR #3136, extended with an optional virtual output for native macOS volume UI and concurrent per-app controls.

## Use

Build/install the separate development app with `./build.sh --dev --install`. For an optimized local build retaining its separate identity, use `VORSSAINT_DEV_OPTIMIZED=1 ./build.sh --dev --install`. The normal mixer needs no driver. Enabling **Software volume fallback** in Mixer > Options offers the bundled installer when the optional Vorssaint Audio driver is missing or too old. Cancelling the confirmation leaves the option off. Confirming opens Apple Installer and stores the desired On setting; processing starts only when a compatible driver is available. Cancelling Apple Installer leaves this visible pending setting on, so turn it off to cancel that request. A later HAL notification never re-enables a setting the user turned off. The administrator installer adds only `/Library/Audio/Plug-Ins/HAL/VorssaintAudio.driver` and restarts Core Audio, briefly interrupting audio.

With **Software volume fallback** enabled, the app uses writable native device volume first: AirPods and built-in speakers retain native master volume without the virtual driver. Previously controlled apps can still use the separate per-app renderer on these outputs. For a fixed-volume physical device such as a Samsung DisplayPort monitor, it selects **Vorssaint Audio** as the system output and forwards the final mixed stream to the selected physical device. Volume and mute remain normal macOS controls. Per-app sliders remain available. Per-app routes explicitly sent to a different physical device follow native semantics: default-output master volume does not control another device.

The per-app format watcher distinguishes a new format suspension from a routine refresh queued during validation. A successful validation can resume rendering even when the trailing routine read is throttled; a newer format notification still keeps the old callback silent until its own validation. Regression checks cover initial/repeated validation, unchanged polling, changed formats and stop/invalidation. This fixes a reproduced startup race that otherwise left the callback suspended and exhausted recovery.

An explicit per-app volume choice is remembered even after reset to 100%. While that application's output IO is running, the mixer prepares its existing control path after a restart so the first later slider change can update gain without building a new tap. Applications with no saved volume or route remain untouched. A unity engine can be released when output IO stops; a later resume prepares it again. Anonymous process rows retain this choice only within the current session. Hiding an application, call-audio bypass and disabling the mixer keep their existing authority. First-ever control, startup during existing playback, recovery and device changes may still require a brief audio-path handoff.

At displayed 100%, per-app gain is exactly unity. The per-app boost peak limiter is enabled only for requested gain above unity; native tap compensation alone does not enable it. A preallocated per-frame flag retains boost protection for delayed samples while moving through 100%. Unboosted samples keep the same fixed 256-frame delay without extra peak attenuation. This describes the local DSP stage, not a guarantee of bit-perfect end-to-end device or Bluetooth playback.

Before starting a replacement physical bridge, the app writes and verifies the destination’s saved master level and mute. Its pump and physical IO start only after those controls match, so a new destination cannot inherit the previous output’s level during initialization. A failed write/readback aborts startup. Clearing the last per-app/universal route releases unity processing if no separate saved volume or active edit still requires it; remembered volume control remains prepared.

Select outputs in the mixer or macOS. Returning to a native-volume output removes the virtual path; returning to a fixed-volume output recreates it. If a connection, format, rendering or owner heartbeat fails, the app/driver gives control back to available physical output. Quitting or disabling normally restores the previous output and alert-sound route. A fixed-volume physical output regains its unattenuated path when software processing stops.

The Sound output switcher package and audio output priority use the underlying physical destination while fallback is active. Vorssaint's internal driver and loopback devices are excluded from their choices; other vendors' virtual outputs remain selectable. Existing switcher selections containing Vorssaint Audio migrate to its remembered physical output. Repeated shortcut presses track the latest requested destination and discard superseded queued changes.

Audio priority retains disconnected hardware in its saved order and marks it unavailable until it returns. Missing last-known names fall back to device UIDs. On upgrade, both input and output priority lists persistently remove the old private `com.vorssaint.utils.software-volume.bridge.*` identities and internal driver UIDs; unavailable hardware and other vendors' virtual devices are retained. These lists are local preferences, not preconfigured devices shipped to other users.

Driver 1.2/build 4 exposes an output-only device with no hidden input. A bounded PCM property transfers playback to the app's background pump; the physical output callback never reads an input. Access requires the main/development app signed by the driver's leaf certificate, in addition to exclusive PID ownership. Native gain/mute are applied once at final playback. Per-app taps retain their System Audio Recording permission. Physical input streams are disabled and read back before IO starts. The local bridge/component does not save or upload audio. See [microphone boundaries and verification](SOFTWARE-VOLUME-PRIVACY.md).

The app requires build 4 and never falls back to the old hidden input. An older installed driver triggers the optional installer when enabling fallback. App and driver must use the same signing certificate; ad-hoc drivers cannot authorize this transport. A local development installation uses the existing stable signing identity.

The app has separate preferences/permissions under `com.vorssaint.utils.dev`; it does not replace the official app and does not auto-update from official releases.

## Remove component

Open Settings > Volume mixer > Options and choose **Remove audio driver**. **Audio privacy** is available in the same settings section. These management actions do not appear in the menu-bar or notch quick controls. The app turns fallback off, restores physical playback, requests administrator approval, removes the dedicated HAL bundle and package receipt, and clears its saved fallback device/levels. Cancelling authorization leaves the component installed and fallback off. **Uninstall Vorssaint completely** also removes the component before deleting the app.

For removal without launching the app, quit Vorssaint and run `./Tools/uninstall-software-volume-driver.sh` in Terminal. A copy is also bundled at `Vorssaint.app/Contents/Resources/uninstall-software-volume-driver.sh`. It requests administrator authorization, verifies the exact bundle identity, removes only the dedicated driver and restarts Core Audio. The official application is untouched.

## Verify

- `./Tools/test-software-volume.sh`: driver, bridge/policy and isolated uninstaller filesystem checks.
- `./Tools/build-software-volume-driver.sh`: driver-interface, ownership, native control and qualified PCM, caller authorization and native-control checks.
- `swiftc Sources/Vorssaint/Services/QuickTools/MicMuteSupport.swift Sources/Vorssaint/Services/Audio/VirtualOutputSupport.swift Tests/SoftwareVolume/BridgeTests.swift -o build/software-volume-bridge-tests && build/software-volume-bridge-tests`: hardware-first policy, restore policy, microphone/channel isolation and progress checks.
- `./build.sh --test`, built app `--selftest`, and `codesign --verify --deep --strict` on app/driver.

Third-party source, pin and modifications are recorded in `ThirdParty/BlackHole/UPSTREAM.md` with its GPL license. This is a local build, not an official release.

## License and release packaging

BlackHole source at the recorded pin is GPLv3; Vorssaint is GPL-3.0-or-later, so this distribution uses the compatible GPLv3 terms. The package contains our own build of the source, uses Vorssaint Audio branding, preserves upstream notices and includes the exact driver Corresponding Source and build script inside the driver bundle. It does not include upstream's proprietary official installer/binaries or artwork. See `ThirdParty/BlackHole/UPSTREAM.md` and `LICENSE` for the applicable notices and redistribution requirements.

Local signatures are not Developer ID distribution signatures. Official packaging must configure `VORSSAINT_DRIVER_SIGN_IDENTITY` and `VORSSAINT_INSTALLER_SIGN_IDENTITY`, complete its notarization/release review, and retain matching source access.

## Driver updates

Each app bundle records the exact driver build it ships in `VorssaintAudioDriverBuild`; the build script derives it from the driver's `CFBundleVersion`. The app requires at least that build and the output-only protocol floor. With fallback already enabled, an older or invalid installed build causes one update offer per app launch. Unused optional components do not trigger an update offer. Declining does not repeat the offer on each audio-device notification; the update action remains available in Options.

The installed version is checked again when opening Installer, so a stale alert cannot launch a downgrade after another update completed. Package metadata also enables version and strict-identifier checks, treats Corresponding Source as data rather than another installable bundle, and preserves a newer legacy component. Installation uses the bundled package and standard macOS administrator approval. No driver binary is downloaded silently. Readiness requires the loaded HAL to expose the owner, session-key and output-PCM interfaces, rather than accepting only a newly copied plist.

Increment the driver build whenever a new driver/protocol or signing-certificate change requires users to reinstall it. Release app and driver signing identities must satisfy the same certificate requirement. The current local development package is unsigned and must not be represented as a notarized public release.

## Local validation, 2026-10-31

On macOS 27.2, the tester confirmed Samsung playback, native volume keys/mute/system slider/OSD, per-app 50%/110% and continuous slider changes without the orange microphone indicator. Retaining an existing per-app engine while output IO continues also eliminated the confirmed reset 100% / wait / adjust dropout. The tester subsequently confirmed AirPods playback no longer stutters; an earlier transient disappeared after restart, so its exact cause is not established. No PR3538 gain-ramp code was merged.

Two separate 120-second samples (13 readings, 10 seconds apart) recorded native AirPods app memory 83 MB and driver 5.1 MB, both stable. Active Samsung fallback recorded app 75–76 MB and driver 5.4–7.7 MB, ending 75 MB/5.4 MB. Median driver CPU was 0% on the native route and 7.6% of one CPU core with fallback; the app median was 2%/5.5%. These are short-run observations, not a long-term leak proof or a controlled benchmark of every app feature.

Latest SDK27.2 automated suite including priority migration and remembered control: 119959/119960 checks passed; the sole failure is the previously observed `Tests/NotchCompactTests.swift:339` history-selection test. Mixer 1240, audio priority 24, localization 8651, driver 49, bridge/update 39, uninstall 10, concurrent PCM and playback suites passed. Priority migration tests exercise the production preference loader, persistent removal of retired internal devices, preservation of disconnected hardware/third-party virtual devices, and repeated loading. Driver upgrade policy was tested for missing/older/current/newer/invalid builds, stale offers, cancellation and explicit Off. A temporary signed app requiring build 5 against installed build 4 showed the real update alert and opened its bundled installer; installation was cancelled, leaving the actual driver unchanged.

Selected screenshots and their capture conditions are in [pr-assets/software-volume-output-only](pr-assets/software-volume-output-only/README.md). Final-build Samsung sleep/wake and iPhone microphone recording with concurrent playback are now verified below.

A final owner-death test used SIGKILL with Music paused and fallback active: macOS restored the built-in physical output by the first metadata sample, and remained there throughout a six-second observation. This verifies route restoration with the new transport; it is not a claim of uninterrupted sound during a crash.

The latest optimized SDK27.2 app was checked after the validation-race fix: two clean restarts prepared remembered Music at 100% without interaction. The user confirmed smooth first 100→50%, reset/wait/boost on native AirPods and smooth per-app/system controls on Samsung fallback, without the orange microphone indicator. Reconnected AirPods returned to native output through Audio priority. The latest bundled selftest and strict app/driver signatures passed.

A later controlled native AirPods comparison reproduced a quieter/different sound at per-app 100% with equal hardware volume and mute. The per-app renderer was applying boost peak protection at unity. The corrected unboosted production DSP preserves tested sample values after its fixed delay, including overrange samples; protection remains attached to delayed boosted frames. A synthetic 0.999-amplitude probe previously lost about 0.492 dB; no exact attenuation of the played song was measured. After the fix, the user repeated the comparison and reported no audible difference. Production-callback regressions cover these boundaries, compensation and fallback layouts. Install/update action labels also omit trailing ellipses in all 15 languages.

After the final limiter/unity correction, the user confirmed smooth AirPods per-app 50% → reset 100% → wait → 110%, without the orange microphone indicator.

Final review fixes have deterministic production-method regressions: target controls precede the bridge’s first callback, initialization fails closed on failed/mismatching controls, and clearing a same-device route releases otherwise unnecessary unity processing. The tests failed before their respective fixes (13 startup assertions, 2 route-cleanup assertions) and pass afterwards. No audible two-fixed-output A→B switch was performed on this host.

After installing both final-review fixes, the user confirmed responsive AirPods and Samsung playback/controls without interruptions or the orange microphone indicator. The latest full SDK27.2 suite passed 119959/119960 checks, with only the accepted NotchCompactTests.swift:339 baseline failure; mixer1240, driver49, bridge39, uninstall10, PCM/playback and installer/SDK checks passed. Optimized app selftest and strict app/driver signatures passed. Driver build4 is unchanged.

Final-build Samsung sleep/wake passed. The macOS power log confirmed actual sleep/wake; the same app process resumed Music and the output-only fallback after device re-enumeration, preserving master volume/mute. The user confirmed volume keys, mute/unmute, native icon/OSD, system slider and per-app50/reset100/wait110 after wake, without interruptions or the orange microphone indicator.

Final-build iPhone input coexistence passed with Music playing through Samsung fallback. QuickTime explicitly selected the iPhone microphone; Core Audio associated its active input with that device. The user recorded and listened locally, confirming correct microphone recording and uninterrupted Music. After closing the recording window/quitting QuickTime, the physical input was stopped while Music/fallback continued, and the user confirmed the orange indicator cleared. The voice recording is excluded from publication. This does not certify every duplex USB interface.
