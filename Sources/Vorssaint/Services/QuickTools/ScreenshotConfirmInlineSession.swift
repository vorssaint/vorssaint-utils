// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// Owns the shared editor model while a confirm-selection overlay is adjusting,
/// so the selection surface reuses real annotation tools/renderer instead of a
/// parallel toolkit.
@MainActor
final class ScreenshotConfirmInlineSession {
    let model: ScreenshotEditorModel
    private let sourceImage: CGImage
    private let scale: CGFloat
    private var selectionPixelRect: CGRect
    private var dragStartView: CGPoint?
    private var annotating = false
    private var pendingOCRCopy = false
    private var cancellables = Set<AnyCancellable>()

    var onChange: (() -> Void)?

    private init(model: ScreenshotEditorModel,
                 sourceImage: CGImage,
                 scale: CGFloat,
                 selectionPixelRect: CGRect) {
        self.model = model
        self.sourceImage = sourceImage
        self.scale = scale
        self.selectionPixelRect = selectionPixelRect
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.onChange?() }
            .store(in: &cancellables)
        model.$textWords
            .receive(on: RunLoop.main)
            .sink { [weak self] words in
                guard let self, self.pendingOCRCopy, !words.isEmpty else { return }
                self.pendingOCRCopy = false
                self.copyAllRecognizedText()
            }
            .store(in: &cancellables)
    }

    static func start(sourceImage: CGImage,
                      scale: CGFloat,
                      selectionViewRect: CGRect,
                      viewSize: CGSize) -> ScreenshotConfirmInlineSession? {
        let pixelRect = ScreenshotSupport.imagePixelRect(
            fromView: selectionViewRect,
            viewSize: viewSize,
            imageSize: CGSize(width: sourceImage.width, height: sourceImage.height))
        guard pixelRect.width >= 2, pixelRect.height >= 2,
              let cropped = sourceImage.cropping(to: pixelRect)
        else { return nil }
        let model = ScreenshotEditorModel(image: cropped, scale: scale)
        // Confirm overlay always opens on arrow, matching WeChat and the editor's
        // fallback starting tool — not select (which would only move the frame).
        model.tool = .arrow
        return ScreenshotConfirmInlineSession(
            model: model,
            sourceImage: sourceImage,
            scale: scale,
            selectionPixelRect: pixelRect)
    }

    /// Keep the floating stamp in sync with the adjustable selection. A clean
    /// session re-crops from the freeze; a dirty one keeps the annotated
    /// bitmap and only moves/scales how it is shown.
    func syncSelection(_ selectionViewRect: CGRect, viewSize: CGSize) {
        let pixelRect = ScreenshotSupport.imagePixelRect(
            fromView: selectionViewRect,
            viewSize: viewSize,
            imageSize: CGSize(width: sourceImage.width, height: sourceImage.height))
        guard pixelRect.width >= 2, pixelRect.height >= 2 else { return }
        let previous = selectionPixelRect
        let sizeChanged = abs(pixelRect.width - previous.width) > 0.5
            || abs(pixelRect.height - previous.height) > 0.5
        let moved = abs(pixelRect.minX - previous.minX) > 0.5
            || abs(pixelRect.minY - previous.minY) > 0.5
        selectionPixelRect = pixelRect
        guard !model.isDirty, sizeChanged || moved else { return }
        guard let cropped = sourceImage.cropping(to: pixelRect) else { return }
        model.resetCaptureImage(cropped)
    }

    func imagePoint(fromView point: CGPoint, selection: CGRect) -> CGPoint {
        let local = CGPoint(x: point.x - selection.minX, y: point.y - selection.minY)
        let sx = model.imageSize.width / max(selection.width, 1)
        let sy = model.imageSize.height / max(selection.height, 1)
        return CGPoint(x: local.x * sx, y: local.y * sy)
    }

    func beginAnnotation(at viewPoint: CGPoint, selection: CGRect) {
        annotating = true
        dragStartView = viewPoint
        model.beginDrag(at: imagePoint(fromView: viewPoint, selection: selection))
    }

    func continueAnnotation(to viewPoint: CGPoint, selection: CGRect) {
        guard annotating else { return }
        model.continueDrag(to: imagePoint(fromView: viewPoint, selection: selection))
    }

    func endAnnotation(at viewPoint: CGPoint, selection: CGRect) {
        guard annotating else { return }
        defer {
            annotating = false
            dragStartView = nil
        }
        let start = dragStartView ?? viewPoint
        let isTap = ScreenshotSupport.isClick(from: start, to: viewPoint)
        model.endDrag(at: imagePoint(fromView: viewPoint, selection: selection), isTap: isTap)
    }

    var isAnnotating: Bool { annotating }

    /// Drawing tools use the selection interior; select still moves the frame
    /// unless an annotation is already targeted.
    var usesSelectionInteriorForTools: Bool {
        model.tool != .select
    }

    func prepareForExport() {
        if let id = model.editingTextID {
            let text = model.annotations.first(where: { $0.id == id })?.text ?? ""
            model.commitText(id, text: text)
        }
        if model.tool == .crop, model.cropDraft != nil {
            model.applyCrop()
        }
    }

    func exportImage() -> ScreenshotRenderer.Export? {
        prepareForExport()
        return model.exportImage(withBackdrop: false)
    }

    func drawAnnotations(in context: CGContext, selection: CGRect) {
        guard selection.width > 1, selection.height > 1 else { return }
        context.saveGState()
        context.addPath(CGPath(roundedRect: selection,
                               cornerWidth: 8,
                               cornerHeight: 8,
                               transform: nil))
        context.clip()

        let zoomX = selection.width / max(model.imageSize.width, 1)
        let zoomY = selection.height / max(model.imageSize.height, 1)
        context.translateBy(x: selection.minX, y: selection.minY)
        context.scaleBy(x: zoomX, y: zoomY)
        ScreenshotRenderer.drawAnnotations(
            model.annotations,
            in: context,
            blurSources: model.blurSources,
            imageSize: model.imageSize,
            scale: model.scale,
            annotationShadowsEnabled: model.annotationShadowsEnabled,
            skippingText: model.editingTextID,
            spotlightDimStrength: model.spotlightDimStrength)

        if !model.selectedWordIndexes.isEmpty {
            context.setFillColor(CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.32))
            for index in model.selectedWordIndexes where model.textWords.indices.contains(index) {
                let rect = model.textWords[index].rect.insetBy(dx: -1.5 * model.scale,
                                                               dy: -1.5 * model.scale)
                context.fill(rect)
            }
        }
        context.restoreGState()
    }

    func copyOCRSelectionOrAll() {
        model.tool = .select
        if !model.selectedWordIndexes.isEmpty {
            copyText(model.selectedText)
            return
        }
        if !model.textWords.isEmpty {
            copyAllRecognizedText()
            return
        }
        pendingOCRCopy = true
        model.recognizeText()
    }

    private func copyAllRecognizedText() {
        let indexes = Array(model.textWords.indices)
        copyText(ScreenshotSupport.joinedWords(model.textWords, selected: indexes))
    }

    private func copyText(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareVorssaintSource()
        pasteboard.setString(text, forType: .string)
        QuickToolHUD.show(icon: "text.viewfinder", message: L10n.shared.s.ocrCopied)
    }

    func pin() {
        guard let export = exportImage() else { return }
        ScreenshotPinController.shared.pin(image: export.image, scale: export.scale)
        model.markExported()
    }
}
