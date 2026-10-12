// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum ScreenshotCanvasModelTests {
    class Fixture {
        var baseImage: CGImage
        var imageSize: CGSize { CGSize(width: baseImage.width, height: baseImage.height) }
        var annotations: [ScreenshotSupport.Annotation] = []
        var selectedID: UUID?
        var editingTextID: UUID?
        var newTextID: UUID?
        var cropDraft: CGRect?
        let scale: CGFloat = 1
        var tool: ScreenshotSupport.Tool = .select
        var expansionFill = ScreenshotCanvasSupport.Fill.white
        var expansionDraft: CGRect?
        var expansionHandle: ScreenshotSupport.Handle?
        var expansionStartPoint: CGPoint?
        var expansionRejected = false
        var pixelated: [Int: CGImage] = [:]
        var softBlurred: [Int: CGImage] = [:]
        var textRuns: [CGRect]?
        var textWords: [ScreenshotSupport.RecognizedWord] = []
        var carriedRuns: [ObjectIdentifier: [CGRect]] = [:]
        var undoStack: [(image: CGImage, annotations: [ScreenshotSupport.Annotation])] = []
        var redoStack: [(image: CGImage, annotations: [ScreenshotSupport.Annotation])] = []
        static let undoLimit = 60
        var canUndo = false, canRedo = false, isDirty = false
        init(image: CGImage) { baseImage = image }
        func clearTextSelection() {}
        func recognizeText() {}
        func recognizeQRCodes() {}
        func ensureBlurSamplesForAnnotations() {}
        func pruneCarriedRuns() {}
        func refreshDirtyState() {}
    }

    static func run(_ suite: TestSuite) {
        counterSizeAfterExpansion(suite)
        let base = ScreenshotCanvasSupportTests.image(width: 40, height: 40)
        let host = Host(image: base)
        let pasted = ScreenshotCanvasSupportTests.image(width: 20, height: 10)
        suite.expect(host.pasteImage(pasted), "valid paste succeeds")
        let id = host.selectedID
        let center = CGPoint(x: 20, y: 20)
        suite.expect(host.hitTest(center) == id, "image is selectable as a whole object")
        suite.expect(host.hitTest(center, includeShapeInteriors: false) == nil,
                     "image interiors remain available for new text and stickers")
        suite.expect(host.annotations.count == 1 && host.annotations[0].id == id,
                     "paste appends and selects a single object")
        suite.expect(host.commitCanvasExpansion(to: CGRect(x: -10, y: -20, width: 50, height: 60)),
                     "expansion commits")
        suite.expect(host.annotations[0].rect.origin == CGPoint(x: 20, y: 35),
                     "image shifts with the old content")
        suite.expect(host.undoStack.count == 2, "paste and expansion each produce one history entry")
        host.undo()
        suite.expect(host.baseImage === base && host.annotations[0].id == id, "undo expansion preserves paste")
        host.undo()
        suite.expect(host.annotations.isEmpty, "undo paste removes only the pasted object")
        host.redo()
        host.redo()
        suite.expect(host.baseImage.width == 50 && host.annotations[0].id == id, "redo restores both edits")
        let count = host.undoStack.count
        let current = host.baseImage
        suite.expect(!host.commitCanvasExpansion(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
                     "an invalid expansion is rejected")
        suite.expect(host.baseImage === current && host.undoStack.count == count,
                     "failure leaves image and history unchanged")
    }

    private static func counterSizeAfterExpansion(_ suite: TestSuite) {
        let context = CGContext(data: nil, width: 800, height: 800,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 800))
        let host = Host(image: context.makeImage()!)
        host.annotations = [ScreenshotSupport.Annotation(tool: .counter,
            rect: CGRect(x: 100, y: 100, width: 0, height: 0), number: 1)]
        suite.expect(host.commitCanvasExpansion(to: CGRect(x: 0, y: 0, width: 1600, height: 1600)),
                     "large canvas expansion commits without resizing existing counters")
        guard let image = ScreenshotImageLayerTests.renderLayers(host.baseImage, host.annotations,
            cache: ScreenshotRenderer.ImageLayerCache()) else {
            suite.expect(false, "expanded counter exports")
            return
        }
        let inside = ScreenshotCanvasSupportTests.pixel(image, x: 112, y: 100)
        let outside = ScreenshotCanvasSupportTests.pixel(image, x: 125, y: 100)
        suite.expect(inside[0] > inside[1] && outside == [255, 255, 255, 255],
                     "rendered counter keeps its original diameter after expansion")
        host.undo()
        suite.expect(host.annotations[0].renderReferenceSize == nil,
                     "undo restores the counter's original rendering state")
    }
}
