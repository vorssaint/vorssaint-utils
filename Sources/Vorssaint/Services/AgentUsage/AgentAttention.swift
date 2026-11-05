// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import Foundation

/// A session that stopped on something only the person can answer, by its
/// log file. Only times, causes and folder names are kept, in memory.
struct AgentAttention: Equatable {
    /// The turn's key, as the store's turns use it.
    let file: String
    let provider: AgentProvider
    var project: String
    var place: AgentSessionPlace
    var cause: AgentAwait
    var since: Date
    var inferred: Bool
    /// Seen while the logs were first read: history, never news. Only a
    /// session record can make it current again.
    var history: Bool
    /// Claude Code's own session record says so, which the logs never
    /// override; it holds until the record changes.
    var recorded = false
}

/// How long each kind of wait goes before a reminder, and how often.
enum AgentAttentionPolicy {
    /// The "Remind after" choices.
    static let delays: [TimeInterval] = [30, 60, 120, 300]
    static let defaultDelay: TimeInterval = 60
    /// A tool call that goes this long without its result, while nothing
    /// else is written, may wait on an approval: allowed calls come back
    /// within half a minute.
    static let inferQuiet: TimeInterval = 90
    static let inferredDelay: TimeInterval = 120
    static let interruptedDelay: TimeInterval = 5 * 60
    /// Repeats after the first notice, each counted from the one before;
    /// then it stops.
    static let repeats: [TimeInterval] = [4 * 60, 10 * 60]
    /// At most one notice this often, across every session.
    static let globalGap: TimeInterval = 45
    /// After the island comes back, as after unlocking, before what came
    /// due meanwhile is told, as one notice.
    static let resumeSettle: TimeInterval = 10
    /// The session's app in front this long means the person saw it.
    static let seenAfter: TimeInterval = 10

    /// The first notice's wait for a cause, or nil when it never notifies.
    static func firstDelay(_ attention: AgentAttention, delay: TimeInterval) -> TimeInterval {
        if attention.cause == .interrupted { return interruptedDelay }
        if attention.inferred { return inferredDelay }
        // A dialog may be one the person opened themselves.
        return attention.cause == .dialog ? 2 * delay : delay
    }
}

/// Decides which waits are worth a notice now. Pure: the clock and what is
/// in front are handed in.
struct AgentAttentionSchedule {
    private struct Sent {
        var count: Int
        var last: Date
    }

    /// Notices sent per wait, keyed by file, cause and start, so a new wait
    /// in the same session starts over.
    private var sent: [String: Sent] = [:]
    /// When each wait's app came to the front, while it stays there.
    private var focusedSince: [String: Date] = [:]
    /// When each wait's app was last in front, which postpones it.
    private var lastFocused: [String: Date] = [:]
    private var seen: Set<String> = []
    private(set) var lastNotice: Date?
    private var holdUntil: Date?

    private static func key(_ attention: AgentAttention) -> String {
        "\(attention.file)|\(attention.cause.rawValue)|\(attention.since.timeIntervalSince1970)"
    }

    /// Nothing is told before `date`; what comes due meanwhile is told then.
    mutating func hold(until date: Date) {
        holdUntil = max(holdUntil ?? date, date)
    }

    /// The person looked at the session: no more reminders for this wait.
    mutating func markSeen(file: String, in attention: [String: AgentAttention]) {
        if let wait = attention[file] { seen.insert(Self.key(wait)) }
    }

    /// The waits to tell now, the longest first; empty when none is due.
    /// `focused` holds the files whose app is in front.
    mutating func due(_ attention: [String: AgentAttention], now: Date, delay: TimeInterval, repeats: Bool,
                      interruptions: Bool, inferred: Bool, focused: Set<String>) -> [AgentAttention] {
        let keys = Set(attention.values.map(Self.key))
        sent = sent.filter { keys.contains($0.key) }
        seen.formIntersection(keys)
        focusedSince = focusedSince.filter { focused.contains($0.key) }
        lastFocused = lastFocused.filter { attention[$0.key] != nil }
        var due: [AgentAttention] = []
        for wait in attention.values {
            let key = Self.key(wait)
            if focused.contains(wait.file) {
                let since = focusedSince[wait.file] ?? now
                focusedSince[wait.file] = since
                lastFocused[wait.file] = now
                if now.timeIntervalSince(since) >= AgentAttentionPolicy.seenAfter { seen.insert(key) }
                continue
            }
            guard !wait.history, !seen.contains(key), !wait.inferred || inferred,
                  wait.cause != .interrupted || interruptions else { continue }
            var at: Date
            if let record = sent[key] {
                // Interruptions and guesses are told once.
                guard repeats, !wait.inferred, wait.cause != .interrupted,
                      record.count - 1 < AgentAttentionPolicy.repeats.count else { continue }
                at = record.last.addingTimeInterval(AgentAttentionPolicy.repeats[record.count - 1])
            } else {
                at = wait.since.addingTimeInterval(AgentAttentionPolicy.firstDelay(wait, delay: delay))
            }
            // Out of the front, it waits a full delay again before a word.
            if let left = lastFocused[wait.file] { at = max(at, left.addingTimeInterval(delay)) }
            if now >= at { due.append(wait) }
        }
        guard !due.isEmpty, now >= holdUntil ?? now else { return [] }
        // Whatever comes due within the gap is told with the next notice.
        if let lastNotice, now.timeIntervalSince(lastNotice) < AgentAttentionPolicy.globalGap, now >= lastNotice {
            return []
        }
        holdUntil = nil
        lastNotice = now
        for wait in due {
            let key = Self.key(wait)
            sent[key] = Sent(count: (sent[key]?.count ?? 0) + 1, last: now)
        }
        return due.sorted { ($0.since, $0.file) < ($1.since, $1.file) }
    }

    /// Whether the wait was told before, so its notice says how long.
    func isReminder(_ attention: AgentAttention) -> Bool {
        (sent[Self.key(attention)]?.count ?? 0) > 1
    }
}

/// What a tap on a wait's notice brings to the front: the app that owns the
/// session's process, or the agent's own app.
struct AgentSessionTarget: Equatable {
    /// The attention's file.
    let file: String
    var bundleID: String?
    var pid: Int32?

    /// The owning app's process: the closest one up the chain that is an
    /// app in the Dock. Main thread.
    func application() -> NSRunningApplication? {
        if let pid {
            for ancestor in AgentProcessTree.ancestors(of: pid) {
                if let app = NSRunningApplication(processIdentifier: ancestor), app.activationPolicy == .regular {
                    return app
                }
            }
        }
        guard let bundleID else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }
}

enum AgentProcessTree {
    /// The process and its parents, nearest first, up to launchd.
    static func ancestors(of pid: Int32) -> [Int32] {
        var chain: [Int32] = []
        var current = pid
        while current > 1, chain.count < 32, !chain.contains(current) {
            chain.append(current)
            guard let parent = parent(of: current) else { break }
            current = parent
        }
        return chain
    }

    static func parent(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }
}

/// What the island tells about one or more waits at once.
struct AgentAttentionNotice: Equatable {
    let provider: AgentProvider
    let project: String
    let cause: AgentAwait
    let inferred: Bool
    /// How long the longest wait has gone.
    let waited: TimeInterval
    let place: AgentSessionPlace
    /// The other waits told with it, by project.
    let others: [String]
    /// Told before, so it says how long instead of what to do.
    let reminder: Bool
    let target: AgentSessionTarget
}
