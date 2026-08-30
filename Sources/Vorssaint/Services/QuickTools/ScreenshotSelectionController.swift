// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The capture surface: one borderless panel per screen, above everything,
/// where the user drags a region, clicks a window or confirms a full screen.
///
/// With freeze on (the default) every display is photographed first and the
/// panels show that still image while the area is chosen. With freeze off the
/// panels are transparent and pixels are captured at confirmation time.
///
/// More than one feature picks an area this way, so the surface says what the
/// area is for and only one session is ever on screen.
final class ScreenshotSelectionController {

    struct Capture {
        let image: CGImage
        /// Pixels per point of the source display, for 1x export math.
        let scale: CGFloat
        /// The captured area in Cocoa global coordinates.
        let anchorRect: CGRect
    }

    /// What the caller wants out of the same gesture. The screenshot tool
    /// wants pixels; the recorder wants to know WHERE, and takes its own
    /// pixels afterwards, for as long as the person keeps recording.
    enum Mode {
        case image
        case geometry
        case color
    }

    enum Outcome {
        case captured(Capture)
        case region(RecorderSupport.Region)
        case scrollingRegion(RecorderSupport.Region)
        case color(NSColor)
        case cancelled
        case failed
    }

    private var panels: [ScreenshotOverlayPanel] = []

    var protectedWindowIDs: Set<CGWindowID> {
        Set(panels.compactMap { $0.windowNumber > 0 ? CGWindowID($0.windowNumber) : nil })
    }

    /// The overlays are part of the capture, so they stay excluded even when
    /// the session is not registered anywhere yet.
    private var captureExcludedWindowIDs: Set<CGWindowID> {
        otherProtectedWindowIDs().union(protectedWindowIDs)
    }
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var completion: ((Outcome) -> Void)?
    private let freeze: Bool
    private let includePointer: Bool
    private let showLastRegion: Bool
    private let hideVorssaintWindows: Bool
    private let otherProtectedWindowIDs: () -> Set<CGWindowID>
    private let baseMode: Mode
    private let supportsScrollingCapture: Bool
    private let screenCaptureOptions: ScreenCaptureSelectionOptions?
    fileprivate let requiresDraggedRegion: Bool
    private var finished = false
    /// Read by the overlays so a late event finds a session that is over.
    fileprivate var isOver: Bool { finished }
    fileprivate var spaceIsDown = false
    fileprivate var selectionInProgress = false {
        didSet { panels.forEach { $0.overlayView.refreshGuideVisibility() } }
    }
    fileprivate var scrollingCaptureEnabled = false {
        didSet {
            panels.forEach {
                $0.overlayView.refreshCaptureGuide()
                $0.overlayView.needsDisplay = true
            }
        }
    }
    fileprivate var offersScrollingCapture: Bool {
        supportsScrollingCapture && activeTool == .screenshot && activeMode == .image
    }
    fileprivate var acceptsWindowClick: Bool {
        activeMode != .color && !requiresDraggedRegion && !scrollingCaptureEnabled
    }
    fileprivate var isPickingColor: Bool { activeMode == .color }
    fileprivate var loupeEnabled = false {
        didSet { panels.forEach { $0.overlayView.refreshPointerState() } }
    }
    fileprivate var loupeZoom: CGFloat = 1 {
        didSet { panels.forEach { $0.overlayView.needsDisplay = true } }
    }

    /// The last confirmed region, per display, so R repeats it instantly.
    private static var lastRegion: (displayID: CGDirectDisplayID, viewRect: CGRect)?

    /// True while a session owns the screen. Two surfaces at once would stack
    /// dim over dim and split the keyboard between them, so whichever feature
    /// asks second is turned away.
    private(set) static var isSessionOnScreen = false

    private let strings = FeatureStrings.screenshot(L10n.shared.language)
    /// Named at the head of the hint bar so the surface never leaves the
    /// person guessing what the area they are about to pick is for.
    private let purpose: String?

