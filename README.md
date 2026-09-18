<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/readme/logo-dark.svg">
    <img src="docs/assets/readme/logo.svg" width="220" alt="Vorssaint logo">
  </picture>
</p>

<h1 align="center">Vorssaint</h1>

<p align="center">
  One menu bar icon doing the job of a dozen paid Mac apps.<br>
  Free, open source, and everything runs on your Mac.
</p>

<p align="center">
  <a href="https://vorssaint.com">Website</a> ·
  <a href="#install">Install</a> ·
  <a href="#everything-it-does">Features</a> ·
  <a href="#private-by-default">Privacy</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="mailto:hello@vorssaint.com">Contact</a> ·
  <a href="https://buymeacoffee.com/vorssaint">Buy Me a Coffee</a>
</p>

<p align="center">
  <a href="https://github.com/vorssaint/vorssaint-utils/releases"><img src="https://img.shields.io/github/v/release/vorssaint/vorssaint-utils?label=release&color=4c8dff" alt="Latest release"></a>
  <a href="https://github.com/vorssaint/vorssaint-utils/releases"><img src="https://img.shields.io/github/downloads/vorssaint/vorssaint-utils/total?color=4c8dff" alt="Downloads"></a>
  <a href="https://github.com/vorssaint/vorssaint-utils/actions/workflows/ci.yml"><img src="https://github.com/vorssaint/vorssaint-utils/actions/workflows/ci.yml/badge.svg?branch=main&event=push" alt="CI status"></a>
  <a href="#what-you-need"><img src="https://img.shields.io/badge/macOS-14%2B%20Apple%20Silicon-black" alt="macOS 14 and newer, Apple Silicon"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue" alt="License GPL 3.0 or later"></a>
</p>

<p align="center">
  <a href="https://discord.gg/M6BwWH4BJp">
    <img src="docs/assets/readme/discord-symbol.svg" width="72" alt="Discord">
  </a>
</p>

<p align="center">
  For anything private, email
  <a href="mailto:hello@vorssaint.com"><strong>hello@vorssaint.com</strong></a>.
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/53716?utm_source=repository-badge&amp;utm_medium=badge&amp;utm_campaign=badge-repository-53716" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/repositories/53716" alt="vorssaint/vorssaint-utils | Trendshift" width="250" height="55"></a>
  <a href="https://trendshift.io/repositories/53716?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-53716" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/53716/weekly?language=Swift" alt="vorssaint/vorssaint-utils | Trendshift weekly ranking" width="250" height="55"></a>
</p>

<p align="center">
  <img src="docs/assets/readme/panel-mixer.png" width="196" alt="Volume mixer with per app sliders, one app boosted past 100 percent">
  <img src="docs/assets/readme/panel-system.png" width="196" alt="System tab with temperatures, usage graphs and memory pressure">
  <img src="docs/assets/readme/panel-controls.png" width="196" alt="Window controls with the app switcher and Dock features">
  <img src="docs/assets/readme/panel-utilities.png" width="196" alt="Utilities with cleaner, Homebrew, media tools and clipboard">
</p>

Per app volume, a real system monitor, a better app switcher, window snapping, Dock previews, clipboard history, text snippets, a file shelf, an uninstaller. The utilities Mac users usually buy one by one, together behind a single menu bar icon, with no account, no telemetry and no subscription.

## Install only what you use

Nobody needs all of it, and Vorssaint is built around that. The Features page installs and uninstalls whole features: what you uninstall disappears from the entire app and stops loading, so it spends no CPU, memory or energy. Nothing is deleted, and installing again brings your old settings back.

First setup offers three one click bundles, Essentials, Windows, and Battery and quiet, plus a visual picker for choosing individual features. Only the permissions those choices need are requested next, and everything can be changed later in Settings. Every feature also wears an honest energy badge saying what it keeps alive while on.

<p align="center">
  <img src="docs/assets/readme/features-hub.png" width="720" alt="The Features hub in Settings, installing and uninstalling whole features">
</p>

The rest bends the same way: panel sections reorder and hide, the compact layout trades sections for tabs, settings export to a file and import on a new Mac, the app can stay light or dark apart from the Mac, and the whole app speaks more than a dozen languages.

## Everything it does

### Sound

- **Volume mixer.** Adjust the Mac's overall volume or slide any single app up or down, enter an exact percentage, and push a quiet one past 100 percent when a video is just too low. Send system sounds through another output, or hide the apps you never adjust to keep the list short. Pin favorites from each row’s menu and hold Command while dragging an app to reorder it; positions survive closing apps and travel with settings backups. No audio driver, no setup.
- **Per app output.** Send your music to the speakers and a call to your headset at the same time.
- **Output switcher.** Cycle between chosen outputs with one shortcut, and drop the volume automatically when headphones disconnect.
- **Microphone tools.** Pin your favorite input so the Mac stops guessing, adjust its input volume in the mixer with an exact percentage on supported devices, and mute every microphone at once with a click or shortcut, whichever one an app is using. Input volume stays locked while microphone mute is active.
- **Music app blocker.** Stops the Music app from bursting in when headphones connect. You can still open it yourself.

### Know what your Mac is doing

