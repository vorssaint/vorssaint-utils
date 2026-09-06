// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// How the internal-battery charge reading appears in the menu bar when that
/// metric is enabled. The default keeps the familiar glyph beside the percent;
/// hide-icon drops the glyph so only the charge text occupies the slot.
enum MenuBarBatteryPresentation: Equatable {
    case iconAndPercent
    case percentOnly

    static func resolve(hideIcon: Bool) -> MenuBarBatteryPresentation {
        hideIcon ? .percentOnly : .iconAndPercent
    }

    static var current: MenuBarBatteryPresentation {
        resolve(hideIcon: UserDefaults.standard.bool(forKey: DefaultsKey.menuBarBatteryHideIcon))
    }

    var showsIcon: Bool { self == .iconAndPercent }

    /// Character-width budget for the dense status title layout. Percent-only
    /// needs less room without the SF Symbol column.
    var denseWidthUnits: Int {
        showsIcon ? 11 : 6
    }

    /// Clamped charge string shared by dense and block layouts.
    static func percentText(percent: Int) -> String {
        "\(max(0, min(100, percent)))%"
    }

    /// Dense-mode body after an optional symbol. With the icon, keep the
    /// existing "BAT 85%" label; without it, show the bare percent so the
    /// slot stays as compact as the request asks for. Charging state is not
    /// re-encoded here — without the bolt glyph it is less visible on purpose.
    func denseBodyText(percent: Int) -> String {
        let value = Self.percentText(percent: percent)
        return showsIcon ? "BAT " + value : value
    }
}
