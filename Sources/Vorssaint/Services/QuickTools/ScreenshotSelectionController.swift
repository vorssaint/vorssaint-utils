// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox

/// The capture surface: one borderless panel per screen, above everything,
/// where the user drags a region, clicks a window or confirms a full screen.
///
/// With freeze on (the default) every display is photographed first and the
/// panels show that still image while the area is chosen. With freeze off the
/// panels are transparent and pixels are captured at confirmation time.
final class ScreenshotSelectionController {

    struct Capture {
        let image: CGImage
        /// Pixels per point of the source display, for 1x export math.
        let scale: CGFloat
        /// The captured area in Cocoa global coordinates.
        let anchorRect: CGRect
    }

    enum Outcome {
        case captured(Capture)
        case cancelled
        case failed
    }

    private var panels: [ScreenshotOverlayPanel] = []
    private var keyMonitor: Any?
    private var completion: ((Outcome) -> Void)?
    private let freeze: Bool
    private let includePointer: Bool
    private var finished = false
    /// Read by the overlays so a late event finds a session that is over.
    fileprivate var isOver: Bool { finished }
    fileprivate var spaceIsDown = false
    fileprivate var loupeEnabled = false {
        didSet { panels.forEach { $0.overlayView.refreshPointerState() } }
    }
    fileprivate var loupeZoom: CGFloat = 1 {
        didSet { panels.forEach { $0.overlayView.needsDisplay = true } }
    }

    /// The last confirmed region, per display, so R repeats it instantly.
    private static var lastRegion: (displayID: CGDirectDisplayID, viewRect: CGRect)?

    private let strings = FeatureStrings.screenshot(L10n.shared.language)

    init(freeze: Bool, includePointer: Bool) {
        self.freeze = freeze
        self.includePointer = includePointer
    }

