// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import os
import ScreenCaptureKit

/// Owns the live clone overlays: one borderless floating panel plus one
/// ScreenCaptureKit stream per pinned window.
///
/// Floaty's answer to a window server that ignores cross-process level
/// changes: never touch the other app's window at all. The pinned window
/// keeps its own level and order while this process captures it and shows
/// the pixels in a borderless panel of our own at the floating level, which
/// macOS still grants to our own windows. The clone draws exactly over the
/// original, is click-through so every click lands on the real window
/// beneath, and follows the original through moves and resizes on the frames
/// the pinning service reads on its sweeps.
///
/// The service calls every entry point on the main thread (its timers and
/// Accessibility work all live there); stream callbacks arrive on the shared
/// serial queue and hop back to main before touching overlay state, the same
/// split RecorderCaptureEngine keeps.
final class WindowPinningOverlayManager {
    static let shared = WindowPinningOverlayManager()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "window-pinning")

    /// The clone reads as live at 30 fps, and the stream runs for as long as
    /// the pin holds — one per pinned window, next to every other pin's — so
    /// the cheaper cadence wins over the recorder's 60.
    fileprivate static let frameRate = 30

    /// Every overlay's stream output shares one serial queue, like the
    /// engine's single capture queue: callbacks for different windows never
    /// overlap, and teardown can drain the queue to quiesce a stopping
    /// stream before its panel goes away.
    fileprivate static let streamQueue = DispatchQueue(label: "com.vorssaint.window-pinning.overlay",
                                                       qos: .userInitiated)

    private var overlays: [UInt32: WindowPinningOverlay] = [:]
    /// Pointer monitors and the app-activation observer, installed only
    /// while a clone exists.
    private var mouseMonitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    /// A click or app switch reorders windows a beat after the event itself;
    /// visibility is re-read once the window server has caught up.
    private static let reorderSettleDelay: TimeInterval = 0.05

    /// Called when a clone catches a click because another window covers the
    /// original there; the service brings the original forward.
    var onCloneClicked: ((PinnedWindowEntry) -> Void)?

    private init() {}

    // MARK: - Permission

    /// Screen Recording permission state (prompts via CGRequestScreenCaptureAccess).
    var hasScreenRecordingPermission: Bool { CGPreflightScreenCaptureAccess() }

    func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Overlays

    /// Shows the overlay for a pinned window. Returns false when Screen
    /// Recording is missing or the window cannot be shared right now; the
    /// caller keeps its pin and retries on later sweeps.
    @discardableResult
    func startOverlay(for entry: PinnedWindowEntry) -> Bool {
        guard hasScreenRecordingPermission else {
            Self.log.info("overlay refused for window \(entry.windowID, privacy: .public): Screen Recording not granted")
            return false
        }
        guard overlays[entry.windowID] == nil else { return true }

        // The ScreenCaptureKit window lookup is asynchronous, so the
        // synchronous "cannot be shared" signal is the window server itself:
        // a window missing from its list is gone for good. A window that
        // merely lags ScreenCaptureKit's content listing is caught by the
        // retry inside the overlay; if it still cannot be shared the overlay
        // removes itself and isActive flipping false tells the caller's next
        // sweep to retry or prune.
        guard let windowServerFrame = WindowServerSupport.frame(ofWindowID: entry.windowID) else {
            return false
        }

        let overlay = WindowPinningOverlay(
            entry: entry,
            frame: Self.occlusionBeatingFrame(Self.appkitFrame(fromWindowServerFrame: windowServerFrame)))
        overlay.onStreamEnded = { [weak self] windowID in
            // The stream ended without being asked (owner quit, window
            // closed, capture error): a clone frozen on its last frame would
            // masquerade as the pinned window, so drop it.
            self?.removeOverlay(windowID: windowID, stopStream: false)
        }
        overlay.onClicked = { [weak self, weak overlay] in
            guard let self, let overlay else { return }
            // The original comes forward, so the next click under the
            // pointer belongs to it again.
            overlay.setClickThrough(true)
            self.onCloneClicked?(overlay.entry)
        }
        overlays[entry.windowID] = overlay
        updateMouseMonitors()
        updateVisibility()
        overlay.beginCapture { [weak self] windowID in
            self?.removeOverlay(windowID: windowID, stopStream: false)
        }
        return true
    }

    func stopOverlay(windowID: UInt32) {
        removeOverlay(windowID: windowID, stopStream: true)
    }

    func stopAll() {
        for windowID in Array(overlays.keys) {
            removeOverlay(windowID: windowID, stopStream: true)
        }
    }

    /// Moves overlays to the frames the caller read from the window server,
    /// keyed by CGWindowID. Ids without an overlay or without a frame are
    /// ignored.
    func syncFrames(_ frames: [UInt32: CGRect]) {
        for (windowID, windowServerFrame) in frames {
            overlays[windowID]?.move(to: Self.occlusionBeatingFrame(Self.appkitFrame(fromWindowServerFrame: windowServerFrame)))
        }
        // The pointer may sit still while windows reorder under it.
        updateVisibility()
        routeClicks()
    }

    /// True while an overlay exists for the id.
    func isActive(windowID: UInt32) -> Bool {
        overlays[windowID] != nil
    }

    // MARK: - Teardown

    private func removeOverlay(windowID: UInt32, stopStream: Bool) {
        guard let overlay = overlays[windowID] else { return }
        overlays[windowID] = nil
        overlay.tearDown(stopStream: stopStream)
        updateMouseMonitors()
    }

    // MARK: - Click routing

    /// A click-through clone sends every click to whatever window really
    /// sits at that point. Once another window covers the original, that is
    /// the other window, and the floating clone looks clickable but is not.
    /// So the clone under the pointer only stays click-through while the
    /// original would take the click; otherwise it catches the click and
    /// raises the original.
    private func updateMouseMonitors() {
        guard overlays.isEmpty || mouseMonitors.isEmpty else { return }
        guard !overlays.isEmpty else {
            mouseMonitors.forEach(NSEvent.removeMonitor)
            mouseMonitors.removeAll()
            if let activationObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
                self.activationObserver = nil
            }
            return
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                self?.updateVisibilitySoon()
            }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.handlePointer(event)
        }) { mouseMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.handlePointer(event)
            return event
        }) { mouseMonitors.append(token) }
    }

    private func handlePointer(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged: followDrag()
        case .leftMouseDown, .leftMouseUp: updateVisibilitySoon()
        default: break
        }
        routeClicks()
    }

    /// The clone only shows while another window overlaps the original.
    /// Uncovered, the original is already in front, and letting it show
    /// directly keeps drags and resizes native instead of trailing a capture.
    private func updateVisibility() {
        guard !overlays.isEmpty else { return }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                 kCGNullWindowID) as? [[String: Any]] ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for overlay in overlays.values {
            overlay.setShown(WindowPinningResolver.isCovered(
                pinnedWindowID: overlay.entry.windowID,
                pinnedOwnerPID: overlay.entry.ownerPID,
                ownPID: ownPID,
                windows: windows))
        }
    }

    private func updateVisibilitySoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reorderSettleDelay) { [weak self] in
            self?.updateVisibility()
            self?.routeClicks()
        }
    }

    /// The service's sweep runs every 150 ms, which a dragged clone visibly
    /// trails. While a drag is under way every drag event re-reads each
    /// original's frame from the window server (a cheap single-window query)
    /// so the clone moves in step with the pointer.
    private func followDrag() {
        for (windowID, overlay) in overlays {
            guard let frame = WindowServerSupport.frame(ofWindowID: windowID) else { continue }
            overlay.move(to: Self.occlusionBeatingFrame(Self.appkitFrame(fromWindowServerFrame: frame)))
        }
    }

    private func routeClicks() {
        let cursor = NSEvent.mouseLocation
        let hovered = overlays.values.filter { $0.contains(appkitPoint: cursor) }
        guard !hovered.isEmpty else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
        let point = CGPoint(x: cursor.x, y: primaryHeight - cursor.y)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                 kCGNullWindowID) as? [[String: Any]] ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for overlay in hovered {
            overlay.setClickThrough(WindowPinningResolver.clickFallsThrough(
                at: point,
                pinnedWindowID: overlay.entry.windowID,
                pinnedOwnerPID: overlay.entry.ownerPID,
                ownPID: ownPID,
                windows: windows))
        }
    }

    // MARK: - Coordinates

    /// The window server reports frames top-left-origin with the main display
    /// at (0,0); AppKit positions windows bottom-left-origin with the main
    /// screen at (0,0). Flipping around the PRIMARY screen's height (the first
    /// entry, not `main`, which follows the key window and can sit on another
    /// display) lands a window-server frame exactly where `NSPanel.setFrame`
    /// expects it, on any display in the arrangement.
    fileprivate static func appkitFrame(fromWindowServerFrame frame: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
        return CGRect(x: frame.minX,
                      y: primaryHeight - frame.maxY,
                      width: frame.width,
                      height: frame.height)
    }

    /// The clone covers the original exactly: a covered original stops
    /// painting (window-server occlusion) and shows as a blank white surface,
    /// and any uncovered sliver of it is exactly that — a white ring around
    /// the clone. Covering it entirely hides the blank surface; keeping the
    /// pin's original content live is the stream's job, and the window server
    /// keeps the backing store that the stream reads.
    fileprivate static func occlusionBeatingFrame(_ appkitFrame: CGRect) -> CGRect {
        appkitFrame
    }
}

