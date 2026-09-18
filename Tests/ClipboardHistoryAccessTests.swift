// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClipboardHistoryAccessTests {
    static func run(expect: (Bool, String) -> Void) {
        precondition(Thread.isMainThread)

        // A deadline rejects the result immediately but cannot free admission
        // for another capture until the actual read leaves the queue.
        var capture = ClipboardHistoryCaptureState()
        let first = capture.begin()!
        expect(capture.needsBaseline, "first capture establishes a baseline")
        capture.expire(first)
        expect(!capture.accepts(first), "expired capture is rejected before another tick")
        for _ in 0..<100 {
            expect(capture.begin() == nil, "expired read still occupies capture admission")
        }
        capture.invalidate() // stop
        capture.restart() // start while the old read is still blocked
        expect(capture.begin() == nil, "stop/start cannot queue a second blocked read")
        expect(!capture.accepts(first), "restart rejects the previous run's result")
        capture.finish()
        let baseline = capture.begin()!
        expect(capture.needsBaseline && capture.accepts(baseline),
               "new run establishes its own baseline after old read finishes")
        capture.didBaseline()
        capture.finish()
        let fresh = capture.begin()!
        capture.expire(first)
        expect(capture.accepts(fresh), "old timeout cannot invalidate a newer capture")
        expect(!capture.needsBaseline, "normal captures follow the accepted baseline")
        capture.finish()

        let lane = GeneralPasteboardAccess(label: "Vorssaint.Tests.ClipboardDeadline")
        let release = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        var completions = 0
        var finishes = 0
        var answer: Int?
        var finishedValue: Int?
        var answerOnMain = false
        lane.async(timeout: 0.03, { _ -> Int? in
            entered.signal()
            _ = release.wait(timeout: .now() + 2)
            return 42
        }, then: { value in
            completions += 1
            answer = value
            answerOnMain = Thread.isMainThread
        }, didFinish: { value in
            finishedValue = value
            finishes += 1
        })
        expect(entered.wait(timeout: .now() + 1) == .success, "read starts on lane")
        pump { completions == 1 }
        expect(answer == nil && answerOnMain, "timeout returns nil on main")
        expect(finishes == 0, "timeout does not pretend the blocked operation finished")
        release.signal()
        pump { finishes == 1 }
        expect(finishes == 1 && completions == 1 && answer == nil,
               "late completion releases admission without delivering stale success")
        expect(finishedValue == 42,
               "expired result retains bookkeeping for the actual operation completion")

        // A queued user action must expire without ever running its write.
        let releaseQueue = DispatchSemaphore(value: 0)
        let queueEntered = DispatchSemaphore(value: 0)
        lane.async {
            queueEntered.signal()
            _ = releaseQueue.wait(timeout: .now() + 2)
        }
        expect(queueEntered.wait(timeout: .now() + 1) == .success, "lane is held before copy")
        let writes = Counter()
        var copyCompletions = 0
        var copyFinishes = 0
        var copyAnswer: Bool?
        lane.async(timeout: 0.03, { _ -> Bool? in
            writes.increment()
            return true
        }, then: { value in
            copyAnswer = value
            copyCompletions += 1
        }, didFinish: { _ in copyFinishes += 1 })
        pump { copyCompletions == 1 }
        expect(copyAnswer == nil && writes.value == 0 && copyFinishes == 0,
               "queued copy expires without writing or freeing its occupied slot")
        releaseQueue.signal()
        pump { copyFinishes == 1 }
        expect(copyFinishes == 1 && copyCompletions == 1 && writes.value == 0,
               "expired queued copy never writes after the lane recovers")

        var freshAnswer: Bool?
        var freshCompletions = 0
        var freshFinishes = 0
        lane.async(timeout: 0.5, { _ -> Bool? in false }, then: { value in
            freshAnswer = value
            freshCompletions += 1
        }, didFinish: { _ in freshFinishes += 1 })
        pump { freshCompletions == 1 }
        // Exercise the canceled deadline as well as the successful delivery.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.55))
        expect(freshAnswer == false && freshCompletions == 1 && freshFinishes == 1,
               "write failure is preserved and delivered once before the deadline")

        // Main may be busy past the deadline. Even if the worker finished,
        // result delivery must check the clock rather than race the timer.
        let workReturned = DispatchSemaphore(value: 0)
        var overdueAnswer: Int?
        var overdueCompletions = 0
        lane.async(timeout: 0.03, { _ -> Int? in
            workReturned.signal()
            return 7
        }, then: { value in
            overdueAnswer = value
            overdueCompletions += 1
        })
        expect(workReturned.wait(timeout: .now() + 1) == .success, "worker finishes before delivery")
        Thread.sleep(forTimeInterval: 0.06)
        pump { overdueCompletions == 1 }
        expect(overdueAnswer == nil && overdueCompletions == 1,
               "result queued on main cannot succeed after its deadline")
    }

    private static func pump(until condition: () -> Bool) {
        let limit = Date(timeIntervalSinceNow: 1)
        while !condition(), Date() < limit {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
    }

    private final class Counter {
        private let lock = NSLock()
        private var count = 0

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }
    }
}
