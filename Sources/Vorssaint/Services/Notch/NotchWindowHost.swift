// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import QuartzCore

struct NotchFileDropActions {
    let canAccept: (NSPasteboard) -> Bool
    let enter: (NSPasteboard) -> Void
    let accept: (NSPasteboard) -> Bool
    let exit: () -> Void
    var update: ((CGPoint) -> Bool)? = nil
}

enum NotchContentTransition { case none, reveal, dismiss, replace }

/// The window reserves the transition's bounds once. Core Animation moves
/// the silhouette independently of SwiftUI layout and the application run loop.
final class NotchWindowHost: NSObject, CAAnimationDelegate {
    let panel: NotchPanel
    private let canvas: NotchCanvas
    private let quickAccessContainer: NotchQuickAccessContainer?
    private var quickAccessConfiguration: NotchQuickAccessConfiguration?
    private var quickAccessNotchSize = CGSize.zero
    private var quickAccessAnimate = false
    private var currentGeometry: NotchGeometry
    private var appliedFrame = CGRect.zero
    private var animationGeneration = 0
    private var isAnimating = false
    private var hidesWhenSettled = false
    private var targetUsesGlass = false
    private var mouseEventsBeforeHide: Bool?
    private var frameProbe: NotchFrameProbe?
    private let overlaySpace = NotchOverlaySpace()
    private var concealedForFrameChange = false
    private var restoresKeyAfterFrameChange = false
    private var settledActions: [() -> Void] = []
    private(set) var targetSize: CGSize
    private(set) var resizeCount = 0
    private(set) var concealedFrameChanges = 0