/// One pinned window's clone: the panel showing it, the sample display layer
/// inside the panel and the stream feeding that layer. Modeled on
/// RecorderCaptureEngine: buffers arrive on the manager's serial queue,
/// shared state sits behind one lock, and teardown drains the queue so no
/// callback outlives its overlay.
private final class WindowPinningOverlay: NSObject {
    let entry: PinnedWindowEntry
    /// The manager drops the overlay (closing the panel) when the stream
    /// ends by itself, which is what keeps isActive honest.
    var onStreamEnded: ((UInt32) -> Void)?
    /// A click the clone caught while it was not click-through.
    var onClicked: (() -> Void)?

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "window-pinning")

    private let stateLock = NSLock()
    private var stream: SCStream?
    /// The running stream's configuration, kept so a resize of the original
    /// can update its output size in place.
    private var streamConfiguration: SCStreamConfiguration?
    /// The panel size a scheduled stream resize will apply; non-nil while one
    /// is scheduled.
    private var pendingStreamSize: CGSize?
    /// A live resize reports a new size on every drag event; the stream is
    /// reconfigured at most this often, plus once with the final size.
    private static let streamResizeInterval: TimeInterval = 0.1
    /// Stream pixels per point, as last configured. Guarded by stateLock: the
    /// stream queue reads it to size each buffer in points.
    private var streamScale: CGFloat = 2
    /// Pixel size of the last buffer the layer was laid out for, and whether a
    /// layout for a new size is on its way to main. Guarded by stateLock.
    private var layoutBufferPixelSize: CGSize?
    private var layoutPending = false
    /// The point size the display layer is laid out at: the latest buffer's,
    /// never the panel's, so a frame is never stretched. Main thread only.
    private var bufferPointSize: CGSize?
    private var displayLayer: AVSampleBufferDisplayLayer?
    private var panel: NSPanel?
    /// Set the moment teardown starts, so a content fetch or retry landing
    /// afterwards cannot resurrect a stopped overlay.
    private var stopping = false

    /// How long a missing window waits for ScreenCaptureKit's listing to
    /// catch up with the window server before the single retry.
    private static let fetchRetryDelayNanoseconds: UInt64 = 500_000_000

    init(entry: PinnedWindowEntry, frame: CGRect) {
        self.entry = entry
        super.init()
        panel = makePanel(frame: frame)
    }

    // MARK: - Panel

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .floating
        // Transparent, not opaque: the captured window has rounded corners
        // whose pixels carry zero alpha, and an opaque panel fills them in as
        // a square box (white, or black) around the clone.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Click-through by default: the clone covers the real window, so
        // clicks fall through to the original underneath. The manager turns
        // it off while another window covers the original under the pointer.
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        // No shadow of our own: the original window keeps its shadow, and a
        // clone dragging a second shadow around would double it up.
        panel.hasShadow = false
        // Not on all Spaces: the clone belongs to the original's Space. The
        // manager orders it in only while the original is on screen, and
        // ordering in places it on the active Space, which is then the
        // original's.
        panel.collectionBehavior = [.stationary, .ignoresCycle]
        panel.animationBehavior = .none
        // NSPanel hides itself when the app deactivates by default; a pin
        // has to survive the user clicking back into the app they pinned.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let host = WindowPinningCloneView(frame: NSRect(origin: .zero, size: frame.size))
        host.wantsLayer = true
        host.onMouseDown = { [weak self] in self?.onClicked?() }
        let displayLayer = AVSampleBufferDisplayLayer()
        // Fill, not fit: the panel is the window's frame exactly, so an
        // aspect fit would leave letterbox bands around the clone.
        displayLayer.videoGravity = .resize
        displayLayer.backgroundColor = NSColor.clear.cgColor
        displayLayer.isOpaque = false
        displayLayer.frame = host.bounds
        // The layer is laid out at each buffer's own size (layoutDisplayLayer),
        // which overshoots the panel for a beat when the window shrinks.
        host.layer?.masksToBounds = true
        host.layer?.addSublayer(displayLayer)
        panel.contentView = host
        self.displayLayer = displayLayer
        Self.log.debug("panel up for window \(self.entry.windowID, privacy: .public): frame=\(String(describing: frame), privacy: .public) screens=\(String(describing: NSScreen.screens.map { $0.frame }), privacy: .public)")
        // Ordered in by the manager's visibility pass, not here: a pin
        // restored at launch may belong to a Space that is not active.
        return panel
    }

    // MARK: - Capture

    /// Looks the window up in ScreenCaptureKit's shareable content and starts
    /// the stream on it. ScreenCaptureKit can briefly lag the window server
    /// right after a window appears, so a miss retries once before the
    /// overlay gives up and lets the caller's sweep retry later.
    func beginCapture(onCaptureFailed: @escaping (UInt32) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            let window = await self.fetchShareableWindow(attempt: 0)
            await MainActor.run {
                guard !self.stopping else { return }
                if let window {
                    self.startStream(with: window)
                } else {
                    onCaptureFailed(self.entry.windowID)
                }
            }
        }
    }

    private func fetchShareableWindow(attempt: Int) async -> SCWindow? {
        // Off-screen windows stay in the listing (`onScreenWindowsOnly:
        // false`): a pin restored at launch whose window sits on another
        // Space still gets its stream, ready for when that Space is active
        // again. The completion-handler form
        // of this call is gone from the macOS 26 SDK (only the async import
        // remains), so the engine's `try await` shape carries the lookup;
        // the retry around it is this feature's, not the engine's.
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                               onScreenWindowsOnly: false)
            if let window = content.windows.first(where: { $0.windowID == entry.windowID }) {
                return window
            }
            guard attempt == 0 else {
                Self.log.info("window \(self.entry.windowID, privacy: .public) not in shareable content after retry")
                return nil
            }
        } catch {
            // A hard error (permission revoked mid-flight, system capture
            // failure) is not the transient "listing lags the window
            // server" case the retry exists for.
            Self.log.error("shareable content for window \(self.entry.windowID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        try? await Task.sleep(nanoseconds: Self.fetchRetryDelayNanoseconds)
        return await fetchShareableWindow(attempt: 1)
    }

    private func startStream(with window: SCWindow) {
        guard !stopping else { return }
        let configuration = SCStreamConfiguration()
        let scale = Self.backingScale(forWindowServerFrame: window.frame)
        configuration.width = max(1, Int((window.frame.width * scale).rounded()))
        configuration.height = max(1, Int((window.frame.height * scale).rounded()))
        configuration.minimumFrameInterval = CMTime(value: 1,
                                                    timescale: CMTimeScale(WindowPinningOverlayManager.frameRate))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.capturesAudio = false
        // The clone carries no pointer: the real cursor already shows on the
        // real window under the click-through panel.
        configuration.showsCursor = false
        // Keep the window's alpha so its rounded corners stay see-through.
        configuration.shouldBeOpaque = false
        // The stream is sized to the window now and resized with it (see
        // scheduleStreamResize). Until a resize lands, the window draws 1:1
        // into the old output, cropped or with an empty margin, and the layer
        // shows each buffer at its own size: never scaled, so a resize never
        // squeezes the clone. A margin shows the live original underneath.
        configuration.scalesToFit = false
        configuration.captureResolution = .best
        configuration.ignoreShadowsDisplay = true
        configuration.ignoreShadowsSingleWindow = true

        Self.log.debug("stream starting for window \(self.entry.windowID, privacy: .public): scFrame=\(String(describing: window.frame), privacy: .public) scale=\(scale, privacy: .public) panel=\(String(describing: self.panel?.frame), privacy: .public)")
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window),
                              configuration: configuration,
                              delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen,
                                       sampleHandlerQueue: WindowPinningOverlayManager.streamQueue)
        } catch {
            Self.log.error("overlay stream for window \(self.entry.windowID, privacy: .public) could not attach its output: \(error.localizedDescription, privacy: .public)")
            onStreamEnded?(self.entry.windowID)
            return
        }
        stateLock.withLock {
            self.stream = stream
            self.streamScale = scale
        }
        streamConfiguration = configuration
        // Held strongly: the overlay must stay alive until the start settles,
        // whether it lands (startCaptureSettled) or fails (startCaptureFailed).
        Task {
            do {
                try await stream.startCapture()
            } catch {
                await MainActor.run { self.startCaptureFailed(stream, error: error) }
                return
            }
            await MainActor.run { self.startCaptureSettled(stream) }
        }
    }

    private func startCaptureFailed(_ stream: SCStream, error: Error) {
        let wasCurrent = stateLock.withLock { () -> Bool in
            guard self.stream === stream else { return false }
            self.stream = nil
            return true
        }
        guard wasCurrent else { return }
        Self.log.error("overlay stream for window \(self.entry.windowID, privacy: .public) failed to start: \(error.localizedDescription, privacy: .public)")
        onStreamEnded?(entry.windowID)
    }

    /// The answer to a stop that raced the start: the stream came up after
    /// teardown already ran, so nobody else will ever stop it and it must be
    /// stopped here — a live capture with no panel would run forever.
    private func startCaptureSettled(_ stream: SCStream) {
        let isCurrent = stateLock.withLock { self.stream === stream }
        guard !isCurrent else { return }
        Task { try? await stream.stopCapture() }
    }

    // MARK: - Teardown

    /// Closes the panel and stops the stream. The display layer detaches
    /// first so a callback already past its stream check finds nothing left
    /// to draw into, and the serial queue drains afterwards like the engine
    /// drains its capture queue: a buffer that beat the stop must finish
    /// enqueueing before the overlay disappears.
    func tearDown(stopStream: Bool) {
        stopping = true
        let stream = stateLock.withLock { () -> SCStream? in
            let current = stopStream ? self.stream : nil
            self.stream = nil
            return current
        }
        let displayLayer = stateLock.withLock { () -> AVSampleBufferDisplayLayer? in
            let layer = self.displayLayer
            self.displayLayer = nil
            return layer
        }
        displayLayer?.removeFromSuperlayer()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        if let stream {
            Task {
                try? await stream.stopCapture()
                WindowPinningOverlayManager.streamQueue.sync {}
            }
        } else {
            WindowPinningOverlayManager.streamQueue.sync {}
        }
    }

    func setClickThrough(_ clickThrough: Bool) {
        guard let panel, panel.ignoresMouseEvents != clickThrough else { return }
        panel.ignoresMouseEvents = clickThrough
    }

    func setShown(_ shown: Bool) {
        guard let panel, panel.isVisible != shown else { return }
        if shown {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    func contains(appkitPoint point: CGPoint) -> Bool {
        guard let panel, panel.isVisible else { return false }
        return NSMouseInRect(point, panel.frame, false)
    }

    /// Moves the clone to where the window server now reports the original.
    func move(to appkitFrame: CGRect) {
        guard let panel, panel.frame != appkitFrame else { return }
        let resized = panel.frame.size != appkitFrame.size
        panel.setFrame(appkitFrame, display: resized)
        guard resized else { return }
        layoutDisplayLayer()
        scheduleStreamResize(to: appkitFrame.size)
    }

    /// Keeps the stream's output the window's size, so a resized original is
    /// not squeezed into the size it had when it was pinned.
    private func scheduleStreamResize(to size: CGSize) {
        let alreadyScheduled = pendingStreamSize != nil
        pendingStreamSize = size
        guard !alreadyScheduled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.streamResizeInterval) { [weak self] in
            guard let self, let size = self.pendingStreamSize else { return }
            self.pendingStreamSize = nil
            self.resizeStream(to: size)
        }
    }

    private func resizeStream(to size: CGSize) {
        guard !stopping,
              let configuration = streamConfiguration,
              let stream = stateLock.withLock({ self.stream }) else { return }
        let scale = panel?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        guard configuration.width != width || configuration.height != height else { return }
        configuration.width = width
        configuration.height = height
        stateLock.withLock { self.streamScale = scale }
        Task { [entry] in
            do {
                try await stream.updateConfiguration(configuration)
            } catch {
                Self.log.error("overlay stream for window \(entry.windowID, privacy: .public) could not resize: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Pins the display layer to the panel's top-left corner at the latest
    /// buffer's point size, which is where the window draws itself in an
    /// unscaled capture.
    private func layoutDisplayLayer() {
        guard let host = panel?.contentView,
              let displayLayer = stateLock.withLock({ self.displayLayer }) else { return }
        let size = bufferPointSize ?? host.bounds.size
        // A standalone sublayer animates frame changes implicitly (a quarter
        // second), which reads as the clone lagging a resize.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = CGRect(x: 0, y: host.bounds.height - size.height,
                                    width: size.width, height: size.height)
        CATransaction.commit()
    }

    // MARK: - Coordinates

    /// Stream pixels per point of window: the backing factor of the display
    /// the window sits on, falling back to the main screen's. SCWindow's
    /// display link is gone from the macOS 26 SDK, but which display a window
    /// sits on is still recoverable geometrically, which is all this lookup
    /// ever needed.
    private static func backingScale(forWindowServerFrame frame: CGRect) -> CGFloat {
        let appkitFrame = WindowPinningOverlayManager.appkitFrame(fromWindowServerFrame: frame)
        let center = CGPoint(x: appkitFrame.midX, y: appkitFrame.midY)
        for screen in NSScreen.screens where screen.frame.contains(center) {
            return screen.backingScaleFactor
        }
        return NSScreen.main?.backingScaleFactor ?? 2
    }
}

// MARK: - Stream callbacks

extension WindowPinningOverlay: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              Self.carriesPixels(sampleBuffer) else { return }
        let layer = stateLock.withLock { () -> AVSampleBufferDisplayLayer? in
            guard self.stream === stream else { return nil }
            return displayLayer
        }
        // A live view drops a frame the display layer cannot take: one stale
        // beat is invisible, a growing queue would turn the clone into a
        // delayed echo of the original.
        guard let layer, layer.isReadyForMoreMediaData,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pixelSize = CGSize(width: CVPixelBufferGetWidth(imageBuffer),
                               height: CVPixelBufferGetHeight(imageBuffer))
        enum Route { case enqueue, relayout(CGSize), drop }
        let route = stateLock.withLock { () -> Route in
            // Frames behind a pending relayout are dropped, so none of them
            // overtakes it and shows at the old layout.
            if layoutPending { return .drop }
            guard pixelSize != layoutBufferPixelSize else { return .enqueue }
            layoutBufferPixelSize = pixelSize
            layoutPending = true
            return .relayout(CGSize(width: pixelSize.width / streamScale,
                                    height: pixelSize.height / streamScale))
        }
        switch route {
        case .drop:
            return
        case .enqueue:
            layer.enqueue(sampleBuffer)
        case .relayout(let pointSize):
            // A buffer of a new size is laid out on main before it shows. Main
            // never waits on this queue except in teardown, which only drains.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.bufferPointSize = pointSize
                self.layoutDisplayLayer()
                layer.enqueue(sampleBuffer)
                self.stateLock.withLock { self.layoutPending = false }
            }
        }
    }

    /// The recorder's pixel test, copied whole: a buffer only counts when the
    /// display actually changed and the buffer carries an image, so an idle
    /// pinned window never enqueues blank frames on the clone. One deliberate
    /// divergence: the recorder also accepts `.started` frames because an
    /// archive wants the earliest frame; a live clone prefers to wait a beat
    /// for real pixels, because the first `.started` frame of a capture is
    /// usually empty — and reads as a white flash while it waits.
    private static func carriesPixels(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return false }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete
    }
}

extension WindowPinningOverlay: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let wasCurrent = stateLock.withLock { () -> Bool in
            guard self.stream === stream else { return false }
            self.stream = nil
            return true
        }
        guard wasCurrent else { return }
        Self.log.error("overlay stream for window \(self.entry.windowID, privacy: .public) stopped: \(error.localizedDescription, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onStreamEnded?(self.entry.windowID)
        }
    }
}

/// The clone's content view: it only sees clicks while the panel is not
/// click-through, and takes the first one even though the panel never becomes
/// key, so a single click raises the original.
private final class WindowPinningCloneView: NSView {
    var onMouseDown: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }
}
