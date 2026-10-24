// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

typealias AgentCursorServiceProductionAccount = AgentCursorAccount

/// The production service methods run against a controllable desktop and reader.
enum AgentCursorServiceTests {
    enum NSRunningApplication {
        static var open = true
        static func runningApplications(withBundleIdentifier: String) -> [Int] { open ? [1] : [] }
    }

    enum AgentCursorAccount {
        typealias Failure = AgentCursorServiceProductionAccount.Failure
        typealias Reading = AgentCursorServiceProductionAccount.Reading
        static let interval = AgentCursorServiceProductionAccount.interval
        static func session() -> URLSession { AgentCursorServiceProductionAccount.session() }
        private static let lock = NSLock()
        private static var result: Result<Reading, Failure> = .failure(.unavailable)
        private static var blocked = false
        private static var count = 0
        static var calls: Int { lock.withLock { count } }
        static func configure(_ value: Result<Reading, Failure>, blocked: Bool = false) {
            lock.withLock { result = value; self.blocked = blocked }
        }
        static func read(home: URL, since: Date, now: Date, transport: AgentCursorServiceProductionAccount.Transport,
                         onAccount: (String) -> Void) async throws -> Reading {
            let value = lock.withLock { count += 1; return result }
            if case .success(let reading) = value { onAccount(reading.account) }
            while lock.withLock({ blocked }) { try await Task.sleep(nanoseconds: 1_000_000) }
            try Task.checkCancellation()
            return try value.get()
        }
    }

    class Fixture {
        static let horizon: TimeInterval = 91 * 86_400
        var running = true
        var paused = false
        var providers: [AgentProvider] = [.cursor]
        var enabled: Set<AgentProvider> = [.cursor]
        var session = 1
        var readerSession = 1
        let home = FileManager.default.temporaryDirectory
        let queue = DispatchQueue.main
        var cursorRequest: Task<Void, Never>?
        var cursorGeneration = 0
        var cursorAttempted = Date.distantPast
        var cursorChecking = false
        var cursorFailure: AgentCursorAccount.Failure?
        var cursorAccount: String?
        var cursorPlan: AgentPlan?
        var store = AgentUsageStore()
        var previousLimits: [AgentProvider: AgentLimits] = [:]
        var warned: [String: (provider: AgentProvider, window: AgentLimitWindow)] = [:]
        var published = 0
        func publish() { published += 1 }
        func checkLimits() {}
    }

    private static func wait(_ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !predicate(), Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
        return predicate()
    }

    private static func store(_ suite: TestSuite) {
        let store = AgentUsageStore(), now = Date()
        let cursor = AgentUsageRecord(provider: .cursor, date: now, model: "unknown", project: "", session: "",
                                      tokens: AgentTokens(input: 10), cost: 2, savings: 0, reportedCost: true)
        let claude = AgentUsageRecord(provider: .claude, date: now, model: "unknown", project: "local", session: "s",
                                      tokens: AgentTokens(input: 3), cost: nil, savings: 0)
        store.apply([.usage(key: "claude", record: claude, billable: AgentBillable(tokens: claude.tokens))],
                    file: "claude.log", provider: .claude, tracksTurns: false, modified: now)
        store.replaceCursorUsage([cursor, cursor])
        var snapshot = store.snapshot(plans: [:], providers: [.cursor, .claude], now: now)
        suite.expect(snapshot.usage(.today).byProvider[.cursor]?.requests == 2
                     && snapshot.usage(.today).byProvider[.cursor]?.cost == 4,
                     "a Cursor export reaches the widget totals without merging identical requests")
        store.replaceCursorUsage([cursor])
        snapshot = store.snapshot(plans: [:], providers: [.cursor, .claude], now: now)
        suite.expect(snapshot.usage(.today).byProvider[.cursor]?.tokens.input == 10
                     && snapshot.usage(.today).byProvider[.claude]?.tokens.input == 3,
                     "a replacement updates cached widget totals and preserves local agent records")
        store.reprice()
        suite.expect(store.records.first(where: { $0.provider == .cursor })?.cost == 2,
                     "Cursor's reported API value survives a price-list update")
        store.setLimits(AgentLimits(provider: .cursor, windows: [], observedAt: now, source: .account))
        suite.expect(store.saved.records.map(\.record.provider) == [.claude]
                     && store.saved.limits.allSatisfy { $0.provider != .cursor },
                     "Cursor account history and limits never enter the on-disk log archive")
        store.replaceCursorUsage([])
        suite.expect(store.records.map(\.provider) == [.claude], "clearing a Cursor account preserves other providers")
    }

