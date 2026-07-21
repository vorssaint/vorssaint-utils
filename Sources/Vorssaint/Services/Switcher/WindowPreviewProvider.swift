// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import CoreImage
import Darwin
import Foundation
import ScreenCaptureKit

/// Captures window thumbnails for the switcher with ScreenCaptureKit.
///
/// Thumbnails live only in this in-memory cache: stale images make cards
/// appear instantly on the next invocation while fresh captures stream in.
/// Without Screen Recording permission the provider stays silent and the
/// switcher falls back to app icons.
final class WindowPreviewProvider {
    static let shared = WindowPreviewProvider()

    /// Longest thumbnail edge, in pixels (2x for Retina sharpness).
    private static let defaultMaxPixelSize: CGFloat = 640

    private var cache: [CGWindowID: CGImage] = [:]
    private var lastTouched: [CGWindowID: TimeInterval] = [:]
    private static let cacheLimit = 48
    /// Upper bound on the bytes the thumbnail cache may hold; the count limit
    /// alone would allow ~160 MB of big-window thumbnails.
    private static let cacheByteBudget = 64 * 1024 * 1024
    private var captureTask: Task<Void, Never>?
    private var warmTask: Task<Void, Never>?
    private var activationToken: NSObjectProtocol?
    private var pendingWarmPid: pid_t?
    private var pressureSource: DispatchSourceMemoryPressure?

