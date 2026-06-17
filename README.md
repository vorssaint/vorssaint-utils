# Vorssaint

> The free, open-source toolkit that replaces several paid Mac utilities.

[![Release](https://img.shields.io/github/v/release/vorssaint/vorssaint-utils?label=release)](https://github.com/vorssaint/vorssaint-utils/releases)
[![CI](https://github.com/vorssaint/vorssaint-utils/actions/workflows/ci.yml/badge.svg?branch=main&event=push)](https://github.com/vorssaint/vorssaint-utils/actions/workflows/ci.yml)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B%20(Apple%20Silicon)-black)](#requirements)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue)](LICENSE)

*Leia em [Português (Brasil)](docs/README.pt-BR.md).*

<p align="center">🇺🇸 🇧🇷 🇪🇸 🇩🇪 🇫🇷 🇮🇹 🇯🇵 🇨🇳</p>
<p align="center"><sub>The interface speaks 8 languages, switchable anytime in Settings.</sub></p>

If Vorssaint is useful to you, a quick ⭐ means a lot and helps others find the project. It is, and always will be, 100% free with no subscription; community support is what keeps it alive, so if you'd like to chip in you can [buy me a coffee](https://buymeacoffee.com/vorssaint) ☕.

One small menu bar app that does the jobs you'd otherwise buy a handful of
separate utilities for: keep your Mac awake, see what's slowing it down, set the
volume per app, switch windows, carry files between apps, remove leftovers and
fix a few everyday annoyances.

**Free. Open source. Local.** No account, no subscription, no telemetry.
Nothing leaves your Mac except an update check you can turn off. It's built
with native macOS frameworks, so it stays small and quick.

**Install with [Homebrew](https://brew.sh):**

```sh
brew install --cask vorssaint/tap/vorssaint
```

Already have Vorssaint installed? Adopt your copy into Homebrew with no reinstall: `brew install --cask --adopt vorssaint/tap/vorssaint`. You can also [download the .dmg](https://github.com/vorssaint/vorssaint-utils/releases).

<p align="center">
  <img src="docs/demo.gif" alt="Vorssaint running from the menu bar with live metrics and the compact section-based panel" width="780">
</p>

## What it does

Features are configurable from Settings or directly from the panel.

### 🌡️ See what's slowing your Mac down
CPU, GPU and battery temperatures, live CPU/GPU load, memory pressure, uptime,
battery health and cycles, network speed and totals, power draw and history
graphs. Pin CPU, GPU, RAM, Network, Power or Battery right in the menu bar.

### 🎚️ Set the volume per app
Turn one app down without changing the rest of your Mac. The per-app mixer macOS
never shipped, with a live dot on whatever is playing. (macOS 14.4 and later.)

### 🪟 Jump to any window instantly
Replace ⌘Tab with a grid of live window thumbnails, including multiple windows of
the same app, and a quick flick that toggles straight back to the last one you used.

### ⚡ Keep your Mac awake on demand
For a download, a build or a presentation: on a timer or until you stop it, even
with the lid closed. Battery protection switches it off when the charge runs low.

### 📥 Carry files with the Shelf
A floating tray, summoned at the cursor, that holds files, images, text and
links so you can drag them between apps, windows and Spaces. Drop several files
at once to keep them as a batch, or add loose items into an existing stack.

### 🧭 Keep the panel compact
Switch between the full list and a section-based panel with one click. Sections
stay at the top, the panel grows only as much as the active section needs, and
Cleaning Mode lives in its own Utilities section.

### 🧼 Clean the keyboard safely
Cleaning Mode locks the keyboard for a quick wipe-down, then unlocks from the
overlay, a repeated-key gesture, or automatically after a short timeout.

### 🖱️ Fix the mouse scroll direction
Invert the mouse wheel without touching the trackpad's natural scrolling.

### ✂️ Move files in Finder with ⌘X / ⌘V
Cut files and folders and paste them into another folder: the move Finder leaves
out. Text fields keep their normal shortcuts.

### ❌ Close the last window, quit the app
When an app's last window closes, it quits and frees its memory, with a per-app
exception list for the apps you'd rather keep running.

### 🗑️ Remove an app and everything it left behind
Drop an app onto Settings to find its caches, preferences, logs and other
leftovers, review the list, and send it all to the Trash.

### 🧪 Fan Control beta
A beta Fan Control entry is available for testing. Manual controls stay disabled
until Mac models are validated safely.

## Why it's built this way

- **Free and open source**, under GPL-3.0-or-later. No paywalled tiers.
- **Local by default.** No account, no sign-in, no telemetry. The only network
  call checks GitHub for a new version, and you can turn it off.
- **Native and light.** Plain SwiftUI + AppKit, no external dependencies, a
  single small app instead of several.
- **Optional by design.** Features can be adjusted or disabled, ask for a
  permission only when they need one, and degrade gracefully without it.

## Install

### Homebrew (recommended)
```sh
brew install --cask vorssaint/tap/vorssaint
```
Already have Vorssaint installed and don't want to reinstall it? Adopt your
existing copy into Homebrew instead:
```sh
brew install --cask --adopt vorssaint/tap/vorssaint
```
After that, updates arrive with `brew upgrade --cask vorssaint`.

### Download
Grab the latest DMG from [**Releases**](https://github.com/vorssaint/vorssaint-utils/releases),
open it and drag **Vorssaint** into **Applications**.

Vorssaint is signed with a Developer ID and notarized by Apple, so it opens
normally with no security warning. The stable signing identity also keeps your
granted permissions across updates.

### Official builds and forks
Official Vorssaint builds are distributed only by the project maintainer.
Unofficial forks must use a different name, icon, bundle identifier and signing
identity. The GPL license covers the source code only and does not grant
permission to use the Vorssaint name, logo, icon, bundle identity, trade dress
or official branding. See [TRADEMARKS.md](TRADEMARKS.md).

### Build from source
```sh
git clone https://github.com/vorssaint/vorssaint-utils.git
cd vorssaint-utils
./build.sh            # compile, generate the icon, assemble the signed bundle
./build.sh --install  # same, then install into /Applications and launch
```

### Requirements
- macOS 14 (Sonoma) or newer
- Apple Silicon
- Xcode Command Line Tools (to build from source)

## Permissions

Everything is optional: features degrade gracefully and the onboarding walks you
through each grant.

| Permission | Used by | Without it |
|---|---|---|
| **Accessibility** | Scroll inverter, switcher keyboard, cut & paste, quit on close | Those features stay off |
| **Screen Recording** | Window titles & thumbnails in the switcher | Switcher shows app icons only |
| **Notifications** | Session end & battery protection alerts | Silent operation |
| **Full Disk Access** (optional) | A more thorough uninstaller scan | Scans the accessible locations only |
| **Administrator** (once, optional) | Password-free closed-lid toggling | Password prompt per toggle |

Cut & paste and the uninstaller also ask macOS for Automation consent the first
time they talk to Finder. The shelf needs no permissions.

The first launch opens a short, guided onboarding (language, permissions and an
opt-in page per feature). Revisit it anytime from **Settings › About**.

## Uninstall

```sh
./Tools/uninstall.sh   # from a clone, or download it from the repo
```
It quits the app, unregisters the login item, resets its Accessibility and
Screen Recording permissions, deletes the app, preferences and saved state, and
removes the optional closed-lid `sudoers` rule, leaving nothing behind. Or drag
the app to the Trash and run `tccutil reset All com.vorssaint.utils` to clear
its permissions.

## Architecture

```
Sources/Vorssaint/
├── main.swift                  # entry point (--selftest, --sensors)
├── App/                        # AppDelegate, menu bar status item
├── Core/                       # localization, permissions, defaults
├── Services/                   # all behavior: energy, monitor, scroll, switcher,
│                               #   audio mixer, Finder, auto-quit, uninstall, shelf
├── Support/                    # selftest & sensor dump
└── UI/                         # SwiftUI: panel, settings, onboarding, switcher, shelf
```

Strict separation: **UI** observes **services**. Every user-facing string lives
in `Core/Localization.swift`, compiler-checked for every supported language.

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md) for
the build setup, project conventions and how to add a translation or port the
sensor mapping to a new chip.

## License

The source code is licensed under [GPL-3.0-or-later](LICENSE), copyright
© 2026 Vorssaint. The license covers source code only. Vorssaint branding is
covered separately in [TRADEMARKS.md](TRADEMARKS.md).
