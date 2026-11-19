// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct InstantSpacesSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = InstantSpacesService.shared
    @AppStorage(DefaultsKey.instantSpacesKeyboard) private var keyboard = false
    @AppStorage(DefaultsKey.instantSpacesTrackpad) private var trackpad = false

    private var strings: InstantSpacesStrings { FeatureStrings.instantSpaces(l10n.language) }

    var body: some View {
        Form {
            Section(strings.title) {
                Toggle(strings.keyboard, isOn: $keyboard)
                Text(strings.keyboardCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(strings.trackpad, isOn: $trackpad)
                Text(strings.trackpadCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!InstantSpacesGesture.isSupported)

            Section {
                Text(strings.compatibility)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if InstantSpacesGesture.isSupported, keyboard || trackpad,
                   permissions.accessibility, !service.isRunning {
                    Label(strings.unavailable, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                }
            }
            if (keyboard || trackpad), !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: keyboard) { _, value in sync(requestPermission: value) }
        .onChange(of: trackpad) { _, value in sync(requestPermission: value) }
    }

    private func sync(requestPermission: Bool) {
        service.syncWithPreferences()
        guard requestPermission, !permissions.accessibility else { return }
        permissions.requestAccessibility()
        permissions.openAccessibilitySettings()
    }
}