    init() {
        // Thumbnails are pure convenience; when the system runs out of memory
        // they are the first thing this app sheds. They re-capture on the next
        // invocation (Stage Manager parked windows fall back to app icons
        // until their window becomes active again).
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .critical, queue: .main)
        source.setEventHandler { [weak self] in
            self?.cache.removeAll()
            self?.lastTouched.removeAll()
        }
        source.resume()
        pressureSource = source
    }

    deinit {
        pressureSource?.cancel()
    }

    func cachedPreview(for windowID: CGWindowID) -> CGImage? {
        if cache[windowID] != nil {
            lastTouched[windowID] = ProcessInfo.processInfo.systemUptime
        }
        return cache[windowID]
    }

    /// Refreshes thumbnails for the previewable `items`, invoking `onUpdate`
    /// on the main thread as each capture lands. Earlier entries are captured
    /// first, so pass items in display order. Tab entries share their host
    /// window's capture, so each backing window is captured once.
    func refreshPreviews(for items: [SwitcherItem],
                         maxPixelSize: CGFloat = defaultMaxPixelSize,
                         onUpdate: @escaping (CGWindowID, CGImage) -> Void) {
        guard Permissions.shared.screenRecording else { return }

        var seen = Set<CGWindowID>()
        let targets: [PreviewTarget] = items.compactMap { item in
            guard let id = item.previewWindowID, !seen.contains(id) else { return nil }
            seen.insert(id)
            return PreviewTarget(id: id,
                                 pid: item.windowOwnerPID,
                                 title: item.title,
                                 appName: item.appName,
                                 frame: item.frame,
                                 isMinimized: item.isMinimized)
        }

        captureTask?.cancel()
        // Never prune to the caller's subset: Dock preview refreshes a single
        // app through this same provider, and under Stage Manager a parked
        // window cannot be recaptured — an evicted preview is gone until that
        // window becomes active again. Drop only windows that no longer exist,
        // then bound memory by dropping the least recently used extras.
        pruneCache(keeping: seen)

        captureTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            // Primary path: window-server captures are synchronous, full
            // resolution and cover minimized/other-Space windows. Verified on
            // macOS 27: for windows parked in the Stage Manager strip EVERY
            // capture API returns the strip's small tilted artwork instead of
            // the window content, so captures are classified and rejected ones
            // keep the previous good thumbnail (or the app-icon fallback);
            // thumbnails heal as windows become active again. The SCK path
            // below is the fallback for when the private call is unavailable.
            var pending: [PreviewTarget] = []
            for target in targets {
                guard !Task.isCancelled else { return }
                guard let image = Self.captureViaWindowServer(target.id) else {
                    pending.append(target)
                    continue
                }
                if let grid = SwitcherSupport.alphaGrid(of: image),
                   SwitcherSupport.captureLooksTransformed(alphaGrid: grid) {
                    // Never show the tilted strip artwork. When nothing better
                    // is cached, an upright rectified version stands in until
                    // the window becomes active and a clean capture replaces it.
                    if let rectified = Self.rectifiedStripCapture(image) {
                        let copy = Self.bitmapCopy(rectified)
                        await MainActor.run {
                            guard !Task.isCancelled, self.cache[target.id] == nil else { return }
                            self.store(copy, for: target.id)
                            onUpdate(target.id, copy)
                        }
                    }
                    continue
                }
                if !target.isMinimized,
                   !SwitcherSupport.captureCoversWindow(imageWidth: image.width,
                                                        imageHeight: image.height,
                                                        windowSize: target.frame.size) {
                    // Only a slice of the window came back: the window server
                    // clips a capture to the part of the window that is inside
                    // a display, so a window hanging over a screen edge would
                    // show as a thin band. The fallback below returns the whole
                    // window wherever it sits. Minimized windows are exempt:
                    // their listed size can be a placeholder, and their capture
                    // is the last full one the window server kept.
                    pending.append(target)
                    continue
                }
                let scaled = Self.bitmapCopy(image, maxPixelSize: maxPixelSize)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.store(scaled, for: target.id)
                    onUpdate(target.id, scaled)
                }
            }
            guard !pending.isEmpty else { return }

            guard let content = try? await SCShareableContent.excludingDesktopWindows(false,
                                                                                      onScreenWindowsOnly: false)
            else { return }
            let scWindows = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })

            for target in pending {
                guard !Task.isCancelled else { return }
                guard let scWindow = scWindows[target.id]
                    ?? Self.bestWindowMatch(for: target, in: content.windows) else { continue }

                // Size the buffer from the window that was matched, not from the
                // listed entry: a stale or placeholder size with a different
                // shape would leave the window scaled into a corner of the
                // buffer with padding around it, which reads as a thin card.
                let source = scWindow.frame.width > 1 && scWindow.frame.height > 1
                    ? scWindow.frame
                    : target.frame
                let configuration = SCStreamConfiguration()
                let scale = min(1, maxPixelSize / max(source.width, source.height, 1))
                configuration.width = max(1, Int((source.width * scale).rounded()))
                configuration.height = max(1, Int((source.height * scale).rounded()))
                configuration.showsCursor = false

                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                              configuration: configuration)
                else { continue }
                guard !Task.isCancelled else { return }

                // Stage Manager renders strip-parked windows as a small sheared
                // snapshot floating on transparency, and this capture path can
                // return that artwork instead of the window content. Never show
                // it; rectify it as a stand-in when nothing better is cached.
                if let grid = SwitcherSupport.alphaGrid(of: image),
                   SwitcherSupport.captureLooksTransformed(alphaGrid: grid) {
                    if let rectified = Self.rectifiedStripCapture(image) {
                        let copy = Self.bitmapCopy(rectified)
                        await MainActor.run {
                            guard !Task.isCancelled, self.cache[target.id] == nil else { return }
                            self.store(copy, for: target.id)
                            onUpdate(target.id, copy)
                        }
                    }
                    continue
                }

                let copy = Self.bitmapCopy(image, maxPixelSize: maxPixelSize)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.store(copy, for: target.id)
                    onUpdate(target.id, copy)
                }
            }
        }
    }

    // MARK: - Window-server capture

    private typealias CGSConnectionID = UInt32
    private typealias CGSCaptureFunction =
        @convention(c) (CGSConnectionID, UnsafeMutablePointer<UInt32>, UInt32, UInt32) -> Unmanaged<CFArray>?

    /// `CGSHWCaptureWindowList` — resolved at runtime so a future macOS that
    /// drops the symbol degrades to the ScreenCaptureKit path instead of
    /// failing to launch.
    private static let windowServerCapture: CGSCaptureFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSHWCaptureWindowList")
        else { return nil }
        return unsafeBitCast(symbol, to: CGSCaptureFunction.self)
    }()

    private static let windowServerConnection: CGSConnectionID = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSMainConnectionID")
        else { return 0 }
        typealias ConnectionFunction = @convention(c) () -> CGSConnectionID
        return unsafeBitCast(symbol, to: ConnectionFunction.self)()
    }()

    /// Best resolution + ignore the global clip shape, so parked, minimized and
    /// other-Space windows come back as their real, untransformed content.
    private static let windowServerCaptureOptions: UInt32 = (1 << 8) | (1 << 11)

    /// Internal so the screenshot tool can reuse the existing window capture.
    static func captureViaWindowServer(_ windowID: CGWindowID) -> CGImage? {
        guard windowServerConnection != 0, let capture = windowServerCapture else { return nil }
        var id = UInt32(windowID)
        guard let array = capture(windowServerConnection, &id, 1, windowServerCaptureOptions)?
            .takeRetainedValue(),
            CFArrayGetCount(array) > 0,
            let value = CFArrayGetValueAtIndex(array, 0)
        else { return nil }
        let candidate = unsafeBitCast(value, to: CFTypeRef.self)
        guard CFGetTypeID(candidate) == CGImage.typeID else { return nil }
        let image = unsafeBitCast(candidate, to: CGImage.self)
        guard image.width > 1, image.height > 1 else { return nil }
        return image
    }

    private static let rectifyContext = CIContext()

    /// Recovers an upright preview from Stage Manager's tilted strip artwork:
    /// finds the opaque quadrilateral and reverses the perspective transform.
    /// Lower resolution than a real capture, so it is only used when nothing
    /// better is cached, and a clean capture replaces it as soon as the window
    /// becomes active.
    private static func rectifiedStripCapture(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 16, height > 16 else { return nil }
        let bytesPerPixel = 4
        var data = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * bytesPerPixel,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        guard drawn else { return nil }
        var alpha = [UInt8](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            alpha[index] = data[index * bytesPerPixel + 3]
        }
        guard let corners = SwitcherSupport.opaqueQuadCorners(alpha: alpha, width: width, height: height)
        else { return nil }

        func vector(_ point: CGPoint) -> CIVector {
            CIVector(x: point.x, y: CGFloat(height - 1) - point.y)
        }
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(vector(corners.topLeft), forKey: "inputTopLeft")
        filter.setValue(vector(corners.topRight), forKey: "inputTopRight")
        filter.setValue(vector(corners.bottomRight), forKey: "inputBottomRight")
        filter.setValue(vector(corners.bottomLeft), forKey: "inputBottomLeft")
        guard let corrected = filter.outputImage,
              corrected.extent.width > 16, corrected.extent.height > 16
        else { return nil }

        // The strip artwork holds ~230-320 px for a whole window; a switcher
        // tile displays around 3x that. Lanczos plus a light sharpen keeps the
        // upscale legible where the tile's plain bilinear stretch turns to mush.
        let maxSide = max(corrected.extent.width, corrected.extent.height)
        let upscale = min(3.0, 900.0 / maxSide)
        var output = corrected
        if upscale > 1.05,
           let lanczos = CIFilter(name: "CILanczosScaleTransform"),
           let sharpen = CIFilter(name: "CISharpenLuminance") {
            lanczos.setValue(corrected, forKey: kCIInputImageKey)
            lanczos.setValue(upscale, forKey: kCIInputScaleKey)
            lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
            sharpen.setValue(lanczos.outputImage, forKey: kCIInputImageKey)
            sharpen.setValue(0.5, forKey: kCIInputSharpnessKey)
            output = sharpen.outputImage ?? corrected
        }
        guard let rendered = rectifyContext.createCGImage(output, from: output.extent) else { return nil }
        return rendered
    }

    /// Redraws a capture into a bitmap this process owns, downscaling to
    /// `maxPixelSize` when the source is larger. Window-server, SCK and Core
    /// Image captures are surface-backed by the system; caching one directly
    /// would pin that surface (and whatever the OS charges to it) for as long
    /// as the thumbnail lives, so the cache only ever holds plain copies.
    private static func bitmapCopy(_ image: CGImage,
                                   maxPixelSize: CGFloat = .greatestFiniteMagnitude) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, maxPixelSize / max(width, height, 1))
        let scaledWidth = max(1, Int(width * scale))
        let scaledHeight = max(1, Int(height * scale))
        guard let context = CGContext(data: nil,
                                      width: scaledWidth,
                                      height: scaledHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = scale < 1 ? .high : .default
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(scaledWidth), height: CGFloat(scaledHeight)))
        return context.makeImage() ?? image
    }

    func cancel() {
        captureTask?.cancel()
        captureTask = nil
    }

    // MARK: - Cache lifetime

    private func pruneCache(keeping active: Set<CGWindowID>) {
        let existing = Self.existingWindowIDs() ?? Set(cache.keys)
        cache = cache.filter { existing.contains($0.key) }
        lastTouched = lastTouched.filter { cache[$0.key] != nil }
        let victims = SwitcherSupport.staleCacheVictims(ids: Set(cache.keys),
                                                        active: active,
                                                        lastTouched: lastTouched,
                                                        limit: Self.cacheLimit)
        for id in victims {
            cache[id] = nil
            lastTouched[id] = nil
        }
        let byteVictims = SwitcherSupport.cacheByteBudgetVictims(
            sizes: cache.mapValues { $0.bytesPerRow * $0.height },
            active: active,
            lastTouched: lastTouched,
            budget: Self.cacheByteBudget)
        for id in byteVictims {
            cache[id] = nil
            lastTouched[id] = nil
        }
    }

    private static func existingWindowIDs() -> Set<CGWindowID>? {
        guard let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        return Set(info.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
    }

    private func store(_ image: CGImage, for id: CGWindowID) {
        cache[id] = image
        lastTouched[id] = ProcessInfo.processInfo.systemUptime
    }

    // MARK: - Opportunistic warming

    /// Windows parked in the Stage Manager strip cannot be captured (every API
    /// returns the strip's tilted artwork), so the cache is warmed the moment
    /// an app becomes active — its windows are capturable right then. By the
    /// time the switcher opens, most tiles have a real last-seen preview even
    /// if their window is parked again.
    func startWarming() {
        guard activationToken == nil else { return }
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.scheduleWarm(pid: app.processIdentifier)
        }
        if let front = NSWorkspace.shared.frontmostApplication {
            scheduleWarm(pid: front.processIdentifier)
        }
    }

    func stopWarming() {
        if let activationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(activationToken)
        }
        activationToken = nil
        pendingWarmPid = nil
        warmTask?.cancel()
        warmTask = nil
    }

    /// Waits for the stage/space transition to settle, then captures the
    /// activated app's windows. Never prunes: warming only adds fresh entries.
    private func scheduleWarm(pid: pid_t) {
        guard Permissions.shared.screenRecording else { return }
        pendingWarmPid = pid
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.pendingWarmPid == pid, self.activationToken != nil else { return }
            self.pendingWarmPid = nil
            let items = WindowEnumerator.listWindows(for: pid)
            guard !items.isEmpty else { return }
            warmTask?.cancel()
            warmTask = Task(priority: .utility) { [weak self] in
                guard let self else { return }
                for item in items {
                    guard !Task.isCancelled, let id = item.previewWindowID else { continue }
                    guard let image = Self.captureViaWindowServer(id) else { continue }
                    if let grid = SwitcherSupport.alphaGrid(of: image),
                       SwitcherSupport.captureLooksTransformed(alphaGrid: grid) {
                        if let rectified = Self.rectifiedStripCapture(image) {
                            let copy = Self.bitmapCopy(rectified)
                            await MainActor.run {
                                guard self.cache[id] == nil else { return }
                                self.store(copy, for: id)
                            }
                        }
                        continue
                    }
                    // Same clipped-capture guard as the refresh path, without a
                    // fallback: warming only ever adds good thumbnails, so a
                    // sliced one is dropped rather than cached.
                    if !item.isMinimized,
                       !SwitcherSupport.captureCoversWindow(imageWidth: image.width,
                                                            imageHeight: image.height,
                                                            windowSize: item.frame.size) {
                        continue
                    }
                    let scaled = Self.bitmapCopy(image, maxPixelSize: Self.defaultMaxPixelSize)
                    await MainActor.run { self.store(scaled, for: id) }
                }
                await MainActor.run { self.pruneCache(keeping: []) }
            }
        }
    }

    private struct PreviewTarget {
        let id: CGWindowID
        let pid: pid_t
        let title: String
        let appName: String
        let frame: CGRect
        let isMinimized: Bool
    }

    private static func bestWindowMatch(for target: PreviewTarget, in windows: [SCWindow]) -> SCWindow? {
        let candidates = windows.filter { window in
            window.owningApplication?.processID == target.pid
        }
        guard !candidates.isEmpty else { return nil }

        if let titled = candidates.first(where: { titlesMatch($0.title, target.title) }) {
            return titled
        }

        let frameMatches = candidates
            .map { window in (window: window, score: frameDistance(window.frame, target.frame)) }
            .filter { $0.score < 80 }
            .sorted { $0.score < $1.score }

        if let closest = frameMatches.first?.window {
            return closest
        }

        if candidates.count == 1 {
            return candidates[0]
        }
        return nil
    }

    private static func titlesMatch(_ lhs: String?, _ rhs: String) -> Bool {
        let left = (lhs ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
    }

    private static func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.midX - rhs.midX)
            + abs(lhs.midY - rhs.midY)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }
}
