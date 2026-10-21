// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The production capture body and queue run against a controllable native
/// call, permission check and clock. No windows are captured and no Screen
/// Recording permission is needed.
enum WindowServerCaptureContract {
    enum Provider {
        typealias CGSConnectionID = UInt32
        typealias CGSCaptureFunction =
            @convention(c) (CGSConnectionID, UnsafeMutablePointer<UInt32>, UInt32, UInt32) -> Unmanaged<CFArray>?
        static var windowServerConnection: CGSConnectionID = 1
        static let windowServerCaptureOptions: UInt32 = (1 << 8) | (1 << 11)
        /// Replaced on every reset, so pauses never carry from one case to the next.
        static var windowServerCaptures = Fake.makeQueue()
        static var windowServerCapture: CGSCaptureFunction? = { connection, id, count, options in
            Fake.capture(connection: connection, id: id.pointee, count: count, options: options)
        }
    }

    enum Fake {
        static let lock = NSLock()
        static var inFlight = 0
        static var maximumInFlight = 0
        static var calls: [UInt32] = []
        static var results: [UInt32: Bool] = [:]
        static var heldIDs: Set<UInt32> = []
        static var mode = 4
        static var argumentsValid = true
        static var usedMainThread = false
        /// Stands still unless a case moves it, so real delays never read as slow.
        static var clock: TimeInterval = 1000
        static var checkDelay: TimeInterval = 0
        static var checks = 0
        static var whileChecking: (() -> Void)?
        /// Counts the queue's clock reads, so a case can tell when an answer
        /// has been timed before it moves the clock.
        static var clockReads = 0
        static let entered = DispatchSemaphore(value: 0)
        static let release = DispatchSemaphore(value: 0)

        static func makeQueue() -> WindowServerCaptureQueue {
            WindowServerCaptureQueue(now: { lock.withLock { clockReads += 1; return clock } }, checkPermission: {
                let hook = lock.withLock { () -> (() -> Void)? in
                    checks += 1
                    clock += checkDelay
                    return whileChecking
                }
                hook?()
            })
        }

        static func advance(by interval: TimeInterval) {
            lock.withLock { clock += interval }
        }

        final class Flag: @unchecked Sendable {
            private let lock = NSLock()
            private var value = false

            var isSet: Bool { lock.withLock { value } }
            func set() { lock.withLock { value = true } }
        }

        static let image = makeImage(size: 2)
        static let tinyImage = makeImage(size: 1)

        private static func makeImage(size: Int) -> CGImage {
            CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }

        static func capture(connection: UInt32, id: UInt32, count: UInt32,
                            options: UInt32) -> Unmanaged<CFArray>? {
            let settings = lock.withLock { () -> (Bool, Int) in
                inFlight += 1
                maximumInFlight = max(maximumInFlight, inFlight)
                calls.append(id)
                argumentsValid = argumentsValid && connection == 1 && count == 1
                    && options == Provider.windowServerCaptureOptions
                usedMainThread = usedMainThread || Thread.isMainThread
                return (heldIDs.contains(id), mode)
            }
            defer { lock.withLock { inFlight -= 1 } }
            if settings.0 {
                entered.signal()
                _ = release.wait(timeout: .now() + 10)
            }
            switch settings.1 {
            case 0: return nil
            case 1: return Unmanaged.passRetained([] as CFArray)
            case 2: return Unmanaged.passRetained(["not an image"] as CFArray)
            case 3: return Unmanaged.passRetained([tinyImage] as CFArray)
            default: return Unmanaged.passRetained([image] as CFArray)
            }
        }

        static func reset(holding ids: Set<UInt32> = [], mode: Int = 4) {
            lock.withLock {
                inFlight = 0
                maximumInFlight = 0
                calls = []
                results = [:]
                heldIDs = ids
                self.mode = mode
                argumentsValid = true
                usedMainThread = false
                checkDelay = 0
                checks = 0
                whileChecking = nil
                clockReads = 0
            }
            Provider.windowServerCaptures = makeQueue()
        }
    }

