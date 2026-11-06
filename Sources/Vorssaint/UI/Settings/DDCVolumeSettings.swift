// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Settings for the volume keys driving a monitor's own speakers over DDC:
/// the switch, how far one press moves, and the range the keys stay in.
struct DDCVolumeSettingsCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.ddcVolumeEnabled) private var enabled = false
    @AppStorage(DefaultsKey.ddcVolumeStep) private var step = DDCVolumeSupport.defaultStepPercent
    @AppStorage(DefaultsKey.ddcVolumeMinimum) private var minimum = 0
    @AppStorage(DefaultsKey.ddcVolumeMaximum) private var maximum = 100

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }

    var body: some View {
        SettingsCard(title: strings.speakersTitle) {
            SettingsRow(symbol: "hifispeaker.fill", title: strings.speakersToggle,
                        caption: strings.speakersCaption) {
                Toggle(strings.speakersToggle, isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) { _, isOn in
                        if isOn { permissions.requestAccessibility() }
                        DDCVolumeService.shared.syncWithPreferences()
                    }
            }
            if enabled {
                Divider()
                SettingsRow(symbol: "plusminus", title: strings.speakersStep,
                            caption: strings.speakersStepCaption) {
                    Picker(strings.speakersStep, selection: stepBinding) {
                        ForEach(DDCVolumeSupport.stepChoices, id: \.self) { choice in
                            Text(choice == DDCVolumeSupport.defaultStepPercent
                                 ? strings.speakersStepStandard
                                 : "\(Int(choice.rounded()))%").tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(symbol: "speaker.fill", title: strings.speakersMinimum,
                            caption: strings.speakersMinimumCaption) {
                    limitControl(title: strings.speakersMinimum, value: minimumBinding, range: 0...95)
                }
                SettingsRow(symbol: "speaker.wave.3.fill", title: strings.speakersMaximum,
                            caption: strings.speakersMaximumCaption) {
                    limitControl(title: strings.speakersMaximum, value: maximumBinding, range: 5...100)
                }
                if !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
    }

    /// A step stored before the choices changed shows as the nearest choice
    /// instead of an empty menu.
    private var stepBinding: Binding<Double> {
        Binding {
            let current = DDCVolumeSupport.sanitizedStep(step)
            return DDCVolumeSupport.stepChoices.min { abs($0 - current) < abs($1 - current) }
                ?? DDCVolumeSupport.defaultStepPercent
        } set: { step = $0 }
    }

    /// The limits keep at least five points between them: dragging one into
    /// the other pushes the other along.
    private var minimumBinding: Binding<Int> {
        Binding { minimum } set: { value in
            minimum = value
            if maximum < value + 5 { maximum = min(100, value + 5) }
        }
    }

    private var maximumBinding: Binding<Int> {
        Binding { maximum } set: { value in
            maximum = value
            if minimum > value - 5 { minimum = max(0, value - 5) }
        }
    }

    private func limitControl(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 8) {
            Slider(value: Binding(get: { Double(value.wrappedValue) },
                                  set: { value.wrappedValue = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 5)
                .frame(width: 150)
                .accessibilityLabel(title)
            Text("\(value.wrappedValue)%")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }
}
