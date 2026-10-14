# Menu bar organizer: experimental alternative

This contribution is an alternative for review alongside [#2786](https://github.com/vorssaint/vorssaint-utils/pull/2786), [#2983](https://github.com/vorssaint/vorssaint-utils/pull/2983), and [#2989](https://github.com/vorssaint/vorssaint-utils/pull/2989). It is not intended to be merged wholesale together with competing organizer backends. The maintainer should choose or reconcile the approaches first.

## Use

Install **Menu bar organizer** in Features, then enable it in Menu Bar settings. It is experimental and uninstalled by default. It appears only on the Menu Bar settings surface, rather than also adding controls to General.

- The list contains observed status-item owners, including accessory helpers; running an ordinary app alone does not add it.
- Click the separate arrow to open hidden icons in a horizontal shelf. Option-click includes always-hidden icons.
- Click a shelf icon to invoke the real status control. Some controls open an app window rather than a menu, matching their normal click action.
- On macOS 27, right-click an icon to change its saved per-app section. All icons of one app share a section.
- Reveal All restores icons for native Command-drag ordering. On older macOS versions, the physical divider positions define hidden and always-hidden sections.
- Uninstalling or disabling the feature releases visibility restrictions and removes its timers, monitors, panels, and status controls. Saved enabled state and section rules remain available for reinstallation and settings backup.

## Permissions and rendering

Discovery and interaction use Accessibility. The organizer neither requires Screen Recording nor captures pixels when that permission happens to be granted to other features. It uses application icons, clear AppKit glass where supported, and a native translucent material on older SDKs/systems. Appearance changes are event-driven.

For custom controls that do not implement Accessibility press actions, the organizer resolves a current target, verifies the topmost hit and its owner/geometry, and posts a left-button down/up pair. It rejects ambiguous matches, covering windows, adjacent items, terminated owners, and cancelled requests. It does not click saved screen coordinates or fall back to launching a different application.

## Platform limits

macOS 27 visibility uses the private MenuBarClientCore assessment API, discovered at runtime. This can change between OS releases. Failures release the restriction and restore visible icons while preserving the requested hidden sections; periodic inventory refresh retries activation automatically, including after a transient relaunch failure. Additional system indicators can disappear while an assessment is active. Run the registered installed copy; duplicate builds with the same bundle ID can otherwise lose their recovery arrow.

Assessment mode also blocks Notification Center. The organizer temporarily releases it while the pointer is over the system clock and restores the current section rules half a second after the pointer leaves. Hidden icons are briefly visible during that interaction. Clock frames are discovered through Accessibility on a background queue; disabling or uninstalling the organizer removes the pointer monitors and cancels pending restoration. Final installed-copy verification of clock clicks and repeated app relaunches remains outstanding.

macOS 14–26 uses off-screen dividers. A crowded/notched bar may still leave a real target unreachable after revealing icons. Such targets are not guessed. No live QA on these versions is claimed by the model tests.

## Validation and remaining QA

The tests cover section rules, omitted accessory owners, changed AX identities, cache replacement, process isolation, ambiguous matches, hit-test boundaries, shelf geometry, locale coverage, feature availability, permission demand, portable preferences, failed-activation recovery, clock suspension/restoration, cancellation, and display-coordinate conversion. They do not synthesize desktop input.

On 2026-10-14, after synchronizing with upstream `main` at `1a16004cbb5253829ef695afa333825f5d99d1bb`, the organizer suite passed all 120 checks. The full suite had one failure out of 116,262 checks: the unchanged countdown-row height assertion described below. Preference cleanup, uninstall-Spaces, and developer-install isolation checks passed.

Earlier live testing of the combined development build on macOS 27.0.1 verified Tuxera and Amphetamine menus and the NeatDownloadManager window, with five hidden icons retained without duplicates. These checks preceded the final standalone feature-hub integration and upstream rebase.

On the local macOS 27.0.1 test host, the unchanged `NotchCompactTests.swift:218` countdown-row height assertion failed in the organizer full suite and isolated notch suite. The same isolated failure reproduced from a clean source archive of upstream `main` at `fe24c1766d568b132c1c78c554cc422381a3a17d`. It is recorded as an upstream/environment baseline failure; the assertion and notch implementation are unchanged in this contribution.

Before release, verify the final integrated branch on an installed copy: install/uninstall while a menu is open; Accessibility revocation; disable/quit; repeated hidden/always-hidden interactions; owner relaunch; MenuBarAgent restart; sleep/wake; a crowded notched bar; multiple displays and Spaces; and macOS 14–26. Native-speaker review of the additional locale copy and upstream Swift 6.0.3 compatibility CI are also outstanding.

The independent Arabic/RTL PR supplies the Arabic app language; this organizer includes Arabic copy by language code so either contribution can be reviewed against current main without depending on the other.
