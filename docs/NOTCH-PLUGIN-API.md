# Notch plugin API

The first plugin API lets a statically compiled integration add an action to
the notch's Controls page. Plugins are ordinary Swift code compiled into
Vorssaint; the app does not load or execute external code at runtime.

## Define and register an action

Conform to `NotchPlugin` and register the instance with
`NotchPluginRegistry.shared` during app startup, before the notch opens:

```swift
@MainActor
struct BuildStatusPlugin: NotchPlugin {
    let identifier = "example.build-status"
    let title = "Build status"
    let symbol = "checkmark.circle"

    func perform() {
        // Run the integration's action.
    }
}

// In applicationDidFinishLaunching, before FeatureRuntime.shared.syncAtLaunch():
NotchPluginRegistry.shared.register(BuildStatusPlugin())
```

`identifier` must be a unique, nonempty string of at most 128 UTF-8 bytes
containing only letters, numbers, `.`, `-` or `_`. `title` must be nonblank,
contain no control characters, and fit in 96 UTF-8 bytes. `symbol` must fit in
64 UTF-8 bytes, contain only letters, numbers, `.` or `-`, and resolve to an SF
Symbol available on the current macOS version. Invalid entries and duplicate
identifiers are rejected: `register(_:)` returns `false`; accepted entries
return `true` and retain their registration order.

Registered actions appear as tiles in a horizontally scrollable row on the
Controls page. `NotchPluginRegistry` publishes changes to its
`plugins` collection, so registrations made while the app is running appear
without restarting.

This API is a source-level integration point, not a standalone binary SDK or
dynamic plugin loader. Integrations must be included in the app build and
registered by its startup code. The plugin action runs on the main actor and
is responsible for its own permissions, work and errors.
