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

/// `depart` keeps the leaving content on screen while the shape closes
/// around it, fading out before the next content takes its place.
enum NotchContentTransition { case none, reveal, dismiss, depart, replace }

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
    private var missionControlTimer: Timer?
    private var concealedForMissionControl = false
    private var missionControlAlpha: CGFloat = 1
    private var missionControlMouseEvents = false
    private var desktopReadings = 0
    private var lastMissionControlCheck: TimeInterval = -.infinity
    private var lastMissionControlProbe: TimeInterval = -.infinity
    private var overviewWasVisible = false
    private var restoringFromMissionControl = false
    var missionControlDidRestore: (() -> Void)?
    private let overlaySpace = NotchOverlaySpace()
    private var concealedForFrameChange = false
    private var restoresKeyAfterFrameChange = false
    private var settledActions: [() -> Void] = []
    private(set) var targetSize: CGSize
    private(set) var resizeCount = 0
    private(set) var concealedFrameChanges = 0
    private(set) var missionControlFrameProbeCount = 0

    init(content: AnyView, geometry: NotchGeometry, size: CGSize,
         background: (NotchBackdropPresentation) -> AnyView = { _ in AnyView(Color.black) },
         quickAccess: ((NotchQuickAccessMotion, NotchBackdropPresentation) -> AnyView)? = nil) {
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
        panel.setFrame(pixelAligned(geometry.frame(for: size)), display: false)
        canvas.islandMinX = { [weak self] size in self?.islandMinX(size) }
        canvas.stageCentreX = { [weak self] in
            guard let self else { return nil }
            return self.currentGeometry.screen.midX - self.panel.frame.minX - self.canvas.convert(CGPoint.zero, to: nil).x
        }
        canvas.layoutSubtreeIfNeeded()
        appliedFrame = panel.frame
        overlaySpace?.add(panel)
        panel.visibilityDidChange = { [weak self] in self?.syncMissionControlMonitoring() }
    }

    /// Whether leaving content is fading out with the shape rather than hidden at once.
    var departsContent: Bool { canvas.departsContent }

    /// The view has swapped out the departed content; the next one fades in.
    func finishDeparture() { canvas.finishDeparture() }

    /// Visible, or ordered out for the few milliseconds of a concealed frame change.
    private var isPresented: Bool { panel.isVisible || concealedForFrameChange }
    var isConcealedForMissionControl: Bool {
        // Media-key taps can ask from a worker thread. Never touch AppKit or
        // run the frame probe there; a panel being hidden cannot show feedback.
        guard Thread.isMainThread else { return concealedForMissionControl || hidesWhenSettled }
        // A hidden panel needs on-demand checks to detect Mission Control;
        // once concealed, its timer keeps watching for the desktop to return.
        if !panel.isVisible && !concealedForFrameChange { refreshMissionControlState() }
        return concealedForMissionControl
    }

    func blocksHoverReveal() -> Bool {
        // Check again at the hover deadline: Mission Control can start while
        // the pointer is waiting over the island's activation area.
        refreshMissionControlState(now: true)
        return concealedForMissionControl
    }

    func setMouseEventsIgnored(_ ignored: Bool) {
        // Capture controls can change their click-through policy while the
        // island is concealed or on its way out. Keep that policy for restore.
        if concealedForMissionControl { missionControlMouseEvents = ignored }
        if mouseEventsBeforeHide != nil { mouseEventsBeforeHide = ignored }
        let effective = ignored || concealedForMissionControl || hidesWhenSettled
        if panel.ignoresMouseEvents != effective { panel.ignoresMouseEvents = effective }
    }

    func hide(animated: Bool, transitionContent: NotchContentTransition = .dismiss) {
        guard isPresented else { return }
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !hidesWhenSettled || !animate else { return }
        present(size: CGSize(width: currentGeometry.collapsed.width, height: 0), geometry: currentGeometry,
                animated: animate, transitionContent: transitionContent == .depart ? .depart : .dismiss,
                hideWhenSettled: true)
    }

    func present(size: CGSize, geometry: NotchGeometry, animated: Bool, transitionContent: NotchContentTransition = .none,
                 quickAccess: NotchQuickAccessConfiguration? = nil, revealFromHidden: Bool = false,
                 hideWhenSettled: Bool = false, usesGlass: Bool = false) {
        canvas.setOutline(NotchSilhouette.current())
        hidesWhenSettled = hideWhenSettled
        if hideWhenSettled {
            if mouseEventsBeforeHide == nil {
                mouseEventsBeforeHide = concealedForMissionControl ? missionControlMouseEvents : panel.ignoresMouseEvents
            }
            // The departing surface must already release the menu bar below it.
            panel.ignoresMouseEvents = true
        } else if let previous = mouseEventsBeforeHide {
            panel.ignoresMouseEvents = previous
            mouseEventsBeforeHide = nil
        }
        if concealedForMissionControl { panel.ignoresMouseEvents = true }
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
            // Glass closing into a black strip shuts as its page leaves, so the
            // empty shell never shows the windows beneath it; opening out of one
            // lets the glass in over the last stretch, as the page fades in.
            let start = revealing ? 0 : canvas.visibleSize?.height ?? targetSize.height
            canvas.backdropPresentation.planFade(from: start, to: size.height, endsInGlass: usesGlass)
            canvas.updateCanvasBlack()
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
        else if animated && changesFrame && (revealing || transitionContent == .reveal) {
            // Reduce Motion, or a panel that was ordered out, puts the island
            // at its new size at once. Shown at once, the page reached the
            // screen in the resting shape, flushed ahead of the resize, or
            // ahead of the surface drawn beneath it. A fade is not motion.
            canvas.transitionContent(.reveal, shapeSnaps: true)
        } else { canvas.restoreContent() }
        guard changesFrame else { configureQuickAccess(); return }
        // An ordered-out panel still has its last expanded shape. Start the
        // reveal at the screen edge, even when reopening at that same size.
        let previousWidth = revealing ? geometry.collapsed.width : canvas.bounds.width
        let previousPath = revealing
            ? NotchShape(attached: true, radius: 0, floatingGap: NotchSilhouette.current().gap)
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

        let start = canvas.surfaceSize(of: previousPath)
        // Room for the swing past a larger target, and for everything already reserved.
        var envelope = NotchMotion.envelope(from: start, to: size)
        if !revealing {
            envelope = CGSize(width: max(envelope.width, canvas.bounds.width), height: max(envelope.height, canvas.bounds.height))
        }
        envelope = NotchMotion.reservation(envelope, centring: size)
        let reservedGutter = max(quickAccessContainer?.gutter ?? 0, gutter)
        let reservedBottom = max(quickAccessContainer?.bottomInset ?? 0, bottom)
        // The probe flushes the layer tree; the departing animation stays
        // installed until then, so no frame shows its bare model path.
        let concealed = concealForFrameChange(to: reservedFrame(mainSize: envelope, gutter: reservedGutter, bottom: reservedBottom),
                                              generation: generation)
        defer { if concealed { reinstateAfterFrameChange() } }
        guard generation == animationGeneration else { return }
        isAnimating = false
        // The window is drawn as its frame changes, before the motion is
        // installed. Until then the silhouette and its material keep the
        // shape on screen instead of showing the target for a frame.
        canvas.motionStart = start
        defer { canvas.motionStart = nil }
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
        // Each frame is the island's own silhouette at that size, so its
        // corners and shoulders stay true while the sides swing apart.
        let motion = NotchMotion.frames(from: start, to: size)
        let paths = motion.sizes.map(canvas.silhouettePath)
        // The floating controls emerge once the island reaches its size, while it still swings.
        if quickAccessConfiguration != nil {
            quickAccessContainer?.motion.setVisible(true, animated: canAnimate,
                                                    delay: NotchMotion.arrivalTime(from: start, to: size))
        }
        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = paths
        animation.keyTimes = motion.keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .linear
        animation.duration = motion.duration
        if withdrawing {
            animation.beginTime = CACurrentMediaTime() + NotchQuickAccessLayout.withdrawalDuration
            animation.fillMode = .backwards
        }
        animation.delegate = self
        animation.setValue(generation, forKey: "notchGeneration")
        isAnimating = true
        canvas.animate(animation, from: paths.first, motion: (start, size))
        CATransaction.commit()
        // The window already has its new frame; its layers go out at once,
        // not at the end of this turn of the run loop, so the screen never
        // shows the new frame with the layers laid out for the old one.
        CATransaction.flush()
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
        canvas.updateCanvasBlack()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.setContentSize(targetSize)
        setFrame(mainSize: targetSize, gutter: gutter, bottom: bottom)
        guard generation == animationGeneration else { CATransaction.commit(); return }
        configureQuickAccess()
        canvas.layoutSubtreeIfNeeded()
        guard generation == animationGeneration else { CATransaction.commit(); return }
        CATransaction.commit()
        CATransaction.flush()
        quickAccessContainer?.motion.setVisible(quickAccessConfiguration != nil, animated: quickAccessAnimate)
        if hidesWhenSettled {
            panel.orderOut(nil)
            concealedForFrameChange = false
            restoresKeyAfterFrameChange = false
        }
        runSettledActions()
    }

    private func reservedFrame(mainSize: CGSize, gutter: CGFloat, bottom: CGFloat) -> CGRect {
        pixelAligned(currentGeometry.frame(for: CGSize(width: mainSize.width + gutter * 2, height: mainSize.height + bottom)))
    }

    /// Frames snap to the display's pixels here, not later inside AppKit, so
    /// the island's place within any reserved area can be snapped the same way.
    /// The pixels are those of the island's display, which the window may not
    /// have reached yet when it moves to another one.
    private func pixelAligned(_ rect: CGRect) -> CGRect {
        let scale = NSScreen.screens.first { $0.frame == currentGeometry.screen }?.backingScaleFactor
            ?? panel.backingScaleFactor
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let minX = snap(rect.minX), minY = snap(rect.minY)
        return CGRect(x: minX, y: minY, width: snap(rect.maxX) - minX, height: snap(rect.maxY) - minY)
    }

    /// Where the island of `size` starts inside the canvas: on the pixel it
    /// occupies at rest, whatever area is reserved around it. Centred by
    /// arithmetic, half a point of odd margin moved it a pixel on a
    /// standard-resolution display as a transition began or settled.
    private func islandMinX(_ size: CGSize) -> CGFloat {
        pixelAligned(currentGeometry.frame(for: size)).minX - panel.frame.minX - canvas.convert(CGPoint.zero, to: nil).x
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
        // Reading the probe resizes a window of its own and flushes the layer
        // tree mid-change; on the desktop, now and then, the island left the
        // screen for that frame as it opened or settled. Only an overview on
        // screen is reason to ask.
        guard concealedForMissionControl || NotchFrameProbe.overviewIsVisible(on: currentGeometry.screen) else { return false }
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
        // Placed on the controls' own stage, so a resized window leaves them be.
        let islandX = canvas.convert(CGPoint(x: islandMinX(quickAccessNotchSize), y: 0), to: container.quickView).x
        let body = CGRect(x: islandX + shoulder, y: 0,
                          width: quickAccessNotchSize.width - shoulder * 2, height: quickAccessNotchSize.height)
        container.motion.configure(configuration, body: body,
                                   headerTop: currentGeometry.quickAccessCenterY,
                                   animated: quickAccessAnimate)
        container.setHoverRects(container.motion.hoverRects.map {
            container.convert($0, from: container.quickView).intersection(container.bounds)
        })
    }

    func setHoverHandler(_ handler: @escaping (Bool) -> Void) {
        canvas.hoverChanged = handler
        quickAccessContainer?.hoverChanged = handler
    }

    func containsHover(_ screenPoint: CGPoint) -> Bool {
        guard isPresented, !concealedForMissionControl else { return false }
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

    /// The stationary island must stay on Show Desktop for file drops, but it
    /// covers desktop names in Mission Control. A full-screen overview window
    /// is the cheap hint, and the frame probe, which waits on the window
    /// server, runs only while one is up or the island is concealed.
    private func syncMissionControlMonitoring() {
        guard panel.isVisible || concealedForMissionControl else {
            missionControlTimer?.invalidate()
            missionControlTimer = nil
            return
        }
        if missionControlTimer == nil {
            let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
                self?.refreshMissionControlState()
            }
            timer.tolerance = 0.04
            missionControlTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        if panel.isVisible { refreshMissionControlState(now: true) }
    }

    private func refreshMissionControlState(now immediate: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard immediate || now - lastMissionControlCheck >= 0.08 else { return }
        lastMissionControlCheck = now
        let overview = NotchFrameProbe.overviewIsVisible(on: currentGeometry.screen)
        let appeared = overview && !overviewWasVisible
        overviewWasVisible = overview
        // The window list costs a fraction of a millisecond; a probe reading
        // waits up to a frame for the window server. Without an overview the
        // desktop needs no reading at all. While one stays up the reading is
        // repeated slowly, and once it closes the desktop is confirmed promptly.
        guard overview || concealedForMissionControl else { return }
        let interval = concealedForMissionControl && !overview ? 0.08 : 0.5
        guard immediate || appeared || now - lastMissionControlProbe >= interval else { return }
        lastMissionControlProbe = now
        sampleMissionControl()
    }

    private func sampleMissionControl() {
        missionControlFrameProbeCount += 1
        let probe = frameProbe ?? NotchFrameProbe(collectionBehavior: panel.collectionBehavior)
        frameProbe = probe
        if probe.serverAnimatesFrames(level: panel.level, screen: currentGeometry.screen) {
            desktopReadings = 0
            guard !concealedForMissionControl else { panel.ignoresMouseEvents = true; return }
            concealedForMissionControl = true
            // Reopened during the fade back in, the panel is still on its way
            // to the alpha kept from the first entry.
            if !restoringFromMissionControl { missionControlAlpha = panel.alphaValue }
            missionControlMouseEvents = mouseEventsBeforeHide ?? panel.ignoresMouseEvents
            panel.ignoresMouseEvents = true
            if panel.isVisible { fadeMissionControl(to: 0) }
            else {
                panel.alphaValue = 0
                syncMissionControlMonitoring()
            }
        } else if concealedForMissionControl {
            desktopReadings += 1
            guard desktopReadings >= 3 else { return }
            restoreFromMissionControl()
        }
    }

    private func restoreFromMissionControl() {
        concealedForMissionControl = false
        desktopReadings = 0
        panel.ignoresMouseEvents = hidesWhenSettled ? true : missionControlMouseEvents
        if panel.isVisible {
            restoringFromMissionControl = true
            fadeMissionControl(to: missionControlAlpha) { [weak self] in self?.restoringFromMissionControl = false }
        } else {
            panel.alphaValue = missionControlAlpha
            syncMissionControlMonitoring()
        }
        missionControlDidRestore?()
    }

    private func fadeMissionControl(to alpha: CGFloat, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
            panel.animator().alphaValue = alpha
        }, completionHandler: completion)
    }

    var visibleFrame: CGRect {
        currentGeometry.frame(for: canvas.visibleSize ?? targetSize)
    }

    /// The island's own surface, without the floating controls beside it.
    func containsSurface(_ screenPoint: CGPoint) -> Bool {
        guard isPresented, !concealedForMissionControl else { return false }
        return canvas.containsVisiblePoint(canvas.convert(panel.convertPoint(fromScreen: screenPoint), from: nil))
    }

    func contains(_ screenPoint: CGPoint) -> Bool {
        if containsSurface(screenPoint) { return true }
        guard isPresented, !concealedForMissionControl, let container = quickAccessContainer else { return false }
        return container.motion.contains(container.quickView.convert(panel.convertPoint(fromScreen: screenPoint), from: nil))
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
    var contentProbeBlurred: Bool { canvas.contentProbeBlurred }
    var contentProbeGrowing: Bool { canvas.contentProbeGrowing }
    var contentProbeGrowthDrift: CGFloat { canvas.contentProbeGrowthDrift }
    var backdropProbeFrame: CGRect { canvas.backdropProbeFrame }
    var backdropProbeIndependent: Bool { canvas.backdropProbeIndependent }
    var backdropProbeFollowsSilhouette: Bool { canvas.backdropProbeFollowsSilhouette }
    var silhouetteProbePath: CGPath? { canvas.visiblePath }
    /// The size the running resize started from.
    var motionProbeStart: CGSize? { canvas.motionProbeStart }
    var backdropProbeContour: Path { canvas.backdropPresentation.contour }
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
            panel.convertPoint(toScreen: container.quickView.convert(placement.center(progress: 1), to: nil))
        }
    }

    /// The floating layer's opacity at a screen point, drawn offscreen.
    func quickAccessProbeOpacity(at screenPoint: CGPoint) -> CGFloat? {
        guard let view = quickAccessContainer?.quickView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let point = view.convert(panel.convertPoint(fromScreen: screenPoint), from: nil)
        let scale = CGFloat(bitmap.pixelsWide) / max(1, view.bounds.width)
        // Bitmap rows run from the top.
        let row = view.isFlipped ? point.y : view.bounds.height - point.y
        return bitmap.colorAt(x: Int(point.x * scale), y: Int(row * scale))?.alphaComponent
    }

    func beginProbeDrop(_ pasteboard: NSPasteboard, localSource: Bool = false) -> NSDragOperation {
        canvas.beginDrop(pasteboard, localSource: localSource)
    }
    func finishProbeDrop(_ pasteboard: NSPasteboard) -> Bool { canvas.finishDrop(pasteboard) }
