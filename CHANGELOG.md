# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [2.15.1] - 2026-06-16

### Fixed
- The menu panel opens fully expanded again after updating, instead of restoring
  an old collapsed layout that made it look unexpectedly tiny.

## [2.15.0] - 2026-06-16

### Added
- **Shelf now gets out of the way.** After it appears, it fades away on its own
  after a few seconds if you are not interacting with it.
- **Shelf feels more balanced.** The panel is more square, with a comfortable
  three-column grid instead of a tight horizontal strip.

### Changed
- The menu bar icon now stays full strength while idle, turns amber while Keep
  Awake is active, and still turns blue when an update is available.

### Fixed
- Shaking a file dragged from a Dock stack now opens the Shelf, matching the
  behavior of files dragged from Finder.

## [2.14.0] - 2026-06-15

### Added
- **Now in eight languages.** The interface is available in English, Português,
  Español, Deutsch, Français, Italiano, 日本語 and 简体中文. Choose yours in
  Settings › General; a one-time chooser also appears after updating.

### Fixed
- The Battery label in the system monitor no longer wraps onto a second line.
- The menu bar panel now stays centered with even margins instead of leaving a gap
  on the right when macOS is set to always show scroll bars.

## [2.13.1] - 2026-06-15

### Fixed
- The System monitor step in the welcome tour now scrolls, so its content is never
  clipped at the bottom on shorter windows.

## [2.13.0] - 2026-06-15

### Added
- **Make the panel yours.** Collapse any section you don't use with a tap on its
  header, and drag to reorder the sections from Settings › Monitor. The panel shows
  what matters to you first, with less scrolling.

### Changed
- Cleaning Mode moved into the panel's footer, alongside Settings and Quit.

### Fixed
- **Keyboard shortcuts work in the Settings window.** Cmd+W, Cmd+M, Cmd+H and Cmd+Q,
  plus cut, copy, paste and select all in text fields, now respond as expected.
- Removed an occasional extra outline around the Shelf, and evened out the panel's
  spacing so it no longer sits closer to one edge.

## [2.12.0] - 2026-06-15

### Added
- **Support the project.** A new Support tab in Settings, and a brief one-time note
  when you update, let you back Vorssaint with a coffee if you'd like. It stays
  free, with no subscription, always.

### Fixed
- **Battery health matches macOS.** The health percentage now lines up with the
  "Maximum Capacity" shown in System Information.
- **The menu bar icon is recoverable.** macOS can hide menu bar icons when the bar
  runs out of room, common on Macs with a notch. Now reopening Vorssaint from
  Applications brings the icon back, a new "Show menu bar icon" button in Settings
  rebuilds it, and the icon remembers its position.
- Fixed the Support tab hiding the rest of the Settings sidebar.

## [2.11.0] - 2026-06-15

### Added
- **Cleaning Mode.** Locks the keyboard so you can wipe it down without typing
  anything by accident. Unlock by pressing the same key five times in a row, by
  clicking Unlock on the overlay, or just by waiting, since it releases on its own
  after a minute. Start it from the panel or the icon's menu.

### Fixed
- **Battery health now matches macOS.** The health percentage lines up with the
  "Maximum Capacity" shown in System Information.
- **Removing the menu bar icon no longer locks you out.** The icon can't be dragged
  off the bar by accident, it always comes back on launch, and reopening the app
  from Finder or Spotlight restores it and opens the panel.
- The icon's right-click menu now opens reliably even when the panel is already open.

## [2.10.0] - 2026-06-15

### Added
- **System monitor, expanded.** The panel now shows live network speed (download
  and upload) with session totals; power draw, broken into what the Mac consumes,
  what it pulls from the adapter, and the battery's flow, health, charge and cycle
  count; and history graphs for CPU, GPU, memory, network, power and battery. A
  system uptime line is included too.
