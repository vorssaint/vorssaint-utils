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
  <a href="https://github.com/vorssaintapp/vorssaint-utils/releases"><img src="https://img.shields.io/github/v/release/vorssaintapp/vorssaint-utils?label=release&color=4c8dff" alt="Latest release"></a>
  <a href="https://github.com/vorssaintapp/vorssaint-utils/releases"><img src="https://img.shields.io/github/downloads/vorssaintapp/vorssaint-utils/total?color=4c8dff" alt="Downloads"></a>
  <a href="https://github.com/vorssaintapp/vorssaint-utils/actions/workflows/ci.yml"><img src="https://github.com/vorssaintapp/vorssaint-utils/actions/workflows/ci.yml/badge.svg?branch=main&event=push" alt="CI status"></a>
  <a href="#what-you-need"><img src="https://img.shields.io/badge/macOS-14%2B%20Apple%20Silicon-black" alt="macOS 14 and newer, Apple Silicon"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue" alt="License GPL 3.0 or later"></a>
</p>

<p align="center">
  <a href="https://discord.gg/M6BwWH4BJp">
    <img src="docs/assets/readme/discord-symbol.svg" width="72" alt="Discord">
  </a>
</p>

<p align="center">
  For partnerships or anything private, email
  <a href="mailto:hello@vorssaint.com"><strong>hello@vorssaint.com</strong></a>.
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/53716?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-53716" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/53716/daily?language=Swift" alt="vorssaintapp/vorssaint-utils | Trendshift daily ranking" width="250" height="55"></a>
  &nbsp;&nbsp;
  <a href="https://trendshift.io/repositories/53716?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-53716" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/53716/weekly?language=Swift" alt="vorssaintapp/vorssaint-utils | Trendshift weekly ranking" width="250" height="55"></a>
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

- **Volume mixer.** Adjust the Mac's overall volume or slide any single app up or down, enter an exact percentage, and push a quiet one past 100 percent when a video is just too low. Send system sounds through another output, or hide the apps you never adjust to keep the list short. No audio driver, no setup.
- **Per app output.** Send your music to the speakers and a call to your headset at the same time.
- **Output switcher.** Cycle between chosen outputs with one shortcut, and drop the volume automatically when headphones disconnect.
- **Microphone tools.** Pin your favorite input so the Mac stops guessing, and mute every microphone at once with a click or shortcut, whichever one an app is using.
- **Music app blocker.** Stops the Music app from bursting in when headphones connect. You can still open it yourself.

### Know what your Mac is doing

- **System monitor.** CPU, GPU, memory, swap use and temperatures with history graphs, including a choice between total memory in use and memory held by apps, plus battery health, time remaining, cycle count, power draw, an optional Fan Control beta with continuous manual speeds, custom temperature curves and live RPM, the apps burning energy right now and a shortcut to the Mac's full process inspector.
- **Menu bar readouts.** Keep the readings you care about in the bar itself, with values or compact usage bars, including optional battery time remaining and fan speed, combined or as separate items.
- **Network.** Live rates, session totals and a built in speed test.
- **Alerts.** Optional notifications for sustained CPU load, high CPU or battery temperature, memory pressure, low disk space and low battery.

### Windows and the Dock

- **App switcher.** A richer take on pressing ⌘Tab, with adjustable live window thumbnails, minimized windows included, and more than one window per app. Simple mode keeps every window and its title without previews or screen capture, with optional grouping to one entry per app. Optionally press S to keep search open after releasing the switcher shortcut, or hide the shortcut hints below the large icon row. Press the window shortcut directly to move between windows of the app in front. Set per-app rules to include windowless apps, keep them window-only or hide them. Choose apps where Vorssaint pauses both switcher and Dock thumbnail capture while they are in front.
- **Window layout.** Snap the active window to halves, thirds, sixths, corners or center, maximize it with or without a margin, or move it to the next or previous display, each with its own optional shortcut. Restore steps back through recent placements. Turn on edge snapping in Window Layout, then drag a title bar to any screen edge or corner for a live preview. Hold chosen modifiers and drag anywhere to move it, then add Shift to resize. A mouse can also resize with the right button.
- **Dock Preview.** Hover a Dock icon to see adjustable window thumbnails with clear titles, click the one you want or drag it to move and snap the window.
- **Dock clicks.** Click the Dock icon of the active app to minimize its windows, hide the app, or cycle through its windows.
- **Maximize windows.** The green button fills the screen without creating another Space, and puts the window back on the next click.
- **Quit on close.** Apps you choose quit when their last window closes.

<p align="center">
  <img src="docs/assets/readme/window-switcher.gif" width="540" alt="The window switcher showing live thumbnails of open windows">
</p>

### Keyboard and mouse

- **Text snippets.** Type a short trigger anywhere and it becomes your text, expanded instantly or after a space, with clipboard variables plus date and time in any format you like. A searchable quick menu, organized into folders, types any snippet right at your cursor.
- **Smooth scrolling.** Gives a mouse wheel the glide of a trackpad.
- **Focus follows mouse.** Install it from Features to bring the window under the
  pointer to the front after an adjustable pause. It waits while you drag or hold a
  modifier key.