    init(freeze: Bool,
         includePointer: Bool,
         showLastRegion: Bool,
         hideVorssaintWindows: Bool = true,
         protectedWindowIDs: @escaping () -> Set<CGWindowID> = { [] },
         purpose: String? = nil,
         mode: Mode = .image,
         supportsScrollingCapture: Bool = false,
         requiresDraggedRegion: Bool = false,
         screenCaptureOptions: ScreenCaptureSelectionOptions? = nil) {
        self.freeze = freeze
        self.includePointer = includePointer
        self.showLastRegion = showLastRegion
        self.hideVorssaintWindows = hideVorssaintWindows
        self.otherProtectedWindowIDs = protectedWindowIDs
        self.purpose = purpose
        self.baseMode = mode
        self.supportsScrollingCapture = supportsScrollingCapture
        self.requiresDraggedRegion = requiresDraggedRegion
        self.screenCaptureOptions = screenCaptureOptions
    }

    private var activeTool: ScreenCaptureTool? { screenCaptureOptions?.selectedTool }

    private var activeMode: Mode {
        switch activeTool {
        case .recording: return .geometry
        case .color: return .color
        case .screenshot, .text: return .image
        case .none: return baseMode
        }
    }

    func begin(completion: @escaping (Outcome) -> Void) {
        Self.isSessionOnScreen = true
        self.completion = completion
        screenCaptureOptions?.onSelectionChange = { [weak self] in
            self?.screenCaptureToolDidChange()
        }
        if freeze {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let images = await ScreenshotCaptureEngine.captureAllDisplays(
                    includePointer: self.includePointer,
                    hideVorssaintWindows: self.hideVorssaintWindows,
                    protectedWindowIDs: self.captureExcludedWindowIDs)
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
        let pickable = ScreenshotCaptureEngine.pickableWindows(
            hideVorssaintWindows: hideVorssaintWindows,
            protectedWindowIDs: captureExcludedWindowIDs)
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
                                               strings: strings,
                                               purpose: purpose,
                                               screenCaptureOptions: screenCaptureOptions)
            if showLastRegion, let last = Self.lastRegion, last.displayID == displayID {
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
        if isPickingColor { loupeEnabled = true }
        NSCursor.crosshair.set()
    }

    private func screenCaptureToolDidChange() {
        scrollingCaptureEnabled = false
        loupeEnabled = isPickingColor
        if isPickingColor, !freeze { loadLiveLoupeImages() }
        panels.forEach { $0.overlayView.captureToolDidChange() }
        if selectionInProgress { selectionInProgress = false }
    }

    /// Live selection stays transparent, but the loupe still needs source
    /// pixels. Capture them once after the overlays exist; ScreenCaptureKit
    /// excludes this app's own panels, so the screen itself remains live.
    private func loadLiveLoupeImages() {
        let hideWindows = hideVorssaintWindows
        let excludedIDs = captureExcludedWindowIDs
        Task { @MainActor [weak self] in
            let images = await ScreenshotCaptureEngine.captureAllDisplays(
                includePointer: false,
                hideVorssaintWindows: hideWindows,
                protectedWindowIDs: excludedIDs)
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
                if self.acceptsWindowClick {
                    self.captureFullDisplayUnderMouse()
                }
            case kVK_Space:
                if let panel = self.panelUnderMouse(), panel.overlayView.isDragging {
                    // Holding Space moves the in-progress selection.
                    self.spaceIsDown = true
                }
            case kVK_ANSI_R:
                self.repeatLastRegion()
            case _ where self.selectCaptureTool(for: event):
                break
            case _ where Self.isScrollingCaptureKey(event):
                self.toggleScrollingCapture()
            case _ where Self.isLoupeKey(event):
                self.toggleLoupe()
            default:
                break
            }
            return nil
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            self?.finish(.cancelled)
        }
    }

    private func selectCaptureTool(for event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let tool = ScreenCaptureTool.matchingShortcut(event.charactersIgnoringModifiers),
              let screenCaptureOptions,
              screenCaptureOptions.availableTools.contains(tool)
        else { return false }
        screenCaptureOptions.select(tool)
        return true
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

    private static func isScrollingCaptureKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        else { return false }
        if let typed = event.charactersIgnoringModifiers?.lowercased(), !typed.isEmpty {
            return typed == "s"
        }
        return Int(event.keyCode) == kVK_ANSI_S
    }