- **Metrics in the menu bar.** Pin any of CPU, GPU, RAM, Network or Power next to
  the icon, updated live. Memory can show as a colored pressure dot, a percentage,
  or both. Everything is opt-in, and the text keeps a fixed width so the icon
  never shifts as the numbers change.
- **Internet speed test.** Measure download, upload and latency on demand from the
  Network block.
- **Pick exactly what you see.** Choose which blocks appear in the panel and which
  items appear inside each block, both in Settings and during setup. New options
  default to on, so nothing changes until you tune it.
- **Update notifications.** When a new version is available the menu bar icon turns
  blue and a banner offers it at the top of the panel. Automatic checks are more
  frequent and also run when you reopen the app, so updates surface on their own.

### Fixed
- Fixed two mach port leaks in the CPU and memory sampling that could slowly
  accumulate while the panel was open.

## [2.9.1] - 2026-06-14

### Changed
- The switcher's grouping option now shows **one entry per app**, collapsing all
  of an app's windows into a single entry instead of one per window. Turn it on
  for an app-level switcher rather than a window-level one.

## [2.9.0] - 2026-06-14

### Added
- **Switcher option to merge an app's tabs.** A new setting makes the window
  switcher treat the tabs of one window as a single entry, so apps like Finder
  and Terminal with many tabs no longer flood the switcher. It is off by default;
  when on, only the active tab of each tabbed window is shown.

## [2.8.1] - 2026-06-14

### Fixed
- The mixer slider no longer stays amber after a boosted app returns to 100% or
  below. It goes back to the normal color as soon as the volume is no longer
  above 100%.

## [2.8.0] - 2026-06-14

### Added
- **Volume boost in the mixer.** Each app's volume now goes up to 200%, for when a
  video or call plays too quietly. Above 100% the slider and the percentage turn
  amber so a boost is never mistaken for normal volume, and a one-tap reset button
  returns that app to 100%. At 100% the audio stays bit-perfect passthrough.

## [2.7.3] - 2026-06-14

### Fixed
- The ⌃⌥⌘K shortcut toggles "Keep awake" reliably again. When the temporary shelf
  was also enabled, its global shortcut could swallow the ⌃⌥⌘K key press, so
  nothing happened; the two shortcuts no longer interfere.

## [2.7.2] - 2026-06-14

### Fixed
- On the "Quit on last window close" onboarding illustration, the red close
  button now sits aligned with the other window buttons, instead of off in the
  corner of the window.

## [2.7.1] - 2026-06-14

### Changed
- **The brand badge now sits on a solid black background** instead of the
  previous purple-tinted one, for a cleaner, more neutral look. It affects the
  menu bar panel header, the About tab and the onboarding screens.

## [2.7.0] - 2026-06-14

### Fixed
- **Quit on last window close** no longer quits an app when you leave full screen
  with the green button. Exiting full screen briefly leaves the app without a
  window for a moment, which was being read as the last window closing; it now
  confirms the app is really window-less, after the transition settles, before
  quitting it.

### Added
- **Advanced settings page** with two clean-up tools, each behind a confirmation:
  - **Clear all permissions** resets every permission you granted Vorssaint
    (Accessibility, Screen Recording, Full Disk Access and the rest) and removes
    its login item and closed-lid rule, leaving the app in place. Good for a fresh
    start or before uninstalling.
  - **Uninstall Vorssaint completely** does all of that, removes the preferences,
    moves the app to the Trash and quits, leaving nothing behind. You can
    reinstall anytime.

## [2.6.0] - 2026-06-14

### Changed
- **Vorssaint is now signed with an Apple Developer ID and notarized.** The
  first-launch security warning is gone: downloads open normally, with nothing to
  click around. Releases are notarized and stapled automatically.

### Migration
- **You will grant permissions once on this update.** Notarization requires a
  different signing certificate, which changes the app's code identity, so macOS
  asks you to re-allow Accessibility, Screen Recording and the like a single
  time. After this update the identity is stable again (now an Apple-issued one),
  so future updates keep your permissions as before. Your settings and data are
  untouched.

