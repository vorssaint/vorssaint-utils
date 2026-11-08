// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

extension Color {
    /// Paints a stored app accent `#RRGGBB`. The value is validated by
    /// `AppAccentColor` before it reaches a view, so the fallback used here is
    /// only what the shared hex reader requires.
    init(appAccentHex hex: String) {
        let rgb = MenuBarUsageBarSupport.rgb(for: hex, fallback: MenuBarUsageBarSupport.defaultNormalColor)
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Applies the user's chosen accent colour to a window's view tree.
///
/// `Color.accentColor` is not something SwiftUI lets a view set for the whole
/// app on macOS, and the app has no asset catalog to hold an `AccentColor`
/// entry, so a chosen colour is published through SwiftUI's accent-colour
/// environment instead: measured on macOS 26, `.accentColor(_:)` reaches a
/// `Color.accentColor` drawn by a descendant `NSHostingView`, while `.tint(_:)`
/// only reaches `.tint`-derived styles. Every window root therefore goes
/// through this modifier once, and the several hundred `Color.accentColor`
/// call sites keep working untouched.
///
/// While no colour is chosen the modifier adds nothing the view tree can
/// observe, so the app follows the Mac exactly as before.
struct AppAccentTint: ViewModifier {
    @ObservedObject private var appearance = AppAppearanceController.shared

    func body(content: Content) -> some View {
        if let hex = appearance.accentColorHex {
            content.accentColor(Color(appAccentHex: hex))
        } else {
            content
        }
    }
}

extension View {
    /// Wraps a window's root view so it follows the app accent colour.
    func appAccentTint() -> some View {
        modifier(AppAccentTint())
    }
}
