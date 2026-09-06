// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Activation is useful evidence even before Accessibility can name a window.
/// Keep it in the same timeline as focus, rather than filing a missed window
/// behind every window seen earlier. Access is serialized by the tracker lock.
struct WindowFocusHistory {
    struct Request: Equatable {
        let pid: pid_t
        let id = UUID()
    }

    private enum Use: Equatable {
        case app(pid_t)
        case window(CGWindowID)
    }

    private var recent: [Use] = []
    private(set) var current: Request?
    private(set) var revision = UUID()

    mutating func activate(_ pid: pid_t, recording: Bool = true) -> Request? {
        current = recording ? Request(pid: pid) : nil
        if recording { promote(.app(pid)) }
        return current
    }

    @discardableResult
    mutating func focus(_ window: CGWindowID, for request: Request) -> Bool {
        guard current == request else { return false }
        recent.removeAll { $0 == .app(request.pid) }
        promote(.window(window))
        return true
    }

    mutating func switched(to window: CGWindowID?, pid: pid_t, previous: CGWindowID?) {
        if let current, previous != nil {
            recent.removeAll { $0 == .app(current.pid) }
        }
        // Invalidate an AX read already in flight before the explicit switch.
        current = Request(pid: pid)
        if let previous { promote(.window(previous)) }
        recent.removeAll { $0 == .app(pid) }
        if let window { promote(.window(window)) }
        else { promote(.app(pid)) }
    }

    mutating func reconcile(windows: Set<CGWindowID>, revision capturedRevision: UUID) {
        // A WindowServer query must not erase focus recorded while it ran.
        guard revision == capturedRevision else { return }
        recent.removeAll {
            switch $0 {
            case .window(let id): return !windows.contains(id)
            // The running-app snapshot can predate a launch notification.
            // Only an actual termination removes activation evidence.
            case .app: return false
            }
        }
    }

    mutating func terminated(_ pid: pid_t) {
        recent.removeAll { $0 == .app(pid) }
        if current?.pid == pid { current = nil }
        revision = UUID()
    }

    /// Resolve an unresolved activation to that app's best available entry.
    /// This does not promote its other windows or replace confirmed focus.
    func order(_ entries: [WindowUseOrder.Entry], baseline: [Int]) -> [Int] {
        var result: [Int] = []
        var seen = Set<Int>()
        for use in recent {
            let index = baseline.first { index in
                switch use {
                case .window(let id): return entries[index].windowID == id
                case .app(let pid): return entries[index].pid == pid
                }
            }
            if let index, seen.insert(index).inserted { result.append(index) }
        }
        result += baseline.filter { seen.insert($0).inserted }
        return result
    }

    private mutating func promote(_ use: Use) {
        revision = UUID()
        recent.removeAll { $0 == use }
        recent.insert(use, at: 0)
        if recent.count > WindowUseOrder.limit { recent.removeLast() }
    }
}

/// The rules that turn "what the user used, and when" into the order the
/// switcher shows. Kept free of AppKit so the ordering can be tested on its
/// own: getting this wrong is invisible in a build and obvious in daily use.
enum WindowUseOrder {
    /// How many windows are remembered. Well past any realistic session, and
    /// small enough that the lookups stay trivial.
    static let limit = 256

    /// One entry to place. `windowID` is nil for an app entry with no window,
    /// which can never appear in the window history and is placed by its app.
    struct Entry: Equatable {
        let windowID: CGWindowID?
        let pid: pid_t

        init(windowID: CGWindowID?, pid: pid_t) {
            self.windowID = windowID
            self.pid = pid
        }
    }

    /// Positions for `entries`, most recently used first.
    ///
    /// A window the user actually focused is placed by that history alone, so
    /// the entry right after the current one is always the window used before
    /// it, whichever app owns it. Windows never seen focused cannot be ranked
    /// that way, so they follow, most recently used app first and then in the
    /// window server's front-to-back order — which is where an untouched
    /// window's own recency lives.
    static func order(_ entries: [Entry],
                      windowHistory: [CGWindowID],
                      appHistory: [pid_t],
                      frontToBack: [CGWindowID]) -> [Int] {
        let windowRank = rankMap(windowHistory)
        let appRank = rankMap(appHistory)
        let depthRank = rankMap(frontToBack)

        return entries.indices.sorted { lhs, rhs in
            key(entries[lhs], at: lhs, windowRank, appRank, depthRank)
                < key(entries[rhs], at: rhs, windowRank, appRank, depthRank)
        }
    }

