// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Runs the production refresh and snapshot methods with inert process data and
/// controlled queues. No real process is inspected, signalled or launched.
enum PortManagerRefreshTests {
    enum Processes {
        static var current: [pid_t: UInt64] = [:]
        static var enumerated: [pid_t] = []
        static var enumerationFails = false
        static func startTime(for pid: pid_t) -> UInt64? { current[pid] }
    }
    enum Listing {
        static var status: Int32 = 0
        static var output = ""
        static var during: [pid_t: UInt64] = [:]
        static var calls = 0
        static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
            calls += 1
            Processes.current = during
            return (status, output)
        }
    }
    final class Queue {
        enum QoS { case userInitiated }
        static let main = Queue()
        static let worker = Queue()
        var jobs: [() -> Void] = []
        static func global(qos: QoS) -> Queue { worker }
        func async(execute action: @escaping () -> Void) { jobs.append(action) }
        func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
    }
    class Fixture {
        typealias DispatchQueue = Queue
        typealias KillProcessService = Processes
        typealias Shell = Listing
        var entries: [PortManagerEntry] = []
        var isRefreshing = false
        var hasLoadedOnce = false
        var refreshFailed = false
        static func proc_listallpids(_ buffer: UnsafeMutableRawPointer?, _ byteCount: Int32) -> Int32 {
            guard !Processes.enumerationFails else { return -1 }
            guard let buffer else { return Int32(Processes.enumerated.count) }
            let count = min(Processes.enumerated.count, Int(byteCount) / MemoryLayout<pid_t>.size)
            let pids = buffer.assumingMemoryBound(to: pid_t.self)
            for index in 0..<count { pids[index] = Processes.enumerated[index] }
            return Int32(count)
        }
    }
    private static let rows = """
        p123
        cExample Server
        PTCP
        n*:4321
        p124
        cOther Server
        PTCP
        n*:4322
        """
    static func run(_ suite: TestSuite) {
        defer {
            Queue.main.jobs = []; Queue.worker.jobs = []
            Processes.current = [:]; Processes.enumerated = []; Processes.enumerationFails = false
            Listing.status = 0; Listing.output = ""; Listing.during = [:]; Listing.calls = 0
        }
        func prepare(before: [pid_t: UInt64], after: [pid_t: UInt64], status: Int32 = 0) {
            Processes.current = before
            Processes.enumerated = before.keys.sorted()
            Processes.enumerationFails = false
            Listing.during = after
            Listing.status = status
            Listing.output = rows
        }
        prepare(before: [123: 100, 124: 200], after: [123: 100, 124: 200])
        suite.expect(Service.snapshot()?.map(\.startedAt) == [100, 200],
                     "stable listener identities retain their termination capability")
        prepare(before: [123: 100, 124: 200], after: [123: 300, 124: 200])
        let reused = Service.snapshot()
        suite.expect(reused?.count == 2 && reused?[0].startedAt == nil && reused?[1].startedAt == 200,
                     "a reused PID cannot lend a new process identity to an old listener row")
        prepare(before: [124: 200], after: [123: 100, 124: 200])
        suite.expect(Service.snapshot()?[0].startedAt == nil,
                     "a process first seen during the listing requires a fresh scan before termination")
        prepare(before: [123: 100, 124: 200], after: [124: 200])
        suite.expect(Service.snapshot()?[0].startedAt == nil,
                     "an exited or unreadable process never receives a termination identity")
        prepare(before: [123: 100, 124: 200], after: [123: 100, 124: 200])
        Processes.enumerationFails = true
        suite.expect(Service.snapshot()?.allSatisfy { $0.startedAt == nil } == true,
                     "failed identity enumeration keeps the listing read-only")
        prepare(before: [123: 100], after: [123: 100], status: -1)
        suite.expect(Service.snapshot() == nil, "a timed-out listing remains a failure, not an empty result")
        Listing.status = 1
        Listing.output = ""
        suite.expect(Service.snapshot() == [], "a successful scan with no listeners is genuinely empty")

        let service = Service()
        prepare(before: [:], after: [:], status: -1)
        Listing.calls = 0
        service.refresh()
        service.refresh()
        suite.expect(service.isRefreshing && Queue.worker.jobs.count == 1,
                     "refresh starts once while a scan is in progress")
        Queue.worker.drain()
        suite.expect(service.isRefreshing && !service.refreshFailed,
                     "a completed scan waits for main-queue publication")
        Queue.main.drain()
        suite.expect(!service.isRefreshing && service.refreshFailed && !service.hasLoadedOnce,
                     "the first timeout stops loading and reports a retryable failure")
        suite.expect(service.entries.isEmpty && Listing.calls == 1,
                     "a failed first scan does not invent data or launch duplicate work")
        prepare(before: [123: 100, 124: 200], after: [123: 100, 124: 200])
        service.refresh()
        suite.expect(service.isRefreshing && !service.refreshFailed,
                     "retry clears the old failure while work runs")
        Queue.worker.drain(); Queue.main.drain()
        let previous = service.entries
        suite.expect(service.hasLoadedOnce && !service.refreshFailed && previous.count == 2,
                     "a successful retry publishes listeners and clears the error")
        prepare(before: [:], after: [:], status: -1)
        service.refresh()
        Queue.worker.drain(); Queue.main.drain()
        suite.expect(service.entries == previous && service.hasLoadedOnce && service.refreshFailed,
                     "a later timeout preserves the last successful listing and reports stale data")
        Listing.status = 1
        Listing.output = ""
        service.refresh()
        Queue.worker.drain(); Queue.main.drain()
        suite.expect(service.entries.isEmpty && service.hasLoadedOnce && !service.refreshFailed,
                     "a successful empty retry replaces old listeners without claiming a failure")
    }
}
