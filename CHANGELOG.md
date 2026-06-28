# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [3.1.4] - 2026-06-27

### Summary
Vorssaint 3.1.4 makes Homebrew in Settings more stable and easier to browse, adds package updates from Homebrew, adds a large-icon ⌘Tab view with visible shortcuts, adds finer Window Layout placement options, improves App Switcher and Dock Preview navigation, expands Monitor menu bar metrics and makes Clipboard History faster to use from the keyboard.

### Added
- Window Layout can now place the active window into left, center and right
  thirds, left or right two-thirds layouts, and the next display.
- Dock Preview can now pin the current preview panel, show position when an app
  has multiple windows, and reliably minimize or restore windows directly from
  each preview card or its context menu. Multi-window previews can also move to
  the previous or next window from the preview header, and pinned previews can
  be dragged to a better position on screen. Multiple pinned previews can stay
  on screen at once while you keep using other apps. The selected preview stays
  visible while navigating long rows of windows, and pinned previews stay open
  until you close or unpin them from the header.
- App Switcher can now show a large icon row with one entry per app, with the
  selected app's window previews above it so a specific window can still be
  chosen directly.
- Monitor can now show disk usage and live disk activity in the menu bar, if
  enabled.

### Changed
- Homebrew now shows package counts in filters and sections, making long
  installed lists easier to scan.
- Homebrew now marks installed packages that have updates available, shows a
  compact update count, can refresh Homebrew itself and can update one package
  directly from the list, the context menu, the detail view or all available
  updates at once. Operation logs and fallback commands can also be copied.
- Clipboard History's quick window now targets the previous item first when no
  items are pinned, supports arrow-key selection, copy-without-paste, keyboard
  pin/delete actions, full-text tooltips and multi-word search.
- App Switcher now filters windows as you type while switching, and App Switcher
  plus Dock Preview show the app name under titles when it helps distinguish
  similar windows.
- The large-icon App Switcher now shows the current app-switching shortcut and
  the shortcut for moving between windows of the selected app.
- What's New and the update preview now show the short summary at the top of the
  release notes.
- Monitor's per-app CPU, GPU, memory and energy lists can now bring a listed app
  forward directly.

### Fixed
- Homebrew in Settings no longer destabilizes the Settings navigation when it
  loads many installed packages.

## [3.1.3] - 2026-06-25

### Summary
Vorssaint 3.1.3 makes Cleaning Mode, Keep Awake, Monitor, Clipboard History and the Window Switcher more reliable, improves readability in the panel and adds optional pointer movement for Keep Awake sessions.

### Added
- Keep Awake can now move the pointer slightly at a chosen interval during
  active sessions, if enabled.

### Fixed
- Cleaning Mode now blocks brightness, media, volume and lock keys while the
  keyboard is locked.
- Keep Awake option text no longer gets cut off in the panel or Energy settings.
- Keep Awake closed-lid mode now handles failed password-free setup more clearly
  and can fall back to the macOS password prompt when needed.
- Battery health now follows the same maximum capacity value shown by macOS when
  that value is available.
- Monitor text in the panel now has better contrast, with steadier alignment for
  power and battery rows.
- Monitor Alerts controls now live in Settings instead of appearing both in
  Settings and the main panel.
- Clipboard History's shortcut toggle can now be turned off even when Clipboard
  History itself is currently disabled.
- The Network menu bar metric is now better centered and easier to read.
- The Window Switcher now focuses only the selected browser profile window,
  including when that selected window is minimized afterward.

## [3.1.2] - 2026-06-24

### Summary
Vorssaint 3.1.2 improves GIF handling in Media and Shelf, adds more Keep Awake control in the panel, lets Monitor metrics use separate menu bar items with focused detail views and expands the Volume Mixer with speaker protection and shortcut-based output switching.

### Added
- Keep Awake can now choose the active menu bar icon color directly from the
  panel, including an option to keep the normal adaptive icon with no active
  color.
- Keep Awake can now start automatically when Vorssaint opens, if enabled from
  the panel or Energy settings.
- Monitor metrics can now use separate menu bar items, so each active metric can
  be positioned independently on crowded or notched menu bars. Clicking a metric
  opens a focused detail view for CPU, GPU, RAM, network, battery or power.
- Volume Mixer can now lower speaker volume automatically when wired or
  Bluetooth headphones disconnect, if enabled.
- Volume Mixer can now cycle through selected system outputs with a global
  shortcut, if enabled.

### Changed
- Monitor and Shelf now use lighter thumbnails and temporary caches, reducing
  memory use while browsing metrics and dragging items.

### Fixed
- GIFs created by Media now stay visible in Finder, including outputs from
  source files whose names start with a dot.
- Panel sections and folded controls now open instantly without extra transition
  animations.
