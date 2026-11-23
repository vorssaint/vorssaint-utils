// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin

enum ScreenshotCanvasModelTests {
    class Fixture {
        var baseImage: CGImage
        var imageSize: CGSize { CGSize(width: baseImage.width, height: baseImage.height) }
        var annotations: [ScreenshotSupport.Annotation] = []
        var selectedID: UUID?
        var draftID: UUID?
        var editingSelectedAnnotation = false
        var color: ScreenshotSupport.ColorID = .red
        var stroke: ScreenshotSupport.StrokeID = .medium
        var arrowStyle: ScreenshotSupport.ArrowStyleID = .filled
        var sticker: ScreenshotSupport.StickerID = .check
        var textSize = 24
        var blurLevel = ScreenshotSupport.BlurStrength.defaultLevel
        var blurStyle: ScreenshotSupport.BlurStyleID = .pixelate
        var blurTextOnly = false
        var cropResizeOrigin: CGRect?
        var cropMoveOrigin: CGRect?
        var cropSelectionOrigin: CGRect?
        var cropLoupePoint: CGPoint?
        let currentDisplayZoom: CGFloat = 1
        var editingText = ""
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
        /// Mirrors the editor's memory budget: full frames dominate it, and
        /// states sharing one capture are charged once.
        static var undoByteBudget = 256 << 20
        static let undoAnnotationBytes = 512
        var canUndo = false, canRedo = false, isDirty = false
        weak var cleanImage: CGImage?
        var cleanAnnotations: [ScreenshotSupport.SavedAnnotation] = []
        let backdropStyle = ScreenshotSupport.BackdropStyle()
        var cleanBackdropStyle = ScreenshotSupport.BackdropStyle()
        let watermarkStyle = ScreenshotSupport.WatermarkStyle()
        var cleanWatermarkStyle = ScreenshotSupport.WatermarkStyle()
        let annotationShadowsEnabled = false, spotlightDimStrength: CGFloat = 0.5
        var cleanAnnotationShadowsEnabled = false, cleanSpotlightDimStrength: CGFloat = 0.5
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
        @discardableResult
        func ensureBlurSample(_ style: ScreenshotSupport.BlurStyleID, level: Int) -> Bool { true }
        func pruneCarriedRuns() {}
    }

    struct CloseController {
        struct NSWindow {}

        final class NSAlert {
            static var response = NSApplication.ModalResponse.alertSecondButtonReturn
            static var shown = 0
            var messageText = "", informativeText = ""
            var alertStyle: AppKit.NSAlert.Style = .warning
            func addButton(withTitle title: String) {}
            func runModal() -> NSApplication.ModalResponse {
                Self.shown += 1
                return Self.response
            }
        }

        let model: Host
        let strings = FeatureStrings.screenshot(.enUS)
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

    private static func closingWithInlineText(_ suite: TestSuite) {
        let model = Host(image: frame(width: 240, height: 100))
        model.markExported()
        model.tool = .text
        let controller = CloseController(model: model)
        let window = CloseController.NSWindow()
        typealias Alert = CloseController.NSAlert
        Alert.response = .alertSecondButtonReturn
        Alert.shown = 0
        func tapText() {
            let point = CGPoint(x: 20, y: 20)
            model.beginDrag(at: point)
            model.endDrag(at: point, isTap: true)
        }

        tapText()
        guard let emptyID = model.editingTextID else {
            suite.expect(false, "the text tool opens an inline draft")
            return
        }
        for blank in ["", " \t\n"] {
            model.editingText = blank
            suite.expect(controller.windowShouldClose(window) && Alert.shown == 0,
                         "an empty or whitespace-only first caption closes without a discard prompt")
        }
        model.commitText(emptyID)
        suite.expect(model.annotations.isEmpty && !model.canUndo && !model.isDirty,
                     "submitting the empty caption leaves the capture and its history clean")

        tapText()
        guard let id = model.editingTextID else {
            suite.expect(false, "the text tool can start a new caption after an empty one")
            return
        }
        model.editingText = "First"
        suite.expect(!controller.windowShouldClose(window) && Alert.shown == 1
                     && model.editingTextID == id && model.editingText == "First"
                     && model.annotations.first?.text == "" && !model.canUndo && !model.isDirty,
                     "canceling red-button close preserves the first unsubmitted caption for further typing")
        model.editingText += " caption "
        model.commitText(id)
        suite.expect(model.annotations.map(\.text) == ["First caption"] && model.undoStack.count == 1,
                     "submitting after cancel keeps the continued caption as one edit")
        model.undo()
        suite.expect(model.annotations.isEmpty && !model.canUndo && !model.isDirty,
                     "undoing the caption returns to the original clean capture")
        model.redo()
        suite.expect(model.annotations.map(\.text) == ["First caption"] && model.isDirty
                     && !controller.windowShouldClose(window) && Alert.shown == 2,
                     "redo restores the completed caption and ordinary unsaved changes still prompt")

        model.markExported()
        tapText()
        suite.expect(model.editingTextID == id && model.editingText == "First caption"
                     && controller.windowShouldClose(window) && Alert.shown == 2,
                     "reopening an exported caption loads its text and closes without a discard prompt")
        model.editingText = ""
        Alert.response = .alertFirstButtonReturn
        suite.expect(controller.windowShouldClose(window) && Alert.shown == 3
                     && model.annotations.first?.text == "First caption",
                     "confirming discard allows closing with a pending deletion of an exported caption")
    }

