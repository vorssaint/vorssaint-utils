// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The panel down the side of the editor: three looks to start from, then the
/// handful of things worth changing. Everything here changes the picture the
/// preview is already showing, so nothing has to be imagined.
struct RecorderInspector: View, Equatable {
    let model: RecorderEditorModel
    private let document: RecorderEditDocument
    private let duration: Double
    private let selectedText: RecorderTextOverlay?
    private let selectedImage: RecorderImageOverlay?
    private let selectedBlur: RecorderBlurRegion?
    private let selectedZoom: RecorderTimeline.ZoomSegment?
    private let isPickingBlurArea: Bool
    @ObservedObject private var l10n = L10n.shared
    @State private var showsBackdropPopover = false
    @State private var tab: Tab = .look
    @State private var hoveredLook: RecorderEditDocument.Look?
    /// Typing is one edit, landed when the field is let go. Without this the
    /// caption would only reach the preview on a Return, and this field takes
    /// several lines, so Return is a new line and not a commit.
    @FocusState private var textFieldFocused: Bool

    private static let width: CGFloat = 272
    private static let horizontalInset: CGFloat = 16

    init(model: RecorderEditorModel) {
        self.model = model
        document = model.document
        duration = model.duration
        selectedText = model.selectedText
        selectedImage = model.selectedImage
        selectedBlur = model.selectedBlur
        selectedZoom = model.selectedZoom
        isPickingBlurArea = model.isPickingBlurArea
    }

