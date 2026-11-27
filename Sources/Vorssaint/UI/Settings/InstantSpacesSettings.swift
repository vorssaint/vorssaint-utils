// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct InstantSpacesSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = InstantSpacesService.shared
    @AppStorage(DefaultsKey.instantSpacesKeyboard) private var keyboard = false
    @AppStorage(DefaultsKey.instantSpacesTrackpad) private var trackpad = false

    @AppStorage(DefaultsKey.instantSpacesCycleEnabled) private var cycle = false
    @AppStorage(DefaultsKey.instantSpacesCycleCustom) private var cycleCustom = false

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

            Section(strings.cycle) {
                Toggle(strings.cycle, isOn: $cycle)
                if cycle {
                    Toggle(strings.cycleCustom, isOn: $cycleCustom)
                    if cycleCustom {
                        ShortcutPreferenceRow(role: .instantSpacesCycle, isEnabled: cycle,
                                              label: strings.cycle, includeInactiveConflicts: true,
                                              additionalConflict: { shortcut in
                            guard AppFeature.windowLayout.isAvailable else { return nil }
                            return WindowLayoutService.shared.shortcutConflictTitle(shortcut, excluding: nil)
                        }) { service.syncWithPreferences() }
                    }
                    Text(strings.cycleCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!InstantSpacesGesture.isSupported)

            Section {
                Text(strings.compatibility)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if InstantSpacesGesture.isSupported, keyboard || trackpad || cycle,
                   permissions.accessibility, !service.isRunning {
                    Label(strings.unavailable, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                }
            }
            if (keyboard || trackpad || cycle), !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: keyboard) { _, value in sync(requestPermission: value) }
        .onChange(of: trackpad) { _, value in sync(requestPermission: value) }
        .onChange(of: cycle) { _, value in sync(requestPermission: value) }
        .onChange(of: cycleCustom) { _, _ in service.syncWithPreferences() }
    }

    private func sync(requestPermission: Bool) {
        service.syncWithPreferences()
        guard requestPermission, !permissions.accessibility else { return }
        permissions.requestAccessibility()
        permissions.openAccessibilitySettings()
    }
}
