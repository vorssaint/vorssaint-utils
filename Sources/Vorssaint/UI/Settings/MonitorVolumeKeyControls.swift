// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct MonitorVolumeKeyControls: View {
    let strings: BrightnessFeatureStrings

    @AppStorage(DefaultsKey.ddcVolumeStep) private var step = MonitorVolumeKeySettings.defaultStepPercent
    @AppStorage(DefaultsKey.ddcVolumeMinimum) private var minimum = 0
    @AppStorage(DefaultsKey.ddcVolumeMaximum) private var maximum = 100

    private var settings: MonitorVolumeKeySettings {
        MonitorVolumeKeySettings(stepPercent: step, minimumPercent: minimum, maximumPercent: maximum)
    }

    var body: some View {
        SettingsRow(symbol: "plusminus", title: strings.speakersStep) {
            Picker(strings.speakersStep, selection: Binding(get: { settings.stepPercent }, set: { step = $0 })) {
                ForEach(MonitorVolumeKeySettings.stepChoices, id: \.self) { choice in
                    if choice == MonitorVolumeKeySettings.defaultStepPercent {
                        Text(strings.speakersStepStandard).tag(choice)
                    } else {
                        Text(choice / 100, format: .percent).tag(choice)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        SettingsRow(symbol: "speaker.fill", title: strings.speakersMinimum, caption: strings.speakersMinimumCaption) {
            limit(strings.speakersMinimum, value: Binding(get: { settings.minimumPercent }, set: { minimum = $0 }),
                  range: 0...(settings.maximumPercent - 1))
        }
        SettingsRow(symbol: "speaker.wave.3.fill", title: strings.speakersMaximum, caption: strings.speakersMaximumCaption) {
            limit(strings.speakersMaximum, value: Binding(get: { settings.maximumPercent }, set: { maximum = $0 }),
                  range: (settings.minimumPercent + 1)...100)
        }
    }

    private func limit(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            if range.lowerBound < range.upperBound {
                Slider(value: Binding(get: { Double(value.wrappedValue) }, set: {
                    value.wrappedValue = Int($0.rounded())
                }), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                    .frame(width: 150)
                    .accessibilityLabel(title)
            }
            Text(Double(value.wrappedValue) / 100, format: .percent)
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
        }
    }
}
