// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The companion hiding in the island when idle, with the production bodies
/// on a controlled clock. Nothing is drawn and no preference is read.
enum NotchMascotHidingContract {
    typealias DispatchQueue = NotchScreenRefreshContract.DispatchQueue
    enum NSEvent { static var mouseLocation = CGPoint.zero }
    final class NSWorkspace {
        static let shared = NSWorkspace()
        var accessibilityDisplayShouldReduceMotion = false
    }
    final class Host {
        var pointerInside = false
        func containsHover(_ point: CGPoint) -> Bool { pointerInside }
    }
    class State {
        struct Geometry { var floats = false }
        var geometry = Geometry()
        var running = true, mascotOn = true, expanded = false
        /// The closed island has nothing else to show and room for it.
        var restsInPlace = true, canHost = true
        /// The preference as Settings has it, with the companion on.
        var hidesWhenIdle = false
        var mascotHidesAtSync: Bool?
        var mascotTucked = false
        var mascotStirred: CFTimeInterval = -.infinity
        var mascotTuckWork: DispatchWorkItem?
        var mascotVisit: NotchMascotVisit? { didSet { noteMascotStirred() } }
        var pendingMascotReaction: (reaction: NotchMascotReaction, deadline: CFTimeInterval, notBefore: CFTimeInterval)?
        var mascotBridging = false, mascotInBar = false
        var mascotVisitWork: DispatchWorkItem?
        var mascotStepBackWork: DispatchWorkItem?
        var mascotStepsAside = false
        var windowHost: Host? = Host()
        var refreshes = 0, visitEnds = 0
        var entrances: [Bool] = []
        var mascotRestsInView: Bool { mascotOn && restsInPlace && !mascotTucked && !mascotInBar }
        func canHostMascotVisit() -> Bool { canHost && !expanded && !mascotInBar }
        func mediaTime() -> CFTimeInterval { DispatchQueue.main.now }
        func noteMascotStirred() {}
        func refreshPresentation() { refreshes += 1 }
        func endMascotVisit() { visitEnds += 1; mascotVisit = nil }
        func stageMascotEntrance(arriving: Bool) { entrances.append(arriving) }
    }

    /// A new island on a controlled clock, before its first preference sync.
    private static func fresh() -> Service {
        DispatchQueue.main = NotchScreenRefreshContract.Scheduler()
        DispatchQueue.main.now = 1000
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = false
        return Service()
    }

    /// Set to hide when idle, the companion just switched on: out beside the
    /// camera in a resting island, a quiet while counting from now.
    private static func out() -> Service {
        let service = fresh()
        service.hidesWhenIdle = true
        _ = service.syncMascotHiding(switchedOn: false)
        _ = service.syncMascotHiding(switchedOn: true)
        service.noteMascotStirred()
        return service
    }