    func begin(completion: @escaping (Outcome) -> Void) {
        self.completion = completion
        if freeze {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let images = await ScreenshotCaptureEngine.captureAllDisplays(
                    includePointer: self.includePointer)
                guard !images.isEmpty else {
                    self.finish(.failed)
                    return
                }
                self.present(frozenImages: images)
            }
        } else {
            present(frozenImages: [:])
        }
    }

    private func present(frozenImages: [CGDirectDisplayID: CGImage]) {
        guard !finished else { return }
        let pickable = ScreenshotCaptureEngine.pickableWindows()
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0

        for screen in NSScreen.screens {
            let displayID = screen.displayID
            if freeze, frozenImages[displayID] == nil { continue }
            let windows = pickable.map { entry -> ScreenshotSupport.PickableWindow in
                let cocoa = ScreenshotSupport.cocoaRect(fromWindowServer: entry.bounds,
                                                        mainScreenHeight: mainHeight)
                let viewRect = ScreenshotSupport.flippedViewRect(fromCocoa: cocoa,
                                                                 screenFrame: screen.frame)
                return ScreenshotSupport.PickableWindow(windowID: entry.id, frame: viewRect)
            }.filter { $0.frame.intersects(CGRect(origin: .zero, size: screen.frame.size)) }

            let panel = ScreenshotOverlayPanel(screen: screen,
                                               frozenImage: frozenImages[displayID],
                                               windows: windows,
                                               controller: self,
                                               strings: strings)
            if let last = Self.lastRegion, last.displayID == displayID {
                panel.overlayView.ghostRect = last.viewRect
            }
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        guard !panels.isEmpty else {
            finish(.failed)
            return
        }
        keyPanelUnderMouse()?.makeKey()
        installKeyMonitor()
        NSCursor.crosshair.set()
    }

    /// Live selection stays transparent, but the loupe still needs source
    /// pixels. Capture them once after the overlays exist; ScreenCaptureKit
    /// excludes this app's own panels, so the screen itself remains live.
    private func loadLiveLoupeImages() {
        Task { @MainActor [weak self] in
            let images = await ScreenshotCaptureEngine.captureAllDisplays(includePointer: false)
            guard let self, !self.finished else { return }
            for panel in self.panels {
                panel.overlayView.updateLoupeImage(images[panel.displayID])
            }
        }
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, event.window is ScreenshotOverlayPanel else { return event }
            if event.type == .keyUp {
                if event.keyCode == UInt16(kVK_Space) { self.spaceIsDown = false }
                return nil
            }
            switch Int(event.keyCode) {
            case kVK_Escape:
                self.finish(.cancelled)
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.captureFullDisplayUnderMouse()
            case kVK_Space:
                if let panel = self.panelUnderMouse(), panel.overlayView.isDragging {
                    // Holding Space moves the in-progress selection.
                    self.spaceIsDown = true
                }
            case kVK_ANSI_R:
                self.repeatLastRegion()
            case _ where Self.isLoupeKey(event):
                self.toggleLoupe()
            default:
                break
            }
            return nil
        }
    }

    /// The loupe toggle follows the typed character, with the physical slot
    /// as a fallback: the Z key sits elsewhere on some keyboard layouts and
    /// the localized hints promise the letter itself.
    private static func isLoupeKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        else { return false }
        if let typed = event.charactersIgnoringModifiers?.lowercased(), !typed.isEmpty {
            return typed == "z"
        }
        return Int(event.keyCode) == kVK_ANSI_Z
    }

    private func toggleLoupe() {
        loupeEnabled.toggle()
        // Live mode has no frozen shot to sample. Pixels are fetched only
        // when the loupe actually turns on, and fresh each time, so it
        // magnifies what is on screen now instead of the session's opening
        // frame and idle sessions never pay for a capture.
        if loupeEnabled, !freeze {
            loadLiveLoupeImages()
        }
    }

    fileprivate func adjustLoupeZoom(by scrollDelta: CGFloat) {
        loupeZoom = ScreenshotSupport.captureLoupeZoom(loupeZoom, adjustedBy: scrollDelta)
    }

    private func panelUnderMouse() -> ScreenshotOverlayPanel? {
        let location = NSEvent.mouseLocation
        return panels.first { $0.screenFrame.contains(location) } ?? panels.first
    }

    private func keyPanelUnderMouse() -> ScreenshotOverlayPanel? {
        panelUnderMouse()
    }

    // MARK: - Confirmations (called by the views)

    /// The surfaces stop answering the pointer the instant a picture starts
    /// being taken. They are either about to leave the screen or already gone,
    /// and the rest of the gesture must not begin a second capture.
    private func markCapturePending() {
        panels.forEach { $0.overlayView.isCapturePending = true }
    }

    fileprivate func confirmRegion(_ viewRect: CGRect, on panel: ScreenshotOverlayPanel) {
        guard viewRect.width >= 1, viewRect.height >= 1 else { return }
        markCapturePending()
        Self.lastRegion = (panel.displayID, viewRect)
        let pixelRect = ScreenshotSupport.imagePixelRect(
            fromView: viewRect,
            viewSize: panel.screenFrame.size,
            imageSize: panel.frozenImageSize ?? panel.pixelSize)
        if let frozen = panel.frozenImage {
            guard let cropped = frozen.cropping(to: pixelRect) else {
                finish(.failed)
                return
            }
            finish(.captured(Capture(
                image: cropped,
                scale: panel.pixelScale,
                anchorRect: ScreenshotSupport.cocoaRect(
                    fromFlippedView: viewRect,
                    screenFrame: panel.screenFrame))))
        } else {
            captureLive(displayID: panel.displayID,
                        pixelRect: pixelRect,
                        scale: panel.pixelScale,
                        anchorRect: ScreenshotSupport.cocoaRect(
                            fromFlippedView: viewRect,
                            screenFrame: panel.screenFrame))
        }
    }

    fileprivate func confirmWindow(_ windowID: CGWindowID,
                                   frame: CGRect,
                                   on panel: ScreenshotOverlayPanel) {
        markCapturePending()
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let image = await ScreenshotCaptureEngine.captureWindow(
                windowID, scale: panel.pixelScale) else {
                self.finish(.failed)
                return
            }
            self.finish(.captured(Capture(
                image: image,
                scale: panel.pixelScale,
                anchorRect: ScreenshotSupport.cocoaRect(
                    fromFlippedView: frame,
                    screenFrame: panel.screenFrame))))
        }
    }

    private func captureFullDisplayUnderMouse() {
        guard let panel = panelUnderMouse() else { return }
        markCapturePending()
        if let frozen = panel.frozenImage {
            finish(.captured(Capture(image: frozen,
                                     scale: panel.pixelScale,
                                     anchorRect: panel.screenFrame)))
        } else {
            captureLive(displayID: panel.displayID,
                        pixelRect: nil,
                        scale: panel.pixelScale,
                        anchorRect: panel.screenFrame)
        }
    }

    private func repeatLastRegion() {
        guard let last = Self.lastRegion,
              let panel = panels.first(where: { $0.displayID == last.displayID })
        else { return }
        confirmRegion(last.viewRect, on: panel)
    }

    /// Live-mode confirmation: the panels leave the screen, the display is
    /// photographed, and only then does the session end. The brief hide is
    /// what the capture must not contain.
    private func captureLive(displayID: CGDirectDisplayID,
                             pixelRect: CGRect?,
                             scale: CGFloat,
                             anchorRect: CGRect) {
        panels.forEach { $0.orderOut(nil) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard var image = await ScreenshotCaptureEngine.captureDisplay(
                displayID, includePointer: self.includePointer)
            else {
                self.finish(.failed)
                return
            }
            if let pixelRect {
                let clamped = ScreenshotSupport.clamp(
                    pixelRect,
                    to: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                guard let cropped = image.cropping(to: clamped) else {
                    self.finish(.failed)
                    return
                }
                image = cropped
            }
            self.finish(.captured(Capture(image: image,
                                          scale: scale,
                                          anchorRect: anchorRect)))
        }
    }

    func cancel() {
        finish(.cancelled)
    }

    private func finish(_ outcome: Outcome) {
        guard !finished else { return }
        finished = true
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        // A gesture can still have events on the way, so the surfaces are made
        // inert before they leave the screen: whatever arrives after this
        // point finds nothing left to act on.
        markCapturePending()
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        NSCursor.arrow.set()
        let completion = completion
        self.completion = nil
        completion?(outcome)
    }
}

