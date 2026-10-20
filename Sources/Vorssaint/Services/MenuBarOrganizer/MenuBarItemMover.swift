// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Rearranges the menu bar by hand, so to speak: macOS 27 offers no API for an
/// item's position, but it does obey a ⌘-drag, and MenuBarAgent persists where
/// the icon was dropped. The drag is synthesised as HID mouse events.
///
/// Every call blocks for the length of the gesture (about half a second plus
/// travel). Do not call it on the main thread: the main run loop may itself be
/// tracking the drag when the icon belongs to Vorssaint, and would then starve
/// both the gesture and the tracking.
enum MenuBarItemMover {
    /// Stamped on every event posted here ("VSMB"), which is how the input
    /// guard separates the gesture from whatever the user's hand is doing.
    static let syntheticTag: Int64 = 0x5653_4D42

    /// The gesture's timing. The agent only follows a drag that looks human.
    private enum Pace {
        /// How long the pointer must have rested before the drag may begin.
        static let pointerRest: TimeInterval = 0.25
        /// A hand that never rests does not postpone the move forever.
        static let pointerRestPatience: TimeInterval = 1.5
        /// Press and hold before moving, or the press is not taken as a grab.
        static let pressDwell: TimeInterval = 0.18
        static let betweenSteps: TimeInterval = 0.03
        /// Pause over the target before letting go.
        static let dropDwell: TimeInterval = 0.12
        /// Longest hop between two drag events. Beyond this the agent stops
        /// noticing the slots the icon passes over.
        static let longestHop: CGFloat = 40
        /// One jump from start to end is not treated as a drag at all.
        static let fewestHops = 6
    }

    /// ⌘-drags from `start` to `end`, both in CG global coordinates (top-left
    /// origin, as Accessibility frames report them), then puts the pointer
    /// back where it was. Blocking; never on the main thread.
    static func commandDrag(from start: CGPoint, to end: CGPoint) {
        awaitRestingPointer()
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        source.userData = syntheticTag
        let home = CGEvent(source: nil)?.location

        InputGuard.protecting { inputGuard in
            func emit(_ type: CGEventType, at point: CGPoint, thenWait pause: TimeInterval) {
                if let event = CGEvent(mouseEventSource: source, mouseType: type,
                                       mouseCursorPosition: point, mouseButton: .left) {
                    event.flags = .maskCommand
                    event.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
                    event.post(tap: .cghidEventTap)
                }
                // The ⌘-click brings another app to the front, and macOS
                // answers that by showing the cursor and re-coupling the mouse.
                inputGuard.reapply()
                Thread.sleep(forTimeInterval: pause)
            }

            emit(.leftMouseDown, at: start, thenWait: Pace.pressDwell)
            for point in path(from: start, to: end) {
                emit(.leftMouseDragged, at: point, thenWait: Pace.betweenSteps)
            }
            Thread.sleep(forTimeInterval: Pace.dropDwell)
            emit(.leftMouseUp, at: end, thenWait: 0)
            // Still hidden here, so the trip home is not seen.
            if let home { CGWarpMouseCursorPosition(home) }
        }
    }

    /// The points to drag through, ending exactly on `end`. Smoothstep eases
    /// the motion in and out; its steepest slope is 1.5, so the hop count is
    /// sized for that and even the fastest hop stays within `longestHop`.
    private static func path(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let hops = max(Pace.fewestHops, Int((distance * 1.5 / Pace.longestHop).rounded(.up)))
        return (1...hops).map { hop in
            let linear = CGFloat(hop) / CGFloat(hops)
            let eased = linear * linear * (3 - 2 * linear)
            return CGPoint(x: start.x + (end.x - start.x) * eased,
                           y: start.y + (end.y - start.y) * eased)
        }
    }

    /// Returns once the physical mouse has been still for `Pace.pointerRest`,
    /// or when patience runs out. Starting under a moving hand would fight it.
    private static func awaitRestingPointer() {
        let deadline = Date().addingTimeInterval(Pace.pointerRestPatience)
        while Date() < deadline {
            let sinceLastInput = InputGuard.watchedEvents
                .map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }
                .min() ?? .infinity
            if sinceLastInput >= Pace.pointerRest { return }
            Thread.sleep(forTimeInterval: min(0.05, Pace.pointerRest - sinceLastInput))
        }
    }
}