- Folded panel setup sections now open when clicking either the arrow or the
  section title.
- The System panel now shows the separate menu bar items control only when at
  least one menu bar metric is active.
- Shelf now preserves animated GIF data when macOS provides a GIF file or GIF
  data, instead of flattening it into a still image.

## [3.1.1] - 2026-06-23

### Summary
Vorssaint 3.1.1 makes Homebrew package loading more reliable, keeps Clipboard History from disrupting the app you are pasting into and adds direct window closing in App Switcher.

### Added
- App Switcher cards now show a close button on hover, so you can close a
  specific window without leaving the switcher.

### Fixed
- Clipboard History no longer activates Vorssaint when opening the quick history
  window, so paste actions keep their target in apps like Excel.
- Closing a window from Dock Preview or App Switcher now triggers Quit on Close
  when that was the app's last window.
- Homebrew now keeps loading installed packages when Homebrew prints warnings
  before or after its package list.

## [3.1.0] - 2026-06-23

### Summary
Vorssaint 3.1.0 adds three optional tools: Clipboard History for saving and reusing copied text locally, Window Layout for arranging the active window with shortcuts, and Monitor Alerts for notifying you when selected system limits need attention. It also makes Settings easier to browse and improves menu bar metric readability on light and dark wallpapers.

### Added
- Clipboard History, with local text history, pinned items, search, manual order,
  clear controls, sensitive-text skip and quick paste shortcuts.
- Window Layout, with actions for halves, corners, center, maximize, restore and
  optional global shortcuts.
- Monitor Alerts, with optional notifications for high CPU, CPU temperature,
  memory pressure, disk space and battery, configurable from Settings and the
  System panel.

### Changed
- Settings are now grouped into clearer categories.
- Homebrew and Dock Preview no longer show beta labels in the app.
- Clipboard and Window Layout are available in the Utilities panel and can be
  hidden or reordered.
- Menu bar metric text now adapts better to light and dark wallpapers.
- What's New no longer opens again after installing an update, because the
  update flow already shows the changelog before download.

## [3.0.10] - 2026-06-21

### Summary
- This update adds disk monitoring to the System Monitor, with per-disk storage,
  activity, SMART details when available and safe eject controls for external
  drives.
- App Switcher is steadier with multiple windows and fullscreen apps, including
  games.
- App Switcher now has a Finder visibility option for users who prefer not to
  show Finder when it has no open windows.

### Added
- System Monitor now has a Disks section with storage usage, live read/write
  activity, session totals, SMART details when macOS exposes them, per-disk
  selection and Finder-style decimal storage values.
- Disks can now be selected individually, with per-disk details, an Eject action,
  an Eject all action for external drives and safety guards that block eject
  actions for the internal system disk.
- App Switcher can now hide Finder when it has no open windows, while keeping
  Finder windows visible when they exist.

### Fixed
- App Switcher now returns to the exact window you last used in apps with
  multiple windows, instead of letting the app choose a different window.
- App Switcher now switches more reliably when entering or leaving fullscreen
  apps and games.

## [3.0.9] - 2026-06-20

### Summary
- This update focuses on making Vorssaint feel lighter, steadier and more
  reliable during everyday use.
- Menu bar readings for CPU, GPU, RAM and temperatures stay visible through
  brief refresh gaps, while the monitor does less background work when the panel
  is closed or only a few metrics are visible.
- The Volume Mixer is easier to control with one output selection for the system
  and apps, while per-app volume, mute and boost settings stay intact.
- Media tools are more responsive with larger videos and more reliable when
  reading video details or creating GIFs.

### Changed
- The Volume Mixer can now send the whole system and apps to one audio output at
  once.
- The system monitor and menu bar now do less background work, especially when
  the panel is closed or only a few metrics are visible.
- Live monitor updates are smoother and avoid unnecessary redraws while values
  are refreshing.
- Media tools are more responsive with large videos and handle video details and
  GIF creation more reliably.

### Fixed
- GPU temperature, RAM and CPU readings in the menu bar now stay visible through
  quick moments when a value is unavailable instead of disappearing and coming
  back.
- The Network panel now starts measuring correctly when opened directly on
  Network.
- GPU usage in the menu bar now avoids brief spikes when opening the panel,
  while still showing real sustained activity.

## [3.0.8] - 2026-06-20

### Added
- CPU, GPU and battery temperatures can now be pinned to the menu bar as
  metrics, using the selected Celsius or Fahrenheit setting.
- Menu bar temperatures now combine with matching usage or battery charge by
  default, with a setting to split them into separate CPU°C, GPU°C and BAT°C
  blocks.