- **Scroll direction.** Invert vertical and horizontal wheel movement separately without
  touching the trackpad's natural scrolling.
- **Side buttons.** The mouse Back and Forward buttons start meaning it, in Finder, browsers and compatible apps.
- **Mouse button shortcuts.** Give any extra button or side-wheel direction a key combination of your choice. Click add, use it, record the keys.
- **Middle click.** A three finger press becomes a real middle click.
- **Apps to leave alone.** Every feature above can name apps from anywhere on your Mac that drive themselves with the mouse, like 3D and design tools, and it steps aside in those.
- **Key debounce.** Filters the double letters a worn keyboard invents.
- **Super key.** Hold Caps Lock and it counts as the modifier combination you choose, so one key can drive your shortcuts. A tap on its own can switch input sources, switch capitals, press Escape, or do nothing.
- **Keyboard shortcuts.** Edit every installed feature's global shortcut from one categorized page, see what is active and use the shorter Super key combination when available.

### Clipboard, files and links

- **Clipboard history.** Local history of text, images and files with pinned favorites, search, quick paste shortcuts and an on-demand preview where text can be selected or edited.
- **Auto clear clipboard.** Empty the system clipboard a set time after you copy, and when the Mac sleeps, the display sleeps or the screen locks. Each trigger is optional, works with history off, and leaves your saved items untouched.
- **Paste as plain text.** One shortcut pastes without fonts, colors or links, and the original stays on the clipboard.
- **Shelf.** Park files, text and links near your cursor mid drag, or open it from a screen edge, then drop them where they belong later.
- **Finder shortcuts.** ⌘X and ⌘V move files, an optional F2 shortcut renames the selection, and copied images can become PNG files with ⌘V.
- **Clean URL.** Strips tracking parameters and extra names you choose from copied links, on demand or automatically.
- **Disk image installer.** When a mounted disk image contains one app, install it into Applications with one click, eject the image and move its download to Trash.

### Everyday tools

- **Command Bar.** One shortcut opens a field over whatever you are doing. Drag its mark to place it anywhere on a screen, or double-click the mark to put it back. Type a few letters to run any Vorssaint action, open an app, switch to a window, insert an emoji or snippet, paste from your clipboard history at the cursor, and it reaches into the app you are using to run any command from its menus, showing that command's own shortcut. It answers sums, conversions, dates and questions about your Mac as you type, opens a web address you enter, and acts on the text you already have selected. Saved shortcuts can also run a local script and show its output as you type. Name a few folders and it finds files in them by name too, through the Mac's own search, without building its own index or looking beyond the folders you choose. Apps also answer to alternate names known by macOS, and the Mac's own Settings panes are one row away. Press ⌘K on an app to quit, restart, force quit or send it to the Uninstaller, and on any row to name it, pin it, hide it or give it a shortcut of its own; ⌘Return shows an app, a folder or a file where it lives. Bug reports and feature ideas can also be sent from here, with every technical detail shown before you choose whether to include it. It learns what you use most and forgets everything you type into the bar.
- **Quick panel.** ⌃⌘V opens a small floating palette with your favorite tools one key away.
- **Quick toggles.** One-click system actions in their own panel tab: switch light and dark mode, toggle the keyboard light, empty the Trash, eject every disk, show hidden files, hide desktop icons, lock the screen and more.
- **Radial menu.** Hold a shortcut, or any extra mouse button, and a wheel of your favorite actions opens around the pointer: apps, files, links, key combos, media controls, quick toggles and Vorssaint tools, with submenus for more. Point and release to run one. Custom profiles let you switch between different wheel layouts, color themes, shortcuts and mouse triggers, and website links can fetch their actual icons on demand.
- **Screen capture.** Screenshots, screen recordings, copying text from the screen and picking a color share one selector, and each tool's own shortcut opens it already on that tool, ready to switch. Only installed tools appear, recording sound and microphone choices stay beside the mode selector, and every related setting lives on one page with a separate mode for each tool.
- **Screenshot.** Capture an area, a window or the whole screen on a frozen picture, or join a long page or document by scrolling it yourself, then pressing Enter or Done. It can include ordinary Vorssaint windows without showing its own capture controls. Its quick preview can stay near the shot or in any screen corner, can be dragged out as a PNG, and can copy, save, delete or open the editor, which adds stickers, annotations, precise crop, redaction, adjustable backgrounds and pinned captures. Recent screenshots and recordings stay one click away in their panel cards and editors, and are searchable from the Command Bar. Copied captures paste as PNG files, including in tools that expect a file path. The preview and editor can share a capture for 1, 6 or 24 hours and delete it early from the app. A QR code in the shot shows its content to copy or open, from the preview and the editor. Optional timer, save folder and 1x export included. Captures can copy themselves to the clipboard, run your favorite action right after the shot, save into dated subfolders with a file name pattern of your own, and use separate shortcuts for a whole-screen shot, the latest capture or any copied image.
- **Screen recording.** Record an area, a window or the whole screen with optional system sound and microphone audio on separate tracks. A dimmed guide keeps the chosen area visible while recording, and floating controls can pause, resume or stop it. Choose either source while selecting, then adjust its volume or remove it in the editor. Vorssaint windows can be selected like any other while recording controls stay out. The editor trims, cuts, smooths the pointer, adds optional automatic zooms that can stay with typing after a click, adds text and adjustable backgrounds, and saves reusable presets. Copy the finished video directly, copy and delete in one step, export video and GIF files to the folder you choose, or compress it locally and share a temporary 1-hour or 6-hour link under 100 MB.
- **Camera preview.** A floating mirror to check how you look before joining a call, one click or shortcut away. Pick the camera when several are connected; it closes as soon as you click away.
- **Scratchpad.** Floating pads in named tabs for short-lived text: meeting notes, numbers, fragments on their way somewhere else. They save as you type, preview Markdown formatting on demand, step aside when you click elsewhere (or stay floating, your call), and can copy everything, export to a file or clear themselves after a quiet period.
- **Copy text from screen.** Select any area and its text is recognized offline, straight onto the clipboard. When the area holds a QR code, its content is shown so you can copy it or open the link.
- **Color picker.** Grab any pixel from the shared screen selector as HEX, RGB, HSL or SwiftUI code, with the system loupe kept as a permission-free fallback.
- **App updates.** One list of the apps on your Mac that have a newer version, from Homebrew and from the App Store. Choose either source or both. Tick the ones you want and they update together, so you stop opening a different store for each app. It can also check in the background and tell you when something is waiting.
- **Cleaner.** Sweeps app leftovers, caches and logs, by hand or on a schedule.
- **Messaging downloads.** The Cleaner can also tidy the media a messaging app saves into Downloads, confirmed by macOS metadata and only ever moved to the Trash, with a review list, retention rules and an optional organizer that files new ones into a folder of your choice.
- **Uninstaller.** Drop an app in and take its verified caches, preferences, helpers and other leftovers to the Trash with it.
- **Media tools.** Compress videos or open any one in the editor to trim, cut and crop it, convert images one at a time or in batches with resizing, watermarks and reusable profiles, make GIFs and extract text, all locally.
- **Homebrew manager.** Search, install and remove formulae and casks without opening a terminal.
- **Cleaning Mode.** Locks the keyboard and blacks out every display while you clean.

