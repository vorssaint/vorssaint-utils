// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// Decoration lives below status items, accepts no input, and never covers an
/// automatically hidden menu bar. Rebuild only on preferences/topology changes.
@MainActor
final class MenuBarAppearanceController {
    private var windows: [NSPanel] = []
    private var enabled = false
    private var subscriptions: Set<AnyCancellable> = []
    private var timer: Timer?
    private var lastSignature = ""

    init() {
        for (center, name) in [(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
                               (NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification),
                               (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)] {
            center.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor in self?.rebuild() }
            }.store(in: &subscriptions)
        }
    }

    func sync(enabled: Bool) {
        self.enabled = enabled && UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerAppearance)
        rebuild()
        timer?.invalidate()
        timer = nil
        guard self.enabled else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func rebuild() {
        let defaults = UserDefaults.standard
        let segments: [CGRect] = enabled ? NSScreen.screens.flatMap { screen -> [CGRect] in
            // visibleFrame reserves the menu bar only while it is persistent.
            guard screen.frame.maxY - screen.visibleFrame.maxY >= NSStatusBar.system.thickness - 2 else { return [] }
            if defaults.bool(forKey: DefaultsKey.menuBarOrganizerSplit),
               let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                return [left, right]
            }
            return [CGRect(x: screen.frame.minX, y: screen.frame.maxY - NSStatusBar.system.thickness,
                           width: screen.frame.width, height: NSStatusBar.system.thickness)]
        } : []
        let style = MenuBarAppearanceStyle(defaults: defaults)
        let signature = segments.map(NSStringFromRect).joined(separator: ";") + String(describing: style)
        guard signature != lastSignature else { return }
        lastSignature = signature
        windows.forEach { $0.close() }
        windows = segments.map { frame in
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = style.shadow
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: MenuBarAppearancePreview(style: style))
            panel.orderFrontRegardless()
            return panel
        }
    }
}

struct MenuBarAppearanceStyle: CustomStringConvertible {
    let first: String
    let second: String
    let opacity: Double
    let gradient: Bool
    let border: Bool
    let shadow: Bool
    let rounded: Bool
    var description: String { "\(first)|\(second)|\(opacity)|\(gradient)|\(border)|\(shadow)|\(rounded)" }

    init(defaults: UserDefaults = .standard) {
        first = MenuBarUsageBarSupport.sanitizedColorHex(defaults.string(forKey: DefaultsKey.menuBarOrganizerFirstColor), fallback: "#303038")
        second = MenuBarUsageBarSupport.sanitizedColorHex(defaults.string(forKey: DefaultsKey.menuBarOrganizerSecondColor), fallback: "#606070")
        let raw = defaults.double(forKey: DefaultsKey.menuBarOrganizerOpacity)
        opacity = raw.isFinite ? min(1, max(0, raw)) : 0.25
        gradient = defaults.bool(forKey: DefaultsKey.menuBarOrganizerGradient)
        border = defaults.bool(forKey: DefaultsKey.menuBarOrganizerBorder)
        shadow = defaults.bool(forKey: DefaultsKey.menuBarOrganizerShadow)
        rounded = defaults.bool(forKey: DefaultsKey.menuBarOrganizerRounded)
    }

    static func color(_ hex: String) -> Color {
        let rgb = MenuBarUsageBarSupport.rgb(for: hex, fallback: "#303038")
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

struct MenuBarAppearancePreview: View {
    let style: MenuBarAppearanceStyle
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.rounded ? 10 : 0)
        shape.fill(LinearGradient(colors: [MenuBarAppearanceStyle.color(style.first),
                                            MenuBarAppearanceStyle.color(style.gradient ? style.second : style.first)],
                                  startPoint: .leading, endPoint: .trailing))
            .opacity(style.opacity)
            .overlay { if style.border { shape.stroke(.primary.opacity(0.4), lineWidth: 1) } }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
