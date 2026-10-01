// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Now card lists every session with its state, needs-you first.
enum AgentSessionBoardTests {
    private static let start = Date(timeIntervalSince1970: 1_790_000_000)

    private static func record(_ session: String, busy: Bool?, pid: Int32 = 1, changed: TimeInterval = 0,
                               status: AgentSessionStatus? = nil) -> AgentSessionRecord {
        AgentSessionRecord(pid: pid, session: session, cwd: "/code/\(session)", name: "\(session)-1",
                           status: status ?? busy.map { $0 ? .busy : .idle },
                           started: start, statusChanged: start.addingTimeInterval(changed))
    }

    private static func registry(_ records: [AgentSessionRecord], complete: Bool = true) -> AgentSessionRegistry {
        var registry = AgentSessionRegistry(running: Set(records.map(\.session)), ended: [], complete: complete, listed: true)
        for record in records { registry.records[record.session] = record }
        return registry
    }

    private static func approval(transcript: String?, cwd: String = "/code/a", agent: AgentProvider = .claude) -> ClaudeApprovalRequest {
        ClaudeApprovalRequest(agent: agent, cwd: cwd, toolName: "Bash", toolInput: [:], summary: "ls",
                              transcriptPath: transcript, alwaysRules: nil)
    }

    private static func store(_ processes: AgentSessionRegistry = AgentSessionRegistry()) -> AgentUsageStore {
        let store = AgentUsageStore()
        store.processes = processes
        return store
    }

