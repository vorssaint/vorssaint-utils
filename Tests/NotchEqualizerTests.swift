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
        func heights() -> [CGFloat] { layers().map(\.bounds.height) }
        func isStopped() -> Bool {
            !view.isMoving && layers().allSatisfy { $0.bounds.height == $0.bounds.width }
        }

        configure()
        expect(isStopped(), "unattached music bars do not animate")
        container.addSubview(view)
        expect(view.isMoving, "visible playing music starts the bars' motion")
        expect(layers().allSatisfy { ($0.animationKeys() ?? []).isEmpty },
               "music bars leave no repeating animation for the window server to draw at the display's rate")
        expect(NotchDecorativeClock.rate <= 30, "decorative motion steps at most thirty times a second")
        expect(view.hitTest(.zero) == nil && !view.isAccessibilityElement(),
               "decorative bars do not intercept the music button or accessibility")
        let original = layers()
        let started = view.motionStart
        configure(tint: .red)
        view.layout()
        expect(zip(original, layers()).allSatisfy { $0 === $1 } && view.motionStart == started,
               "metadata, tint and layout changes preserve bar layers and the motion's phase")
        expect(layers().allSatisfy { $0.backgroundColor == NSColor.red.cgColor },
               "a new artwork tint updates every bar without restarting motion")
        view.step(at: started + 0.1)
        let early = heights()
        view.step(at: started + 0.45)
        expect(heights() != early, "each step moves the playing bars")

        configure(false)
        expect(isStopped(), "pause or reduced motion stops the motion and returns bars to dots")
        configure()
        expect(view.isMoving, "playback resumes motion after a pause")
        window.exposed = false
        window.notifyVisibility()
        expect(isStopped(), "fully occluded windows stop music animation")
        window.exposed = true
        window.notifyVisibility()
        expect(view.isMoving, "visible windows resume playing music animation")
        window.shown = false
        window.notifyVisibility()
        configure()
        expect(isStopped(), "ordered-out islands stay stopped across metadata updates")
        window.shown = true
        window.notifyVisibility()
        container.isHidden = true
        expect(isStopped(), "hiding an ancestor stops music animation")
        container.isHidden = false
        expect(view.isMoving, "unhiding an ancestor resumes music animation")

        for count in [1, 3, 4, 7] {
            configure(count: count, width: 1.8, height: 14)
            expect(layers().count == count, "changing the music indicator replaces obsolete bars")
            let width = CGFloat(count) * 1.8 + CGFloat(count - 1) * 1.8 * 0.85
            var lowest = Array(repeating: CGFloat.infinity, count: count)
            var highest = Array(repeating: -CGFloat.infinity, count: count)
            for frame in 0...45 {
                view.step(at: view.motionStart + Double(frame) / 30)
                for (index, bar) in layers().enumerated() {
                    lowest[index] = min(lowest[index], bar.bounds.height)
                    highest[index] = max(highest[index], bar.bounds.height)
                }
            }
            for bar in layers() {
                expect(bar.frame.minX >= 0 && bar.frame.maxX <= width + 0.0001 && bar.position.y == view.bounds.midY,
                       "music bars retain their spacing and vertical center in every presentation")
            }
            expect(zip(lowest, highest).allSatisfy { $0 >= 1.8 && $1 <= 14 }
                   && highest[count / 2] > lowest[count / 2] + 1
                   && layers().allSatisfy { $0.cornerRadius == 0.9 },
                   "music motion rises and falls within its reserved height with rounded ends")
        }
        view.removeFromSuperview()
        expect(isStopped(), "removing the music surface ends its motion")
        container.addSubview(view)
        expect(view.isMoving, "reattaching a playing surface resumes its motion")
        view.stop()
        window.notifyVisibility()
        expect(isStopped(), "dismantled music bars stay stopped after visibility notifications")
        view.removeFromSuperview()
        weak var released: NotchEqualizerView?
        autoreleasepool {
            let transient = NotchEqualizerView(frame: .zero)
            released = transient
            container.addSubview(transient)
            transient.configure(animates: true, bars: 4, barWidth: 2, height: 14, tint: .white)
            transient.removeFromSuperview()
        }
        expect(released == nil, "visibility observation and motion do not retain discarded music surfaces")
        weak var releasedClock: NotchDecorativeClock?
        autoreleasepool {
            let clock = NotchDecorativeClock { _ in }
            clock.start(in: container)
            releasedClock = clock
        }
        expect(releasedClock == nil, "a running motion clock is released with the view that owns it")
        // The run loop keeps a scheduled display link until it is invalidated.
        // A link left behind would wake the app thirty times a second after
        // its clock stopped or went away.
        let keptClock = NotchDecorativeClock { _ in }
        weak var stoppedLink: CADisplayLink?
        var range: CAFrameRateRange?
        autoreleasepool {
            keptClock.start(in: container)
            stoppedLink = keptClock.displayLink
            range = keptClock.displayLink?.preferredFrameRateRange
        }
        expect(stoppedLink != nil, "a running motion clock steps from a display link")
        expect(range.map { $0.minimum >= 15 && $0.maximum <= 30 && $0.preferred.map { $0 > 0 && $0 <= 30 } ?? false } == true,
               "the motion clock asks for at most thirty steps a second")
        autoreleasepool { keptClock.stop() }
        expect(stoppedLink == nil, "stopping a motion clock takes its display link off the run loop")
        weak var discardedLink: CADisplayLink?
        autoreleasepool {
            let clock = NotchDecorativeClock { _ in }
            clock.start(in: container)
            discardedLink = clock.displayLink
        }
        expect(discardedLink == nil, "a discarded running clock takes its display link off the run loop")

        let swing = (0...40).map { NotchDecorativeClock.swing(Double($0) / 10) }
        expect(abs(swing[0]) < 1e-9 && abs(swing[10] - 1) < 1e-9 && abs(swing[20]) < 1e-9
               && abs(swing[5] - 0.5) < 1e-9 && swing.allSatisfy { $0 >= 0 && $0 <= 1 }
               && zip(swing[0...10], swing[1...10]).allSatisfy { $0 < $1 }
               && (0...20).allSatisfy { abs(swing[$0] - swing[$0 + 20]) < 1e-9 },
               "a swing eases out to its far end and back each cycle")
        let pulse = (0...16).map { NotchDecorativeClock.pulse(Double($0) / 10, period: 1.6) }
        expect(abs(pulse[0]) < 1e-9 && zip(pulse[0..<15], pulse[1..<16]).allSatisfy { $0 < $1 }
               && pulse[15] > 0.99 && abs(pulse[16]) < 1e-9,
               "a pulse eases out over its period and then starts over")
    }
}
