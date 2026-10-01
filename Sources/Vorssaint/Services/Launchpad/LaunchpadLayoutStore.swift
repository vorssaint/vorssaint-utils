// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The single `UserDefaults` blob Launchpad Classic's arrangement lives in,
/// the same versioned-JSON-in-one-key shape `NotchQuickAccessConfiguration`
/// already establishes for the Dynamic Island's quick-access buttons.
enum LaunchpadLayoutStore {
    private static let maximumEncodedSize = 65_536

    static func stored(in defaults: UserDefaults = .standard) -> LaunchpadLayout {
        guard let data = defaults.data(forKey: DefaultsKey.launchpadLayout), !data.isEmpty,
              data.count <= maximumEncodedSize,
              let value = try? JSONDecoder().decode(LaunchpadLayout.self, from: data)
        else { return .initial }
        return LaunchpadLayoutSupport.sanitized(value)
    }

    static func save(_ layout: LaunchpadLayout, in defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = (try? encoder.encode(LaunchpadLayoutSupport.sanitized(layout))) ?? Data()
        defaults.set(encoded, forKey: DefaultsKey.launchpadLayout)
    }
}