## [2.5.4] - 2026-06-13

### Changed
- **Less idle background work.** The Full Disk Access check no longer runs on the
  recurring permission poll. That access cannot change while the app is running
  (only across a relaunch), so it is now checked at launch and when the app is
  reactivated instead. This removes a steady stream of denied file accesses for
  anyone who has not granted it, with no change in behavior

## [2.5.3] - 2026-06-13

### Fixed
- **The uninstaller no longer keeps asking for Full Disk Access after you grant
  it.** The app detected access by reading the TCC database, but that file does
  not exist on every macOS version, so the check always failed and the banner
  stayed even with access granted and the app reopened. It now also confirms
  access by listing a protected folder that exists (Safari, Mail, Messages and
  the like), which is reliable across versions. No need to re-grant: the banner
  clears on its own once you are on this version

## [2.5.2] - 2026-06-13

### Fixed
- **Granting Full Disk Access from the uninstaller is reliable now.** The app
  registered itself with the system and opened the settings pane in the same
  instant, so it was often missing from the list. It now reads the always-present
  TCC database (the dependable trigger) and waits for the system to record the
  request before opening the pane. The hint also explains the sure path: if the
  app is not listed, add it with the list's "+" button from Applications

## [2.5.1] - 2026-06-13

### Fixed
- **A 2.5.0 install updated from an older version could move itself to the
  Trash on first launch.** The startup cleanup compared bundle locations too
  strictly and mistook the just-updated app (still at the old path, because the
  previous updater installs in place) for a leftover copy. It now renames that
  bundle to `Vorssaint.app` through a helper that runs only after the app quits,
  always reopening the app, and the leftover cleanup only runs for a bundle that
  is provably not the one running. Recover a trashed copy by reinstalling from
  the DMG: the bundle id is unchanged, so permissions and settings return intact

## [2.5.0] - 2026-06-13

### Changed
- **The app is now "Vorssaint" everywhere the system shows it.** The app file is
  renamed to `Vorssaint.app` and its executable to `Vorssaint`, so Spotlight, the
  Applications list, Login Items, notifications, the permission panes and system
  dialogs all read "Vorssaint", with no trace of the old name
- Internal names follow suit (the audio mixer device, the closed-lid rule file,
  the diagnostics binary) and the source tree moved to `Sources/Vorssaint`

### Migration
- **Updating keeps your permissions, settings and data, with nothing to do.** The
  bundle identifier is unchanged, so every granted permission (Accessibility,
  Screen Recording, Full Disk Access, Automation), your preferences and the login
  item carry over untouched. The update installs `Vorssaint.app` and removes the
  old `Vorssaint Utils.app`; if a copy is ever left behind (for example after a
  manual install), the app moves it to the Trash on its next launch. The
  closed-lid rule file is renamed the next time that toggle is used

## [2.4.7] - 2026-06-13

### Changed
- **The switcher is window-based.** ⌘Tab now moves between windows, including
  multiple windows of the same app, and a quick flick returns to the last window
  you used. The browser-tabs entries were removed

### Fixed
- **Full Disk Access banner** no longer lingers after you grant it: the app
  re-checks when it regains focus and offers a Relaunch button (the access only
  applies to a freshly launched app)
- **Onboarding**: shortcut keys no longer overlap their description text

## [2.4.6] - 2026-06-12

### Changed
- The app is now called simply **Vorssaint** everywhere you see it (menu bar,
  About, onboarding, notifications). The bundle id, signing identity and app
  filename are unchanged, so this update keeps your granted permissions
- README rewritten around what each feature gets you, with the free, local,
  no-account stance up front

## [2.4.5] - 2026-06-12

### Fixed
- **Uninstaller**: apps the system protects (root-owned, installer-based) are
  now removed through Finder, which asks for the administrator password and
  moves them to the Trash like a drag would. The scan also hardens against
  hostile bundle ids and never lists anything outside ~/Library, /Library or
  the picked app