    /// `entries` rearranged by `order`, for callers that just want the list.
    static func ordered(_ entries: [Entry],
                        windowHistory: [CGWindowID],
                        appHistory: [pid_t],
                        frontToBack: [CGWindowID]) -> [Entry] {
        order(entries, windowHistory: windowHistory, appHistory: appHistory, frontToBack: frontToBack)
            .map { entries[$0] }
    }

    private static func key(_ entry: Entry,
                            at index: Int,
                            _ windowRank: [CGWindowID: Int],
                            _ appRank: [pid_t: Int],
                            _ depthRank: [CGWindowID: Int]) -> SortKey {
        if let windowID = entry.windowID, let rank = windowRank[windowID] {
            return SortKey(tier: 0, primary: rank, secondary: 0, original: index)
        }
        let depth = entry.windowID.flatMap { depthRank[$0] } ?? Int.max
        return SortKey(tier: 1,
                       primary: appRank[entry.pid] ?? Int.max,
                       secondary: depth,
                       original: index)
    }

    private struct SortKey: Comparable {
        let tier: Int
        let primary: Int
        let secondary: Int
        let original: Int

        static func < (lhs: SortKey, rhs: SortKey) -> Bool {
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.primary != rhs.primary { return lhs.primary < rhs.primary }
            if lhs.secondary != rhs.secondary { return lhs.secondary < rhs.secondary }
            return lhs.original < rhs.original
        }
    }

    private static func rankMap<T: Hashable>(_ list: [T]) -> [T: Int] {
        var map: [T: Int] = [:]
        map.reserveCapacity(list.count)
        for (index, value) in list.enumerated() where map[value] == nil {
            map[value] = index
        }
        return map
    }

    /// Moves a window to the front of the history. `previous` becomes second,
    /// which is what makes a quick repeat of the shortcut toggle straight back
    /// to where the user came from.
    static func promoting(_ windowID: CGWindowID,
                          previous: CGWindowID? = nil,
                          in history: [CGWindowID],
                          limit: Int = limit) -> [CGWindowID] {
        var result = history
        result.removeAll { $0 == windowID }
        result.insert(windowID, at: 0)
        if let previous, previous != windowID {
            result.removeAll { $0 == previous }
            result.insert(previous, at: 1)
        }
        return capped(result, limit: limit)
    }

    /// The history after the switcher committed to `target`.
    ///
    /// An entry standing for an app with no window of its own still moves the
    /// window the user came from to the front: with nothing to switch to on
    /// the other side, that window is now the most recently used one there is,
    /// and a quick repeat of the shortcut has to find it there.
    static func promoting(target: CGWindowID?,
                          previous: CGWindowID?,
                          in history: [CGWindowID],
                          limit: Int = limit) -> [CGWindowID] {
        guard let target else {
            guard let previous else { return history }
            return promoting(previous, in: history, limit: limit)
        }
        return promoting(target, previous: previous, in: history, limit: limit)
    }

    /// Same move-to-front, for the list of applications.
    static func promoting(_ pid: pid_t, in history: [pid_t], limit: Int = limit) -> [pid_t] {
        var result = history
        result.removeAll { $0 == pid }
        result.insert(pid, at: 0)
        return capped(result, limit: limit)
    }

    /// Drops windows that no longer exist and files any window that was never
    /// focused while the history was being kept.
    ///
    /// Front-to-back order supplies both the very first history — a session
    /// that starts with nothing remembered is still ordered sensibly, instead
    /// of by the arbitrary order the window server hands out — and the place
    /// for windows that appeared without ever taking focus, which are by
    /// definition older than everything already known.
    static func reconciled(_ history: [CGWindowID],
                           existing: Set<CGWindowID>,
                           frontToBack: [CGWindowID],
                           limit: Int = limit) -> [CGWindowID] {
        var result = history.filter { existing.contains($0) }
        var known = Set(result)
        for windowID in frontToBack where existing.contains(windowID) && !known.contains(windowID) {
            result.append(windowID)
            known.insert(windowID)
        }
        return capped(result, limit: limit)
    }

    /// Drops applications that are no longer running, and files the ones never
    /// seen in front by how deep their windows sit — the same reasoning as for
    /// windows, so a session that starts with nothing remembered is still
    /// ordered by something real.
    static func reconciled(_ history: [pid_t],
                           running: Set<pid_t>,
                           frontToBack: [pid_t] = [],
                           limit: Int = limit) -> [pid_t] {
        var result = history.filter { running.contains($0) }
        var known = Set(result)
        for pid in frontToBack where running.contains(pid) && !known.contains(pid) {
            result.append(pid)
            known.insert(pid)
        }
        return capped(result, limit: limit)
    }

    private static func capped<T>(_ list: [T], limit: Int) -> [T] {
        guard list.count > limit else { return list }
        return Array(list.prefix(limit))
    }
}
