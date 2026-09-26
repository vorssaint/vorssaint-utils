// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One Claude Code process blocked waiting on a person's answer.
struct AgentWaitingSession: Identifiable, Equatable {
    let id: Int32 // pid
    let name: String
}

/// Decides which Claude Code session-status files count as waiting on a
/// reply, kept pure so it is testable without real files or processes.
enum AgentWaitSupport {
    /// A wait this short is normal turnaround, not something worth a
    /// notice — long enough that someone approving prompts back to back at
    /// the terminal never sees one for a prompt already in front of them.
    static let minimumNoticeWait: TimeInterval = 3

    /// One session file's fields, already parsed. `modifiedAt` is the
    /// file's own modification time, microseconds since the epoch, the same
    /// unit `KillProcessService.startTime(for:)` reports.
    struct SessionStatus {
        let status: String?
        let pid: Int32?
        let name: String?
        let cwd: String?
        let modifiedAt: UInt64?
    }

    /// The CLI's own name for the session, or the last path component of its
    /// working directory when the name is missing or blank.
    static func sessionName(_ status: SessionStatus) -> String? {
        (status.name.flatMap { $0.isEmpty ? nil : $0 }) ?? status.cwd.map { ($0 as NSString).lastPathComponent }
    }

    /// Which of the given statuses are genuinely waiting on a reply, sorted
    /// by name. `processStartTime` stands in for a liveness check like
    /// `kill(pid, 0)`, but a bare liveness check is not enough: once a
    /// crashed or force-quit Claude process's file is left behind, macOS can
    /// hand its pid to an unrelated process of the same user, and that
    /// process is alive too. A process that started after the file was last
    /// written cannot be the one that wrote it, so a session only counts
    /// when its pid's process existed no later than the file's own
    /// modification time.
    static func waitingSessions(_ statuses: [SessionStatus],
                                processStartTime: (Int32) -> UInt64?) -> [AgentWaitingSession] {
        statuses.compactMap { status -> AgentWaitingSession? in
            guard status.status == "waiting", let pid = status.pid,
                  let modifiedAt = status.modifiedAt,
                  let startedAt = processStartTime(pid), startedAt <= modifiedAt,
                  let name = sessionName(status) else { return nil }
            return AgentWaitingSession(id: pid, name: name)
        }.sorted { $0.name < $1.name }
    }

    /// Sessions present now but not in the previous scan — a transition
    /// worth a notice, once `waitingLongEnough` says it has actually held.
    /// Kept separate from the scan itself so a stop that clears `waiting`
    /// produces no further notices without this needing to know why the
    /// list is now empty.
    static func newlyWaitingSessions(current: [AgentWaitingSession],
                                     previous: [AgentWaitingSession]) -> [AgentWaitingSession] {
        let previousIDs = Set(previous.map(\.id))
        return current.filter { !previousIDs.contains($0.id) }
    }

    /// Whether a session that has been waiting since `since` has now held
    /// long enough to be worth a notice.
    static func waitedLongEnough(since: Date, now: Date, minimum: TimeInterval = minimumNoticeWait) -> Bool {
        now.timeIntervalSince(since) >= minimum
    }
}
