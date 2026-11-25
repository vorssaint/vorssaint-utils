// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

private typealias SystemWindowLookup = WindowServerSupport

/// Runs the production capture loop and pixel stitching with an isolated image
/// source. No screen permissions, global input or application windows are used.
enum ScreenshotScrollingCaptureTests {
    /// Keep real wheel events, but intercept delivery and window-server reads.
    enum Desktop {
        static let originalBounds = CGRect(x: -200, y: 100, width: 400, height: 500)
        static var bounds = originalBounds
        static var pid: pid_t = 42
        static var receiver: CGWindowID? = 31
        static var access = true
        static var posted: [(CGEvent, CGEventTapLocation)] = []
        static var windows: [[String: Any]] {
            [[kCGWindowNumber as String: 31, kCGWindowOwnerPID as String: pid,
              kCGWindowBounds as String: bounds.dictionaryRepresentation]]
        }
        static func record(_ event: CGEvent, tap: CGEventTapLocation) { posted.append((event, tap)) }
    }
    enum WindowServerSupport {
        static func receivingWindow(at point: CGPoint) -> CGWindowID? {
            Desktop.bounds.contains(point) ? Desktop.receiver : nil
        }
        static func ownerProcessID(ofWindowID id: CGWindowID) -> pid_t? {
            SystemWindowLookup.ownerProcessID(ofWindowID: id, in: Desktop.windows)
        }
        static func ownerProcessID(ofWindowID id: CGWindowID, in windows: [[String: Any]]) -> pid_t? {
            SystemWindowLookup.ownerProcessID(ofWindowID: id, in: windows)
        }
        static func frame(ofWindowID id: CGWindowID, in windows: [[String: Any]]) -> CGRect? {
            SystemWindowLookup.frame(ofWindowID: id, in: windows)
        }
    }
    struct NSScreen {
        static let screens = [NSScreen()]
        let frame = CGRect(x: 0, y: 0, width: 1280, height: 720)
    }
    static func CGPreflightPostEventAccess() -> Bool { Desktop.access }
    static func CGWindowListCopyWindowInfo(_ options: CGWindowListOption, _ id: CGWindowID) -> CFArray? {
        Desktop.windows as CFArray
    }

    enum RecorderSupport {
        struct Region {
            var windowID: CGWindowID?
            let displayID: CGDirectDisplayID = 1
            let pixelRect = CGRect(x: 0, y: 0, width: 32, height: 120)
            var anchorRect = CGRect(x: 10, y: 20, width: 16, height: 60)
            let scale: CGFloat = 2
        }
    }
    enum ScreenshotSelectionController {
        struct Capture {
            let image: CGImage
            let scale: CGFloat
            let anchorRect: CGRect
        }
    }
    @MainActor enum ScreenshotCaptureEngine {
        nonisolated static func pickableWindows(hideVorssaintWindows: Bool,
                                                protectedWindowIDs: Set<CGWindowID>)
            -> [(id: CGWindowID, bounds: CGRect)] {
            let id: CGWindowID = 31
            return ScreenshotCapturePolicy.canPickWindow(id,
                isOwnWindow: Desktop.pid == ProcessInfo.processInfo.processIdentifier,
                hideVorssaintWindows: hideVorssaintWindows, protectedWindowIDs: protectedWindowIDs)
                ? [(id, Desktop.bounds)] : []
        }
        static var source: Source!
        static var preparations = 0
        static func prepareDisplayRegion(displayID: CGDirectDisplayID, pixelRect: CGRect,
                                         includePointer: Bool, hideVorssaintWindows: Bool,
                                         protectedWindowIDs: Set<CGWindowID>) async -> Source? {
            preparations += 1
            return source
        }
        final class Source: ScreenshotScrollingCapture.AutomaticScroller {
            let images: [CGImage?]
            let finish: ScreenshotScrollingCapture.FinishSignal
            var calls = 0
            var automaticIndex: Int?
            var scrolls = 0
            var animateBeforeFirstScroll = false
            var targetIsCurrent = true
            var onRead: ((Int) async -> Void)?
            init(_ images: [CGImage?], finish: ScreenshotScrollingCapture.FinishSignal,
                 automatic: Bool = false) {
                self.images = images
                self.finish = finish
                automaticIndex = automatic ? 0 : nil
            }
            func isCurrent() -> Bool { targetIsCurrent }
            func scroll() -> Bool {
                scrolls += 1
                automaticIndex = min((automaticIndex ?? 0) + 1, images.count - 1)
                return true
            }
            func image() async -> CGImage? {
                calls += 1
                await onRead?(calls)
                if animateBeforeFirstScroll, scrolls == 0 {
                    return ScreenshotScrollingCaptureTests.stationaryPage(
                        animationOffset: calls.isMultiple(of: 2) ? 0 : 12)
                }
                if let automaticIndex { return images[automaticIndex] }
                let index = min(calls - 1, images.count - 1)
                if calls >= images.count { finish.request() }
                return images[index]
            }
        }
    }