/// Keeps the user's mouse out of one synthesised gesture: the cursor is
/// uncoupled from mouse movement and hidden, and a filtering event tap drops
/// physical mouse input. Lives for a single `protecting` call.
private final class InputGuard {
    /// Everything a mouse or trackpad can add to a drag in progress.
    static let watchedEvents: [CGEventType] = [
        .mouseMoved, .scrollWheel,
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
    ]

    private let display = CGMainDisplayID()
    /// Hides are counted by the window server, so each needs its own show.
    private var cursorHides = 0
    private var filter: PhysicalInputFilter?

    /// Runs `body` under the guard and lifts it afterwards, whichever way
    /// `body` ends.
    static func protecting(_ body: (InputGuard) -> Void) {
        let inputGuard = InputGuard()
        inputGuard.raise()
        defer { inputGuard.lower() }
        body(inputGuard)
    }

    /// Call after anything that may have changed the frontmost app, since that
    /// change makes macOS undo both the uncoupling and the hiding.
    func reapply() {
        CGAssociateMouseAndMouseCursorPosition(0)
        if CGDisplayHideCursor(display) == .success { cursorHides += 1 }
    }

    private func raise() {
        // Without Accessibility there is no filter; the two measures in
        // `reapply` still keep most of a stray movement away.
        filter = PhysicalInputFilter.start()
        reapply()
    }

    private func lower() {
        for _ in 0..<cursorHides { CGDisplayShowCursor(display) }
        cursorHides = 0
        CGAssociateMouseAndMouseCursorPosition(1)
        filter?.stop()
        filter = nil
    }
}

/// An event tap at the HID level that lets only tagged events through, served
/// by a thread of its own. The main run loop cannot serve it, being possibly
/// busy with the very drag this protects, and an unserved filtering tap stalls
/// all input until the system switches it off.
private final class PhysicalInputFilter {
    private let port: CFMachPort
    private let runLoop: CFRunLoop

    private init(port: CFMachPort, runLoop: CFRunLoop) {
        self.port = port
        self.runLoop = runLoop
    }

    /// Returns once the tap is being served, so nothing synthesised can reach
    /// the HID stream ahead of it. `nil` when the tap is refused.
    static func start() -> PhysicalInputFilter? {
        let mask = InputGuard.watchedEvents.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: passTaggedOnly, userInfo: nil),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        else { return nil }

        let serving = DispatchSemaphore(value: 0)
        var servedBy: CFRunLoop?
        let thread = Thread {
            let current = CFRunLoopGetCurrent()
            CFRunLoopAddSource(current, source, .defaultMode)
            // Reported from inside the loop: a stop requested before the loop
            // runs would be lost and leave this thread behind.
            CFRunLoopPerformBlock(current, CFRunLoopMode.defaultMode.rawValue) {
                servedBy = current
                serving.signal()
            }
            CFRunLoopRun()
        }
        thread.name = "com.vorssaint.menu-bar-organizer.input-filter"
        thread.qualityOfService = .userInteractive
        thread.start()
        serving.wait()

        guard let servedBy else {
            CFMachPortInvalidate(port)
            return nil
        }
        return PhysicalInputFilter(port: port, runLoop: servedBy)
    }

    func stop() {
        CGEvent.tapEnable(tap: port, enable: false)
        CFRunLoopStop(runLoop)
        CFMachPortInvalidate(port)
    }
}

/// Tap callback. Notices that the tap was disabled carry no input and are
/// handed on untouched; of the rest only the mover's own events survive.
private func passTaggedOnly(_: CGEventTapProxy, type: CGEventType, event: CGEvent,
                            _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        return Unmanaged.passUnretained(event)
    }
    return event.getIntegerValueField(.eventSourceUserData) == MenuBarItemMover.syntheticTag
        ? Unmanaged.passUnretained(event)
        : nil
}