#endif

    /// The area reserved for the island inside the window.
    var contentCanvasSize: CGSize { canvas.bounds.size }
    /// The fixed stage the island's content is laid out on.
    var contentStageSize: CGSize { canvas.hostedSize }

    var contentTopOnScreen: CGFloat {
        panel.convertPoint(toScreen: canvas.contentTopInWindow).y
    }

    func close() {
        missionControlTimer?.invalidate()
        missionControlTimer = nil
        panel.visibilityDidChange = nil
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

/// SwiftUI lays out and draws a hosting view a frame after it is resized, so
/// a view sized with the island's reserved area showed its content, its
/// material and its floating controls a frame out of place whenever the
/// window grew or shrank around a transition. Each hosting view instead
/// keeps one stage, as large as the largest display and centred on the
/// island, which no resize of the window changes.
enum NotchStage {
    static func size(including size: CGSize) -> CGSize {
        let largest = NSScreen.screens.reduce(CGSize.zero) {
            CGSize(width: max($0.width, $1.frame.width), height: max($0.height, $1.frame.height))
        }
        return CGSize(width: max(size.width, largest.width), height: max(size.height, largest.height))
    }

    /// A stage of `stage` size centred on the top of `bounds`.
    static func frame(_ stage: CGSize, in bounds: CGRect, dy: CGFloat = 0) -> CGRect {
        CGRect(x: bounds.midX - stage.width / 2, y: bounds.minY + dy, width: stage.width, height: stage.height)
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

    /// On macOS 27 Mission Control and App Exposé cover the display with a
    /// WindowManager window at layer 19; Show Desktop uses layer 18 and keeps
    /// the island, and its own transition would read as animated. Earlier
    /// systems had Dock's overview window at layer 18. This is only a reason
    /// to run the frame probe, never a visibility decision by itself, and the
    /// size check leaves Stage Manager's strip out.
    static func overviewIsVisible(on screen: CGRect) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        return windows.contains { window in
            let owner = window[kCGWindowOwnerName as String] as? String
            let layer = window[kCGWindowLayer as String] as? Int
            if owner == "Dock" { return layer == 18 }
            guard owner == "WindowManager", layer == 19,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return (bounds["Width"] ?? 0) >= screen.width - 1 && (bounds["Height"] ?? 0) >= screen.height - 1
        }
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
        if !window.isVisible {
            // A panel created directly in hidden-until-hover mode has not
            // primed this probe. Give the server a settled initial frame.
            attach(level: level, screen: screen)
            window.contentView?.layoutSubtreeIfNeeded()
            CATransaction.flush()
        }
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
    var visibilityDidChange: (() -> Void)?
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
        visibilityDidChange?()
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        visibilityDidChange?()
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
    private var stage = CGSize.zero
#if VORSSAINT_DEVELOPMENT
    var nextProbeLayout: (() -> Void)?
#endif
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init(canvas: NotchCanvas, content: (NotchQuickAccessMotion, NotchBackdropPresentation) -> AnyView) {
        self.canvas = canvas
        let motion = NotchQuickAccessMotion()
        self.motion = motion
        quickView = NSHostingView(rootView: content(motion, canvas.backdropPresentation))
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
        stage = NotchStage.size(including: CGSize(width: max(stage.width, bounds.width), height: max(stage.height, bounds.height)))
        let stageFrame = NotchStage.frame(stage, in: bounds)
        if quickView.frame != stageFrame { quickView.frame = stageFrame }
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
        guard canvas.containsVisiblePoint(canvas.convert(local, from: self))
                || motion.contains(quickView.convert(local, from: self)) else { return nil }
        return super.hitTest(point)
    }
}

/// CADisplayLink retains its target; the weak forwarding object lets an ordered
/// out or destroyed canvas release its scheduler even mid-animation.
private final class NotchBackdropTick: NSObject {
    weak var canvas: NotchCanvas?
    init(canvas: NotchCanvas) { self.canvas = canvas }
    /// SwiftUI's drawing of what is set now reaches the screen the frame after
    /// the one being prepared, so the material aims one frame further.
    @objc func fire(_ sender: CADisplayLink) {
        canvas?.advanceBackdrop(to: sender.targetTimestamp + (sender.targetTimestamp - sender.timestamp))
    }
}

private final class NotchCanvas: NSView {
    private let host: NotchHostingView
    private let backdrop: NotchHostingView
    let backdropPresentation = NotchBackdropPresentation()
    /// The backdrop keeps one width, centred on the island, so resizing the
    /// reserved area never moves what SwiftUI drew. Sized with the canvas,
    /// the material stayed a frame at its old place when the window grew to
    /// open, cutting the island in half.
    private var stage = CGSize.zero
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
    private(set) var outline = NotchSilhouette.current()
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    /// Switching outlines redraws the resting island at once.
    func setOutline(_ next: NotchSilhouette) {
        guard outline != next else { return }
        outline = next
        stopMotion()
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

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
        layer?.backgroundColor = NSColor.black.cgColor
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
    var contentProbeBlurred: Bool { host.layer?.filters?.isEmpty == false }
    var contentProbeGrowing: Bool { host.layer?.animation(forKey: Self.arrivalScaleKey) != nil }
    /// How far growing content's top centre has left the island's.
    var contentProbeGrowthDrift: CGFloat {
        guard let layer = host.layer, let transform = layer.presentation()?.transform else { return 0 }
        let anchor = CGPoint(x: layer.anchorPoint.x * layer.bounds.width, y: layer.anchorPoint.y * layer.bounds.height)
        let top = CGPoint(x: layer.bounds.midX, y: layer.contentsAreFlipped() ? layer.bounds.minY : layer.bounds.maxY)
        let x = (top.x - anchor.x) * transform.m11 + (top.y - anchor.y) * transform.m21 + transform.m41 + anchor.x
        let y = (top.x - anchor.x) * transform.m12 + (top.y - anchor.y) * transform.m22 + transform.m42 + anchor.y
        return hypot(x - top.x, y - top.y)
    }
    var backdropProbeFrame: CGRect { backdropPresentation.contour.boundingRect }
    var backdropProbeFollowsSilhouette: Bool {
        visiblePath.map { backdropPresentation.contour == backdropContour($0) } ?? false
    }
    var backdropProbeIndependent: Bool {
        host.layer?.mask === contentVisibility && backdrop.layer?.mask == nil
            && (backdrop.layer?.presentation()?.opacity ?? backdrop.layer?.opacity) == 1
    }
#endif

    var hostedSize: CGSize { host.frame.size }
    var contentTopInWindow: CGPoint { host.convert(.zero, to: nil) }

    private static let motionKey = "notch.resize"
    private static let departureKey = "notchDeparture"
    var departsContent: Bool {
        contentVisibility.animation(forKey: "notch.opacity")?.value(forKey: Self.departureKey) as? Bool == true
    }
    /// A resting silhouette shows its model path. Until that path is
    /// committed, the presentation layer still describes the previous one,
    /// and a resize starting there would replay a size already left.
    var visiblePath: CGPath? {
        guard silhouette.animation(forKey: Self.motionKey) != nil else { return silhouette.path.map(inCanvas) }
        return (silhouette.presentation()?.path ?? silhouette.path).map(inCanvas)
    }

    /// A mask path in the canvas's coordinates.
    private func inCanvas(_ path: CGPath) -> CGPath {
        var offset = CGAffineTransform(translationX: silhouette.frame.minX, y: 0)
        return path.copy(using: &offset) ?? path
    }

    /// The island's size as drawn, from the top edge: a floating capsule
    /// still counts the space above it, as its window and hover do.
    func surfaceSize(of path: CGPath) -> CGSize {
        let box = path.boundingBoxOfPath
        let height = max(0, box.maxY)
        guard outline.gap > 0 else { return CGSize(width: box.width, height: height) }
        return CGSize(width: box.width + 2 * min(NotchLayout.capsuleSide(height: height), box.width), height: height)
    }

    var visibleSize: CGSize? { visiblePath.map(surfaceSize) }

    /// Clicks in the space above a floating capsule still reach it, as they
    /// reach the top of the attached island.
    func containsVisiblePoint(_ point: CGPoint) -> Bool {
        guard let path = visiblePath else { return false }
        if path.contains(point) { return true }
        let box = path.boundingBoxOfPath
        return outline.gap > 0 && !box.isEmpty && point.y >= 0 && point.y <= box.minY + 1
            && point.x >= box.minX && point.x <= box.maxX
    }

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

    /// Where the island of a size starts in this canvas, from the window host.
    var islandMinX: ((CGSize) -> CGFloat?)?
    /// The display's centre in this canvas: the stages hang from this fixed
    /// point, so no size of the island or of its window moves them.
    var stageCentreX: (() -> CGFloat?)?

    private func islandX(_ size: CGSize) -> CGFloat {
        islandMinX?(size) ?? (bounds.width - size.width) / 2
    }

    /// The island's silhouette at `size`, at its place in the reserved area,
    /// in the mask layer's own coordinates.
    func silhouettePath(for size: CGSize) -> CGPath {
        var translation = CGAffineTransform(translationX: islandX(size) - silhouette.frame.minX, y: 0)
        let path = NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: size.height),
                              floatingGap: outline.gap)
            .path(in: CGRect(origin: .zero, size: size)).cgPath
        return path.copy(using: &translation) ?? path
    }

    /// The resize the silhouette is running, to draw the material for the
    /// frame about to be shown rather than the one already on screen.
    private var motionTimeline: (begin: CFTimeInterval, from: CGSize, to: CGSize)?
    var motionProbeStart: CGSize? { motionTimeline?.from }

    func animate(_ animation: CAAnimation, from: CGPath?, motion: (from: CGSize, to: CGSize)? = nil) {
        motionStart = nil
        motionTimeline = motion.map { (animation.beginTime > 0 ? animation.beginTime : CACurrentMediaTime(), $0.from, $0.to) }
        silhouette.path = silhouettePath(for: contentSize)
        edge.path = silhouette.path
        silhouette.add(animation, forKey: Self.motionKey)
        if let from { setBackdropContour(inCanvas(from)) }
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
        motionTimeline = nil
        silhouette.removeAnimation(forKey: Self.motionKey)
        edge.removeAnimation(forKey: Self.motionKey)
        backdropDisplayLink?.invalidate()
        backdropDisplayLink = nil
    }

    var usesGlass: Bool { backdropPresentation.usesGlass }

    func setUsesGlass(_ enabled: Bool) {
        guard usesGlass != enabled else { return }
        backdropPresentation.usesGlass = enabled
        updateCanvasBlack()
    }

    /// The island's black is also the canvas's own fill, not only the
    /// SwiftUI backdrop's, which reaches the screen a frame late whenever it
    /// changes: left to the backdrop alone, the island could vanish for a
    /// frame as it began to open or settled after closing. Under glass the
    /// fill gives way as the backdrop's resting black does.
    func updateCanvasBlack() {
        let alpha = usesGlass ? CGFloat(backdropPresentation.restingBlack) : 1
        let color = NSColor.black.withAlphaComponent(alpha).cgColor
        guard layer?.backgroundColor != color else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = color
        CATransaction.commit()
    }

    /// SwiftUI draws the material a frame after it is told, while the mask
    /// moves in step with the screen. Following the frame on screen, the
    /// material trailed the opening island by a frame, and its clear lower
    /// glass showed without the dark gradient meant to cover it.
    fileprivate func advanceBackdrop(to target: CFTimeInterval) {
        backdropTicks += 1
        guard let timeline = motionTimeline else { synchronizeBackdrop(); return }
        let size = NotchMotion.size(at: max(0, target - timeline.begin), from: timeline.from, to: timeline.to)
        setBackdropContour(inCanvas(silhouettePath(for: size)))
    }

    /// The size shown while a resize is being prepared, before its motion.
    var motionStart: CGSize?

    fileprivate func synchronizeBackdrop() {
        // Immediately use the final model path after stopping the scheduler;
        // the presentation layer can still describe the preceding frame until
        // Core Animation commits this transaction.
        let path = backdropDisplayLink == nil ? silhouette.path.map(inCanvas) : visiblePath
        if let path { setBackdropContour(path) }
    }

    /// A canvas path in the backdrop's own coordinates.
    private func backdropContour(_ path: CGPath) -> Path {
        var offset = CGAffineTransform(translationX: -backdrop.frame.minX, y: 0)
        return Path(path.copy(using: &offset) ?? path)
    }

    private func setBackdropContour(_ path: CGPath) {
        let contour = backdropContour(path)
        guard backdropPresentation.contour != contour else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { backdropPresentation.contour = contour }
        updateCanvasBlack()
    }

    deinit { backdropDisplayLink?.invalidate() }

    func transitionContent(_ kind: NotchContentTransition, shapeSnaps: Bool = false) {
        guard kind != .none else { return }
        let currentOpacity = contentVisibility.presentation()?.opacity ?? contentVisibility.opacity
        let presentedArrival = self.presentedArrival
        contentVisibility.removeAnimation(forKey: "notch.opacity")
        host.layer?.removeAnimation(forKey: kCATransition)
        endArrival()
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
            // content; content arriving small and out of focus can show
            // sooner than sharp content could. Reversals continue from the
            // opacity already on screen. A shape that snaps into place only
            // needs its first frames drawn.
            let keyTimes: [NSNumber] = kind == .dismiss ? [0, 0.65, 1] : shapeSnaps ? [0, 0.25, 1] : [0, 0.35, 1]
            let duration: CFTimeInterval = kind == .dismiss ? 0.40 : shapeSnaps ? 0.2 : 0.45
            animation.values = [start, start, 1]
            animation.keyTimes = keyTimes
            animation.duration = duration
            animation.calculationMode = .linear
            animation.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)]
            if kind == .depart {
                // Departing content shrinks with the shape and stays hidden
                // until the view has swapped it out, however late that is.
                animation.values = [currentOpacity, 0]
                animation.keyTimes = [0, 1]
                animation.duration = 0.16
                animation.timingFunctions = [CAMediaTimingFunction(name: .easeIn)]
                animation.fillMode = .forwards
                animation.isRemovedOnCompletion = false
                animation.setValue(true, forKey: Self.departureKey)
            }
            contentVisibility.opacity = 1
            contentVisibility.add(animation, forKey: "notch.opacity")
            // A fade is not motion; a shape that snaps into place brings no
            // blur or growth, and departing content only leaves.
            if !shapeSnaps, kind != .depart {
                beginArrival(opening: kind == .reveal, keyTimes: keyTimes, duration: duration,
                             resuming: start > 0 ? presentedArrival ?? (blur: 0, scale: 1) : nil)
            }
        }
        CATransaction.commit()
    }

    func finishDeparture() {
        guard departsContent else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        // The swapped view reaches the screen with a later update.
        animation.beginTime = CACurrentMediaTime() + 0.06
        animation.fillMode = .backwards
        animation.duration = 0.14
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        contentVisibility.removeAnimation(forKey: "notch.opacity")
        contentVisibility.add(animation, forKey: "notch.opacity")
        CATransaction.commit()
    }

    func restoreContent() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentVisibility.removeAnimation(forKey: "notch.opacity")
        contentVisibility.opacity = 1
        host.layer?.removeAnimation(forKey: kCATransition)
        CATransaction.commit()
        endArrival()
    }

    /// Content arrives out of focus, and an opening page a little small, and
    /// both settle with the island, as the phone's island brings its content in.
    private struct Arrival {
        let begin: CFTimeInterval
        let duration: CFTimeInterval
        let scale: CGFloat
        /// The hosting layer's width the growth was centred for.
        var width: CGFloat = 0
    }

    private static let arrivalBlurName = "notchArrival"
    private static let arrivalBlurKey = "notch.arrival.blur"
    private static let arrivalScaleKey = "notch.arrival.scale"
    private var arrival: Arrival?
    private var arrivalGeneration = 0

    /// Core Animation's own blur, which the window server renders with the
    /// rest of the island; a Core Image filter would need the hosting view's
    /// whole layer tree rendered in this process. Without it, content only
    /// fades and grows in.
    private static func makeArrivalBlur() -> NSObject? {
        let make = NSSelectorFromString("filterWithType:")
        guard let type = NSClassFromString("CAFilter") as? NSObject.Type, type.responds(to: make),
              let filter = type.perform(make, with: "gaussianBlur")?.takeUnretainedValue() as? NSObject else { return nil }
        filter.setValue(arrivalBlurName, forKey: "name")
        filter.setValue(0, forKey: "inputRadius")
        return filter
    }

    /// The blur and growth on screen while content is still arriving.
    private var presentedArrival: (blur: CGFloat, scale: CGFloat)? {
        guard arrival != nil || host.layer?.animation(forKey: Self.arrivalBlurKey) != nil,
              let presentation = host.layer?.presentation() else { return nil }
        let blur = presentation.value(forKeyPath: "filters.\(Self.arrivalBlurName).inputRadius") as? NSNumber
        return (CGFloat(blur?.doubleValue ?? 0), presentation.transform.m11)
    }

    private func beginArrival(opening: Bool, keyTimes: [NSNumber], duration: CFTimeInterval,
                              resuming: (blur: CGFloat, scale: CGFloat)?) {
        guard let layer = host.layer else { return }
        arrivalGeneration += 1
        let generation = arrivalGeneration
        let begin = layer.convertTime(CACurrentMediaTime(), from: nil)
        let radius = resuming?.blur ?? (opening ? 12 : 6)
        if radius > 0, let filter = Self.makeArrivalBlur() {
            layer.filters = [filter]
            let blur = CAKeyframeAnimation(keyPath: "filters.\(Self.arrivalBlurName).inputRadius")
            blur.values = [radius, opening ? radius / 2 : radius, 0]
            blur.keyTimes = keyTimes
            blur.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)]
            blur.beginTime = begin
            blur.duration = duration
            layer.add(blur, forKey: Self.arrivalBlurKey)
        }
        let scale = resuming?.scale ?? (opening ? 0.86 : 1)
        if scale != 1 {
            arrival = Arrival(begin: begin, duration: duration, scale: scale)
            installArrivalScale()
        }
        // A filter left in place, even at no radius, keeps an extra render pass.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.arrivalGeneration == generation else { return }
            self.endArrival()
        }
    }

    /// Content grows from the island's top centre, which moves within the
    /// hosting layer whenever the reserved area changes width, so the
    /// growth is centred again for each width.
    private func installArrivalScale() {
        guard var arrival, let layer = host.layer,
              layer.convertTime(CACurrentMediaTime(), from: nil) < arrival.begin + arrival.duration else { return }
        arrival.width = layer.bounds.width
        self.arrival = arrival
        let growth = CABasicAnimation(keyPath: "transform")
        growth.fromValue = NSValue(caTransform3D: arrivalTransform(scale: arrival.scale, in: layer))
        growth.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        growth.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        growth.beginTime = arrival.begin
        growth.duration = arrival.duration
        layer.add(growth, forKey: Self.arrivalScaleKey)
    }

    private func arrivalTransform(scale: CGFloat, in layer: CALayer) -> CATransform3D {
        let anchor = CGPoint(x: layer.anchorPoint.x * layer.bounds.width, y: layer.anchorPoint.y * layer.bounds.height)
        let top = layer.contentsAreFlipped() ? layer.bounds.minY : layer.bounds.maxY
        let offset = CGPoint(x: layer.bounds.midX - anchor.x, y: top - anchor.y)
        let transform = CATransform3DScale(CATransform3DMakeTranslation(offset.x, offset.y, 0), scale, scale, 1)
        return CATransform3DTranslate(transform, -offset.x, -offset.y, 0)
    }

    private func endArrival() {
        arrivalGeneration += 1
        arrival = nil
        guard let layer = host.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: Self.arrivalBlurKey)
        layer.removeAnimation(forKey: Self.arrivalScaleKey)
        if layer.filters?.isEmpty == false { layer.filters = nil }
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
        stage = NotchStage.size(including: CGSize(width: max(stage.width, bounds.width), height: max(stage.height, bounds.height)))
        let centre = stageCentreX?() ?? bounds.midX
        // The mask keeps the stage's size too: resized with the window, it was
        // drawn anew for the new bounds and could come up empty for the frame
        // the window changed, hiding the whole island as it began to open.
        let maskFrame = CGRect(x: centre - stage.width / 2, y: 0, width: stage.width, height: stage.height)
        if silhouette.frame != maskFrame {
            silhouette.frame = maskFrame
            edge.frame = maskFrame
        }
        silhouette.path = silhouettePath(for: motionStart ?? contentSize)
        edge.path = silhouette.path
        edge.opacity = contentSize.height > 64 ? 1 : 0
        // Keep foreground layout fixed inside the reserved reveal area. Only
        // the separate backdrop's contour changes on animation frames.
        // A floating capsule starts below the top edge; its content keeps
        // the middle of the capsule, not of the strip above it.
        var hostFrame = NotchStage.frame(stage, in: bounds, dy: (outline.gap / 2).rounded(.down))
        hostFrame.origin.x = centre - stage.width / 2
        if host.frame != hostFrame { host.frame = hostFrame }
        contentVisibility.frame = host.bounds
        if let arrival, arrival.width != host.layer?.bounds.width { installArrivalScale() }
        var backdropFrame = NotchStage.frame(stage, in: bounds)
        backdropFrame.origin.x = hostFrame.minX
        if backdrop.frame != backdropFrame { backdrop.frame = backdropFrame }
        synchronizeBackdrop()
        activationButton.frame = activationRect.offsetBy(dx: islandX(contentSize), dy: 0)
        let hoverRect = CGRect(x: islandX(contentSize), y: 0, width: contentSize.width, height: contentSize.height)
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