    init(content: AnyView, geometry: NotchGeometry, size: CGSize,
         background: (NotchBackdropPresentation) -> AnyView = { _ in AnyView(Color.black) },
         quickAccess: ((NotchQuickAccessMotion) -> AnyView)? = nil) {
        targetSize = size
        currentGeometry = geometry
        panel = NotchPanel(contentRect: geometry.frame(for: size),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        let mainCanvas = NotchCanvas(content: content, background: background, size: size)
        canvas = mainCanvas
        quickAccessContainer = quickAccess.map { NotchQuickAccessContainer(canvas: mainCanvas, content: $0) }
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = NotchPanel.normalLevel
        // Stationary keeps the island in place when the desktop is revealed,
        // where files are dragged onto it; a transient overlay is swept away
        // with the windows. The two behaviors are mutually exclusive, and the
        // stationary one also slides with the desktop between Spaces; the
        // island's own Space, joined before it first shows, holds it in place.
        panel.collectionBehavior = NotchPanel.overlayCollectionBehavior
        panel.contentView = quickAccessContainer ?? canvas
        canvas.layoutSubtreeIfNeeded()
        appliedFrame = panel.frame
        overlaySpace?.add(panel)
    }

    /// Visible, or ordered out for the few milliseconds of a concealed frame change.
    private var isPresented: Bool { panel.isVisible || concealedForFrameChange }

    func hide(animated: Bool) {
        guard isPresented else { return }
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !hidesWhenSettled || !animate else { return }
        present(size: CGSize(width: currentGeometry.collapsed.width, height: 0), geometry: currentGeometry,
                animated: animate, transitionContent: .dismiss, hideWhenSettled: true)
    }

    func present(size: CGSize, geometry: NotchGeometry, animated: Bool, transitionContent: NotchContentTransition = .none,
                 quickAccess: NotchQuickAccessConfiguration? = nil, revealFromHidden: Bool = false,
                 hideWhenSettled: Bool = false, usesGlass: Bool = false) {
        hidesWhenSettled = hideWhenSettled
        if hideWhenSettled {
            if mouseEventsBeforeHide == nil { mouseEventsBeforeHide = panel.ignoresMouseEvents }
            // The departing surface must already release the menu bar below it.
            panel.ignoresMouseEvents = true
        } else if let previous = mouseEventsBeforeHide {
            panel.ignoresMouseEvents = previous
            mouseEventsBeforeHide = nil
        }
        canvas.updateContrast()
        let revealing = revealFromHidden && !isPresented
        if isPresented || revealing {
            // Settle the probe on screen ahead of its first reading: a window
            // ordered in and sized in one flush has no previous bounds to animate from.
            let probe = frameProbe ?? NotchFrameProbe(collectionBehavior: panel.collectionBehavior)
            frameProbe = probe
            probe.attach(level: panel.level, screen: geometry.screen)
        }
        let canAnimate = animated && (isPresented || revealing) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let previousGutter = quickAccessConfiguration == nil ? 0 : NotchQuickAccessLayout.gutter
        let previousBottom = quickAccessBottomInset(for: targetSize, geometry: currentGeometry)
        let previousFrame = currentGeometry.frame(for: CGSize(width: targetSize.width + previousGutter * 2, height: targetSize.height + previousBottom))
        let withdrawing = !revealing && quickAccessConfiguration != nil && quickAccess == nil
        if revealing { quickAccessContainer?.motion.setVisible(false, animated: false) }
        quickAccessConfiguration = quickAccessContainer == nil ? nil : quickAccess
        quickAccessAnimate = canAnimate
        if quickAccessConfiguration != nil { quickAccessNotchSize = size }
        if withdrawing { quickAccessContainer?.motion.setVisible(false, animated: canAnimate) }
        let gutter = quickAccessConfiguration == nil ? 0 : NotchQuickAccessLayout.gutter
        let bottom = quickAccessBottomInset(for: size, geometry: geometry)
        let frame = geometry.frame(for: CGSize(width: size.width + gutter * 2, height: size.height + bottom))
        let changesFrame = revealing || (hideWhenSettled && !canAnimate) || size != targetSize
            || frame != previousFrame || (!isAnimating && panel.frame != appliedFrame)
        targetUsesGlass = usesGlass
        if canAnimate && changesFrame && (usesGlass || canvas.usesGlass) {
            // Glass closing into a black strip darkens on the way there, so the
            // material swap on arrival changes nothing on screen; opening out of
            // one lets the glass in gradually.
            let start = revealing ? 0 : canvas.visiblePath?.boundingBoxOfPath.height ?? targetSize.height
            canvas.backdropPresentation.planFade(from: start, to: size.height, endsInGlass: usesGlass)
        }
        // A shape still moving keeps its glass until it settles, even when an
        // unanimated refresh lands meanwhile: a click in Settings closes the
        // island and the option it changes syncs preferences mid-close.
        canvas.setUsesGlass(usesGlass || (((canAnimate && changesFrame) || isAnimating) && canvas.usesGlass))
        guard changesFrame || transitionContent != .none else {
            currentGeometry = geometry
            configureQuickAccess()
            if !isAnimating { quickAccessContainer?.motion.setVisible(quickAccessConfiguration != nil, animated: canAnimate) }
            return
        }
        if canAnimate { canvas.transitionContent(revealing ? .reveal : transitionContent) }
        else { canvas.restoreContent() }
        guard changesFrame else { configureQuickAccess(); return }
        // An ordered-out panel still has its last expanded shape. Start the
        // reveal at the screen edge, even when reopening at that same size.
        let previousWidth = revealing ? geometry.collapsed.width : canvas.bounds.width
        let previousPath = revealing
            ? NotchShape(attached: true, radius: 0)
                .path(in: CGRect(x: 0, y: 0, width: previousWidth, height: 0)).cgPath
            : canvas.visiblePath
        let sameScreen = geometry.screen == currentGeometry.screen
        animationGeneration += 1
        let generation = animationGeneration
        targetSize = size
        currentGeometry = geometry
        resizeCount += 1
        guard canAnimate, sameScreen || revealing, let previousPath else {
            settle()
            return
        }

        let envelope = NotchMotion.envelope(from: revealing ? previousPath.boundingBoxOfPath.size : canvas.bounds.size, to: size)
        let reservedGutter = max(quickAccessContainer?.gutter ?? 0, gutter)
        let reservedBottom = max(quickAccessContainer?.bottomInset ?? 0, bottom)
        // The probe flushes the layer tree; the departing animation stays
        // installed until then, so no frame shows its bare model path.
        let concealed = concealForFrameChange(to: reservedFrame(mainSize: envelope, gutter: reservedGutter, bottom: reservedBottom),
                                              generation: generation)
        defer { if concealed { reinstateAfterFrameChange() } }
        guard generation == animationGeneration else { return }
        isAnimating = false
        canvas.stopMotion()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.setContentSize(size)
        setFrame(mainSize: envelope, gutter: reservedGutter, bottom: reservedBottom)
        // Updating the hosting view can synchronously report a newer content
        // size. Only the latest request may install an animation or settle it.
        guard generation == animationGeneration else { CATransaction.commit(); return }
        configureQuickAccess()
        canvas.layoutSubtreeIfNeeded()
        guard generation == animationGeneration else { CATransaction.commit(); return }
        var translation = CGAffineTransform(translationX: (envelope.width - previousWidth) / 2, y: 0)
        let from = previousPath.copy(using: &translation)
        let duration = NotchMotion.duration(from: previousPath.boundingBoxOfPath.size, to: size)
        if quickAccessConfiguration != nil {
            quickAccessContainer?.motion.setVisible(true, animated: canAnimate, delay: duration)
        }
        let animation = CASpringAnimation(perceptualDuration: duration, bounce: 0)
        animation.keyPath = "path"
        animation.fromValue = from
        animation.toValue = canvas.targetPath
        animation.duration = animation.settlingDuration
        if withdrawing {
            animation.beginTime = CACurrentMediaTime() + NotchQuickAccessLayout.withdrawalDuration
            animation.fillMode = .backwards
        }
        animation.delegate = self
        animation.setValue(generation, forKey: "notchGeneration")
        isAnimating = true
        canvas.animate(animation, from: from)
        CATransaction.commit()
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        // AppKit may cancel a layer animation when the panel resigns key.
        // Internal reversals have already changed the generation; a cancelled
        // current animation must still release its reserved window bounds.
        guard isAnimating, anim.value(forKey: "notchGeneration") as? Int == animationGeneration else { return }
        settle()
    }

    private func settle() {
        let generation = animationGeneration
        let gutter: CGFloat = quickAccessConfiguration == nil ? 0 : NotchQuickAccessLayout.gutter
        let bottom = quickAccessBottomInset(for: targetSize, geometry: currentGeometry)
        // A departing island is ordered out below; its released bounds are never shown.
        let concealed = !hidesWhenSettled
            && concealForFrameChange(to: reservedFrame(mainSize: targetSize, gutter: gutter, bottom: bottom), generation: generation)
        defer { if concealed { reinstateAfterFrameChange() } }
        guard generation == animationGeneration else { return }
        isAnimating = false
        canvas.stopMotion()
        canvas.setUsesGlass(targetUsesGlass)
        // Settled glass is fully open, whatever a cut-short transition planned.
        if targetUsesGlass { canvas.backdropPresentation.openFully() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.setContentSize(targetSize)
        setFrame(mainSize: targetSize, gutter: gutter, bottom: bottom)
        guard generation == animationGeneration else { CATransaction.commit(); return }
        configureQuickAccess()
        canvas.layoutSubtreeIfNeeded()
        guard generation == animationGeneration else { CATransaction.commit(); return }
        CATransaction.commit()
        quickAccessContainer?.motion.setVisible(quickAccessConfiguration != nil, animated: quickAccessAnimate)
        if hidesWhenSettled {
            panel.orderOut(nil)
            concealedForFrameChange = false
            restoresKeyAfterFrameChange = false
        }
        runSettledActions()
    }

    private func reservedFrame(mainSize: CGSize, gutter: CGFloat, bottom: CGFloat) -> CGRect {
        currentGeometry.frame(for: CGSize(width: mainSize.width + gutter * 2, height: mainSize.height + bottom))
    }

    /// Short pages may end above the last side button. Keep its circle and
    /// hover margin inside the window without enlarging the island's surface.
    private func quickAccessBottomInset(for size: CGSize, geometry: NotchGeometry) -> CGFloat {
        guard let configuration = quickAccessConfiguration else { return 0 }
        let sideCount = max(configuration.buttons.filter { $0.side == .left }.count,
                            configuration.buttons.filter { $0.side == .right }.count)
        let sideBottom = sideCount > 0
            ? geometry.quickAccessCenterY + CGFloat(sideCount - 1) * NotchQuickAccessLayout.rowSpacing
                + NotchQuickAccessLayout.diameter / 2 + NotchQuickAccessLayout.hoverMargin
            : 0
        return max(configuration.hasBottom ? NotchQuickAccessLayout.gutter : 0, sideBottom - size.height)
    }

    /// Mission Control switches the window server into a mode where every
    /// change to an on-screen window's frame is animated by the server itself,
    /// over about half a second, stretching the window's current pixels across
    /// its previous bounds. The island only changes its frame at the ends of a
    /// resize, so the settled island would smear over the reserved area. A
    /// frame changed while the panel is ordered out is applied as is; the
    /// panel returns a few milliseconds later, at the new bounds. Returns
    /// whether this call concealed the panel; only that call reinstates it.
    private func concealForFrameChange(to frame: CGRect, generation: Int) -> Bool {
        // Ordering out ends an attached sheet; that dialog outranks a smooth resize.
        guard !concealedForFrameChange, panel.isVisible, panel.attachedSheet == nil,
              !NotchFrameProbe.matches(frame, panel.frame), let frameProbe else { return false }
        // Flushing the probe can report a newer content size synchronously.
        guard frameProbe.serverAnimatesFrames(level: panel.level, screen: currentGeometry.screen),
              generation == animationGeneration, panel.isVisible else { return false }
        concealedForFrameChange = true
        concealedFrameChanges += 1
        restoresKeyAfterFrameChange = panel.isKeyWindow
        panel.orderOut(nil)
        CATransaction.flush()
        return true
    }

    private func reinstateAfterFrameChange() {
        guard concealedForFrameChange else { return }
        concealedForFrameChange = false
        panel.orderFrontRegardless()
        CATransaction.flush()
        if restoresKeyAfterFrameChange { panel.makeKey() }
        restoresKeyAfterFrameChange = false
    }

    private func setFrame(mainSize: CGSize, gutter: CGFloat, bottom: CGFloat) {
        quickAccessContainer?.gutter = gutter
        quickAccessContainer?.bottomInset = bottom
        panel.setFrame(reservedFrame(mainSize: mainSize, gutter: gutter, bottom: bottom), display: false)
        // A media measurement can arrive during AppKit layout. A nested
        // layoutSubtreeIfNeeded is then deferred, so reserve the actual canvas
        // and hosting view now, before the animated mask can expose new pixels.
        quickAccessContainer?.updateFrames()
        canvas.updateGeometry()
        panel.contentView?.layoutSubtreeIfNeeded()
        // AppKit aligns the backing window to pixels; its accepted frame is
        // the baseline for detecting a later move by the window server.
        appliedFrame = panel.frame
    }

    private func configureQuickAccess() {
        guard let container = quickAccessContainer else { return }
        container.quickView.isHidden = quickAccessConfiguration == nil && container.gutter == 0 && container.bottomInset == 0
        guard let configuration = quickAccessConfiguration else {
            container.setHoverRects([])
            return
        }
        // The silhouette's shoulders sit outside its vertical body.
        let shoulder = NotchLayout.shoulder(height: targetSize.height)
        let body = CGRect(x: (panel.frame.width - quickAccessNotchSize.width) / 2 + shoulder, y: 0,
                          width: quickAccessNotchSize.width - shoulder * 2, height: quickAccessNotchSize.height)
        container.motion.configure(configuration, body: body,
                                   headerTop: currentGeometry.quickAccessCenterY,
                                   animated: quickAccessAnimate)
        container.setHoverRects(container.motion.hoverRects.map { $0.intersection(container.bounds) })
    }

    func setHoverHandler(_ handler: @escaping (Bool) -> Void) {
        canvas.hoverChanged = handler
        quickAccessContainer?.hoverChanged = handler
    }

    func containsHover(_ screenPoint: CGPoint) -> Bool {
        guard isPresented else { return false }
        // Hover follows the destination bounds, not a transient mask edge.
        // A resize must never turn a stationary pointer into an exit.
        if currentGeometry.contains(screenPoint, in: targetSize) { return true }
        guard let container = quickAccessContainer else { return false }
        let point = container.convert(panel.convertPoint(fromScreen: screenPoint), from: nil)
        return container.hoverRects.contains { $0.contains(point) }
    }

    func whenSettled(_ action: @escaping () -> Void) {
        settledActions.append(action)
        if !isAnimating { runSettledActions() }
    }

    private func runSettledActions() {
        let actions = settledActions
        settledActions.removeAll()
        for action in actions { DispatchQueue.main.async(execute: action) }
    }

    var visibleFrame: CGRect {
        currentGeometry.frame(for: canvas.visiblePath?.boundingBoxOfPath.size ?? targetSize)
    }

    /// The island's own surface, without the floating controls beside it.
    func containsSurface(_ screenPoint: CGPoint) -> Bool {
        guard isPresented else { return false }
        return canvas.containsVisiblePoint(canvas.convert(panel.convertPoint(fromScreen: screenPoint), from: nil))
    }

    func contains(_ screenPoint: CGPoint) -> Bool {
        if containsSurface(screenPoint) { return true }
        guard isPresented, let container = quickAccessContainer else { return false }
        return container.motion.contains(container.convert(panel.convertPoint(fromScreen: screenPoint), from: nil))
    }

    func setFileDropActions(_ actions: NotchFileDropActions?) { canvas.setFileDropActions(actions) }

    func setActivationArea(_ rect: CGRect, title: String, willPress: @escaping () -> Void, activate: @escaping () -> Void) {
        canvas.setActivationArea(rect, title: title, willPress: willPress, activate: activate)
    }

#if VORSSAINT_DEVELOPMENT
    func probePresentDuringLayout(size: CGSize, geometry: NotchGeometry) -> Bool {
        guard let container = quickAccessContainer else { return false }
        var backingReady = false
        container.nextProbeLayout = { [weak self] in
            guard let self else { return }
            self.present(size: size, geometry: geometry, animated: true, quickAccess: .initial)
            backingReady = self.contentCanvasSize.height + 0.5 >= size.height
        }
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        return backingReady
    }

    var contentProbeOpacity: Float { canvas.contentProbeOpacity }
    var contentProbeAnimating: Bool { canvas.contentProbeAnimating }
    var contentProbeAlpha: CGFloat { canvas.contentProbeAlpha }
    var contentProbeReplacing: Bool { canvas.contentProbeReplacing }
    var backdropProbeFrame: CGRect { canvas.backdropProbeFrame }
    var backdropProbeIndependent: Bool { canvas.backdropProbeIndependent }
    var backdropProbePath: CGPath { canvas.backdropPresentation.contour.cgPath }
    var silhouetteProbePath: CGPath? { canvas.visiblePath }
    var backdropProbeUsesGlass: Bool { canvas.usesGlass }
    var backdropProbeOpenness: Double { canvas.backdropPresentation.openness }
    /// Nil where this macOS has no overlay Spaces to offer.
    var overlayProbeHolds: Bool? { overlaySpace.map { $0.probeHolds(panel) } }
    var backdropProbeScheduled: Bool { canvas.backdropDisplayLink != nil }
    var backdropProbeTicks: Int { canvas.backdropTicks }
    func synchronizeBackdropProbe() { canvas.synchronizeBackdrop() }

    var quickAccessProbeTrackingAreas: Int { quickAccessContainer?.trackingAreas.count ?? 0 }
    var quickAccessProbeInteractive: Bool { quickAccessContainer?.motion.interactive == true }
    var quickAccessProbeCenters: [CGPoint] {
        guard let container = quickAccessContainer else { return [] }
        let motion = container.motion
        return motion.placements.map { placement in
            panel.convertPoint(toScreen: container.convert(placement.center(progress: 1), to: nil))
        }
    }

    func beginProbeDrop(_ pasteboard: NSPasteboard, localSource: Bool = false) -> NSDragOperation {
        canvas.beginDrop(pasteboard, localSource: localSource)
    }
    func finishProbeDrop(_ pasteboard: NSPasteboard) -> Bool { canvas.finishDrop(pasteboard) }
#endif

    var contentCanvasSize: CGSize { canvas.hostedSize }

    var contentTopOnScreen: CGFloat {
        panel.convertPoint(toScreen: canvas.contentTopInWindow).y
    }

    func close() {
        animationGeneration += 1
        isAnimating = false
        concealedForFrameChange = false
        canvas.stopMotion()
        quickAccessContainer?.motion.setVisible(false, animated: false)
        quickAccessContainer?.setHoverRects([])
        panel.orderOut(nil)
        panel.contentView = nil
        overlaySpace?.close()
        frameProbe?.close()
        frameProbe = nil
        runSettledActions()
    }
}

/// Nothing announces the window server's animated mode. An invisible two-point
/// window resized right before the island's own frame change tells whether the
/// server applies frames immediately: outside Mission Control the new size
/// reads back at once, inside it the previous size is still reported while the
/// server animates. Only a size change is applied synchronously, once the
/// layer tree is flushed; a move is deferred and would read back stale anywhere.
private final class NotchFrameProbe {
    private let window: NotchPanel
    private var grown = false

    init(collectionBehavior: NSWindow.CollectionBehavior) {
        window = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 2, height: 2),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = collectionBehavior
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        content.wantsLayer = true
        window.contentView = content
    }

    /// AppKit aligns window bounds to pixels; sub-point differences are no change.
    static func matches(_ frame: CGRect, _ other: CGRect) -> Bool {
        abs(frame.minX - other.minX) <= 0.5 && abs(frame.minY - other.minY) <= 0.5
            && abs(frame.width - other.width) <= 0.5 && abs(frame.height - other.height) <= 0.5
    }

    /// Keeps the probe on the island's display, below its menu bar so the
    /// space measurements never count it, at the island's own level.
    func attach(level: NSWindow.Level, screen: CGRect) {
        if window.level != level { window.level = level }
        let side: CGFloat = grown ? 40 : 2
        let frame = CGRect(x: screen.minX, y: screen.minY, width: side, height: side)
        if !Self.matches(frame, window.frame) { window.setFrame(frame, display: false) }
        if !window.isVisible { window.orderFrontRegardless() }
    }

    /// Whether a frame set on an on-screen window right now would be animated.
    /// Unknown geometry reads as immediate, keeping the ordinary resize, and so
    /// does a flush that could not commit: inside an AppKit layout pass or an
    /// explicit transaction the layer tree stays pending, the server still
    /// shows the old size, and that lag would pass for Mission Control on the
    /// desktop. The probe's presentation layer trails its model exactly then.
    /// The reading waits for the server to apply the flushed commit, up to a
    /// frame (5 ms median, 15 ms at the 90th percentile in the presentation
    /// checks); a direct window-server query waits just the same.
    func serverAnimatesFrames(level: NSWindow.Level, screen: CGRect) -> Bool {
        grown.toggle()
        attach(level: level, screen: screen)
        window.contentView?.layoutSubtreeIfNeeded()
        CATransaction.flush()
        guard let layer = window.contentView?.layer, let committed = layer.presentation()?.bounds.size,
              abs(committed.width - layer.bounds.width) <= 0.5, abs(committed.height - layer.bounds.height) <= 0.5,
              window.windowNumber > 0,
              let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(window.windowNumber))
                            as? [[String: Any]])?.first,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let width = bounds["Width"], let height = bounds["Height"] else { return false }
        return abs(width - window.frame.width) > 0.5 || abs(height - window.frame.height) > 0.5
    }

    func close() { window.orderOut(nil) }
}

