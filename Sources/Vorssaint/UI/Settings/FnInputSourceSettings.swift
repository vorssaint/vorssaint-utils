// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct FnInputSourceSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = FnInputSourceService.shared
    @AppStorage(DefaultsKey.fnInputSourceEnabled) private var enabled = false
    /// Read on appearing and whenever the app comes back to the front, which
    /// is where a trip to System Settings ends.
    @State private var systemAction = FnInputSourceService.systemAction()

    private var text: FnInputSourceStrings { FeatureStrings.fnInputSource(l10n.language) }

    private static let keyboardSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")

    var body: some View {
        Form {
            Section(text.pageTitle) {
                Toggle(text.enableToggle, isOn: $enabled)
                    .onChange(of: enabled) { _, value in
                        FnInputSourceService.shared.syncWithPreferences()
                        guard value, !permissions.accessibility else { return }
                        permissions.requestAccessibility()
                        permissions.openAccessibilitySettings()
                    }
                Text(text.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(text.keyboardNote, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, service.isRunning {
                    Label(text.activeNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if enabled, permissions.accessibility {
                    Label(text.tapRefused, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section(text.systemSection) {
                if systemAction == .nothing {
                    Label {
                        Text(text.systemNothing)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .font(.caption)
                } else {
                    Label(text.systemOther, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(enabled ? .orange : .secondary)
                }
                Button(text.openKeyboardSettings) {
                    if let url = Self.keyboardSettingsURL {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            if enabled, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { systemAction = FnInputSourceService.systemAction() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            systemAction = FnInputSourceService.systemAction()
        }
    }
}
