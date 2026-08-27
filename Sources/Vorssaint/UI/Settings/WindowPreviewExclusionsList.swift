// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct WindowPreviewExclusionsList: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var apps: [String] = Self.savedApps

    private var text: WindowPreviewExclusionStrings {
        FeatureStrings.windowPreviewExclusions(l10n.language)
    }

    var body: some View {
        AppBundleList(title: text.listTitle,
                      caption: text.caption,
                      addTitle: text.addButton,
                      removeLabel: text.removeButton,
                      bundleIDs: apps,
                      onAdd: { save(apps + [$0]) },
                      onRemove: { bundleID in save(apps.filter { $0 != bundleID }) })
    }

    private static var savedApps: [String] {
        Defaults.sanitizedBundleIdentifierList(
            UserDefaults.standard.stringArray(forKey: DefaultsKey.windowPreviewExcludedApps) ?? [])
    }

    private func save(_ bundleIDs: [String]) {
        let sanitized = Defaults.sanitizedBundleIdentifierList(bundleIDs)
        UserDefaults.standard.set(sanitized, forKey: DefaultsKey.windowPreviewExcludedApps)
        apps = sanitized
    }
}
