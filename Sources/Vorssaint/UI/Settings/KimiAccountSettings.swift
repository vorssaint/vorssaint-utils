// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Kimi Code's service region, next to its provider switch. The limits reuse
/// the sign-in the official CLI already holds.
struct KimiAccountSettings: View {
    @ObservedObject private var service = KimiUsageService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsKimiRegion) private var region = KimiRegion.stored().rawValue

    private var text: KimiAccountStrings { FeatureStrings.kimiAccount(l10n.language) }

    /// The picker reads the effective region while none is chosen yet, so a
    /// detected international sign-in is already checked.
    private var regionBinding: Binding<String> {
        Binding {
            KimiRegion(rawValue: region)?.rawValue ?? KimiRegion.stored().rawValue
        } set: { newValue in
            region = newValue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text.title).font(.subheadline.weight(.medium))
            Text(text.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsMenuRow(symbol: "globe", title: text.region, selection: regionBinding) {
                Text(text.china).tag(KimiRegion.china.rawValue)
                Text(text.international).tag(KimiRegion.international.rawValue)
            }
            if let failure = service.failure {
                Text(text.failure(failure)).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(service.configured ? text.cliNote : text.notConfigured)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: region) { _, _ in
            service.regionDidChange()
            NotchService.shared.syncWithPreferences()
        }
    }
}