    static func run(_ suite: TestSuite) {
        store(suite)
        let now = Date()
        let record = AgentUsageRecord(provider: .cursor, date: now, model: "test", project: "", session: "",
                                      tokens: AgentTokens(input: 10), cost: 1, savings: 0, reportedCost: true)
        let window = AgentLimitWindow(id: "cursor.plan", kind: .other, minutes: 43200, scope: nil,
                                      usedPercent: 25, resetsAt: now.addingTimeInterval(86400))
        let limits = AgentLimits(provider: .cursor, windows: [window], observedAt: now, source: .account)
        func reading(_ account: String, records: [AgentUsageRecord]? = [record]) -> AgentCursorAccount.Reading {
            AgentCursorAccount.Reading(account: account,
                summary: AgentCursorUsage.Summary(limits: limits, plan: AgentPlan(name: "Pro", monthlyPrice: nil)), records: records)
        }
        let host = Host()
        defer { host.cancelCursorUsage(); NSRunningApplication.open = true }
        let before = AgentCursorAccount.calls
        NSRunningApplication.open = false
        host.refreshCursorUsage(now: now)
        suite.expect(host.cursorFailure == .closed && !host.cursorChecking && AgentCursorAccount.calls == before,
                     "a closed desktop app starts no credential read or network check")
        NSRunningApplication.open = true
        host.paused = true
        host.refreshCursorUsage(now: now)
        host.paused = false
        host.providers = []
        host.refreshCursorUsage(now: now)
        suite.expect(AgentCursorAccount.calls == before, "paused or disabled tracking starts no Cursor work")
        host.providers = [.cursor]
        AgentCursorAccount.configure(.success(reading("one")))
        host.refreshCursorUsage(now: now)
        suite.expect(wait { !host.cursorChecking && host.store.records.count == 1 }, "a completed check reaches the production store")
        suite.expect(host.cursorAccount == "one" && host.cursorPlan?.name == "Pro" && host.store.limits[.cursor] == limits,
                     "Cursor usage, limits and plan all belong to the same desktop account")
        host.refreshCursorUsage(now: now.addingTimeInterval(10))
        suite.expect(AgentCursorAccount.calls == before + 1, "opening the widget cannot bypass the refresh cadence")
        AgentCursorAccount.configure(.success(reading("one", records: nil)))
        host.refreshCursorUsage(now: now.addingTimeInterval(301))
        suite.expect(wait { !host.cursorChecking }, "an incomplete history check settles")
        suite.expect(host.cursorFailure == .incomplete && host.store.records.count == 1,
                     "incomplete same-account history preserves the last complete totals")
        AgentCursorAccount.configure(.success(reading("two", records: nil)), blocked: true)
        host.refreshCursorUsage(now: now.addingTimeInterval(602))
        suite.expect(wait { host.cursorAccount == "two" }, "account changes are delivered before a slow export completes")
        suite.expect(host.store.records.isEmpty && host.store.limits[.cursor] == nil && host.cursorPlan == nil,
                     "switching accounts clears old totals, limits and plan before fetching the replacement")
        host.cancelCursorUsage()
        host.paused = true
        AgentCursorAccount.configure(.success(reading("two")))
        _ = wait { host.cursorRequest == nil }
        suite.expect(host.store.records.isEmpty && !host.cursorChecking,
                     "a cancelled check cannot repopulate paused usage")
        host.paused = false
        host.cursorAttempted = .distantPast
        AgentCursorAccount.configure(.failure(.needsSignIn))
        host.store.replaceCursorUsage([record])
        host.refreshCursorUsage(now: now)
        suite.expect(wait { !host.cursorChecking && host.store.records.isEmpty }, "sign-out clears previously displayed account usage")
        suite.expect(host.cursorFailure == .needsSignIn, "sign-out points back to the desktop sign-in")
        host.cursorAttempted = .distantPast
        AgentCursorAccount.configure(.success(reading("two")), blocked: true)
        host.refreshCursorUsage(now: now)
        suite.expect(wait { host.cursorAccount == "two" }, "the next desktop session starts checking")
        NSRunningApplication.open = false
        host.refreshCursorUsage(now: now)
        AgentCursorAccount.configure(.success(reading("two")))
        suite.expect(!host.cursorChecking && host.cursorFailure == .closed && host.cursorRequest == nil,
                     "closing Cursor cancels an active check and exposes the desktop requirement")
    }
}
