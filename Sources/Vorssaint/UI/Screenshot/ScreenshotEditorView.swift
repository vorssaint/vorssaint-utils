// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

/// Screenshot annotation editor with a tool rail, actions, contextual styles
/// and a shared renderer for the canvas and exported image.
/// Carries the hovered tool button's frame up to the root, so its label can be
/// drawn outside the scroll view that holds the rail.
private struct ToolAnchor: Equatable {
    let tool: ScreenshotSupport.Tool
    let bounds: Anchor<CGRect>
}

private struct ToolAnchorKey: PreferenceKey {
    static let defaultValue: ToolAnchor? = nil

    static func reduce(value: inout ToolAnchor?, nextValue: () -> ToolAnchor?) {
        value = nextValue() ?? value
    }
}

struct ScreenshotEditorView: View {
    @ObservedObject var model: ScreenshotEditorModel
    let controller: ScreenshotEditorController
    @ObservedObject private var l10n = L10n.shared

    @State private var editingText = ""
    @FocusState private var textFieldFocused: Bool
    @State private var dragInFlight = false
    @State private var dragStartView: CGPoint = .zero
    @State private var appeared = false
    @State private var backdropPopoverShown = false
    @State private var hoveredTool: ScreenshotSupport.Tool?
    @State private var isDropTargeted = false
    @State private var lastTapAt: Date?
    @State private var lastTapPoint: CGPoint = .zero
    @State private var editingCounterText = ""
    @State private var toolOptionsShown = false
    @State private var sharing = false
    @State private var sharedRecord: ScreenshotShareRecord?
    @AppStorage(DefaultsKey.screenshotToolOrder) private var toolOrderRaw =
        ScreenshotSupport.Tool.defaultOrderStorage
    @AppStorage(DefaultsKey.screenshotToolShortcutsEnabled) private var toolShortcutsEnabled = true
    @AppStorage(DefaultsKey.screenshotSharingEnabled) private var sharingEnabled = true

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    private var recentCapturesTitle: String {
        FeatureStrings.recentCaptures(l10n.language).title
    }

