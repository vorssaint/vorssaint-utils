// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What a session record's `status` says. "waiting" is a permission prompt
/// open in the terminal, seen with Claude Code 2.1.287.
enum AgentSessionStatus: String, Equatable {
    case busy, idle, waiting
}

/// A running Claude session as its `sessions/<pid>.json` record describes it.
struct AgentSessionRecord: Equatable {
    let pid: Int32
    let session: String
    let cwd: String
    let name: String
    /// Nil for any other value, which proves nothing.
    let status: AgentSessionStatus?
    let started: Date?
    let statusChanged: Date?
}

/// A turn that ended a short while ago, kept so the board can say so.
struct AgentEndedTurn: Equatable {
    let turn: AgentLiveSession
    let ended: Date
    let failed: Bool
}

enum AgentSessionActivity: Equatable {
    case working
    /// Blocked on a permission prompt.
    case asking
    case quiet
    case ended(Date, failed: Bool)
}

/// One line on the board. Holds no prompt, reply or tool output.
struct AgentSessionRow: Equatable, Identifiable {
    /// Claude: the session id; Codex: the log path.
    let id: String
    let provider: AgentProvider
    let project: String
    /// The name Claude Code gives the session.
    let name: String?
    let pid: Int32?
    /// The folder the process runs in, from its record.
    let cwd: String?
    /// When the turn began, else when the session did.
    let started: Date
    /// When the current activity began.
    let since: Date
    let model: String
    let tokens: AgentTokens
    let cost: Double
    let activity: AgentSessionActivity
}

enum AgentSessionState: Equatable {
    case needsApproval, working, failed, done, waiting
}

enum AgentSessionBoard {
    /// How long Done or Error shows before the session reads as waiting.
    static let recentWindow = AgentUsageStore.lateEnd
    /// How long a session without a process record stays on the board after
    /// its last activity.
    // ponytail: Codex keeps no process record; a process scan can keep its rows alive.
    static let codexWindow: TimeInterval = 30 * 60

