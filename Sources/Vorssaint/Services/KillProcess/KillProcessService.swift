// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import Foundation

/// One row of the live process list: either a single process, or - when
/// grouping is on - a responsible app with every helper process it owns
/// folded into it (`groupedCount > 1`).
struct KillProcessEntry: Identifiable, Equatable {
    let pid: pid_t
    let ppid: pid_t
    let name: String
    let path: String
    let cpuPercent: Double
    let memoryBytes: Double
    let isRegularApp: Bool
    let bundleURL: URL?
    let groupedCount: Int
    let isProtected: Bool

    var id: pid_t { pid }
}

/// Lists every running process (via `ps`, the same source
/// `ProcessUsageService` uses for the resource breakdown) and kills,
/// force-kills, restarts, or tears down whole process trees. Backs both the
/// Kill Process settings page and its Command Bar rows, which share this
/// service's cache instead of shelling out twice.
final class KillProcessService: ObservableObject {
    static let shared = KillProcessService()

    enum SortBy: String {
        case cpu, memory, name, pid
    }

    private enum DirectKillResult {
        case killed, alreadyGone, needsAdmin, failed
    }

    @Published private(set) var entries: [KillProcessEntry] = []
    @Published var query: String = ""
    @Published private(set) var sortBy: SortBy
    @Published private(set) var sortAscending: Bool
    @Published private(set) var groupRelated: Bool
    @Published private(set) var isRefreshing = false
    /// True once a `ps` snapshot has completed successfully at least once, so
    /// the view can tell "still loading for the first time" apart from
    /// "search matched nothing" - both look like an empty `entries` array
    /// otherwise.
    @Published private(set) var hasLoadedOnce = false

    private let cacheLock = NSLock()
    private var lastRefresh: TimeInterval = 0
    private let cacheFreshSeconds: TimeInterval = 3

    private var restartObserver: NSObjectProtocol?
    private var pendingRestartPID: pid_t?
    private var pendingRestartURL: URL?

