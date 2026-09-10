# KI: FeatureRuntime + AppFeature

## What

Hub install/uninstall gate. Availability keys separate from enable keys.

## Where

- `Sources/Vorssaint/Core/FeatureCatalog.swift` — `AppFeature`, `FeatureGroup`, `AppPermission`
- `Sources/Vorssaint/App/FeatureRuntime.swift` — bindings, `syncAtLaunch`, presets

## How to change

1. Add `AppFeature` case (never rename raw values).
2. Assign `group` / strings / hub UI.
3. Add `FeatureRuntime.bindings` entry calling `Service.shared.syncWithPreferences()`.
4. Wire Settings + menu panel only if feature should appear when available.

## Gotchas

- Uninstall mid-session stops work immediately; singleton unload needs relaunch (`needsRestartToUnload`).
- Hardware gate (`isHardwareSupported`) can refuse install but never revoke existing install.
- On-demand tools (OCR, cleaning mode, screenshot, command bar, recorder) often skip permission polling.
