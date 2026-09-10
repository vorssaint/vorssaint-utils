# KI: App lifecycle + menu bar

## Entry

`main.swift` → early guards (`SuperKeyMappingGuard`, mouse acceleration recovery) → CLI flags → `AppDelegate` + `NSApplication.run()`.

## Key types

| Type | File | Role |
|------|------|------|
| `AppDelegate` | `App/AppDelegate.swift` (~1.9k lines) | Launch, permissions sinks, wire services |
| `StatusItemController` | `App/StatusItemController.swift` | Menu bar item |
| `MenuBarRenderer` | `App/MenuBarRenderer.swift` | Glyph / metrics in bar |
| `FeatureRuntime` | `App/FeatureRuntime.swift` | Feature load/unload |

## Patterns

- Singletons: `Type.shared`
- State: Combine `@Published` / `ObservableObject` (no Observation macros — CLI tools build)
- Permissions: `Core/Permissions.swift` + polling via `PermissionPollingSupport`

## Build notes

- Stable local signing: `./Tools/setup-signing.sh` (TCC tied to code hash)
- Fast typecheck: `swift build`; real bundle: `./build.sh`