    static func sessionID(_ file: String) -> String {
        ((file as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    static func rows(turns: [String: AgentLiveSession], waiting: [String: AgentLiveSession],
                     recent: [String: AgentEndedTurn], registry: AgentSessionRegistry, now: Date) -> [AgentSessionRow] {
        var rows: [AgentSessionRow] = []
        var files: [String: String] = [:]
        for file in Set(turns.keys).union(waiting.keys).union(recent.keys) { files[sessionID(file)] = file }
        var covered: Set<String> = []
        if registry.listed {
            for record in registry.records.values {
                covered.insert(record.session)
                let file = files[record.session]
                let turn = file.flatMap { turns[$0] }
                let quiet = file.flatMap { waiting[$0] }
                let ended = file.flatMap { recent[$0] }
                let known = turn ?? quiet ?? ended?.turn
                let opened = record.started ?? record.statusChanged ?? now
                let activity: AgentSessionActivity
                let since: Date
                switch record.status {
                case .busy?:
                    activity = .working
                    since = (turn ?? quiet)?.started ?? record.statusChanged ?? opened
                case .waiting?:
                    activity = .asking
                    since = record.statusChanged ?? opened
                case .idle?:
                    // The process says so even when a stale turn reads as open.
                    activity = ended.map { .ended($0.ended, failed: $0.failed) } ?? .quiet
                    since = ended?.ended ?? record.statusChanged ?? opened
                case .none:
                    (activity, since) = storeActivity(turn: turn, quiet: quiet, ended: ended, fallback: opened)
                }
                let working = activity == .working ? (turn ?? quiet) : known
                rows.append(AgentSessionRow(
                    id: record.session, provider: .claude,
                    project: AgentLogParser.projectName(record.cwd).isEmpty ? known?.project ?? "" : AgentLogParser.projectName(record.cwd),
                    name: record.name.isEmpty ? nil : record.name, pid: record.pid, cwd: record.cwd,
                    started: (turn ?? quiet)?.started ?? opened, since: since,
                    model: working?.model ?? "", tokens: working?.tokens ?? AgentTokens(), cost: working?.cost ?? 0,
                    activity: activity))
            }
        }
        for (session, file) in files where !covered.contains(session) {
            let turn = turns[file], quiet = waiting[file], ended = recent[file]
            guard let known = turn ?? quiet ?? ended?.turn else { continue }
            // A complete list without the session means its process is gone.
            if known.provider == .claude, registry.listed, registry.complete { continue }
            let last = ended?.ended ?? known.lastActivity
            guard turn != nil || now.timeIntervalSince(last) < codexWindow else { continue }
            let (activity, since) = storeActivity(turn: turn, quiet: quiet, ended: ended, fallback: known.started)
            rows.append(AgentSessionRow(
                id: known.provider == .claude ? session : file, provider: known.provider, project: known.project,
                name: nil, pid: nil, cwd: nil, started: known.started, since: since, model: known.model, tokens: known.tokens,
                cost: known.cost, activity: activity))
        }
        return rows
    }

    private static func storeActivity(turn: AgentLiveSession?, quiet: AgentLiveSession?, ended: AgentEndedTurn?,
                                      fallback: Date) -> (AgentSessionActivity, Date) {
        if let turn { return (.working, turn.started) }
        if let quiet { return (.quiet, quiet.lastActivity) }
        if let ended { return (.ended(ended.ended, failed: ended.failed), ended.ended) }
        return (.quiet, fallback)
    }

    static func state(_ row: AgentSessionRow, now: Date, approval: ClaudeApprovalRequest?) -> AgentSessionState {
        if let approval, matches(row, approval) { return .needsApproval }
        switch row.activity {
        case .working: return .working
        case .asking: return .needsApproval
        case .ended(let at, let failed) where now.timeIntervalSince(at) < recentWindow: return failed ? .failed : .done
        default: return .waiting
        }
    }

    /// The board row an approval came from, if the board lists it.
    static func row(for approval: ClaudeApprovalRequest, in rows: [AgentSessionRow]) -> AgentSessionRow? {
        rows.first { matches($0, approval) }
    }

    /// Whether a click can find the row's process: Claude rows carry a pid,
    /// Codex rows find theirs from the rollout.
    static func canJump(_ row: AgentSessionRow) -> Bool {
        row.pid != nil || row.provider == .codex
    }

    /// The transcript names the session; without one, the folder does.
    private static func matches(_ row: AgentSessionRow, _ approval: ClaudeApprovalRequest) -> Bool {
        guard row.provider == approval.agent else { return false }
        if let transcript = approval.transcriptPath, !transcript.isEmpty { return sessionID(transcript) == sessionID(row.id) }
        return approval.project == row.project
    }

    /// Needs you first (approval, error, done), then working, then waiting;
    /// newest first inside each group.
    static func sorted(_ rows: [AgentSessionRow], now: Date, approval: ClaudeApprovalRequest?) -> [AgentSessionRow] {
        let order: [AgentSessionState] = [.needsApproval, .failed, .done, .working, .waiting]
        let ranked = rows.map { (row: $0, rank: order.firstIndex(of: state($0, now: now, approval: approval)) ?? 4) }
        return ranked.sorted { left, right in
            if left.rank != right.rank { return left.rank < right.rank }
            if left.row.since != right.row.since { return left.row.since > right.row.since }
            return left.row.id < right.row.id
        }.map(\.row)
    }

    /// Sessions that wait on the person because something happened. An idle
    /// session does not count: nothing asked for anyone. An approval from a
    /// session the board does not list still counts.
    static func needsYou(_ rows: [AgentSessionRow], now: Date, approval: ClaudeApprovalRequest?) -> Int {
        let states = rows.map { state($0, now: now, approval: approval) }
        let unlisted = approval != nil && !states.contains(.needsApproval) ? 1 : 0
        return states.filter { [.needsApproval, .failed, .done].contains($0) }.count + unlisted
    }

    /// Whether the board reads differently at `now` with nothing new read.
    static func movesWithClock(_ rows: [AgentSessionRow], from then: Date, to now: Date) -> Bool {
        rows.contains {
            guard case .ended(let at, _) = $0.activity else { return false }
            return (then.timeIntervalSince(at) < recentWindow) != (now.timeIntervalSince(at) < recentWindow)
        }
    }
}
