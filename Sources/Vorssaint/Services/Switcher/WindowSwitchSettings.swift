// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum WindowSwitchMinimizedPlacement: String, CaseIterable {
    case normal
    case end
    case hidden
}

enum WindowSwitchSortMode: String, CaseIterable {
    case activationMRU
}

struct WindowSwitchSettings {
    var minimizedPlacement: WindowSwitchMinimizedPlacement = .normal
    var showFullscreenWindows = true
    var sortMode: WindowSwitchSortMode = .activationMRU

    static func load(from defaults: UserDefaults = .standard) -> WindowSwitchSettings {
        WindowSwitchSettings(
            minimizedPlacement: WindowSwitchMinimizedPlacement(
                rawValue: defaults.string(forKey: DefaultsKey.switcherMinimizedPlacement) ?? ""
            ) ?? .normal,
            showFullscreenWindows: defaults.object(forKey: DefaultsKey.switcherShowFullscreenWindows) as? Bool ?? true,
            sortMode: .activationMRU
        )
    }
}
