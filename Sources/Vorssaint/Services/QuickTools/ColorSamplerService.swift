// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Picks the color of any pixel from the shared capture surface and copies it
/// in the configured format. The native sampler remains the permission-free
/// fallback. Clipboard history keeps every picked color automatically.
final class ColorSamplerService: ObservableObject {
    static let shared = ColorSamplerService()

    /// The system sampler must stay referenced while its loupe is up.
    private var activeSampler: NSColorSampler?

    private init() {}

    func pick() {
        ScreenCaptureService.shared.capture(initial: .color)
    }

    func pickNative() {
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

    func receiveUnifiedColor(_ color: NSColor) {
        copy(color)
    }

    /// The string the configured copy format would produce for this color,
    /// so a preview (the capture loupe's readout bar) can show exactly what
    /// a copy will put on the pasteboard.
    func formattedValue(_ color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        let format = ColorCopyFormat.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.colorPickerFormat) ?? "hex"
        )
        return QuickToolsSupport.colorString(red: srgb.redComponent,
                                             green: srgb.greenComponent,
                                             blue: srgb.blueComponent,
                                             format: format,
                                             bareHex: UserDefaults.standard.bool(forKey: DefaultsKey.colorPickerBareHex))
    }

    /// Copies without the HUD. The capture surface calls this while its
    /// shielding-level panels are still up, where the HUD would be invisible,
    /// and shows its own confirmation instead.
    @discardableResult
    func copyQuietly(_ color: NSColor) -> String? {
        guard let value = formattedValue(color) else { return nil }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        return value
    }

    private func copy(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB),
              let value = copyQuietly(color)
        else { return }
        QuickToolHUD.show(icon: "eyedropper", message: value, swatch: srgb)
    }
}
