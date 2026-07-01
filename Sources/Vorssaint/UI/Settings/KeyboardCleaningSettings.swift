// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct KeyboardCleaningSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var cleaning = CleaningModeManager.shared
    @AppStorage(DefaultsKey.panelControlCleaning) private var showInPanel = true

    var body: some View {
        Form {
            Section(l10n.s.keyboardCleaningName) {
                Toggle(l10n.s.keyboardCleaningToggle, isOn: cleaningBinding)
                Text(l10n.s.keyboardCleaningCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(cleaning.statusText(l10n.s),
                      systemImage: cleaning.isActive ? "checkmark.circle.fill" : "keyboard")
                    .font(.caption)
                    .foregroundStyle(cleaning.isActive ? .green : .secondary)
                Toggle(l10n.s.panelShowItem, isOn: $showInPanel)
            }

            Section(l10n.s.permissionRequired) {
                permissionRow(title: l10n.s.keyboardCleaningInputMonitoring,
                              granted: permissions.inputMonitoring) {
                    permissions.requestInputMonitoring()
                    permissions.openInputMonitoringSettings()
                }
                permissionRow(title: l10n.s.permissionAccessibility,
                              granted: permissions.accessibility) {
                    permissions.requestAccessibility()
                    permissions.openAccessibilitySettings()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var cleaningBinding: Binding<Bool> {
        Binding {
            cleaning.isActive
        } set: { enabled in
            enabled ? CleaningModeManager.shared.activate() : CleaningModeManager.shared.deactivate()
        }
    }

    private func permissionRow(title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Spacer()
            Button(l10n.s.permissionRequest, action: action)
                .disabled(granted)
        }
    }
}