    static func run(_ suite: TestSuite) {
        let delay = NotchMascotSupport.hideDelay, retry = NotchMascotSupport.hideRetry
        let away = NotchMascotMotion.duration(of: NotchMascotSupport.hideAway)

        let plain = fresh()
        let plainSynced = !plain.syncMascotHiding(switchedOn: false) && !plain.mascotTucked
            && plain.mascotTuckWork == nil
        DispatchQueue.main.advance(delay * 3)
        suite.expect(plainSynced && !plain.mascotTucked && plain.mascotVisit == nil && plain.refreshes == 0,
                     "not set to hide when idle, it rests beside the camera from launch on and nothing counts")

        let launched = fresh()
        launched.hidesWhenIdle = true
        suite.expect(!launched.syncMascotHiding(switchedOn: false) && launched.mascotTucked
                     && launched.mascotTuckWork == nil && launched.mascotVisit == nil,
                     "set to hide when idle, the companion starts in the island at launch, with nothing to animate")

        // Switched on: it comes out to say hello and hides a quiet while later.
        let switched = out()
        suite.expect(!switched.mascotTucked && switched.mascotTuckWork != nil,
                     "switched on, it comes out and a quiet while starts counting")
        DispatchQueue.main.advance(delay - 1)
        suite.expect(!switched.mascotTucked, "it stays out until the quiet while is over")
        DispatchQueue.main.advance(1)
        suite.expect(switched.mascotTucked && switched.mascotVisit?.kind == NotchMascotSupport.hideAway
                     && switched.refreshes == 1,
                     "a quiet while after it last stirred it yawns and hops into the island")
        suite.expect(switched.mascotStepsAside,
                     "an activity arriving as it yawns has its wing covered until the companion is gone")
        let handBack = NotchMascotMotion.handBack(of: NotchMascotSupport.hideAway, floats: false) ?? away
        DispatchQueue.main.advance(handBack)
        suite.expect(!switched.mascotStepsAside && switched.mascotVisit != nil,
                     "the wing comes back as it goes behind the camera, before its visit is over")
        DispatchQueue.main.advance(away - handBack)
        suite.expect(switched.visitEnds == 1 && switched.mascotVisit == nil && switched.mascotTuckWork == nil,
                     "once it is behind the camera the visit ends, so the wings fold, and nothing is left counting")

        // Anything it does starts the while over.
        let stirred = out()
        DispatchQueue.main.advance(delay * 0.8)
        stirred.noteMascotStirred()
        DispatchQueue.main.advance(delay * 0.8)
        suite.expect(!stirred.mascotTucked && stirred.mascotTuckWork != nil,
                     "a reaction or a visit starts the quiet while over")
        DispatchQueue.main.advance(delay * 0.2)
        suite.expect(stirred.mascotTucked, "and a whole quiet while later it hides")

        // Under the pointer, it waits for the pointer to go.
        let watched = out()
        watched.windowHost?.pointerInside = true
        DispatchQueue.main.advance(delay + retry * 2)
        suite.expect(!watched.mascotTucked && watched.mascotTuckWork != nil,
                     "it never hides while the pointer is on it, looking at it or petting it")
        watched.windowHost?.pointerInside = false
        DispatchQueue.main.advance(retry)
        suite.expect(watched.mascotTucked && watched.mascotVisit?.kind == NotchMascotSupport.hideAway,
                     "once the pointer goes, it hides at the next check")

        // Busy, it waits and tries again.
        let strolling = out()
        strolling.mascotVisit = NotchMascotVisit(id: UUID(), kind: .lap, greeting: .wink, start: strolling.mediaTime())
        DispatchQueue.main.advance(delay + retry)
        let strolled = !strolling.mascotTucked
        strolling.mascotVisit = nil
        DispatchQueue.main.advance(retry)
        let rested = !strolling.mascotTucked
        DispatchQueue.main.advance(delay)
        suite.expect(strolled && rested && strolling.mascotTucked,
                     "on a stroll it stays out, and the stroll's end starts a whole quiet while")
        for (name, busy, free) in [
            ("a reaction waiting to show", { (s: Service) in
                s.pendingMascotReaction = (.celebrate, s.mediaTime() + 60, s.mediaTime())
            }, { (s: Service) in s.pendingMascotReaction = nil }),
            ("the island opening around it", { (s: Service) in s.mascotBridging = true },
             { (s: Service) in s.mascotBridging = false }),
            ("the Command Bar", { (s: Service) in s.mascotInBar = true }, { (s: Service) in s.mascotInBar = false }),
        ] {
            let service = out()
            busy(service)
            DispatchQueue.main.advance(delay + retry)
            let waited = !service.mascotTucked && service.mascotTuckWork != nil
            free(service)
            DispatchQueue.main.advance(retry)
            suite.expect(waited && service.mascotTucked, "busy with \(name), it hides only once that is over")
        }
        let expired = out()
        expired.pendingMascotReaction = (.celebrate, expired.mediaTime() + 1, expired.mediaTime())
        DispatchQueue.main.advance(delay)
        suite.expect(expired.mascotTucked, "a reaction past its time keeps nothing waiting")

        // Out of sight it simply stays in: nothing to animate.
        for (name, hide) in [("an activity in its place", { (s: Service) in s.restsInPlace = false }),
                             ("the island open", { (s: Service) in s.expanded = true }),
                             ("no room beside the camera", { (s: Service) in s.canHost = false })] {
            let service = out()
            hide(service)
            DispatchQueue.main.advance(delay)
            suite.expect(service.mascotTucked && service.mascotVisit == nil,
                         "with \(name), it is simply in the island when the island rests again")
        }
        let still = out()
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = true
        DispatchQueue.main.advance(delay)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = false
        suite.expect(still.mascotTucked && still.mascotVisit == nil && still.refreshes == 1,
                     "with Reduce Motion it goes without the hop, and the wings simply fold")
        let stopped = out()
        stopped.running = false
        DispatchQueue.main.advance(delay * 3)
        suite.expect(!stopped.mascotTucked && stopped.mascotTuckWork == nil, "a stopped island hides nothing")

        // Turned on in Settings, it goes in at once, and turned off, it comes back out.
        let toggled = fresh()
        _ = toggled.syncMascotHiding(switchedOn: false)
        toggled.hidesWhenIdle = true
        suite.expect(toggled.syncMascotHiding(switchedOn: false) && toggled.mascotTucked
                     && toggled.mascotVisit?.kind == NotchMascotSupport.hideAway && toggled.mascotTuckWork == nil,
                     "turned on, it hops into the island at once, without waiting for quiet")
        DispatchQueue.main.advance(away)
        toggled.hidesWhenIdle = false
        suite.expect(toggled.syncMascotHiding(switchedOn: false) && !toggled.mascotTucked
                     && toggled.entrances == [true] && toggled.mascotTuckWork == nil,
                     "turned off, it comes back out from behind the camera to rest, and nothing counts")
        let busyToggle = fresh()
        _ = busyToggle.syncMascotHiding(switchedOn: false)
        busyToggle.mascotVisit = NotchMascotVisit(id: UUID(), kind: .lap, greeting: .wink, start: busyToggle.mediaTime())
        busyToggle.hidesWhenIdle = true
        let answered = busyToggle.syncMascotHiding(switchedOn: false) && !busyToggle.mascotTucked
        busyToggle.mascotVisit = nil
        DispatchQueue.main.advance(retry)
        suite.expect(answered && busyToggle.mascotTucked,
                     "turned on mid-stroll, it goes in as soon as the stroll is over, not a quiet while later")
        let openToggle = out()
        openToggle.mascotTucked = true
        openToggle.expanded = true
        openToggle.hidesWhenIdle = false
        _ = openToggle.syncMascotHiding(switchedOn: false)
        suite.expect(!openToggle.mascotTucked && openToggle.entrances.isEmpty,
                     "turned off with the island open, it is simply back in its place when the island closes")

        // Switched off, there is nothing left to hide or to bring out.
        let off = out()
        off.mascotTucked = true
        off.mascotOn = false
        off.hidesWhenIdle = false
        suite.expect(!off.syncMascotHiding(switchedOn: false) && off.entrances.isEmpty && off.mascotTuckWork == nil,
                     "switched off while hidden, it stays where it is and nothing counts")
    }
}