final class NotchPanel: NSPanel {
    static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
    ]
    // Status items own the screen edge at their level, even when our view's
    // hit test includes it. Keep the island above them, below native menus.
    static let normalLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    var acceptsKeyFocus = false
    var handleScroll: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { acceptsKeyFocus }
    override var canBecomeMain: Bool { false }
    // Liquid Glass swaps to a flat, blurred stand-in in a window that looks
    // inactive, and a non-activating panel only looks active while it holds
    // key focus: an island opened by hover stayed dull until clicked. Like
    // the menu bar it hangs from, the island always looks active, without
    // taking the keyboard from the app in front. AppKit's own glass windows
    // answer this private question the same way.
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    // AppKit describes a non-activating panel as a system dialog, which tiling
    // window managers then track and list on whichever space is current; the
    // borderless overlays they leave alone are undescribed windows.
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }

    // Ordering out a window detaches its sheet without ever running the
    // sheet's completion, which would leave a dialog opened inside the island
    // waiting forever after a lock, sleep or teardown. End it first.
    override func orderOut(_ sender: Any?) {
        if let sheet = attachedSheet { endSheet(sheet, returnCode: .cancel) }
        super.orderOut(sender)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel, handleScroll?(event) == true { return }
        super.sendEvent(event)
    }
}

