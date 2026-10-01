// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct LaunchpadSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.launchpadShortcutEnabled) private var shortcutEnabled = false
    @AppStorage(DefaultsKey.launchpadPinchEnabled) private var pinchEnabled = false
    @State private var showingResetConfirm = false

    private var text: LaunchpadStrings { FeatureStrings.launchpad(l10n.language) }

    var body: some View {
        Form {
            Section {
                Button(text.openButton) { LaunchpadService.shared.show() }
                Text(text.hubDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(text.shortcutToggle, isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { LaunchpadService.shared.syncWithPreferences() }
                ShortcutPreferenceRow(role: .launchpad, isEnabled: shortcutEnabled, symbolName: "keyboard") {
                    LaunchpadService.shared.syncWithPreferences()
                }

                Toggle(text.pinchToggle, isOn: $pinchEnabled)
                    .onChange(of: pinchEnabled) { LaunchpadService.shared.syncWithPreferences() }

                Button(text.resetLayoutButton) { showingResetConfirm = true }
                    .confirmationDialog(
                        text.resetLayoutConfirmTitle,
                        isPresented: $showingResetConfirm,
                        titleVisibility: .visible
                    ) {
                        Button(text.resetLayoutConfirmTitle, role: .destructive) {
                            UserDefaults.standard.removeObject(forKey: DefaultsKey.launchpadLayout)
                        }
                    } message: {
                        Text(text.resetLayoutConfirmMessage)
                    }
            }
        }
        .formStyle(.grouped)
        .onAppear { LaunchpadService.shared.syncWithPreferences() }
    }
}
