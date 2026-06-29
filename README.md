# Vorssaint

> One small menu bar app that replaces a whole stack of paid Mac utilities.

<p align="center">
  <a href="https://vorssaint.com"><strong>vorssaint.com</strong></a>
</p>

<p align="center">
  <a href="https://github.com/vorssaint/vorssaint-utils/releases"><img src="https://img.shields.io/github/v/release/vorssaint/vorssaint-utils?label=release" alt="Latest release"></a>
  <a href="https://github.com/vorssaint/vorssaint-utils/actions/workflows/ci.yml"><img src="https://github.com/vorssaint/vorssaint-utils/actions/workflows/ci.yml/badge.svg?branch=main&event=push" alt="CI status"></a>
  <a href="#what-you-need"><img src="https://img.shields.io/badge/macOS-14%2B%20(Apple%20Silicon)-black" alt="macOS 14 and newer, Apple Silicon"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL%203.0%20or%20later-blue" alt="License GPL 3.0 or later"></a>
</p>

<p align="center"><sub>Também disponível em <a href="docs/README.pt-BR.md">Português (Brasil)</a>.</sub></p>

Vorssaint is the one menu bar app that does the work of a whole shelf of paid Mac tools. Per app volume, a full system monitor, window controls, clipboard history, a window switcher, a file shelf, an app uninstaller, link cleaning, keep awake and a handful more, all living behind a single icon up in your menu bar. Install it once and stop paying for and juggling a pile of single purpose apps. It is local-first and stays out of your way: core features run on your Mac, with network used only for update checks, speed tests and Homebrew actions you start. Free, open source, no account, no subscription and no Vorssaint telemetry.

## Everything in one menu bar app

Here is the whole toolkit. Every part can be turned on or off, so you keep what you use and hide the rest.

### 🎚️ Per app volume, the one people reach for first

Vorssaint puts a real mixer in your menu bar, so you can slide any single app up or down while the rest of your Mac stays exactly where it was. Mute a loud video and let your music keep playing. Lift a quiet call without turning everything else up. There is no extra audio driver to install and nothing to set up first.

<p align="center"><img src="docs/assets/readme/volume-mixer.png" alt="Per app volume mixer" width="540"></p>

On macOS 26 and newer the slider takes on the Liquid Glass look, and earlier versions of macOS keep the familiar one.

### 📊 See what your Mac is doing

- **System monitor.** Follow CPU, GPU, memory, temperatures, battery details and uptime in one compact panel, with small history graphs and optional menu bar readouts.
- **Monitor alerts.** Get optional notifications for sustained CPU load, high CPU temperature, critical memory pressure, low disk space and low battery.
- **Network.** Watch live upload and download rates, the totals for your session, and a speed test you can run whenever you are curious.
- **Power and battery.** Keep an eye on the system draw, the adapter input, the flow in and out of the battery, plus health, cycle count and which apps are burning real energy right now.

<p align="center"><img src="docs/assets/readme/system-monitor-graph.png" alt="System monitor with live graphs" width="460"></p>

### 🪟 Move windows and files around

- **Window switcher.** A richer spin on ⌘Tab with live thumbnails, including more than one window from the same app.
- **Window Layout.** Move the active window to halves, corners, center or the usable screen with optional shortcuts.
- **Shelf.** Park files, images, text and links near your cursor for a moment, then drag them wherever they belong later on.
- **Finder cut and paste.** Use ⌘X and ⌘V to move selected files, while text fields keep their usual shortcuts.
- **Quit on close.** Let an app quit when its last window closes, with exceptions for the apps you want to leave running.
- **Green button maximizer.** An optional take on the green button that keeps the window in the current Space and puts it back to its old size on the next click.
- **Clipboard history.** Keep a local text history with pinned items, search, manual ordering and quick paste shortcuts.

<p align="center"><img src="docs/assets/readme/window-switcher.gif" alt="Window switcher with live thumbnails" width="460"></p>

### ⚡ Keep your Mac awake

Run a timer or stay up until you say stop. Closed lid mode is there for when you want the Mac to keep going with the screen down, and it stays opt in and tightly scoped so it never catches you off guard.

<p align="center"><img src="docs/assets/readme/keep-awake-lid-closed.png" alt="Keep awake and closed lid controls" width="460"></p>

### 🧹 Tidy up and fine tune

- **Uninstaller.** Drop an app onto Settings, look over the caches, preferences and logs it left around, then move them all to the Trash together.
- **Clean URL.** Strip the tracking junk out of copied links, with an option to do it automatically.
- **Cleaning Mode.** Lock the keyboard for a quick wipe down and unlock from the overlay or a repeated key tap.
- **Scroll direction.** Flip the mouse wheel on its own without touching the trackpad and its natural scrolling.
- **Fan Control beta.** A safe testing entry is in place, with the manual controls held back until each Mac model is checked out properly.

