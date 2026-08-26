// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Applies the user's light/dark choice to every window the app owns.
///
/// One assignment covers the whole app: panels, Settings, overlays and any
/// window opened later inherit it, so there is nothing to observe and nothing
/// to keep running. The menu bar item is deliberately left out: measured on
/// macOS 27, status bar windows keep the appearance the system gives them
/// (vibrant, tied to the menu bar) and ignore the app override, so the icon and
/// the readings keep following the menu bar over any wallpaper.
final class AppAppearanceController: ObservableObject {
    static let shared = AppAppearanceController()

    @Published var appearance: AppAppearance {
        didSet {
            guard appearance != oldValue else { return }
            UserDefaults.standard.set(appearance.rawValue, forKey: DefaultsKey.appearance)
            apply()
        }
    }

    @Published var liquidGlassEnabled: Bool {
        didSet {
            guard liquidGlassEnabled != oldValue else { return }
            UserDefaults.standard.set(liquidGlassEnabled, forKey: DefaultsKey.liquidGlassEnabled)
        }
    }

    private init() {
        appearance = AppAppearance.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.appearance)
        )
        liquidGlassEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.liquidGlassEnabled)
    }

    /// The panel is a popover anchored to the menu bar item, so it takes its
    /// appearance from that status bar window instead of from the app and has
    /// to be told separately. Measured on macOS 27.
    private weak var panel: NSPopover?

    /// Called once at launch, before any window exists, and again on every
    /// change from Settings.
    func apply() {
        NSApp.appearance = nsAppearance
        panel?.appearance = nsAppearance
    }

    /// Registers the menu bar panel so it follows the choice too.
    func follow(panel popover: NSPopover) {
        panel = popover
        popover.appearance = nsAppearance
    }

    private var nsAppearance: NSAppearance? {
        switch appearance {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}
