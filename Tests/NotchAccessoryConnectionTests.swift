// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Exercise the production lifecycle and its real run loop without connecting
/// to a device, changing radio power, or stalling bluetoothd on the test Mac.
enum NotchAccessoryConnectionTests {
    private typealias Event = NotchAccessoryConnectionEvent

    private final class Source: NotchAccessoryConnectionSource {
        let onStart: (@escaping () -> Bool, @escaping (Event) -> Void) -> Void
        let onStop: () -> Void
        var callback: ((Event) -> Void)?
        var stops = 0

        init(onStart: @escaping (@escaping () -> Bool, @escaping (Event) -> Void) -> Void = { _, _ in },
             onStop: @escaping () -> Void = {}) {
            self.onStart = onStart
            self.onStop = onStop
        }

        func start(isCancelled: @escaping () -> Bool, onEvent: @escaping (Event) -> Void) {
            callback = onEvent
            onStart(isCancelled, onEvent)
        }

        func stop() {
            stops += 1
            onStop()
            // Keep the callback to model a late framework notification.
        }
    }

    private final class Tasks {
        var pending: [() -> Void] = []
        func enqueue(_ work: @escaping () -> Void) { pending.append(work) }
        func drain() {
            while !pending.isEmpty { pending.removeFirst()() }
        }
    }

    static func run(_ suite: TestSuite) {
        workerDoesNotWaitForUI(suite)
        blockedReadCanBeStopped(suite)
        nestedRunLoopDoesNotOverlap(suite)
        obsoleteEvents(suite)
        cancelledBeforeStart(suite)
    }

