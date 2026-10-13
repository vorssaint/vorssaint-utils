// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the service's scheduling decision against a recording timer.
enum AgentUsagePollingTests {
    final class Timer {
        var schedules: [(deadline: DispatchTime, interval: TimeInterval)] = []
        func schedule(deadline: DispatchTime, repeating interval: TimeInterval = 0,
                      leeway: DispatchTimeInterval = .nanoseconds(0)) {
            schedules.append((deadline, interval))
        }
    }
    struct Store {
        var turns: [String: Int] = [:]
        var waiting: [String: Int] = [:]
    }
    struct Cursor { var modified: Date }
    class Fixture {
        static let poll: TimeInterval = 2
        static let pollWindow: TimeInterval = 30 * 60
        var store = Store()
        var cursors: [String: Cursor] = [:]
        var poller: Timer? = Timer()
        var polling = false
    }

    static func run(_ suite: TestSuite) {
        let host = Host(), now = Date(timeIntervalSince1970: 100_000)
        let timer = host.poller!
        host.syncPolling(now: now)
        suite.expect(timer.schedules.isEmpty && !host.polling,
                     "no fast timer is armed without logs or active sessions")

        host.cursors["recent"] = Cursor(modified: now.addingTimeInterval(-60))
        host.syncPolling(now: now)
        suite.expect(host.polling && timer.schedules.last?.interval == 2,
                     "a recent log keeps two-second polling even between turns")
        host.syncPolling(now: now)
        suite.expect(timer.schedules.count == 1,
                     "file events do not keep postponing an already armed poll")

        host.syncPolling(now: now.addingTimeInterval(30 * 60))
        suite.expect(!host.polling && timer.schedules.last?.deadline == .distantFuture,
                     "the fast timer stops waking after recent logs age out")
        host.store.turns["long-running"] = 1
        host.syncPolling(now: now.addingTimeInterval(30 * 60))
        suite.expect(host.polling && timer.schedules.last?.interval == 2,
                     "a long-running turn keeps fast polling even with an old log")
        host.store.turns.removeAll()
        host.store.waiting["approval"] = 1
        host.syncPolling(now: now.addingTimeInterval(30 * 60))
        suite.expect(host.polling && timer.schedules.count == 3,
                     "a turn waiting for approval keeps the same polling cadence")
        host.store.waiting.removeAll()
        host.syncPolling(now: now.addingTimeInterval(30 * 60))
        suite.expect(!host.polling, "finishing the last old turn parks the fast timer again")

        host.cursors["recent"] = Cursor(modified: now.addingTimeInterval(30 * 60))
        host.syncPolling(now: now.addingTimeInterval(30 * 60))
        suite.expect(host.polling && timer.schedules.count == 5,
                     "a file event or the slower sweep can resume fast polling")
        host.poller = nil
        host.polling = false
        host.syncPolling(now: now.addingTimeInterval(30 * 60))
        suite.expect(host.poller == nil && !host.polling && timer.schedules.count == 5,
                     "late work after pause or stop cannot recreate a timer")
    }
}
