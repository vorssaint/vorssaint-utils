// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// System eyedropper: picks the color of any pixel on screen with the native
/// magnifier loupe and copies it in the configured format. The clipboard
/// history keeps every picked color automatically.
final class ColorSamplerService: ObservableObject {
    static let shared = ColorSamplerService()

    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 11)
    /// The system sampler must stay referenced while its loupe is up.
    private var activeSampler: NSColorSampler?

    private init() {
        hotkey.onPress = { [weak self] in self?.pick() }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.colorPicker.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.colorPickerShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.colorPickerShortcut,
                                            fallback: .colorPickerDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut)
    }

    func suspend() {
        hotkey.unregister()
    }

    func pick() {
        guard activeSampler == nil else { return }
        let sampler = NSColorSampler()
        activeSampler = sampler
        sampler.show { [weak self] color in
            DispatchQueue.main.async {
                self?.activeSampler = nil
                guard let color else { return }
                self?.copy(color)
            }
        }
    }

    private func copy(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return }
        let format = ColorCopyFormat.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.colorPickerFormat) ?? "hex"
        )
        let value = QuickToolsSupport.colorString(red: srgb.redComponent,
                                                  green: srgb.greenComponent,
                                                  blue: srgb.blueComponent,
                                                  format: format,
                                                  bareHex: UserDefaults.standard.bool(forKey: DefaultsKey.colorPickerBareHex))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        QuickToolHUD.show(icon: "eyedropper", message: value, swatch: srgb)
    }
}