    @discardableResult
    private static func launch(_ id: UInt32, waiting: Bool = true,
                               started: DispatchSemaphore? = nil,
                               finished: DispatchSemaphore) -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) {
            started?.signal()
            let image = await Provider.captureViaWindowServer(id, waitingForOtherCaptures: waiting)
            Fake.lock.withLock { Fake.results[id] = image === Fake.image }
            finished.signal()
        }
    }

    private static func wait(_ event: DispatchSemaphore) -> Bool {
        event.wait(timeout: .now() + 3) == .success
    }

    static func run(_ suite: TestSuite) {
        let finished = DispatchSemaphore(value: 0)

        // Every rejection must release the queue, and a successful capture
        // keeps the original pixels and native arguments for all callers.
        for mode in 0...4 {
            Fake.reset(mode: mode)
            launch(20, waiting: false, finished: finished)
            suite.expect(wait(finished) && Fake.lock.withLock { Fake.results[20] == (mode == 4) },
                         "capture result \(mode) preserves native image validation")
            Fake.lock.withLock { Fake.mode = 4 }
            launch(21, waiting: false, finished: finished)
            suite.expect(wait(finished) && Fake.lock.withLock {
                Fake.results[21] == true && Fake.argumentsValid && !Fake.usedMainThread
            }, "a later capture succeeds off the main thread after result \(mode)")
        }

        Fake.reset()
        Provider.windowServerConnection = 0
        launch(22, finished: finished)
        suite.expect(wait(finished) && Fake.lock.withLock { Fake.calls.isEmpty },
                     "a missing connection does not enter native capture")
        Provider.windowServerConnection = 1
        let capture = Provider.windowServerCapture
        Provider.windowServerCapture = nil
        launch(23, finished: finished)
        suite.expect(wait(finished) && Fake.lock.withLock { Fake.calls.isEmpty },
                     "an unavailable capture function does not enter the queue")
        Provider.windowServerCapture = capture

        Fake.reset(holding: [1, 3])
        launch(1, finished: finished)
        suite.expect(wait(Fake.entered), "the first native capture starts")
        launch(2, waiting: false, finished: finished)
        suite.expect(wait(finished) && Fake.lock.withLock {
            Fake.results[2] == false && Fake.calls == [1]
        }, "background warming skips a busy queue")
        launch(3, finished: finished)
        suite.expect(Fake.entered.wait(timeout: .now() + 0.1) == .timedOut,
                     "a foreground capture cannot overlap the in-flight capture")
        Fake.release.signal()
        suite.expect(wait(Fake.entered), "a waiting foreground capture eventually starts")
        Fake.release.signal()
        let firstFinished = wait(finished)
        let secondFinished = wait(finished)
        suite.expect(firstFinished && secondFinished && Fake.lock.withLock {
            Fake.maximumInFlight == 1 && Fake.results[1] == true && Fake.results[3] == true
        }, "both serialized foreground captures keep their original images")

        // Repeated refresh/cancel while a native call is stuck must not fill
        // the cooperative pool, even with more requests than workers.
        Fake.reset(holding: [1])
        let activeFinished = DispatchSemaphore(value: 0)
        let active = launch(1, finished: activeFinished)
        suite.expect(wait(Fake.entered), "the slow native call starts")
        let started = DispatchSemaphore(value: 0)
        let cancelledFinished = DispatchSemaphore(value: 0)
        let count = max(32, ProcessInfo.processInfo.activeProcessorCount * 2)
        let requests = (10..<(10 + count)).map {
            launch(UInt32($0), started: started, finished: cancelledFinished)
        }
        var allStarted = true
        for _ in requests { if !wait(started) { allStarted = false; break } }
        let unrelated = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) { unrelated.signal() }
        suite.expect(allStarted && wait(unrelated),
                     "queued captures leave the cooperative executor responsive")
        requests.forEach { $0.cancel() }
        var allCancelled = true
        for _ in requests { if !wait(cancelledFinished) { allCancelled = false; break } }
        suite.expect(allCancelled && Fake.lock.withLock { Fake.calls == [1] },
                     "cancelled waiters finish without submitting captures or waiting for the native call")
        active.cancel()
        suite.expect(wait(activeFinished) && Fake.lock.withLock { Fake.results[1] == false },
                     "cancelling an active caller discards its eventual image immediately")
        launch(2, waiting: false, finished: finished)
        suite.expect(wait(finished) && Fake.lock.withLock { Fake.calls == [1] },
                     "cancelling the active caller does not release native capture exclusivity")
        let survivorID = UInt32(10 + count)
        launch(survivorID, finished: finished)
        Fake.release.signal()
        suite.expect(wait(finished) && Fake.lock.withLock {
            Fake.calls == [1, survivorID] && Fake.maximumInFlight == 1
                && Fake.results[survivorID] == true && Fake.results[1] == false
        }, "after a late native result, only a live request captures and cancelled results stay discarded")
        let warmID = UInt32(11 + count)
        launch(warmID, waiting: false, finished: finished)
        suite.expect(wait(finished) && Fake.lock.withLock { Fake.results[warmID] == true },
                     "background warming captures again once cancelled requests have left the queue")

        Fake.reset()
        Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            let image = await Provider.captureViaWindowServer(80)
            suite.expect(image == nil, "a request cancelled before submission returns no image")
            finished.signal()
        }
        suite.expect(wait(finished) && Fake.lock.withLock { Fake.calls.isEmpty },
                     "a request cancelled before submission never enters native capture")

        runStallGuards(suite, finished: finished)
        runScreenCaptureKitTurns(suite, finished: finished)
        runProductionWiring(suite)
    }

    /// The app's own queue asks tccd first, and the switcher captures only
    /// while someone can see its thumbnails.
    private static func runProductionWiring(_ suite: TestSuite) {
        suite.expect(WindowServerCaptureQueue.screenRecordingCheck != nil,
                     "TCCAccessPreflight resolves from TCC.framework, so each capture turn can ask tccd first")
        WindowServerCaptureQueue.screenRecordingCheck?()
        let provider = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Switcher/WindowPreviewProvider.swift",
                                    encoding: .utf8)) ?? ""
        suite.expect(provider.contains("WindowServerCaptureQueue(\n        checkPermission: WindowServerCaptureQueue.screenRecordingCheck ?? {})"),
                     "the shared capture queue asks tccd before its turns")
        suite.expect(provider.components(separatedBy: "Self.screenIsInView(),").count == 4
                     && provider.contains("displaysAsleep: CGDisplayIsAsleep(CGMainDisplayID()) != 0)"),
                     "refreshes and warming capture only while the screen is in view")
        let onConsole = kCGSessionOnConsoleKey as String
        suite.expect(SwitcherSupport.screenIsInView(session: [onConsole: true], displaysAsleep: false)
                     && SwitcherSupport.screenIsInView(session: nil, displaysAsleep: false),
                     "thumbnails are captured on an unlocked screen with the displays awake")
        suite.expect(!SwitcherSupport.screenIsInView(session: [onConsole: false], displaysAsleep: false)
                     && !SwitcherSupport.screenIsInView(session: [onConsole: true, "CGSSessionScreenIsLocked": true],
                                                        displaysAsleep: false)
                     && !SwitcherSupport.screenIsInView(session: [onConsole: true], displaysAsleep: true),
                     "no thumbnail is captured for another account, a locked screen or sleeping displays")
    }

    /// Issue #1863: the permission check stalling under load ends the session
    /// once a capture waits 30 seconds on it, so captures stop at the first sign.
    private static func runStallGuards(_ suite: TestSuite, finished: DispatchSemaphore) {
        let pauses: [TimeInterval] = (1...7).map { WindowServerCaptureQueue.pause(afterSlowTurns: $0) }
        suite.expect(pauses == [30, 60, 120, 240, 480, 600, 600], "pauses double from half a minute up to ten")

        Fake.reset()
        Fake.lock.withLock { Fake.checkDelay = WindowServerCaptureQueue.slowPermissionCheck }
        launch(30, finished: finished)
        suite.expect(wait(finished) && Fake.lock.withLock {
            Fake.calls.isEmpty && Fake.checks == 1 && Fake.results[30] == false
        }, "a slow permission check keeps the capture from reaching the system")
        Fake.lock.withLock { Fake.checkDelay = 0 }
        launch(31, finished: finished)
        suite.expect(wait(finished) && Fake.lock.withLock { Fake.calls.isEmpty && Fake.checks == 1 },
                     "captures stay paused after a slow check without asking again")
        suite.expect(!Provider.windowServerCaptures.acceptsCaptures,
                     "a reader can tell captures are paused instead of taking the refusal for a missing window")
        Fake.advance(by: WindowServerCaptureQueue.pause(afterSlowTurns: 1))
        suite.expect(Provider.windowServerCaptures.acceptsCaptures, "the pause ends on time")
        launch(32, finished: finished)
        suite.expect(wait(finished) && Fake.lock.withLock {
            Fake.calls == [32] && Fake.checks == 2 && Fake.results[32] == true
        }, "after the pause a prompt check lets the capture through")
        launch(33, finished: finished)
        suite.expect(wait(finished) && Fake.lock.withLock { Fake.calls == [32, 33] && Fake.checks == 2 },
                     "a prompt check vouches for the captures that follow it")
        Fake.advance(by: WindowServerCaptureQueue.permissionCheckLifetime)
        launch(34, finished: finished)
        suite.expect(wait(finished) && Fake.lock.withLock { Fake.calls == [32, 33, 34] && Fake.checks == 3 },
                     "an old prompt check is asked again before the next capture")

        Fake.reset()
        let checking = DispatchSemaphore(value: 0)
        let answer = DispatchSemaphore(value: 0)
        Fake.lock.withLock {
            Fake.whileChecking = {
                checking.signal()
                _ = answer.wait(timeout: .now() + 3)
            }
        }
        let cancelled = launch(35, finished: finished)
        suite.expect(wait(checking), "the check is asked before a capture")
        cancelled.cancel()
        answer.signal()
        suite.expect(wait(finished) && Fake.lock.withLock { Fake.calls.isEmpty && Fake.results[35] == false },
                     "a caller cancelled while the check is asked never captures")
        Fake.lock.withLock { Fake.whileChecking = nil }
        launch(36, finished: finished)
        suite.expect(wait(finished) && Fake.lock.withLock { Fake.calls == [36] && Fake.checks == 1 },
                     "the turn given up after the check leaves the queue usable")

        // The same turn must also close when nothing else is asked for, or
        // two quiet seconds later every capture is refused for good.
        Fake.reset()
        let givenUpChecking = DispatchSemaphore(value: 0)
        let givenUpAnswer = DispatchSemaphore(value: 0)
        Fake.lock.withLock {
            Fake.whileChecking = {
                givenUpChecking.signal()
                _ = givenUpAnswer.wait(timeout: .now() + 3)
            }
        }
        let givenUp = launch(37, finished: finished)
        let givenUpAsked = wait(givenUpChecking)
        let readsBeforeAnswer = Fake.lock.withLock { Fake.clockReads }
        givenUp.cancel()
        givenUpAnswer.signal()
        // Move the clock only once the answer has been timed, so the check
        // itself still reads as prompt.
        var answerTimed = false
        for _ in 0..<300 where !answerTimed {
            answerTimed = Fake.lock.withLock { Fake.clockReads > readsBeforeAnswer }
            if !answerTimed { usleep(10_000) }
        }
        Fake.advance(by: WindowServerCaptureQueue.slowCapture)
        var reopened = false
        for _ in 0..<300 where !reopened {
            reopened = Provider.windowServerCaptures.acceptsCaptures
            if !reopened { usleep(10_000) }
        }
        suite.expect(givenUpAsked && wait(finished) && answerTimed && reopened
                     && Fake.lock.withLock { Fake.calls.isEmpty && Fake.checks == 1 },
                     "a turn given up after its check closes, so later captures are not refused")

        Fake.reset(holding: [40])
        let slowFinished = DispatchSemaphore(value: 0)
        launch(40, finished: slowFinished)
        suite.expect(wait(Fake.entered), "a capture that will come back slowly starts")
        let queued = DispatchSemaphore(value: 0)
        // With 40 held, the only clock read is 41's own request: once it is
        // in, the clock can move without refusing it.
        let readsBeforeQueued = Fake.lock.withLock { Fake.clockReads }
        launch(41, started: queued, finished: finished)
        let queuedStarted = wait(queued)
        var queuedIn = false
        for _ in 0..<300 where !queuedIn {
            queuedIn = Fake.lock.withLock { Fake.clockReads > readsBeforeQueued }
            if !queuedIn { usleep(10_000) }
        }
        suite.expect(queuedStarted && queuedIn && finished.wait(timeout: .now() + 0.1) == .timedOut
                     && Fake.lock.withLock { Fake.calls == [40] && Fake.results[41] == nil },
                     "a capture asked for early waits behind the slow one")
        Fake.advance(by: WindowServerCaptureQueue.slowCapture)
        launch(42, finished: finished)
        suite.expect(wait(finished) && Fake.lock.withLock { Fake.results[42] == false && Fake.calls == [40] },
                     "nothing waits behind a capture that has not come back")
        Fake.release.signal()
        let slowCameBack = wait(slowFinished)
        let queuedSkipped = wait(finished)
        suite.expect(slowCameBack && queuedSkipped && Fake.lock.withLock {
            Fake.results[40] == true && Fake.results[41] == false && Fake.calls == [40]
        }, "a slow capture keeps its image and pauses what waited behind it")
        Fake.advance(by: WindowServerCaptureQueue.pause(afterSlowTurns: 1))
        Fake.lock.withLock { Fake.checkDelay = WindowServerCaptureQueue.slowPermissionCheck }
        launch(43, finished: finished)
        suite.expect(wait(finished) && Fake.lock.withLock { Fake.calls == [40] && Fake.checks == 2 },
                     "the check after a pause can keep captures paused")
        Fake.lock.withLock { Fake.checkDelay = 0 }
        Fake.advance(by: WindowServerCaptureQueue.pause(afterSlowTurns: 1))
        launch(44, finished: finished)
        suite.expect(wait(finished) && Fake.lock.withLock { Fake.calls == [40] && Fake.checks == 2 },
                     "a second slow turn in a row pauses for longer")
        Fake.advance(by: WindowServerCaptureQueue.pause(afterSlowTurns: 2))
        launch(45, finished: finished)
        suite.expect(wait(finished) && Fake.lock.withLock {
            Fake.calls == [40, 45] && Fake.checks == 3 && Fake.results[45] == true
        }, "a prompt check and a quick capture resume captures")
        Fake.lock.withLock { Fake.heldIDs = [46] }
        launch(46, finished: slowFinished)
        let laterSlowStarted = wait(Fake.entered)
        Fake.advance(by: WindowServerCaptureQueue.slowCapture)
        Fake.release.signal()
        let laterSlowCameBack = wait(slowFinished)
        Fake.advance(by: WindowServerCaptureQueue.pause(afterSlowTurns: 1))
        launch(47, finished: finished)
        suite.expect(laterSlowStarted && laterSlowCameBack && wait(finished)
                     && Fake.lock.withLock { Fake.results[47] == true },
                     "a quick capture resets the backoff, so the next slow turn pauses for half a minute again")
    }

    /// ScreenCaptureKit requests make the same check, so they take the same turns.
    private static func runScreenCaptureKitTurns(_ suite: TestSuite, finished: DispatchSemaphore) {
        Fake.reset(holding: [50])
        let started = DispatchSemaphore(value: 0)
        let gate = DispatchSemaphore(value: 0)
        let performed = DispatchSemaphore(value: 0)
        Task.detached {
            let value: Int? = await Provider.windowServerCaptures.perform {
                started.signal()
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().async {
                        _ = gate.wait(timeout: .now() + 10)
                        continuation.resume()
                    }
                }
                return 7
            }
            suite.expect(value == 7, "ScreenCaptureKit work returns its own result")
            performed.signal()
        }
        suite.expect(wait(started), "ScreenCaptureKit work takes a turn")
        launch(50, finished: finished)
        suite.expect(Fake.entered.wait(timeout: .now() + 0.1) == .timedOut,
                     "a window-server capture waits for the ScreenCaptureKit turn to return")
        gate.signal()
        suite.expect(wait(performed) && wait(Fake.entered),
                     "the window-server capture starts once ScreenCaptureKit returns")
        Fake.release.signal()
        suite.expect(wait(finished) && Fake.lock.withLock {
            Fake.results[50] == true && Fake.calls == [50] && Fake.checks == 1
        }, "both kinds of turns share one prompt check")

        Fake.reset()
        Task.detached {
            _ = await Provider.windowServerCaptures.perform { () async -> Int? in
                Fake.advance(by: WindowServerCaptureQueue.slowCapture)
                return 1
            }
            finished.signal()
        }
        suite.expect(wait(finished), "a slow ScreenCaptureKit turn finishes")
        launch(51, finished: finished)
        let ranWhilePaused = Fake.Flag()
        Task.detached {
            let value: Int? = await Provider.windowServerCaptures.perform {
                ranWhilePaused.set()
                return 1
            }
            suite.expect(value == nil, "ScreenCaptureKit work is refused while captures are paused")
            finished.signal()
        }
        let refusedCapture = wait(finished)
        let refusedWork = wait(finished)
        suite.expect(refusedCapture && refusedWork && !ranWhilePaused.isSet && Fake.lock.withLock {
            Fake.calls.isEmpty && Fake.results[51] == false
        }, "a slow ScreenCaptureKit turn pauses every capture")
    }
}
