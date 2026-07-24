// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI
import Vision

/// Everything the annotation editor can do to one capture: the mutable
/// document (image, annotations, undo history) and the export paths. The
/// SwiftUI editor view observes this model; geometry is in image pixels.
final class ScreenshotEditorModel: ObservableObject {
    @Published private(set) var baseImage: CGImage
    @Published var annotations: [ScreenshotSupport.Annotation] = []
    @Published var selectedID: UUID?
    @Published var editingTextID: UUID?
    @Published var tool: ScreenshotSupport.Tool {
        didSet {
            UserDefaults.standard.set(tool.rawValue, forKey: DefaultsKey.screenshotLastTool)
            if tool != .select { clearTextSelection() }
            if tool == .crop, oldValue != .crop {
                selectedID = nil
                cropDraft = CGRect(origin: .zero, size: imageSize)
            } else if oldValue == .crop {
                cropDraft = nil
                cropLoupePoint = nil
            }
        }
    }
    /// Words recognized in the capture and selectable with the select tool.
    @Published private(set) var textWords: [ScreenshotSupport.RecognizedWord] = []
    @Published private(set) var selectedWordIndexes: [Int] = []
    private var textSelectionAnchor: CGPoint?
    /// A QR code found in the capture, offered as a copy or open action.
    @Published private(set) var qrReading: BarcodeDetector.Reading?
    @Published var color: ScreenshotSupport.ColorID {
        didSet {
            UserDefaults.standard.set(color.rawValue, forKey: DefaultsKey.screenshotLastColor)
            applyStyleToSelection()
        }
    }
    @Published var stroke: ScreenshotSupport.StrokeID {
        didSet {
            UserDefaults.standard.set(stroke.rawValue, forKey: DefaultsKey.screenshotLastStroke)
            applyStyleToSelection()
        }
    }
    @Published var sticker: ScreenshotSupport.StickerID {
        didSet {
            UserDefaults.standard.set(sticker.rawValue,
                                      forKey: DefaultsKey.screenshotLastSticker)
            applyStickerToSelection()
        }
    }
    @Published var annotationShadowsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(annotationShadowsEnabled,
                                      forKey: DefaultsKey.screenshotAnnotationShadows)
            refreshDirtyState()
        }
    }
    /// The full backdrop configuration (kind, colors or image, margin and
    /// corner sliders), persisted as JSON and applied live on the canvas.
    @Published var backdropStyle: ScreenshotSupport.BackdropStyle {
        didSet {
            UserDefaults.standard.set(backdropStyle.encoded(),
                                      forKey: DefaultsKey.screenshotBackdropStyle)
            reloadBackdropImageIfNeeded()
            refreshDirtyState()
        }
    }
    /// Custom backdrops the user chose to keep.
    @Published private(set) var backdropPresets: [ScreenshotSupport.BackdropStyle] {
        didSet {
            UserDefaults.standard.set(
                ScreenshotSupport.encodedBackdropPresets(backdropPresets),
                forKey: DefaultsKey.screenshotBackdropPresets)
        }
    }
    /// Loaded image for an image-kind backdrop; nil when missing on disk,
    /// which quietly renders as no backdrop.
    @Published private(set) var backdropImage: CGImage?
    @Published var cropDraft: CGRect?
    /// Exact image pixel under a crop resize grip. Nil while moving the
    /// whole crop so the loupe appears only when it adds precision.
    @Published private(set) var cropLoupePoint: CGPoint?
    /// Continuous zoom (view points per image pixel); nil fits the window.
    @Published var zoomOverride: CGFloat?
    /// What the view actually laid out last, so pinch and scroll zoom start
    /// from the visible scale even in fit mode. Plain var on purpose: the
    /// view writes it during layout.
    var currentDisplayZoom: CGFloat = 0.5
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    /// True while there is work that never left the app: closing then asks.
    @Published private(set) var isDirty = false

    let scale: CGFloat
    private(set) var pixelated: CGImage?

    private var undoStack: [(image: CGImage, annotations: [ScreenshotSupport.Annotation])] = []
    private var redoStack: [(image: CGImage, annotations: [ScreenshotSupport.Annotation])] = []
    private static let undoLimit = 60
    private var cleanImage: CGImage?
    private var cleanAnnotations: [ScreenshotSupport.Annotation] = []
    private var cleanBackdropStyle = ScreenshotSupport.BackdropStyle()
    private var cleanAnnotationShadowsEnabled = false

    // Gesture state, in image pixels.
    private var dragStart: CGPoint = .zero
    private var draftID: UUID?
    private var moveOrigin: CGRect = .zero
    private var movePoints: [CGPoint] = []
    private var activeHandle: ScreenshotSupport.Handle?
    private var cropResizeOrigin: CGRect?
    private var cropMoveOrigin: CGRect?
    private var dragRegistered = false
    private var newTextID: UUID?

    var imageSize: CGSize {
        CGSize(width: baseImage.width, height: baseImage.height)
    }

    /// Natural on-screen size in points (pixels over capture scale).
    var pointSize: CGSize {
        CGSize(width: CGFloat(baseImage.width) / scale, height: CGFloat(baseImage.height) / scale)
    }

    init(image: CGImage, scale: CGFloat) {
        baseImage = image
        self.scale = scale
        let defaults = UserDefaults.standard
        var lastTool = ScreenshotSupport.Tool(
            rawValue: defaults.string(forKey: DefaultsKey.screenshotLastTool) ?? "") ?? .arrow
        if lastTool == .select || lastTool == .crop { lastTool = .arrow }
        tool = lastTool
        color = ScreenshotSupport.ColorID.sanitized(
            defaults.string(forKey: DefaultsKey.screenshotLastColor))
        stroke = ScreenshotSupport.StrokeID.sanitized(
            defaults.string(forKey: DefaultsKey.screenshotLastStroke))
        sticker = ScreenshotSupport.StickerID.sanitized(
            defaults.string(forKey: DefaultsKey.screenshotLastSticker))
        annotationShadowsEnabled = defaults.bool(
            forKey: DefaultsKey.screenshotAnnotationShadows)
        let rawStyle = defaults.string(forKey: DefaultsKey.screenshotBackdropStyle) ?? ""
        backdropStyle = ScreenshotSupport.BackdropStyle.decoded(rawStyle)
        backdropPresets = ScreenshotSupport.decodedBackdropPresets(
            defaults.string(forKey: DefaultsKey.screenshotBackdropPresets))
        pixelated = nil
        reloadBackdropImageIfNeeded()
        recordCleanState()
    }

    /// Backdrop margin in image pixels for the current settings; zero while
    /// the backdrop is off. The live canvas and the exporter share this.
    var backdropPaddingPixels: CGFloat {
        showsBackdrop
            ? ScreenshotSupport.backdropPadding(for: imageSize,
                                                factor: CGFloat(backdropStyle.padding))
            : 0
    }

    /// Corner rounding of the capture card in image pixels.
    var cardCornerPixels: CGFloat {
        ScreenshotSupport.cardCornerRadius(for: imageSize,
                                           factor: CGFloat(backdropStyle.cornerRadius))
    }

    /// True when something actually paints behind the capture (an image
    /// backdrop whose file vanished counts as nothing).
    var showsBackdrop: Bool {
        if case .none = backdropFill { return false }
        return true
    }

    /// The style resolved into what the renderer paints, shared by the live
    /// canvas and the exporter.
    var backdropFill: ScreenshotRenderer.BackdropFill {
        let style = backdropStyle.sanitized()
        switch style.kind {
        case .none:
            return .none
        case .preset:
            guard let id = style.presetID,
                  let preset = ScreenshotSupport.BackdropID(rawValue: id)
            else { return .none }
            return .colors(preset.stops)
        case .solid, .gradient:
            let colors = (style.colors ?? []).map {
                (red: $0[0], green: $0[1], blue: $0[2])
            }
            return colors.isEmpty ? .none : .colors(colors)
        case .image:
            guard let backdropImage else { return .none }
            return .image(backdropImage)
        }
    }

    private func reloadBackdropImageIfNeeded() {
        guard backdropStyle.kind == .image, let path = backdropStyle.imagePath else {
            backdropImage = nil
            return
        }
        if backdropImage != nil, loadedBackdropPath == path { return }
        loadedBackdropPath = path
        backdropImage = Self.loadBackdropImage(path)
    }

    private var loadedBackdropPath: String?

    /// Loads and caps a backdrop image; wallpapers can be 6K and the fill
    /// never needs more than the export canvas.
    private static func loadBackdropImage(_ path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Backdrop presets

    /// Keeps the current custom backdrop (colors or image) in the presets
    /// row; duplicates are ignored.
    func saveCurrentBackdropAsPreset() {
        let style = backdropStyle.sanitized()
        guard style.kind != .none, style.kind != .preset else { return }
        var snapshot = style
        // A preset is the look, not this capture's sliders.
        snapshot.padding = 0.5
        snapshot.cornerRadius = 0.1
        guard !backdropPresets.contains(where: {
            var candidate = $0
            candidate.padding = 0.5
            candidate.cornerRadius = 0.1
            return candidate == snapshot
        }) else { return }
        backdropPresets = Array((backdropPresets + [snapshot])
            .suffix(ScreenshotSupport.backdropPresetLimit))
    }

    func removeBackdropPreset(at index: Int) {
        guard backdropPresets.indices.contains(index) else { return }
        backdropPresets.remove(at: index)
    }

    // MARK: - Selectable text on the canvas

    var selectedText: String {
        ScreenshotSupport.joinedWords(textWords, selected: selectedWordIndexes)
    }

    func clearTextSelection() {
        textSelectionAnchor = nil
        if !selectedWordIndexes.isEmpty { selectedWordIndexes = [] }
    }

    func wordIndex(at point: CGPoint) -> Int? {
        textWords.firstIndex { $0.rect.insetBy(dx: -2 * scale, dy: -2 * scale).contains(point) }
    }

    /// Word-level recognition of the base capture, off the main thread; the
    /// boxes land in image pixels with their line index.
    func recognizeText() {
        let image = baseImage
        let width = CGFloat(image.width)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var words: [ScreenshotSupport.RecognizedWord] = []
            let maximumTilePixels = 12_000_000
            let tileHeight = min(image.height,
                                 max(512, min(4096,
                                     maximumTilePixels / max(image.width, 1))))
            var tileY = 0
            var lineOffset = 0
            while tileY < image.height {
                guard let current = self, image === current.baseImage else { return }
                let currentHeight = min(tileHeight, image.height - tileY)
                guard let tile = image.cropping(to: CGRect(x: 0,
                                                           y: tileY,
                                                           width: image.width,
                                                           height: currentHeight))
                else { break }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                let handler = VNImageRequestHandler(cgImage: tile, options: [:])
                try? handler.perform([request])
                let observations = request.results ?? []
                for (line, observation) in observations.enumerated() {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let text = candidate.string
                    var searchStart = text.startIndex
                    for raw in text.split(separator: " ") {
                        let word = String(raw)
                        guard let range = text.range(of: word,
                                                   range: searchStart..<text.endIndex),
                              let box = try? candidate.boundingBox(for: range)?.boundingBox
                        else { continue }
                        searchStart = range.upperBound
                        let rect = CGRect(x: box.minX * width,
                                          y: CGFloat(tileY)
                                            + (1 - box.maxY) * CGFloat(currentHeight),
                                          width: box.width * width,
                                          height: box.height * CGFloat(currentHeight))
                        words.append(ScreenshotSupport.RecognizedWord(
                            text: word,
                            rect: rect,
                            line: lineOffset + line))
                    }
                }
                lineOffset += observations.count
                tileY += currentHeight
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, image === self.baseImage else { return }
                self.textWords = words
            }
        }
    }

    /// Scans the capture for a QR code off the main thread; the result drives
    /// the copy or open action in the toolbar. Re-run whenever the base image
    /// changes (crop, undo) so a cropped out code stops being offered.
    func recognizeQRCodes() {
        let image = baseImage
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let current = self, image === current.baseImage else { return }
            let reading = BarcodeDetector.read(image)
            DispatchQueue.main.async { [weak self] in
                guard let self, image === self.baseImage else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self.qrReading = reading
                }
            }
        }
    }

    // MARK: - Zoom

    static let zoomRange: ClosedRange<CGFloat> = 0.05...3

    /// Multiplies the current zoom (pinch, ⌃ scroll, ⌘ plus and minus).
    func adjustZoom(by factor: CGFloat) {
        let current = zoomOverride ?? currentDisplayZoom
        zoomOverride = min(max(current * factor, Self.zoomRange.lowerBound),
                           Self.zoomRange.upperBound)
    }

    /// Absolute zoom for pinch gestures anchored at the gesture's start.
    func setZoom(_ zoom: CGFloat) {
        zoomOverride = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    // MARK: - Undo

    private func registerUndo() {
        undoStack.append((baseImage, annotations))
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        refreshUndoFlags()
        isDirty = true
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append((baseImage, annotations))
        restore(last)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((baseImage, annotations))
        restore(next)
    }

    private func restore(_ state: (image: CGImage, annotations: [ScreenshotSupport.Annotation])) {
        if state.image !== baseImage {
            baseImage = state.image
            pixelated = nil
            clearTextSelection()
            recognizeText()
            recognizeQRCodes()
        }
        annotations = state.annotations
        if annotations.contains(where: { $0.tool == .pixelate }) {
            ensurePixelated()
        } else {
            pixelated = nil
        }
        selectedID = nil
        editingTextID = nil
        newTextID = nil
        cropDraft = nil
        refreshUndoFlags()
        refreshDirtyState()
    }

    private func refreshUndoFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func markExported() {
        recordCleanState()
    }

    private func recordCleanState() {
        cleanImage = baseImage
        cleanAnnotations = annotations
        cleanBackdropStyle = backdropStyle.sanitized()
        cleanAnnotationShadowsEnabled = annotationShadowsEnabled
        isDirty = false
    }

    private func refreshDirtyState() {
        guard let cleanImage else { return }
        isDirty = baseImage !== cleanImage
            || annotations != cleanAnnotations
            || backdropStyle.sanitized() != cleanBackdropStyle
            || annotationShadowsEnabled != cleanAnnotationShadowsEnabled
    }

    // MARK: - Selection styling

    /// Applies color or thickness changes to the selected annotation.
    private func applyStyleToSelection() {
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID })
        else { return }
        guard annotations[index].color != color || annotations[index].stroke != stroke else { return }
        registerUndo()
        annotations[index].color = color
        annotations[index].stroke = stroke
        if annotations[index].tool == .text {
            annotations[index].rect = ScreenshotRenderer.textBounds(
                annotations[index].text,
                at: annotations[index].rect.origin,
                stroke: stroke,
                scale: scale)
        }
    }

    private func applyStickerToSelection() {
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID }),
              annotations[index].tool == .sticker,
              annotations[index].text != sticker.rawValue
        else { return }
        registerUndo()
        annotations[index].text = sticker.rawValue
    }

    // MARK: - Gestures (image-pixel coordinates)

    func beginDrag(at point: CGPoint) {
        dragStart = point
        dragRegistered = false
        switch tool {
        case .select:
            beginSelectDrag(at: point)
        case .crop:
            if let draft = cropDraft,
               let handle = ScreenshotSupport.handle(at: point, rect: draft,
                                                     tolerance: 14 * scale) {
                activeHandle = handle
                cropResizeOrigin = draft
                cropLoupePoint = handle.position(in: draft)
            } else if let draft = cropDraft, draft.contains(point) {
                cropMoveOrigin = draft
            }
        case .arrow, .line:
            registerUndo()
            dragRegistered = true
            let annotation = ScreenshotSupport.Annotation(
                tool: tool, points: [point, point], color: color, stroke: stroke)
            annotations.append(annotation)
            draftID = annotation.id
        case .freehand:
            registerUndo()
            dragRegistered = true
            let annotation = ScreenshotSupport.Annotation(
                tool: tool, points: [point], color: color, stroke: stroke)
            annotations.append(annotation)
            draftID = annotation.id
        case .rect, .ellipse, .highlight, .pixelate, .redact:
            if tool == .pixelate { ensurePixelated() }
            registerUndo()
            dragRegistered = true
            let annotation = ScreenshotSupport.Annotation(
                tool: tool, rect: CGRect(origin: point, size: .zero),
                color: color, stroke: stroke)
            annotations.append(annotation)
            draftID = annotation.id
        case .text, .sticker, .counter:
            break
        }
    }

    private func beginSelectDrag(at point: CGPoint) {
        if let selectedID,
           let selected = annotations.first(where: { $0.id == selectedID }) {
            let tolerance = 12 * scale
            if selected.tool.resizesWithHandles,
               let handle = ScreenshotSupport.handle(at: point, rect: selected.rect,
                                                     tolerance: tolerance) {
                activeHandle = handle
                moveOrigin = selected.rect
                return
            }
            if selected.points.count >= 2 {
                if hypot(point.x - selected.points[0].x, point.y - selected.points[0].y) < tolerance {
                    activeHandle = .topLeft
                    movePoints = selected.points
                    return
                }
                if hypot(point.x - selected.points[1].x, point.y - selected.points[1].y) < tolerance {
                    activeHandle = .bottomRight
                    movePoints = selected.points
                    return
                }
            }
        }
        selectedID = hitTest(point)
        if let selectedID, let hit = annotations.first(where: { $0.id == selectedID }) {
            if hit.tool == .sticker {
                self.selectedID = nil
                sticker = ScreenshotSupport.StickerID.sanitized(hit.text)
                self.selectedID = selectedID
            }
            moveOrigin = hit.rect
            movePoints = hit.points
            clearTextSelection()
        } else if let word = wordIndex(at: point) {
            // A drag over recognized text selects intersecting words.
            textSelectionAnchor = point
            selectedWordIndexes = [word]
        }
    }

    func continueDrag(to point: CGPoint) {
        switch tool {
        case .select:
            continueSelectDrag(to: point)
        case .crop:
            let bounds = CGRect(origin: .zero, size: imageSize)
            if let handle = activeHandle, let origin = cropResizeOrigin {
                let rect = ScreenshotSupport.resizedRect(origin, dragging: handle, to: point)
                let clamped = ScreenshotSupport.clamp(rect, to: bounds)
                cropDraft = clamped
                cropLoupePoint = handle.position(in: clamped)
            } else if let origin = cropMoveOrigin {
                let delta = CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y)
                cropDraft = ScreenshotSupport.movedRect(origin, by: delta, within: bounds)
            }
        case .arrow, .line:
            updateDraft { $0.points = [dragStart, point] }
        case .freehand:
            updateDraft { $0.points.append(point) }
        case .rect, .ellipse, .highlight, .pixelate, .redact:
            updateDraft { $0.rect = ScreenshotSupport.selectionRect(from: dragStart, to: point) }
        case .text, .sticker, .counter:
            break
        }
    }

    private func continueSelectDrag(to point: CGPoint) {
        if let anchor = textSelectionAnchor {
            selectedWordIndexes = ScreenshotSupport.wordSelection(
                anchor: anchor, current: point, boxes: textWords.map(\.rect))
            return
        }
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID })
        else { return }
        if !dragRegistered {
            registerUndo()
            dragRegistered = true
        }
        if let handle = activeHandle {
            if annotations[index].points.count >= 2 {
                var points = movePoints
                if handle == .topLeft { points[0] = point } else { points[1] = point }
                annotations[index].points = points
            } else {
                annotations[index].rect = ScreenshotSupport.resizedRect(
                    moveOrigin, dragging: handle, to: point)
            }
            return
        }
        let delta = CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y)
        if annotations[index].points.isEmpty {
            annotations[index].rect = moveOrigin.offsetBy(dx: delta.x, dy: delta.y)
        } else {
            annotations[index].points = movePoints.map {
                CGPoint(x: $0.x + delta.x, y: $0.y + delta.y)
            }
        }
    }

    /// `isTap` is decided by the view in screen points, so a click stays a
    /// click at any zoom level; deciding it here in image pixels made taps
    /// on zoomed-out Retina captures read as drags (the text tool bug).
    func endDrag(at point: CGPoint, isTap: Bool) {
        defer {
            draftID = nil
            activeHandle = nil
            cropResizeOrigin = nil
            cropMoveOrigin = nil
            cropLoupePoint = nil
            dragRegistered = false
        }
        switch tool {
        case .text:
            guard isTap else { return }
            if selectExistingAnnotation(at: point) { return }
            registerUndo()
            var annotation = ScreenshotSupport.Annotation(
                tool: .text, color: color, stroke: stroke)
            annotation.rect = ScreenshotRenderer.textBounds("", at: point, stroke: stroke, scale: scale)
            annotations.append(annotation)
            newTextID = annotation.id
            selectedID = annotation.id
            editingTextID = annotation.id
        case .sticker:
            guard isTap else { return }
            if selectExistingAnnotation(at: point) { return }
            registerUndo()
            let bounds = CGRect(origin: .zero, size: imageSize)
            let side = ScreenshotSupport.stickerSide(for: imageSize, scale: scale)
            let annotation = ScreenshotSupport.Annotation(
                tool: .sticker,
                rect: ScreenshotSupport.stickerRect(centeredAt: point,
                                                     side: side,
                                                     within: bounds),
                text: sticker.rawValue,
                color: color,
                stroke: stroke)
            annotations.append(annotation)
            selectedID = annotation.id
        case .counter:
            guard isTap else { return }
            if selectExistingAnnotation(at: point) { return }
            registerUndo()
            let annotation = ScreenshotSupport.Annotation(
                tool: .counter,
                rect: CGRect(x: point.x, y: point.y, width: 0, height: 0),
                color: color, stroke: stroke, number: 1)
            annotations.append(annotation)
            annotations = ScreenshotSupport.renumberingCounters(annotations)
            selectedID = annotation.id
        case .arrow, .line, .rect, .ellipse, .highlight, .pixelate, .redact, .freehand:
            if isTap {
                // A tap never leaves a degenerate shape behind; treat it as
                // picking whatever is under the cursor instead.
                annotations.removeAll { $0.id == draftID }
                if !undoStack.isEmpty { undoStack.removeLast() }
                refreshUndoFlags()
                refreshDirtyState()
                _ = selectExistingAnnotation(at: point)
            } else if let draftID {
                selectedID = draftID
            }
        case .select:
            textSelectionAnchor = nil
            if isTap, !dragRegistered {
                selectedID = hitTest(point)
                if let selectedID,
                   let hit = annotations.first(where: { $0.id == selectedID }),
                   hit.tool == .text {
                    editingTextID = selectedID
                } else if selectedID == nil, let word = wordIndex(at: point) {
                    selectedWordIndexes = [word]
                } else if selectedID == nil {
                    clearTextSelection()
                }
            }
        case .crop:
            break
        }
    }

    /// A click on an existing mark always means "edit this", even while a
    /// creation tool is active. Real drags still create with the active tool.
    /// Sticker selection updates the style picker without mutating the mark;
    /// text enters its inline editor immediately.
    @discardableResult
    private func selectExistingAnnotation(at point: CGPoint) -> Bool {
        guard let hitID = hitTest(point, includeShapeInteriors: false),
              let hit = annotations.first(where: { $0.id == hitID })
        else {
            selectedID = nil
            return false
        }
        if hit.tool == .sticker {
            selectedID = nil
            sticker = ScreenshotSupport.StickerID.sanitized(hit.text)
        }
        selectedID = hitID
        editingTextID = hit.tool == .text ? hitID : nil
        clearTextSelection()
        tool = .select
        return true
    }

    private func updateDraft(_ mutate: (inout ScreenshotSupport.Annotation) -> Void) {
        guard let draftID,
              let index = annotations.firstIndex(where: { $0.id == draftID })
        else { return }
        mutate(&annotations[index])
    }

    /// `includeShapeInteriors: false` is the creation-tap variant: area
    /// shapes (boxes, ellipses, highlights, censors) only answer near their
    /// edge, so their inside stays free for placing a new text, sticker or
    /// counter — the tap that used to create one there must keep doing so.
    func hitTest(_ point: CGPoint, includeShapeInteriors: Bool = true) -> UUID? {
        let tolerance = 10 * scale
        for annotation in annotations.reversed() {
            switch annotation.tool {
            case .arrow, .line:
                guard annotation.points.count >= 2 else { continue }
                if ScreenshotSupport.distance(from: point,
                                              toSegment: annotation.points[0],
                                              annotation.points[1])
                    <= tolerance + annotation.stroke.width * scale / 2 {
                    return annotation.id
                }
            case .freehand:
                for pathPoint in annotation.points
                where hypot(point.x - pathPoint.x, point.y - pathPoint.y) <= tolerance {
                    return annotation.id
                }
            case .counter:
                let radius = ScreenshotSupport.counterDiameter(for: imageSize, scale: 1) / 2
                if hypot(point.x - annotation.rect.midX, point.y - annotation.rect.midY)
                    <= radius + 4 * scale {
                    return annotation.id
                }
        case .rect, .ellipse, .highlight, .pixelate, .redact:
                let outer = annotation.rect.insetBy(dx: -tolerance / 2, dy: -tolerance / 2)
                guard outer.contains(point) else { continue }
                if includeShapeInteriors {
                    return annotation.id
                }
                // Edge ring only: a shape too small to have a meaningful
                // interior stays fully tappable.
                let inner = annotation.rect.insetBy(dx: tolerance, dy: tolerance)
                if inner.isEmpty || inner.width <= 0 || inner.height <= 0
                    || !inner.contains(point) {
                    return annotation.id
                }
            case .text, .sticker:
                if annotation.rect.insetBy(dx: -tolerance / 2, dy: -tolerance / 2)
                    .contains(point) {
                    return annotation.id
                }
            case .select, .crop:
                continue
            }
        }
        return nil
    }

    // MARK: - Edits

    func deleteSelected() {
        guard let selectedID else { return }
        guard annotations.contains(where: { $0.id == selectedID }) else { return }
        registerUndo()
        annotations.removeAll { $0.id == selectedID }
        annotations = ScreenshotSupport.renumberingCounters(annotations)
        self.selectedID = nil
        editingTextID = nil
        if newTextID == selectedID { newTextID = nil }
    }

    func commitText(_ id: UUID, text: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        editingTextID = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNew = newTextID == id
        if isNew, trimmed.isEmpty {
            annotations.remove(at: index)
            if selectedID == id { selectedID = nil }
            while let last = undoStack.last,
                  last.annotations.contains(where: { $0.id == id }) {
                undoStack.removeLast()
            }
            if !undoStack.isEmpty { undoStack.removeLast() }
            newTextID = nil
            refreshUndoFlags()
            refreshDirtyState()
            return
        }
        guard annotations[index].text != trimmed else {
            newTextID = nil
            return
        }
        if !isNew { registerUndo() }
        guard !trimmed.isEmpty else {
            annotations.remove(at: index)
            if selectedID == id { selectedID = nil }
            return
        }
        annotations[index].text = trimmed
        annotations[index].rect = ScreenshotRenderer.textBounds(
            trimmed,
            at: annotations[index].rect.origin,
            stroke: annotations[index].stroke,
            scale: scale)
        newTextID = nil
    }

    func applyCrop() {
        guard let draft = cropDraft else {
            tool = .select
            return
        }
        let cropRect = ScreenshotSupport.clamp(
            draft.integral,
            to: CGRect(origin: .zero, size: imageSize))
        guard cropRect.width >= 8, cropRect.height >= 8,
              let cropped = baseImage.cropping(to: cropRect)
        else {
            tool = .select
            return
        }
        registerUndo()
        baseImage = cropped
        pixelated = nil
        clearTextSelection()
        textWords = textWords.compactMap { word in
            let moved = word.rect.offsetBy(dx: -cropRect.minX, dy: -cropRect.minY)
            guard moved.intersects(CGRect(origin: .zero, size: CGSize(width: cropped.width,
                                                                      height: cropped.height)))
            else { return nil }
            return ScreenshotSupport.RecognizedWord(text: word.text, rect: moved, line: word.line)
        }
        annotations = annotations.map { annotation in
            var moved = annotation
            moved.rect = annotation.rect.offsetBy(dx: -cropRect.minX, dy: -cropRect.minY)
            moved.points = annotation.points.map {
                CGPoint(x: $0.x - cropRect.minX, y: $0.y - cropRect.minY)
            }
            return moved
        }
        if annotations.contains(where: { $0.tool == .pixelate }) {
            ensurePixelated()
        }
        cropDraft = nil
        selectedID = nil
        tool = .select
        recognizeText()
        recognizeQRCodes()
    }

    // MARK: - Output

    func exportImage(withBackdrop: Bool = true) -> CGImage? {
        if annotations.contains(where: { $0.tool == .pixelate }) {
            ensurePixelated()
        }
        let downscale = UserDefaults.standard.bool(forKey: DefaultsKey.screenshotDownscale)
        return ScreenshotRenderer.renderExport(
            baseImage: baseImage,
            annotations: annotations,
            pixelated: pixelated,
            scale: scale,
            annotationShadowsEnabled: annotationShadowsEnabled,
            style: backdropStyle.sanitized(),
            fill: withBackdrop ? backdropFill : .none,
            downscaleTo1x: downscale)
    }

    private func ensurePixelated() {
        guard pixelated == nil else { return }
        pixelated = ScreenshotRenderer.pixelatedImage(from: baseImage)
    }
}