// MARK: - Panel

/// Full-screen borderless panel for one display. Never activates the app;
/// becomes key only so Esc and friends arrive.
private final class ScreenshotOverlayPanel: NSPanel {
    let screenFrame: CGRect
    let displayID: CGDirectDisplayID
    let frozenImage: CGImage?
    let pixelScale: CGFloat
    private(set) var overlayViewStorage: ScreenshotOverlayView!

    var overlayView: ScreenshotOverlayView { overlayViewStorage }

    var frozenImageSize: CGSize? {
        frozenImage.map { CGSize(width: $0.width, height: $0.height) }
    }

    /// Display size in pixels, for live-mode crop math.
    var pixelSize: CGSize {
        CGSize(width: screenFrame.width * pixelScale, height: screenFrame.height * pixelScale)
    }

    init(screen: NSScreen,
         frozenImage: CGImage?,
         windows: [ScreenshotSupport.PickableWindow],
         controller: ScreenshotSelectionController,
         strings: ScreenshotFeatureStrings) {
        screenFrame = screen.frame
        displayID = screen.displayID
        self.frozenImage = frozenImage
        pixelScale = screen.backingScaleFactor
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isReleasedWhenClosed = false
        isOpaque = frozenImage != nil
        backgroundColor = frozenImage == nil ? .clear : .black
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true

        // The frozen still sits in its own view UNDER the chrome: a backing
        // layer configured before the view joins a window can lose its
        // contents, and the chrome's dim must paint over the image anyway.
        let container = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        if let frozenImage {
            let imageView = NSImageView(frame: container.bounds)
            imageView.image = NSImage(cgImage: frozenImage, size: screen.frame.size)
            imageView.imageScaling = .scaleAxesIndependently
            imageView.autoresizingMask = [.width, .height]
            container.addSubview(imageView)
        }
        let view = ScreenshotOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size),
                                         frozenImage: frozenImage,
                                         loupeImage: frozenImage,
                                         windows: windows,
                                         controller: controller,
                                         panel: self,
                                         strings: strings)
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        overlayViewStorage = view
        contentView = container
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - View

