# Vorssaint

> The free, open-source toolkit that replaces several paid Mac utilities.

[![Release](https://img.shields.io/github/v/release/vorssaint/vorssaint-utils?label=release)](https://github.com/vorssaint/vorssaint-utils/releases)
[![CI](https://github.com/vorssaint/vorssaint-utils/actions/workflows/ci.yml/badge.svg)](https://github.com/vorssaint/vorssaint-utils/actions/workflows/ci.yml)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B%20(Apple%20Silicon)-black)](#requirements)
[![License: PolyForm NC](https://img.shields.io/badge/license-PolyForm%20Noncommercial-blue)](LICENSE)

*Leia em [Português (Brasil)](docs/README.pt-BR.md).*

One small menu bar app that does the jobs you'd otherwise buy a handful of
separate utilities for: keep your Mac awake, see what's slowing it down, set the
volume per app, switch windows and tabs, and fix a few everyday annoyances.

**Free. Open source. Local.** No account, no subscription, no telemetry, no AI.
Nothing leaves your Mac except an update check you can turn off. It's native
(SwiftUI + AppKit), not Electron, so it stays small and quick.

## What it does

Every feature is optional and has its own page in Settings.

### 🌡️ See what's slowing your Mac down
CPU, GPU and battery temperatures, live CPU/GPU load and memory pressure, right
in the menu bar. Tap any reading to see which apps are behind it.

### 🎚️ Set the volume per app
Turn Safari down without touching Spotify or Zoom. The per-app mixer macOS never
shipped, with a live dot on whatever is playing. (macOS 14.4 and later.)

### 🪟 Jump to any window instantly
Replace ⌘Tab with a grid of live window thumbnails, every browser tab as its own
entry, and a quick flick that toggles straight back to where you were.

### ⚡ Keep your Mac awake on demand
For a download, a build or a presentation: on a timer or until you stop it, even
with the lid closed. Battery protection switches it off when the charge runs low.

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

### 📥 A shelf to carry files around
A floating tray, summoned at the cursor, that holds files, images, text and
links so you can drag them between apps, windows and Spaces.

## Why it's built this way

- **Free and open source**, under a noncommercial license. No paywalled tiers.
- **Local by default.** No account, no sign-in, no telemetry. The only network
  call checks GitHub for a new version, and you can turn it off.
- **Native and light.** Plain SwiftUI + AppKit, no external dependencies, a
  single small app instead of several.
- **Opt-in by design.** Each feature is off until you turn it on, asks for a
  permission only when it needs one, and degrades gracefully without it.

## Install

### Download (recommended)
Grab the latest DMG from [**Releases**](https://github.com/vorssaint/vorssaint-utils/releases),
open it and drag **Vorssaint** into **Applications**.

> **Opening it the first time.** Vorssaint is signed but not notarized by Apple
> (notarization needs a paid Apple Developer account), so macOS shows a security
> warning on the first launch. It's open source: you can read every line here or
> build it yourself. To open it, do one of these once:
>
> - Open **System Settings › Privacy & Security**, scroll to **Security**, and
>   click **Open Anyway** next to Vorssaint.
> - Or, in Terminal: `xattr -dr com.apple.quarantine "/Applications/Vorssaint Utils.app"`
>
> Updates installed from inside the app don't show this, and a stable signing
> identity keeps your granted permissions across updates.

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

Cut & paste, the switcher tabs and the uninstaller also ask macOS for Automation
consent the first time they talk to Finder or a browser. The shelf needs no
permissions.

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
Sources/VorssaintUtils/
├── main.swift                  # entry point (--selftest, --sensors)
├── App/                        # AppDelegate, menu bar status item
├── Core/                       # localization (pt-BR/en-US), permissions, defaults
├── Services/                   # all behavior: energy, monitor, scroll, switcher,
│                               #   audio mixer, Finder, auto-quit, uninstall, shelf
├── Support/                    # selftest & sensor dump
└── UI/                         # SwiftUI: panel, settings, onboarding, switcher, shelf
```

Strict separation: **UI** observes **services**. Every user-facing string lives
in `Core/Localization.swift`, compiler-checked for both languages.

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md) for
the build setup, project conventions and how to add a translation or port the
sensor mapping to a new chip.

## License

[PolyForm Noncommercial License 1.0.0](LICENSE), © 2026 Vorssaint. Free to use,
modify and share for any **noncommercial** purpose, with attribution. Commercial
use is not permitted.