    static func run(_ suite: TestSuite) {
        var completed = false
        let task = Task { @MainActor in
            await checks(suite)
            completed = true
        }
        let deadline = Date().addingTimeInterval(30)
        while !completed && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        if !completed { task.cancel() }
        suite.expect(completed, "scrolling capture completes without wheel events or desktop access")
    }

    static func frame(offset: Int, width: Int = 32, height: Int = 120, seed: Int = 0,
                      contentWidth: Int? = nil, sparse: Bool = false) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                guard column < (contentWidth ?? width) else { continue }
                let r = row + offset
                if seed == 0 {
                    pixels[row * width + column] = UInt8(
                        (r * 17 + column * 31 + (r / 7) * 13) % 251)
                } else {
                    var value = UInt32(r * width + column + seed)
                    value = (value ^ (value >> 16)) &* 0x45d9f3b
                    value = (value ^ (value >> 16)) &* 0x45d9f3b
                    pixels[row * width + column] = UInt8(truncatingIfNeeded: value ^ (value >> 16))
                }
                if sparse {
                    // Text-like rows separated by white space. Random pixels
                    // alone do not expose false matches against blank bands.
                    pixels[row * width + column] = r % 24 < 8
                        ? 215 + pixels[row * width + column] % 40 : 255
                }
            }
        }
        let data = Data(pixels) as CFData
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// The document does not move. Only an animated banner changes rows.
    static func stationaryPage(animationOffset: Int, blankBackground: Bool = false,
                               bannerRows: Range<Int> = 30..<66) -> CGImage {
        let width = 32, height = 120
        let document = frame(offset: 0, seed: 91)
        let animation = frame(offset: animationOffset, seed: 91)
        var bytes = blankBackground ? [UInt8](repeating: 255, count: width * height)
            : Array(document.dataProvider!.data! as Data)
        let animated = Array(animation.dataProvider!.data! as Data)
        for row in bannerRows {
            bytes.replaceSubrange(row * width..<(row + 1) * width,
                                  with: animated[row * width..<(row + 1) * width])
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func paddedFrame(offset: Int) -> CGImage {
        let image = frame(offset: offset)
        let context = CGContext(data: nil, width: image.width + 1, height: image.height + 1,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // A transparent bottom row and right column, as a padded region capture.
        context.draw(image, in: CGRect(x: 0, y: 1, width: image.width, height: image.height))
        return context.makeImage()!
    }

    static func sparsePage(offset: Int, height: Int = 120) -> CGImage {
        let width = 32
        var bytes = [UInt8](repeating: 255, count: width * height)
        for row in 0..<height {
            let documentRow = row < 20 ? row : row + offset
            guard row < 20 || [26, 49, 74, 97, 117, 141].contains(documentRow) else { continue }
            for column in 0..<width {
                bytes[row * width + column] = UInt8((documentRow * 17 + column * 31) % 181)
            }
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &bytes, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    /// Sparse, repeated lines at the reported 120-column Terminal width. Draw
    /// once and crop viewports so the expected output includes every source row.
    @MainActor static func terminalDocument() -> CGImage {
        let width = 1_800, height = 150 * 28
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for line in 1...150 {
            (String(line) as NSString).draw(
                at: CGPoint(x: 12, y: height - line * 28 + 2),
                withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 24, weight: .regular),
                                 .foregroundColor: NSColor.white])
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }

    @MainActor static func checks(_ suite: TestSuite) async {
        // Match the reported output dimensions. Small synthetic images miss
        // rounding at the edges of strips drawn far down a tall bitmap.
        let sliceHeights = [1522, 160, 240, 320, 720, 400, 80, 1120, 400, 400, 78]
        let slices = sliceHeights.map { height -> CGImage in
            let context = CGContext(data: nil, width: 2876, height: height,
                                    bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 2876, height: height))
            return context.makeImage()!
        }
        if let joined = ScreenshotScrollingCapture.stitch(slices) {
            var alpha = [UInt8](repeating: 0, count: joined.height)
            let context = CGContext(data: &alpha, width: 1, height: joined.height,
                                    bitsPerComponent: 8, bytesPerRow: 1,
                                    space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
            context.draw(joined, in: CGRect(x: 0, y: 0, width: 1, height: joined.height))
            suite.expect(joined.height == 5440 && alpha.allSatisfy { $0 == 255 },
                         "tall Retina bitmap stitching never creates transparent seam rows")
        } else { suite.expect(false, "tall screenshot strips can be joined") }

        let retinaStart = frame(offset: 0, width: 256, height: 1340, seed: 91)
        let retinaNext = frame(offset: 83, width: 256, height: 1340, seed: 91)
        func sample(_ image: CGImage) -> ScreenshotSupport.ScrollingSample {
            .init(width: image.width, height: image.height,
                  pixels: Array(image.dataProvider!.data! as Data))
        }
        let matchingStarted = ProcessInfo.processInfo.systemUptime
        let transition = ScreenshotSupport.scrollingTransition(
            previous: sample(retinaStart), current: sample(retinaNext))
        let matchingDuration = ProcessInfo.processInfo.systemUptime - matchingStarted
        suite.expect(transition == .advanced(overlap: 1257, direction: .forward,
                                             contentColumns: 0..<256),
                     "Retina-height matching preserves the exact native-pixel overlap")
        // A generous bound for a ~0.1 s operation; the original unoptimized
        // nested loops took ~7 s, missing whole viewports during normal input.
        suite.expect(matchingDuration < 1,
                     "Retina matching must not stall the capture for a second (\(matchingDuration)s)")

        let region = RecorderSupport.Region()
        defer { ScreenshotCaptureEngine.source = nil }
        func capture(_ frames: [CGImage?]) async -> ScreenshotScrollingCapture.Result {
            let signal = ScreenshotScrollingCapture.FinishSignal()
            ScreenshotCaptureEngine.source = .init(frames, finish: signal)
            ScreenshotCaptureEngine.preparations = 0
            let result = await ScreenshotScrollingCapture.capture(
                region: region, includePointer: false, hideVorssaintWindows: true,
                protectedWindowIDs: [], finishSignal: signal, onProgress: { _ in })
            suite.expect(ScreenshotCaptureEngine.preparations == 1,
                         "scrolling session resolves its capture configuration only once")
            return result
        }
        if case .success(let capture) = await capture([
            stationaryPage(animationOffset: 0), stationaryPage(animationOffset: 12),
            stationaryPage(animationOffset: 24), stationaryPage(animationOffset: 36)
        ]) {
            suite.expect(capture.image.height == 120,
                         "a stationary page with an animated banner never adds empty capture rows")
        } else { suite.expect(false, "stationary content remains a complete single viewport") }
        if let event = ScreenshotAutomaticScroller.scrollEvent(
            processID: 42, point: CGPoint(x: -150, y: 220), step: 80) {
            suite.expect(event.location == CGPoint(x: -150, y: 220),
                         "automatic scroll retains the selected point: \(event.location)")
            suite.expect(event.flags.isEmpty,
                         "automatic scroll clears modifiers: \(event.flags.rawValue)")
            let expectedFields: [(CGEventField, Int64)] = [
                (.scrollWheelEventPointDeltaAxis1, -80),
                (.eventTargetUnixProcessID, 42),
                (.eventSourceUserData, ScrollWheelSupport.syntheticTag),
                (.eventSourceUnixProcessID, Int64(ProcessInfo.processInfo.processIdentifier))
            ]
            for (field, expected) in expectedFields {
                let actual = event.getIntegerValueField(field)
                suite.expect(actual == expected,
                             "automatic scroll field \(field.rawValue): got \(actual), expected \(expected)")
            }
        } else { suite.expect(false, "an automatic downward scroll event can be prepared without posting it") }
        let targetRect = CGRect(x: -170, y: 460, width: 40, height: 80)
        let screen = CGRect(x: -800, y: 40, width: 800, height: 600)
        let controlsSize = CGSize(width: 320, height: 70)
        let usual = ScreenshotSupport.scrollingControlsFrame(size: controlsSize, visibleFrame: screen, avoiding: nil)
        let underControls = CGPoint(x: usual.midX, y: usual.midY)
        let moved = ScreenshotSupport.scrollingControlsFrame(
            size: controlsSize, visibleFrame: screen, avoiding: underControls)
        suite.expect(screen.contains(moved) && !moved.contains(underControls)
                     && ScreenshotSupport.scrollingControlsFrame(size: controlsSize, visibleFrame: screen,
                                                                avoiding: .zero) == usual,
                     "capture controls move only when they would intercept the automatic wheel")
        func scroller(window: CGWindowID? = nil, hide: Bool = true, protected: Set<CGWindowID> = [])
            -> ScreenshotAutomaticScroller? {
            ScreenshotAutomaticScroller(region: .init(windowID: window, anchorRect: targetRect),
                                        hideVorssaintWindows: hide, protectedWindowIDs: protected)
        }
        Desktop.bounds = Desktop.originalBounds
        Desktop.pid = 42
        Desktop.receiver = 31
        Desktop.access = true
        Desktop.posted = []
        guard let delivery = scroller(window: 31) else {
            suite.expect(false, "the picked window can receive automatic scrolls on a secondary display")
            return
        }
        suite.expect(scroller() != nil && scroller(window: 32) == nil && delivery.scroll()
                     && Desktop.posted.count == 1 && Desktop.posted.first?.1 == .cgSessionEventTap
                     && Desktop.posted.first?.0.location == CGPoint(x: -150, y: 220),
                     "dragged and clicked targets scroll only the receiving window at the selected point")
        Desktop.posted = []
        Desktop.access = false
        suite.expect(!delivery.scroll() && Desktop.posted.isEmpty,
                     "automatic scrolling stops when input permission is lost")
        Desktop.access = true
        Desktop.bounds.origin.x += 1
        suite.expect(!delivery.scroll() && Desktop.posted.isEmpty,
                     "automatic scrolling stops when its selected window moves")
        Desktop.bounds = Desktop.originalBounds
        Desktop.receiver = 32
        suite.expect(scroller() == nil && !delivery.scroll() && Desktop.posted.isEmpty,
                     "an overlapping window in the same process cannot take the selected window's scroll")
        Desktop.receiver = 31
        Desktop.pid = ProcessInfo.processInfo.processIdentifier
        suite.expect(!delivery.scroll() && Desktop.posted.isEmpty && scroller() == nil
                     && scroller(hide: false, protected: [31]) == nil && scroller(hide: false) != nil,
                     "replaced, hidden and protected windows get no events; a visible app window is eligible")
        Desktop.pid = 42
        var automatic = ScreenshotScrollingCapture.AutoScrollState()
        suite.expect(automatic.next(now: 0, height: 120, settled: false) == .wait
                     && automatic.next(now: 0.25, height: 120, settled: true) == .scroll
                     && automatic.next(now: 0.4, height: 120, settled: true) == .wait
                     && automatic.next(now: 0.9, height: 162, settled: true) == .scroll,
                     "automatic capture observes each scroll and waits for overlapping frames")
        suite.expect(automatic.next(now: 1.5, height: 162, settled: true) == .scroll
                     && automatic.next(now: 2.1, height: 162, settled: true) == .scroll
                     && automatic.next(now: 2.7, height: 162, settled: true) == .finish,
                     "three attempts without new content stop automatic scrolling")
        var animatedBottom = ScreenshotScrollingCapture.AutoScrollState()
        suite.expect(animatedBottom.next(now: 0, height: 120, settled: true) == .scroll
                     && animatedBottom.next(now: 1, height: 120, settled: false) == .wait
                     && animatedBottom.next(now: 1.6, height: 120, settled: false) == .scroll
                     && animatedBottom.next(now: 3.2, height: 120, settled: false) == .scroll
                     && animatedBottom.next(now: 4.8, height: 120, settled: false) == .finish,
                     "an animated element cannot keep automatic scrolling alive indefinitely")
        var animatedStart = ScreenshotScrollingCapture.AutoScrollState()
        suite.expect(animatedStart.next(now: 0, height: 120, settled: false) == .wait
                     && animatedStart.next(now: 1, height: 120, settled: false) == .wait
                     && animatedStart.next(now: 1.6, height: 120, settled: false) == .scroll,
                     "automatic scrolling starts even when the page never becomes still")
        for alreadyAtBottom in [false, true] {
            let signal = ScreenshotScrollingCapture.FinishSignal()
            let frames = alreadyAtBottom
                ? [0, 12, 24, 36].map { stationaryPage(animationOffset: $0) }
                : [0, 42, 72].map { frame(offset: $0) }
            let source = ScreenshotCaptureEngine.Source(frames, finish: signal, automatic: true)
            ScreenshotCaptureEngine.source = source
            var heights: [Int] = []
            let result = await ScreenshotScrollingCapture.capture(
                region: region, includePointer: false, hideVorssaintWindows: true,
                protectedWindowIDs: [], finishSignal: signal,
                autoScroll: source, onProgress: { heights.append($0) })
            if case .success(let capture) = result {
                suite.expect(capture.image.height == (alreadyAtBottom ? 120 : 192)
                             && heights == (alreadyAtBottom ? [120] : [120, 162, 192])
                             && source.scrolls == (alreadyAtBottom ? 3 : 5)
                             && !signal.isRequested,
                             "automatic capture stops at the bottom without inflating the pixel count or pressing Done")
            } else { suite.expect(false, "automatic capture completes on its own at the document bottom") }
        }
        let animatedSignal = ScreenshotScrollingCapture.FinishSignal()
        let animatedSource = ScreenshotCaptureEngine.Source(
            [stationaryPage(animationOffset: 0)], finish: animatedSignal, automatic: true)
        animatedSource.animateBeforeFirstScroll = true
        ScreenshotCaptureEngine.source = animatedSource
        let animatedResult = await ScreenshotScrollingCapture.capture(
            region: region, includePointer: false, hideVorssaintWindows: true,
            protectedWindowIDs: [], finishSignal: animatedSignal,
            autoScroll: animatedSource, onProgress: { _ in })
        if case .success(let capture) = animatedResult {
            suite.expect(capture.image.height == 120 && animatedSource.scrolls == 3,
                         "an animated starting viewport still scrolls and finishes without false pixel growth")
        } else { suite.expect(false, "an animated starting viewport completes without pressing Done") }
        let stopSignal = ScreenshotScrollingCapture.FinishSignal()
        let stopSource = ScreenshotCaptureEngine.Source([frame(offset: 0)], finish: stopSignal, automatic: true)
        ScreenshotCaptureEngine.source = stopSource
        stopSource.onRead = { call in
            if call == 2 {
                try? await Task.sleep(nanoseconds: 300_000_000)
                stopSignal.request()
            }
        }
        _ = await ScreenshotScrollingCapture.capture(
            region: region, includePointer: false, hideVorssaintWindows: true,
            protectedWindowIDs: [], finishSignal: stopSignal,
            autoScroll: stopSource, onProgress: { _ in })
        suite.expect(stopSource.scrolls == 0, "Done during frame acquisition prevents the next scheduled wheel event")

        let cancelSignal = ScreenshotScrollingCapture.FinishSignal()
        let cancelSource = ScreenshotCaptureEngine.Source([frame(offset: 0)], finish: cancelSignal, automatic: true)
        cancelSource.onRead = { call in
            if call == 2 { withUnsafeCurrentTask { $0?.cancel() } }
        }
        ScreenshotCaptureEngine.source = cancelSource
        let cancelTask = Task {
            await ScreenshotScrollingCapture.capture(
                region: region, includePointer: false, hideVorssaintWindows: true,
                protectedWindowIDs: [], finishSignal: cancelSignal, autoScroll: cancelSource, onProgress: { _ in })
        }
        if case .cancelled = await cancelTask.value {
            suite.expect(cancelSource.scrolls == 0, "Cancel during frame acquisition sends no further wheel event")
        } else { suite.expect(false, "Cancel during capture discards the in-flight image") }

        let coveredSignal = ScreenshotScrollingCapture.FinishSignal()
        let coveredSource = ScreenshotCaptureEngine.Source(
            [frame(offset: 0), frame(offset: 42)], finish: coveredSignal, automatic: true)
        coveredSource.onRead = { [weak coveredSource] _ in
            if coveredSource?.scrolls == 1 { coveredSource?.targetIsCurrent = false }
        }
        ScreenshotCaptureEngine.source = coveredSource
        let covered = await ScreenshotScrollingCapture.capture(
            region: region, includePointer: false, hideVorssaintWindows: true,
            protectedWindowIDs: [], finishSignal: coveredSignal,
            autoScroll: coveredSource, onProgress: { _ in })
        if case .partial(let capture) = covered {
            suite.expect(coveredSource.scrolls == 1 && pixels(capture.image) == pixels(frame(offset: 0)),
                         "a target covered during frame acquisition never contributes pixels or another event")
        } else { suite.expect(false, "losing the input window preserves only previously verified frames") }

        let bannerSignal = ScreenshotScrollingCapture.FinishSignal()
        let bannerSource = ScreenshotCaptureEngine.Source(
            [0, 6, 12].map { stationaryPage(animationOffset: $0, blankBackground: true, bannerRows: 6..<42) },
            finish: bannerSignal, automatic: true)
        ScreenshotCaptureEngine.source = bannerSource
        let banner = await ScreenshotScrollingCapture.capture(
            region: region, includePointer: false, hideVorssaintWindows: true,
            protectedWindowIDs: [], finishSignal: bannerSignal, autoScroll: bannerSource, onProgress: { _ in })
        if case .partial(let capture) = banner {
            suite.expect(capture.image.height == 120 && bannerSource.scrolls == 1,
                         "an ambiguous moving banner on white cannot fabricate height or skip another viewport")
        } else { suite.expect(false, "a clipped animation on blank paper cannot establish a page seam") }

        let sparseSignal = ScreenshotScrollingCapture.FinishSignal()
        let sparseFrames = [0, 12, 24, 36].map { sparsePage(offset: $0) }
        let sparseSource = ScreenshotCaptureEngine.Source(sparseFrames, finish: sparseSignal, automatic: true)
        ScreenshotCaptureEngine.source = sparseSource
        var sparseHeights: [Int] = []
        let sparseResult = await ScreenshotScrollingCapture.capture(
            region: region, includePointer: false, hideVorssaintWindows: true,
            protectedWindowIDs: [], finishSignal: sparseSignal, autoScroll: sparseSource,
            onProgress: { sparseHeights.append($0) })
        if case .success(let capture) = sparseResult {
            suite.expect(sparseHeights == [120, 132, 144, 156]
                         && pixels(capture.image) == pixels(sparsePage(offset: 0, height: 156)),
                         "a fixed header cannot finish a moving sparse page early or hide any document row")
        } else { suite.expect(false, "automatic capture reaches the end of the sparse document") }
        let terminal = terminalDocument()
        let terminalFrames = stride(from: 0, through: 120, by: 15).map { line in
            terminal.cropping(to: CGRect(x: 0, y: line * 28,
                                        width: terminal.width, height: 30 * 28))!
        }
        if case .success(let capture) = await capture(terminalFrames) {
            suite.expect(capture.image.width == terminal.width,
                         "sparse Terminal output preserves all 120 selected columns")
            suite.expect(capture.image.height == terminal.height,
                         "Terminal capture keeps every line from 1 through 150 (got \(capture.image.height) rows)")
            suite.expect(pixels(capture.image) == pixels(terminal),
                         "repeated Terminal text is joined without missing, duplicated or shifted lines")
        } else { suite.expect(false, "Terminal sequence frames have a recoverable overlap") }

        let irregularTerminalFrames = [0, 211, 87, 587, 1_000, 1_400].map { offset in
            terminal.cropping(to: CGRect(x: 0, y: offset,
                                        width: terminal.width, height: 30 * 28))!
        }
        if case .success(let capture) = await capture(irregularTerminalFrames),
           let expected = terminal.cropping(to: CGRect(x: 0, y: 0, width: terminal.width, height: 2_240)) {
            suite.expect(pixels(capture.image) == pixels(expected),
                         "Terminal backtracking and partial text rows preserve exact pixel alignment")
        } else { suite.expect(false, "irregular Terminal scrolling has a recoverable overlap") }

        if case .success(let capture) = await capture([
            frame(offset: 0, contentWidth: 8), frame(offset: 42, contentWidth: 8)
        ]) {
            suite.expect(pixels(capture.image) == pixels(frame(offset: 0, height: 162, contentWidth: 8)),
                         "matching a narrow text column never crops the selected blank side area")
        } else { suite.expect(false, "a narrow moving column has a recoverable overlap") }

        if case .success(let capture) = await capture([frame(offset: 0), frame(offset: 42)]) {
            suite.expect(capture.image.height == 162 && capture.scale == 2
                         && capture.anchorRect == region.anchorRect,
                         "Done includes the last frame without a wheel event and preserves geometry")
            suite.expect(pixels(capture.image) == pixels(frame(offset: 0, height: 162)),
                         "stitched pixels follow the document without duplicated or inverted strips")
        } else { suite.expect(false, "pixel polling must capture scrolling without mouse events") }

        if case .success(let capture) = await capture([
            paddedFrame(offset: 0), paddedFrame(offset: 42), paddedFrame(offset: 72)
        ]) {
            suite.expect(pixels(capture.image) == pixels(frame(offset: 0, height: 192)),
                         "transparent capture-edge padding never becomes a seam or loses content rows")
        } else { suite.expect(false, "padded screen captures must still join") }

        // A larger advance halfway through a long page must not strand the
        // matcher on its last accepted frame and discard every later viewport.
        let longPageOffsets = [0, 42, 84, 180, 276, 372, 468, 564, 660]
        if case .success(let capture) = await capture(longPageOffsets.map {
            frame(offset: $0, seed: 91)
        }) {
            suite.expect(pixels(capture.image) == pixels(frame(offset: 0, height: 780, seed: 91)),
                         "a long capture preserves every row after a near-page advance")
        } else { suite.expect(false, "long pages keep capturing after smaller overlaps") }

        let sparsePageOffsets = [0, 8, 94, 180, 266, 352, 438, 524, 610]
        if case .success(let capture) = await capture(sparsePageOffsets.map {
            frame(offset: $0, seed: 91, sparse: true)
        }) {
            suite.expect(pixels(capture.image)
                == pixels(frame(offset: 0, height: 730, seed: 91, sparse: true)),
                         "white bands on a long page never turn forward scrolling into backtracking")
        } else { suite.expect(false, "long pages with white space preserve their full content") }

        if case .success(let capture) = await capture([frame(offset: 0)]) {
            suite.expect(capture.image.height == 120, "Done without scrolling returns the initial capture")
        } else { suite.expect(false, "Done must also work without any scroll movement") }

        if case .partial(let capture) = await capture([frame(offset: 0), frame(offset: 0, seed: 91)]) {
            suite.expect(capture.image.height == 120, "unmatched scrolling preserves the first frame")
        } else { suite.expect(false, "Done preserves a partial image when no overlap is found") }

        if case .partial(let capture) = await capture([
            frame(offset: 0, seed: 91, sparse: true),
            frame(offset: 104, seed: 731, sparse: true)
        ]) {
            suite.expect(capture.image.height == 120,
                         "unrelated sparse pages cannot be stitched together just on white space")
        } else { suite.expect(false, "white space alone cannot establish page continuity") }

        if case .partial(let capture) = await capture([
            frame(offset: 0), frame(offset: 42), frame(offset: 0, seed: 91)
        ]) {
            suite.expect(pixels(capture.image) == pixels(frame(offset: 0, height: 162)),
                         "a later mismatch preserves all successfully stitched content")
        } else { suite.expect(false, "unmatched movement must return the completed portion") }

        if case .partial(let capture) = await capture([frame(offset: 0), nil]) {
            suite.expect(capture.image.height == 120, "a later capture failure keeps existing pixels")
        } else { suite.expect(false, "a later source failure must not discard the capture") }

        if case .success(let capture) = await capture([
            frame(offset: 0), frame(offset: 42), frame(offset: 12), frame(offset: 72)
        ]) {
            suite.expect(pixels(capture.image) == pixels(frame(offset: 0, height: 192)),
                         "backtracking and resuming never duplicates already captured content")
        } else { suite.expect(false, "scrolling back then forward still completes") }

        if case .failed = await capture([nil]) {} else {
            suite.expect(false, "failure before any frame is reported as failed")
        }

        let signal = ScreenshotScrollingCapture.FinishSignal()
        ScreenshotCaptureEngine.source = .init([frame(offset: 0)], finish: signal)
        let cancelled = Task {
            await ScreenshotScrollingCapture.capture(
                region: region, includePointer: false, hideVorssaintWindows: true,
                protectedWindowIDs: [], finishSignal: signal, onProgress: { _ in })
        }
        cancelled.cancel()
        if case .cancelled = await cancelled.value {} else {
            suite.expect(false, "Cancel must not deliver a screenshot")
        }
    }
}