![Menu bar temperature metrics](https://raw.githubusercontent.com/vorssaint/vorssaint-utils/main/Resources/Images/menu-bar-temperature-metrics.png)

## [3.0.7] - 2026-06-20

### Added
- Utilities now includes Media for local video compression, GIF creation, image
  compression and text extraction from images, with drag and drop, simple
  controls and local-only processing.
- Dock Preview cards now include a red close button on the left for closing the
  real window directly from its preview, and the panel stays correctly sized as
  windows are closed.
- Pending Finder cut operations now include a close button to cancel the cut and
  dismiss the floating HUD.

### Changed
- Menu bar metrics now use a cleaner compact layout with clearer CPU, GPU, RAM,
  battery, power and network readings, custom ordering, persisted choices and
  steadier widths.
- The menu panel uses a subtler glass surface so text and controls stay readable
  across different backgrounds.

## [3.0.6] - 2026-06-20

### Added
- Global shortcuts for Keep Awake, Shelf and App Switcher can now be changed or
  turned off.

### Fixed
- Closed Vorssaint Settings windows no longer linger in App Switcher.
- Minimized windows now stay open and remain available in App Switcher and Dock
  Preview.

## [3.0.5] - 2026-06-19

### Added
- When installing an update, a preview of the new version's changelog is shown
  first, so you can decide whether the update is worth it before downloading.
- After updating, a What's New window summarizes everything since your previous
  version. You can turn it off in Settings > What's New, or with "Don't show
  again".
- The app switcher and Dock previews now have a size option (Normal, Large or
  Extra large) so windows stay easy to identify on large displays.

### Fixed
- Closed-lid mode now reliably brings up the administrator password prompt when
  it is being set up on a Mac that has not granted permission yet, and no longer
  becomes unstable when the request is retried.
- "Clear all permissions" could freeze the Mac's input; it now stops the app's
  event taps before resetting permissions, and feature event taps no longer
  block when Accessibility is revoked.
- Cut & paste for files in Finder (⌘X) shows its on-screen confirmation again:
  Finder Automation is now requested in-process and re-requested if it was lost
  after an update, instead of failing silently.
- When closed-lid mode cannot be turned on, the message now clearly says to
  switch it off and on again to try, instead of a confusing note that pointed at
  your password even when no password was involved.

## [3.0.4] - 2026-06-18

### Added
- Utilities now includes a Homebrew manager for searching, installing and
  uninstalling formulae and casks from the menu panel, with popularity-sorted
  search results and a guided setup flow when Homebrew is not installed.
- The Volume Mixer can now route each app to the system default output or a
  specific speaker, display or audio device.
- The Volume Mixer now includes a global microphone picker that remembers a
  preferred input and restores it when the device reconnects.
- Dock Preview can now show window previews when hovering over open apps in the
  Dock, with a temporary peek before selecting a window.
- This update includes a one-time Dock Preview intro with a short demo and beta
  note.

### Changed
- Panel edit mode now has a clearer OK button, reset control and drag handles
  for reordering items.
- Utilities now defaults to Homebrew first, followed by Uninstaller, Clean URL
  and Cleaning Mode.

### Fixed
- App Switcher now keeps fullscreen windows available when they are on another
  Space.
- App Switcher thumbnails now try a secondary ScreenCaptureKit match for native
  fullscreen windows on another Space.
- Green-button maximization now avoids falling through to native fullscreen when
  the custom resize path cannot run.
- Quit on close now ignores stale AX windows after a real close-button request
  when WindowServer confirms there is no visible app window left.
- Quit on close now follows explicit close-button clicks in apps that do not
  always emit standard window-close callbacks.
- Settings now opens beside the menu panel instead of starting underneath it.

## [3.0.3] - 2026-06-18

### Changed
- The Shelf is easier to grab and move from the header and empty space, while
  still accepting dropped items in the empty area.
- Shelf close and clear controls now have larger hit areas, clearer spacing and
  a danger hover state for clearing items.
- The menu panel footer now uses full button hit areas and handles longer
  translations without overlapping.
- Settings now uses a shorter What's New sidebar label, and update controls live
  in About with the other app details.

### Fixed
- The custom green-button maximize option now animates window resizing instead
  of jumping instantly.
- Window-control click monitoring now avoids slow accessibility checks unless a
  click is actually on a window control, reducing stalls in other apps.

## [3.0.2] - 2026-06-18

### Fixed
- Opening Clean URL or Uninstaller from the menu panel is now more stable on
  macOS 15.

## [3.0.1] - 2026-06-18

### Fixed
- Quit on close now handles apps that keep delayed window records after the last
  standard window is closed, including Spotify and Discord.
- The app switcher no longer shows recently closed Ghostty terminal windows.
- Finder can now be selected from the app switcher even when no Finder window is
  open.
- Finder stays locked in Quit on close exceptions and cannot be quit from the app
  switcher.

## [3.0.0] - 2026-06-18

### Added
- Clean URL is now available in Utilities and Settings, with optional automatic
  cleaning for copied links.
- Panel sections can now be customized inline from the panel: the edit control
  keeps the real panel visible, shows hidden items as muted rows and lets them
  be restored from the same place.
- Utilities now includes an optional green-button window maximizer that keeps
  windows in the current Space and restores the previous size on the next click.
- The menu panel now has a Controls section next to Utilities for quickly
  turning feature-style options on or off.

### Changed
- Menu bar metrics now use a more compact layout with short labels, tighter
  values, a steadier reserved width and an automatic two-line stack when several
  metrics are enabled.
- Menu bar metric labels can now be switched between compact and classic styles
  from Monitor settings.
- Updates no longer open a What's New window for existing users. Release notes
  are available in Settings.
- The Buy Me a Coffee shortcut was removed from the menu panel and first-run
  introduction. It remains in Settings > Support.
- Monitor graphs now include a zero baseline so current levels are easier to
  read.

### Fixed
- The Uninstaller app chooser now stays inside Vorssaint instead of opening the
  system file picker, avoiding unexpected language changes.

## [2.17.3] - 2026-06-17

### Website
- Official site: [vorssaint.com](https://vorssaint.com).

### Added
- Every update now opens a What's New window with the latest release notes and a
  discreet vorssaint.com link.
- The Uninstaller is now available directly in the menu panel's Utilities
  section, with drag-and-drop and Choose app support.
- The menu panel header now includes a Buy Me a Coffee shortcut.

### Changed
- Settings and What's New windows can now be focused from the window switcher.
- The menu bar icon no longer bounces when opening the panel.
- The README now uses focused screenshots and GIFs for each feature.

### Fixed
- Quit on close now detects the last-window close more reliably for apps like
  Safari and WhatsApp.
- The post-update What's New window now opens centered on screen.

## [2.17.2] - 2026-06-17

### Fixed
- Shelf and Cut & Paste HUDs no longer use the native rectangular panel shadow,
  avoiding extra outlines on some macOS display/window configurations.

## [2.17.1] - 2026-06-17

### Fixed
- The release build now uses the macOS 26 runner so the Volume Mixer slider uses
  the same Liquid Glass effect as the Developer build on macOS 26 and later.

## [2.17.0] - 2026-06-17

### Added
- The Battery section now shows apps with significant current energy use.
- The Volume Mixer uses a compact Liquid Glass slider on macOS 26 and later,
  while older macOS versions keep the standard slider.

### Changed
- The Keep Awake status under the app name is now a clearer state indicator.
- Panel metric colors now adapt between Light Mode and Dark Mode for better
  contrast.

### Fixed
- Update notices in section navigation mode now count toward the panel height
  instead of cutting off the content.
- The Settings window now opens in a normal centered position after relaunch,
  instead of appearing under the menu panel.
- Volume Mixer sliders now track system accent color changes more reliably.
- The menu panel no longer opens with its header clipped during first-launch
  layout timing.

## [2.16.1] - 2026-06-16

### Fixed
- Memory usage now matches Activity Monitor's Memory Used total more closely.
- Network readings now ignore another local virtual interface so totals stay focused on real network traffic.

## [2.16.0] - 2026-06-16

### Added
- The menu panel now has an optional section navigation mode, with section icons
  placed below the app header and a centered List/Sections switch in the footer.
- The section navigation mode is introduced during the update flow and is enabled
  by default so existing users can try it right away.
- Shelf drops can now be kept as batches, and loose items can be added into an
  existing stack by dropping them onto it.
- Battery can now be shown as an optional menu bar metric.
- A Fan Control beta entry can be enabled in Monitor settings. Manual control
  remains disabled until Mac models are validated.

### Changed
- Cleaning Mode now lives in a dedicated Utilities section inside the panel.
- The menu panel now fades and slides when opening or closing.
- The section navigation panel now grows only as much as the active section needs,
  instead of reserving a large empty area for shorter sections.

### Fixed
- The Shelf stays visible while it contains files, instead of auto-hiding while
  the user is still collecting items.
- The app switcher now handles apps on other Spaces more reliably when focusing a
  selected window.

## [2.15.2] - 2026-06-16

### Fixed
- The menu panel now resizes smoothly as sections collapse and expand, without
  stale empty space or unnecessary scrolling.
- The Settings window now stays open when clicking outside it, and only closes
  when the user closes it intentionally.
- Clicking the Settings window now hides the menu panel only when the panel is
  overlapping it, while still allowing Settings and the panel to stay open side
  by side for live layout changes.
- App updates no longer open the language chooser or Buy Me a Coffee support
  prompt automatically.

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
