// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The production window-server capture body runs against a capture call that
/// holds itself open until released, so overlapping captures show up (#1863).
enum WindowServerCaptureContract {
    enum Provider {
        typealias CGSConnectionID = UInt32
        typealias CGSCaptureFunction =
            @convention(c) (CGSConnectionID, UnsafeMutablePointer<UInt32>, UInt32, UInt32) -> Unmanaged<CFArray>?
        static let windowServerConnection: CGSConnectionID = 1
        static let windowServerCaptureOptions: UInt32 = 0
        static let windowServerCaptureLock = NSLock()
        static let windowServerCapture: CGSCaptureFunction? = { _, _, _, _ in Fake.capture() }
    }

    enum Fake {
        static let state = NSLock()
        static var inFlight = 0
        static var mostInFlight = 0
        static var calls = 0
        static var results: [Int: Bool] = [:]
        static let entered = DispatchSemaphore(value: 0)
        static let release = DispatchSemaphore(value: 0)

        static func capture() -> Unmanaged<CFArray>? {
            state.lock()
            inFlight += 1
            calls += 1
            mostInFlight = max(mostInFlight, inFlight)
            state.unlock()
            entered.signal()
            // Bounded so a capture that should have been skipped fails the
            // checks below instead of hanging the suite.
            _ = release.wait(timeout: .now() + 2)
            state.lock()
            inFlight -= 1
            state.unlock()
            return Unmanaged.passRetained([image] as CFArray)
        }

        static let image: CGImage = {
            let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return context.makeImage()!
        }()

        static func record(_ key: Int, _ image: CGImage?) {
            state.lock()
            results[key] = image != nil
            state.unlock()
        }
    }

    static func run(_ suite: TestSuite) {
        let finished = DispatchGroup()
        finished.enter()
        Thread.detachNewThread {
            Fake.record(1, Provider.captureViaWindowServer(1))
            finished.leave()
        }
        let firstEntered = Fake.entered.wait(timeout: .now() + 5) == .success
        let skipped = Provider.captureViaWindowServer(2, waitingForOtherCaptures: false)
        suite.expect(firstEntered && skipped == nil && Fake.calls == 1,
                     "background warming skips a window while another capture is in flight")

        finished.enter()
        Thread.detachNewThread {
            Fake.record(3, Provider.captureViaWindowServer(3))
            finished.leave()
        }
        // Bounded: with the lock the second capture cannot enter, so this
        // times out; without it, it enters right away.
        let overlapped = Fake.entered.wait(timeout: .now() + 0.5) == .success
        Fake.release.signal()
        let secondEntered = overlapped || Fake.entered.wait(timeout: .now() + 5) == .success
        Fake.release.signal()
        let done = finished.wait(timeout: .now() + 5) == .success
        suite.expect(done && secondEntered && !overlapped && Fake.mostInFlight == 1
                     && Fake.results == [1: true, 3: true],
                     "a capture that waits starts only after the one in flight returns")
    }
}