    /// A frame of `width`×`height` from a plain context, cheap to fill.
    private static func frame(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        context.setFillColor(NSColor(deviceRed: 0.2, green: 0.4, blue: 0.6, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Older entries go once the history's pixels pass the memory budget, so
    /// a few full 5K frames cannot pile up, while an annotation-only session
    /// keeps the step limit because it holds a single capture.
    private static func historyStopsByBytes(_ suite: TestSuite) {
        let originalBudget = Host.undoByteBudget
        defer { Host.undoByteBudget = originalBudget }
        let host = Host(image: ScreenshotCanvasSupportTests.image(width: 40, height: 40))
        let pasted = ScreenshotCanvasSupportTests.image(width: 4, height: 4)
        for _ in 0..<(Host.undoLimit + 3) { _ = host.pasteImage(pasted) }
        suite.expect(host.undoStack.count == Host.undoLimit,
                     "states sharing one capture stay bounded by steps, not bytes")

        let frames = (0..<6).map { _ in frame(width: 128, height: 128) }
        let frameBytes = frames[0].bytesPerRow * frames[0].height
        Host.undoByteBudget = frameBytes * 4 + 4096
        let big = Host(image: frames[0])
        for image in frames {
            big.baseImage = image
            _ = big.pasteImage(pasted)
            big.annotations = []
        }
        suite.expect(big.undoStack.count == 4 && big.undoStack.first?.image === frames[2],
                     "only recent distinct frames fit the undo pixel budget")

        let layers = Host(image: pasted)
        for image in frames {
            _ = layers.pasteImage(image)
            _ = layers.pasteImage(pasted)
            layers.annotations.removeAll()
        }
        let retained = Set(layers.undoStack.flatMap { state in
            state.annotations.compactMap { $0.imageAsset.map { ObjectIdentifier($0.image) } }
        })
        suite.expect(retained.count == 4 && !retained.contains(ObjectIdentifier(frames[0])),
                     "images retained only by pasted annotations share the history budget")

        guard let padded = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 16,
                                     bytesPerRow: 512, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGBitmapInfo.byteOrder16Little.rawValue
                                         | CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        else {
            suite.expect(false, "the padded 16-bit image fixture exists")
            return
        }
        Host.undoByteBudget = padded.bytesPerRow * padded.height + 1024
        let depth = Host(image: pasted)
        _ = depth.pasteImage(padded)
        _ = depth.pasteImage(pasted)
        depth.annotations.removeAll()
        depth.baseImage = frame(width: 32, height: 32)
        _ = depth.pasteImage(pasted)
        suite.expect(depth.undoStack.allSatisfy { state in
            !state.annotations.contains { $0.imageAsset?.image === padded }
        }, "a high-depth image is charged its actual row stride")

        Host.undoByteBudget = frameBytes * 2 + 512
        let mixed = Host(image: frames[5])
        mixed.undoStack = frames.prefix(2).map { ($0, []) }
        mixed.redoStack = [(frames[3], [])]
        mixed.undo()
        suite.expect(mixed.undoStack.count + mixed.redoStack.count == 2
                     && mixed.redoStack.last?.image === frames[5],
                     "undo budgets both stacks and keeps the immediate redo")
        mixed.redo()
        suite.expect(mixed.baseImage === frames[5],
                     "the retained redo returns to the previous frame")

        let click = Host(image: frames[1])
        click.undoStack = [(frames[0], [])]
        click.redoStack = [(frames[2], [])]
        let existing = ScreenshotSupport.Annotation(tool: .rect, rect: CGRect(x: 5, y: 5, width: 24, height: 24))
        let start = CGPoint(x: 60, y: 60)
        let end = CGPoint(x: 95, y: 110)
        click.tool = .rect
        click.annotations = [existing]
        click.selectedID = existing.id
        click.beginDrag(at: start)
        click.endDrag(at: start, isTap: true)
        suite.expect(click.annotations.map(\.id) == [existing.id] && click.selectedID == nil
                     && click.draftID == nil && click.undoStack.count == 1 && click.redoStack.count == 1,
                     "a tap without a drawing drops the draft and preserves undo and redo")

        click.selectedID = existing.id
        click.beginDrag(at: start)
        let drawing = click.draftID
        suite.expect(drawing != nil && click.annotations.last?.id == drawing && click.selectedID == nil,
                     "pressing to draw clears the previous selection and leaves the new shape unselected")
        click.continueDrag(to: end)
        suite.expect(click.selectedID == nil && click.annotations.last?.rect ==
                     CGRect(x: 60, y: 60, width: 35, height: 50)
                     && click.undoStack.count == 1 && click.redoStack.count == 1,
                     "the shape takes its dragged bounds before selection or history changes")
        click.endDrag(at: end, isTap: false)
        suite.expect(click.selectedID == drawing && click.draftID == nil && click.annotations.count == 2
                     && click.undoStack.last?.annotations.map(\.id) == [existing.id] && click.redoStack.isEmpty,
                     "releasing selects the new shape and records only the pre-drag annotations")
        let full = CGRect(origin: .zero, size: click.imageSize)
        let beforeCrop = click.undoStack.count
        for draft in [full, full.insetBy(dx: -4, dy: -3), full.insetBy(dx: 0.2, dy: 0.4)] {
            click.cropDraft = draft
            click.applyCrop()
            suite.expect(click.baseImage === frames[1] && click.undoStack.count == beforeCrop,
                         "a crop that clamps or rounds to the full canvas keeps its buffer and history")
        }
    }

    /// Exercises the full-size drawing contexts on demand. Each edit goes through
    /// the same expansion and history methods as the editor, using generated pixels.
    private static func largeCanvasHistory(_ suite: TestSuite) {
        let width = 5120, height = 2880
        let host = Host(image: frame(width: width, height: height))
        func footprint() -> UInt64? {
            var info = rusage_info_current()
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, $0)
                }
            }
            return status == 0 ? info.ri_phys_footprint : nil
        }
        var samples: [UInt64] = []
        for edit in 1...14 {
            let rect = CGRect(x: 0, y: 0, width: width + 4 * edit, height: height)
            let changed = autoreleasepool { host.commitCanvasExpansion(to: rect) }
            let retained = host.undoStack.reduce(0) { $0 + $1.image.bytesPerRow * $1.image.height }
            guard changed, retained <= Host.undoByteBudget else {
                suite.expect(false, "5K expansion must succeed and evict old buffers before the next edit")
                return
            }
            if [6, 10, 14].contains(edit) {
                guard let used = footprint() else {
                    suite.expect(false, "the test process exposes its physical footprint")
                    return
                }
                samples.append(used)
                print("5K edit \(edit): \(host.undoStack.count) undo states, " +
                      "\(retained >> 20) MiB history, \(used >> 20) MiB process footprint")
            }
        }
        let bytesPerFrame = UInt64(host.baseImage.bytesPerRow * host.baseImage.height)
        suite.expect(samples.max()! - samples.min()! <= 2 * bytesPerFrame,
                     "5K edits reach a steady physical footprint within two frame buffers")
        let finalWidth = host.baseImage.width
        let available = host.undoStack.count
        suite.expect(available == 4, "four recent full 5K frames fit the history budget")
        for step in 1...4 {
            host.undo()
            suite.expect(host.baseImage.width == finalWidth - 4 * step,
                         "5K undo restores the recent canvas at step \(step)")
        }
        for step in 1...4 {
            host.redo()
            suite.expect(host.baseImage.width == finalWidth - 4 * (4 - step),
                         "5K redo restores the edited canvas at step \(step)")
        }
    }

