// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

/// The watermark picker: a line of text in one of the editor's colors or a
/// picture from disk, set on one of nine places with size, opacity and tilt
/// sliders. Everything applies live and is remembered for the next capture,
/// like the backdrop, and a mark worth keeping goes into the presets row so
/// switching between a logo and a caption is one click.
struct ScreenshotWatermarkPopover: View {
    @ObservedObject var model: ScreenshotEditorModel
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var textFocused: Bool

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    private var isOn: Bool {
        model.watermarkStyle.kind != .none
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            kindPicker
            switch model.watermarkStyle.kind {
            case .none:
                EmptyView()
            case .text:
                textSection
            case .image:
                imageRow
            }
            if isOn || !model.watermarkPresets.isEmpty {
                presetGrid
            }
            Divider()
            placementSection
        }
        .padding(14)
        .frame(width: 292)
    }

    // MARK: - Content

    private var kindPicker: some View {
        Picker("", selection: kindBinding) {
            Text(strings.backdropNone).tag(ScreenshotSupport.WatermarkStyle.Kind.none)
            Text(strings.toolText).tag(ScreenshotSupport.WatermarkStyle.Kind.text)
            Text(strings.watermarkImageLabel).tag(ScreenshotSupport.WatermarkStyle.Kind.image)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .accessibilityLabel(strings.watermarkLabel)
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField(strings.watermarkTextPlaceholder, text: textBinding)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .focused($textFocused)
                .onAppear {
                    // A fresh text mark is there to be typed; an existing
                    // one keeps the keyboard where it was.
                    guard model.watermarkStyle.text.isEmpty else { return }
                    DispatchQueue.main.async { textFocused = true }
                }
            HStack(spacing: 4) {
                ForEach(ScreenshotSupport.ColorID.allCases, id: \.self) { colorID in
                    colorDot(colorID)
                }
            }
        }
    }

    private func colorDot(_ colorID: ScreenshotSupport.ColorID) -> some View {
        let selected = ScreenshotSupport.ColorID(rawValue: model.watermarkStyle.color) == colorID
        return Button {
            model.watermarkStyle.color = colorID.rawValue
        } label: {
            ZStack {
                Circle()
                    .fill(Color(nsColor: ScreenshotRenderer.nsColor(colorID)))
                    .frame(width: 17, height: 17)
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(0.22), lineWidth: 0.5)
                    )
                if selected {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.9), lineWidth: 1.5)
                        .frame(width: 23, height: 23)
                }
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(strings.colorLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var imageRow: some View {
        let path = model.watermarkStyle.imagePath
        return HStack(spacing: 8) {
            Group {
                if let path,
                   let thumbnail = BackdropPickerAssets.thumbnail(for: URL(fileURLWithPath: path)) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 22)
            Text(path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? strings.backdropNone)
                .font(.system(size: 12))
                .foregroundStyle(path == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button(strings.folderChoose) {
                chooseImage()
            }
            .controlSize(.small)
        }
    }

    // MARK: - Presets

    private var presetGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                  spacing: 8) {
            ForEach(Array(model.watermarkPresets.enumerated()), id: \.offset) { index, preset in
                presetSwatch(preset, index: index)
            }
            savePresetSwatch
        }
    }

    private func presetSwatch(_ preset: ScreenshotSupport.WatermarkStyle, index: Int) -> some View {
        let selected = model.watermarkStyle.sanitized() == preset
        let name = preset.kind == .image
            ? URL(fileURLWithPath: preset.imagePath ?? "").lastPathComponent
            : preset.text
        return Button {
            model.watermarkStyle = preset
        } label: {
            Group {
                if preset.kind == .image, let path = preset.imagePath,
                   let thumbnail = BackdropPickerAssets.thumbnail(for: URL(fileURLWithPath: path)) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                } else {
                    Text(preset.text)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(nsColor: ScreenshotRenderer.nsColor(
                            ScreenshotSupport.ColorID(rawValue: preset.color) ?? .white)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            // A neutral plate keeps both black and white marks legible.
            .background(Color(white: 0.5).opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                                  lineWidth: selected ? 2.5 : 1)
            )
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button(strings.backdropDeletePreset, role: .destructive) {
                model.removeWatermarkPreset(at: index)
            }
        }
    }

    private var canSavePreset: Bool {
        let style = model.watermarkStyle.sanitized()
        return style.kind != .none && !model.watermarkPresets.contains(style)
    }

    private var savePresetSwatch: some View {
        Button {
            model.saveCurrentWatermarkAsPreset()
        } label: {
            ZStack {
                Color.primary.opacity(0.06)
                Image(systemName: "plus")
                    .foregroundStyle(.secondary)
            }
            .frame(height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.borderless)
        .disabled(!canSavePreset)
        .screenshotSafeHelp(strings.watermarkSavePreset)
        .accessibilityLabel(strings.watermarkSavePreset)
    }

    // MARK: - Placement

    private var placementSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                sliderLabel(strings.watermarkPositionLabel)
                anchorGrid
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                sliderLabel(strings.watermarkSizeLabel)
                Slider(value: sizeBinding, in: 0...1)
                    .controlSize(.small)
            }
            HStack(spacing: 8) {
                sliderLabel(strings.watermarkOpacityLabel)
                Slider(value: opacityBinding, in: ScreenshotSupport.WatermarkStyle.opacityRange)
                    .controlSize(.small)
            }
            HStack(spacing: 8) {
                sliderLabel(strings.watermarkRotationLabel)
                Slider(value: rotationBinding,
                       in: ScreenshotSupport.WatermarkStyle.rotationRange,
                       step: 1)
                    .controlSize(.small)
                Text("\(Int(model.watermarkStyle.rotation.rounded()))°")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .disabled(!isOn)
    }

    private func sliderLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            // The column keeps the controls aligned; Russian and Turkish run
            // past it, so the label gives a little rather than being cut.
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(width: 80, alignment: .leading)
            .foregroundStyle(isOn ? .secondary : .tertiary)
    }

    /// Nine places instead of a drag, the recorder's grid: it reads at a
    /// glance and a corner mark stays in its corner whatever the capture.
    private var anchorGrid: some View {
        let rows: [[ScreenshotSupport.WatermarkStyle.Anchor]] = [
            [.topLeading, .top, .topTrailing],
            [.leading, .center, .trailing],
            [.bottomLeading, .bottom, .bottomTrailing],
        ]
        return VStack(spacing: 3) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(rows[row], id: \.rawValue) { anchor in
                        let selected = model.watermarkStyle.anchor == anchor
                        Button {
                            model.watermarkStyle.anchor = anchor
                        } label: {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(selected
                                      ? Color.accentColor.opacity(0.85)
                                      : Color.primary.opacity(0.10))
                                .frame(width: 22, height: 15)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(strings.watermarkPositionLabel)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    // MARK: - Bindings

    private var kindBinding: Binding<ScreenshotSupport.WatermarkStyle.Kind> {
        Binding {
            model.watermarkStyle.kind
        } set: { kind in
            model.watermarkStyle.kind = kind
            // Choosing a picture mark without a picture yet is asking for one.
            if kind == .image, model.watermarkStyle.imagePath == nil {
                DispatchQueue.main.async { chooseImage() }
            }
        }
    }

    private var textBinding: Binding<String> {
        Binding {
            model.watermarkStyle.text
        } set: { text in
            model.watermarkStyle.text = String(
                text.prefix(ScreenshotSupport.WatermarkStyle.textLimit))
        }
    }

    private var sizeBinding: Binding<Double> {
        Binding {
            model.watermarkStyle.size
        } set: { value in
            model.watermarkStyle.size = value
        }
    }

    private var opacityBinding: Binding<Double> {
        Binding {
            model.watermarkStyle.opacity
        } set: { value in
            model.watermarkStyle.opacity = value
        }
    }

    private var rotationBinding: Binding<Double> {
        Binding {
            model.watermarkStyle.rotation
        } set: { value in
            model.watermarkStyle.rotation = value
        }
    }

    // MARK: - Actions

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            model.watermarkStyle.imagePath = url.path
        }
    }
}