/// The notch keeps its existing masked canvas. A separate, transparent sibling
/// holds the drops, so both surfaces share one window, focus and capture policy.
private final class NotchQuickAccessContainer: NSView {
    let canvas: NotchCanvas
    let motion: NotchQuickAccessMotion
    let quickView: NSHostingView<AnyView>
    private(set) var hoverRects: [CGRect] = []
    private var hoverTrackingAreas: [NSTrackingArea] = []
    var hoverChanged: ((Bool) -> Void)?
    var gutter: CGFloat = 0 { didSet { needsLayout = true } }
    var bottomInset: CGFloat = 0 { didSet { needsLayout = true } }
#if VORSSAINT_DEVELOPMENT
    var nextProbeLayout: (() -> Void)?
#endif
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init(canvas: NotchCanvas, content: (NotchQuickAccessMotion) -> AnyView) {
        self.canvas = canvas
        let motion = NotchQuickAccessMotion()
        self.motion = motion
        quickView = NSHostingView(rootView: content(motion))
        quickView.sizingOptions = []
        quickView.wantsLayer = true
        quickView.isHidden = true
        super.init(frame: canvas.frame)
        wantsLayer = true
        autoresizesSubviews = false
        addSubview(quickView)
        addSubview(canvas)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        updateFrames()
#if VORSSAINT_DEVELOPMENT
        let probe = nextProbeLayout
        nextProbeLayout = nil
        probe?()
#endif
    }