    static func run(_ suite: TestSuite) {
        let now = start.addingTimeInterval(600)
        let tokens = AgentTokens(input: 100, output: 20)
        let usage = AgentUsageRecord(provider: .claude, date: start.addingTimeInterval(5), model: "claude-opus-5-5",
                                     project: "a", session: "a", tokens: tokens, cost: 0.5, savings: 0)

        // Claude: the process record says busy or idle.
        let busy = store(registry([record("a", busy: true), record("b", busy: false, changed: 30)]))
        busy.apply([.turnBegan(start), .usage(key: "k", record: usage, billable: AgentBillable(tokens: tokens))],
                   file: "/p/a.jsonl", provider: .claude, tracksTurns: true, modified: start, now: start)
        let rows = busy.sessions(now: now)
        let a = rows.first { $0.id == "a" }, b = rows.first { $0.id == "b" }
        suite.expect(rows.count == 2 && a?.activity == .working && a?.model == "claude-opus-5-5" && a?.cost == 0.5
                        && a?.name == "a-1" && a?.project == "a" && a?.pid == 1,
                     "a busy session works with its turn's model and cost")
        suite.expect(b?.activity == .quiet && b?.since == start.addingTimeInterval(30)
                        && AgentSessionBoard.state(b!, now: now, approval: nil) == .waiting,
                     "an idle session with no turn ended lately waits for you since its status changed")
        let alone = store(registry([record("c", busy: true)])).sessions(now: now)
        suite.expect(alone.count == 1 && alone[0].activity == .working && alone[0].model.isEmpty,
                     "a busy session shows from its record alone")

        // A permission prompt open in the terminal needs you, with or without the notch holding it.
        let asking = store(registry([record("w", busy: nil, changed: 20, status: .waiting)]))
        asking.apply([.turnBegan(start)], file: "/p/w.jsonl", provider: .claude, tracksTurns: true, modified: start)
        let askingRows = asking.sessions(now: now)
        suite.expect(askingRows.count == 1 && askingRows[0].activity == .asking
                        && askingRows[0].since == start.addingTimeInterval(20)
                        && AgentSessionBoard.state(askingRows[0], now: now, approval: nil) == .needsApproval
                        && AgentSessionBoard.needsYou(askingRows, now: now, approval: nil) == 1,
                     "a session waiting on a permission prompt needs approval")

        // Done, then waiting once the recent window passes; an error reads as one.
        let done = store(registry([record("a", busy: false), record("e", busy: false)]))
        done.apply([.turnBegan(start), .turnEnded(start.addingTimeInterval(60), completed: true, duration: nil)],
                   file: "/p/a.jsonl", provider: .claude, tracksTurns: true, modified: start, now: start.addingTimeInterval(60))
        done.apply([.turnBegan(start), .turnEnded(start.addingTimeInterval(60), completed: false, duration: nil, failed: true)],
                   file: "/p/e.jsonl", provider: .claude, tracksTurns: true, modified: start, now: start.addingTimeInterval(60))
        let ended = done.sessions(now: start.addingTimeInterval(70))
        let doneRow = ended.first { $0.id == "a" }!, failedRow = ended.first { $0.id == "e" }!
        suite.expect(AgentSessionBoard.state(doneRow, now: start.addingTimeInterval(70), approval: nil) == .done
                        && AgentSessionBoard.state(doneRow, now: start.addingTimeInterval(60 + 6 * 60), approval: nil) == .waiting,
                     "a finished turn reads as done, then as waiting after a few minutes")
        suite.expect(AgentSessionBoard.state(failedRow, now: start.addingTimeInterval(70), approval: nil) == .failed,
                     "a turn ended by an error reads as an error")
        suite.expect(AgentSessionBoard.movesWithClock(ended, from: start.addingTimeInterval(70), to: start.addingTimeInterval(70 + 5 * 60))
                        && !AgentSessionBoard.movesWithClock(ended, from: start.addingTimeInterval(70), to: start.addingTimeInterval(80)),
                     "the board moves with the clock only when done turns to waiting")
        var snapshot = AgentUsageSnapshot(loaded: true, now: start.addingTimeInterval(70))
        snapshot.sessions = ended
        suite.expect(AgentUsageSummary.movesWithClock(snapshot, now: start.addingTimeInterval(70 + 5 * 60)),
                     "a snapshot is published again when a done session turns to waiting")
        suite.expect(done.snapshot(plans: [:], providers: [.claude], now: now).sessions.count == 2
                        && done.snapshot(plans: [:], providers: [.codex], now: now).sessions.isEmpty,
                     "the snapshot carries the sessions of the agents shown")
        done.apply([.turnBegan(start.addingTimeInterval(90))], file: "/p/a.jsonl", provider: .claude, tracksTurns: true,
                   modified: start, now: start.addingTimeInterval(90))
        suite.expect(done.recent["/p/a.jsonl"] == nil && done.recent["/p/e.jsonl"] != nil, "a new turn clears the one that ended")
        done.forget(file: "/p/e.jsonl")
        suite.expect(done.recent.isEmpty, "a removed log forgets its ended turn")

        // The registry wins over the logs.
        let stale = store(registry([record("a", busy: false)]))
        stale.apply([.turnBegan(start)], file: "/p/a.jsonl", provider: .claude, tracksTurns: true, modified: start)
        stale.apply([.turnBegan(start)], file: "/p/gone.jsonl", provider: .claude, tracksTurns: true, modified: start)
        let staleRows = stale.sessions(now: now)
        suite.expect(staleRows.count == 1 && staleRows[0].activity == .quiet,
                     "an idle record overrides a turn left open, and a session with no process has no row")
        let partial = store(registry([record("a", busy: nil)], complete: false))
        partial.apply([.turnBegan(start)], file: "/p/a.jsonl", provider: .claude, tracksTurns: true, modified: start)
        partial.apply([.turnBegan(start)], file: "/p/b.jsonl", provider: .claude, tracksTurns: true, modified: start)
        let partialRows = partial.sessions(now: now)
        suite.expect(partialRows.count == 2 && partialRows.allSatisfy { $0.activity == .working },
                     "an unknown status and an incomplete read fall back to the logs")
        let unlisted = store()
        unlisted.apply([.turnBegan(start)], file: "/p/a.jsonl", provider: .claude, tracksTurns: true, modified: start)
        suite.expect(unlisted.sessions(now: now).map(\.id) == ["a"], "without records, Claude sessions come from the logs")

        // Codex: done, then waiting, then gone; quiet reads as waiting.
        let codex = store()
        let log = "/codex/rollout-1.jsonl"
        codex.apply([.turnBegan(start), .turnEnded(start.addingTimeInterval(60), completed: true, duration: nil)],
                    file: log, provider: .codex, tracksTurns: true, modified: start, now: start.addingTimeInterval(60))
        let codexDone = codex.sessions(now: start.addingTimeInterval(70))
        suite.expect(codexDone.map(\.id) == [log]
                        && AgentSessionBoard.state(codexDone[0], now: start.addingTimeInterval(70), approval: nil) == .done
                        && AgentSessionBoard.state(codexDone[0], now: start.addingTimeInterval(60 + 6 * 60), approval: nil) == .waiting,
                     "a Codex task that completes reads as done, then waiting")
        codex.closeIdleTurns(now: start.addingTimeInterval(60 + 31 * 60), after: NotchAgentSupport.idleTurn)
        suite.expect(codex.sessions(now: start.addingTimeInterval(60 + 31 * 60)).isEmpty, "a Codex session leaves the board after half an hour")
        let quiet = store()
        quiet.apply([.turnBegan(start)], file: log, provider: .codex, tracksTurns: true, modified: start)
        quiet.closeIdleTurns(now: start.addingTimeInterval(1200), after: NotchAgentSupport.idleTurn)
        let quietRows = quiet.sessions(now: start.addingTimeInterval(1200))
        suite.expect(quietRows.count == 1 && AgentSessionBoard.state(quietRows[0], now: now, approval: nil) == .waiting,
                     "a quiet Codex turn reads as waiting")

        // An approval belongs to its session; sorting puts needs-you first.
        let many = store(registry([record("a", busy: true), record("b", busy: true), record("c", busy: false),
                                   record("d", busy: false)]))
        many.apply([.turnBegan(start), .turnEnded(start.addingTimeInterval(500), completed: true, duration: nil)],
                   file: "/p/c.jsonl", provider: .claude, tracksTurns: true, modified: start, now: start.addingTimeInterval(500))
        let board = many.sessions(now: now)
        let ask = approval(transcript: "/x/b.jsonl")
        suite.expect(board.filter { AgentSessionBoard.state($0, now: now, approval: ask) == .needsApproval }.map(\.id) == ["b"],
                     "an approval marks only the session its transcript names")
        suite.expect(board.filter { AgentSessionBoard.state($0, now: now, approval: approval(transcript: nil, cwd: "/code/a")) == .needsApproval }
                        .map(\.id) == ["a"]
                        && board.allSatisfy { AgentSessionBoard.state($0, now: now, approval: approval(transcript: nil, agent: .codex)) != .needsApproval },
                     "without a transcript the folder names the session, for the same agent only")
        suite.expect(AgentSessionBoard.sorted(board, now: now, approval: ask).map(\.id) == ["b", "c", "a", "d"],
                     "needs approval, then done, then working, then waiting")
        suite.expect(AgentSessionBoard.needsYou(board, now: now, approval: ask) == 2
                        && AgentSessionBoard.needsYou(board, now: now, approval: nil) == 1
                        && AgentSessionBoard.needsYou(board, now: now, approval: approval(transcript: "/x/zz.jsonl")) == 2,
                     "needs-you counts approvals and finished turns, never idle sessions")

        // The Now card grows with its sessions.
        let live = NotchAgentTile(card: .live, provider: nil), spend = NotchAgentTile(card: .spend, provider: nil)
        let heights = [0, 2, 3, 4, 9].map { NotchAgentSupport.height(of: [live, spend], boardRows: $0) }
        suite.expect(heights == [96, 96, 112, 136, 136] && NotchAgentSupport.height(of: [spend], boardRows: 9) == 96,
                     "the Now card grows to four sessions, then scrolls")
        suite.expect(NotchAgentSupport.contentHeight([[live], [spend]], boardRows: 4) == 136 + NotchAgentSupport.spacing + 96,
                     "the page grows with the Now card")
    }
}