// MARK: - Window controller

/// Hosts one editor window per capture and owns everything with a side
/// effect: clipboard, files, pins, text recognition and the close-confirm.
final class ScreenshotEditorController: NSObject, NSWindowDelegate {
    let model: ScreenshotEditorModel
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(L10n.shared.language)
    }

    init(capture: ScreenshotSelectionController.Capture) {
        model = ScreenshotEditorModel(image: capture.image, scale: capture.scale)
        super.init()
    }

    func show() {
        let content = ScreenshotEditorView(model: model, controller: self)
        let host = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: host)
        // One continuous surface: the canvas fills the window and the
        // controls float over it, so the editor reads as a single object.
        window.title = strings.editorTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Keep the editor dark so canvas contrast and popovers stay consistent.
        window.appearance = NSAppearance(named: .darkAqua)
        // Content drags edit annotations. Only the title strip moves the window.
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]

        // Chrome must equal the view's designed margins exactly (rail 64 +
        // sides, action band above, style band below), so a fresh window
        // opens with zero leftover stage around the capture.
        let screen = NSScreen.pointerVisibleFrame
        let contentSize = ScreenshotSupport.editorContentSize(
            imagePointSize: model.pointSize,
            visibleSize: screen.size)
        let minimumSize = ScreenshotSupport.editorMinimumContentSize(visibleSize: screen.size)
        window.setContentSize(contentSize)
        window.contentMinSize = minimumSize
        window.center()

        self.window = window
        installKeyMonitor()
        model.recognizeText()
        model.recognizeQRCodes()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    /// Closes without the discard confirmation used by the titlebar button.
    func discardAndClose() {
        window?.close()
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window,
                  ScreenshotSupport.editorOwnsKeyEvent(
                    eventWindowNumber: event.windowNumber,
                    editorWindowNumber: window.windowNumber,
                    editorIsKey: window.isKeyWindow)
            else { return event }
            // While a text field edits, every key belongs to it.
            if window.firstResponder is NSText || self.model.editingTextID != nil {
                return event
            }
            return self.handleKey(event) ? nil : event
        }
        // Control-scroll adjusts canvas zoom.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window,
                  ScreenshotSupport.editorOwnsKeyEvent(
                    eventWindowNumber: event.windowNumber,
                    editorWindowNumber: window.windowNumber,
                    editorIsKey: window.isKeyWindow),
                  event.modifierFlags.contains(.control)
            else { return event }
            let delta = event.scrollingDeltaY
            guard delta != 0 else { return nil }
            let clamped = max(-24, min(24, delta))
            self.model.adjustZoom(by: 1 + clamped * 0.014)
            return nil
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = Int(event.keyCode)

        if flags.contains(.command) {
            switch key {
            case kVK_ANSI_C:
                // Text selected on the canvas copies as text and keeps the
                // editor open; otherwise the capture leaves as an image.
                if !model.selectedWordIndexes.isEmpty {
                    copySelectedText()
                } else {
                    copyToClipboard()
                }
                return true
            case kVK_ANSI_S:
                if flags.contains(.shift) { saveAs() } else { save() }
                return true
            case kVK_ANSI_Z:
                if flags.contains(.shift) { model.redo() } else { model.undo() }
                return true
            case kVK_ANSI_P: pin(); return true
            case kVK_Delete, kVK_ForwardDelete:
                discardAndClose()
                return true
            case kVK_ANSI_0: model.zoomOverride = nil; return true
            case kVK_ANSI_1: model.zoomOverride = 1 / model.scale; return true
            case kVK_ANSI_Equal: model.adjustZoom(by: 1.25); return true
            case kVK_ANSI_Minus: model.adjustZoom(by: 0.8); return true
            default:
                return false
            }
        }
        guard flags.isDisjoint(with: [.command, .control, .option]) else { return false }

        switch key {
        case kVK_Delete, kVK_ForwardDelete:
            model.deleteSelected()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if model.tool == .crop, model.cropDraft != nil {
                model.applyCrop()
            } else {
                copyToClipboard()
            }
            return true
        case kVK_Escape:
            if model.tool == .crop, model.cropDraft != nil {
                model.tool = .select
            } else if !model.selectedWordIndexes.isEmpty {
                model.clearTextSelection()
            } else if model.selectedID != nil {
                model.selectedID = nil
            } else {
                window?.performClose(nil)
            }
            return true
        default:
            guard let character = event.characters?.first,
                  let number = Int(String(character)),
                  let tool = ScreenshotSupport.Tool.shortcutTool(
                    number: number,
                    orderRaw: UserDefaults.standard.string(forKey: DefaultsKey.screenshotToolOrder),
                    enabled: UserDefaults.standard.bool(
                        forKey: DefaultsKey.screenshotToolShortcutsEnabled))
            else { return false }
            model.tool = tool
            return true
        }
    }

    // MARK: Export actions

    /// Every terminal output closes the editor: the capture leaves the app
    /// and the window's job is done, so nothing lingers to tidy up.
    func copyToClipboard() {
        guard let image = model.exportImage() else { return }
        guard Self.copyImage(image) else {
            NSSound.beep()
            return
        }
        model.markExported()
        QuickToolHUD.show(icon: "camera.viewfinder", message: strings.copiedHUD)
        window?.close()
    }

    @discardableResult
    static func copyImage(_ image: CGImage) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let png = ScreenshotRenderer.pngData(from: image) {
            item.setData(png, forType: .png)
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        if let tiff = bitmap.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        return pasteboard.writeObjects([item])
    }

    func save() {
        guard let image = model.exportImage(),
              let data = ScreenshotRenderer.pngData(from: image)
        else { return }
        let (url, consumedNumber) = ScreenshotService.saveDestination(strings: strings)
        do {
            try data.write(to: url, options: .atomic)
            model.markExported()
            QuickToolHUD.show(icon: "camera.viewfinder",
                              message: String(format: strings.savedHUDFormat,
                                              url.deletingLastPathComponent().lastPathComponent))
            window?.close()
        } catch {
            if let consumedNumber {
                ScreenshotService.rewindNumberSequence(toReuse: consumedNumber)
            }
            NSSound.beep()
        }
    }

    func saveAs() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = ScreenshotSupport.fileName(
            prefix: strings.fileNamePrefix, date: Date())
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            guard let image = self.model.exportImage(),
                  let data = ScreenshotRenderer.pngData(from: image)
            else { return }
            do {
                try data.write(to: url, options: .atomic)
                self.model.markExported()
                self.window?.close()
            } catch {
                NSSound.beep()
            }
        }
    }

    /// Pinning snapshots the current export and leaves the editor open.
    func pin() {
        guard let image = model.exportImage(withBackdrop: false) else { return }
        ScreenshotPinController.shared.pin(image: image, scale: model.scale)
        model.markExported()
    }

    /// Copies the words selected on the canvas as plain text.
    func copySelectedText() {
        let text = model.selectedText
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        QuickToolHUD.show(icon: "text.viewfinder", message: L10n.shared.s.ocrCopied)
    }

    /// Shows the detected code's content in the shared result panel; the
    /// editor stays open behind it so the capture can still be worked on.
    func showQRResult() {
        guard let reading = model.qrReading else { return }
        QRResultController.shared.show(reading: reading)
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = strings.discardTitle
        alert.informativeText = strings.discardMessage
        alert.addButton(withTitle: strings.discardConfirm)
        alert.addButton(withTitle: strings.cancel)
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        window?.delegate = nil
        window = nil
        ScreenshotService.shared.editorDidClose(self)
    }
}
