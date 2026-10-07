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
            func animationCount(_ layer: CALayer? = nil) -> Int {
                guard let layer = layer ?? view.layer else { return 0 }
                return (layer.animationKeys() ?? []).count + (layer.sublayers ?? []).reduce(0) { $0 + animationCount($1) }
            }
            /// The artwork, the dot and the ring, in the order the view adds them.
            func moving() -> CALayer? { view.layer?.sublayers?[pulse ? 2 : 0] }
            func look() -> (scale: CGFloat, opacity: Float) {
                (moving()?.transform.m11 ?? 0, moving()?.opacity ?? -1)
            }
            configure()
            expect(!view.isMoving, "unattached agent artwork does not animate")
            container.addSubview(view)
            expect(view.isMoving, "visible agent artwork starts its motion")
            expect(animationCount() == 0,
                   "agent motion leaves no repeating animation for the window server to draw at the display's rate")
            let started = view.motionStart
            configure(tint: .red)
            view.layout()
            expect(view.motionStart == started, "agent updates preserve the motion's phase")
            let period = pulse ? 1.6 : 2.4
            view.step(at: started)
            let first = look()
            view.step(at: started + period / 2)
            let middle = look()
            view.step(at: started + period * 1.5)
            let again = look()
            expect(abs(first.scale - (pulse ? 1 : 0.84)) < 0.001 && abs(first.opacity - (pulse ? 0.6 : 0.7)) < 0.001,
                   "agent motion starts where the animation it replaces did")
            expect(middle.scale > first.scale + 0.1 && (pulse ? middle.opacity < first.opacity : middle.opacity > first.opacity),
                   "both scale and opacity change over the cycle")
            expect(abs(again.scale - middle.scale) < 0.001 && abs(again.opacity - middle.opacity) < 0.001,
                   "agent motion retains its original rhythm")
            expect(view.hitTest(.zero) == nil && !view.isAccessibilityElement(),
                   "agent decorations do not intercept clicks or accessibility")
            configure(false)
            expect(!view.isMoving && look().scale == 1, "idle agents and Reduce Motion stop decorative motion")
            configure()
            window.exposed = false
            window.notifyVisibility()
            expect(!view.isMoving, "fully covered agent pages stop animation")
            window.exposed = true
            window.notifyVisibility()
            expect(view.isMoving, "uncovering agent pages restores animation")
            window.shown = false
            window.notifyVisibility()
            configure()
            expect(!view.isMoving, "closed Settings stay stopped across agent updates")
            window.shown = true
            window.notifyVisibility()
            expect(view.isMoving, "reopening Settings restores agent motion")
            container.isHidden = true
            expect(!view.isMoving, "hidden ancestors stop agent motion")
            container.isHidden = false
            expect(view.isMoving, "visible ancestors restore agent motion")
            view.removeFromSuperview()
            expect(!view.isMoving, "removing agent artwork ends its motion")
            container.addSubview(view)
            view.stop()
            window.notifyVisibility()
            expect(!view.isMoving, "dismantled agent artwork stays stopped")
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