    // The editor's clock and trim are not inputs to the inspector. Comparing
    // its displayed values keeps playback updates out of the panel's layout.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model
            && lhs.duration == rhs.duration
            && lhs.selectedText == rhs.selectedText
            && lhs.selectedImage == rhs.selectedImage
            && lhs.selectedBlur == rhs.selectedBlur
            && lhs.selectedZoom == rhs.selectedZoom
            && lhs.isPickingBlurArea == rhs.isPickingBlurArea
            && lhs.document.backdrop == rhs.document.backdrop
            && lhs.document.aspect == rhs.document.aspect
            && lhs.document.showsPointer == rhs.document.showsPointer
            && lhs.document.pointerSmoothing == rhs.document.pointerSmoothing
            && lhs.document.pointerSize == rhs.document.pointerSize
            && lhs.document.showsClickRing == rhs.document.showsClickRing
            && lhs.document.zoomEnabled == rhs.document.zoomEnabled
            && lhs.document.zoomAmount == rhs.document.zoomAmount
            && lhs.document.zoomsOnTyping == rhs.document.zoomsOnTyping
            && lhs.document.zoomSegments.isEmpty == rhs.document.zoomSegments.isEmpty
    }

    private var strings: RecorderFeatureStrings {
        FeatureStrings.recorder(l10n.language)
    }

    private var screenshotStrings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    private enum Tab: Int {
        case look, pointer, zoom
    }

    private var backdropStyle: ScreenshotSupport.BackdropStyle { document.resolvedBackdrop }
    private var showsBackdrop: Bool { backdropStyle.kind != .none }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Selecting a zoom swaps the whole panel to that zoom. The
                // swap is what teaches the selection model, without a word.
                if let text = selectedText {
                    selectedTextSection(text)
                } else if let image = selectedImage {
                    selectedImageSection(image)
                } else if let blur = selectedBlur {
                    selectedBlurSection(blur)
                } else if let selected = selectedZoom {
                    selectedZoomSection(selected)
                } else {
                    tabPicker
                    switch tab {
                    case .look:
                        lookSection
                        Divider().opacity(0.35)
                        backgroundSection
                    case .pointer:
                        if model.hasPointerTrack {
                            pointerSection
                        } else {
                            Text(strings.noPointerNote)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    case .zoom:
                        zoomSection
                    }
                }
            }
            .padding(.horizontal, Self.horizontalInset)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.never)
        .frame(width: Self.width)
        .background(.ultraThinMaterial)
    }

    private var tabPicker: some View {
        TabPicker(labels: [strings.lookLabel, strings.pointerSectionLabel, strings.zoomSectionLabel],
                  width: Self.width - 2 * Self.horizontalInset, selection: $tab)
    }

    private struct TabPicker: NSViewRepresentable {
        let labels: [String]
        let width: CGFloat
        @Binding var selection: Tab

        func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

        func makeNSView(context: Context) -> NSSegmentedControl {
            let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne,
                                             target: context.coordinator, action: #selector(Coordinator.selectTab(_:)))
            updateNSView(control, context: context)
            return control
        }

        func updateNSView(_ control: NSSegmentedControl, context: Context) {
            let coordinator = context.coordinator
            coordinator.selection = $selection
            if coordinator.labels != labels {
                coordinator.labels = labels
                for (index, label) in labels.enumerated() { control.setLabel(label, forSegment: index) }
                let measurement = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: nil, action: nil)
                measurement.segmentDistribution = .fillEqually
                let size = measurement.intrinsicContentSize
                coordinator.size = CGSize(width: min(size.width, width), height: size.height)
                control.segmentDistribution = size.width <= width ? .fillEqually : .fillProportionally
            }
            if control.selectedSegment != selection.rawValue { control.selectedSegment = selection.rawValue }
            control.isEnabled = context.environment.isEnabled
        }

        // The control can draw in the space reserved for the panel, even
        // when its natural equal-segment width exceeds that space.
        func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
            context.coordinator.size
        }

        final class Coordinator: NSObject {
            var selection: Binding<Tab>
            var labels: [String] = []
            var size: CGSize = .zero

            init(selection: Binding<Tab>) { self.selection = selection }

            @objc func selectTab(_ sender: NSSegmentedControl) {
                if let tab = Tab(rawValue: sender.selectedSegment) { selection.wrappedValue = tab }
            }
        }
    }

    // MARK: - Look

    private var lookSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(strings.lookLabel)
            HStack(spacing: 7) {
                lookCard(.raw, title: strings.lookRaw, icon: "rectangle")
                lookCard(.clean, title: strings.lookClean,
                         icon: "cursorarrow.motionlines")
                lookCard(.studio, title: strings.lookStudio, icon: "sparkles")
            }
        }
    }

    private func lookCard(_ look: RecorderEditDocument.Look,
                          title: String,
                          icon: String) -> some View {
        let selected = document.matches(look)
        let hovered = hoveredLook == look
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                model.applyLook(look)
            }
        } label: {
            VStack(spacing: 6) {
                lookPreview(look, icon: icon)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.1)
                                   : Color.white.opacity(hovered ? 0.07 : 0.035))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.72)
                                           : Color.white.opacity(hovered ? 0.14 : 0.07),
                                  lineWidth: selected ? 1.25 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.28))
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
        .onHover { isInside in hoveredLook = isInside ? look : nil }
    }

    private func lookPreview(_ look: RecorderEditDocument.Look, icon: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(look == .studio
                      ? AnyShapeStyle(LinearGradient(colors: [Color.indigo.opacity(0.9),
                                                               Color.purple.opacity(0.55)],
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing))
                      : AnyShapeStyle(Color.black.opacity(look == .raw ? 0.82 : 0.62)))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(white: look == .raw ? 0.55 : 0.78).opacity(0.82))
                .frame(width: 31, height: 20)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                }
                .shadow(color: .black.opacity(0.24), radius: 3, y: 2)
        }
        .frame(width: 48, height: 36)
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
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
                            colors: BackdropPickerAssets.previewColors(for: backdropStyle),
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 26, height: 20)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        }
                    Text(showsBackdrop
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
                ScreenshotBackdropPopover(model: model, showsAdjustments: false)
            }

            Picker(strings.shapeLabel, selection: aspectBinding) {
                Text(strings.shapeOriginal).tag(RecorderSupport.Aspect.original.rawValue)
                Text(strings.shapeWide).tag(RecorderSupport.Aspect.wide.rawValue)
                Text(strings.shapeSquare).tag(RecorderSupport.Aspect.square.rawValue)
                Text(strings.shapeVertical).tag(RecorderSupport.Aspect.vertical.rawValue)
            }
            .pickerStyle(.menu)

            if showsBackdrop {
                VStack(spacing: 7) {
                    backgroundSlider(title: screenshotStrings.backdropPaddingLabel,
                                     value: backdropStyle.padding,
                                     onChange: { updateBackdrop(\.padding, to: $0) },
                                     onReset: { updateBackdrop(\.padding, to: 0.5) })
                    backgroundSlider(title: screenshotStrings.backdropCornersLabel,
                                     value: backdropStyle.cornerRadius,
                                     onChange: { updateBackdrop(\.cornerRadius, to: $0) },
                                     onReset: { updateBackdrop(\.cornerRadius, to: 0) })
                    backgroundSlider(title: screenshotStrings.backdropBlurLabel,
                                     value: backdropStyle.blur,
                                     onChange: { updateBackdrop(\.blur, to: $0) },
                                     onReset: { updateBackdrop(\.blur, to: 0) })
                }
                .padding(9)
                .background(Color.white.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func updateBackdrop(
        _ keyPath: WritableKeyPath<ScreenshotSupport.BackdropStyle, Double>,
        to value: Double
    ) {
        var style = model.backdropStyle
        style[keyPath: keyPath] = value
        model.backdropStyle = style
    }

    private func backgroundSlider(title: String,
                                  value: Double,
                                  onChange: @escaping (Double) -> Void,
                                  onReset: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(Color(white: 0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 50, alignment: .leading)
            Slider(value: Binding(get: { value }, set: onChange), in: 0...1)
                .controlSize(.mini)
                .onTapGesture(count: 2) { onReset() }
            Text(String(format: "%.0f%%", locale: MetricFormat.locale, value * 100))
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color(white: 0.86))
                .frame(width: 34, alignment: .trailing)
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
                        format: "%.1f×",
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
                anchorGrid(selected: overlay.anchor) { anchor in
                    model.updateSelectedText { $0.anchor = anchor }
                }
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

    // MARK: - One picture

    /// The picture itself was chosen when the block was made, so what is left
    /// here is how big it is, how solid it is and where it sits.
    private func selectedImageSection(_ overlay: RecorderImageOverlay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.selectLaneItem(.image, id: nil)
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
            sectionTitle(strings.thisImageLabel)

            Text(URL(fileURLWithPath: overlay.path).lastPathComponent)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            valueSlider(title: strings.imageSizeLabel,
                        value: overlay.size,
                        range: RecorderImageOverlay.sizeRange,
                        format: "%.0f%%",
                        scale: 100,
                        onChange: { value in model.updateSelectedImage { $0.size = value } },
                        onCommit: { model.commitZoomEdit() },
                        onReset: {
                            model.updateSelectedImage { $0.size = RecorderImageOverlay.defaultSize }
                            model.commitZoomEdit()
                        })

            valueSlider(title: strings.imageOpacityLabel,
                        value: overlay.opacity,
                        range: RecorderImageOverlay.opacityRange,
                        format: "%.0f%%",
                        scale: 100,
                        onChange: { value in model.updateSelectedImage { $0.opacity = value } },
                        onCommit: { model.commitZoomEdit() },
                        onReset: {
                            model.updateSelectedImage { $0.opacity = 1 }
                            model.commitZoomEdit()
                        })

            VStack(alignment: .leading, spacing: 5) {
                Text(strings.imagePositionLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.72))
                anchorGrid(selected: overlay.anchor) { anchor in
                    model.updateSelectedImage { $0.anchor = anchor }
                }
            }

            Button(strings.removeText) { model.removeSelectedImage() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - One blur

    /// The area is the whole thing, and it is drawn on the picture rather than
    /// typed here: a blur that misses by a few pixels is not a blur.
    private func selectedBlurSection(_ blur: RecorderBlurRegion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.selectLaneItem(.blur, id: nil)
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
            sectionTitle(strings.thisBlurLabel)

            Button {
                model.beginPickingBlurArea()
            } label: {
                Label(strings.blurPickArea, systemImage: "aqi.medium")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isPickingBlurArea)
            Text(isPickingBlurArea ? strings.blurPickAreaHint : strings.blurCaption)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let levels = ScreenshotSupport.BlurStrength.levels
            valueSlider(title: screenshotStrings.blurStrengthLabel,
                        value: Double(blur.strength),
                        range: Double(levels.lowerBound)...Double(levels.upperBound),
                        format: "%.0f",
                        step: 1,
                        onChange: { model.setSelectedBlurStrength(Int($0.rounded())) },
                        onCommit: { model.commitZoomEdit() },
                        onReset: {
                            model.setSelectedBlurStrength(ScreenshotSupport.BlurStrength.defaultLevel)
                            model.commitZoomEdit()
                        })

            Button(strings.removeZoom) { model.removeSelectedBlur() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
    }

    /// Nine places instead of a drag: it reads at a glance, needs no gesture
    /// on the picture, and covers what people actually do with a caption or a
    /// mark of their own.
    private func anchorGrid(selected: RecorderTextOverlay.Anchor,
                            onSelect: @escaping (RecorderTextOverlay.Anchor) -> Void)
        -> some View {
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
                            .fill(selected == anchor
                                  ? Color.accentColor.opacity(0.85)
                                  : Color.white.opacity(0.08))
                            .frame(height: 20)
                            .onTapGesture {
                                onSelect(anchor)
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
                             step: Double? = nil,
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
            Group {
                if let step {
                    Slider(value: Binding(get: { value }, set: onChange),
                           in: range,
                           step: step,
                           onEditingChanged: { editing in if !editing { onCommit() } })
                } else {
                    Slider(value: Binding(get: { value }, set: onChange),
                           in: range,
                           onEditingChanged: { editing in if !editing { onCommit() } })
                }
            }
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
            if document.showsPointer {
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
                            value: document.pointerSize,
                            range: RecorderSupport.pointerSizeRange,
                            format: "%.2f×",
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
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(strings.zoomSectionLabel)
            if model.hasPointerTrack {
                Toggle(strings.zoomToggle, isOn: Binding(
                    get: { model.document.zoomEnabled },
                    set: model.setAutomaticZoomEnabled))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            if document.zoomEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(strings.typingZoomToggle, isOn: Binding(
                        get: { model.document.zoomsOnTyping },
                        set: model.setTypingZoomEnabled))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    Text(strings.typingZoomCaption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if document.zoomSegments.isEmpty {
                    zoomEmptyState
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        valueSlider(title: strings.zoomAmountLabel,
                                    value: document.zoomAmount,
                                    range: RecorderSupport.zoomAmountRange,
                                    format: "%.1f×",
                                    onChange: { doubleBinding(\.zoomAmount).wrappedValue = $0 },
                                    onReset: { doubleBinding(\.zoomAmount).wrappedValue = 1.8 })
                        if model.hasPointerTrack {
                            Button(strings.regenerateZooms) { model.regenerateZooms() }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(11)
                    .background(Color.white.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
        }
    }

    private var zoomEmptyState: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 3) {
                Text(strings.zoomEmptyTitle)
                    .font(.system(size: 12, weight: .semibold))
                Text(strings.zoomEmptyCaption)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(model.canCreateAutomaticZooms
                   ? strings.createAutomaticZooms : strings.addZoomButton) {
                if model.canCreateAutomaticZooms {
                    model.regenerateZooms()
                } else {
                    model.addZoom(at: model.sourceTime)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
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
