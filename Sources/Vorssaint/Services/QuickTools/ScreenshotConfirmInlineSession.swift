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
    private var pendingOCRRecognize = false
    private var cancellables = Set<AnyCancellable>()

    var onChange: (() -> Void)?
    /// HUD sits under shielding panels; the overlay draws this feedback itself.
    var onOCRFeedback: ((String) -> Void)?

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
                guard let self, self.pendingOCRRecognize else { return }
                self.pendingOCRRecognize = false
                if words.isEmpty {
                    self.onOCRFeedback?(L10n.shared.s.ocrNoText)
                    return
                }
                // WeChat / Shottr style: outline words in the crop and wait for
                // a click or drag-select before copying — never dump everything
                // on the first recognition pass.
                self.model.clearTextSelection()
                self.onChange?()
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
        // Confirm overlay keeps the editor's medium stroke — large looked too thick.
        model.stroke = .medium
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

    /// Drawing tools always use the selection interior. Select does too once
    /// annotations or OCR words exist so taps can re-edit text / pick marks
    /// instead of panning the crop (CleanShot / WeChat). An empty select
    /// session still moves the frame.
    var usesSelectionInteriorForTools: Bool {
        if model.tool != .select { return true }
        if pendingOCRRecognize || !model.textWords.isEmpty { return true }
        return !model.annotations.isEmpty
    }

    /// Marks that should lock crop handles until the person unlocks (Shottr).
    var hasLockableAnnotations: Bool {
        !model.annotations.isEmpty
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

        if !model.textWords.isEmpty {
            // Recognized words stay lightly outlined so OCR is visible even
            // before a copy; selected ones fill like the editor.
            context.setStrokeColor(CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.55))
            context.setLineWidth(max(1, model.scale))
            for word in model.textWords {
                let rect = word.rect.insetBy(dx: -1.0 * model.scale, dy: -1.0 * model.scale)
                context.stroke(rect)
            }
            if !model.selectedWordIndexes.isEmpty {
                context.setFillColor(CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.32))
                for index in model.selectedWordIndexes where model.textWords.indices.contains(index) {
                    let rect = model.textWords[index].rect.insetBy(dx: -1.5 * model.scale,
                                                                   dy: -1.5 * model.scale)
                    context.fill(rect)
                }
            }
        }
        drawSelectionChrome(in: context)
        context.restoreGState()
    }

    /// Light dashed outline / endpoint dots so Delete has a visible target
    /// (same language as the full editor chrome, without crop grips).
    private func drawSelectionChrome(in context: CGContext) {
        guard let selectedID = model.selectedID,
              let selected = model.annotations.first(where: { $0.id == selectedID }),
              selected.id != model.editingTextID
        else { return }
        let scale = model.scale
        context.setStrokeColor(CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.9))
        context.setLineWidth(1.5 * scale)
        context.setLineDash(phase: 0, lengths: [4 * scale, 3 * scale])
        if selected.points.count >= 2, selected.tool != .freehand {
            for point in selected.points.prefix(2) {
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                let handle = CGRect(x: point.x - 4 * scale, y: point.y - 4 * scale,
                                    width: 8 * scale, height: 8 * scale)
                context.fillEllipse(in: handle)
                context.strokeEllipse(in: handle)
            }
            context.setLineDash(phase: 0, lengths: [])
            return
        }
        let box = selected.rect.insetBy(dx: -3 * scale, dy: -3 * scale)
        context.stroke(box)
        context.setLineDash(phase: 0, lengths: [])
        if selected.tool.resizesWithHandles {
            for handle in ScreenshotSupport.Handle.allCases {
                let position = handle.position(in: selected.rect)
                let dot = CGRect(x: position.x - 3.5 * scale, y: position.y - 3.5 * scale,
                                 width: 7 * scale, height: 7 * scale)
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fillEllipse(in: dot)
                context.strokeEllipse(in: dot)
            }
        }
    }

    /// OCR is scoped to the confirm crop (`model.baseImage`). First press only
    /// recognizes and shows word boxes; later presses copy the current word
    /// selection. Partial copy needs a click or drag-select first (WeChat).
    func copyOCRSelectionOrAll() {
        model.tool = .select
        onChange?()
        if !model.textWords.isEmpty {
            guard !model.selectedWordIndexes.isEmpty else {
                // Boxes are already visible — wait for a pick instead of
                // dumping the whole crop again.
                onChange?()
                return
            }
            copyText(model.selectedText)
            return
        }
        // Avoid stacking overlapping recognitions if the person mashes OCR.
        if pendingOCRRecognize { return }
        pendingOCRRecognize = true
        model.recognizeText()
    }

    /// Cmd+C while adjusting: copy a narrowed OCR selection only.
    @discardableResult
    func copyOCRSelectionIfAny() -> Bool {
        guard !model.selectedWordIndexes.isEmpty else { return false }
        copyText(model.selectedText)
        return true
    }

    private func copyText(_ text: String) {
        guard !text.isEmpty else {
            onOCRFeedback?(L10n.shared.s.ocrNoText)
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareVorssaintSource()
        pasteboard.setString(text, forType: .string)
        // Shielding panels bury QuickToolHUD; surface the same copy toast on
        // the overlay so OCR feedback is actually visible.
        onOCRFeedback?(L10n.shared.s.ocrCopied)
        onChange?()
    }

    /// Pin at the live selection's on-screen frame (original size), then the
    /// caller dismisses the capture UI — WeChat-style floating pin.
    func pin(screenFrame: CGRect) {
        prepareForExport()
        // Keep Retina pixels: the 1x-downscale preference is for files/clipboard,
        // not the floating pin (which should match the confirm preview sharpness).
        guard let export = model.exportImage(withBackdrop: false, downscaleTo1x: false)
        else { return }
        ScreenshotPinController.shared.pin(image: export.image,
                                           scale: export.scale,
                                           screenFrame: screenFrame)
        model.markExported()
    }
}
