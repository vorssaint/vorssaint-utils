// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// AppKit draws the shelf's material without capturing the screen. Appearance
/// changes are event-driven; AppKit also handles Reduce Transparency.
final class MenuBarHiddenBarAppearance {
    let view: NSView
    let contentView: NSView
    private weak var anchor: NSStatusBarButton?
    private weak var panel: NSPanel?
    private var appearanceObservation: NSKeyValueObservation?
    private var themeObserver: NSObjectProtocol?

    init(frame: CGRect, anchor: NSStatusBarButton?) {
        self.anchor = anchor
        let bounds = CGRect(origin: .zero, size: frame.size)
        contentView = NSView(frame: bounds)
        contentView.autoresizingMask = [.width, .height]
#if compiler(>=6.2)
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .clear
            glass.cornerRadius = 12
            glass.contentView = contentView
            view = glass
        } else {
            view = Self.material(frame: bounds, content: contentView)
        }
#else
        view = Self.material(frame: bounds, content: contentView)
#endif
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
    }

    private static func material(frame: CGRect, content: NSView) -> NSView {
        let effect = NSVisualEffectView(frame: frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.addSubview(content)
        return effect
    }

    func follow(panel: NSPanel) {
        stop()
        self.panel = panel
        appearanceObservation = anchor?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.update()
        }
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in self?.update() }
        update()
    }

    func stop() {
        appearanceObservation?.invalidate()
        appearanceObservation = nil
        if let themeObserver { DistributedNotificationCenter.default().removeObserver(themeObserver) }
        themeObserver = nil
        panel = nil
    }

    private func update() {
        guard let panel else { return }
        // Status windows follow macOS even when Vorssaint's windows use a
        // user-selected light/dark override. The shelf must follow the bar.
        panel.appearance = anchor?.effectiveAppearance ?? NSAppearance(named:
            UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .darkAqua : .aqua)
    }

    deinit { stop() }
}