- **System monitor.** CPU, GPU, memory, swap use and temperatures with history graphs, including a choice between total memory in use and memory held by apps, plus battery charge, temperature, health, time remaining, cycle count and power draw together in Power, an optional Fan Control beta with continuous manual speeds, custom temperature curves and live RPM, the apps burning energy right now and a shortcut to the Mac's full process inspector.
- **Menu bar readouts.** Keep the readings you care about in the bar itself, with values or compact usage bars, including optional battery time remaining and fan speed, combined or as separate items.
- **Network.** Live rates, session totals and a built in speed test.
- **Alerts.** Optional notifications for sustained CPU load, high CPU or battery temperature, memory pressure, low disk space and low battery.

### Windows and the Dock

- **App switcher.** A richer take on pressing ⌘Tab, with adjustable live window thumbnails, minimized windows included, and more than one window per app. Simple mode keeps every window and its title without previews or screen capture, with optional grouping to one entry per app. Optionally press S to keep search open after releasing the switcher shortcut, or hide the shortcut hints below the large icon row. Press the window shortcut directly to move between windows of the app in front. Choose whether it opens on the screen under the pointer, the one with the menu bar or the one with the active window. Optionally show only windows on the display under the pointer; the switcher stays closed when that display has no windows. Set per-app rules to include windowless apps, keep them window-only or hide them. Choose apps where Vorssaint pauses both switcher and Dock thumbnail capture while they are in front. Minimal previews hide window titles, controls and decoration while keeping selection visible. Middle-click a preview to close that window.
- **Window layout.** Snap the active window to halves, including a centered half-width placement, thirds, sixths, corners or center with configurable gaps between windows and screen edges, maximize it with or without a margin, or move it to the next or previous display, each with its own optional shortcut. Using the left or right shortcut again carries the window to the display on that side, landing on the half it came in through. Restore steps back through recent placements. Turn on edge snapping in Window Layout, choose its active edges and corners on the visual screen map, then drag a title bar there for a live preview. Hold chosen modifiers and drag anywhere to move it, then add Shift to resize. A mouse can also resize with the right button.
- **Dock Preview.** Hover a Dock icon to see adjustable window thumbnails with clear titles from all desktops by default. Click one to switch to its desktop or drag it to move and snap the window. Turn on “Show only the current desktop” to limit previews. Middle-click closes only the pointed window, including in pinned previews. Optional minimal previews hide titles, controls and decoration.
- **Dock clicks.** Click the Dock icon of the active app to minimize its windows, hide the app, or cycle through its windows.
- **Maximize windows.** The green button fills the screen without creating another Space, and puts the window back on the next click.
- **Quit on close.** Apps you choose quit when their last window closes.
- **Quit and close protection.** Protect ⌘Q and ⌘W with a hold, double press or extra modifier, independently and only for the apps you choose.

<p align="center">
  <img src="docs/assets/readme/window-switcher.gif" width="540" alt="The window switcher showing live thumbnails of open windows">
</p>

### Keyboard and mouse

- **Text snippets.** Type a short trigger anywhere and it becomes your text, expanded instantly or after a space, with clipboard variables plus date and time in any format you like. A searchable quick menu, organized into folders, types any snippet right at your cursor.
- **Smooth scrolling.** Gives a mouse wheel a fluid glide with adjustable speed and response.
- **Pointer acceleration.** Optionally disable acceleration for connected mice while preserving the previous system setting for restoration.
- **Focus follows mouse.** Install it from Features to bring the window under the
  pointer to the front after an adjustable pause. It waits while you drag or hold a
  modifier key.
- **Scroll direction.** Invert vertical and horizontal wheel movement separately without
  touching the trackpad's natural scrolling.
- **Side buttons.** The mouse Back and Forward buttons start meaning it, in Finder, browsers and compatible apps.
- **Mouse button shortcuts.** Give any extra button or side-wheel direction a key combination of your choice, or hold a button and drag to switch Spaces, open Mission Control or show the current app's windows.
- **Middle click.** A three finger press becomes a real middle click.
- **Apps to leave alone.** Every feature above can name apps from anywhere on your Mac that drive themselves with the mouse, like 3D and design tools, and it steps aside in those.
- **Extra click filter.** Ignore rapid accidental extra clicks from worn primary, secondary and middle mouse buttons without delaying normal clicks.
- **Key debounce.** Filters the double letters a worn keyboard invents.
- **Super key.** Hold Caps Lock or a right-side modifier key and it counts as the modifier combination you choose, so one key can drive your shortcuts. A tap on its own can switch input sources, switch capitals, press Escape, or do nothing. Choose apps that pause Super key while they are open, even in the background, so the selected key works normally until the last one quits. Keep the selected key at its default action in System Settings › Keyboard › Modifier Keys.
- **Keyboard shortcuts.** Edit every installed feature's global shortcut from one categorized page, see what is active and use the shorter Super key combination when available. On supported Macs, enable optional keyboard backlight shortcuts under Mouse and keyboard › Keyboard light to adjust it one step at a time.

### Clipboard, files and links

- **Clipboard history.** Local history of text, images and files with pinned favorites, search, quick paste shortcuts and an on-demand preview where text can be selected or edited.
- **Auto clear clipboard.** Empty the system clipboard a set time after you copy, and when the Mac sleeps, the display sleeps or the screen locks. Each trigger is optional, works with history off, and leaves your saved items untouched.
- **Paste as plain text.** One shortcut pastes without fonts, colors or links, and the original stays on the clipboard.
- **Shelf.** Park files, text and links near your cursor mid drag, or open it from a screen edge, then drop them where they belong later. Attachments dragged from other apps arrive as complete files with their original names. Share the files you parked anywhere the Mac can send them. Choose whether its close button clears every item or keeps them for later.
- **Finder shortcuts.** ⌘X and ⌘V move files, an optional F2 shortcut renames the selection, and copied images can become PNG files with ⌘V.
- **Clean URL.** Strips tracking parameters and extra names you choose from copied links, on demand or automatically.
- **Disk image installer.** When a mounted disk image contains one app, install it into Applications with one click and eject the image. Choose whether to move its download to Trash and show the installed app in Finder.

