// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Apps that temporarily turn off every Window Layout input while focused.
final class WindowLayoutIgnoredApps: ObservableObject {
    static let shared = WindowLayoutIgnoredApps()

    @Published private(set) var apps: [String] = []

    private init() {
        reload()
    }

    func reload() {
        let defaults = UserDefaults.standard
        let raw = defaults.stringArray(forKey: DefaultsKey.windowLayoutIgnoredApps) ?? []
        let sanitized = Defaults.sanitizedBundleIdentifierList(raw)
        if raw != sanitized {
            defaults.set(sanitized, forKey: DefaultsKey.windowLayoutIgnoredApps)
        }
        apps = sanitized
    }

    func add(_ bundleID: String) {
        let updated = Defaults.sanitizedBundleIdentifierList(apps + [bundleID])
        guard updated != apps else { return }
        UserDefaults.standard.set(updated, forKey: DefaultsKey.windowLayoutIgnoredApps)
        apps = updated
    }

    func remove(_ bundleID: String) {
        guard apps.contains(bundleID) else { return }
        UserDefaults.standard.set(apps.filter { $0 != bundleID },
                                  forKey: DefaultsKey.windowLayoutIgnoredApps)
        reload()
    }

    func contains(_ bundleID: String?) -> Bool {
        Self.contains(bundleID, in: apps)
    }

    static func contains(_ bundleID: String?, in apps: [String]) -> Bool {
        guard let bundleID else { return false }
        return apps.contains(bundleID)
    }
}
