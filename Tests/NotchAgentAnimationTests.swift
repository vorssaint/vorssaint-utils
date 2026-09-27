// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

enum NotchAgentAnimationTests {
    private final class Window: NSWindow {
        var shown = true
        var exposed = true
        override var isVisible: Bool { shown }
        override var occlusionState: NSWindow.OcclusionState { exposed ? [.visible] : [] }
        func notifyVisibility() {
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: self)
        }
    }

    static func run(expect: (Bool, String) -> Void) {
        let window = Window(contentRect: CGRect(x: 0, y: 0, width: 40, height: 40),
                            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: window.frame)
        window.contentView = container
        let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        for pulse in [false, true] {
            let view = NotchAgentAnimationView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
            func configure(_ animates: Bool = true, tint: NSColor = .white) {
                if pulse { view.configurePulse(size: 6, tint: tint, animates: animates) }
                else { view.configureGlyph(image: image, size: 13, tint: tint, animates: animates) }
            }
            func animations(_ layer: CALayer? = nil) -> [CAAnimationGroup] {
                guard let layer = layer ?? view.layer else { return [] }
                return (layer.animationKeys() ?? []).compactMap { layer.animation(forKey: $0) as? CAAnimationGroup }
                    + (layer.sublayers ?? []).flatMap { animations($0) }
            }
            configure()
            expect(animations().isEmpty, "unattached agent artwork does not animate")
            container.addSubview(view)
            expect(animations().count == 1, "visible agent artwork starts one compositor animation")
            let started = animations().first?.beginTime
            configure(tint: .red)
            view.layout()
            expect(animations().first?.beginTime == started, "agent updates preserve the animation phase")
            if let animation = animations().first {
                expect(animation.delegate == nil && animation.repeatCount.isInfinite,
                       "agent motion has no repeating callbacks in the app")
                expect(animation.duration == (pulse ? 1.6 : 1.2) && animation.autoreverses == !pulse,
                       "agent motion retains its original rhythm")
                expect(animation.animations?.count == 2 && animation.animations?.allSatisfy { $0.duration == animation.duration } == true,
                       "both scale and opacity animate over the full cycle")
            }
            expect(view.hitTest(.zero) == nil && !view.isAccessibilityElement(),
                   "agent decorations do not intercept clicks or accessibility")
            configure(false)
            expect(animations().isEmpty, "idle agents and Reduce Motion stop decorative motion")
            configure()
            window.exposed = false
            window.notifyVisibility()
            expect(animations().isEmpty, "fully covered agent pages stop animation")
            window.exposed = true
            window.notifyVisibility()
            expect(animations().count == 1, "uncovering agent pages restores animation")
            window.shown = false
            window.notifyVisibility()
            configure()
            expect(animations().isEmpty, "closed Settings stay stopped across agent updates")
            window.shown = true
            window.notifyVisibility()
            expect(animations().count == 1, "reopening Settings restores agent motion")
            container.isHidden = true
            expect(animations().isEmpty, "hidden ancestors stop agent motion")
            container.isHidden = false
            expect(animations().count == 1, "visible ancestors restore agent motion")
            view.removeFromSuperview()
            expect(animations().isEmpty, "removing agent artwork ends its animations")
            container.addSubview(view)
            view.stop()
            window.notifyVisibility()
            expect(animations().isEmpty, "dismantled agent artwork stays stopped")
            view.removeFromSuperview()
        }
        weak var released: NotchAgentAnimationView?
        autoreleasepool {
            let view = NotchAgentAnimationView(frame: .zero)
            released = view
            container.addSubview(view)
            view.removeFromSuperview()
        }
        expect(released == nil, "visibility observation does not retain discarded agent artwork")
    }
}
