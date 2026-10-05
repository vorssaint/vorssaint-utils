// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// The drop that carries the Command Bar out of the Dynamic Island, in a
/// window of its own at the island's level. `CommandBarDropletMotion` works
/// out every frame once. Core Animation plays them, and the app only hears
/// when the drop has landed. The companion rides inside, live.
final class CommandBarDroplet {
    static let shared = CommandBarDroplet()

    private var panel: OverlayPanel?
    private let stage = CALayer()
    private let neck = CAShapeLayer()
    private let bead = CALayer()
    private let mascot = NotchMascotRig()
    private var generation = 0
    /// Where the last drop fell from, for the bar to rise back there.
    private var island: CGRect?
    /// A drop still on its way: closed meanwhile, the bar was never seen,
    /// so nothing rises back.
    private var falling = false

    private init() {
        stage.isGeometryFlipped = true
        neck.fillColor = NSColor.black.cgColor
        bead.backgroundColor = NSColor.black.cgColor
        bead.cornerCurve = .continuous
        for layer in [stage, neck, bead] {
            layer.actions = ["position": NSNull(), "bounds": NSNull(), "path": NSNull(), "cornerRadius": NSNull(),
                             "opacity": NSNull(), "frame": NSNull()]
        }
        stage.addSublayer(neck)
        stage.addSublayer(bead)
        stage.addSublayer(mascot.root)
    }

