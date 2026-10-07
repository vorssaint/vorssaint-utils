// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// Steps small looping decorations, the music bars and an agent's pulse, a
/// limited number of times a second. A repeating Core Animation animation is
/// drawn again by the window server on every refresh of the display, up to
/// 120 times a second on a ProMotion screen, and each of those frames
/// composites the display again however small the change. The motion is slow
/// and a few points tall, and looks the same at a quarter of that rate.
final class NotchDecorativeClock {
    /// The most steps a second. A display that cannot divide its refresh rate
    /// down to it steps a little less often.
    static let rate: Float = 30

    private let step: (CFTimeInterval) -> Void
    private var link: CADisplayLink?

    /// `step` receives the time the frame being prepared will show at.
    init(step: @escaping (CFTimeInterval) -> Void) {
        self.step = step
    }

    var isRunning: Bool { link != nil }

    /// The display link while it runs, so tests can check its rate and that
    /// stopping takes it off the run loop.
    var displayLink: CADisplayLink? { link }

    /// Steps in time with the display that shows `view`.
    func start(in view: NSView) {
        guard link == nil else { return }
        let link = view.displayLink(target: Target(clock: self), selector: #selector(Target.fire(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: Self.rate / 2, maximum: Self.rate,
                                                        preferred: Self.rate)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    deinit { link?.invalidate() }

    /// A display link retains its target. The clock is held weakly, so a
    /// discarded view releases it, and the link with it, even while it runs.
    private final class Target: NSObject {
        weak var clock: NotchDecorativeClock?
        init(clock: NotchDecorativeClock) { self.clock = clock }
        @objc func fire(_ link: CADisplayLink) { clock?.step(link.targetTimestamp) }
    }

    /// Where a swing to and fro stands at `phase`, counted in half cycles: 0
    /// at its start, 1 at its far end and 0 again two halves later, easing in
    /// and out at both ends like the animation it replaces.
    static func swing(_ phase: Double) -> Double {
        let half = phase.truncatingRemainder(dividingBy: 2)
        let travelled = half < 0 ? half + 2 : half
        let out = travelled <= 1 ? travelled : 2 - travelled
        return (1 - cos(.pi * out)) / 2
    }

    /// How far a pulse that starts over every `period` seconds has eased out
    /// by `elapsed`, from 0 to 1.
    static func pulse(_ elapsed: Double, period: Double) -> Double {
        guard period > 0 else { return 0 }
        let cycle = elapsed.truncatingRemainder(dividingBy: period)
        let progress = (cycle < 0 ? cycle + period : cycle) / period
        return sin(.pi / 2 * progress)
    }
}