### 🌍 Made to feel at home

Vorssaint speaks nine languages and you can switch between them anytime in Settings. The compact panel lets you choose between a plain list and grouped sections, and you can tuck away the parts you rarely use, then bring them back from the same spot.

## Install

The easiest way is with [Homebrew](https://brew.sh).

```sh
brew install --cask vorssaint/tap/vorssaint
```

Already running Vorssaint and you would rather not reinstall it? Adopt your current copy into Homebrew with no download.

```sh
brew install --cask --adopt vorssaint/tap/vorssaint
```

From then on, updates arrive with `brew upgrade --cask vorssaint`. You can also grab the latest disk image from the [releases page](https://github.com/vorssaint/vorssaint-utils/releases), open it and drag Vorssaint into Applications.

Vorssaint is signed with an Apple Developer ID and notarized by Apple, so it opens with no security warning, and that stable signing identity holds on to the permissions you grant across updates.

## Private by default

Vorssaint runs on your machine and asks for nothing it does not need. No account, no telemetry, no Vorssaint analytics and no tracking. It has no cloud dashboard and no Vorssaint backend. Network access is limited to visible features: update checks, the speed test and Homebrew searches, analytics and installs when you use the Homebrew manager. The whole story is written up in the [privacy notes](docs/PRIVACY.md).

Every macOS permission is optional, and the first run walks you through each one. A feature that is missing a permission simply stays quiet instead of breaking. Here is the short version, with the full picture in the [permissions guide](docs/PERMISSIONS.md).

| Permission | Used by | Without it |
|---|---|---|
| Accessibility | Scroll direction, Window Layout, the switcher, Dock Preview, Finder cut and paste, quit on close | Those features stay off |
| Screen Recording | Window titles and thumbnails in the switcher and Dock Preview | Previews fall back or stay unavailable |
| System Audio Recording | Per app volume and output routing in the mixer | Apps stay on normal system audio |
| Notifications | Keep awake, battery, Monitor and update alerts | The app stays silent |
| Full Disk Access (optional) | A deeper uninstaller scan | It scans the reachable places only |
| Administrator (once, optional) | Password free closed lid toggling | A password prompt on each toggle |

Finder cut and paste, the uninstaller and Homebrew's Terminal handoff can also ask macOS for Automation access the first time they talk to Finder or Terminal. The shelf needs no permission at all.

## What you need

- A Mac with Apple Silicon
- macOS 14 Sonoma or newer
- Xcode Command Line Tools, only if you build it yourself

### Build it yourself

```sh
git clone https://github.com/vorssaint/vorssaint-utils.git
cd vorssaint-utils
./build.sh            # compile, generate the icon and assemble the signed bundle
./build.sh --install  # the same, then install into Applications and launch
```

The [contributing guide](CONTRIBUTING.md) covers the layout and the conventions. Official Vorssaint builds come only from the maintainer. A fork has to use a different name, icon, bundle identity and signing identity, because the GPL covers the source code and not the Vorssaint name, logo or look. See [TRADEMARKS.md](TRADEMARKS.md).

## Troubleshooting

App blocked on first launch, a permission that will not take hold, or the switcher showing icons instead of thumbnails? The [troubleshooting guide](docs/TROUBLESHOOTING.md) walks through the common fixes, including how to reset permissions and remove the app cleanly.

## Uninstall

```sh
./Tools/uninstall.sh
```

The script quits the app, drops the login item, resets its privacy grants, deletes the app along with its preferences and saved state, and removes the optional closed lid rule, so nothing is left behind. You can also drag the app to the Trash and run `tccutil reset All com.vorssaint.utils` to clear its permissions.

## Documentation

- [Privacy](docs/PRIVACY.md), what does and does not leave your Mac
- [Permissions](docs/PERMISSIONS.md), every macOS permission in plain words
- [Troubleshooting](docs/TROUBLESHOOTING.md), the common fixes
- [Contributing](CONTRIBUTING.md), build, layout and conventions
- [Support](SUPPORT.md), where to get help
- [Security](SECURITY.md), how to report a vulnerability

## Contributing

Issues and pull requests are very welcome. The [contributing guide](CONTRIBUTING.md) has the build setup, the project conventions and how to add a translation or map the sensors on a new chip. For help, bug reports and feature ideas head to [support](SUPPORT.md), and to report something sensitive in private see the [security policy](SECURITY.md).

## Support the project

Vorssaint is free and it will stay that way. If it earns a place in your menu bar, a quick ⭐ helps other people find it. If you want to chip in beyond that you can [buy me a coffee](https://buymeacoffee.com/vorssaint), and either way the project lives on the community around it.

## License

The source code is licensed under [GPL 3.0 or later](LICENSE), copyright 2026 Vorssaint. That license covers the source code. The Vorssaint name, logo and look are covered on their own in [TRADEMARKS.md](TRADEMARKS.md).