    private static var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Lets the drop fall from `island` into the bar's frame `bar`, both on
    /// screen. `revealed` runs once it has opened into the field, for the bar
    /// itself to take its place.
    func drop(from island: CGRect, into bar: CGRect, look: NotchMascotLook, revealed: @escaping () -> Void) {
        cancel()
        self.island = island
        // The companion goes into the drop, and the island rests without it.
        NotchService.shared.setMascotInBar(true)
        guard !Self.reducesMotion else { revealed(); return }
        let current = generation
        falling = true
        let field = CGRect(x: bar.minX, y: bar.maxY - CommandBarView.fieldHeight,
                           width: bar.width, height: CommandBarView.fieldHeight)
        let area = Self.area(island: island, reaching: field)
        let local = Self.local(area)
        let edge = CommandBarDropletMotion.rootDepth
        let centerX = island.midX - area.minX
        let fieldRect = local(field)
        let icon = CGPoint(x: fieldRect.minX + 16 + CommandBarDropletMotion.mascotSize / 2, y: fieldRect.midY)
        let motion = CommandBarDropletMotion.drop(edge: edge, centerX: centerX, field: fieldRect, icon: icon)
        let begin = CACurrentMediaTime()
        prepare(in: area, look: look, mood: .surprised)
        mascot.turn(to: .idle, at: begin + motion.landing)
        play(motion, edge: edge, centerX: centerX, begin: begin, completion: nil)
        // The bar takes over once the shape has all but arrived, and the
        // drop fades through the last of its swing on top of it.
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.generation == current else { return }
            self.falling = false
            revealed()
            self.fadeOut(current)
        }
        let wait = CABasicAnimation(keyPath: "opacity")
        wait.fromValue = 1
        wait.toValue = 1
        wait.beginTime = begin
        wait.duration = max(0.01, motion.reveal)
        stage.add(wait, forKey: "reveal")
        CATransaction.commit()
    }

    /// Folds the bar at `bar` back into a drop that rises into the island.
    /// The bar's window is already gone. This draws its shape on the way.
    func retract(from bar: CGRect, look: NotchMascotLook, mood: NotchMascotMood) {
        let unseen = falling
        cancel()
        guard !unseen, !Self.reducesMotion, let island = NotchService.shared.commandBarDropSource() ?? island else {
            NotchService.shared.setMascotInBar(false)
            return
        }
        let current = generation
        let field = CGRect(x: bar.minX, y: bar.maxY - CommandBarView.fieldHeight,
                           width: bar.width, height: CommandBarView.fieldHeight)
        let area = Self.area(island: island, reaching: bar)
        let local = Self.local(area)
        let edge = CommandBarDropletMotion.rootDepth
        let centerX = island.midX - area.minX
        let fieldRect = local(field)
        let icon = CGPoint(x: fieldRect.minX + 16 + CommandBarDropletMotion.mascotSize / 2, y: fieldRect.midY)
        let motion = CommandBarDropletMotion.retract(edge: edge, centerX: centerX, bar: local(bar), field: fieldRect, icon: icon)
        prepare(in: area, look: look, mood: mood)
        play(motion, edge: edge, centerX: centerX, begin: CACurrentMediaTime()) { [weak self] in
            guard let self, self.generation == current else { return }
            self.panel?.orderOut(nil)
            // Back in the island, it hops out to rest there again.
            NotchService.shared.setMascotInBar(false, homecoming: mood)
        }
    }

    /// Stops whatever is falling or rising and takes the window away.
    func cancel() {
        generation += 1
        falling = false
        for layer in [stage, neck, bead, mascot.root] { layer.removeAllAnimations() }
        panel?.orderOut(nil)
    }

    // MARK: Drawing

    /// The window spans the island's lower edge, a little inside it, down to
    /// below the bar, with room around for the spring to swing.
    private static func area(island: CGRect, reaching target: CGRect) -> CGRect {
        let margin: CGFloat = 28
        let minX = min(island.minX, target.minX) - margin
        let maxX = max(island.maxX, target.maxX) + margin
        let top = island.minY + CommandBarDropletMotion.rootDepth
        let bottom = target.minY - margin
        return CGRect(x: minX, y: bottom, width: maxX - minX, height: max(1, top - bottom))
    }

    /// Screen rectangles in the window's own points, from its top left.
    private static func local(_ area: CGRect) -> (CGRect) -> CGRect {
        { rect in CGRect(x: rect.minX - area.minX, y: area.maxY - rect.maxY, width: rect.width, height: rect.height) }
    }

    private func ensurePanel() -> OverlayPanel {
        if let panel { return panel }
        let panel = OverlayPanel(contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        // Level with the island, so the drop grows out of its edge.
        panel.level = NotchPanel.normalLevel
        panel.collectionBehavior = NotchPanel.overlayCollectionBehavior
        let view = NSView(frame: panel.contentLayoutRect)
        let root = CALayer()
        root.actions = ["sublayers": NSNull(), "bounds": NSNull(), "position": NSNull()]
        view.layer = root
        view.wantsLayer = true
        root.addSublayer(stage)
        panel.contentView = view
        self.panel = panel
        return panel
    }

    private func prepare(in area: CGRect, look: NotchMascotLook, mood: NotchMascotMood) {
        let panel = ensurePanel()
        panel.sharingType = NotchSupport.showsInCaptures() ? .readOnly : .none
        panel.setFrame(area, display: false)
        let scale = NSScreen.screens.first { $0.frame.intersects(area) }?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.frame = CGRect(origin: .zero, size: area.size)
        stage.opacity = 1
        stage.contentsScale = scale
        neck.frame = stage.bounds
        neck.contentsScale = scale
        bead.contentsScale = scale
        mascot.configure(look: look, size: CommandBarDropletMotion.mascotSize, contentsScale: scale)
        mascot.reset(to: mood)
        CATransaction.commit()
        // Under the island: the drop grows out from behind its edge and rises
        // back behind it, as liquid it holds.
        NotchService.shared.orderBelowIsland(panel)
    }

    private func play(_ motion: CommandBarDropletMotion, edge: CGFloat, centerX: CGFloat, begin: CFTimeInterval,
                      completion: (() -> Void)?) {
        guard let last = motion.frames.last, motion.duration > 0 else { completion?(); return }
        let times = motion.keyTimes.map { NSNumber(value: $0) }
        func animation(_ key: String, _ values: [Any]) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: key)
            animation.values = values
            animation.keyTimes = times
            animation.duration = motion.duration
            animation.beginTime = begin
            animation.calculationMode = .linear
            animation.fillMode = .backwards
            return animation
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let completion { CATransaction.setCompletionBlock(completion) }
        neck.add(animation("path", motion.frames.map {
            CommandBarDropletMotion.neckPath($0, edge: edge, centerX: centerX)
        }), forKey: "drop")
        bead.add(animation("bounds", motion.frames.map { NSValue(rect: CGRect(origin: .zero, size: $0.bead.size)) }),
                 forKey: "dropBounds")
        bead.add(animation("position", motion.frames.map { NSValue(point: CGPoint(x: $0.bead.midX, y: $0.bead.midY)) }),
                 forKey: "dropPosition")
        bead.add(animation("cornerRadius", motion.frames.map { NSNumber(value: Double($0.radius)) }), forKey: "dropRadius")
        mascot.root.add(animation("position", motion.frames.map { NSValue(point: $0.mascot) }), forKey: "dropPosition")
        mascot.root.add(animation("transform", motion.frames.map {
            NSValue(caTransform3D: CATransform3DMakeScale($0.mascotScale, $0.mascotScale, 1))
        }), forKey: "dropScale")
        // Where the last frame leaves everything, once the animations are gone.
        neck.path = CommandBarDropletMotion.neckPath(last, edge: edge, centerX: centerX)
        bead.bounds = CGRect(origin: .zero, size: last.bead.size)
        bead.position = CGPoint(x: last.bead.midX, y: last.bead.midY)
        bead.cornerRadius = last.radius
        mascot.root.position = last.mascot
        mascot.root.transform = CATransform3DMakeScale(last.mascotScale, last.mascotScale, 1)
        CATransaction.commit()
    }

    /// The bar is in place under the drop, and the drop fades off it.
    private func fadeOut(_ current: Int) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.generation == current else { return }
            self.panel?.orderOut(nil)
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.14
        stage.add(fade, forKey: "fade")
        stage.opacity = 0
        CATransaction.commit()
    }
}
