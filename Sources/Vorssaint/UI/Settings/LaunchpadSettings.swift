// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct LaunchpadSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = LaunchpadService.shared
    @AppStorage(DefaultsKey.launchpadShortcutEnabled) private var shortcutEnabled = true
    @AppStorage(DefaultsKey.launchpadStyle) private var styleRaw = LaunchpadSupport.Style.fullScreen.rawValue
    @State private var confirmingReset = false

    private var strings: LaunchpadFeatureStrings { FeatureStrings.launchpad(l10n.language) }

    var body: some View {
        Form {
            Section {
                Button {
                    LaunchpadService.shared.show()
                } label: {
                    Label(strings.openButton, systemImage: AppFeature.launchpad.symbolName)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(strings.caption)
                    Text(strings.editHint).foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Picker(strings.styleTitle, selection: $styleRaw) {
                    ForEach(LaunchpadSupport.Style.allCases, id: \.rawValue) { style in
                        Text(strings.title(style)).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(strings.pageTitle)
            }

            Section {
                Toggle(l10n.s.quickToolShortcutToggle, isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _, _ in service.syncWithPreferences() }
                ShortcutPreferenceRow(role: .launchpad, isEnabled: shortcutEnabled) {
                    service.syncWithPreferences()
                }
                if shortcutEnabled, service.shortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button(strings.addToDock) {
                    let added = LaunchpadDockIcon.install()
                    QuickToolHUD.show(icon: added ? "checkmark.circle" : "exclamationmark.triangle",
                                      message: added ? strings.dockAdded : strings.dockFailed)
                }
                Text(strings.dockCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(strings.dockTitle)
            }

            Section {
                Button(strings.resetLayout, role: .destructive) { confirmingReset = true }
                    .confirmationDialog(strings.resetLayout, isPresented: $confirmingReset) {
                        Button(strings.resetLayout, role: .destructive) { service.resetLayout() }
                        Button(strings.cancel, role: .cancel) {}
                    } message: {
                        Text(strings.resetLayoutMessage)
                    }
            }
        }
        .formStyle(.grouped)
    }
}