/// Draws the frozen background, the dim, the selection, window highlights,
/// the magnifier and the hint bar; owns all mouse interaction. Flipped so
/// geometry matches image pixels (top-left origin) with no sign juggling.
private final class ScreenshotOverlayView: NSView {
    private let frozenImage: CGImage?
    private var loupeImage: CGImage?
    private let windows: [ScreenshotSupport.PickableWindow]
    /// Both are held weakly on purpose. The session hands its result over
    /// after the panels leave the screen, so the controller is already gone
    /// while the window server still delivers the tail of a gesture here.
    private weak var controller: ScreenshotSelectionController?
    private weak var panel: ScreenshotOverlayPanel?
    private let strings: ScreenshotFeatureStrings

    private var dragOrigin: CGPoint?
    private var lastDragPoint: CGPoint = .zero
    private var selection: CGRect = .zero
    private var hoverPoint: CGPoint = .zero
    private var hoveredWindow: ScreenshotSupport.PickableWindow?
    var ghostRect: CGRect?
    var isCapturePending = false {
        didSet { needsDisplay = true }
    }

    var isDragging: Bool { dragOrigin != nil }

    /// A surface whose session is over answers nothing, so the rest of a
    /// gesture can neither reach a controller that is gone nor start a second
    /// capture behind the one already running.
    private var acceptsPointerInput: Bool {
        ScreenshotSupport.selectionAcceptsPointerInput(
            sessionIsOver: controller?.isOver ?? true,
            capturePending: isCapturePending)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(frame: CGRect,
         frozenImage: CGImage?,
         loupeImage: CGImage?,
         windows: [ScreenshotSupport.PickableWindow],
         controller: ScreenshotSelectionController,
         panel: ScreenshotOverlayPanel,
         strings: ScreenshotFeatureStrings) {
        self.frozenImage = frozenImage
        self.loupeImage = loupeImage
        self.windows = windows
        self.controller = controller
        self.panel = panel
        self.strings = strings
        super.init(frame: frame)
        let tracking = NSTrackingArea(rect: .zero,
                                      options: [.activeAlways, .mouseMoved, .inVisibleRect],
                                      owner: self)
        addTrackingArea(tracking)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    func refreshPointerState() {
        guard let panel else { return }
        let point = CGPoint(x: NSEvent.mouseLocation.x - panel.screenFrame.minX,
                            y: panel.screenFrame.maxY - NSEvent.mouseLocation.y)
        if bounds.contains(point) {
            hoverPoint = point
            hoveredWindow = ScreenshotSupport.window(at: hoverPoint, in: windows)
        }
        needsDisplay = true
    }

    func updateLoupeImage(_ image: CGImage?) {
        loupeImage = image
        needsDisplay = true
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        hoverPoint = convert(event.locationInWindow, from: nil)
        hoveredWindow = ScreenshotSupport.window(at: hoverPoint, in: windows)
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard acceptsPointerInput, let controller, controller.loupeEnabled else {
            super.scrollWheel(with: event)
            return
        }
        controller.adjustLoupeZoom(by: event.scrollingDeltaY)
    }

    override func mouseDown(with event: NSEvent) {
        guard acceptsPointerInput else { return }
        let point = convert(event.locationInWindow, from: nil)
        hoverPoint = point
        dragOrigin = point
        lastDragPoint = point
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard acceptsPointerInput, let controller, let origin = dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        hoverPoint = point
        if controller.spaceIsDown, selection.width > 0 {
            // Space pans the selection instead of resizing it.
            let delta = CGPoint(x: point.x - lastDragPoint.x, y: point.y - lastDragPoint.y)
            selection.origin.x += delta.x
            selection.origin.y += delta.y
            dragOrigin = CGPoint(x: origin.x + delta.x, y: origin.y + delta.y)
        } else {
            selection = ScreenshotSupport.selectionRect(
                from: origin,
                to: point,
                square: event.modifierFlags.contains(.shift),
                fromCenter: event.modifierFlags.contains(.option))
        }
        selection = ScreenshotSupport.clamp(selection, to: bounds)
        lastDragPoint = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard acceptsPointerInput, let controller, let panel else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let origin = dragOrigin else { return }
        dragOrigin = nil
        controller.spaceIsDown = false

        let clicked = ScreenshotSupport.isClick(from: origin, to: point)
        if clicked {
            if let target = ScreenshotSupport.window(at: point, in: windows) {
                controller.confirmWindow(target.windowID, frame: target.frame, on: panel)
            }
            selection = .zero
            needsDisplay = true
            return
        }
        guard selection.width >= 2, selection.height >= 2 else {
            selection = .zero
            needsDisplay = true
            return
        }
        controller.confirmRegion(selection, on: panel)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let controller,
              let panel
        else { return }
        let mouseIsOnThisScreen = panel.screenFrame.contains(NSEvent.mouseLocation)

        let dimAlpha: CGFloat = frozenImage == nil ? 0.32 : 0.26
        context.setFillColor(CGColor(gray: 0, alpha: dimAlpha))
        if selection.width > 0, selection.height > 0 {
            context.beginPath()
            context.addRect(bounds)
            context.addRect(selection)
            context.fillPath(using: .evenOdd)
            drawSelectionChrome(context, pixelScale: panel.pixelScale)
        } else if dragOrigin == nil, hoveredWindow != nil {
            if let hovered = hoveredWindow {
                context.beginPath()
                context.addRect(bounds)
                context.addRect(hovered.frame)
                context.fillPath(using: .evenOdd)
                drawWindowHighlight(context, rect: hovered.frame)
            } else {
                context.fill(bounds)
            }
        } else {
            context.fill(bounds)
        }

        if controller.loupeEnabled, !controller.spaceIsDown,
           mouseIsOnThisScreen, let loupeImage {
            let point = isDragging ? lastDragPoint : hoverPoint
            drawCaptureLoupe(context,
                             image: loupeImage,
                             near: point,
                             zoom: controller.loupeZoom)
        }

        if let ghostRect, dragOrigin == nil, selection == .zero {
            drawGhost(context, rect: ghostRect)
        }
        if mouseIsOnThisScreen {
            drawHintBar()
        }
    }

    private func drawSelectionChrome(_ context: CGContext, pixelScale: CGFloat) {
        // Double hairline stays visible over any background.
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.85))
        context.setLineWidth(2.5)
        context.stroke(selection.insetBy(dx: -1.25, dy: -1.25))
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
        context.setLineWidth(1)
        context.stroke(selection.insetBy(dx: -0.5, dy: -0.5))

        let pixelWidth = Int((selection.width * pixelScale).rounded())
        let pixelHeight = Int((selection.height * pixelScale).rounded())
        drawBadge("\(pixelWidth) × \(pixelHeight)",
                  near: CGPoint(x: selection.midX, y: selection.maxY + 10))
    }

