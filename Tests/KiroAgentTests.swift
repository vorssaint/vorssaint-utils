// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Kiro's session folders, read through the production reader and store.
enum KiroAgentTests {
    static func run(_ suite: TestSuite) {
        let home = FileManager.default.temporaryDirectory.appending(path: "vorss-kiro-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appending(path: ".kiro/sessions")
        let event = sessions.appending(path: "a1b2/sess_k1")
        let legacy = sessions.appending(path: "cli")
        do {
            for folder in [event, legacy, sessions.appending(path: "a1b2/sess_k1/tool-outputs")] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
        } catch {
            suite.expect(false, "the Kiro fixture creates its folders: \(error)")
            return
        }
        roots(suite, home: home, sessions: sessions, event: event, legacy: legacy)
        eventLog(suite, folder: event)
        snapshot(suite, folder: legacy)
        archive(suite)
        account(suite, folder: home)
    }

    private static func write(_ text: String, to url: URL) {
        try! Data(text.utf8).write(to: url)
    }

    private static func roots(_ suite: TestSuite, home: URL, sessions: URL, event: URL, legacy: URL) {
        write("", to: event.appending(path: "messages.jsonl"))
        write("{}", to: event.appending(path: "session.json"))
        write("{}", to: legacy.appending(path: "old.json"))
        write("", to: legacy.appending(path: "old.jsonl"))
        write("x", to: event.appending(path: "tool-outputs/out.txt"))
        write("", to: sessions.appending(path: "dashboard-search.db"))
        guard let root = AgentLogRoot.all(home: home).first(where: { $0.provider == .kiro }) else {
            suite.expect(false, "Kiro sessions are a discovered local root")
            return
        }
        let base = root.url.path
        suite.expect(root.accepts(base + "/a1b2/sess_k1/messages.jsonl") && root.accepts(base + "/cli/old.json")
                        && !root.accepts(base + "/cli/old.jsonl") && !root.accepts(base + "/a1b2/sess_k1/session.json")
                        && !root.accepts(base + "/a1b2/sess_k1/tool-outputs/out.json")
                        && !root.accepts(base + "/.index/sess_k1/messages.jsonl")
                        && !root.accepts(base + "/cli/sess_x/messages.jsonl"),
                     "Kiro admits only session event logs and older session documents")
        let found = Set(AgentLogReader.discover([root], since: .distantPast).map(\.path))
        suite.expect(found == [base + "/a1b2/sess_k1/messages.jsonl", base + "/cli/old.json"],
                     "Kiro discovery finds both session shapes without walking tool output")
        suite.expect(AgentLogReader.isLog(base + "/cli/old.json"), "a Kiro session document counts as a log")
    }

    private static func eventLog(_ suite: TestSuite, folder: URL) {
        let now = Date()
        let start = now.addingTimeInterval(-30)
        func stamp(_ offset: TimeInterval) -> String {
            ISO8601DateFormatter().string(from: start.addingTimeInterval(offset))
        }
        write(#"{"id":"sess_k1","workspacePaths":["/Users/me/code/island"],"modelId":"claude-sonnet-5"}"#,
              to: folder.appending(path: "session.json"))
        let log = folder.appending(path: "messages.jsonl")
        var lines = [
            #"{"id":"1","timestamp":"\#(stamp(0))","payload":{"type":"user","content":"private"}}"#,
            #"{"id":"2","timestamp":"\#(stamp(0))","payload":{"type":"turn_start","executionId":"e1"}}"#,
            #"{"id":"3","timestamp":"\#(stamp(5))","payload":{"type":"assistant","operationType":"Reasoning","reasoningModelId":"qdev::claude-opus-5.5","content":"private"}}"#,
        ]
        write(lines.joined(separator: "\n") + "\n", to: log)
        let store = AgentUsageStore()
        store.reportsTransitions = true
        let cursor = AgentLogCursor(path: log.path, provider: .kiro)
        func read() -> [AgentUsageEvent] {
            var events: [AgentUsageEvent] = []
            AgentLogReader.readAppended(cursor) { line in
                let entries = KiroReader().parse(line, state: &cursor.state, now: now)
                events += store.apply(entries, file: cursor.path, provider: .kiro, tracksTurns: cursor.tracksTurns,
                                      modified: cursor.modified, now: now)
            }
            return events
        }
        _ = read()
        suite.expect(store.turns[log.path]?.project == "island" && store.turns[log.path]?.model == "claude-opus-5.5",
                     "a working Kiro turn shows the workspace from session.json and the replying model")
        lines += [
            #"{"id":"4","timestamp":"\#(stamp(20))","payload":{"type":"usage_summary","promptTurnSummaries":[{"unit":"credit","usage":2.0}],"status":"success","executionId":"e1","requestIds":["a"]}}"#,
            #"{"id":"5","timestamp":"\#(stamp(21))","payload":{"type":"turn_end","stopReason":"end_turn","executionId":"e1"}}"#,
        ]
        write(lines.joined(separator: "\n") + "\n", to: log)
        let events = read()
        suite.expect(events == [.finished(provider: .kiro, duration: 21, cost: 0, tokens: 0, project: "island")],
                     "a finished Kiro turn is reported; the plan covers its credits")
        suite.expect(store.records.count == 1 && store.records[0].session == "sess_k1" && store.records[0].requests == 1,
                     "the Kiro event log is read on from where it stopped, without its header again")
    }

    private static func snapshot(_ suite: TestSuite, folder: URL) {
        let now = Date()
        let file = folder.appending(path: "old.json")
        func turn(_ end: String?, credits: [Double]) -> String {
            let usage = credits.map { #"{"value":\#($0),"unit":"credit","unitPlural":"credits"}"# }.joined(separator: ",")
            let ending = end.map { #""end_timestamp":"\#($0)","# } ?? ""
            return #"{\#(ending)"model":"claude-sonnet-5","total_request_count":2,"input_token_count":0,"metering_usage":[\#(usage)],"result":{"Ok":{"role":"assistant"}}}"#
        }
        func document(_ turns: [String]) -> String {
            // Pretty-printed and without a final newline, as Kiro writes it.
            """
            {
              "session_id": "old",
              "cwd": "/Users/me/code/dotfiles",
              "session_state": {
                "conversation_metadata": {
                  "user_turn_metadatas": [\(turns.joined(separator: ","))]
                }
              }
            }
            """
        }
        let store = AgentUsageStore()
        let cursor = AgentLogCursor(path: file.path, provider: .kiro)
        var handed = 0
        func read() {
            AgentLogReader.readAppended(cursor) { line in
                handed += 1
                store.apply(KiroReader().parse(line, state: &cursor.state, now: now), file: cursor.path,
                            provider: .kiro, tracksTurns: cursor.tracksTurns, modified: cursor.modified, now: now)
            }
        }
        let first = turn("2026-09-22T12:00:00.000Z", credits: [0.25, 0.5])
        write(document([first, turn(nil, credits: [9])]), to: file)
        read()
        suite.expect(store.records.count == 1 && store.records[0].cost == 0 && store.records[0].credits == 0.75
                        && store.records[0].project == "dotfiles" && store.records[0].requests == 2,
                     "an older Kiro session counts each finished turn")
        read()
        suite.expect(handed == 1, "an unchanged Kiro session document is not read again")
        write("{\"session_id\": \"old\", \"cwd\"", to: file)
        read()
        suite.expect(store.records.count == 1, "a Kiro session document caught mid-write changes nothing")
        write(document([first, turn("2026-09-22T12:05:00.000Z", credits: [1])]), to: file)
        read()
        suite.expect(store.records.count == 2 && store.records.map(\.requests) == [2, 2],
                     "a rewritten Kiro session document adds only its new turn")
    }

    /// Reported charges keep their cost through a relaunch, where repricing
    /// from the list would leave tokenless credits worth nothing.
    private static func archive(_ suite: TestSuite) {
        let store = AgentUsageStore()
        let record = AgentUsageRecord(provider: .kiro, date: Date(), model: "claude-opus-5.5", project: "p",
                                      session: "s", requests: 1, tokens: AgentTokens(),
                                      cost: 1.25, savings: 0, reportedCost: true, credits: 3)
        store.apply([.usage(key: "kiro:s:e", record: record, billable: AgentBillable(isAggregate: true))],
                    file: "/k/messages.jsonl", provider: .kiro, tracksTurns: true, modified: Date())
        let contents = AgentUsageArchive.Contents(providers: [.kiro], store: store.saved, cursors: [])
        guard let decoded = AgentUsageArchive.decode(AgentUsageArchive.encode(contents, build: "kiro"), build: "kiro")
        else {
            suite.expect(false, "a Kiro archive decodes")
            return
        }
        let resumed = AgentUsageStore(saved: decoded.store)
        resumed.reprice()
        suite.expect(resumed.records == [record], "a Kiro charge survives the archive and a reprice")
    }

    /// The month's credits as Kiro's account answer gives them.
    private static func account(_ suite: TestSuite, folder: URL) {
        let observed = Date(timeIntervalSince1970: 1_790_000_000)
        func answer(used: Double, overage: Double, charges: Double) -> [String: Any] {
            ["success": true, "message": "Plan: KIRO POWER | 1 usage breakdowns",
             "data": ["planName": "KIRO POWER", "billingCycleReset": "2026-11-01", "overagesEnabled": true,
                      "usageBreakdowns": [["resourceType": "CREDIT", "displayName": "Credits", "used": used,
                                           "limit": 10_000, "percentage": 10, "currentOverages": overage,
                                           "overageRate": 0.04, "overageCharges": charges, "currency": "USD",
                                           "hasLimit": true]]]]
        }
        guard case .success(let within) = AgentKiroServer.summary(answer(used: 1045.08, overage: 0, charges: 0),
                                                                  observed: observed),
              let window = within.limits.windows.first, let credits = window.credits else {
            suite.expect(false, "Kiro's account answer gives the month's credits")
            return
        }
        suite.expect(within.plan?.name == "Power" && within.limits.provider == .kiro && within.limits.source == .account
                        && abs(window.usedPercent - 10.4508) < 0.0001 && credits.limit == 10_000
                        && abs(credits.remaining - 8954.92) < 0.0001 && !credits.isOver
                        && window.resetsAt == Date(timeIntervalSince1970: 1_793_491_200),
                     "Kiro's credits give the plan, the share used, what is left and the month's renewal")
        guard case .success(let over) = AgentKiroServer.summary(answer(used: 10_523.22, overage: 523.22, charges: 20.93),
                                                                observed: observed),
              let past = over.limits.windows.first, let spent = past.credits else {
            suite.expect(false, "Kiro's account answer past the limit still reads")
            return
        }
        suite.expect(past.usedPercent == 100 && spent.isOver && spent.overage == 523.22 && spent.overageCharges == 20.93
                        && abs(spent.usedShare - 1.052322) < 0.000001 && spent.remaining == 0,
                     "credits past Kiro's limit keep the full share and bill the overage")
        suite.expect(AgentFormat.percent(spent.usedShare, capped: false, locale: Locale(identifier: "en_US")) == "105%"
                        && AgentFormat.percent(spent.usedShare, locale: Locale(identifier: "en_US")) == "100%"
                        && AgentFormat.credits(8954.92, locale: Locale(identifier: "en_US")) == "8,955"
                        && AgentFormat.credits(12.46, locale: Locale(identifier: "en_US")) == "12.5",
                     "credits read as whole numbers from a hundred, and their share can pass 100%")
        var noCharges = answer(used: 1_100, overage: 100, charges: 0)
        var data = noCharges["data"] as! [String: Any]
        var breakdown = (data["usageBreakdowns"] as! [[String: Any]])[0]
        breakdown.removeValue(forKey: "overageCharges")
        data["usageBreakdowns"] = [breakdown]
        noCharges["data"] = data
        if case .success(let derived) = AgentKiroServer.summary(noCharges, observed: observed) {
            suite.expect(derived.limits.windows.first?.credits?.overageCharges == 100 * 0.04,
                         "an overage without its charge is priced at the overage rate")
        } else {
            suite.expect(false, "an answer without its overage charge still reads")
        }
        overage(suite, answer: answer, observed: observed)
        summary(suite)
        suite.expect(AgentKiroServer.summary(["success": false, "message": "Not logged in"], observed: observed)
                        == .failure(.needsSignIn)
                        && AgentKiroServer.summary(["success": true, "data": ["usageBreakdowns": []]], observed: observed)
                        == .failure(.unreachable)
                        && AgentKiroServer.failure(["code": -32601, "message": "Method not found"]) == .outdated,
                     "a signed-out Kiro, an answer without credits and an old Kiro each say so")
        suite.expect(AgentKiroServer.current(within.limits, now: observed) == within.limits
                        && AgentKiroServer.current(within.limits, now: Date(timeIntervalSince1970: 1_793_491_200)) == nil,
                     "the month's reading lasts until the month renews")
        suite.expect(AgentKiroServer.interval(after: nil, pageVisible: true) == 60
                        && AgentKiroServer.interval(after: .needsSignIn, pageVisible: true) == 30 * 60,
                     "Kiro is asked every minute while the page shows, and seldom while it cannot answer")

        // A stand-in for Kiro CLI that answers only the two questions asked,
        // after a notification, as Kiro's own server sends them unasked.
        let script = folder.appending(path: "kiro-cli")
        write("""
        #!/bin/sh
        [ "$*" = "acp --agent-engine v3" ] || exit 3
        while IFS= read -r line; do
          case "$line" in
            *'"initialize"'*) printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1}}' ;;
            *'_kiro/account/getUsage'*)
              printf '%s\\n' '{"jsonrpc":"2.0","method":"_kiro/mcp/status","params":{}}'
              printf '%s\\n' '{"jsonrpc":"2.0","id":2,"result":{"success":true,"data":{"planName":"KIRO PRO","billingCycleReset":"2026-11-01","usageBreakdowns":[{"resourceType":"CREDIT","used":250,"limit":1000,"currentOverages":0,"overageRate":0.04,"overageCharges":0,"hasLimit":true}]}}}' ;;
          esac
        done
        """, to: script)
        chmod(script.path, 0o755)
        let result = AgentKiroServer.Request().run(script, environment: ["PATH": "/usr/bin:/bin"], timeout: 5)
        if case .success(let summary) = result {
            suite.expect(summary.plan?.name == "Pro" && summary.limits.windows.first?.credits?.used == 250,
                         "Kiro's own server is asked for the account's credits, and nothing else")
        } else {
            suite.expect(false, "Kiro's own server answers the credits question: \(result)")
        }
        let cancelled = AgentKiroServer.Request()
        cancelled.cancel()
        suite.expect(cancelled.run(script, environment: [:], timeout: 5) == .failure(.unreachable),
                     "a cancelled Kiro check never starts Kiro")
    }

    /// Only credits past the plan's allowance cost anything, and they count
    /// as spending as the account reports them, once each.
    private static func overage(_ suite: TestSuite, answer: (Double, Double, Double) -> [String: Any],
                                observed: Date) {
        func limits(_ used: Double, _ over: Double, _ charges: Double, at offset: TimeInterval) -> AgentLimits {
            guard case .success(let summary) = AgentKiroServer.summary(answer(used, over, charges),
                                                                       observed: observed.addingTimeInterval(offset))
            else { fatalError("the overage fixture reads") }
            return summary.limits
        }
        let store = AgentUsageStore()
        func check(_ reading: AgentLimits) -> Bool {
            guard let charge = AgentKiroServer.overage(reading, recorded: store.records) else { return false }
            store.apply([charge], file: AgentKiroServer.accountSource, provider: .kiro, tracksTurns: false,
                        modified: reading.observedAt)
            return true
        }
        let spent = { store.records.reduce(0.0) { $0 + ($1.cost ?? 0) } }
        suite.expect(!check(limits(9_000, 0, 0, at: 0)) && store.records.isEmpty,
                     "credits within Kiro's plan add no spending")
        suite.expect(check(limits(10_100, 100, 4, at: 60)) && abs(spent() - 4) < 0.0001
                        && store.records.last?.date == observed.addingTimeInterval(60),
                     "the overage counts as spending when the account first reports it")
        suite.expect(!check(limits(10_100, 100, 4.001, at: 120)) && check(limits(10_150, 150, 6, at: 180))
                        && abs(spent() - 6) < 0.0001 && store.records.count == 2,
                     "only what the overage grew by is added, and a fraction of a cent is no news")
        let saved = AgentUsageArchive.Contents(providers: [.kiro], store: store.saved, cursors: [])
        let resumed = AgentUsageArchive.resume(saved, logs: [], since: .distantPast).store
        suite.expect(resumed.records == store.records
                        && AgentKiroServer.overage(limits(10_150, 150, 6, at: 240), recorded: resumed.records) == nil,
                     "overage charges outlast a relaunch, though no log holds them, and are not counted again")
    }

    /// Spending holds only what was charged; the other cards show the
    /// credits Kiro's turns used, and never the overage as anyone's work.
    private static func summary(_ suite: TestSuite) {
        let now = Date()
        let turn = AgentUsageRecord(provider: .kiro, date: now.addingTimeInterval(-60), model: "claude-opus-5.5",
                                    project: "island", session: "sess_k", requests: 2, tokens: AgentTokens(), cost: 0,
                                    savings: 0, reportedCost: true, credits: 12.5)
        let charge = AgentUsageRecord(provider: .kiro, date: now.addingTimeInterval(-30), model: "", project: "",
                                      session: AgentKiroServer.overageSession(resets: now.addingTimeInterval(86_400)),
                                      requests: 0, tokens: AgentTokens(), cost: 4, savings: 0, reportedCost: true)
        let snapshot = AgentUsageSummary.snapshot(records: [turn, charge], limits: [:], live: [], plans: [:],
                                                  providers: [.kiro], now: now)
        let today = snapshot.usage(.today)
        suite.expect(today.total.cost == 4 && today.byProvider[.kiro]?.cost == 4 && today.work.cost == 0
                        && today.work.credits == 12.5,
                     "only Kiro's overage is spending; its turns' credits are work")
        suite.expect(today.models.map(\.name) == [AgentPricing.displayName("claude-opus-5.5")] && today.models.first?.totals.credits == 12.5
                        && today.projects.map(\.name) == ["island"]
                        && snapshot.days.last?.total.cost == 0 && snapshot.days.last?.total.credits == 12.5,
                     "the overage joins no model, project or day; the turns' credits do")
        let english = Locale(identifier: "en_US")
        let label = { (count: String) in count + " credits" }
        suite.expect(AgentFormat.use(today.models[0].totals, byCost: true, credits: label, locale: english) == "12.5 credits"
                        && AgentFormat.use(AgentTotals(cost: 2), byCost: true, credits: label, locale: english) == "$2.00"
                        && today.models[0].totals.use(byCost: true) > 0,
                     "Kiro's use reads in credits, other agents' in dollars, and its bars still have a length")
    }
}