    private static func pump(until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !done(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    private static func workerDoesNotWaitForUI(_ suite: TestSuite) {
        let callbackFinished = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var threads: [Thread] = []
        var hasRunLoop = true
        func recordThread() {
            lock.withLock {
                threads.append(Thread.current)
                hasRunLoop = hasRunLoop && CFRunLoopCopyCurrentMode(CFRunLoopGetCurrent()) != nil
            }
        }
        let event = Event.connected(name: "Keyboard", majorClass: 5, minorClass: 16)
        let monitor = NotchAccessoryConnectionMonitor(makeSource: { perform in
            recordThread()
            return Source(onStart: { _, emit in
                recordThread()
                perform {
                    recordThread()
                    emit(event)
                    callbackFinished.signal()
                }
            }, onStop: {
                recordThread()
                stopped.signal()
            })
        })
        var delivered: [Event] = []
        var deliveredOnMain = false
        monitor.start {
            delivered.append($0)
            deliveredOnMain = Thread.isMainThread
        }
        // Intentionally leave the main run loop unserviced. The Bluetooth
        // callback must finish anyway; no main.sync or main-run-loop worker.
        suite.expect(callbackFinished.wait(timeout: .now() + 2) == .success,
                     "accessory discovery and callbacks finish while the UI thread is blocked")
        suite.expect(delivered.isEmpty, "presentation waits asynchronously for the UI")
        pump { !delivered.isEmpty }
        suite.expect(delivered == [event] && deliveredOnMain,
                     "only an immutable connection event is delivered on the main thread")
        monitor.stop()
        suite.expect(stopped.wait(timeout: .now() + 2) == .success,
                     "native unregistration also finishes without servicing the UI")
        let evidence = lock.withLock { (threads, hasRunLoop) }
        suite.expect(evidence.0.count == 4 && evidence.0.allSatisfy { !$0.isMainThread && $0 === evidence.0.first },
                     "creation, discovery, callbacks and cleanup use the same background thread")
        suite.expect(evidence.1, "the Bluetooth worker serves a run loop, not just a dispatch queue")
    }

    private static func blockedReadCanBeStopped(_ suite: TestSuite) {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let restarted = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var creations = 0
        var order: [String] = []
        var sawCancellation = false
        let monitor = NotchAccessoryConnectionMonitor(makeSource: { _ in
            let number = lock.withLock { creations += 1; return creations }
            return Source(onStart: { isCancelled, emit in
                lock.withLock { order.append("start \(number)") }
                if number == 1 {
                    entered.signal()
                    _ = release.wait(timeout: .now() + 3)
                    lock.withLock { sawCancellation = isCancelled() }
                }
                // Deliberately send a result even after the first read was cancelled.
                emit(.connected(name: "Device \(number)", majorClass: 5, minorClass: 16))
                if number == 2 { restarted.signal() }
            }, onStop: {
                lock.withLock { order.append("stop \(number)") }
                if number == 2 { stopped.signal() }
            })
        })
        var delivered: [Event] = []
        monitor.start { delivered.append($0) }
        suite.expect(entered.wait(timeout: .now() + 2) == .success, "the fixture blocks inside a Bluetooth read")
        let beforeStop = ProcessInfo.processInfo.systemUptime
        monitor.stop()
        monitor.start { delivered.append($0) }
        suite.expect(ProcessInfo.processInfo.systemUptime - beforeStop < 0.5,
                     "disabling and reenabling never joins a blocked Bluetooth worker")
        suite.expect(lock.withLock { creations } == 1,
                     "reenabling cannot create a second source beside a blocked read")
        release.signal()
        suite.expect(restarted.wait(timeout: .now() + 2) == .success, "a replacement starts after old cleanup finishes")
        pump { !delivered.isEmpty }
        suite.expect(delivered == [.connected(name: "Device 2", majorClass: 5, minorClass: 16)],
                     "a read returning after cancellation cannot publish into the new activation")
        suite.expect(lock.withLock { sawCancellation && order == ["start 1", "stop 1", "start 2"] },
                     "cancellation is visible during the blocked read and old cleanup precedes replacement")
        monitor.stop()
        suite.expect(stopped.wait(timeout: .now() + 2) == .success, "the replacement source is cleaned up")
    }

    private static func nestedRunLoopDoesNotOverlap(_ suite: TestSuite) {
        let entered = DispatchSemaphore(value: 0)
        let reconfigured = DispatchSemaphore(value: 0)
        let restarted = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var creations = 0
        var readReturned = false
        var overlapped = false
        let monitor = NotchAccessoryConnectionMonitor(makeSource: { _ in
            let number = lock.withLock { creations += 1; return creations }
            return Source(onStart: { _, _ in
                if number == 1 {
                    entered.signal()
                    let deadline = Date().addingTimeInterval(3)
                    // Model a synchronous framework request that services its
                    // own run loop while it waits for the daemon to reply.
                    while reconfigured.wait(timeout: .now()) != .success, Date() < deadline {
                        RunLoop.current.run(until: Date().addingTimeInterval(0.005))
                    }
                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                    lock.withLock { readReturned = true }
                } else {
                    lock.withLock { overlapped = overlapped || !readReturned }
                    restarted.signal()
                }
            }, onStop: {
                lock.withLock { overlapped = overlapped || !readReturned }
                if number == 2 { stopped.signal() }
            })
        })
        monitor.start { _ in }
        suite.expect(entered.wait(timeout: .now() + 2) == .success, "the fixture enters a nested Bluetooth run loop")
        monitor.stop()
        monitor.start { _ in }
        reconfigured.signal()
        suite.expect(restarted.wait(timeout: .now() + 2) == .success, "replacement resumes after the nested run loop returns")
        suite.expect(lock.withLock { !overlapped && creations == 2 },
                     "nested run loops cannot reenter native startup or cleanup")
        monitor.stop()
        suite.expect(stopped.wait(timeout: .now() + 2) == .success, "nested-loop test cleans up its replacement")
    }

    private static func obsoleteEvents(_ suite: TestSuite) {
        let worker = Tasks(), ui = Tasks()
        var sources: [Source] = []
        var delivered: [Event] = []
        let monitor = NotchAccessoryConnectionMonitor(perform: worker.enqueue, deliver: ui.enqueue,
            makeSource: { _ in let source = Source(); sources.append(source); return source })
        monitor.start { delivered.append($0) }
        worker.drain()
        guard let old = sources.first else { suite.expect(false, "the first observation starts"); return }
        old.callback?(.connected(name: "Old keyboard", majorClass: 5, minorClass: 16))
        suite.expect(ui.pending.count == 1, "the old event is queued for presentation before disable")
        monitor.stop()
        monitor.start { delivered.append($0) }
        worker.drain()
        ui.drain()
        suite.expect(delivered.isEmpty, "an event already waiting on the UI is discarded after reenable")
        old.callback?(.disconnected(name: "Keyboard"))
        ui.drain()
        suite.expect(delivered.isEmpty, "a late disconnect from the old observer cannot clear new notices")
        guard sources.count == 2 else { suite.expect(false, "one replacement observation starts"); return }
        let current = Event.connected(name: "Keyboard", majorClass: 5, minorClass: 16)
        sources[1].callback?(current)
        ui.drain()
        suite.expect(delivered == [current], "the current observer still delivers connection events")
        sources[1].callback?(.disconnected(name: "Keyboard"))
        monitor.stop()
        monitor.stop()
        worker.drain()
        ui.drain()
        suite.expect(delivered == [current] && sources.allSatisfy { $0.stops == 1 },
                     "repeated stop unregisters each source once and discards its pending events")
    }

    private static func cancelledBeforeStart(_ suite: TestSuite) {
        let worker = Tasks()
        var creations = 0
        var monitor: NotchAccessoryConnectionMonitor? = NotchAccessoryConnectionMonitor(perform: worker.enqueue,
            makeSource: { _ in creations += 1; return Source() })
        monitor?.start { _ in }
        monitor?.stop()
        monitor?.start { _ in }
        monitor = nil
        worker.drain()
        suite.expect(creations == 0, "stop or deinit before worker startup makes no Bluetooth calls")
    }
}
