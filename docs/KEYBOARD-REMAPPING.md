# Keyboard remapping

Key remapping is an optional feature in **Settings → Remap keys**. It uses a local macOS keyboard event tap; no kernel extension, input log, or network service is involved. macOS Accessibility permission is required only when remapping is enabled and at least one valid rule is configured. The tap runs only during an active user session and is stopped when the feature is disabled or the app quits.

Each rule records one source key and can send a sequence of key combinations, type text, open an HTTP(S) link, open an installed app, or be disabled. A source key recorded without modifiers is a single-key mapping that also matches while modifiers are held and passes those modifiers through to each output. A source recorded with modifiers matches that exact modifier combination. App-specific rules match the frontmost app's bundle identifier and take priority over global rules. Bundle identifiers can be read from an app's `Info.plist` (`CFBundleIdentifier`).

Rules are stored locally as JSON in the app's preferences. Key-down and key-up events are remapped, and modifier-only source keys are handled through macOS modifier events. Keyboard-device-specific layouts and per-device rules are not configurable in this version. Rules do not alter the macOS keyboard settings or affect input before the app starts.
