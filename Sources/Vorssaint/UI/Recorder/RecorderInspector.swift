// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The panel down the side of the editor: three looks to start from, then the
/// handful of things worth changing. Everything here changes the picture the
/// preview is already showing, so nothing has to be imagined.
struct RecorderInspector: View {
    @ObservedObject var model: RecorderEditorModel
    @ObservedObject private var l10n = L10n.shared
    @State private var showsBackdropPopover = false
    /// Typing is one edit, landed when the field is let go. Without this the
    /// caption would only reach the preview on a Return, and this field takes
    /// several lines, so Return is a new line and not a commit.
    @FocusState private var textFieldFocused: Bool

    private var strings: RecorderFeatureStrings {
        FeatureStrings.recorder(l10n.language)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Selecting a zoom swaps the whole panel to that zoom. The
                // swap is what teaches the selection model, without a word.
                if let text = model.selectedText {
                    selectedTextSection(text)
                } else if let selected = model.selectedZoom {
                    selectedZoomSection(selected)
                } else {
                    lookSection
                    Divider().opacity(0.4)
                    backgroundSection
                    Divider().opacity(0.4)
                    if model.hasPointerTrack {
                        pointerSection
                    } else {
                        Text(strings.noPointerNote)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(white: 0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider().opacity(0.4)
                    // A zoom placed by hand needs no pointer track at all, so
                    // this section is always here.
                    zoomSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.never)
        .frame(width: 258)
        .background(Color(white: 0.145))
    }

    // MARK: - Look

    private var lookSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(strings.lookLabel)
            HStack(spacing: 6) {
                lookButton(.raw, title: strings.lookRaw)
                lookButton(.clean, title: strings.lookClean)
                lookButton(.studio, title: strings.lookStudio)
            }
            Text(strings.lookCaption)
                .font(.system(size: 10.5))
                .foregroundStyle(Color(white: 0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lookButton(_ look: RecorderEditDocument.Look, title: String) -> some View {
        Button(title) {
            model.applyLook(look)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Background

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(strings.backgroundSectionLabel)
            Button {
                showsBackdropPopover = true
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(LinearGradient(
                            colors: BackdropPickerAssets.previewColors(for: model.backdropStyle),
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 26, height: 20)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        }
                    Text(model.showsBackdrop
                         ? strings.backgroundSectionLabel
                         : FeatureStrings.screenshot(l10n.language).backdropNone)
                        .font(.system(size: 12))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .popover(isPresented: $showsBackdropPopover, arrowEdge: .trailing) {
                ScreenshotBackdropPopover(model: model)
            }

            Picker(strings.shapeLabel, selection: aspectBinding) {
                Text(strings.shapeOriginal).tag(RecorderSupport.Aspect.original.rawValue)
                Text(strings.shapeWide).tag(RecorderSupport.Aspect.wide.rawValue)
                Text(strings.shapeSquare).tag(RecorderSupport.Aspect.square.rawValue)
                Text(strings.shapeVertical).tag(RecorderSupport.Aspect.vertical.rawValue)
            }
            .pickerStyle(.menu)
            .disabled(!model.showsBackdrop)
            .opacity(model.showsBackdrop ? 1 : 0.45)
        }
    }

    // MARK: - One zoom

    /// Exactly four rows, and four is the ceiling. A zoom has more knobs than
    /// this in theory; showing them turns a timeline into a control panel.
    private func selectedZoomSection(_ segment: RecorderTimeline.ZoomSegment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // The way back has to be a labelled thing, not a bare glyph:
            // otherwise selecting a zoom feels like a door that locks.
            Button {
                model.selectZoom(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text(strings.backToOptions)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
            .keyboardShortcut(.escape, modifiers: [])
            sectionTitle(strings.thisZoomLabel)
            valueSlider(title: strings.zoomAmountLabel,
                        value: segment.amount,
                        range: RecorderSupport.zoomAmountRange,
                        format: "%.1fx",
                        onChange: { model.setSelectedZoomAmount($0) },
                        onCommit: { model.commitZoomEdit() },
                        onReset: {
                            model.setSelectedZoomAmount(1.8)
                            model.commitZoomEdit()
                        })
            VStack(alignment: .leading, spacing: 5) {
                Text(strings.zoomWhereLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.72))
                Picker("", selection: Binding(
                    get: { segment.followsPointer },
                    set: { follows in
                        if follows {
                            model.setSelectedZoomFocus(nil)
                        } else {
                            model.beginAiming()
                        }
                    })) {
                        Text(strings.zoomFollowsPointer).tag(true)
                        Text(strings.zoomPickSpot).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                if !segment.followsPointer {
                    Button(strings.zoomPickSpotHint) { model.beginAiming() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Button(strings.removeZoom) { model.removeSelectedZoom() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - One text

    private func selectedTextSection(_ overlay: RecorderTextOverlay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.selectLaneItem(.text, id: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text(strings.backToOptions)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
            .keyboardShortcut(.escape, modifiers: [])
            sectionTitle(strings.thisTextLabel)

            TextField(strings.textPlaceholder, text: Binding(
                get: { overlay.text },
                set: { value in model.updateSelectedText { $0.text = value } }),
                      axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .focused($textFieldFocused)
                .onSubmit { model.commitZoomEdit() }
                .onChange(of: textFieldFocused) { _, focused in
                    if !focused { model.commitZoomEdit() }
                }
                .onDisappear { model.commitZoomEdit() }

            valueSlider(title: strings.textSizeLabel,
                        value: overlay.size,
                        range: RecorderTextOverlay.sizeRange,
                        format: "%.0f%%",
                        scale: 100,
                        onChange: { value in model.updateSelectedText { $0.size = value } },
                        onCommit: { model.commitZoomEdit() },
                        onReset: {
                            model.updateSelectedText { $0.size = 0.06 }
                            model.commitZoomEdit()
                        })

            VStack(alignment: .leading, spacing: 5) {
                Text(strings.textPositionLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.72))
                anchorGrid(overlay)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(strings.textColorLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.72))
                HStack(spacing: 6) {
                    ForEach(RecorderTextOverlay.Palette.allCases, id: \.rawValue) { palette in
                        let parts = palette.components
                        Circle()
                            .fill(Color(.sRGB, red: parts.red, green: parts.green,
                                        blue: parts.blue, opacity: 1))
                            .frame(width: 20, height: 20)
                            .overlay {
                                Circle().strokeBorder(
                                    overlay.palette == palette
                                        ? Color.accentColor : Color.white.opacity(0.18),
                                    lineWidth: overlay.palette == palette ? 2.5 : 1)
                            }
                            .onTapGesture {
                                model.updateSelectedText { $0.palette = palette }
                                model.commitZoomEdit()
                            }
                    }
                }
            }

            Button(strings.removeText) { model.removeSelectedText() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
    }

    /// Nine places instead of a drag: it reads at a glance, needs no gesture
    /// on the picture, and covers what people actually do with a caption.
    private func anchorGrid(_ overlay: RecorderTextOverlay) -> some View {
        let rows: [[RecorderTextOverlay.Anchor]] = [
            [.topLeading, .top, .topTrailing],
            [.leading, .center, .trailing],
            [.bottomLeading, .bottom, .bottomTrailing],
        ]
        return VStack(spacing: 4) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(rows[row], id: \.rawValue) { anchor in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(overlay.anchor == anchor
                                  ? Color.accentColor.opacity(0.85)
                                  : Color.white.opacity(0.08))
                            .frame(height: 20)
                            .onTapGesture {
                                model.updateSelectedText { $0.anchor = anchor }
                                model.commitZoomEdit()
                            }
                    }
                }
            }
        }
    }

    /// A slider that says what it is set to and goes back to its default on a
    /// double click. A bare track with no number is the difference between a
    /// control and a guess.
    private func valueSlider(title: String,
                             value: Double,
                             range: ClosedRange<Double>,
                             format: String,
                             scale: Double = 1,
                             onChange: @escaping (Double) -> Void,
                             onCommit: @escaping () -> Void = {},
                             onReset: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.72))
                Spacer()
                Text(String(format: format, value * scale))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color(white: 0.86))
            }
            Slider(value: Binding(get: { value }, set: onChange),
                   in: range,
                   onEditingChanged: { editing in if !editing { onCommit() } })
                .controlSize(.small)
                .onTapGesture(count: 2) { onReset() }
        }
    }

    // MARK: - Pointer

    private var pointerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(strings.pointerSectionLabel)
            Toggle(strings.pointerShowToggle, isOn: boolBinding(\.showsPointer))
                .toggleStyle(.switch)
                .controlSize(.mini)
            if model.document.showsPointer {
                Picker(strings.pointerSmoothingLabel, selection: smoothingBinding) {
                    Text(strings.pointerSmoothingOff)
                        .tag(RecorderMotion.Smoothing.off.rawValue)
                    Text(strings.pointerSmoothingLight)
                        .tag(RecorderMotion.Smoothing.light.rawValue)
                    Text(strings.pointerSmoothingSmooth)
                        .tag(RecorderMotion.Smoothing.smooth.rawValue)
                    Text(strings.pointerSmoothingCinematic)
                        .tag(RecorderMotion.Smoothing.cinematic.rawValue)
                }
                .pickerStyle(.menu)
                valueSlider(title: strings.pointerSizeLabel,
                            value: model.document.pointerSize,
                            range: RecorderSupport.pointerSizeRange,
                            format: "%.2fx",
                            onChange: { doubleBinding(\.pointerSize).wrappedValue = $0 },
                            onReset: { doubleBinding(\.pointerSize).wrappedValue = 1 })
                Toggle(strings.clickRingToggle, isOn: boolBinding(\.showsClickRing))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
    }

    // MARK: - Zoom

    private var zoomSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(strings.zoomSectionLabel)
            if model.hasPointerTrack {
                Toggle(strings.zoomToggle, isOn: boolBinding(\.zoomEnabled))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            if model.document.zoomEnabled {
                valueSlider(title: strings.zoomAmountLabel,
                            value: model.document.zoomAmount,
                            range: RecorderSupport.zoomAmountRange,
                            format: "%.1fx",
                            onChange: { doubleBinding(\.zoomAmount).wrappedValue = $0 },
                            onReset: { doubleBinding(\.zoomAmount).wrappedValue = 1.8 })
                if model.hasPointerTrack {
                    Button(strings.regenerateZooms) { model.regenerateZooms() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    // MARK: - Pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(white: 0.62))
            .textCase(.uppercase)
            .kerning(0.4)
    }

    private func boolBinding(_ path: WritableKeyPath<RecorderEditDocument, Bool>) -> Binding<Bool> {
        Binding(get: { model.document[keyPath: path] },
                set: { newValue in
                    var next = model.document
                    next[keyPath: path] = newValue
                    model.document = next
                })
    }

    private func doubleBinding(
        _ path: WritableKeyPath<RecorderEditDocument, Double>
    ) -> Binding<Double> {
        Binding(get: { model.document[keyPath: path] },
                set: { newValue in
                    var next = model.document
                    next[keyPath: path] = newValue
                    model.document = next
                })
    }

    private var smoothingBinding: Binding<String> {
        Binding(get: { model.document.pointerSmoothing },
                set: { newValue in
                    var next = model.document
                    next.pointerSmoothing = newValue
                    model.document = next
                })
    }

    private var aspectBinding: Binding<String> {
        Binding(get: { model.document.aspect },
                set: { newValue in
                    var next = model.document
                    next.aspect = newValue
                    model.document = next
                })
    }
}
