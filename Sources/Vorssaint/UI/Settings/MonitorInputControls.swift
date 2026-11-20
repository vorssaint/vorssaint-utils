// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Switching a monitor's input from the keyboard: the toggle, its shortcut
/// and, under them, the monitors that can be moved to another input from here.
struct MonitorInputControls: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var brightness = BrightnessService.shared
    @AppStorage(DefaultsKey.monitorInputShortcutEnabled) private var enabled = false
    var showsShortcutRow = true
    var showsSettingsRow = false
    var showsPicker = true

    private var inset: CGFloat { showsSettingsRow ? settingsRowTextInset : 0 }

    var body: some View {
        let strings = FeatureStrings.brightness(l10n.language)
        Group {
            if showsSettingsRow {
                SettingsRow(symbol: "display.2", title: strings.monitorInputShortcut,
                            caption: strings.monitorInputShortcutCaption) {
                    Toggle(strings.monitorInputShortcut, isOn: $enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            } else {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(strings.monitorInputShortcut)
                        Text(strings.monitorInputShortcutCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: enabled) { _, isOn in
            brightness.syncWithPreferences()
            if isOn, showsPicker { brightness.refreshMonitorInputs() }
        }
        .onAppear {
            if enabled, showsPicker { brightness.refreshMonitorInputs() }
        }
        if showsShortcutRow, enabled {
            ShortcutPreferenceRow(role: .monitorInput, isEnabled: enabled,
                                  label: GlobalShortcutRole.monitorInput.title(l10n.s),
                                  includeInactiveConflicts: true,
                                  additionalConflict: { shortcut in
                guard AppFeature.windowLayout.isAvailable else { return nil }
                return WindowLayoutService.shared.shortcutConflictTitle(shortcut, excluding: nil)
            }) {
                brightness.syncWithPreferences()
            }
            .padding(.leading, inset)
        }
        if enabled, brightness.monitorInputShortcutRegistrationFailed {
            Text(l10n.s.shortcutUnavailable)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.leading, inset)
        }
        if enabled, showsPicker {
            monitorRows(strings)
        }
    }

    @ViewBuilder
    private func monitorRows(_ strings: BrightnessFeatureStrings) -> some View {
        if brightness.monitorInputMonitors.isEmpty {
            if !brightness.monitorInputScanning {
                Text(strings.monitorInputPickerEmpty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, inset)
            }
        } else {
            ForEach(brightness.monitorInputMonitors) { monitor in
                // A monitor's own name, not a setting's label, so it is a plain
                // row rather than a `SettingsRow`.
                HStack(spacing: 8) {
                    Image(systemName: "display")
                        .foregroundStyle(.secondary)
                    Text(monitor.name)
                    Spacer(minLength: 12)
                    Picker(monitor.name, selection: Binding(
                        get: { monitor.current },
                        set: { brightness.selectMonitorInput($0, on: monitor.id) })) {
                        ForEach(monitor.inputs, id: \.self) { input in
                            Text(MonitorInputSupport.name(of: input)).tag(input)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                .padding(.leading, inset)
            }
        }
    }
}
