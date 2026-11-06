// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The settings rows for a monitor's own speaker volume: one switch for the
/// volume keys, and for each external monitor on a DDC channel the switch that
/// offers its volume. A monitor that answers readings is offered on its own.
struct MonitorVolumeSettingsRows: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var brightness = BrightnessService.shared
    @ObservedObject private var volume = MonitorVolumeService.shared
    @AppStorage(DefaultsKey.monitorVolumeKeysEnabled) private var keysEnabled = false

    private var strings: MonitorVolumeStrings { FeatureStrings.monitorVolume(l10n.language) }

    var body: some View {
        if !volume.candidates.isEmpty {
            SettingsRow(symbol: "speaker.wave.2", title: strings.keysToggle, caption: strings.keysCaption) {
                Toggle(strings.keysToggle, isOn: $keysEnabled)
                    .labelsHidden()
                    .onChange(of: keysEnabled) { _, isOn in
                        if isOn { Permissions.shared.requestAccessibility() }
                        BrightnessService.shared.syncWithPreferences()
                    }
            }
            ForEach(volume.candidates) { display in
                SettingsRow(symbol: "display", title: "\(strings.monitorToggle): \(display.name)",
                            caption: strings.monitorCaption) {
                    Toggle(display.name, isOn: Binding(
                        get: { volume.isOffered(display.id) },
                        set: { volume.setChosen($0, for: display.id) }))
                        .labelsHidden()
                }
            }
        }
    }
}

/// A monitor's volume in the panel: a slider and a mute button, only for a
/// monitor whose volume is offered.
struct MonitorVolumeRow: View {
    let display: BrightnessDisplay
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var volume = MonitorVolumeService.shared

    private var strings: MonitorVolumeStrings { FeatureStrings.monitorVolume(l10n.language) }

    var body: some View {
        if volume.states[display.id] != nil {
            HStack(spacing: 6) {
                Button {
                    volume.toggleMute(for: display.id)
                } label: {
                    Image(systemName: volume.isMuted(display.id) ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .help(strings.mute)
                .accessibilityLabel(strings.mute)
                Slider(value: Binding(get: { volume.level(for: display.id) },
                                      set: { volume.setLevel($0, for: display.id) }), in: 0...1)
                    .controlSize(.small)
                    .accessibilityLabel("\(strings.title) \(display.name)")
                Text("\(Int((volume.level(for: display.id) * 100).rounded()))%")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32, alignment: .trailing)
            }
        }
    }
}
