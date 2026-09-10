# ADR 0001: Vorssaint architecture overview

- Status: accepted (observed from codebase, 2026-09-05)
- SHA: `05142d90d8239f3d022d0506048f535cececf4f4` (main)

## Context

Vorssaint is a native macOS 14+ (Apple Silicon) menu-bar toolkit: many paid-app features behind one icon, no telemetry, no external package dependencies. Build is `./build.sh` / plain `swiftc`; `Package.swift` exists for editor indexing only.

## Decision (de-facto architecture)

### Layers

| Layer | Path | Rule |
|-------|------|------|
| Entry | `Sources/Vorssaint/main.swift` | Guards, `--selftest`/`--sensors`/`--uninstall`, then `AppDelegate` |
| App | `Sources/Vorssaint/App/` | Lifecycle, status item, menu-bar render, `FeatureRuntime` |
| Core | `Sources/Vorssaint/Core/` | Catalog, defaults, permissions, localization strings |
| Services | `Sources/Vorssaint/Services/` | All behavior; `Type.shared` + Combine `ObservableObject` |
| UI | `Sources/Vorssaint/UI/` | SwiftUI only — observes services, no business logic |
| Support | `Sources/Vorssaint/Support/` | Diagnostics / uninstaller CLI paths |
| Helpers | `HIDEventSystem`, `VMStatisticsCompat`, `FanControlHelper`, `NowPlayingAdapter` | Thin system / privileged edges |

### Feature availability model

- `AppFeature` (stable string IDs) + hub install/uninstall layer **above** per-feature enable keys.
- Unavailable → torn down, not instantiated on next launch; enable keys untouched.
- `FeatureRuntime.bindings` maps features → `syncWithPreferences()` closures (lazy singletons).

### Hard constraints for contributions

1. No new dependencies without an issue first.
2. Services never import SwiftUI.
3. Prefer reuse of existing AX / permission / hotkey / file paths.
4. Direction must fit “small native utilities,” not new subsystems (see `docs/AI-CONTRIBUTIONS.md`).
5. Verify with `./build.sh`, `./build/Vorssaint --selftest`, `./build.sh --test` (UI changes need full `./build.sh`).

## Consequences

- Large surface (~436 Swift files, ~50+ service areas) but modular via hub.
- Contribution risk: duplicate work across ~open PRs/issues; always `gh pr/issue list --search` first.
- Local agent memory lives under `.agents/`, `.codebase-memory/`, `.code-review-graph/` (gitignored).
