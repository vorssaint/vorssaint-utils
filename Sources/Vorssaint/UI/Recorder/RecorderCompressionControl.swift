// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The editor exports directly at these settings; no intermediate saved video.
struct RecorderCompressionControl: View {
    @ObservedObject var model: RecorderEditorModel
    @ObservedObject private var l10n = L10n.shared
    @State private var isPresented = false
    @State private var draft = RecorderEditDocument()

    private var strings: RecorderFeatureStrings { FeatureStrings.recorder(l10n.language) }
    private var compression: RecorderCompressionStrings { FeatureStrings.recorderCompression(l10n.language) }

    var body: some View {
        Button {
            draft = model.document
            isPresented = true
        } label: {
            Label {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(l10n.s.mediaQuality + "  " + dimensions(model.exportSize))
                    Text(sizeLabel(model.document, plan: model.videoExportPlan(for: model.document)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            } icon: {
                Image(systemName: "slider.horizontal.3")
            }
            .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .screenshotSafeHelp(l10n.s.mediaQuality)
        .accessibilityLabel(l10n.s.mediaQuality)
        .disabled(model.isExporting)
        .popover(isPresented: $isPresented) { settings }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.s.mediaQuality).font(.headline)
            Picker(strings.qualityLabel, selection: $draft.quality) {
                Text(strings.qualitySmall).tag(RecorderSupport.Quality.small.rawValue)
                Text(strings.qualityBalanced).tag(RecorderSupport.Quality.balanced.rawValue)
                Text(strings.qualityHigh).tag(RecorderSupport.Quality.high.rawValue)
            }
            Picker(l10n.s.mediaSizingResolution, selection: $draft.exportMaxDimension) {
                Text(compression.originalResolution).tag(0)
                ForEach([640, 1280, 1920, 2560, 3840], id: \.self) { edge in
                    Text("\(edge) px").tag(edge)
                }
                if draft.exportMaxDimension > 0,
                   ![640, 1280, 1920, 2560, 3840].contains(draft.exportMaxDimension) {
                    Text("\(draft.exportMaxDimension) px").tag(draft.exportMaxDimension)
                }
            }
            Toggle(compression.limitFileSize, isOn: Binding(
                get: { draft.exportTargetMegabytes > 0 },
                set: { draft.exportTargetMegabytes = $0 ? 20 : 0 }))
            if draft.exportTargetMegabytes > 0 {
                HStack {
                    Text(l10n.s.mediaTargetSize)
                    Spacer()
                    TextField("", value: $draft.exportTargetMegabytes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 65)
                        .accessibilityLabel(l10n.s.mediaTargetSize)
                    Text(l10n.s.mediaMegabytesSuffix)
                    Stepper("", value: $draft.exportTargetMegabytes, in: 1...512)
                        .labelsHidden()
                        .accessibilityLabel(l10n.s.mediaTargetSize)
                }
                Text(l10n.s.mediaTargetSizeHint)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            if let plan = model.videoExportPlan(for: draft) {
                HStack {
                    Text(dimensions(plan.size))
                    Spacer()
                    Text(sizeLabel(draft, plan: plan))
                }
                .monospacedDigit()
                Text(compression.estimateHint)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(l10n.s.mediaErrorTargetTooSmall)
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(strings.cancelButton, role: .cancel) { isPresented = false }
                Button(FeatureStrings.screenshot(l10n.language).done) {
                    var next = model.document
                    next.quality = draft.quality
                    next.exportMaxDimension = draft.resolvedExportMaxDimension
                    next.exportTargetMegabytes = draft.exportTargetMegabytes > 0
                        ? MediaSupport.sanitizedTargetMegabytes(draft.exportTargetMegabytes) : 0
                    model.document = next
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.videoExportPlan(for: draft) == nil)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private func dimensions(_ size: CGSize) -> String {
        guard size.width > 0, size.height > 0 else { return "—" }
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    private func sizeLabel(_ document: RecorderEditDocument, plan: RecorderVideoExportPlan?) -> String {
        if document.exportTargetBytes > 0 {
            return "≤ " + ByteCountFormatter.string(fromByteCount: document.exportTargetBytes, countStyle: .file)
        }
        guard let plan else { return "—" }
        return "≈ " + ByteCountFormatter.string(fromByteCount: plan.estimatedBytes, countStyle: .file)
    }
}