    func updateFrames() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let frame = CGRect(x: gutter, y: 0, width: max(0, bounds.width - gutter * 2), height: max(0, bounds.height - bottomInset))
        if canvas.frame != frame { canvas.frame = frame }
        if quickView.frame != bounds { quickView.frame = bounds }
        CATransaction.commit()
    }

    func setHoverRects(_ rects: [CGRect]) {
        guard rects != hoverRects else { return }
        hoverTrackingAreas.forEach(removeTrackingArea)
        hoverRects = rects
        hoverTrackingAreas = rects.filter { !$0.isEmpty && !$0.isNull }.map { rect in
            NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag], owner: self, userInfo: nil)
        }
        hoverTrackingAreas.forEach(addTrackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        if hoverTrackingAreas.contains(where: { event.trackingArea === $0 }) { hoverChanged?(true) }
        else { super.mouseEntered(with: event) }
    }

    override func mouseExited(with event: NSEvent) {
        if hoverTrackingAreas.contains(where: { event.trackingArea === $0 }) { hoverChanged?(false) }
        else { super.mouseExited(with: event) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard canvas.containsVisiblePoint(canvas.convert(local, from: self)) || motion.contains(local) else { return nil }
        return super.hitTest(point)
    }
}

/// CADisplayLink retains its target; the weak forwarding object lets an ordered
/// out or destroyed canvas release its scheduler even mid-animation.
private final class NotchBackdropTick: NSObject {
    weak var canvas: NotchCanvas?
    init(canvas: NotchCanvas) { self.canvas = canvas }
    @objc func fire(_ sender: CADisplayLink) { canvas?.advanceBackdrop() }
}

