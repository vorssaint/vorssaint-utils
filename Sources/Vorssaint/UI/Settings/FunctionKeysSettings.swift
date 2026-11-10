// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Gives the dictation (F5) and Do Not Disturb (F6) keys another job.
struct FunctionKeysSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = FunctionKeysService.shared
    @AppStorage(DefaultsKey.functionKeysMicMuteEnabled) private var micMuteEnabled = false
    @AppStorage(DefaultsKey.functionKeysSleepEnabled) private var sleepEnabled = false

    var body: some View {
        Form {
            Section(l10n.s.functionKeysName) {
                Text(l10n.s.functionKeysCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(l10n.s.functionKeysMicMuteName, isOn: $micMuteEnabled)
                    .onChange(of: micMuteEnabled) { _, enabled in changed(enabled) }
                Text(l10n.s.functionKeysMicMuteCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if micMuteEnabled, !AppFeature.micMute.isAvailable {
                    Label(l10n.s.functionKeysMicMuteCaption, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Toggle(l10n.s.functionKeysSleepName, isOn: $sleepEnabled)
                    .onChange(of: sleepEnabled) { _, enabled in changed(enabled) }
                Text(l10n.s.functionKeysSleepCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if (micMuteEnabled || sleepEnabled), service.isRunning {
                    Label(l10n.s.functionKeysName, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section {
                Label(l10n.s.functionKeysMusicNote, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(l10n.s.musicBlockTitle) {
                    SettingsRouter.shared.request(AppFeature.musicBlock.settingsDestination,
                                                  sidebarFeature: .musicBlock)
                }
            }

            if (micMuteEnabled || sleepEnabled), !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func changed(_ enabled: Bool) {
        FunctionKeysService.shared.syncWithPreferences()
        guard enabled, !permissions.accessibility else { return }
        permissions.requestAccessibility()
        permissions.openAccessibilitySettings()
    }
}