    private func drawWindowHighlight(_ context: CGContext, rect: CGRect) {
        context.setFillColor(CGColor(srgbRed: 0.35, green: 0.62, blue: 1, alpha: 0.14))
        context.fill(rect)
        context.setStrokeColor(CGColor(srgbRed: 0.35, green: 0.62, blue: 1, alpha: 0.95))
        context.setLineWidth(2.5)
        context.stroke(rect.insetBy(dx: 1.25, dy: 1.25))
    }

    private func drawGhost(_ context: CGContext, rect: CGRect) {
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.65))
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [5, 4])
        context.stroke(rect)
        context.restoreGState()
    }

    // MARK: Pixel loupe

    private func drawCaptureLoupe(_ context: CGContext,
                                  image: CGImage,
                                  near point: CGPoint,
                                  zoom: CGFloat) {
        let imageSize = CGSize(width: image.width, height: image.height)
        let pixelPoint = ScreenshotSupport.imagePixelPoint(
            fromView: point,
            viewSize: bounds.size,
            imageSize: imageSize)
        let source = ScreenshotSupport.cropLoupeSampleRect(
            around: pixelPoint,
            imageSize: imageSize,
            sideLength: ScreenshotSupport.captureLoupeSampleSide(zoom: zoom))
        guard let sample = image.cropping(to: source) else { return }

        let frame = captureLoupeFrame(near: point, size: 70)
        let path = CGPath(roundedRect: frame,
                          cornerWidth: 9,
                          cornerHeight: 9,
                          transform: nil)
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.interpolationQuality = .none
        // CGImage draws bottom-up inside the flipped overlay, so mirror only
        // this destination to keep the magnified pixels upright.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        let flippedFrame = CGRect(x: frame.minX,
                                  y: bounds.height - frame.maxY,
                                  width: frame.width,
                                  height: frame.height)
        context.draw(sample, in: flippedFrame)
        context.restoreGState()

        let crossX = min(max(frame.minX
            + (pixelPoint.x - source.minX) / source.width * frame.width,
                             frame.minX + 0.5), frame.maxX - 0.5)
        let crossY = min(max(frame.minY
            + (pixelPoint.y - source.minY) / source.height * frame.height,
                             frame.minY + 0.5), frame.maxY - 0.5)

        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.76))
        context.setLineWidth(3)
        context.move(to: CGPoint(x: crossX, y: frame.minY))
        context.addLine(to: CGPoint(x: crossX, y: frame.maxY))
        context.move(to: CGPoint(x: frame.minX, y: crossY))
        context.addLine(to: CGPoint(x: frame.maxX, y: crossY))
        context.strokePath()
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.92))
        context.setLineWidth(1)
        context.move(to: CGPoint(x: crossX, y: frame.minY))
        context.addLine(to: CGPoint(x: crossX, y: frame.maxY))
        context.move(to: CGPoint(x: frame.minX, y: crossY))
        context.addLine(to: CGPoint(x: frame.maxX, y: crossY))
        context.strokePath()
        context.addPath(path)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
        context.setLineWidth(1.5)
        context.strokePath()
        context.restoreGState()
    }

    private func captureLoupeFrame(near point: CGPoint, size: CGFloat) -> CGRect {
        let gap: CGFloat = 16
        let inset: CGFloat = 8
        var origin = CGPoint(x: point.x + gap,
                             y: point.y - size - gap)
        if origin.x + size > bounds.maxX - inset {
            origin.x = point.x - size - gap
        }
        if origin.y < bounds.minY + inset {
            origin.y = point.y + gap
        }
        origin.x = min(max(origin.x, bounds.minX + inset), bounds.maxX - size - inset)
        origin.y = min(max(origin.y, bounds.minY + inset), bounds.maxY - size - inset)
        return CGRect(origin: origin, size: CGSize(width: size, height: size))
    }

    // MARK: Text chrome

    private func drawBadge(_ text: String, near point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        var rect = CGRect(x: point.x - size.width / 2 - 7,
                          y: point.y - 3,
                          width: size.width + 14,
                          height: size.height + 6)
        rect.origin.x = max(6, min(rect.origin.x, bounds.maxX - rect.width - 6))
        rect.origin.y = max(6, min(rect.origin.y, bounds.maxY - rect.height - 6))
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSColor(white: 0, alpha: 0.72).setFill()
        path.fill()
        text.draw(at: CGPoint(x: rect.minX + 7, y: rect.minY + 3), withAttributes: attributes)
    }

    private func drawHintBar() {
        let parts: [String]
        if isCapturePending {
            parts = []
        } else {
            var list = [strings.hintDrag, strings.hintClick,
                        strings.hintFullScreen, strings.hintLoupe, strings.hintCancel]
            if ghostRect != nil { list.append(strings.hintRepeat) }
            parts = list
        }
        guard !parts.isEmpty else { return }
        let text = parts.joined(separator: "   ·   ")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        ]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(x: bounds.midX - size.width / 2 - 16,
                          y: bounds.maxY - 54,
                          width: size.width + 32,
                          height: size.height + 12)
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        NSColor(white: 0, alpha: 0.66).setFill()
        path.fill()
        text.draw(at: CGPoint(x: rect.minX + 16, y: rect.minY + 6), withAttributes: attributes)
    }
}
