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
    /// Optional menu bar icon that opens the system color panel, whose wheel
    /// and palettes tabs (including the person's own palettes) come for free.
    private var panelStatusItem: NSStatusItem?

    private init() {}

    func syncWithPreferences() {
        let wanted = AppFeature.colorPicker.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.colorPickerMenuBarIcon)
        if wanted, panelStatusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "VorssaintColorPanel"
            item.behavior = []
            item.isVisible = true
            if let button = item.button {
                let image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
                image?.isTemplate = true
                button.image = image
                button.toolTip = L10n.shared.s.colorPickerPanelName
                button.target = self
                button.action = #selector(togglePanel(_:))
            }
            panelStatusItem = item
        } else if !wanted, let item = panelStatusItem {
            NSStatusBar.system.removeStatusItem(item)
            panelStatusItem = nil
            NSColorPanel.shared.orderOut(nil)
        }
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        let panel = NSColorPanel.shared
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel(below: sender.window?.frame)
        }
    }

    /// Opens the system color panel under the menu bar icon when there is
    /// one, otherwise wherever the panel last sat.
    func showPanel(below anchor: NSRect? = nil) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        if let anchor,
           let visible = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })?.visibleFrame {
            let size = panel.frame.size
            let x = min(max(anchor.midX - size.width / 2, visible.minX), visible.maxX - size.width)
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: min(anchor.minY, visible.maxY)))
        }
        // Accessory app: activate so the hex field accepts typing.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

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
