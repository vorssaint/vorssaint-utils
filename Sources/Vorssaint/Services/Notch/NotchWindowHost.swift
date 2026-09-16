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
    private var settledActions: [() -> Void] = []
    private(set) var targetSize: CGSize
    private(set) var resizeCount = 0

    init(content: AnyView, geometry: NotchGeometry, size: CGSize,
         quickAccess: ((NotchQuickAccessMotion) -> AnyView)? = nil) {
        targetSize = size
        currentGeometry = geometry
        panel = NotchPanel(contentRect: geometry.frame(for: size),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        let mainCanvas = NotchCanvas(content: content, size: size)
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
        // Stationary and transient are mutually exclusive. Keep the island
        // anchored when the desktop is revealed, outside the system's window motion.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = quickAccessContainer ?? canvas
        canvas.layoutSubtreeIfNeeded()
        appliedFrame = panel.frame
    }

    func present(size: CGSize, geometry: NotchGeometry, animated: Bool, transitionContent: NotchContentTransition = .none,
                 quickAccess: NotchQuickAccessConfiguration? = nil) {
        canvas.updateContrast()
        let canAnimate = animated && panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let previousGutter = quickAccessConfiguration == nil ? 0 : NotchQuickAccessLayout.gutter
        let previousBottom: CGFloat = quickAccessConfiguration?.hasBottom == true ? NotchQuickAccessLayout.gutter : 0
        let previousFrame = currentGeometry.frame(for: CGSize(width: targetSize.width + previousGutter * 2, height: targetSize.height + previousBottom))
        let withdrawing = quickAccessConfiguration != nil && quickAccess == nil
        quickAccessConfiguration = quickAccessContainer == nil ? nil : quickAccess
        quickAccessAnimate = canAnimate
        if quickAccessConfiguration != nil { quickAccessNotchSize = size }
        if withdrawing { quickAccessContainer?.motion.setVisible(false, animated: canAnimate) }
        let gutter = quickAccessConfiguration == nil ? 0 : NotchQuickAccessLayout.gutter
        let bottom: CGFloat = quickAccessConfiguration?.hasBottom == true ? NotchQuickAccessLayout.gutter : 0
        let frame = geometry.frame(for: CGSize(width: size.width + gutter * 2, height: size.height + bottom))
        let changesFrame = size != targetSize
            || frame != previousFrame || (!isAnimating && panel.frame != appliedFrame)
        guard changesFrame || transitionContent != .none else {
            currentGeometry = geometry
            configureQuickAccess()
            if !isAnimating { quickAccessContainer?.motion.setVisible(quickAccessConfiguration != nil, animated: canAnimate) }
            return
        }
        if canAnimate { canvas.transitionContent(transitionContent) }
        else { canvas.restoreContent() }
        guard changesFrame else { configureQuickAccess(); return }
        let previousPath = canvas.visiblePath
        let previousWidth = canvas.bounds.width
        let sameScreen = geometry.screen == currentGeometry.screen
        animationGeneration += 1
        let generation = animationGeneration
        isAnimating = false
        canvas.stopMotion()
        targetSize = size
        currentGeometry = geometry
        resizeCount += 1
        guard canAnimate, sameScreen, let previousPath else {
            settle()
            return
        }

        let envelope = NotchMotion.envelope(from: canvas.bounds.size, to: size)
        let reservedGutter = max(quickAccessContainer?.gutter ?? 0, gutter)
        let reservedBottom = max(quickAccessContainer?.bottomInset ?? 0, bottom)
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
        canvas.animate(animation)
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
        isAnimating = false
        canvas.stopMotion()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.setContentSize(targetSize)
        setFrame(mainSize: targetSize, gutter: quickAccessConfiguration == nil ? 0 : NotchQuickAccessLayout.gutter,
                 bottom: quickAccessConfiguration?.hasBottom == true ? NotchQuickAccessLayout.gutter : 0)
        guard generation == animationGeneration else { CATransaction.commit(); return }
        configureQuickAccess()
        canvas.layoutSubtreeIfNeeded()
        guard generation == animationGeneration else { CATransaction.commit(); return }
        CATransaction.commit()
        quickAccessContainer?.motion.setVisible(quickAccessConfiguration != nil, animated: quickAccessAnimate)
        runSettledActions()
    }

    private func setFrame(mainSize: CGSize, gutter: CGFloat, bottom: CGFloat) {
        quickAccessContainer?.gutter = gutter
        quickAccessContainer?.bottomInset = bottom
        panel.setFrame(currentGeometry.frame(for: CGSize(width: mainSize.width + gutter * 2, height: mainSize.height + bottom)), display: false)
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
        let shoulder = min(NotchLayout.shoulder, targetSize.height * 0.28)
        let body = CGRect(x: (panel.frame.width - quickAccessNotchSize.width) / 2 + shoulder, y: 0,
                          width: quickAccessNotchSize.width - shoulder * 2, height: quickAccessNotchSize.height)
        container.motion.configure(configuration, body: body,
                                   headerTop: currentGeometry.safeContentTop + NotchLayout.headerHeight / 2,
                                   animated: quickAccessAnimate)
        container.setHoverRects(container.motion.hoverRects.map { $0.intersection(container.bounds) })
    }

    func setHoverHandler(_ handler: @escaping (Bool) -> Void) {
        canvas.hoverChanged = handler
        quickAccessContainer?.hoverChanged = handler
    }

    func containsHover(_ screenPoint: CGPoint) -> Bool {
        guard panel.isVisible else { return false }
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

    func contains(_ screenPoint: CGPoint) -> Bool {
        guard panel.isVisible else { return false }
        let local = canvas.convert(panel.convertPoint(fromScreen: screenPoint), from: nil)
        if canvas.containsVisiblePoint(local) { return true }
        guard let container = quickAccessContainer else { return false }
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
        canvas.stopMotion()
        quickAccessContainer?.motion.setVisible(false, animated: false)
        quickAccessContainer?.setHoverRects([])
        panel.orderOut(nil)
        panel.contentView = nil
        runSettledActions()
    }
}

final class NotchPanel: NSPanel {
    // Status items own the screen edge at their level, even when our view's
    // hit test includes it. Keep the island above them, below native menus.
    static let normalLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    var acceptsKeyFocus = false
    var handleScroll: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { acceptsKeyFocus }
    override var canBecomeMain: Bool { false }

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

private final class NotchCanvas: NSView {
    private let host: NotchHostingView
    private let activationButton = NotchActivationButton()
    private var activationRect = CGRect.zero
    private var hoverTrackingArea: NSTrackingArea?
    var hoverChanged: ((Bool) -> Void)?
    private let silhouette = CAShapeLayer()
    private let edge = CAShapeLayer()
    private let contentCover = CALayer()
    private var dropActions: NotchFileDropActions?
    private var acceptingDrag = false
    private var contentSize: CGSize
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init(content: AnyView, size: CGSize) {
        contentSize = size
        host = NotchHostingView(rootView: content)
        host.sizingOptions = []
        host.wantsLayer = true
        host.autoresizingMask = []
        super.init(frame: CGRect(origin: .zero, size: size))
        autoresizesSubviews = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        layer?.mask = silhouette
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
        contentCover.name = "notch.contentCover"
        contentCover.backgroundColor = NSColor.black.cgColor
        contentCover.opacity = 0
        contentCover.zPosition = 1
        layer?.addSublayer(contentCover)
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
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.45 : 0.12).cgColor
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

    func animate(_ animation: CAAnimation) {
        silhouette.add(animation, forKey: Self.motionKey)
        if let borderAnimation = animation.copy() as? CAAnimation {
            borderAnimation.delegate = nil
            edge.add(borderAnimation, forKey: Self.motionKey)
        }
    }
    func stopMotion() {
        silhouette.removeAnimation(forKey: Self.motionKey)
        edge.removeAnimation(forKey: Self.motionKey)
    }

    func transitionContent(_ kind: NotchContentTransition) {
        guard kind != .none else { return }
        let currentOpacity = contentCover.presentation()?.opacity ?? contentCover.opacity
        contentCover.removeAnimation(forKey: "notch.opacity")
        host.layer?.removeAnimation(forKey: kCATransition)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if kind == .replace {
            contentCover.opacity = 0
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.18
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            host.layer?.add(transition, forKey: kCATransition)
        } else {
            // Fade the pixels, not the hosting view: making that view
            // transparent also removes the compact button's AX/hit frame.
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            let start: Float = kind == .dismiss || currentOpacity == 0 ? 1 : currentOpacity
            // Give the silhouette a head start before revealing full-width
            // content. Reversals continue from the opacity already on screen.
            animation.values = [start, start, 0]
            animation.keyTimes = kind == .dismiss ? [0, 0.65, 1] : [0, 0.625, 1]
            animation.duration = 0.40
            animation.calculationMode = .linear
            animation.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)]
            contentCover.opacity = 0
            contentCover.add(animation, forKey: "notch.opacity")
        }
        CATransaction.commit()
    }

    func restoreContent() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentCover.removeAnimation(forKey: "notch.opacity")
        contentCover.opacity = 0
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
        contentCover.frame = bounds
        var translation = CGAffineTransform(translationX: (bounds.width - contentSize.width) / 2, y: 0)
        silhouette.path = NotchShape(attached: true, radius: min(28, contentSize.height / 2))
            .path(in: CGRect(origin: .zero, size: contentSize)).cgPath.copy(using: &translation)
        edge.path = silhouette.path
        edge.opacity = contentSize.height > 64 ? 1 : 0
        // Render the entire reveal area once; changing only the layer mask
        // then exposes cached pixels without redrawing SwiftUI every frame.
        if host.frame != bounds { host.frame = bounds }
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
