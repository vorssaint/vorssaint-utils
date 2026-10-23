// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ClickHighlightSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.clickHighlightRippleEnabled) private var rippleEnabled = false
    @AppStorage(DefaultsKey.clickHighlightRippleOnlyWhileRecording) private var rippleOnlyWhileRecording = false
    @AppStorage(DefaultsKey.clickHighlightStyle) private var style = ClickRippleStyle.ring.rawValue
    @AppStorage(DefaultsKey.clickHighlightSize) private var size = Defaults.defaultClickHighlightSize
    @AppStorage(DefaultsKey.clickHighlightColor) private var colorHex = Defaults.defaultClickHighlightColor
    @AppStorage(DefaultsKey.clickHighlightSpotlightEnabled) private var spotlightEnabled = false
    @AppStorage(DefaultsKey.clickHighlightSpotlightOnlyWhileRecording) private var spotlightOnlyWhileRecording = true
    @AppStorage(DefaultsKey.clickHighlightSpotlightDarkness) private var darkness =
        Defaults.defaultClickHighlightSpotlightDarkness
    @AppStorage(DefaultsKey.clickHighlightSpotlightRadius) private var radius =
        Defaults.defaultClickHighlightSpotlightRadius

    private var text: InputFeedbackStrings { FeatureStrings.inputFeedback(l10n.language) }

    private var recorderAvailable: Bool { AppFeature.screenRecorder.isAvailable }

    private var signature: String {
        [rippleEnabled, rippleOnlyWhileRecording, spotlightEnabled, spotlightOnlyWhileRecording]
            .map { $0 ? "1" : "0" }.joined() + style + colorHex + "\(size)\(darkness)\(radius)"
    }

    private var colorBinding: Binding<Color> {
        Binding {
            let value = ClickHighlightSupport.color(hex: colorHex)
            return Color(red: value.red, green: value.green, blue: value.blue)
        } set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            colorHex = ClickHighlightSupport.hex(red: rgb.redComponent, green: rgb.greenComponent,
                                                 blue: rgb.blueComponent)
        }
    }

    var body: some View {
        Form {
            Section(text.highlightTitle) {
                Text(text.highlightCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(text.rippleSection) {
                Toggle(text.rippleToggle, isOn: $rippleEnabled)
                Picker(text.styleLabel, selection: $style) {
                    ForEach(ClickRippleStyle.allCases) { option in
                        Label(text.styleName(option), systemImage: option.symbolName).tag(option.rawValue)
                    }
                }
                HStack {
                    Text(text.sizeLabel)
                    Slider(value: $size, in: Defaults.allowedClickHighlightSizeRange)
                    Text("\(Int(size)) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                ColorPicker(text.colorLabel, selection: colorBinding, supportsOpacity: false)
                if recorderAvailable {
                    Toggle(text.onlyWhileRecording, isOn: $rippleOnlyWhileRecording)
                }
                Button(text.sampleButton) { ClickHighlightService.shared.preview() }
            }

            Section(text.spotlightSection) {
                Toggle(text.spotlightToggle, isOn: $spotlightEnabled)
                Text(text.spotlightCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(text.darknessLabel)
                    Slider(value: $darkness, in: Defaults.allowedClickHighlightSpotlightDarknessRange)
                }
                .disabled(!spotlightEnabled)
                HStack {
                    Text(text.sizeLabel)
                    Slider(value: $radius, in: Defaults.allowedClickHighlightSpotlightRadiusRange)
                }
                .disabled(!spotlightEnabled)
                if recorderAvailable {
                    Toggle(text.onlyWhileRecording, isOn: $spotlightOnlyWhileRecording)
                        .disabled(!spotlightEnabled)
                    Text(text.onlyWhileRecordingCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: signature) { _, _ in
            ClickHighlightService.shared.syncWithPreferences()
        }
    }
}
