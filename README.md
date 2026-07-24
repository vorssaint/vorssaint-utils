<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/readme/logo-dark.png">
    <img src="docs/assets/readme/logo.png" width="220" alt="Vorssaint logo">
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
  <a href="CHANGELOG.md">Changelog</a>
</p>

<p align="center">
  <a href="https://github.com/vorssaint/vorssaint-utils/releases"><img src="https://img.shields.io/github/v/release/vorssaint/vorssaint-utils?label=release&color=4c8dff" alt="Latest release"></a>
  <a href="https://github.com/vorssaint/vorssaint-utils/releases"><img src="https://img.shields.io/github/downloads/vorssaint/vorssaint-utils/total?color=4c8dff" alt="Downloads"></a>
  <a href="https://github.com/vorssaint/vorssaint-utils/actions/workflows/ci.yml"><img src="https://github.com/vorssaint/vorssaint-utils/actions/workflows/ci.yml/badge.svg?branch=main&event=push" alt="CI status"></a>
  <a href="#what-you-need"><img src="https://img.shields.io/badge/macOS-14%2B%20Apple%20Silicon-black" alt="macOS 14 and newer, Apple Silicon"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue" alt="License GPL 3.0 or later"></a>
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/53716"><img src="https://img.shields.io/badge/Trendshift-%231%20Swift%20Repository%20of%20the%20Day-e8663d?labelColor=2b2b2b" alt="Number 1 Swift repository of the day on Trendshift"></a>
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

Three one click bundles, Essentials, Windows, and Battery and quiet, shape the whole app in one move, and onboarding ends by asking which one you want. Every feature also wears an honest energy badge saying what it keeps alive while on.

<p align="center">
  <img src="docs/assets/readme/features-hub.png" width="720" alt="The Features hub in Settings, installing and uninstalling whole features">
</p>

The rest bends the same way: panel sections reorder and hide, the compact layout trades sections for tabs, settings export to a file and import on a new Mac, and the whole app speaks thirteen languages.

## Everything it does

### Sound

- **Volume mixer.** Slide any single app up or down while the rest of the Mac stays put, and push a quiet one past 100 percent when a video is just too low. Hide the apps you never adjust to keep the list short. No audio driver, no setup.
- **Per app output.** Send your music to the speakers and a call to your headset at the same time.
- **Output switcher.** Cycle between chosen outputs with one shortcut, and drop the volume automatically when headphones disconnect.
- **Microphone tools.** Pin your favorite input so the Mac stops guessing, and mute the mic everywhere with a click or shortcut.
- **Music app blocker.** Stops the Music app from bursting in when headphones connect.

### Know what your Mac is doing

- **System monitor.** CPU, GPU, memory pressure and temperatures with history graphs, plus battery health, time remaining, cycle count, power draw and which apps are burning energy right now.
- **Menu bar readouts.** Keep the readings you care about in the bar itself, with values or compact usage bars, including optional battery time remaining, combined or as separate items.
- **Network.** Live rates, session totals and a built in speed test.
- **Alerts.** Optional notifications for sustained CPU load, high temperature, memory pressure, low disk space and low battery.

### Windows and the Dock

- **App switcher.** A richer take on pressing ⌘Tab, with live window thumbnails, minimized windows included, and more than one window per app.
- **Window layout.** Snap the active window to halves, thirds, sixths, corners, center or another display, each with its own optional shortcut. On a trackpad or mouse, hold chosen modifiers and drag anywhere to move a window, then add Shift to resize it. A mouse can also resize with the right button.
- **Dock Preview.** Hover a Dock icon to peek at that app's windows and jump straight into the right one.
- **Dock clicks.** Click the Dock icon of the active app to minimize its windows, or cycle through them one by one.
- **Maximize windows.** The green button fills the screen without creating another Space, and puts the window back on the next click.
- **Quit on close.** Apps you choose quit when their last window closes.

<p align="center">
  <img src="docs/assets/readme/window-switcher.gif" width="540" alt="The window switcher showing live thumbnails of open windows">
</p>

### Keyboard and mouse

- **Text snippets.** Type a short trigger anywhere and it becomes your text, expanded instantly or after a space, with clipboard variables plus date and time in any format you like. A searchable quick menu, organized into folders, types any snippet right at your cursor.
- **Smooth scrolling.** Gives a mouse wheel the glide of a trackpad.
- **Scroll direction.** Invert the wheel without touching the trackpad's natural scrolling.
- **Side buttons.** The mouse Back and Forward buttons start meaning it, in Finder, browsers and compatible apps.
- **Mouse button shortcuts.** Give any extra mouse button a key combination of your choice. Click add, press the button, record the keys.
- **Middle click.** A three finger press becomes a real middle click.
- **Key debounce.** Filters the double letters a worn keyboard invents.

