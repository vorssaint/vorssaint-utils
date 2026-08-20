// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Apps Selection Actions never offers itself in — a false-positive false
/// alarm in one app (a game capturing every click, a terminal with its own
/// selection model) is more annoying than the bar being unavailable there.
final class SelectionActionsExcludedApps: ObservableObject {
    static let shared = SelectionActionsExcludedApps()

    @Published private(set) var apps: [String] = []

    private init() {
        reload()
    }

    func reload() {
        let defaults = UserDefaults.standard
        let raw = defaults.stringArray(forKey: DefaultsKey.selectionActionsExcludedApps) ?? []
        let sanitized = Defaults.sanitizedBundleIdentifierList(raw)
        if raw != sanitized {
            defaults.set(sanitized, forKey: DefaultsKey.selectionActionsExcludedApps)
        }
        apps = sanitized
    }

    func add(_ bundleID: String) {
        let bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty, !apps.contains(bundleID) else { return }
        UserDefaults.standard.set(apps + [bundleID], forKey: DefaultsKey.selectionActionsExcludedApps)
        reload()
    }

    func remove(_ bundleID: String) {
        guard apps.contains(bundleID) else { return }
        UserDefaults.standard.set(apps.filter { $0 != bundleID },
                                  forKey: DefaultsKey.selectionActionsExcludedApps)
        reload()
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return apps.contains(bundleID)
    }
}