### Energy and display

- **Keep awake.** Keep the Mac up for a timer, until you say stop or automatically with an external display or power connection, including with the lid closed, let displays sleep without stopping local work, choose the active menu bar icon and color, see the remaining time beside it, and optionally toggle it with a right click.
- **Displays.** Adjust brightness or turn individual displays on and off. External screens use their own control channel when available and fall back to dimming the picture, while the keyboard brightness keys can follow the pointer and show the brightness percentage.
- **Extra brightness.** Pushes the XDR panel of a MacBook Pro past its regular maximum using the display's HDR headroom.
- **Bluetooth on sleep.** Switches Bluetooth off while the Mac sleeps, so a laptop in a bag stops stealing the headphones you are listening to elsewhere. Bluetooth you had already turned off stays off, and only what Vorssaint switched off comes back on wake.

## Install

With [Homebrew](https://brew.sh):

```sh
brew install --cask vorssaint
```

Or grab the disk image from the [releases page](https://github.com/vorssaintapp/vorssaint-utils/releases) and drag Vorssaint into Applications.

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

Vorssaint is local-first, with no account, analytics or tracking. The network is touched only by things you can see: update checks, the speed test, Homebrew actions, temporary screenshot or recording links and feedback you explicitly send. The full story is in the [privacy notes](docs/PRIVACY.md).

Permissions get the same treatment. Every one is optional, the app explains each in plain words, shows which features actually use it, and even tells you when a permission you granted is no longer needed by anything, with a shortcut to revoke it.

<p align="center">
  <img src="docs/assets/readme/permissions.png" width="720" alt="The Permissions page showing what each permission does, which features use it, and an unused permission warning">
</p>

| Permission | Used by | Without it |
|---|---|---|
| Accessibility | Switcher, Dock features, window controls, mouse and keyboard features, snippets, cut and paste | Those features stay off |
| Screen Recording | Window previews, screenshots, copy text and screen recordings | Those captures stay unavailable |
| System Audio Recording | Per app volume and output routing | Apps stay on normal system audio |
| Microphone | Optional voice track in screen recordings | Recordings continue without your voice |
| Notifications | Keep awake, battery, monitor and update alerts | The app stays silent |
| Full Disk Access, optional | Deeper cleaner and uninstaller scans | Only reachable places are scanned |
| Administrator, once, optional | Password free closed lid toggling | A password prompt per toggle |

The shelf and almost every quick toggle need no permission at all. Finder cut and paste, the uninstaller, emptying the Trash and the Homebrew terminal handoff ask macOS for Automation access the first time they talk to Finder or Terminal.

## What you need

- A Mac with Apple Silicon
- macOS 14 Sonoma or newer

### Build it yourself

```sh
git clone https://github.com/vorssaintapp/vorssaint-utils.git
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