### Everyday tools

- **Dynamic Island.** An optional black home for music, controls, clipboard, captures, files and system details, including Macs without a camera cutout, where it recreates the same black cutout attached to the top edge and scaled to fit the menu bar. Spacious sizing is the default, with compact and custom options. Design floating shortcuts directly in the interactive preview: add, rename, remove and drag up to three buttons onto each side or below the island. The starting layout places Explore above Timer on the left, Settings above Volume mixer on the right, and Now Playing below. Buttons can open sections or run everyday controls; unavailable actions stay out of the chooser and the island, and saved layouts are preserved. Visual pages organize layout, content, activity and opening behavior. Hover activation defaults to 0.25 seconds and can be adjusted from 0.1 to 1 second under Behavior. Search the in-place section gallery by name or navigate with arrows and Return. Command-K opens the gallery; every section has a stable Option-Command shortcut shown on its card, and Control-Tab cycles through all available sections. Arrange sections and hide individual controls in settings. Controls put playback first, followed by volume and brightness, with the mixer, Keep Awake, timer and calendar as default shortcuts. Capture, microphone and app-specific shortcuts remain customizable. The empty state stays quiet, and compact indicators give menu bar items priority. Playing music is the default resting content, with nothing and battery also available. On screens without a camera cutout, the compact music strip shows the track title and, when there is room, the artist. Hover expands the island by default and responds sooner when the pointer enters or leaves; a preview or click-only opening remains available. An optional hidden mode reveals the island on hover and hides it again on exit, including resting indicators and passive alerts. Available Vorssaint updates have an Update button in the open island's header; the existing preview shows the release notes before downloading, and the resting island stays unchanged. Choose whether reopening restores the last page or opens a specific section. Click the top to open or close; after closing, hover waits until the pointer leaves and returns. Menu bar buttons also toggle their destination. Gestures start enabled and scroll down to open, scroll up over the top row to close, and swipe across music to change one track at a time; lists and sliders keep their scrolling. Keyboard navigation remains available, and trackpad feedback starts enabled. Volume, brightness and notification feedback expands horizontally beside the real or simulated camera; level indicators omit redundant titles. Calendar pairs a browsable month with day-grouped appointments, calendar colors and an ongoing event highlight. Select a date to see its schedule or return to the next seven days. New visible system notifications appear briefly in Dynamic Island and can remain in a session inbox that clears on lock or disable. Click a banner to open its original notification; if it has already disappeared, the identified source app can still be opened. An optional setting dismisses the original system banner after the island shows it; the original may still appear briefly. Music apps take priority over browser videos, keeping pause and resume tied to the selected music app. Music offers a seekable timeline when supported, synchronized lyrics with local file import and a per-track timing adjustment, and the player's real upcoming queue when exposed. Online lyric lookup is a separate opt-in that sends the track title, artist, album and duration, never audio. Timers use an orange minute ruler with click, drag, scroll and keyboard adjustment, a large countdown and circular pause and cancel controls. The island’s optional haptic feedback gives a gentle tap as the selected minute changes. Remaining minutes sit close beside the camera, switching to seconds in the final minute. A stopwatch on the same page counts up with pause and cancel, showing minutes and seconds beside the camera until an hour passes. Pomodoro remembers focus and break durations, the long-break interval and a session goal, shows cycle progress and finishes after the last focus session. Timers and focus sessions stay accurate through sleep, offer explicit breaks and play a repeating sound for up to five minutes or until dismissed, with sound preferences kept in settings. Active downloads and the timer can share the compact strip. The camera mirror can open inside Dynamic Island from Tools or its shortcut and stops when closed or hidden. Accessory connection and low-battery alerts reuse the existing readings, and an optional keyboard light indicator joins volume and screen brightness feedback. Each new drag of compatible images or one video offers a choice between the shelf and media optimization, including when media is already open. Media follows its content height, and file actions do not pin the island automatically. File actions create separate ZIP archives or reuse the media tools for conversion and compression, preserving originals and returning results to the shelf. Downloads follow a folder you choose, showing real percentages when a total is available and an indeterminate state otherwise. Clipboard search stays visible with a pinned filter. Available app panels, tools, clipboard, capture controls and shelf open in the island by default, with independent options to use separate windows; capture controls open without initially dimming the desktop. The base stays black with optional Liquid Glass controls. It appears in captures by default, with an option to hide it.
- **Command Bar.** One shortcut opens a field over whatever you are doing. Drag its mark to place it anywhere on a screen, or double-click the mark to put it back. Type a few letters to run any Vorssaint action, open an app, switch to a window, insert a snippet, paste from your clipboard history at the cursor, and it reaches into the app you are using to run any command from its menus, showing that command's own shortcut. It answers sums, conversions, dates and questions about your Mac as you type, opens a web address you enter, and acts on the text you already have selected. Saved shortcuts can also run a local script and show its output as you type. Name a few folders and it finds files in them by name too, through the Mac's own search, without building its own index or looking beyond the folders you choose. Apps also answer to alternate names known by macOS, and the Mac's own Settings panes are one row away. Manage app shortcuts from Keyboard shortcuts or Command Bar settings with a searchable app list, editable aliases, pinned favorites and shortcut recording in each row. App shortcuts also work before the bar first opens after launch. Press ⌘K on an app to quit, restart, force quit or send it to the Uninstaller, and on any row to name it, pin it, hide it or give it a shortcut of its own; ⌘Return shows an app, a folder or a file where it lives. Bug reports and feature ideas can also be sent from here, with every technical detail shown before you choose whether to include it. Start with a colon or open the Emoji category to find emoji by name and familiar English terms. Choose a default skin tone in Command Bar settings, or use an emoji’s actions to insert another tone just once. It tolerates short typos and remembers search choices across launches without saving the text you type. Clear all learned choices in Settings or forget one result from its actions.
- **Quick panel.** ⌃⌘V opens a small floating palette with your favorite tools one key away.
- **Quick toggles.** One-click system actions in their own panel tab: switch light and dark mode, toggle the keyboard light, empty the Trash, eject every disk except drives you exclude in Settings, show hidden files, hide desktop icons, lock the screen and more.
- **Radial menu.** Hold a shortcut, or any extra mouse button, and a wheel of your favorite actions opens around the pointer: apps, files, links, key combos, media controls, quick toggles and Vorssaint tools, with submenus for more. Point and release to run one. Custom profiles let you switch between different wheel layouts, color themes, shortcuts and mouse triggers, and website links can fetch their actual icons on demand.
- **Screen capture.** Screenshots, screen recordings, copying text from the screen and picking a color share one selector, and each tool's own shortcut opens it already on that tool, ready to switch. Each tool can hide the mode menu when opened through its keyboard shortcut, while capture buttons keep it visible. A pixel-grid magnifier shows the exact point and color, moves one pixel at a time with the arrow keys and copies the color without ending the capture. Its zoom can start at a chosen level or remember the last one, with fast or step-by-step wheel control and ⌥ to switch temporarily. Only installed tools appear, recording sound and microphone choices stay beside the mode selector, and every related setting lives on one page with a separate mode for each tool.
- **Screenshot.** Capture an area, a window or the whole screen on a frozen picture, or join a long page or document by scrolling it yourself, then pressing Enter or Done. It can include ordinary Vorssaint windows without showing its own capture controls. Its quick preview can stay near the shot or in any screen corner, can take the keyboard the moment it appears if you prefer, can be dragged out as a PNG, and can copy, save, delete or open the editor, which adds stickers, annotations, precise crop, redaction, adjustable backgrounds, a watermark of your own and pinned captures. Recent screenshots and recordings stay one click away in their panel cards and editors, and are searchable from the Command Bar. Copied captures paste as PNG files, including in tools that expect a file path. The preview and editor can share a capture for 1, 6 or 24 hours and delete it early from the app. A QR code in the shot shows its content to copy or open, from the preview and the editor. Editor tool shortcuts can be recorded in Settings or the editor’s tool menu. Digits 1–9 reorder tools; other keys stay attached to their tools. Delete clears a shortcut, the row reset restores its position shortcut, and Reset restores all defaults. Optional timer, save folder and 1x export included. Captures can copy themselves to the clipboard, run your favorite action right after the shot, save into dated subfolders with a file name pattern of your own, and use separate shortcuts for a whole-screen shot, the latest capture or any copied image.
- **Screen recording.** Record an area, a window or the whole screen with optional system sound and microphone audio on separate tracks. The picture, system sound and voice stay aligned when you pause and resume. A dimmed guide keeps the chosen area visible while recording, and floating controls can pause, resume or stop it. Choose either source while selecting, then adjust its volume or remove it in the editor. Vorssaint windows can be selected like any other while recording controls stay out. The editor trims, cuts, smooths the pointer, adds optional automatic zooms that can stay with typing after a click, adds text and pictures with adjustable size, position and transparency, blurs any area for as long as you choose so private details stay hidden even inside zooms, adds adjustable backgrounds, and saves reusable presets. Copy the finished video directly, copy and delete in one step, export video and GIF files to the folder you choose, or compress it locally and share a temporary 1-hour or 6-hour link under 100 MB.
- **Camera preview.** A floating mirror to check how you look before joining a call, one click or shortcut away. Pick the camera when several are connected; it closes as soon as you click away.
- **Scratchpad.** Floating pads in named tabs for short-lived text: meeting notes, numbers, fragments on their way somewhere else. They save as you type, preview Markdown formatting on demand, step aside when you click elsewhere (or stay floating, your call), and can copy everything, export to a file or clear themselves after a quiet period. While a pad is focused, ⌘T creates a tab and ⌘W closes the selected tab, asking before removing text; on the last tab, ⌘W hides the window and keeps the note.
- **Copy text from screen.** Select any area and its text is recognized offline, straight onto the clipboard, optionally joining line breaks into one paragraph. When the area holds a QR code, its content is shown so you can copy it or open the link.
- **Color picker.** Grab any pixel from the shared screen selector as HEX, RGB, HSL or SwiftUI code, with the system loupe kept as a permission-free fallback.
- **App updates.** One list of the apps on your Mac that have a newer version. It checks package-managed and store apps, reads supported update feeds published by app developers, and matches other apps by identity or exact name in a public catalog. Managed updates install together; other rows open the original app so its own updater stays in control. Each source can be switched off, and optional background checks tell you when something is waiting.
- **Cleaner.** Sweeps app leftovers, caches and logs, by hand or on a schedule.
- **Messaging downloads.** The Cleaner can also tidy the media a messaging app saves into Downloads, confirmed by macOS metadata and only ever moved to the Trash, with a review list, retention rules and an optional organizer that files new ones into a folder of your choice.
- **Uninstaller.** Drop an app in and take its caches, preferences, helpers, plugins, containers and other leftovers to the Trash with it. Related finds start unchecked so you can review them first.
- **Media tools.** Compress videos or open any one in the editor to trim, cut and crop it, convert images one at a time or in batches with resizing, watermarks and reusable profiles, make GIFs and extract text, all locally. Image batches can use a separate output subfolder, and a menu adds naming placeholders.
- **Homebrew manager.** Search, install and remove formulae and casks without opening a terminal.
- **Cleaning Mode.** Locks the keyboard while you clean and either blacks out every display or leaves the screen visible with a discreet corner indicator.