### Clipboard, files and links

- **Clipboard history.** Local history of text, images and files with pinned favorites, search and quick paste shortcuts.
- **Paste as plain text.** One shortcut pastes without fonts, colors or links, and the original stays on the clipboard.
- **Shelf.** Park files, text and links near your cursor mid drag, then drop them where they belong later.
- **Finder cut and paste.** ⌘X and ⌘V move files the way you always expected them to.
- **Clean URL.** Strips tracking parameters from copied links, on demand or automatically.

### Everyday tools

- **Quick panel.** ⌃⌘V opens a small floating palette with your favorite tools one key away.
- **Quick toggles.** One-click system actions in their own panel tab: switch light and dark mode, empty the Trash, eject every disk, show hidden files, hide desktop icons, lock the screen and more.
- **Radial menu.** Hold a shortcut, or a spare side mouse button, and a wheel of your favorite actions opens around the pointer: apps, files, links, key combos, media controls and Vorssaint tools, with submenus for more. Point and release to run one.
- **Screenshot.** Capture an area, a window or the whole screen on a frozen picture. A quick preview can copy, save, delete or open the editor, which adds stickers, annotations, precise crop, redaction, backgrounds and pinned captures. A QR code in the shot shows its content to copy or open, from the preview and the editor. Optional timer, save folder and 1x export included. Captures can copy themselves to the clipboard, run your favorite action right after the shot, and save into dated subfolders with a file name pattern of your own.
- **Camera preview.** A floating mirror to check how you look before joining a call, one click or shortcut away. Pick the camera when several are connected; it closes as soon as you click away.
- **Scratchpad.** A floating pad for short-lived text: meeting notes, numbers, fragments on their way somewhere else. It saves as you type, floats over your work, and can copy everything, export to a file or clear itself after a quiet period.
- **Copy text from screen.** Select any area and its text is recognized offline, straight onto the clipboard. When the area holds a QR code, its content is shown so you can copy it or open the link.
- **Color picker.** Grab any pixel with the system loupe as HEX, RGB, HSL or SwiftUI code.
- **Cleaner.** Sweeps app leftovers, caches and logs, by hand or on a schedule.
- **WhatsApp downloads.** The Cleaner can also tidy files WhatsApp saved into Downloads, confirmed by macOS metadata and only ever moved to the Trash, with a review list, retention rules and an optional organizer that files new downloads into a folder of your choice.
- **Uninstaller.** Drop an app in and take its caches, preferences and logs to the Trash with it.
- **Media tools.** Compress videos and images, make GIFs and extract text, all locally.
- **Homebrew manager.** Search, install and remove formulae and casks without opening a terminal.
- **Cleaning Mode.** Locks the keyboard and blacks out every display while you clean.

### Energy and display

- **Keep awake.** Keep the Mac up for a timer, until you say stop or automatically with an external display or power connection, including with the lid closed, choose the active menu bar icon and color, and see the remaining time beside it.
- **Displays.** Adjust brightness or turn individual displays on and off from the menu bar panel. External screens use their own control channel when available and fall back to dimming the picture, while the keyboard brightness keys can follow the pointer and show the brightness percentage.
- **Extra brightness.** Pushes the XDR panel of a MacBook Pro past its regular maximum using the display's HDR headroom.

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

Vorssaint has no backend, no account, no analytics and no tracking. The network is touched only by things you can see: update checks, the speed test, and Homebrew searches and installs you start. The full story is in the [privacy notes](docs/PRIVACY.md).

Permissions get the same treatment. Every one is optional, the app explains each in plain words, shows which features actually use it, and even tells you when a permission you granted is no longer needed by anything, with a shortcut to revoke it.

<p align="center">
  <img src="docs/assets/readme/permissions.png" width="720" alt="The Permissions page showing what each permission does, which features use it, and an unused permission warning">
</p>

| Permission | Used by | Without it |
|---|---|---|
| Accessibility | Switcher, Dock features, window controls, mouse and keyboard features, snippets, cut and paste | Those features stay off |
| Screen Recording | Switcher and Dock Preview thumbnails, copy text from screen | Previews fall back or stay off |
| System Audio Recording | Per app volume and output routing | Apps stay on normal system audio |
| Notifications | Keep awake, battery, monitor and update alerts | The app stays silent |
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

## License

[GPL 3.0 or later](LICENSE), copyright 2026 Vorssaint. The license covers the source code; the Vorssaint name, logo and look are covered separately in [TRADEMARKS.md](TRADEMARKS.md).

<p align="center">
  <sub>Made by <a href="https://x.com/vorssaint">@vorssaint</a></sub>
</p>
