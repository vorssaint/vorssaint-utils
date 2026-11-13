// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct RecorderExportFormatControl: View {
    @ObservedObject var model: RecorderEditorModel
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let strings = FeatureStrings.recorderExportFormat(l10n.language)
        Menu {
            Picker(strings.format, selection: Binding(
                get: { model.document.resolvedExportFormat },
                set: { model.setExportFormat($0) })) {
                Text(strings.video).tag(RecorderSupport.ExportFormat.video)
                Text("GIF").tag(RecorderSupport.ExportFormat.gif)
            }
            .pickerStyle(.inline)
        } label: {
            Text(model.document.resolvedExportFormat == .gif ? "GIF" : strings.video)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .screenshotSafeHelp(strings.format)
        .accessibilityLabel(strings.format)
        .disabled(model.isExporting)
    }
}

struct RecorderExportSizeControl: View {
    @ObservedObject var model: RecorderEditorModel
    @ObservedObject private var l10n = L10n.shared
    @State private var showsCustom = false
    @State private var draftPercent = 75.0

    private var strings: RecorderFeatureStrings { FeatureStrings.recorder(l10n.language) }
    private var formatStrings: RecorderExportFormatStrings { FeatureStrings.recorderExportFormat(l10n.language) }
    private var isGIF: Bool { model.document.resolvedExportFormat == .gif }

    private func qualityTitle(_ quality: RecorderSupport.Quality) -> String {
        switch quality {
        case .high: return strings.qualityHigh
        case .balanced: return strings.qualityBalanced
        case .small: return strings.qualitySmall
        }
    }

    private func gifTitle(_ percent: Int) -> String {
        switch percent {
        case 100: return strings.qualityHigh
        case 75: return strings.qualityBalanced
        case 50: return strings.qualitySmall
        default: return formatStrings.customSize
        }
    }

    private func dimensions(_ size: CGSize) -> String {
        guard size.width > 0, size.height > 0 else { return "" }
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    private var title: String {
        if isGIF {
            return gifTitle(model.document.resolvedGIFScalePercent)
                + " \(model.document.resolvedGIFScalePercent)% · " + dimensions(model.exportSize)
        }
        return qualityTitle(model.document.resolvedQuality) + "  " + dimensions(model.exportSize)
    }

    var body: some View {
        Menu {
            if isGIF {
                // A Picker provides the native menu checkmark for each preset.
                Picker(formatStrings.gifSize, selection: Binding(
                    get: { model.document.resolvedGIFScalePercent },
                    set: { model.setGIFScalePercent($0) })) {
                    ForEach([100, 75, 50], id: \.self) { percent in
                        Text(gifTitle(percent) + " (\(percent)%)").tag(percent)
                    }
                    if ![100, 75, 50].contains(model.document.resolvedGIFScalePercent) {
                        Text(formatStrings.customSize + " (\(model.document.resolvedGIFScalePercent)%)")
                            .tag(model.document.resolvedGIFScalePercent)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button(formatStrings.customSize + "…") {
                    draftPercent = Double(model.document.resolvedGIFScalePercent)
                    showsCustom = true
                }
            } else {
                Picker(strings.qualityLabel, selection: Binding(
                    get: { model.document.quality },
                    set: { value in
                        guard !model.isExporting else { return }
                        var next = model.document
                        next.quality = value
                        model.document = next
                    })) {
                    ForEach(RecorderSupport.Quality.allCases, id: \.rawValue) { quality in
                        Text(qualityTitle(quality)).tag(quality.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label(title, systemImage: "slider.horizontal.3")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 240, alignment: .leading)
        }
        // Pin the menu itself on macOS 15 so it cannot consume its row's
        // free width. Bound the label inside it for the narrow editor layout.
        .menuStyle(.borderlessButton)
        .fixedSize()
        .screenshotSafeHelp(isGIF ? formatStrings.gifSize : strings.qualityLabel)
        .accessibilityLabel(isGIF ? formatStrings.gifSize : strings.qualityLabel)
        .accessibilityValue(title)
        .disabled(model.isExporting)
        .popover(isPresented: $showsCustom) {
            VStack(alignment: .leading, spacing: 14) {
                Text(formatStrings.customSize).font(.headline)
                HStack {
                    Text("\(Int(draftPercent))%")
                    Spacer()
                    Text(dimensions(RecorderSupport.gifOutputSize(
                        source: model.exportCanvasSize, scalePercent: Int(draftPercent))))
                }
                .monospacedDigit()
                Slider(value: $draftPercent, in: 1...100, step: 1)
                    .accessibilityLabel(formatStrings.gifSize)
                    .accessibilityValue("\(Int(draftPercent))%")
                HStack {
                    Text("1%")
                    Spacer()
                    Text("100%")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button(strings.cancelButton, role: .cancel) { showsCustom = false }
                    Button(FeatureStrings.screenshot(l10n.language).done) {
                        model.setGIFScalePercent(Int(draftPercent))
                        showsCustom = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(18)
            .frame(width: 280)
            .disabled(model.isExporting)
        }
    }
}

/// FPS is separate from size and applies only after Done, as one undo step.
struct RecorderGIFFrameRateControl: View {
    @ObservedObject var model: RecorderEditorModel
    @ObservedObject private var l10n = L10n.shared
    @State private var isPresented = false
    @State private var draftRate = 12.0

    var body: some View {
        let strings = FeatureStrings.recorderExportFormat(l10n.language)
        Button {
            draftRate = Double(model.document.resolvedGIFFrameRate)
            isPresented = true
        } label: {
            Label("\(model.document.resolvedGIFFrameRate) FPS", systemImage: "gearshape")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .screenshotSafeHelp(strings.frameRate)
        .accessibilityLabel(strings.frameRate)
        .accessibilityValue("\(model.document.resolvedGIFFrameRate) FPS")
        .disabled(model.isExporting)
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 14) {
                Text(strings.frameRate).font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach([8, 12, 15, 24, 30, 50], id: \.self) { rate in
                        Button {
                            draftRate = Double(rate)
                        } label: {
                            Text("\(rate) FPS")
                                .fontWeight(Int(draftRate) == rate ? .bold : .regular)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Int(draftRate) == rate ? .accentColor : .secondary)
                        .accessibilityAddTraits(Int(draftRate) == rate ? .isSelected : [])
                    }
                }
                Text("\(Int(draftRate)) FPS").monospacedDigit()
                Slider(value: $draftRate, in: 1...50, step: 1)
                    .accessibilityLabel(strings.frameRate)
                    .accessibilityValue("\(Int(draftRate)) FPS")
                HStack {
                    Text("1 FPS")
                    Spacer()
                    Text("50 FPS")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button(FeatureStrings.recorder(l10n.language).cancelButton, role: .cancel) {
                        isPresented = false
                    }
                    Button(FeatureStrings.screenshot(l10n.language).done) {
                        model.setGIFFrameRate(Int(draftRate))
                        isPresented = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(18)
            .frame(width: 280)
            .disabled(model.isExporting)
        }
    }
}