    private func toggleScrollingCapture() {
        guard offersScrollingCapture else { return }
        scrollingCaptureEnabled.toggle()
        panels.forEach { $0.overlayView.refreshPointerState() }
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

    /// The picked area as the recorder needs it: whole even pixels of the
    /// source display, plus the same area in Cocoa points so a panel can be
    /// anchored to it. The point rectangle is derived from the SNAPPED pixels,
    /// so what gets recorded and what the person was shown never disagree.
    private func region(fromView viewRect: CGRect,
                        on panel: ScreenshotOverlayPanel,
                        windowID: CGWindowID?) -> RecorderSupport.Region {
        let displayPixels = CGRect(origin: .zero, size: panel.pixelSize)
        let raw = ScreenshotSupport.imagePixelRect(fromView: viewRect,
                                                   viewSize: panel.screenFrame.size,
                                                   imageSize: panel.pixelSize)
        let snapped = RecorderSupport.snappedPixelRect(raw, in: displayPixels)
        let scale = panel.pixelScale > 0 ? panel.pixelScale : 1
        let snappedView = CGRect(x: snapped.origin.x / scale,
                                 y: snapped.origin.y / scale,
                                 width: snapped.width / scale,
                                 height: snapped.height / scale)
        return RecorderSupport.Region(
            displayID: panel.displayID,
            windowID: windowID,
            pixelRect: snapped,
            anchorRect: ScreenshotSupport.cocoaRect(fromFlippedView: snappedView,
                                                    screenFrame: panel.screenFrame),
            scale: scale)
    }

    fileprivate func confirmRegion(_ viewRect: CGRect, on panel: ScreenshotOverlayPanel) {
        guard viewRect.width >= 1, viewRect.height >= 1 else { return }
        guard activeMode != .color else { return }
        markCapturePending()
        Self.lastRegion = (panel.displayID, viewRect)
        if activeMode == .geometry {
            finish(.region(region(fromView: viewRect, on: panel, windowID: nil)))
            return
        }
        if scrollingCaptureEnabled {
            finish(.scrollingRegion(region(fromView: viewRect, on: panel, windowID: nil)))
            return
        }
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
        guard activeMode != .color else { return }
        markCapturePending()
        if activeMode == .geometry {
            finish(.region(region(fromView: frame, on: panel, windowID: windowID)))
            return
        }
        if scrollingCaptureEnabled {
            finish(.scrollingRegion(region(fromView: frame, on: panel, windowID: windowID)))
            return
        }
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
        guard activeMode != .color else { return }
        guard let panel = panelUnderMouse() else { return }
        markCapturePending()
        if activeMode == .geometry {
            let whole = CGRect(origin: .zero, size: panel.screenFrame.size)
            finish(.region(region(fromView: whole, on: panel, windowID: nil)))
            return
        }
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
        guard activeMode != .color else { return }
        guard let last = Self.lastRegion,
              let panel = panels.first(where: { $0.displayID == last.displayID })
        else { return }
        confirmRegion(last.viewRect, on: panel)
    }

    fileprivate func confirmColor(at viewPoint: CGPoint, on panel: ScreenshotOverlayPanel) {
        guard activeMode == .color,
              let image = panel.frozenImage ?? panel.overlayView.loupeImage else { return }
        let point = ScreenshotSupport.imagePixelPoint(
            fromView: viewPoint,
            viewSize: panel.screenFrame.size,
            imageSize: CGSize(width: image.width, height: image.height))
        let x = min(max(Int(point.x.rounded(.down)), 0), image.width - 1)
        let y = min(max(Int(point.y.rounded(.down)), 0), image.height - 1)
        guard let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let color = NSBitmapImageRep(cgImage: pixel).colorAt(x: 0, y: 0)
        else {
            finish(.failed)
            return
        }
        markCapturePending()
        finish(.color(color))
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
                displayID,
                includePointer: self.includePointer,
                hideVorssaintWindows: self.hideVorssaintWindows,
                protectedWindowIDs: self.captureExcludedWindowIDs)
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

    deinit {
        // A session that goes away without ending would otherwise leave the
        // screen marked as taken and every capture feature dead until the app
        // is restarted. The wrong flag is always the one that lets a capture
        // start, never the one that blocks it.
        if !finished { Self.isSessionOnScreen = false }
    }

    private func finish(_ outcome: Outcome) {
        guard !finished else { return }
        finished = true
        Self.isSessionOnScreen = false
        screenCaptureOptions?.onSelectionChange = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
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
         strings: ScreenshotFeatureStrings,
         purpose: String?,
         screenCaptureOptions: ScreenCaptureSelectionOptions?) {
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
                                         strings: strings,
                                         purpose: purpose,
                                         screenCaptureOptions: screenCaptureOptions)
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        overlayViewStorage = view
        contentView = container
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - View

/// Draws the frozen background, the dim, the selection, window highlights
/// and the magnifier; owns all mouse interaction. Flipped so
/// geometry matches image pixels (top-left origin) with no sign juggling.
private final class ScreenshotOverlayView: NSView {
    private let frozenImage: CGImage?
    fileprivate var loupeImage: CGImage?
    private let windows: [ScreenshotSupport.PickableWindow]
    /// Both are held weakly on purpose. The session hands its result over
    /// after the panels leave the screen, so the controller is already gone
    /// while the window server still delivers the tail of a gesture here.
    private weak var controller: ScreenshotSelectionController?
    private weak var panel: ScreenshotOverlayPanel?
    private let strings: ScreenshotFeatureStrings
    private let purpose: String?
    private let screenCaptureOptions: ScreenCaptureSelectionOptions?
    private let guideHost: PassThroughHostingView<CaptureGuideView>

    private var dragOrigin: CGPoint?
    private var lastDragPoint: CGPoint = .zero
    private var selection: CGRect = .zero
    private var hoverPoint: CGPoint = .zero
    private var hoveredWindow: ScreenshotSupport.PickableWindow?
    var ghostRect: CGRect?
    var isCapturePending = false {
        didSet {
            refreshGuideVisibility()
            needsDisplay = true
        }
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
         strings: ScreenshotFeatureStrings,
         purpose: String?,
         screenCaptureOptions: ScreenCaptureSelectionOptions?) {
        self.frozenImage = frozenImage
        self.loupeImage = loupeImage
        self.windows = windows
        self.controller = controller
        self.panel = panel
        self.strings = strings
        self.purpose = purpose
        self.screenCaptureOptions = screenCaptureOptions
        let host = PassThroughHostingView(rootView: CaptureGuideView(
            strings: strings,
            purpose: purpose,
            offersScrollingCapture: controller.offersScrollingCapture,
            requiresDraggedRegion: controller.requiresDraggedRegion,
            scrollingCaptureEnabled: controller.scrollingCaptureEnabled,
            screenCaptureOptions: screenCaptureOptions))
        host.passesThrough = screenCaptureOptions == nil
        guideHost = host
        super.init(frame: frame)
        let tracking = NSTrackingArea(rect: .zero,
                                      options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited,
                                                .inVisibleRect],
                                      owner: self)
        addTrackingArea(tracking)
        addSubview(guideHost)
        refreshGuideVisibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func layout() {
        super.layout()
        let width = min(screenCaptureOptions == nil ? 680 : 620,
                        max(280, bounds.width - 32))
        let height: CGFloat = screenCaptureOptions != nil
            ? 146
            : 72
        guideHost.frame = CGRect(x: bounds.midX - width / 2,
                                 y: bounds.maxY - height - 32,
                                 width: width,
                                 height: height)
    }

    func refreshPointerState() {
        guard let panel else { return }
        let point = CGPoint(x: NSEvent.mouseLocation.x - panel.screenFrame.minX,
                            y: panel.screenFrame.maxY - NSEvent.mouseLocation.y)
        if bounds.contains(point) {
            hoverPoint = point
            hoveredWindow = controller?.acceptsWindowClick == true
                ? ScreenshotSupport.window(at: hoverPoint, in: windows)
                : nil
        }
        needsDisplay = true
    }

    func updateLoupeImage(_ image: CGImage?) {
        loupeImage = image
        needsDisplay = true
    }

    func refreshCaptureGuide() {
        guideHost.rootView = CaptureGuideView(
            strings: strings,
            purpose: purpose,
            offersScrollingCapture: controller?.offersScrollingCapture ?? false,
            requiresDraggedRegion: controller?.requiresDraggedRegion ?? false,
            scrollingCaptureEnabled: controller?.scrollingCaptureEnabled ?? false,
            screenCaptureOptions: screenCaptureOptions)
    }

    func captureToolDidChange() {
        dragOrigin = nil
        selection = .zero
        hoveredWindow = nil
        refreshGuideVisibility()
        refreshCaptureGuide()
        needsLayout = true
        needsDisplay = true
        refreshPointerState()
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        hoverPoint = convert(event.locationInWindow, from: nil)
        hoveredWindow = controller?.acceptsWindowClick == true
            ? ScreenshotSupport.window(at: hoverPoint, in: windows)
            : nil
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        refreshGuideVisibility()
    }

    // System chrome can take pointer ownership without the pointer leaving
    // this display. Re-evaluate the real location so the chooser does not
    // disappear over the Dock, menu bar or its own interactive controls.
    override func mouseExited(with event: NSEvent) {
        refreshGuideVisibility()
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
        controller?.selectionInProgress = true
        lastDragPoint = point
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard acceptsPointerInput, let controller, let origin = dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        hoverPoint = point
        if controller.isPickingColor {
            lastDragPoint = point
            needsDisplay = true
            return
        }
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

        if controller.isPickingColor {
            selection = .zero
            controller.confirmColor(at: point, on: panel)
            return
        }

        let clicked = ScreenshotSupport.isClick(from: origin, to: point)
        if clicked {
            if controller.acceptsWindowClick,
               let target = ScreenshotSupport.window(at: point, in: windows) {
                controller.confirmWindow(target.windowID, frame: target.frame, on: panel)
            }
            selection = .zero
            needsDisplay = true
            controller.selectionInProgress = false
            return
        }
        guard selection.width >= 2, selection.height >= 2 else {
            selection = .zero
            controller.selectionInProgress = false
            needsDisplay = true
            return
        }
        controller.confirmRegion(selection, on: panel)
    }

    func refreshGuideVisibility() {
        guard let panel else {
            guideHost.isHidden = true
            return
        }
        guideHost.isHidden = !ScreenshotSupport.captureGuideIsVisible(
            pointerOnDisplay: panel.screenFrame.contains(NSEvent.mouseLocation),
            selectionInProgress: controller?.selectionInProgress ?? true,
            capturePending: isCapturePending)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let controller,
              let panel
        else { return }
        let mouseIsOnThisScreen = panel.screenFrame.contains(NSEvent.mouseLocation)

        let dimAlpha: CGFloat = frozenImage == nil ? 0.18 : 0.22
        context.setFillColor(CGColor(gray: 0, alpha: dimAlpha))
        if selection.width > 0, selection.height > 0 {
            context.beginPath()
            context.addRect(bounds)
            context.addPath(CGPath(roundedRect: selection,
                                   cornerWidth: 8,
                                   cornerHeight: 8,
                                   transform: nil))
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
    }

    private func drawSelectionChrome(_ context: CGContext, pixelScale: CGFloat) {
        let outer = CGPath(roundedRect: selection.insetBy(dx: -1.5, dy: -1.5),
                           cornerWidth: 9,
                           cornerHeight: 9,
                           transform: nil)
        let inner = CGPath(roundedRect: selection.insetBy(dx: -0.5, dy: -0.5),
                           cornerWidth: 8,
                           cornerHeight: 8,
                           transform: nil)
        context.saveGState()
        context.setShadow(offset: .zero,
                          blur: 9,
                          color: CGColor(srgbRed: 0.18, green: 0.55, blue: 1, alpha: 0.55))
        context.addPath(outer)
        context.setStrokeColor(CGColor(srgbRed: 0.18, green: 0.55, blue: 1, alpha: 0.98))
        context.setLineWidth(3)
        context.strokePath()
        context.restoreGState()
        context.addPath(inner)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
        context.setLineWidth(1)
        context.strokePath()

        let pixelWidth = Int((selection.width * pixelScale).rounded())
        let pixelHeight = Int((selection.height * pixelScale).rounded())
        drawBadge("\(pixelWidth) × \(pixelHeight)",
                  near: CGPoint(x: selection.midX, y: selection.maxY + 10))
    }

    private func drawWindowHighlight(_ context: CGContext, rect: CGRect) {
        let path = CGPath(roundedRect: rect.insetBy(dx: 1.25, dy: 1.25),
                          cornerWidth: 9,
                          cornerHeight: 9,
                          transform: nil)
        context.addPath(path)
        context.setFillColor(CGColor(srgbRed: 0.35, green: 0.62, blue: 1, alpha: 0.14))
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(CGColor(srgbRed: 0.35, green: 0.62, blue: 1, alpha: 0.95))
        context.setLineWidth(2.5)
        context.strokePath()
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

        // A ring around the target pixel rather than lines through it: the
        // frame shows about a dozen source pixels, so a 3pt crosshair on the
        // pointer's sub-pixel position buried the very pixel the color picker
        // is about to copy (issue #755). The ring sits just outside the pixel
        // so the sample keeps its own color.
        let target = ScreenshotSupport.captureLoupeTargetPixelRect(
            around: pixelPoint,
            source: source,
            frame: frame)
        let ring = target.insetBy(dx: -1, dy: -1)
        let reticle = CGMutablePath()
        reticle.addRect(ring)
        // Arms still carry the eye in from the frame edges, which is what the
        // selection tools aim with, and stop before they reach the pixel.
        let arms = [
            (CGPoint(x: ring.midX, y: frame.minY), CGPoint(x: ring.midX, y: ring.minY)),
            (CGPoint(x: ring.midX, y: ring.maxY), CGPoint(x: ring.midX, y: frame.maxY)),
            (CGPoint(x: frame.minX, y: ring.midY), CGPoint(x: ring.minX, y: ring.midY)),
            (CGPoint(x: ring.maxX, y: ring.midY), CGPoint(x: frame.maxX, y: ring.midY)),
        ]
        for (start, end) in arms where end.x > start.x || end.y > start.y {
            reticle.move(to: start)
            reticle.addLine(to: end)
        }

        context.saveGState()
        context.addPath(reticle)
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.76))
        context.setLineWidth(3)
        context.strokePath()
        context.addPath(reticle)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.92))
        context.setLineWidth(1)
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

}