private final class NotchCanvas: NSView {
    private let host: NotchHostingView
    private let backdrop: NotchHostingView
    let backdropPresentation = NotchBackdropPresentation()
    private(set) var backdropDisplayLink: CADisplayLink?
    private lazy var backdropTick = NotchBackdropTick(canvas: self)
    private(set) var backdropTicks = 0
    private let activationButton = NotchActivationButton()
    private var activationRect = CGRect.zero
    private var hoverTrackingArea: NSTrackingArea?
    var hoverChanged: ((Bool) -> Void)?
    private let silhouette = CAShapeLayer()
    private let edge = CAShapeLayer()
    private let contentVisibility = CALayer()
    private var dropActions: NotchFileDropActions?
    private var acceptingDrag = false
    private var contentSize: CGSize
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init(content: AnyView, background: (NotchBackdropPresentation) -> AnyView, size: CGSize) {
        contentSize = size
        backdrop = NotchHostingView(rootView: background(backdropPresentation))
        backdrop.sizingOptions = []
        backdrop.wantsLayer = true
        backdrop.autoresizingMask = []
        host = NotchHostingView(rootView: content)
        host.sizingOptions = []
        host.wantsLayer = true
        host.autoresizingMask = []
        super.init(frame: CGRect(origin: .zero, size: size))
        autoresizesSubviews = false
        wantsLayer = true
        // The backdrop stays independent of the content fade and follows the
        // animated silhouette, keeping its glass lip visible while closing.
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        layer?.mask = silhouette
        addSubview(backdrop)
        addSubview(host)
        activationButton.isTransparent = true
        activationButton.isHidden = true
        activationButton.target = activationButton
        activationButton.action = #selector(NotchActivationButton.invoke)
        activationButton.setAccessibilityIdentifier("notch.activation")
        addSubview(activationButton)
        edge.fillColor = nil
        updateContrast()
        edge.lineWidth = 0.5
        edge.zPosition = 2
        layer?.addSublayer(edge)
        contentVisibility.name = "notch.contentVisibility"
        contentVisibility.backgroundColor = NSColor.black.cgColor
        contentVisibility.opacity = 1
        host.layer?.mask = contentVisibility
        setContentSize(size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setContentSize(_ size: CGSize) {
        contentSize = size
        needsLayout = true
    }

    func setActivationArea(_ rect: CGRect, title: String, willPress: @escaping () -> Void, activate: @escaping () -> Void) {
        activationRect = rect
        activationButton.isHidden = rect.isEmpty
        activationButton.setAccessibilityLabel(title)
        activationButton.willPress = willPress
        activationButton.activate = activate
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func updateContrast() {
        let color = NSColor.white.withAlphaComponent(
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.45 : 0).cgColor
        guard edge.strokeColor != color else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edge.strokeColor = color
        CATransaction.commit()
    }

    func setFileDropActions(_ actions: NotchFileDropActions?) {
        let wasEnabled = dropActions != nil
        dropActions = actions
        guard wasEnabled != (actions != nil) else { return }
        unregisterDraggedTypes()
        if actions != nil { registerForDraggedTypes(ShelfService.tileDropTypes) }
        else { acceptingDrag = false }
    }

    func beginDrop(_ pasteboard: NSPasteboard, localSource: Bool) -> NSDragOperation {
        // In-app tile drags keep their own reorder/merge destinations. This
        // stable native view receives external drops while its content expands.
        acceptingDrag = !localSource && dropActions?.canAccept(pasteboard) == true
        if acceptingDrag { dropActions?.enter(pasteboard) }
        return acceptingDrag ? .copy : []
    }

    func finishDrop(_ pasteboard: NSPasteboard) -> Bool {
        guard acceptingDrag else { return false }
        defer { acceptingDrag = false; dropActions?.exit() }
        return dropActions?.accept(pasteboard) == true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard containsVisiblePoint(convert(sender.draggingLocation, from: nil)) else {
            if acceptingDrag { acceptingDrag = false; dropActions?.exit() }
            return []
        }
        let operation = acceptingDrag ? .copy : beginDrop(sender.draggingPasteboard, localSource: sender.draggingSource != nil)
        if acceptingDrag, dropActions?.update?(convert(sender.draggingLocation, from: nil)) == false { return [] }
        return operation
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        acceptingDrag = false
        dropActions?.exit()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard containsVisiblePoint(convert(sender.draggingLocation, from: nil)) else {
            acceptingDrag = false
            dropActions?.exit()
            return false
        }
        if acceptingDrag, dropActions?.update?(convert(sender.draggingLocation, from: nil)) == false {
            acceptingDrag = false
            dropActions?.exit()
            return false
        }
        return finishDrop(sender.draggingPasteboard)
    }

#if VORSSAINT_DEVELOPMENT
    var contentProbeOpacity: Float { contentVisibility.presentation()?.opacity ?? contentVisibility.opacity }
    var contentProbeAnimating: Bool { contentVisibility.animation(forKey: "notch.opacity") != nil }
    var contentProbeAlpha: CGFloat { host.alphaValue }
    var contentProbeReplacing: Bool { host.layer?.animation(forKey: kCATransition) != nil }
    var backdropProbeFrame: CGRect { backdropPresentation.contour.boundingRect }
    var backdropProbeIndependent: Bool {
        host.layer?.mask === contentVisibility && backdrop.layer?.mask == nil
            && (backdrop.layer?.presentation()?.opacity ?? backdrop.layer?.opacity) == 1
    }
#endif

    var hostedSize: CGSize { host.frame.size }
    var contentTopInWindow: CGPoint { host.convert(.zero, to: nil) }

    private static let motionKey = "notch.resize"
    var targetPath: CGPath? { silhouette.path }
    var visiblePath: CGPath? { silhouette.presentation()?.path ?? silhouette.path }

    func containsVisiblePoint(_ point: CGPoint) -> Bool { visiblePath?.contains(point) == true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard containsVisiblePoint(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }

    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === hoverTrackingArea { hoverChanged?(true) }
        else { super.mouseEntered(with: event) }
    }

    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === hoverTrackingArea { hoverChanged?(false) }
        else { super.mouseExited(with: event) }
    }

    func animate(_ animation: CASpringAnimation, from: CGPath?) {
        silhouette.add(animation, forKey: Self.motionKey)
        if let from { setBackdropContour(from) }
        // Only the material follows the display link; content layout and the
        // native window remain fixed for the duration of the animation.
        let link = displayLink(target: backdropTick, selector: #selector(NotchBackdropTick.fire(_:)))
        backdropDisplayLink = link
        link.add(to: .main, forMode: .common)
        if let borderAnimation = animation.copy() as? CAAnimation {
            borderAnimation.delegate = nil
            edge.add(borderAnimation, forKey: Self.motionKey)
        }
    }
    func stopMotion() {
        silhouette.removeAnimation(forKey: Self.motionKey)
        edge.removeAnimation(forKey: Self.motionKey)
        backdropDisplayLink?.invalidate()
        backdropDisplayLink = nil
    }

    var usesGlass: Bool { backdropPresentation.usesGlass }

    func setUsesGlass(_ enabled: Bool) {
        guard usesGlass != enabled else { return }
        backdropPresentation.usesGlass = enabled
    }

    fileprivate func advanceBackdrop() {
        backdropTicks += 1
        synchronizeBackdrop()
    }

    fileprivate func synchronizeBackdrop() {
        // Immediately use the final model path after stopping the scheduler;
        // the presentation layer can still describe the preceding frame until
        // Core Animation commits this transaction.
        let path = backdropDisplayLink == nil ? silhouette.path : visiblePath
        if let path { setBackdropContour(path) }
    }

    private func setBackdropContour(_ path: CGPath) {
        let contour = Path(path)
        guard backdropPresentation.contour != contour else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { backdropPresentation.contour = contour }
    }

    deinit { backdropDisplayLink?.invalidate() }

    func transitionContent(_ kind: NotchContentTransition) {
        guard kind != .none else { return }
        let currentOpacity = contentVisibility.presentation()?.opacity ?? contentVisibility.opacity
        contentVisibility.removeAnimation(forKey: "notch.opacity")
        host.layer?.removeAnimation(forKey: kCATransition)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if kind == .replace {
            contentVisibility.opacity = 1
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.18
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            host.layer?.add(transition, forKey: kCATransition)
        } else {
            // Mask only the content pixels. A black overlay would obscure the
            // glass; alphaValue would remove the hosting view's AX/hit frame.
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            let start: Float = kind == .dismiss || currentOpacity == 1 ? 0 : currentOpacity
            // Give the silhouette a head start before revealing full-width
            // content. Reversals continue from the opacity already on screen.
            animation.values = [start, start, 1]
            animation.keyTimes = kind == .dismiss ? [0, 0.65, 1] : [0, 0.625, 1]
            animation.duration = 0.40
            animation.calculationMode = .linear
            animation.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)]
            contentVisibility.opacity = 1
            contentVisibility.add(animation, forKey: "notch.opacity")
        }
        CATransaction.commit()
    }

    func restoreContent() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentVisibility.removeAnimation(forKey: "notch.opacity")
        contentVisibility.opacity = 1
        host.layer?.removeAnimation(forKey: kCATransition)
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        updateGeometry()
    }

