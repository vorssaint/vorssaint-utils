// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Ties Home's row to the stored last launch and the feature catalog, kept
/// apart from its rules so they can be tested without either.
extension NotchHomeSupport {
    static func rememberTool(_ item: QuickLauncherItem, in defaults: UserDefaults = .standard) {
        remember(.tool(item.rawValue), in: defaults)
    }

    static func rememberPage(_ module: NotchModule, in defaults: UserDefaults = .standard) {
        remember(.page(module), in: defaults)
    }

    private static func remember(_ launch: Launch, in defaults: UserDefaults) {
        defaults.set(launch.stored, forKey: DefaultsKey.notchRecentLaunch)
        defaults.set(Date().timeIntervalSinceReferenceDate, forKey: DefaultsKey.notchRecentLaunchDate)
    }

    static func rail(modules: [NotchModule], now: Date = Date(), defaults: UserDefaults = .standard) -> [Slot] {
        let controls = NotchSupport.controls(in: defaults)
        let launch = defaults.string(forKey: DefaultsKey.notchRecentLaunch).flatMap(Launch.init(stored:))
        let date = (defaults.object(forKey: DefaultsKey.notchRecentLaunchDate) as? Double)
            .map(Date.init(timeIntervalSinceReferenceDate:))
        let recent = recentSlot(launch, at: date, now: now, shortcuts: controls) { launch in
            switch launch {
            case .tool(let raw):
                return modules.contains(.tools) && QuickLauncherItem(rawValue: raw)?.feature.isAvailable(in: defaults) == true
            case .page(let module):
                return modules.contains(module)
            }
        }
        return rail(controls: controls, recent: recent, toolsPage: modules.contains(.tools))
    }
}