### Changed
- The uninstaller lives directly inside Settings: drop an app on the page, no
  separate window, no enable toggle
- The display now always stays on while a keep-awake session is active; the
  separate toggle is gone
- Cleaner wording across the app and the documentation

## [2.4.4] - 2026-06-12

Stability pass over the whole project: same behavior, fewer ways to fail.

### Fixed
- **Self-update is fail-safe**: the new version is fully copied next to the app
  before the old one is removed, so a failed download/copy can never leave you
  without an app
- **Uninstaller**: scan results landing after you picked a different app are
  discarded (files of app A can no longer be listed under app B); display names
  only strip a trailing ".app"
- **Cut & paste**: an unexpected Accessibility value can no longer crash the
  app from inside the keyboard tap, and a cut superseded by a copy elsewhere
  now dismisses its HUD instead of lingering
- **Shelf**: an image dragged from a web page is kept as an image, not as a
  link to the page

### Changed
- Periodic timers gained tolerances so macOS can coalesce wakeups (less power)
- Internal dedup: one screen-under-mouse helper and one HUD backdrop shared by
  all floating panels; CI workflows moved to the actions' Node 24 lines

## [2.4.3] - 2026-06-12

### Changed
- **Shelf**: tiles are now AppKit-backed so you can select several items (click
  to select) and drag them all out in a single drag

### Fixed
- **Shelf**: you can move the panel again: drag its top bar to reposition it,
  while grabbing a tile still drags the item
- **Shelf**: dropping item(s) somewhere now removes them from the shelf
  automatically (a cancelled drag keeps them)

## [2.4.2] - 2026-06-12

### Fixed
- **Uninstaller**: granting Full Disk Access now actually works. The app
  registers itself with the system first, so it appears (with a toggle) in the
  System Settings list instead of opening to a list it isn't in, and a short
  hint explains how to enable it

## [2.4.1] - 2026-06-12

### Fixed
- **Shelf**: dragging an item out of the shelf now works. The panel no longer
  moves with the pointer, so grabbing a tile starts an item drag instead of
  dragging the whole window
- **Shelf**: shaking the mouse while *moving a window* no longer summons the
  shelf; it appears only when something droppable (a file, image, text or link)
  is actually being dragged

## [2.4.0] - 2026-06-12

### Added
- **Cut & paste files in Finder**: ⌘X cuts the current selection and ⌘V moves it
  into the folder you're viewing, with a floating HUD showing the held items.
  Text fields keep their normal shortcuts. Opt-in
- **Quit on last window close**: when an app that had a window closes its last
  one, it quits, with a per-app exception list (Finder excepted by default).
  Opt-in
- **Complete app uninstaller**: drag an app (or pick one) to find the caches,
  preferences, logs, containers and other files it leaves behind, each with its
  size, then move the selected ones to the Trash and see the space recovered.
  Opt-in
- **Temporary shelf**: a floating area, summoned at the cursor with ⌃⌥⌘D or by
  shaking the mouse mid-drag, that holds files, images, text and links to drag
  back out into any app later; needs no permissions. Opt-in
- A visual onboarding page for each new feature; people updating from an earlier
  version see a one-time "what's new" pass to discover and configure them

### Changed
- Settings moved from a tab bar to a System-Settings-style sidebar, giving every
  feature its own page with room for examples and options

## [2.3.0] - 2026-06-12

### Added
- **Per-app volume mixer** in the panel: set the volume of each app holding an
  audio connection (CoreAudio process taps, macOS 14.4+). A live indicator marks
  apps playing now; volumes persist per app; 100% is untouched passthrough
- **Browser tabs are first-class in the switcher**: each Safari/Chrome/Edge/
  Brave/Vivaldi tab is its own entry

### Changed
- **Switcher is instant**: a browser tab now raises its window immediately
  instead of waiting on the tab-select script, and the panel only appears after
  a short delay so quick flicks switch with no UI