private final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var passesThrough = true
    override func hitTest(_ point: NSPoint) -> NSView? {
        passesThrough ? nil : super.hitTest(point)
    }
}

private struct CaptureGuideView: View {
    let strings: ScreenshotFeatureStrings
    let purpose: String?
    let offersScrollingCapture: Bool
    let requiresDraggedRegion: Bool
    let scrollingCaptureEnabled: Bool
    let screenCaptureOptions: ScreenCaptureSelectionOptions?

    var body: some View {
        if let screenCaptureOptions {
            UnifiedCaptureGuideContent(strings: strings,
                                       options: screenCaptureOptions,
                                       offersScrollingCapture: offersScrollingCapture,
                                       scrollingCaptureEnabled: scrollingCaptureEnabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(true)
        } else {
            standardGuide
        }
    }

    private var standardGuide: some View {
        HStack(spacing: 12) {
            Image(systemName: "viewfinder")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                if !requiresDraggedRegion && !scrollingCaptureEnabled {
                    CaptureKeyHint(key: "↩", icon: "rectangle.inset.filled")
                }
                if offersScrollingCapture {
                    CaptureKeyHint(key: scrollingCaptureEnabled ? "S on" : "S",
                                   icon: "rectangle.stack")
                }
                CaptureKeyHint(key: "Z", icon: "plus.magnifyingglass")
                CaptureKeyHint(key: "esc", icon: "xmark")
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 7)
        .allowsHitTesting(false)
    }

    private var title: String {
        guard let purpose, !purpose.isEmpty else { return strings.hintDrag }
        return purpose
    }

    private var subtitle: String {
        let base = requiresDraggedRegion || scrollingCaptureEnabled
            ? strings.scrollingCaptureSelectionHint
            : purpose?.isEmpty == false
            ? strings.hintDrag + "  ·  " + strings.hintClick
            : strings.hintClick
        guard offersScrollingCapture else { return base }
        let scrolling = scrollingCaptureEnabled
            ? strings.scrollingCaptureHintOn
            : strings.scrollingCaptureHintOff
        return base + "  ·  " + scrolling
    }

}

private struct UnifiedCaptureGuideContent: View {
    let strings: ScreenshotFeatureStrings
    @ObservedObject var options: ScreenCaptureSelectionOptions
    @ObservedObject private var l10n = L10n.shared
    let offersScrollingCapture: Bool
    let scrollingCaptureEnabled: Bool
    @State private var hoveredTool: ScreenCaptureTool?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                captureModePalette
                escapeHint
            }
            contextualGuide
            RecorderSelectionAudioControls(options: options.recorderAudio)
                .opacity(options.selectedTool == .recording ? 1 : 0)
                .allowsHitTesting(options.selectedTool == .recording)
                .accessibilityHidden(options.selectedTool != .recording)
        }
    }

    private var contextualGuide: some View {
        HStack(spacing: 7) {
            Text(subtitle)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            CaptureKeyHint(key: "1–4", icon: "keyboard")
            if options.selectedTool != .color {
                CaptureKeyHint(key: "↩", icon: "rectangle.inset.filled")
                if offersScrollingCapture, options.selectedTool == .screenshot {
                    CaptureKeyHint(key: scrollingCaptureEnabled ? "S on" : "S",
                                   icon: "rectangle.stack")
                }
                CaptureKeyHint(key: "Z", icon: "plus.magnifyingglass")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }

    private var escapeHint: some View {
        HStack(spacing: 5) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
            Text("esc")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 56)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }

    private var captureModePalette: some View {
        HStack(spacing: 2) {
            ForEach(options.availableTools, id: \.self) { tool in
                captureModeButton(tool)
            }
        }
        .padding(4)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }

    private func captureModeButton(_ tool: ScreenCaptureTool) -> some View {
        let selected = options.selectedTool == tool
        let hovered = hoveredTool == tool
        let title = tool.settingsTitle(l10n.s, language: l10n.language)
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                options.select(tool)
            }
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Text(tool.shortcutKey)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .frame(width: 19, height: 19)
                        .background(selected ? Color.accentColor : Color.primary.opacity(0.11),
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Image(systemName: tool.systemImageName)
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                Text(title)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.78))
            .frame(width: 116, height: 48)
            .background(selected ? Color.accentColor.opacity(0.16)
                        : Color.primary.opacity(hovered ? 0.08 : 0.035),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(selected ? 0.48 : 0), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredTool = hovering ? tool : nil
            }
        }
        .help("\(title) (\(tool.shortcutKey))")
        .accessibilityLabel(title)
        .accessibilityValue(tool.shortcutKey)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var subtitle: String {
        switch options.selectedTool {
        case .screenshot:
            let base = strings.hintDrag + "  ·  " + strings.hintClick
            guard offersScrollingCapture else { return base }
            return base + "  ·  "
                + (scrollingCaptureEnabled
                   ? strings.scrollingCaptureHintOn
                   : strings.scrollingCaptureHintOff)
        case .recording:
            return FeatureStrings.recorder(l10n.language).selectionPurpose
                + "  ·  " + strings.hintDrag + "  ·  " + strings.hintClick
        case .text:
            return l10n.s.ocrCaption
        case .color:
            return l10n.s.colorPickerCaption
        }
    }
}

private struct CaptureKeyHint: View {
    let key: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct RecorderSelectionAudioControls: View {
    @ObservedObject var options: RecorderSelectionAudioOptions
    @ObservedObject private var l10n = L10n.shared

    private var strings: RecorderFeatureStrings { FeatureStrings.recorder(l10n.language) }

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $options.systemAudio) {
                Label(strings.systemAudioTrackLabel, systemImage: "speaker.wave.2.fill")
            }
            Toggle(isOn: $options.microphone) {
                Label(strings.microphoneTrackLabel, systemImage: "mic.fill")
            }
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(4)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }
}
