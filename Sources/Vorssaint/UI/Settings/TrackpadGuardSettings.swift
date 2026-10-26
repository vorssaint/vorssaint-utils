// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct TrackpadGuardSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = TrackpadGuardService.shared
    @AppStorage(DefaultsKey.trackpadGuardEnabled) private var enabled = false
    private var text: TrackpadGuardStrings { FeatureStrings.trackpadGuard(l10n.language) }

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: AppFeature.trackpadGuard.symbolName, title: text.title,
                        caption: text.description) {
                Toggle(text.title, isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) { _, _ in service.syncWithPreferences() }
            }
            if enabled {
                VStack(alignment: .leading, spacing: 10) {
                    if let statusText {
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(service.status == .unavailable ? Color.orange : Color.secondary)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    AppBundleList(title: text.appsTitle, caption: "",
                        addTitle: FeatureStrings.mouseExceptions(l10n.language).addButton,
                        removeLabel: FeatureStrings.mouseExceptions(l10n.language).removeButton,
                        bundleIDs: service.apps, reachesEveryApp: true, acceptsExecutables: true,
                        onAdd: service.add, onRemove: service.remove)
                }
                .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private var statusText: String? {
        switch service.status {
        case .off, .chooseApps, .waiting: return nil
        case .ignoring: return text.ignoring
        case .unavailable: return text.unavailable
        }
    }
}