- **Tab-granular toggle**: the switcher tracks a most-recently-used order of
  individual items, so ⌘Tab toggles between two tabs of the same browser just
  like between two apps
- The CPU/GPU/memory breakdown consolidates helper processes under their app
  (one Safari row, not a dozen Web Content rows)

### Removed
- The quick-utilities panel section (hide desktop icons, show hidden files, turn
  off display, eject disks, empty Trash)

## [2.1.0] - 2026-06-12

### Added
- **Per-app resource breakdown**: tapping CPU, GPU or Memory in the panel's
  System section expands the top consumers of that resource. CPU and memory
  come from the process table; per-app GPU% is computed from the accelerator's
  per-process GPU-time counters, sampled as deltas
- **Browser tabs in the switcher**: every Safari/Chrome/Edge/Brave/Vivaldi tab
  appears as its own ⌘Tab entry (the active tab keeps the window thumbnail);
  selecting one focuses that exact tab. Toggleable in Settings › Switcher;
  macOS asks for Automation consent once per browser

## [2.0.2] - 2026-06-12

### Fixed
- **Permissions now survive updates.** Builds are signed with a stable
  self-signed identity (`Tools/setup-signing.sh` locally, shared certificate in
  CI), giving the bundle a constant designated requirement, so macOS keeps
  granted Accessibility and Screen Recording permissions across updates instead
  of dropping them. Falls back to ad-hoc signing on a fresh clone.

### Changed
- The installer **DMG is styled**: a window with the app icon, an arrow and the
  Applications folder for a proper drag-and-drop install.

### Docs
- README/switcher wording updated to ⌘Tab-only (the ⌥Tab option is gone).

## [2.0.1] - 2026-06-12

### Added
- **Automatic updates**: the app checks GitHub Releases (toggle in Settings ›
  General, plus a "Check for updates" menu item), and can download the new DMG
  and self-install with a single click

### Changed
- The window switcher now **always replaces ⌘Tab** (the ⌥Tab option was removed)
- Switcher selection follows a real most-recently-used app order, so a quick
  ⌘Tab→release toggles back to the previous app, matching the system switcher

### Added (switcher)
- Press **Q** while the switcher is open to quit the highlighted app

## [2.0.0] - 2026-06-12

The app was renamed from **Vorss** to **Vorssaint Utils** and prepared for
open source distribution.

### Added
- **System monitor**: CPU/GPU/battery temperatures (SMC), CPU/GPU usage and a
  traffic-light memory pressure indicator in the panel
- **Inverted mouse scrolling**: invert the mouse wheel only, trackpad untouched,
  live toggle (Accessibility)
- **Window switcher**: ⌥Tab (or ⌘Tab takeover) with real window thumbnails
  (ScreenCaptureKit), multi-window support, Spaces/Mission Control friendly
- **Onboarding** in 7 steps: language, Accessibility, Screen Recording,
  monitor tour, optional features, status verification, summary
- **Bilingual interface** (pt-BR / en-US) with live language switching
- New black hole identity: app icon and menu bar glyph with distinct
  active/inactive states and a click micro-interaction
- `--sensors` diagnostic flag (SMC dump for porting to new chips)
- `--uninstall` flag and `Tools/uninstall.sh` for a clean removal (login item,
  TCC permissions, preferences, sudoers rule, no dead entries left behind)
- CI build workflow and automated DMG releases

### Changed
- Renamed to **Vorssaint Utils** (`com.vorssaint.utils`); legacy `Vorss.app`
  is removed by `./build.sh --install`
- The System section now shows only temperatures, usage and memory pressure
- Settings reorganized into General / Energy / Mouse / Switcher / About
- Project restructured into App / Core / Services / UI / Support layers

### Removed
- Clipboard history (and its settings)
- "Sleep now" quick action

## [1.1] - 2026-06-11

Initial internal release as **Vorss**: keep-awake sessions with closed-lid
mode, battery protection, clipboard history, quick utilities and system info.
