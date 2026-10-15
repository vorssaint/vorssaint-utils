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
        var textSelectionAnchor: CGPoint?
        var selectedWordIndexes: [Int] = []
        var activeHandle: ScreenshotSupport.Handle?
        var dragRegistered = false
        var dragStart: CGPoint = .zero
        var moveOrigin: CGRect = .zero
        var movePoints: [CGPoint] = []
        init(image: CGImage) { baseImage = image }
        func clearTextSelection() {}
        func recognizeText() {}
        func recognizeQRCodes() {}
        func ensureBlurSamplesForAnnotations() {}
        func pruneCarriedRuns() {}
        func refreshDirtyState() {}
    }

    /// Command-V with a pasteboard lane that waits until the test runs it
    /// and a clipboard that is never the user's.
    enum Paste {
        final class NSPasteboard {
            static let general = NSPasteboard()
        }
        final class GeneralPasteboardAccess {
            static let shared = GeneralPasteboardAccess()
            private var pending: [() -> Void] = []
            private(set) var isRunning = false
            var queued: Int { pending.count }
            func async<T>(_ work: @escaping () -> T, then completion: @escaping (T) -> Void) {
                pending.append { [unowned self] in
                    isRunning = true
                    let value = work()
                    isRunning = false
                    completion(value)
                }
            }
            func run() {
                let jobs = pending
                pending = []
                jobs.forEach { $0() }
            }
        }
        enum ScreenshotService {
            typealias Capture = ClipboardHistoryImageEditorTests.ScreenshotSelectionController.Capture
            static var image: NSImage?
            static var reads = 0
            static var decodes = 0
            static var offLane = false
            static func clipboardImage(from pasteboard: NSPasteboard) -> NSImage? {
                reads += 1
                offLane = offLane || !GeneralPasteboardAccess.shared.isRunning
                return image
            }
            static func imageCapture(from image: NSImage) -> Capture? {
                decodes += 1
                offLane = offLane || !GeneralPasteboardAccess.shared.isRunning
                return ClipboardHistoryImageEditorTests.ScreenshotService.imageCapture(from: image)
            }
        }
        enum NSSound {
            static var beeps = 0
            static func beep() { beeps += 1 }
        }
        class Fixture {
            var window: AnyObject? = NSObject()
            let model: ScreenshotCanvasModelTests.Host
            init(model: ScreenshotCanvasModelTests.Host) { self.model = model }
        }
    }

    private static func leavingExpansion(_ suite: TestSuite) {
        let host = Host(image: ScreenshotCanvasSupportTests.image(width: 40, height: 40))
        host.tool = .expandCanvas
        host.expansionDraft = CGRect(x: 0, y: 0, width: 60, height: 40)
        host.leaveCanvasExpansion()
        suite.expect(host.tool == .expandCanvas && host.expansionDraft == nil,
                     "escape during an expansion drag drops the drag and keeps the tool")
        host.leaveCanvasExpansion()
        suite.expect(host.tool == .select && host.imageSize == CGSize(width: 40, height: 40),
                     "escape in expand canvas at rest leaves the tool like crop, without changing the canvas")
    }

    static func run(_ suite: TestSuite) {
        counterSizeAfterExpansion(suite)
        samplesAfterExpansion(suite)
        pasteFromClipboard(suite)
        pasteOnWholePixels(suite)
        spotlightAfterExpansion(suite)
        spotlightPastTheEdge(suite)
        leavingExpansion(suite)
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

    /// Older blur areas keep their block size through a new canvas, and with
    /// it a sample of their own that must not change while the user draws.
    private static func samplesAfterExpansion(_ suite: TestSuite) {
        let base = ScreenshotImageLayerTests.solid(
            NSColor(deviceRed: 0.45, green: 0.5, blue: 0.55, alpha: 1), width: 40, height: 40)
        let host = Host(image: base)
        host.annotations = [ScreenshotSupport.Annotation(tool: .pixelate,
            rect: CGRect(x: 5, y: 5, width: 30, height: 30))]
        suite.expect(host.commitCanvasExpansion(to: CGRect(x: -20, y: -20, width: 80, height: 80)),
                     "a canvas with a blur area expands")
        suite.expect(host.annotations[0].renderReferenceSize == CGSize(width: 40, height: 40),
                     "a blur area keeps the size of the canvas it was drawn on")
        let area = host.annotations[0]
        let cache = ScreenshotRenderer.ImageLayerCache()
        let original = ScreenshotRenderer.BlurSources(image: host.baseImage, imageLayerCache: cache)
        func sample() -> CGImage? {
            cache.sources(for: area, images: [], original: original)?.mosaics[area.blurLevel]
        }
        guard let first = ScreenshotImageLayerTests.renderLayers(host.baseImage, host.annotations, cache: cache)
        else {
            suite.expect(false, "an expanded blur area renders")
            return
        }
        let firstSample = sample()
        host.annotations.append(ScreenshotSupport.Annotation(tool: .arrow,
            points: [CGPoint(x: 62, y: 66), CGPoint(x: 76, y: 74)]))
        guard let second = ScreenshotImageLayerTests.renderLayers(host.baseImage, host.annotations, cache: cache)
        else { return }
        suite.expect(firstSample != nil && sample() === firstSample
                     && ScreenshotImageLayerTests.bytes(first, in: area.rect)
                        == ScreenshotImageLayerTests.bytes(second, in: area.rect),
                     "after an expansion, a mark added elsewhere keeps an older blur area's sample and noise")
    }

    /// A spotlight moves with the content like any mark and dims the whole
    /// new canvas outside its regions, where transparent margins stay
    /// transparent. Pasted images below its topmost region dim, those above
    /// stay bright, and a blur area over an image keeps its sample however
    /// the regions change.
    private static func spotlightAfterExpansion(_ suite: TestSuite) {
        let base = ScreenshotImageLayerTests.solid(
            NSColor(deviceRed: 0.8, green: 0.8, blue: 0.8, alpha: 1), width: 40, height: 40)
        let below = ScreenshotImageLayerTests.layer(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1),
                                                    CGRect(x: 25, y: 25, width: 10, height: 10))
        let spot = ScreenshotSupport.Annotation(tool: .spotlight, rect: CGRect(x: 5, y: 5, width: 10, height: 10))
        let above = ScreenshotImageLayerTests.layer(NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1),
                                                    CGRect(x: 25, y: 5, width: 10, height: 10))
        for fill in [ScreenshotCanvasSupport.Fill.transparent, .white] {
            let host = Host(image: base)
            host.expansionFill = fill
            host.annotations = [below, spot, above]
            guard host.commitCanvasExpansion(to: CGRect(x: -20, y: 0, width: 60, height: 40)),
                  let result = ScreenshotImageLayerTests.render(
                    host.baseImage, host.annotations,
                    sources: ScreenshotRenderer.BlurSources(image: host.baseImage))
            else {
                suite.expect(false, "\(fill): a canvas with a spotlight expands and exports")
                continue
            }
            func pixel(_ x: Int, _ y: Int) -> [UInt8] { ScreenshotCanvasSupportTests.pixel(result, x: x, y: y) }
            let margin = pixel(5, 20)
            suite.expect(host.annotations[1].rect == CGRect(x: 25, y: 5, width: 10, height: 10)
                         && host.annotations[1].renderReferenceSize == nil,
                         "\(fill): a spotlight region moves with the content")
            suite.expect((200...208).contains(pixel(30, 10)[0])
                         && (95...110).contains(pixel(30, 30)[0])
                         && (fill == .transparent
                             ? margin[3] == 0
                             : margin[3] == 255 && (120...135).contains(margin[0])),
                         "\(fill): the dim covers the expanded canvas outside the region and keeps clear margins clear: \(margin)")
            suite.expect((120...135).contains(pixel(50, 30)[2]) && pixel(50, 10)[1] >= 250,
                         "\(fill): an image below the spotlight dims and one above stays bright")
        }
        let area = ScreenshotSupport.Annotation(tool: .pixelate, rect: CGRect(x: 22, y: 22, width: 16, height: 16))
        let cache = ScreenshotRenderer.ImageLayerCache()
        let sources = ScreenshotRenderer.BlurSources(image: base, imageLayerCache: cache)
        let images = ScreenshotRenderer.ImageLayerCache.images(
            below: area, among: [below], textRuns: nil, imageSize: CGSize(width: 40, height: 40))
        var marks = [below, area, spot]
        // The area lies outside every region in both renders, so it dims
        // alike, and only a rebuilt sample, with new noise, changes its pixels.
        let first = ScreenshotImageLayerTests.render(base, marks, sources: sources)
        let rebuilt = ScreenshotImageLayerTests.render(
            base, marks, sources: ScreenshotRenderer.BlurSources(
                image: base, imageLayerCache: ScreenshotRenderer.ImageLayerCache()))
        marks[2].rect = CGRect(x: 2, y: 2, width: 6, height: 6)
        marks.append(ScreenshotSupport.Annotation(tool: .spotlight, rect: CGRect(x: 20, y: 0, width: 8, height: 8)))
        let second = ScreenshotImageLayerTests.render(base, marks, sources: sources)
        guard let first, let rebuilt, let second else {
            suite.expect(false, "a blur area over an image renders beside spotlight regions")
            return
        }
        let firstBytes = ScreenshotImageLayerTests.bytes(first, in: area.rect)
        suite.expect(!images.isEmpty && firstBytes != ScreenshotImageLayerTests.bytes(rebuilt, in: area.rect),
                     "a blur area over an image gets new noise with a new sample")
        suite.expect(firstBytes == ScreenshotImageLayerTests.bytes(second, in: area.rect),
                     "drawing or moving spotlight regions keeps the sample of a blur area over an image")
    }

    /// Only the part of a spotlight region on the image lights anything, so
    /// an expansion keeps just that part: what lay past the old edge must
    /// not light the new margin, and a region that lit nothing must not
    /// start dimming the canvas.
    private static func spotlightPastTheEdge(_ suite: TestSuite) {
        let base = ScreenshotImageLayerTests.solid(
            NSColor(deviceRed: 0.8, green: 0.8, blue: 0.8, alpha: 1), width: 40, height: 40)
        let grow = CGRect(x: 0, y: 0, width: 60, height: 40)
        let overshooting = Host(image: base)
        overshooting.annotations = [ScreenshotSupport.Annotation(
            tool: .spotlight, rect: CGRect(x: 30, y: 5, width: 16, height: 10))]
        if overshooting.commitCanvasExpansion(to: grow),
           let result = ScreenshotImageLayerTests.render(
            overshooting.baseImage, overshooting.annotations,
            sources: ScreenshotRenderer.BlurSources(image: overshooting.baseImage)) {
            let beside = ScreenshotCanvasSupportTests.pixel(result, x: 43, y: 10)
            let margin = ScreenshotCanvasSupportTests.pixel(result, x: 50, y: 30)
            suite.expect(overshooting.annotations.map(\.rect) == [CGRect(x: 30, y: 5, width: 10, height: 10)]
                         && (200...208).contains(ScreenshotCanvasSupportTests.pixel(result, x: 35, y: 10)[0])
                         && (120...135).contains(beside[0]) && (120...135).contains(margin[0]),
                         "a spotlight region past the old edge lights only the content it covered: \(beside) \(margin)")
        } else {
            suite.expect(false, "a canvas with a region past its edge expands and exports")
        }
        let outside = Host(image: base)
        outside.annotations = [ScreenshotSupport.Annotation(
            tool: .spotlight, rect: CGRect(x: 45, y: 5, width: 10, height: 10))]
        if outside.commitCanvasExpansion(to: grow),
           let result = ScreenshotImageLayerTests.render(
            outside.baseImage, outside.annotations,
            sources: ScreenshotRenderer.BlurSources(image: outside.baseImage)) {
            let content = ScreenshotCanvasSupportTests.pixel(result, x: 20, y: 20)
            let margin = ScreenshotCanvasSupportTests.pixel(result, x: 50, y: 30)
            suite.expect(outside.annotations.isEmpty && (200...208).contains(content[0]) && margin[0] >= 250,
                         "a spotlight region off the image still dims nothing after an expansion toward it: \(content) \(margin)")
        } else {
            suite.expect(false, "a canvas with a region off its image expands and exports")
        }
    }

    /// A layer off the pixel grid is resampled with every export, so an odd
    /// size difference or a fractional drag would blur a pasted screenshot.
    private static func pasteOnWholePixels(_ suite: TestSuite) {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 31, pixelsHigh: 20,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<20 {
            for x in 0..<31 {
                let level: CGFloat = x % 2 == 0 ? 0 : 1
                bitmap.setColor(NSColor(deviceRed: level, green: level, blue: level, alpha: 1), atX: x, y: y)
            }
        }
        let stripes = bitmap.cgImage!
        let source = ScreenshotImageLayerTests.bytes(stripes, in: CGRect(x: 0, y: 0, width: 31, height: 20))
        let host = Host(image: ScreenshotImageLayerTests.solid(
            NSColor(deviceRed: 0.45, green: 0.5, blue: 0.55, alpha: 1), width: 40, height: 40))
        func exported() -> [UInt8] {
            guard let rect = host.annotations.first?.rect,
                  let image = ScreenshotImageLayerTests.render(host.baseImage, host.annotations, sources: .none)
            else { return [] }
            return ScreenshotImageLayerTests.bytes(image, in: rect)
        }
        suite.expect(host.pasteImage(stripes), "a paste narrower than the canvas by an odd width succeeds")
        let pasted = host.annotations.first?.rect ?? .zero
        suite.expect(pasted == CGRect(x: 4, y: 10, width: 31, height: 20) && exported() == source,
                     "a paste centered on an odd size difference sits on whole pixels and exports pixel for pixel: \(pasted)")
        host.moveOrigin = pasted
        host.dragStart = CGPoint(x: 10, y: 10)
        host.continueSelectDrag(to: CGPoint(x: 12.3, y: 13.7))
        let moved = host.annotations.first?.rect ?? .zero
        suite.expect(moved == CGRect(x: pasted.minX + 2, y: pasted.minY + 4, width: 31, height: 20)
                     && exported() == source,
                     "a pasted image dragged by a fractional distance stays on whole pixels: \(moved)")
    }

    private static func pasteFromClipboard(_ suite: TestSuite) {
        let lane = Paste.GeneralPasteboardAccess.shared
        let service = Paste.ScreenshotService.self
        service.reads = 0
        service.decodes = 0
        service.offLane = false
        Paste.NSSound.beeps = 0
        service.image = NSImage(cgImage: ScreenshotCanvasSupportTests.image(width: 30, height: 20),
                                size: NSSize(width: 30, height: 20))
        let host = Paste.Host(model: Host(image: ScreenshotCanvasSupportTests.image(width: 40, height: 40)))
        host.pasteImageFromClipboard()
        suite.expect(service.reads == 0 && lane.queued == 1,
                     "Command-V leaves the clipboard read to the pasteboard lane")
        lane.run()
        suite.expect(service.reads == 1 && service.decodes == 1 && !service.offLane,
                     "the clipboard image is read and decoded on the pasteboard lane")
        let pasted = host.model.annotations.first
        suite.expect(host.model.annotations.count == 1 && pasted?.imageAsset?.image.width == 30
                     && pasted?.rect.size == CGSize(width: 30, height: 20) && Paste.NSSound.beeps == 0,
                     "the clipboard image lands as a layer, pixel for pixel")
        host.pasteImageFromClipboard()
        host.window = nil
        lane.run()
        suite.expect(host.model.annotations.count == 1 && Paste.NSSound.beeps == 0,
                     "a clipboard read that finishes after the editor closed pastes nothing")
        host.window = NSObject()
        service.image = nil
        host.pasteImageFromClipboard()
        lane.run()
        suite.expect(host.model.annotations.count == 1 && Paste.NSSound.beeps == 1,
                     "a clipboard without an image beeps")
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
