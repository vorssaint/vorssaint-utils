# Contributing to Vorssaint

Thanks for the interest. This project aims to stay small, native and readable.

## License for contributions

Unless it is stated otherwise, contributions to this repository are accepted
under GPL-3.0-or-later.

## Getting started

```sh
git clone https://github.com/vorssaint/vorssaint-utils.git
cd vorssaint-utils
./build.sh                         # build and assemble the bundle
./build/Vorssaint --selftest       # quick health check (SELFTEST OK)
./build.sh --install               # install into /Applications and launch
```

You need macOS 14 or newer, Apple Silicon and the Xcode Command Line Tools. The
build is a plain `swiftc` invocation, see `build.sh`, with no Xcode project and
no external dependencies, reproducible by design. `Package.swift` is there so
SwiftPM aware editors can index the code.

Hitting a build or permission snag while developing? See the
[troubleshooting guide](docs/TROUBLESHOOTING.md).

### Stable signing (optional)

By default `build.sh` signs ad hoc, and that code hash changes on every build,
so macOS asks again for Accessibility and Screen Recording after each rebuild.
Run this once

```sh
./Tools/setup-signing.sh
```

to create a free, self signed identity called `Vorssaint Utils Signing` in a
dedicated keychain. `build.sh` then signs local builds with it and gives them a
constant designated requirement, so granted permissions stick across rebuilds.
It is a local convenience only and never shows up outside the keychain.

Official releases work differently. CI signs them with an Apple **Developer ID**,
from the repo secrets `SIGNING_CERT_P12` and `SIGNING_CERT_PASSWORD`, then
**notarizes** and staples them through `Tools/notarize.sh`, with secrets
`NOTARY_API_KEY_P8`, `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID`, so downloads open
with no Gatekeeper warning. `build.sh` prefers the Developer ID identity when it
is present, with the hardened runtime and `Resources/Vorssaint.entitlements`,
and falls back to the self signed identity, then to ad hoc.

## Project layout

| Folder | Role |
|---|---|
| `Sources/Vorssaint/App` | App lifecycle and the menu bar status item |
| `Sources/Vorssaint/Core` | Localization, permissions, UserDefaults keys |
| `Sources/Vorssaint/Services` | All behavior, like energy, monitor, scroll and switcher |
| `Sources/Vorssaint/UI` | SwiftUI views only, no business logic |
| `Sources/Vorssaint/Support` | `--selftest` and `--sensors` diagnostics |
| `Tools` | Icon generator and DMG packaging |

A few conventions to keep in mind.

- **UI observes services, and services never import SwiftUI.** Keep that boundary.
- Singletons are exposed as `Type.shared` and publish state with Combine through
  `ObservableObject`, with no Observation macros, since the project builds with
  the Command Line Tools.
- Comments explain *why*, not *what*. Keep them rare and useful.
- No new dependencies without talking it over first in an issue.

## Strings and translations

Every user facing string lives in `Core/Localization.swift` as a field of the
`Strings` struct. Adding a field forces **every** supported language to provide
it, and the compiler is the completeness check, so a translation can never
silently fall out of sync.

Vorssaint ships eight languages today, namely English, Português (Brasil),
Español, Deutsch, Français, Italiano, 日本語 and 简体中文. The non base
translations live in `Core/Localizations/`. To add a language, add a case to
`AppLanguage` and a `static let` extension of `Strings` with every field
translated.

## Sensors on new chips

Temperature mapping lives in `SystemMonitor.prepareSensorsIfNeeded()`. CPU keys
look like `Tp…` and `Te…`, GPU is `Tg…`, and battery runs from `TB0T` to
`TB2T`. If a new Apple Silicon generation renames the keys, run this

```sh
./build/Vorssaint --sensors
```

and open a PR with the dump and the adjusted prefixes.

## Reporting bugs and requesting features

You do not need to write code to help. Use the issue forms on the
[new issue](https://github.com/vorssaint/vorssaint-utils/issues/new/choose) page.

- **Bug report.** Include your Vorssaint version from Settings under About and
  your macOS version, plus clear steps to reproduce. The
  [troubleshooting guide](docs/TROUBLESHOOTING.md) explains what makes a report
  useful.
- **Feature request.** Describe the problem you are trying to solve rather than
  only a specific solution.

For general help and every support channel, see [support](SUPPORT.md).

## Pull requests

1. One topic per PR, with a clear description of the behavior before and after.
2. `./build.sh` must finish without warnings and `--selftest` must pass.
3. New user facing text must land in **every** supported language, since the
   build will not compile until it does.
4. Match the style of the file you are editing.

## Releases (maintainers)

```sh
git tag v2.1.0 && git push origin v2.1.0
```

The `release` workflow builds the app, packages the DMG and attaches it to a
GitHub release automatically.
