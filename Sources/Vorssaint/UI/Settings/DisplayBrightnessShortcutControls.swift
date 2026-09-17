// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct DisplayBrightnessShortcutControls: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var brightness = BrightnessService.shared
    @AppStorage(DefaultsKey.displayBrightnessShortcutsEnabled) private var enabled = false
    var showsShortcutRows = true

    var body: some View {
        let strings = FeatureStrings.brightness(l10n.language)
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading, spacing: 3) {
                Text(strings.displayBrightnessShortcuts)
                Text(strings.displayBrightnessShortcutCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: enabled) { _, _ in brightness.syncWithPreferences() }
        if showsShortcutRows, enabled {
            ForEach([GlobalShortcutRole.displayBrightnessDecrease, .displayBrightnessIncrease]) { role in
                ShortcutPreferenceRow(role: role, isEnabled: enabled, label: role.title(l10n.s),
                                      includeInactiveConflicts: true,
                                      additionalConflict: { shortcut in
                    guard AppFeature.windowLayout.isAvailable else { return nil }
                    return WindowLayoutService.shared.shortcutConflictTitle(shortcut, excluding: nil)
                }) {
                    brightness.syncWithPreferences()
                }
            }
        }
        if enabled, brightness.displayBrightnessShortcutRegistrationFailed {
            Text(l10n.s.shortcutUnavailable)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
