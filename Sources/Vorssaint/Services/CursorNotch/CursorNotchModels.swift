// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the closed island and the Cursor page say the agent is doing.
enum CursorLiveState: String, Equatable {
    case idle
    case sent
    case thinking
    case reading
    case searching
    case editing
    case running
    case waiting
    case subagent
    case done
    case stopped
    case failed
    case quiet

    /// A turn that is still moving. Quiet replaces these after ten minutes.
    var isWorking: Bool {
        switch self {
        case .sent, .thinking, .reading, .searching, .editing, .running, .waiting, .subagent:
            return true
        case .idle, .done, .stopped, .failed, .quiet:
            return false
        }
    }

    var isFinished: Bool {
        switch self {
        case .done, .stopped, .failed: return true
        default: return false
        }
    }
}

enum CursorSessionOrigin: String, Equatable {
    case app
    case terminal
}

enum CursorStepStatus: Equatable {
    case running
    case done
    case stopped
    case denied
    case failed
}

/// The words of one timeline row. The page localizes them.
enum CursorStepLabel: Equatable {
    case read(String)
    case search(String)
    case edit(String)
    case delete(String)
    case run(String)
    case mcp(server: String, tool: String)
    case subagent(String)
    case tool(String)
}

struct CursorStep: Identifiable, Equatable {
    var id: String
    var label: CursorStepLabel
    var status: CursorStepStatus
    var output: String?
    var durationMS: Int?
    var sandbox: Bool
    var truncated: Bool
    var automatic: CursorStepMark? = nil
}

enum CursorStepMark: Equatable {
    case allowed
    case denied
}

enum CursorApprovalKind: Equatable {
    case shell
    case mcp
    case edit
}

struct CursorApproval: Identifiable, Equatable {
    var id: UUID
    var hook: String
    var conversationID: String
    var project: String
    var command: String
    var cwd: String
    var path: String
    var server: String
    var tool: String
    var risky: Bool
    var deadline: Date
    /// Seconds the ring was given when the card appeared. Later setting changes do not resize it.
    var timeout: TimeInterval
    var kind: CursorApprovalKind

    var canHandBack: Bool { kind != .edit }
}

struct CursorEditHunk: Equatable {
    var oldText: String
    var newText: String
    var truncated: Bool
}

struct CursorEdit: Identifiable, Equatable {
    var id: String
    var path: String
    var hunks: [CursorEditHunk]
    var added: Int
    var removed: Int

    var truncated: Bool { hunks.contains { $0.truncated } }
}

struct CursorDiffLine: Equatable {
    var sign: String
    var text: String
}

struct CursorSubagent: Identifiable, Equatable {
    var id: String
    var type: String
    var task: String
    var status: String
    var summary: String?
    var files: [String]
}

struct CursorContextMeter: Equatable {
    var percent: Double?
    var tokens: Int?
    var window: Int?

    var isEmpty: Bool { percent == nil && tokens == nil && window == nil }
}

struct CursorTokenCounts: Equatable {
    var input: Int?
    var output: Int?
    var cacheRead: Int?
    var cacheWrite: Int?

    var isEmpty: Bool { input == nil && output == nil && cacheRead == nil && cacheWrite == nil }

    static let none = CursorTokenCounts(input: nil, output: nil, cacheRead: nil, cacheWrite: nil)
}

struct CursorSession: Identifiable, Equatable {
    var id: String
    var source: CursorSessionOrigin
    var remote: Bool
    var background: Bool
    var mode: String?
    var root: String?
    var project: String
    var model: String?
    var cursorVersion: String?
    var generationID: String?
    var started: Date
    var lastEvent: Date
    var endedAt: Date?
    var state: CursorLiveState
    var prompt: String?
    var steps: [CursorStep]
    var edits: [CursorEdit]
    var thought: String?
    var thoughtDurationMS: Int?
    var reply: String?
    var tokens: CursorTokenCounts
    var subagents: [CursorSubagent]
    var context: CursorContextMeter?
    var finishReason: String?

    var fileCount: Int { edits.count }
    var commandCount: Int { steps.filter { if case .run = $0.label { return true }; return false }.count }
    var failureCount: Int { steps.filter { $0.status == .failed || $0.status == .denied || $0.status == .stopped }.count }

    func elapsed(at now: Date) -> TimeInterval {
        now.timeIntervalSince(started)
    }
}

/// A finish, a failure, or several chats waiting. The page localizes the words.
struct CursorNoticeFacts: Equatable {
        enum Kind: Equatable { case finished, stopped, failed, needsYou }

    var kind: Kind
    var project: String
    var files: Int
    var commands: Int
    var failures: Int
    var duration: TimeInterval
    var waiting: Int
}

struct CursorSessionStore: Equatable {
    var sessions: [CursorSession] = []
    private var stepSerial = 0

    mutating func nextStepID() -> String {
        stepSerial += 1
        return "step-\(stepSerial)"
    }
}

enum CursorNoticePolicy {
    /// Finish and failure notices stay quiet while Cursor is the front app.
    /// A chat that needs the user still speaks.
    static func include(_ notice: CursorNoticeFacts, finishAlerts: Bool, failureAlerts: Bool,
                        minimumSeconds: Int, cursorIsFrontmost: Bool, quietWhenFocused: Bool) -> Bool {
        let quiet = quietWhenFocused && cursorIsFrontmost
        switch notice.kind {
        case .needsYou:
            return true
        case .finished, .stopped:
            guard finishAlerts, !quiet else { return false }
            return notice.duration >= TimeInterval(max(0, minimumSeconds))
        case .failed:
            return failureAlerts && !quiet
        }
    }
}

enum CursorLineDiff {
    /// Insertions and removals from `CollectionDifference`, capped so one file
    /// cannot fill the page. The caller runs this off the main actor.
    static func lines(old: String, new: String, limit: Int = 200) -> (lines: [CursorDiffLine], truncated: Bool) {
        let difference = new.components(separatedBy: "\n").difference(from: old.components(separatedBy: "\n"))
        var rows: [CursorDiffLine] = []
        rows.reserveCapacity(min(limit, difference.count))
        for change in difference {
            if rows.count == limit { return (rows, true) }
            switch change {
            case .insert(_, let line, _):
                rows.append(CursorDiffLine(sign: "+", text: line))
            case .remove(_, let line, _):
                rows.append(CursorDiffLine(sign: "-", text: line))
            }
        }
        return (rows, false)
    }

    static func counts(old: String, new: String) -> (added: Int, removed: Int) {
        var added = 0
        var removed = 0
        for change in new.components(separatedBy: "\n").difference(from: old.components(separatedBy: "\n")) {
            switch change {
            case .insert: added += 1
            case .remove: removed += 1
            }
        }
        return (added, removed)
    }
}
