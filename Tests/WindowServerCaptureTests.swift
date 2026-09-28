// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The production capture body and queue run against a controllable native
/// call. No windows are captured and no Screen Recording permission is needed.
enum WindowServerCaptureContract {
    enum Provider {
        typealias CGSConnectionID = UInt32
        typealias CGSCaptureFunction =
            @convention(c) (CGSConnectionID, UnsafeMutablePointer<UInt32>, UInt32, UInt32) -> Unmanaged<CFArray>?
        static var windowServerConnection: CGSConnectionID = 1
        static let windowServerCaptureOptions: UInt32 = (1 << 8) | (1 << 11)
        static let windowServerCaptures = WindowServerCaptureQueue()
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
        static let entered = DispatchSemaphore(value: 0)
        static let release = DispatchSemaphore(value: 0)

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
            }
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

        Fake.reset()
        Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            let image = await Provider.captureViaWindowServer(80)
            suite.expect(image == nil, "a request cancelled before submission returns no image")
            finished.signal()
        }
        suite.expect(wait(finished) && Fake.lock.withLock { Fake.calls.isEmpty },
                     "a request cancelled before submission never enters native capture")
    }
}