    /// A crop owns its pixels instead of pointing into the frame it came from,
    /// with the same size, colour space and pixels.
    private static func cropOwnsItsPixels(_ suite: TestSuite) {
        let parent = ScreenshotImageLayerTests.solid(
            NSColor(deviceRed: 0.2, green: 0.5, blue: 0.8, alpha: 1), width: 1200, height: 800)
        let rect = CGRect(x: 100, y: 60, width: 800, height: 600)
        func buffer(_ image: CGImage) -> Int {
            (image.dataProvider?.data as Data?)?.count ?? 0
        }
        guard let window = parent.cropping(to: rect),
              let independent = ScreenshotSupport.independentImage(window)
        else {
            suite.expect(false, "a crop is copied into pixels of its own")
            return
        }
        suite.expect(independent.width == 800 && independent.height == 600,
                     "the copy keeps the crop's size")
        if let space = independent.colorSpace, let source = parent.colorSpace {
            suite.expect(CFEqual(space, source), "the copy keeps the crop's colour space")
        } else {
            suite.expect(false, "both the crop and its parent carry a colour space")
        }
        suite.expect(buffer(window) > buffer(independent) && buffer(independent) == 800 * 600 * 4,
                     "the crop holds its own buffer instead of the parent's: \(buffer(window)) then \(buffer(independent)) bytes")
        suite.expect(independent.bytesPerRow == 800 * 4,
                     "the copy stops reading rows of the parent")
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        suite.expect(ScreenshotImageLayerTests.bytes(independent, in: bounds)
                     == ScreenshotImageLayerTests.bytes(window, in: bounds),
                     "the copy keeps every pixel")
    }

    static func run(_ suite: TestSuite) {
        historyStopsByBytes(suite)
        closingWithInlineText(suite)
        if ProcessInfo.processInfo.environment["VORSSAINT_SCREENSHOT_MEMORY_SMOKE"] == "1" {
            largeCanvasHistory(suite)
        }
        cropOwnsItsPixels(suite)
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