    var body: some View {
        // Real rows and columns, not overlays: the canvas scrolls in its own
        // region, so zoomed content can never slide under the controls.
        ZStack {
            artboard
            VStack(spacing: 0) {
                topBand
                    .padding(.top, 10)
                    .padding(.horizontal, 12)
                HStack(spacing: 0) {
                    ScrollView(.vertical) {
                        toolRail
                    }
                    .scrollIndicators(.never)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, 10)
                    canvasArea
                }
                .padding(.top, 6)
                bottomRow
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
            }
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 2)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        // The system tooltip waits a second, says only the name, and is turned
        // off entirely on the newest macOS. This one answers the moment the
        // pointer lands, and it is drawn at the root so the tool rail's scroll
        // view cannot clip it.
        .overlayPreferenceValue(ToolAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let frame = proxy[anchor.bounds]
                    toolHoverLabel(anchor.tool)
                        .fixedSize()
                        // Positioned by its leading edge: centring it on the
                        // button's right edge made it straddle the icon.
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .offset(x: frame.maxX + 10, y: frame.midY - 13)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            acceptDroppedImage(providers)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: model.tool)
        .animation(.easeOut(duration: 0.16), value: model.annotationShadowsEnabled)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: model.backdropStyle)
        .sheet(item: $sharedRecord) { record in
            ScreenshotEditorSharedLinkView(record: record,
                                           strings: strings,
                                           close: { sharedRecord = nil })
        }
    }

    /// The window's crown: the brand centered like the menu bar panel, the
    /// actions on the right, the trash for a capture not worth keeping.
    private var topBand: some View {
        ZStack {
            BrandMark(width: 40, tint: Color(white: 0.92))
            HStack {
                Spacer()
                actionCluster
            }
        }
        .frame(height: 38)
    }

    // MARK: - Artboard

    /// Dark canvas surface shared by the editor chrome.
    private var artboard: some View {
        Rectangle()
            .fill(Color(white: 0.115))
            .overlay {
                LinearGradient(colors: [Color.white.opacity(0.035), .clear],
                               startPoint: .top, endPoint: .bottom)
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }

    // MARK: - Canvas

    private var contentPixelSize: CGSize {
        let pad = model.backdropPaddingPixels
        return CGSize(width: model.imageSize.width + pad * 2,
                      height: model.imageSize.height + pad * 2)
    }

    private var canvasArea: some View {
        GeometryReader { proxy in
            let zoom = zoomFactor(available: proxy.size)
            let canvasSize = CGSize(width: contentPixelSize.width * zoom,
                                    height: contentPixelSize.height * zoom)
            ScrollView([.horizontal, .vertical]) {
                canvas(zoom: zoom, canvasSize: canvasSize)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .padding(canvasInsets(available: proxy.size, canvas: canvasSize))
            }
            .scrollIndicators(.never)
            // Trackpad pinch, anchored at the zoom the gesture started from.
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        let base = magnifyBase
                            ?? (model.zoomOverride ?? model.currentDisplayZoom)
                        magnifyBase = base
                        model.setZoom(base * value)
                    }
                    .onEnded { _ in magnifyBase = nil }
            )
        }
    }

    @State private var magnifyBase: CGFloat?

    // Margin around the capture inside its scroll region.
    private static let canvasMargin: CGFloat = 14

    private func zoomFactor(available: CGSize) -> CGFloat {
        let zoom: CGFloat
        if let override = model.zoomOverride {
            zoom = override
        } else {
            let width = max(available.width - Self.canvasMargin * 2, 80)
            let height = max(available.height - Self.canvasMargin * 2, 80)
            let fit = min(width / max(contentPixelSize.width, 1),
                          height / max(contentPixelSize.height, 1))
            // Small captures grow to a practical editing size. This affects
            // only the canvas; exported pixels stay untouched.
            zoom = min(fit, 1)
        }
        // Pinch and scroll zoom start from what is actually on screen.
        model.currentDisplayZoom = zoom
        return zoom
    }

    private func canvasInsets(available: CGSize, canvas: CGSize) -> EdgeInsets {
        EdgeInsets(top: max((available.height - canvas.height) / 2, Self.canvasMargin),
                   leading: max((available.width - canvas.width) / 2, Self.canvasMargin),
                   bottom: max((available.height - canvas.height) / 2, Self.canvasMargin),
                   trailing: max((available.width - canvas.width) / 2, Self.canvasMargin))
    }

    private func canvas(zoom: CGFloat, canvasSize: CGSize) -> some View {
        let outerRadius = model.showsBackdrop
            ? 6
            : max(4, model.cardCornerPixels * zoom)
        return ZStack {
            if model.showsBackdrop {
                backdropFillView
                    .scaleEffect(1 + CGFloat(model.backdropStyle.blur) * 0.08)
                    .blur(radius: ScreenshotSupport.backdropBlurRadius(
                        for: contentPixelSize,
                        factor: CGFloat(model.backdropStyle.blur)) * zoom)
            }
            Canvas { context, size in
                context.withCGContext { cg in
                    drawContent(cg, size: size, zoom: zoom)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: outerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.30), radius: 24, y: 10)
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        .scaleEffect(appeared ? 1 : 0.965)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                appeared = true
            }
        }
        .gesture(canvasGesture(zoom: zoom))
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let point = imagePoint(from: location, zoom: zoom)
                if model.tool != .select, model.selectedAnnotationOwns(point) {
                    NSCursor.openHand.set()
                } else if model.tool != .select {
                    NSCursor.crosshair.set()
                } else if model.wordIndex(at: point) != nil {
                    // Recognized text under the cursor reads as text.
                    NSCursor.iBeam.set()
                } else {
                    NSCursor.arrow.set()
                }
            case .ended:
                NSCursor.arrow.set()
            }
        }
        .overlay(alignment: .topLeading) {
            textEditorOverlay(zoom: zoom)
        }
        .overlay(alignment: .topLeading) {
            counterEditorOverlay(zoom: zoom)
        }
        .overlay(alignment: .topLeading) {
            cropLoupeOverlay(zoom: zoom, canvasSize: canvasSize)
        }
    }

    /// The live backdrop layer, matching exactly what the exporter paints.
    @ViewBuilder
    private var backdropFillView: some View {
        switch model.backdropFill {
        case .none:
            EmptyView()
        case .colors(let components):
            if components.count == 1, let single = components.first {
                Color(.sRGB, red: single.red, green: single.green, blue: single.blue, opacity: 1)
            } else {
                LinearGradient(colors: components.map {
                    Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: 1)
                }, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        case .image(let image):
            // The overlay clips aspect-fill overflow to the backdrop bounds.
            Rectangle()
                .fill(.clear)
                .overlay {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                }
                .clipped()
        }
    }

    private func drawContent(_ cg: CGContext, size: CGSize, zoom: CGFloat) {
        let pad = model.backdropPaddingPixels * zoom
        let imageRect = CGRect(x: pad, y: pad,
                               width: model.imageSize.width * zoom,
                               height: model.imageSize.height * zoom)

        if model.showsBackdrop {
            // The capture sits on the fill like a card: soft shadow and the
            // user's corner rounding, exactly what the exporter composes.
            let corner = model.cardCornerPixels * zoom
            let path = CGPath(roundedRect: imageRect,
                              cornerWidth: corner, cornerHeight: corner, transform: nil)
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: -5), blur: 18,
                         color: CGColor(gray: 0, alpha: 0.38))
            cg.addRect(CGRect(origin: .zero, size: size))
            cg.addPath(path)
            cg.clip(using: .evenOdd)
            cg.addPath(path)
            cg.setFillColor(CGColor(gray: 1, alpha: 1))
            cg.fillPath()
            cg.restoreGState()
            cg.saveGState()
            cg.addPath(path)
            cg.clip()
            drawImageUpright(cg, in: imageRect, canvasHeight: size.height)
            cg.restoreGState()
        } else {
            drawImageUpright(cg, in: imageRect, canvasHeight: size.height)
        }

        cg.saveGState()
        cg.scaleBy(x: zoom, y: zoom)
        cg.translateBy(x: model.backdropPaddingPixels, y: model.backdropPaddingPixels)
        if model.showsBackdrop {
            // The exporter composes annotations before the backdrop, so they
            // never spill onto the margin; the live canvas must agree.
            cg.clip(to: CGRect(origin: .zero, size: model.imageSize))
        }
        ScreenshotRenderer.drawAnnotations(model.annotations,
                                           in: cg,
                                           pixelated: model.pixelated,
                                           imageSize: model.imageSize,
                                           scale: model.scale,
                                           annotationShadowsEnabled: model.annotationShadowsEnabled,
                                           skippingText: model.editingTextID)
        drawTextSelection(cg)
        drawSelectionChrome(cg)
        drawCropChrome(cg, canvasSize: size, zoom: zoom)
        cg.restoreGState()
    }

    /// Highlight for recognized words selected on the canvas.
    private func drawTextSelection(_ cg: CGContext) {
        guard !model.selectedWordIndexes.isEmpty else { return }
        cg.setFillColor(CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.32))
        for index in model.selectedWordIndexes where model.textWords.indices.contains(index) {
            let rect = model.textWords[index].rect.insetBy(dx: -1.5 * model.scale,
                                                           dy: -1.5 * model.scale)
            let path = CGPath(roundedRect: rect,
                              cornerWidth: 2 * model.scale, cornerHeight: 2 * model.scale,
                              transform: nil)
            cg.addPath(path)
            cg.fillPath()
        }
    }

    private func drawImageUpright(_ cg: CGContext, in rect: CGRect, canvasHeight: CGFloat) {
        cg.saveGState()
        cg.translateBy(x: 0, y: canvasHeight)
        cg.scaleBy(x: 1, y: -1)
        let flipped = CGRect(x: rect.minX,
                             y: canvasHeight - rect.maxY,
                             width: rect.width,
                             height: rect.height)
        cg.draw(model.baseImage, in: flipped)
        cg.restoreGState()
    }

    // MARK: - Gestures

    private func canvasGesture(zoom: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = imagePoint(from: value.location, zoom: zoom)
                if !dragInFlight {
                    dragInFlight = true
                    dragStartView = value.location
                    commitEditingTextIfNeeded()
                    model.beginDrag(at: point)
                } else {
                    model.continueDrag(to: point)
                }
            }
            .onEnded { value in
                dragInFlight = false
                let point = imagePoint(from: value.location, zoom: zoom)
                // A second click on a counter opens its number rather than
                // dropping another badge next to it.
                let now = Date()
                let repeated = lastTapAt.map {
                    now.timeIntervalSince($0) <= NSEvent.doubleClickInterval
                        && hypot(value.location.x - lastTapPoint.x,
                                 value.location.y - lastTapPoint.y) < 6
                } ?? false
                lastTapAt = now
                lastTapPoint = value.location
                if repeated, model.beginCounterEditing(at: point) {
                    lastTapAt = nil
                    return
                }
                if repeated, model.beginTextEditing(at: point) {
                    lastTapAt = nil
                    return
                }
                // A click is a click in screen points, whatever the zoom.
                let isTap = hypot(value.location.x - dragStartView.x,
                                  value.location.y - dragStartView.y) < 7
                if isTap, model.tool == .text || model.tool == .sticker || model.tool == .counter,
                   !CGRect(origin: .zero, size: model.imageSize).contains(point) {
                    return
                }
                model.endDrag(at: point, isTap: isTap)
                if model.editingTextID != nil {
                    editingText = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        textFieldFocused = true
                    }
                }
            }
    }

    private func imagePoint(from viewPoint: CGPoint, zoom: CGFloat) -> CGPoint {
        let pad = model.backdropPaddingPixels
        return CGPoint(x: viewPoint.x / zoom - pad, y: viewPoint.y / zoom - pad)
    }

    // MARK: - Crop loupe

    private static let cropLoupeSize: CGFloat = 72

    @ViewBuilder
    private func cropLoupeOverlay(zoom: CGFloat, canvasSize: CGSize) -> some View {
        if let point = model.cropLoupePoint {
            // A crop edge sits between pixels, not on one, so this loupe wants an
            // even sample side to put that edge in the middle of the frame — the
            // opposite of what the capture loupe's color read needs.
            let sourceRect = ScreenshotSupport.cropLoupeSampleRect(
                around: point,
                imageSize: model.imageSize,
                sideLength: 14,
                centredOnPixel: false)
            if let sample = model.baseImage.cropping(to: sourceRect) {
                let size = Self.cropLoupeSize
                let crossX = min(max((point.x - sourceRect.minX) / sourceRect.width * size, 0.5),
                                 size - 0.5)
                let crossY = min(max((point.y - sourceRect.minY) / sourceRect.height * size, 0.5),
                                 size - 0.5)
                ZStack(alignment: .topLeading) {
                    Image(decorative: sample, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: size, height: size)
                    Rectangle()
                        .fill(Color.black.opacity(0.72))
                        .frame(width: 1, height: size)
                        .offset(x: crossX - 0.5)
                    Rectangle()
                        .fill(Color.black.opacity(0.72))
                        .frame(width: size, height: 1)
                        .offset(y: crossY - 0.5)
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 1)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                        .frame(width: 7, height: 7)
                        .offset(x: crossX - 3.5, y: crossY - 3.5)
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
                .position(cropLoupePosition(for: point, zoom: zoom, canvasSize: canvasSize))
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
    }

    private func cropLoupePosition(for point: CGPoint,
                                   zoom: CGFloat,
                                   canvasSize: CGSize) -> CGPoint {
        let size = Self.cropLoupeSize
        let half = size / 2
        let gap: CGFloat = 14
        let pad = model.backdropPaddingPixels
        let anchor = CGPoint(x: (point.x + pad) * zoom,
                             y: (point.y + pad) * zoom)
        var x = anchor.x + half + gap
        var y = anchor.y - half - gap
        if x + half > canvasSize.width { x = anchor.x - half - gap }
        if y - half < 0 { y = anchor.y + half + gap }
        if canvasSize.width >= size {
            x = min(max(x, half), canvasSize.width - half)
        } else {
            x = canvasSize.width / 2
        }
        if canvasSize.height >= size {
            y = min(max(y, half), canvasSize.height - half)
        } else {
            y = canvasSize.height / 2
        }
        return CGPoint(x: x, y: y)
    }

    // MARK: - Selection and crop chrome

    private func drawSelectionChrome(_ cg: CGContext) {
        guard let selectedID = model.selectedID,
              // A text being typed already sits inside a bordered field; the
              // selection box on top of it was two frames around one thing.
              selectedID != model.editingTextID,
              let selected = model.annotations.first(where: { $0.id == selectedID })
        else { return }
        let scale = model.scale
        cg.setStrokeColor(CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.9))
        cg.setLineWidth(1.5 * scale)
        cg.setLineDash(phase: 0, lengths: [4 * scale, 3 * scale])
        if selected.points.count >= 2, selected.tool != .freehand {
            for point in selected.points.prefix(2) {
                cg.setFillColor(CGColor(gray: 1, alpha: 1))
                let handle = CGRect(x: point.x - 4 * scale, y: point.y - 4 * scale,
                                    width: 8 * scale, height: 8 * scale)
                cg.fillEllipse(in: handle)
                cg.strokeEllipse(in: handle)
            }
            return
        }
        let box = selected.tool == .counter
            ? counterBox(selected)
            : selected.rect.insetBy(dx: -3 * scale, dy: -3 * scale)
        cg.stroke(box)
        cg.setLineDash(phase: 0, lengths: [])
        if selected.tool.resizesWithHandles {
            let handleBox = selected.tool == .counter
                ? counterBox(selected).insetBy(dx: 3, dy: 3)
                : selected.rect
            for handle in selected.tool.resizeHandles {
                let position = handle.position(in: handleBox)
                let dot = CGRect(x: position.x - 3.5 * scale, y: position.y - 3.5 * scale,
                                 width: 7 * scale, height: 7 * scale)
                cg.setFillColor(CGColor(gray: 1, alpha: 1))
                cg.fillEllipse(in: dot)
                cg.strokeEllipse(in: dot)
            }
        }
    }

    private func counterBox(_ annotation: ScreenshotSupport.Annotation) -> CGRect {
        let diameter = ScreenshotSupport.counterDiameter(for: annotation,
                                                         imageSize: model.imageSize)
        return CGRect(x: annotation.rect.midX - diameter / 2,
                      y: annotation.rect.midY - diameter / 2,
                      width: diameter,
                      height: diameter).insetBy(dx: -3, dy: -3)
    }

    private func drawCropChrome(_ cg: CGContext, canvasSize: CGSize, zoom: CGFloat) {
        guard model.tool == .crop, let draft = model.cropDraft else { return }
        let scale = model.scale
        let pad = model.backdropPaddingPixels
        cg.setFillColor(CGColor(gray: 0, alpha: 0.45))
        cg.beginPath()
        cg.addRect(CGRect(x: -pad, y: -pad,
                          width: canvasSize.width / zoom, height: canvasSize.height / zoom))
        cg.addRect(draft)
        cg.fillPath(using: .evenOdd)
        cg.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
        cg.setLineWidth(1.5 * scale)
        cg.stroke(draft)
        for handle in ScreenshotSupport.Handle.allCases {
            let position = handle.position(in: draft)
            let radius = 4 * scale
            // A crop grip belongs to the edge itself. Do not push full-image
            // grips inward just to keep the entire circle visible.
            let dot = CGRect(x: position.x - radius, y: position.y - radius,
                             width: 8 * scale, height: 8 * scale)
            cg.setFillColor(CGColor(gray: 1, alpha: 1))
            cg.fillEllipse(in: dot)
        }
    }

    // MARK: - Inline text editing

    @ViewBuilder
    private func counterEditorOverlay(zoom: CGFloat) -> some View {
        if let editingID = model.editingCounterID,
           let annotation = model.annotations.first(where: { $0.id == editingID }) {
            let pad = model.backdropPaddingPixels
            TextField("", text: $editingCounterText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(width: 46, height: 24)
                .background(.black.opacity(0.45), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1))
                .offset(x: (annotation.rect.midX + pad) * zoom - 23,
                        y: (annotation.rect.midY + pad) * zoom - 12)
                .onAppear { editingCounterText = "\(annotation.number)" }
                .onSubmit { model.commitCounterEditing(editingID, number: Int(editingCounterText)) }
                .onExitCommand { model.commitCounterEditing(editingID, number: nil) }
        }
    }

    @ViewBuilder
    private func textEditorOverlay(zoom: CGFloat) -> some View {
        if let editingID = model.editingTextID,
           let annotation = model.annotations.first(where: { $0.id == editingID }) {
            let fontSize = max(11, ScreenshotRenderer.textFont(annotation,
                                                               scale: model.scale).pointSize * zoom)
            let pad = model.backdropPaddingPixels
            TextField(strings.textPlaceholder, text: $editingText)
                .textFieldStyle(.plain)
                // The field shows the face the mark carries, so a chosen font
                // is visible while typing rather than only after leaving.
                .font(annotation.fontName.map { Font.custom($0, size: fontSize) }
                        ?? .system(size: fontSize, weight: .semibold))
                .foregroundStyle(Color(nsColor: ScreenshotRenderer.nsColor(annotation.color)))
                .focused($textFieldFocused)
                // The field takes its width from what is typed, not from the
                // canvas it sits on: left to itself it stretched to the far
                // edge of the window and stopped answering to the text.
                .frame(minWidth: 44, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1)
                )
                .offset(x: (annotation.rect.minX + pad) * zoom - 6,
                        y: (annotation.rect.minY + pad) * zoom - 3)
                .onAppear {
                    editingText = annotation.text
                    DispatchQueue.main.async { textFieldFocused = true }
                }
                .onSubmit {
                    model.commitText(editingID, text: editingText)
                }
                .onExitCommand {
                    model.commitText(editingID, text: editingText)
                }
        }
    }

    /// A dropped image opens an editor of its own rather than replacing the
    /// one under the pointer, whose annotations are someone's work in progress.
    private func acceptDroppedImage(_ providers: [NSItemProvider]) -> Bool {
        let identifier = UTType.fileURL.identifier
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(identifier)
        }) else { return false }
        provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
            let url: URL?
            if let itemURL = item as? URL {
                url = itemURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }
            guard let url else { return }
            DispatchQueue.main.async {
                ScreenshotService.shared.openEditor(imageAt: url)
            }
        }
        return true
    }

    /// Everything that takes the pointer elsewhere goes through here, so a
    /// number or a text left mid-edit is kept rather than needing Return.
    private func commitEditingTextIfNeeded() {
        if let editingID = model.editingTextID {
            model.commitText(editingID, text: editingText)
        }
        if let counterID = model.editingCounterID {
            model.commitCounterEditing(counterID, number: Int(editingCounterText))
        }
    }

    // MARK: - Tool rail

    private func toolHoverLabel(_ tool: ScreenshotSupport.Tool) -> some View {
        let shortcutNumber = ScreenshotSupport.Tool.shortcutNumber(
            for: tool,
            orderRaw: toolOrderRaw,
            enabled: toolShortcutsEnabled)
        return HStack(spacing: 5) {
            Text(tool.screenshotTitle(strings))
                .font(.system(size: 11, weight: .medium))
            if let shortcutNumber {
                Text("\(shortcutNumber)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.1), in: Capsule())
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }

    private var orderedTools: [ScreenshotSupport.Tool] {
        ScreenshotSupport.Tool.ordered(from: toolOrderRaw)
    }

    private var toolRail: some View {
        VStack(spacing: 2) {
            ForEach(orderedTools, id: \.self) { tool in
                railButton(tool)
            }
            Divider()
                .frame(width: 22)
                .padding(.vertical, 2)
            Button {
                toolOptionsShown.toggle()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 33, height: 29)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(toolOptionsShown
                                    ? Color.accentColor.opacity(0.22) : .clear)
                    )
                    .foregroundStyle(toolOptionsShown ? Color.accentColor : Color.secondary)
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.borderless)
            .screenshotSafeHelp(strings.toolShortcutsTitle)
            .accessibilityLabel(strings.toolShortcutsTitle)
            .popover(isPresented: $toolOptionsShown, arrowEdge: .leading) {
                ScreenshotToolOrderControls(orderRaw: $toolOrderRaw,
                                            shortcutsEnabled: $toolShortcutsEnabled)
                    .padding(14)
                    .frame(width: 340)
            }
        }
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 5)
    }

    private func railButton(_ tool: ScreenshotSupport.Tool) -> some View {
        let isActive = model.tool == tool
        let isHovered = hoveredTool == tool
        let shortcutNumber = ScreenshotSupport.Tool.shortcutNumber(
            for: tool,
            orderRaw: toolOrderRaw,
            enabled: toolShortcutsEnabled)
        return Button {
            commitEditingTextIfNeeded()
            model.tool = tool
        } label: {
            Image(systemName: tool.screenshotSymbolName)
                .font(.system(size: 13.5, weight: .medium))
                .symbolEffect(.bounce, value: isActive)
                .frame(width: 33, height: 29)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isActive
                                ? Color.accentColor.opacity(0.22)
                                : isHovered ? Color.primary.opacity(0.08) : .clear)
                )
                .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.85))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .scaleEffect(isHovered && !isActive ? 1.06 : 1)
                .overlay(alignment: .topTrailing) {
                    if let shortcutNumber {
                        Text("\(shortcutNumber)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                            .padding(2)
                            .opacity(isHovered || isActive ? 0.9 : 0)
                    }
                }
        }
        .buttonStyle(.borderless)
        .anchorPreference(key: ToolAnchorKey.self, value: .bounds) { anchor in
            hoveredTool == tool ? ToolAnchor(tool: tool, bounds: anchor) : nil
        }
        .onHover { inside in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                hoveredTool = inside ? tool : (hoveredTool == tool ? nil : hoveredTool)
            }
        }
        .screenshotSafeHelp(tool.screenshotTitle(strings)
            + (shortcutNumber.map { "  (\($0))" } ?? ""))
        .accessibilityLabel(tool.screenshotTitle(strings))
    }

    // MARK: - QR code (shown only when the capture holds one)

    /// Opens the shared result panel that spells out the code's content, with
    /// copy and open actions.
    private var qrControl: some View {
        Button {
            controller.showQRResult()
        } label: {
            Image(systemName: "qrcode")
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .tint(.accentColor)
        .screenshotSafeHelp(l10n.s.qrResultTitle)
        .accessibilityLabel(l10n.s.qrResultTitle)
    }

    // MARK: - Action cluster (top right)

    private var actionCluster: some View {
        HStack(spacing: 4) {
            Button {
                RecentCaptureService.shared.showHistoryWindow()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .screenshotSafeHelp(recentCapturesTitle)
            .accessibilityLabel(recentCapturesTitle)

            Divider().frame(height: 16).padding(.horizontal, 3)

            Button {
                controller.discardAndClose()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .screenshotSafeHelp(strings.discardConfirm)
            .accessibilityLabel(strings.discardConfirm)

            Divider().frame(height: 16).padding(.horizontal, 3)

            // The window's key monitor claims ⌘Z first and swallows it, but it
            // steps aside whenever a text field holds the responder chain, and
            // the editor answered nothing at all in that state. The buttons
            // carry the standard shortcut so the window behaves like any other
            // Mac window whichever path the key takes, and they commit a text
            // being typed before undoing it out of existence.
            Button {
                commitEditingTextIfNeeded()
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!model.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            Button {
                commitEditingTextIfNeeded()
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!model.canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])

            if model.qrReading != nil {
                Divider().frame(height: 16).padding(.horizontal, 3)
                qrControl
                    .transition(.scale.combined(with: .opacity))
            }

            Divider().frame(height: 16).padding(.horizontal, 3)

            Button {
                commitEditingTextIfNeeded()
                controller.pin()
            } label: {
                Image(systemName: "pin")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .screenshotSafeHelp(strings.pinButton + "  (⌘P)")
            .accessibilityLabel(strings.pinButton)

            Divider().frame(height: 16).padding(.horizontal, 3)

            if sharingEnabled {
                shareMenu
                Divider().frame(height: 16).padding(.horizontal, 3)
            }

            Menu {
                Button(strings.saveButton) {
                    commitEditingTextIfNeeded()
                    controller.save()
                }
                Button(strings.saveAsButton) {
                    commitEditingTextIfNeeded()
                    controller.saveAs()
                }
            } label: {
                Text(strings.saveButton)
            } primaryAction: {
                commitEditingTextIfNeeded()
                controller.save()
            }
            .fixedSize()
            .screenshotSafeHelp("⌘S")

            Button(strings.copyButton) {
                commitEditingTextIfNeeded()
                controller.copyToClipboard()
            }
            .buttonStyle(.borderedProminent)
            .screenshotSafeHelp("⏎")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 4)
    }

    private var shareMenu: some View {
        Menu {
            ForEach(ScreenshotShareDuration.allCases) { duration in
                Button(duration.title(strings)) {
                    commitEditingTextIfNeeded()
                    sharing = true
                    controller.share(duration: duration) { record in
                        sharing = false
                        sharedRecord = record
                    }
                }
            }
        } label: {
            Group {
                if sharing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "link")
                }
            }
            .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(sharing)
        .screenshotSafeHelp(sharing ? strings.sharingHUD : strings.shareButton)
        .accessibilityLabel(strings.shareButton)
    }

    // MARK: - Bottom row

    private var showsColorControls: Bool {
        switch model.tool {
        case .arrow, .line, .rect, .ellipse, .ellipseFilled, .freehand, .highlight,
             .text, .counter, .redact:
            return true
        case .select:
            guard let selectedID = model.selectedID,
                  let selected = model.annotations.first(where: { $0.id == selectedID })
            else { return false }
            return selected.tool != .sticker
        case .pixelate:
            return true
        case .sticker, .crop:
            return false
        }
    }

    /// The tool the style bar is speaking for: the active one, or the shape
    /// that is selected while the pointer tool is in hand.
    private var styledTool: ScreenshotSupport.Tool? {
        guard model.tool == .select else { return model.tool }
        guard let selectedID = model.selectedID,
              let selected = model.annotations.first(where: { $0.id == selectedID })
        else { return nil }
        return selected.tool
    }

    /// A text mark reads its size from its own handles now, so the width picker
    /// gives up its place to the face the glyphs are drawn with.
    private var showsFontControls: Bool {
        styledTool == .text || styledTool == .counter
    }

    /// Families installed on this Mac, the system font first so the default is
    /// one click away rather than buried in the alphabet.
    private var fontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }

    private var fontMenu: some View {
        Menu {
            Button(systemFontLabel) {
                model.applyTextFont(nil)
            }
            Divider()
            ForEach(fontFamilies, id: \.self) { family in
                Button(family) { model.applyTextFont(family) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "textformat")
                    .font(.system(size: 10, weight: .semibold))
                Text(model.textFontName ?? systemFontLabel)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: 110)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var systemFontLabel: String {
        NSFont.systemFont(ofSize: 12).familyName ?? "System"
    }

    /// An arrow is the one mark whose ends mean something, so where its heads
    /// sit belongs in the bar rather than in a preference nobody would find.
    private var showsArrowControls: Bool {
        styledTool == .arrow
    }

    private func arrowHeadButton(_ heads: ScreenshotSupport.ArrowHeads) -> some View {
        let selected = model.arrowHeads == heads
        return Button {
            model.applyArrowHeads(heads)
        } label: {
            Image(systemName: heads.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 20)
                .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.75))
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.16) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.borderless)
    }

    /// The pixelate mark has no outline but it does have a coarseness, so the
    /// width picker's place is taken by the strength that mark actually reads.
    private var showsBlurControls: Bool {
        styledTool == .pixelate
    }

    /// A width picker that changes nothing is worse than no picker, so it only
    /// appears for the tools that actually draw an outline.
    private var showsStrokeControls: Bool {
        guard let styledTool else { return false }
        return styledTool.usesStroke
    }

    /// Depth only means something once a shape is picked, and only when there
    /// is something else for it to pass.
    private var showsLayerControls: Bool {
        model.selectedID != nil && model.annotations.count > 1
    }

    /// Each direction dims on its own once the shape reaches that end, so the
    /// buttons never offer a move that would do nothing.
    private func canMoveSelected(_ move: ScreenshotSupport.LayerMove) -> Bool {
        guard let selectedID = model.selectedID else { return false }
        return ScreenshotSupport.canReorder(model.annotations, moving: selectedID, move)
    }

    private func layerButton(_ move: ScreenshotSupport.LayerMove,
                             symbol: String,
                             label: String) -> some View {
        Button {
            commitEditingTextIfNeeded()
            model.moveSelected(move)
        } label: {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .disabled(!canMoveSelected(move))
        .screenshotSafeHelp(label)
        .accessibilityLabel(label)
    }

    private var showsStickerControls: Bool {
        if model.tool == .sticker { return true }
        guard model.tool == .select,
              let selectedID = model.selectedID,
              let selected = model.annotations.first(where: { $0.id == selectedID })
        else { return false }
        return selected.tool == .sticker
    }

    private var bottomRow: some View {
        // One row, no stacking: the chips can never collide with the style
        // bar on a narrow window.
        HStack(alignment: .center, spacing: 10) {
            infoChip
            Spacer(minLength: 6)
            if model.tool == .crop, model.cropDraft != nil {
                cropBar
            } else {
                styleBar
            }
            Spacer(minLength: 6)
            zoomChip
        }
    }

    private var styleBar: some View {
        HStack(spacing: 10) {
            if showsStickerControls {
                stickerMenu
                Divider().frame(height: 16)
            }
            if showsColorControls {
                HStack(spacing: 4) {
                    ForEach(ScreenshotSupport.ColorID.allCases, id: \.self) { colorID in
                        colorDot(colorID)
                    }
                }
                Divider().frame(height: 16)
                if showsFontControls {
                    fontMenu
                    Divider().frame(height: 16)
                }
                if showsArrowControls {
                    HStack(spacing: 3) {
                        ForEach(ScreenshotSupport.ArrowHeads.allCases, id: \.self) { heads in
                            arrowHeadButton(heads)
                        }
                    }
                    Divider().frame(height: 16)
                }
                if showsBlurControls {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.dotted")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Slider(value: Binding(get: { model.pixelateStrength },
                                              set: { model.applyPixelateStrength($0) }),
                               in: 0...1)
                            .frame(width: 96)
                        Text("\(Int(model.pixelateStrength * 100))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                    Divider().frame(height: 16)
                }
                if showsStrokeControls {
                    HStack(spacing: 3) {
                        ForEach(ScreenshotSupport.StrokeID.allCases, id: \.self) { stroke in
                            strokeGlyph(stroke)
                        }
                    }
                    Divider().frame(height: 16)
                }
            }
            if showsLayerControls {
                layerButton(.backward, symbol: "square.2.layers.3d.bottom.filled",
                            label: strings.sendBackward)
                layerButton(.forward, symbol: "square.2.layers.3d.top.filled",
                            label: strings.bringForward)
                Divider().frame(height: 16)
            }
            annotationShadowButton
            Divider().frame(height: 16)
            backdropButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 12, y: 3)
    }

    private var stickerMenu: some View {
        Menu {
            ForEach(ScreenshotSupport.StickerID.allCases, id: \.self) { sticker in
                Button {
                    model.sticker = sticker
                } label: {
                    HStack {
                        Text(sticker.glyph)
                        if model.sticker == sticker {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(model.sticker.glyph)
                    .font(.system(size: 16))
                Text(strings.toolSticker)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .frame(height: 24)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .screenshotSafeHelp(strings.toolSticker)
        .accessibilityLabel(strings.toolSticker)
    }

    private var cropBar: some View {
        HStack(spacing: 8) {
            Button(strings.cancel) {
                model.tool = .select
            }
            Button(strings.cropApply) {
                model.applyCrop()
            }
            .buttonStyle(.borderedProminent)
            .screenshotSafeHelp("⏎")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 3)
    }

    private func colorDot(_ colorID: ScreenshotSupport.ColorID) -> some View {
        let selected = model.color == colorID
        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                model.color = colorID
            }
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
            .scaleEffect(selected ? 1.05 : 1)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(strings.colorLabel)
    }

    /// Line-weight glyphs with three increasing stroke widths.
    private func strokeGlyph(_ stroke: ScreenshotSupport.StrokeID) -> some View {
        let selected = model.stroke == stroke
        let height: CGFloat = switch stroke {
        case .small: 1.8
        case .medium: 3.4
        case .large: 5.4
        }
        return Button {
            model.stroke = stroke
        } label: {
            Capsule()
                .fill(selected ? Color.accentColor : Color.primary.opacity(0.6))
                .frame(width: 15, height: height)
                .frame(width: 25, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.18) : .clear)
                )
        }
        .buttonStyle(.borderless)
        .screenshotSafeHelp(strings.strokeLabel)
        .accessibilityLabel(strings.strokeLabel)
    }

    private var annotationShadowButton: some View {
        Button {
            model.annotationShadowsEnabled.toggle()
        } label: {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 25, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(model.annotationShadowsEnabled
                                ? Color.accentColor.opacity(0.20) : .clear)
                )
                .foregroundStyle(model.annotationShadowsEnabled
                                    ? Color.accentColor : Color.primary.opacity(0.65))
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.borderless)
        .screenshotSafeHelp(strings.shadowLabel)
        .accessibilityLabel(strings.shadowLabel)
        .accessibilityAddTraits(model.annotationShadowsEnabled ? .isSelected : [])
    }

    private var backdropButton: some View {
        // A plain view with an explicit tap gesture: every point of the
        // control opens the popover, swatch included, with a hover wash so
        // it reads as one button.
        HStack(spacing: 6) {
            Group {
                switch model.backdropStyle.sanitized().kind {
                case .none:
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.85))
                case .image:
                    Image(systemName: "photo.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.85))
                case .preset, .solid, .gradient:
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(fillPreview(for: model.backdropStyle))
                        .frame(width: 21, height: 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                        )
                }
            }
            Text(strings.backdropLabel)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(backdropButtonHovered ? Color.primary.opacity(0.10) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { inside in backdropButtonHovered = inside }
        .onTapGesture { backdropPopoverShown.toggle() }
        .screenshotSafeHelp(strings.backdropLabel)
        .accessibilityLabel(strings.backdropLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { backdropPopoverShown.toggle() }
        .popover(isPresented: $backdropPopoverShown, arrowEdge: .top) {
            ScreenshotBackdropPopover(model: model)
        }
    }

    @State private var backdropButtonHovered = false

    private func fillPreview(for style: ScreenshotSupport.BackdropStyle) -> LinearGradient {
        let colors = BackdropPickerAssets.previewColors(for: style)
        return LinearGradient(colors: colors,
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Corner chips

    private var infoChip: some View {
        HStack(spacing: 8) {
            dragOutHandle
            Text(dimensionsLabel)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private var zoomChip: some View {
        HStack(spacing: 3) {
            zoomButton(active: model.zoomOverride == nil, help: "⌘0") {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 11, weight: .medium))
            } action: {
                model.zoomOverride = nil
            }
            Text(zoomPercentLabel)
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 38)
                .lineLimit(1)
                .fixedSize()
            zoomButton(active: isActualZoom, help: "⌘1") {
                Text("1:1")
                    .font(.system(size: 11, weight: .medium))
            } action: {
                model.zoomOverride = 1 / model.scale
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .screenshotSafeHelp("⌃ scroll · ⌘+ ⌘-")
    }

    private func zoomButton<Label: View>(active: Bool,
                                         help: String,
                                         @ViewBuilder label: () -> Label,
                                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .frame(width: 30, height: 20)
                .background(active ? Color.accentColor : .clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(active ? Color.white : Color.primary.opacity(0.85))
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.borderless)
        .screenshotSafeHelp(help)
    }

    private var isActualZoom: Bool {
        guard let override = model.zoomOverride else { return false }
        return abs(override - 1 / model.scale) < 0.001
    }

    private var zoomPercentLabel: String {
        let zoom = model.zoomOverride ?? model.currentDisplayZoom
        return "\(Int((zoom * model.scale * 100).rounded()))%"
    }

    private var dimensionsLabel: String {
        let width = Int(model.imageSize.width)
        let height = Int(model.imageSize.height)
        let retina = model.scale > 1 ? "  @\(Int(model.scale))x" : ""
        return "\(width) × \(height) px\(retina)"
    }

    /// A draggable thumbnail that exports the flattened PNG.
    private var dragOutHandle: some View {
        Image(nsImage: NSImage(cgImage: model.baseImage,
                               size: NSSize(width: 22, height: 22 * model.imageSize.height
                                                / max(model.imageSize.width, 1))))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 26, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
            )
            .onDrag {
                commitEditingTextIfNeeded()
                guard let image = model.exportImage(),
                      let provider = ScreenshotService.dragItemProvider(image: image,
                                                                        strings: strings)
                else { return NSItemProvider() }
                model.markExported()
                return provider
            }
            .screenshotSafeHelp(strings.editorTitle)
    }

}

private struct ScreenshotEditorSharedLinkView: View {
    let record: ScreenshotShareRecord
    let strings: ScreenshotFeatureStrings
    let close: () -> Void
    @State private var deleting = false
    @State private var showingDeleteError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(strings.sharedLinksTitle, systemImage: "link")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(strings.done, action: close)
                    .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(record.url.absoluteString)
                    .font(.system(.body, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 4) {
                    Text(strings.expiresLabel)
                    Text(record.expiresAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }

            HStack {
                Spacer()
                Button {
                    if ScreenshotShareService.shared.copy(record.url) {
                        QuickToolHUD.show(icon: "link", message: strings.sharedHUD)
                    } else {
                        NSSound.beep()
                    }
                } label: {
                    Label(strings.copyLink, systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: .command)
                Button(role: .destructive) {
                    deleteLink()
                } label: {
                    if deleting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(strings.deleteLink, systemImage: "trash")
                    }
                }
                .disabled(deleting)
            }
        }
        .padding(20)
        .frame(width: 480)
        .alert(strings.deleteFailedHUD, isPresented: $showingDeleteError) {
            Button(strings.done, role: .cancel) {}
        }
    }

    private func deleteLink() {
        deleting = true
        Task { @MainActor in
            do {
                try await ScreenshotShareService.shared.delete(record)
                QuickToolHUD.show(icon: "link", message: strings.linkDeletedHUD)
                close()
            } catch {
                deleting = false
                showingDeleteError = true
            }
        }
    }
}

extension ScreenshotSupport.Tool {
    var screenshotSymbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .freehand: return "scribble.variable"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .sticker: return "face.smiling"
        case .counter: return "1.circle"
        case .pixelate: return "aqi.medium"
        case .redact: return "rectangle.fill"
        case .ellipseFilled: return "circle.fill"
        case .crop: return "crop"
        }
    }

    func screenshotTitle(_ strings: ScreenshotFeatureStrings) -> String {
        switch self {
        case .select: return strings.toolSelect
        case .arrow: return strings.toolArrow
        case .line: return strings.toolLine
        case .rect: return strings.toolRect
        case .ellipse: return strings.toolEllipse
        case .freehand: return strings.toolFreehand
        case .highlight: return strings.toolHighlight
        case .text: return strings.toolText
        case .sticker: return strings.toolSticker
        case .counter: return strings.toolCounter
        case .pixelate: return strings.toolPixelate
        case .redact: return strings.toolRedact
        case .ellipseFilled: return strings.toolEllipseFilled
        case .crop: return strings.toolCrop
        }
    }
}

extension View {
    /// SwiftUI's system tooltip bridge crashes on the current macOS 27 beta
    /// while routing hover events. Keep accessibility labels everywhere and
    /// use native hover help on earlier systems.
    @ViewBuilder
    func screenshotSafeHelp(_ text: String) -> some View {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            self
        } else {
            help(text)
        }
    }
}
