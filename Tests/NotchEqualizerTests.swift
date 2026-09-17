// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

enum NotchEqualizerTests {
    /// Real native views and layers, with visibility supplied by a window
    /// that is never ordered onscreen. No player or user preference is touched.
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
        let window = Window(contentRect: CGRect(x: 0, y: 0, width: 80, height: 40),
                            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 80, height: 40))
        window.contentView = container
        let view = NotchEqualizerView(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        func configure(_ animates: Bool = true, count: Int = 7, width: CGFloat = 2,
                       height: CGFloat = 20, tint: NSColor = .white) {
            view.configure(animates: animates, bars: count, barWidth: width, height: height, tint: tint)
        }
        func layers() -> [CALayer] { view.layer?.sublayers ?? [] }
        func animations() -> [CABasicAnimation] {
            layers().flatMap { bar in
                (bar.animationKeys() ?? []).compactMap { bar.animation(forKey: $0) as? CABasicAnimation }
            }
        }
        func isStopped() -> Bool {
            layers().allSatisfy { ($0.animationKeys() ?? []).isEmpty && $0.bounds.height == $0.bounds.width }
        }

        configure()
        expect(isStopped(), "unattached music bars do not animate")
        container.addSubview(view)
        expect(!animations().isEmpty, "visible playing music starts native bar motion")
        expect(view.hitTest(.zero) == nil && !view.isAccessibilityElement(),
               "decorative bars do not intercept the music button or accessibility")
        let original = layers()
        let starts = animations().map(\.beginTime)
        configure(tint: .red)
        view.layout()
        expect(zip(original, layers()).allSatisfy { $0 === $1 } && animations().map(\.beginTime) == starts,
               "metadata, tint and layout changes preserve bar layers and animation phase")
        expect(layers().allSatisfy { $0.backgroundColor == NSColor.red.cgColor },
               "a new artwork tint updates every bar without restarting motion")
        expect(animations().allSatisfy { $0.delegate == nil && $0.repeatCount.isInfinite },
               "native bar motion repeats without per-cycle app callbacks")

        configure(false)
        expect(isStopped(), "pause or reduced motion removes animations and returns bars to dots")
        configure()
        expect(!animations().isEmpty, "playback resumes motion after a pause")
        window.exposed = false
        window.notifyVisibility()
        expect(isStopped(), "fully occluded windows stop music animation")
        window.exposed = true
        window.notifyVisibility()
        expect(!animations().isEmpty, "visible windows resume playing music animation")
        window.shown = false
        window.notifyVisibility()
        configure()
        expect(isStopped(), "ordered-out islands stay stopped across metadata updates")
        window.shown = true
        window.notifyVisibility()
        container.isHidden = true
        expect(isStopped(), "hiding an ancestor stops music animation")
        container.isHidden = false
        expect(!animations().isEmpty, "unhiding an ancestor resumes music animation")

        for count in [1, 3, 4, 7] {
            configure(count: count, width: 1.8, height: 14)
            expect(layers().count == count, "changing the music indicator replaces obsolete bars")
            let width = CGFloat(count) * 1.8 + CGFloat(count - 1) * 1.8 * 0.85
            for bar in layers() {
                expect(bar.frame.minX >= 0 && bar.frame.maxX <= width + 0.0001 && bar.position.y == view.bounds.midY,
                       "music bars retain their spacing and vertical center in every presentation")
            }
            for animation in animations() {
                let low = (animation.fromValue as? NSNumber)?.doubleValue ?? -1
                let high = (animation.toValue as? NSNumber)?.doubleValue ?? -1
                expect(low >= 1.8 && high <= 14 && high > low && animation.autoreverses,
                       "music motion stays within its reserved height with rounded ends")
            }
        }
        view.removeFromSuperview()
        expect(isStopped(), "removing the music surface ends its animations")
        container.addSubview(view)
        expect(!animations().isEmpty, "reattaching a playing surface resumes its motion")
        view.stop()
        window.notifyVisibility()
        expect(isStopped(), "dismantled music bars stay stopped after visibility notifications")
        view.removeFromSuperview()
        weak var released: NotchEqualizerView?
        autoreleasepool {
            let transient = NotchEqualizerView(frame: .zero)
            released = transient
            container.addSubview(transient)
            transient.removeFromSuperview()
        }
        expect(released == nil, "visibility observation does not retain discarded music surfaces")
    }
}