    private init() {
        sortBy = SortBy(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.killProcessSortBy) ?? "cpu") ?? .cpu
        sortAscending = UserDefaults.standard.bool(forKey: DefaultsKey.killProcessSortAscending)
        groupRelated = UserDefaults.standard.bool(forKey: DefaultsKey.killProcessGroupRelated)
    }

    var filteredEntries: [KillProcessEntry] {
        let ascending = sortAscending
        let sorted = entries.sorted { lhs, rhs in
            let result: Bool
            switch sortBy {
            case .cpu: result = lhs.cpuPercent > rhs.cpuPercent
            case .memory: result = lhs.memoryBytes > rhs.memoryBytes
            case .name: result = lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            case .pid: result = lhs.pid < rhs.pid
            }
            return ascending ? !result : result
        }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.lowercased().contains(needle) || String($0.pid) == needle
        }
    }

    /// Column-header sorting: clicking the active column flips direction,
    /// clicking a different one switches to it at that column's natural
    /// default direction (highest-first for CPU/memory/PID, A-Z for name).
    func toggleSort(_ value: SortBy) {
        if sortBy == value {
            sortAscending.toggle()
        } else {
            sortBy = value
            sortAscending = false
        }
        UserDefaults.standard.set(sortBy.rawValue, forKey: DefaultsKey.killProcessSortBy)
        UserDefaults.standard.set(sortAscending, forKey: DefaultsKey.killProcessSortAscending)
    }

    func setGroupRelated(_ value: Bool) {
        groupRelated = value
        UserDefaults.standard.set(value, forKey: DefaultsKey.killProcessGroupRelated)
        refresh(force: true)
    }

    /// Refreshes the process list off the main thread and republishes on the
    /// main thread. `force` bypasses the freshness cache, so a kill's
    /// reconciling refresh and an explicit tap of the refresh button always
    /// see the current state. `completion` always fires on the main thread,
    /// even when the cache was already fresh, so a caller that needs the
    /// current snapshot (the Command Bar's lazy load) can sequence off it
    /// instead of guessing at a delay.
    func refresh(force: Bool = false, completion: (() -> Void)? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.refresh(force: force, completion: completion) }
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        let fresh = !force && now - lastRefresh < cacheFreshSeconds
        cacheLock.unlock()
        guard !fresh else {
            completion?()
            return
        }

        isRefreshing = true
        let grouped = groupRelated
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let rows = Self.snapshot(grouped: grouped)
            DispatchQueue.main.async {
                guard let self else {
                    completion?()
                    return
                }
                // A failed or empty `ps` call (transient - a timeout under
                // load, a hiccup) must never wipe a list that was already
                // showing good data; only a genuine snapshot replaces it.
                if let rows {
                    self.entries = rows
                    self.hasLoadedOnce = true
                }
                self.isRefreshing = false
                self.cacheLock.lock()
                self.lastRefresh = ProcessInfo.processInfo.systemUptime
                self.cacheLock.unlock()
                completion?()
            }
        }
    }

    // MARK: - Kill

    func kill(_ entry: KillProcessEntry, force: Bool) {
        guard !entry.isProtected else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let removed = self.killBatch([entry.pid], force: force, adminPromptProcessName: entry.name)
            self.finishKill(removed: removed)
        }
    }

    /// Kills every currently listed process sharing this exact name.
    func killAll(named name: String, force: Bool) {
        let pids = entries.filter { $0.name == name && !$0.isProtected }.map(\.pid)
        guard !pids.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let removed = self.killBatch(pids, force: force, adminPromptProcessName: name)
            self.finishKill(removed: removed)
        }
    }

    /// Kills a process together with every descendant, deepest first, so a
    /// parent never outlives children it might otherwise try to restart.
    func killTree(_ entry: KillProcessEntry, force: Bool) {
        guard !entry.isProtected else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let candidates = [entry.pid] + Self.descendants(of: entry.pid)
            let safePids = candidates.filter { !Self.isProtected(pid: $0) }
            let ordered = safePids.reversed()
            let removed = self.killBatch(Array(ordered), force: force, adminPromptProcessName: entry.name)
            self.finishKill(removed: removed)
        }
    }

    /// Sends the direct-kill signal to every pid, then escalates every pid
    /// that came back EPERM through a single `AdminShell` prompt, so killing
    /// several processes owned by another user asks for the password once.
    private func killBatch(_ pids: [pid_t], force: Bool, adminPromptProcessName: String) -> Set<pid_t> {
        var removed = Set<pid_t>()
        var needsAdmin: [pid_t] = []
        for pid in pids {
            guard !Self.isProtected(pid: pid) else { continue }
            switch Self.attemptDirectKill(pid: pid, force: force) {
            case .killed, .alreadyGone: removed.insert(pid)
            case .needsAdmin: needsAdmin.append(pid)
            case .failed: break
            }
        }
        guard !needsAdmin.isEmpty else { return removed }

        let signalFlag = force ? "-9" : "-15"
        let command = "/bin/kill \(signalFlag) " + needsAdmin.map(String.init).joined(separator: " ")
        let prompt = String(format: FeatureStrings.killProcess(L10n.shared.language).adminPromptFormat,
                            adminPromptProcessName)
        if AdminShell.runSync(command, prompt: prompt) {
            removed.formUnion(needsAdmin)
        }
        return removed
    }

    private static func attemptDirectKill(pid: pid_t, force: Bool) -> DirectKillResult {
        if let running = NSRunningApplication(processIdentifier: pid),
           !running.isTerminated, running.activationPolicy == .regular {
            return (force ? running.forceTerminate() : running.terminate()) ? .killed : .failed
        }
        let signal = force ? SIGKILL : SIGTERM
        if Darwin.kill(pid, signal) == 0 { return .killed }
        switch errno {
        case EPERM: return .needsAdmin
        case ESRCH: return .alreadyGone
        default: return .failed
        }
    }

    /// Removes killed rows immediately so the list feels responsive, then
    /// reconciles with a real `ps` snapshot shortly after - long enough for
    /// the kernel to have reaped the process, short enough nobody notices
    /// the wait.
    private func finishKill(removed: Set<pid_t>) {
        DispatchQueue.main.async {
            if !removed.isEmpty {
                self.entries.removeAll { removed.contains($0.pid) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh(force: true)
        }
    }

    /// BFS over `pgrep -P` to collect every descendant of `pid`. Capped well
    /// above any real process tree, so a pathological environment can't spin
    /// this forever.
    private static func descendants(of pid: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var frontier = [pid]
        while !frontier.isEmpty, result.count < 4096 {
            var next: [pid_t] = []
            for parent in frontier {
                let output = Shell.run("/usr/bin/pgrep", ["-P", String(parent)]).output
                next.append(contentsOf: output.split(separator: "\n").compactMap {
                    pid_t($0.trimmingCharacters(in: .whitespaces))
                })
            }
            result.append(contentsOf: next)
            frontier = next
        }
        return result
    }

    // MARK: - Restart

    func canRestart(_ entry: KillProcessEntry) -> Bool {
        !entry.isProtected && entry.bundleURL != nil
    }

    /// Terminates the app, waits for the real termination notification (not
    /// a fixed delay), then relaunches it - the same sequence
    /// `CommandBarService.restart` uses for its own restart row.
    func restart(_ entry: KillProcessEntry) {
        guard !entry.isProtected, let url = entry.bundleURL else { return }
        cancelPendingRestart()
        pendingRestartPID = entry.pid
        pendingRestartURL = url
        restartObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let terminated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  terminated.processIdentifier == self?.pendingRestartPID else { return }
            self?.completeRestart()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Self.attemptDirectKill(pid: entry.pid, force: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard self?.pendingRestartPID == entry.pid else { return }
            self?.cancelPendingRestart()
        }
    }

    private func completeRestart() {
        guard let url = pendingRestartURL else {
            cancelPendingRestart()
            return
        }
        cancelPendingRestart()
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, _ in
            self?.refresh(force: true)
        }
    }

    private func cancelPendingRestart() {
        if let restartObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(restartObserver)
        }
        restartObserver = nil
        pendingRestartPID = nil
        pendingRestartURL = nil
    }

    // MARK: - Protected Processes

    static func isProtected(pid: pid_t, name: String = "", path: String = "") -> Bool {
        KillProcessSupport.isProtected(pid: pid, name: name, path: path)
    }

    // MARK: - Snapshot

    /// Nil on a failed or clearly-wrong snapshot (a timed-out or non-zero
    /// `ps`, or zero rows parsed - never legitimately true on a running Mac),
    /// so a transient hiccup can be told apart from an actually-empty list.
    private static func snapshot(grouped: Bool) -> [KillProcessEntry]? {
        let result = Shell.run("/bin/ps", ["-eo", "pid,ppid,pcpu,rss,comm"])
        guard result.status == 0 else { return nil }
        let rows = parsePS(result.output)
        guard !rows.isEmpty else { return nil }
        return (grouped ? groupedByApp(rows) : rows).sorted { $0.cpuPercent > $1.cpuPercent }
    }

    /// Lines look like "  437     1  12.5  20480 /System/Library/.../WindowServer".
    private static func parsePS(_ output: String) -> [KillProcessEntry] {
        var rows: [KillProcessEntry] = []
        for line in output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard columns.count == 5,
                  let pid = pid_t(columns[0]), pid > 0,
                  let ppid = pid_t(columns[1]),
                  let cpu = Double(columns[2])
            else { continue }
            let rss = Double(columns[3]) ?? 0
            let commandPath = String(columns[4]).trimmingCharacters(in: .whitespaces)
            let shortName = commandPath.contains("/")
                ? (commandPath as NSString).lastPathComponent : commandPath
            let running = NSRunningApplication(processIdentifier: pid)
            let isProt = isProtected(pid: pid, name: shortName, path: commandPath)
            rows.append(KillProcessEntry(
                pid: pid,
                ppid: ppid,
                name: ResponsibleProcess.displayName(pid: pid, fallback: shortName),
                path: commandPath,
                cpuPercent: cpu,
                memoryBytes: rss * 1024,
                isRegularApp: running?.activationPolicy == .regular,
                bundleURL: running?.bundleURL,
                groupedCount: 1,
                isProtected: isProt))
        }
        return rows
    }

    /// Folds helper processes under the app responsible for them, summing
    /// their CPU/memory - the same grouping `ProcessUsageService` applies to
    /// the resource breakdown, reused here via `ResponsibleProcess`.
    private static func groupedByApp(_ rows: [KillProcessEntry]) -> [KillProcessEntry] {
        var byOwner: [pid_t: [KillProcessEntry]] = [:]
        for row in rows {
            byOwner[ResponsibleProcess.owner(of: row.pid), default: []].append(row)
        }
        return byOwner.compactMap { owner, members in
            guard let primary = members.first(where: { $0.pid == owner }) ?? members.first else { return nil }
            let running = NSRunningApplication(processIdentifier: owner)
            let isProt = isProtected(pid: owner, name: primary.name, path: primary.path)
            return KillProcessEntry(
                pid: owner,
                ppid: primary.ppid,
                name: ResponsibleProcess.displayName(pid: owner, fallback: primary.name),
                path: primary.path,
                cpuPercent: members.reduce(0) { $0 + $1.cpuPercent },
                memoryBytes: members.reduce(0) { $0 + $1.memoryBytes },
                isRegularApp: running?.activationPolicy == .regular,
                bundleURL: running?.bundleURL,
                groupedCount: members.count,
                isProtected: isProt)
        }
    }
}