### Energy and display

- **Keep awake.** Keep the Mac up for a timer, until you say stop or automatically with an external display, a power connection or selected apps running in the background, pause the session while the Mac is locked, keep going with the lid closed, let displays sleep without stopping local work, choose the active menu bar icon and color, see the remaining time beside it, and optionally toggle it with a right click.
- **Displays.** Adjust brightness or turn individual displays on and off. External screens use their own control channel when available and fall back to dimming the picture, while the keyboard brightness keys can follow the pointer and show the brightness percentage. Optional custom brightness shortcuts adjust the primary display or the display under the pointer. Enable and edit them under More options, on the Keyboard shortcuts page or in the panel's Options.
- **Extra brightness.** Pushes the XDR panel of a MacBook Pro past its regular maximum using the display's HDR headroom. Toggle it from the Displays panel or Settings.
- **Bluetooth on sleep.** Switches Bluetooth off while the Mac sleeps, so a laptop in a bag stops stealing the headphones you are listening to elsewhere. Bluetooth you had already turned off stays off, and only what Vorssaint switched off comes back on wake.

## Install

With [Homebrew](https://brew.sh):

```sh
brew install --cask vorssaint
```

Or grab the disk image from the [releases page](https://github.com/vorssaint/vorssaint-utils/releases) and drag Vorssaint into Applications.

Builds are signed with an Apple Developer ID and notarized, so macOS opens them without a fuss and your permissions survive updates.

## Uninstall

With Homebrew:

```sh
brew uninstall --cask vorssaint
```

To remove Vorssaint completely, including its settings and permissions:

```sh
./Tools/uninstall.sh
```

## Private by default

Vorssaint is local-first, with no account, analytics or tracking. The network is touched only by things you can see: update checks, the speed test, Homebrew actions, optional online lyric lookup, temporary screenshot or recording links and feedback you explicitly send. The full story is in the [privacy notes](docs/PRIVACY.md).

Permissions get the same treatment. Every one is optional, the app explains each in plain words, shows which features actually use it, and even tells you when a permission you granted is no longer needed by anything, with a shortcut to revoke it.

<p align="center">
  <img src="docs/assets/readme/permissions.png" width="720" alt="The Permissions page showing what each permission does, which features use it, and an unused permission warning">
</p>

| Permission | Used by | Without it |
|---|---|---|
| Accessibility | Switcher, Dock features, window controls, mouse and keyboard features, snippets, cut and paste, optional Dynamic Island notification mirroring | Those features stay off |
| Screen Recording | Window previews, screenshots, copy text and screen recordings | Those captures stay unavailable |
| System Audio Recording | Per app volume and output routing | Apps stay on normal system audio |
| Microphone | Optional voice track in screen recordings | Recordings continue without your voice |
| Camera | The mirror window or Dynamic Island preview | The mirror stays off |
| Calendars | Appointments in Dynamic Island | Calendar access remains unavailable |
| Files and Folders | Downloads in the folder you choose | Choose an accessible folder |
| Notifications | Keep awake, battery, monitor and update alerts | System notifications stay off |
| Full Disk Access, optional | Deeper cleaner and uninstaller scans | Only reachable places are scanned |
| Administrator, once, optional | Password free closed lid toggling | A password prompt per toggle |

The shelf and almost every quick toggle need no permission at all. Finder cut and paste, the uninstaller, emptying the Trash and the Homebrew terminal handoff ask macOS for Automation access the first time they talk to Finder or Terminal.

## What you need

- A Mac with Apple Silicon
- macOS 14 Sonoma or newer

### Build it yourself

```sh
git clone https://github.com/vorssaint/vorssaint-utils.git
cd vorssaint-utils
./build.sh            # compile, generate the icon, assemble the signed bundle
./build.sh --install  # the same, then install into Applications and launch
```

Xcode Command Line Tools are the only requirement. The [contributing guide](CONTRIBUTING.md) covers the layout and conventions. Official builds come only from the maintainer: the GPL covers the source, while the Vorssaint name, icon and look are covered by [TRADEMARKS.md](TRADEMARKS.md), so forks need their own identity.

## When something misbehaves

The [troubleshooting guide](docs/TROUBLESHOOTING.md) walks through the common cases: the app blocked on first launch, a permission that will not stick, thumbnails showing as icons. To remove Vorssaint completely, `./Tools/uninstall.sh` quits the app, drops the login item, resets its privacy grants and deletes every trace.

## Documentation

- [Privacy](docs/PRIVACY.md), what does and does not leave your Mac
- [Permissions](docs/PERMISSIONS.md), every macOS permission in plain words
- [Troubleshooting](docs/TROUBLESHOOTING.md), the common fixes
- [Contributing](CONTRIBUTING.md), build, layout and conventions
- [Support](SUPPORT.md), where to get help
- [Security](SECURITY.md), how to report a vulnerability

## Community

Vorssaint went from first commit to the front of GitHub trending in three days, top of the Swift charts, and issues and pull requests have shaped every release since. Bug reports, feature ideas and translations are all welcome, starting from the [contributing guide](CONTRIBUTING.md).

Vorssaint is free and will stay that way. If it earned its place in your menu bar, a star helps other people find it, and a [coffee](https://buymeacoffee.com/vorssaint) keeps the maintainer awake, with or without the Keep awake feature.

## Acknowledgements

- App icon designed by [@divisionseven](https://github.com/divisionseven)

## License

[GPL 3.0 or later](LICENSE), copyright 2026 Vorssaint. The license covers the source code; the Vorssaint name, logo and look are covered separately in [TRADEMARKS.md](TRADEMARKS.md).

<p align="center">
  <sub>Made by <a href="https://x.com/vorssaint">@vorssaint</a></sub>
</p>


## 🌐 Web Resources & Aesthetic Symbols Index
- [ZODIAC CELESTIAL](https://clean-aesthetic-fonts-73.pages.dev/pt/zodiac-celestial/)
- [SYM 1F92F](https://lace-and-ribbon-text-61.pages.dev/symbol/sym-1f92f/)
- [SYM 2631](https://coquette-aesthetic-symbols-88.pages.dev/symbol/sym-2631/)
- [SYM 1F496](https://alchemical-symbol-hub-52.pages.dev/symbol/sym-1f496/)
- [BIOHAZARD SYMBOL](https://pastel-moe-emoticons-80.pages.dev/symbol/biohazard-symbol/)
- [OUTLINED STAR](https://balletcore-bio-symbols-63.pages.dev/symbol/outlined-star/)
- [DISCORD STATUS](https://ballet-core-symbols-11.pages.dev/es/discord-status/)
- [STARRY LOVE AURA](https://coquette-aesthetic-symbols-88.pages.dev/symbol/starry-love-aura/)
- [SYM 1D49B](https://synthwave-text-vault-95.pages.dev/symbol/sym-1d49b/)
- [SYM 1F924](https://baroque-aesthetic-symbols-59.pages.dev/symbol/sym-1f924/)
- [SYM 1F617](https://soft-angel-symbols-21.pages.dev/symbol/sym-1f617/)
- [SYM 26EF](https://cyber-clan-tags-36.pages.dev/symbol/sym-26ef/)
- [SYM 1F61D](https://vintage-angel-text-38.pages.dev/symbol/sym-1f61d/)
- [SYM 268D](https://coquette-aesthetic-symbols-88.pages.dev/symbol/sym-268d/)
- [SYM 2642](https://dark-literary-kaomoji-13.pages.dev/symbol/sym-2642/)
- [SYM 1F92C](https://arcane-symbol-vault-32.pages.dev/symbol/sym-1f92c/)
- [SYM 1D48E](https://zen-typography-hub-86.pages.dev/symbol/sym-1d48e/)
- [SYM 1D47B](https://gothic-bio-fonts-22.pages.dev/symbol/sym-1d47b/)
- [SYM 1F92A](https://anime-sparkle-text-95.pages.dev/symbol/sym-1f92a/)
- [NATURE FLOWERS](https://sleek-typography-hub-12.pages.dev/vi/nature-flowers/)
- [SYM 1D46B](https://ribbon-bow-unicode-18.pages.dev/symbol/sym-1d46b/)
- [SYM 1D44C](https://mecha-text-vault-91.pages.dev/symbol/sym-1d44c/)
- [MUSIC FLAT SIGN](https://ribbon-bow-unicode-18.pages.dev/symbol/music-flat-sign/)
- [SYM 1D48B](https://coquette-aesthetic-symbols-62.pages.dev/symbol/sym-1d48b/)
- [SYM 1D427](https://ribbon-bow-unicode-18.pages.dev/symbol/sym-1d427/)
- [WINGED ANGELIC COQUETTE HEART](https://sleek-typography-hub-12.pages.dev/symbol/winged-angelic-coquette-heart/)
- [SYM 1D449](https://minimal-star-symbols-54.pages.dev/symbol/sym-1d449/)
- [NATURE FLOWERS](https://ribbon-bow-unicode-18.pages.dev/vi/nature-flowers/)
- [HEAVY RIGHTWARD ARROW](https://soft-angel-symbols-21.pages.dev/symbol/heavy-rightward-arrow/)
- [SYM 1D463](https://coquette-aesthetic-symbols-62.pages.dev/symbol/sym-1d463/)
- [SYM 1D40E](https://sleek-bio-fonts-25.pages.dev/symbol/sym-1d40e/)
- [SYM 1D407](https://clean-aesthetic-arrows-99.pages.dev/symbol/sym-1d407/)
- [TENDER GENTLE TEAR KAOMOJI](https://sleek-typography-hub-12.pages.dev/symbol/tender-gentle-tear-kaomoji/)
- [COQUETTE BOW RIBBON](https://coquette-aesthetic-symbols-88.pages.dev/symbol/coquette-bow-ribbon/)
- [SYM 1F63A](https://vintage-runes-text-63.pages.dev/symbol/sym-1f63a/)
- [SYM 26EA](https://cyberpunk-clan-tags-43.pages.dev/symbol/sym-26ea/)
- [SYM 26A6](https://sleek-arrow-symbols-42.pages.dev/symbol/sym-26a6/)
- [RIGHTWARDS PAIRED HARPOON](https://clean-aesthetic-arrows-99.pages.dev/symbol/rightwards-paired-harpoon/)
- [SYM 26AC](https://clean-aesthetic-arrows-99.pages.dev/symbol/sym-26ac/)
- [BRACKETS](https://gothic-bio-fonts-98.pages.dev/pt/brackets/)
- [SYM 2674](https://coquette-aesthetic-symbols-62.pages.dev/symbol/sym-2674/)
- [SYM 1D417](https://theeduplaycampen.pages.dev/symbol/sym-1d417/)
- [SYM 2686](https://theeduplaycampen.pages.dev/symbol/sym-2686/)
- [SEA STARFISH OCEAN](https://coquette-aesthetic-symbols-88.pages.dev/symbol/sea-starfish-ocean/)
- [SYM 2616](https://kawaii-kaomoji-hub-88.pages.dev/symbol/sym-2616/)
- [SYM 1D42A](https://witchy-runic-text-71.pages.dev/symbol/sym-1d42a/)
- [PISCES ZODIAC FISHES](https://coquette-aesthetic-symbols-52.pages.dev/symbol/pisces-zodiac-fishes/)
- [DISCORD STATUS](https://coquette-symbols.pages.dev/es/discord-status/)
- [SYM 2637](https://sleek-bio-fonts-25.pages.dev/symbol/sym-2637/)
- [SYM 1D40C](https://coquette-aesthetic-symbols-52.pages.dev/symbol/sym-1d40c/)
- [RIGHT HEAVY BRACKET BOX](https://coquette-aesthetic-symbols-62.pages.dev/symbol/right-heavy-bracket-box/)
- [MUSIC WEATHER](https://ribbon-bow-unicode-18.pages.dev/music-weather/)
- [SYM 1D40C](https://ribbon-heart-fonts-86.pages.dev/symbol/sym-1d40c/)
- [DISCORD STATUS](https://coquette-aesthetic-symbols-88.pages.dev/ru/discord-status/)
- [SYM 26AA](https://zen-typography-hub-86.pages.dev/symbol/sym-26aa/)
- [SYM 1D42A](https://coquette-aesthetic-symbols-86.pages.dev/symbol/sym-1d42a/)
- [SYM 1D40E](https://ribbon-bow-unicode-18.pages.dev/symbol/sym-1d40e/)
- [SYM 1D438](https://sleek-bio-fonts-25.pages.dev/symbol/sym-1d438/)
- [MUSIC SHARP SIGN](https://soft-angel-symbols-21.pages.dev/symbol/music-sharp-sign/)
- [SYM 1D495](https://sleek-typography-hub-12.pages.dev/symbol/sym-1d495/)
- [SYM 1F61C](https://coquette-aesthetic-symbols-62.pages.dev/symbol/sym-1f61c/)
- [COQUETTE BOW RIBBON](https://soft-bow-fonts-22.pages.dev/symbol/coquette-bow-ribbon/)
- [SYM 1D407](https://ribbon-bow-unicode-18.pages.dev/symbol/sym-1d407/)
- [SYM 1F63F](https://ribbon-bow-unicode-18.pages.dev/symbol/sym-1f63f/)
- [OPEN CENTRE STAR](https://cyber-clan-tags-36.pages.dev/symbol/open-centre-star/)
- [SYM 1D418](https://dark-literary-kaomoji-13.pages.dev/symbol/sym-1d418/)
- [SYM 2746](https://vintage-runes-text-63.pages.dev/symbol/sym-2746/)
- [RIBBON BOW UNICODE 18.PAGES.DEV](https://ribbon-bow-unicode-18.pages.dev/)
- [TRENDING](https://soft-angel-symbols-21.pages.dev/es/trending/)
- [SYM 1F925](https://vintage-runes-text-63.pages.dev/symbol/sym-1f925/)
- [VIRGO ZODIAC MAIDEN](https://coquette-aesthetic-symbols-86.pages.dev/symbol/virgo-zodiac-maiden/)
- [SYM 263B](https://glitch-font-studio-46.pages.dev/symbol/sym-263b/)
- [AQUARIUS ZODIAC WATER BEARER](https://manga-speech-symbols-95.pages.dev/symbol/aquarius-zodiac-water-bearer/)
- [SYM 2639](https://vintage-coquette-text-58.pages.dev/symbol/sym-2639/)
- [RINGED PLANET SATURN](https://minimal-star-symbols-25.pages.dev/symbol/ringed-planet-saturn/)
- [SYM 1D49B](https://vintage-angel-text-38.pages.dev/symbol/sym-1d49b/)
- [SYM 26F0](https://ribbon-heart-fonts-86.pages.dev/symbol/sym-26f0/)
- [SYM 26A8](https://cyber-clan-tags-36.pages.dev/symbol/sym-26a8/)
- [SYM 26E6](https://clean-line-emojis-93.pages.dev/symbol/sym-26e6/)
- [SYM 26A4](https://ribbon-bow-unicode-18.pages.dev/symbol/sym-26a4/)
- [SYM 1D405](https://chibi-emoticon-world-87.pages.dev/symbol/sym-1d405/)
- [DAGGER CROSS SYMBOL](https://vintage-coquette-text-58.pages.dev/symbol/dagger-cross-symbol/)
- [SYM 1D41A](https://theeduplaycampen.pages.dev/symbol/sym-1d41a/)
- [SYM 1F495](https://ribbon-bow-unicode-18.pages.dev/symbol/sym-1f495/)
- [SYM 2638](https://kawaii-kaomoji-hub-88.pages.dev/symbol/sym-2638/)
- [ANGEL WINGS HEART](https://minimal-star-symbols-54.pages.dev/symbol/angel-wings-heart/)
- [SYM 265F](https://clean-line-emojis-93.pages.dev/symbol/sym-265f/)
- [SYM 1FAE2](https://vintage-runes-text-63.pages.dev/symbol/sym-1fae2/)
- [SYM 1F921](https://ribbon-bow-unicode-18.pages.dev/symbol/sym-1f921/)
- [SYM 1D454](https://chibi-emoticon-world-87.pages.dev/symbol/sym-1d454/)
- [TENDER GENTLE TEAR KAOMOJI](https://vintage-lace-text-53.pages.dev/symbol/tender-gentle-tear-kaomoji/)
- [SYM 2632](https://theeduplaycampen.pages.dev/symbol/sym-2632/)
- [TRENDING](https://coquette-aesthetic-symbols-88.pages.dev/trending/)
- [SYM 1D44A](https://coquette-aesthetic-symbols-14.pages.dev/symbol/sym-1d44a/)
- [INSTAGRAM BIO](https://clean-aesthetic-arrows-99.pages.dev/pt/instagram-bio/)
- [SYM 1F62E](https://gothic-bio-fonts-98.pages.dev/symbol/sym-1f62e/)
- [SYM 1D417](https://minimal-star-symbols-22.pages.dev/symbol/sym-1d417/)
- [SYM 1D415](https://soft-angel-symbols-21.pages.dev/symbol/sym-1d415/)
- [WARM HUG EMBRACE KAOMOJI](https://vintage-runes-text-63.pages.dev/symbol/warm-hug-embrace-kaomoji/)
- [SYM 1D4A4](https://monochrome-text-lab-86.pages.dev/symbol/sym-1d4a4/)
- [LIBRA ZODIAC SCALES](https://monochrome-text-lab-86.pages.dev/symbol/libra-zodiac-scales/)
- [SYM 1D42E](https://soft-angel-symbols-21.pages.dev/symbol/sym-1d42e/)
- [SYM 1D41B](https://theeduplaycampen.pages.dev/symbol/sym-1d41b/)
- [SYM 1D424](https://cyber-clan-tags-36.pages.dev/symbol/sym-1d424/)
- [SYM 2640](https://clean-aesthetic-arrows-99.pages.dev/symbol/sym-2640/)
- [SYM 26CD](https://sleek-arrow-symbols-42.pages.dev/symbol/sym-26cd/)
- [SYM 1F636 200D 1F32B FE0F](https://daintystar-font-studio-48.pages.dev/symbol/sym-1f636-200d-1f32b-fe0f/)
- [SYM 26EC](https://ribbon-heart-fonts-86.pages.dev/symbol/sym-26ec/)
- [SYM 1D49A](https://chibi-emotion-faces-74.pages.dev/symbol/sym-1d49a/)
- [SYM 1F615](https://cyber-clan-tags-90.pages.dev/symbol/sym-1f615/)
- [SYM 267A](https://coquette-aesthetic-symbols-88.pages.dev/symbol/sym-267a/)
- [SYM 1D458](https://soft-angel-symbols-21.pages.dev/symbol/sym-1d458/)
- [TRENDING](https://sleek-type-aesthetic-51.pages.dev/trending/)
- [SYM 1D493](https://cyber-clan-tags-36.pages.dev/symbol/sym-1d493/)
- [SYM 26F8](https://sleek-bio-symbols-51.pages.dev/symbol/sym-26f8/)
- [SYM 1D470](https://coquette-symbols.pages.dev/symbol/sym-1d470/)
- [SYM 2679](https://coquette-aesthetic-symbols-88.pages.dev/symbol/sym-2679/)
- [BRACKETS](https://subtle-sparkle-text-86.pages.dev/vi/brackets/)
- [LEFT POINTING DOUBLE ANGLE QUOTATION](https://sleek-typography-hub-12.pages.dev/symbol/left-pointing-double-angle-quotation/)
- [SYM 1D405](https://raven-gothic-kaomoji-25.pages.dev/symbol/sym-1d405/)
- [CAPRICORN ZODIAC GOAT](https://moe-star-emoticons-13.pages.dev/symbol/capricorn-zodiac-goat/)
- [OPEN CENTRE STAR](https://soft-angel-unicode-43.pages.dev/symbol/open-centre-star/)
- [SYM 26F7](https://gothic-bio-fonts-13.pages.dev/symbol/sym-26f7/)
- [SYM 26F9](https://sleek-arrow-symbols-42.pages.dev/symbol/sym-26f9/)
- [NATURE FLOWERS](https://gothic-bio-fonts-22.pages.dev/nature-flowers/)
- [SYM 26EE](https://minimal-star-symbols-22.pages.dev/symbol/sym-26ee/)
- [SYM 1D463](https://manga-speech-symbols-95.pages.dev/symbol/sym-1d463/)
- [STARS](https://neon-matrix-symbols-94.pages.dev/stars/)
- [SYM 2683](https://minimal-star-symbols-25.pages.dev/symbol/sym-2683/)
- [SYM 1F62C](https://minimal-star-symbols-25.pages.dev/symbol/sym-1f62c/)
