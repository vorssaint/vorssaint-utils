# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and run

```sh
./build.sh                  # compile, generate icon, assemble signed bundle → build/stage/Vorssaint.app
./build.sh --install        # same, then install to /Applications and launch
./build.sh --dev            # build "Vorssaint (Developer)" variant — distinct bundle ID so it coexists with the release app
./build.sh --test           # compile and run unit tests (fast, no Xcode required)
./build/Vorssaint --selftest  # quick health check after building; should print "SELFTEST OK"
./build/Vorssaint --sensors   # dump raw SMC sensor keys — useful when mapping sensors on new Apple Silicon chips
```

The build is a plain `swiftc` invocation with no Xcode project and no external dependencies. `Package.swift` exists only so SwiftPM-aware editors can index the code.

### Stable signing (optional, recommended for active development)

Each ad-hoc build gets a new code hash, so macOS re-prompts for Accessibility and Screen Recording after every rebuild. Run once to create a persistent local identity:

```sh
./Tools/setup-signing.sh
```

## Architecture

This is a macOS menu bar app (LSUIElement, Apple Silicon, macOS 14+) built with AppKit + SwiftUI and Combine.

**The core rule: UI observes services; services never import SwiftUI.**

### Layer structure

| Layer | Path | Role |
|---|---|---|
| App | `Sources/Vorssaint/App/` | App lifecycle, `NSPopover`, menu bar status item |
| Core | `Sources/Vorssaint/Core/` | `Defaults` (UserDefaults keys), `Localization`, permissions |
| Services | `Sources/Vorssaint/Services/` | All behavior — audio, switcher, keep-awake, shelf, metrics, etc. |
| UI | `Sources/Vorssaint/UI/` | SwiftUI views only, no business logic |
| Support | `Sources/Vorssaint/Support/` | `--selftest` and `--sensors` diagnostics |

### Key patterns

- **Singletons** are exposed as `Type.shared` and publish state via Combine `ObservableObject`. The project avoids `@Observable` macros because it builds with the Command Line Tools (not full Xcode).
- **Feature services** each have a `syncWithPreferences()` method called at startup that reads `UserDefaults` and activates or deactivates themselves. See `AppDelegate.applicationDidFinishLaunching`.
- **UserDefaults keys** live as string constants in `Core/Defaults.swift` — always use those, never raw strings.

### Localization

Every user-facing string is a field on the `Strings` struct in `Core/Localization.swift`. Adding a field requires adding it to every supported language file in `Core/Localizations/` — the build fails until all languages are complete. Eight languages ship today: English, Português (Brasil), Español, Deutsch, Français, Italiano, 日本語, 简体中文.

### Tests

Tests live in `Tests/MetricsTests.swift` and cover pure helpers (metric formatting, URL cleaning, localization contracts, defaults). They are compiled and run with `./build.sh --test` — no XCTest, no Xcode required.

## Conventions

- Comments explain *why*, not *what*. Keep them rare.
- No new dependencies without opening an issue first.
- PRs must pass `./build.sh` with no warnings and `--selftest` must pass.
- Any new user-facing text must be added to all eight language files or the build will not compile.