    func updateGeometry() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        silhouette.frame = bounds
        edge.frame = bounds
        contentVisibility.frame = bounds
        var translation = CGAffineTransform(translationX: (bounds.width - contentSize.width) / 2, y: 0)
        silhouette.path = NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: contentSize.height))
            .path(in: CGRect(origin: .zero, size: contentSize)).cgPath.copy(using: &translation)
        edge.path = silhouette.path
        edge.opacity = contentSize.height > 64 ? 1 : 0
        // Keep foreground layout fixed inside the reserved reveal area. Only
        // the separate backdrop's contour changes on animation frames.
        if host.frame != bounds { host.frame = bounds }
        if backdrop.frame != bounds { backdrop.frame = bounds }
        synchronizeBackdrop()
        activationButton.frame = activationRect.offsetBy(dx: (bounds.width - contentSize.width) / 2, dy: 0)
        let hoverRect = CGRect(x: (bounds.width - contentSize.width) / 2, y: 0, width: contentSize.width, height: contentSize.height)
        if hoverTrackingArea?.rect != hoverRect {
            if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
            let area = NSTrackingArea(rect: hoverRect, options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag], owner: self, userInfo: nil)
            hoverTrackingArea = area
            addTrackingArea(area)
        }
        CATransaction.commit()
    }
}

final class NotchActivationButton: NSButton {
    var willPress: (() -> Void)?
    var activate: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        willPress?()
        super.mouseDown(with: event)
    }
    @objc func invoke() { activate?() }
}

private final class NotchHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
