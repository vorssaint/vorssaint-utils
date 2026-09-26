// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation

/// Watches Claude Code's own per-process session files
/// (`~/.claude/sessions/<pid>.json`) for a session the CLI itself marked
/// `"waiting"` — genuinely blocked on a reply, not merely a turn that ended
/// with nothing further to ask (that state reads `"idle"` in the same file).
/// Claude only: Codex keeps no equivalent lightweight per-session status file
/// to watch the same way. Which sessions count is decided by `AgentWaitSupport`,
/// kept pure and testable without real files or processes.
final class AgentWaitWatcher: ObservableObject {
    static let shared = AgentWaitWatcher()

    @Published private(set) var waiting: [AgentWaitingSession] = []
    /// A session that has been waiting long enough to be worth a notice
    /// rather than only the quiet badge — see `AgentWaitSupport.waitedLongEnough`.
    let newlyWaiting = PassthroughSubject<AgentWaitingSession, Never>()

    /// The usage reader watches both of these for the same provider (an
    /// env-relocated `CLAUDE_CONFIG_DIR` writes here instead), so a session
    /// file can just as well land in either.
    private static let roots = [".claude/sessions", ".config/claude/sessions"].map {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: $0, directoryHint: .isDirectory)
    }
    private let queue = DispatchQueue(label: "com.vorssaint.utils.agentwait", qos: .utility)
    private var watcher: AgentLogWatcher?
    private var running = false
    /// Bumped on every start/stop so a rescan already in flight when the
    /// watcher is switched off — or off then straight back on — cannot
    /// apply a result computed under the wrong session.
    private var generation = 0
    /// When each currently-waiting pid was first seen waiting, for the
    /// notice's own minimum hold.
    private var waitingSince: [Int32: Date] = [:]

    private init() {}

    func syncWithPreferences() {
        let wanted = NotchAgentSupport.isEnabled()
            && NotchAgentSupport.providers().contains(.claude)
            && UserDefaults.standard.bool(forKey: DefaultsKey.notchAgentsWaitingAlert)
        if wanted { start() } else { stop() }
    }

    private func start() {
        guard !running else { return }
        running = true
        generation &+= 1
        queue.async { [weak self] in self?.rescan() }
        let watcher = self.watcher ?? AgentLogWatcher(queue: queue) { [weak self] _, _ in self?.rescan() }
        self.watcher = watcher
        _ = watcher.start(Self.roots.map(\.path))
    }

    func stop() {
        guard running else { return }
        running = false
        generation &+= 1
        watcher?.stop()
        waitingSince.removeAll()
        if !waiting.isEmpty { waiting = [] }
    }

    /// Runs on `queue`. Reads every session file fresh each time: the
    /// directories hold one small file per Claude process, never enough of
    /// them to make a cursor worth keeping.
    private func rescan() {
        let statuses = Self.roots.flatMap { root -> [AgentWaitSupport.SessionStatus] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            return names.filter { $0.hasSuffix(".json") }.compactMap { name in
                let path = root.appendingPathComponent(name).path
                guard let data = FileManager.default.contents(atPath: path),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
                else { return nil }
                return AgentWaitSupport.SessionStatus(
                    status: json["status"] as? String,
                    pid: (json["pid"] as? NSNumber)?.int32Value,
                    name: json["name"] as? String,
                    cwd: json["cwd"] as? String,
                    modifiedAt: UInt64(modified.timeIntervalSince1970 * 1_000_000))
            }
        }
        let sorted = AgentWaitSupport.waitingSessions(statuses) { KillProcessService.startTime(for: $0) }
        let generation = self.generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.generation == generation, self.waiting != sorted else { return }
            let newlyWaiting = AgentWaitSupport.newlyWaitingSessions(current: sorted, previous: self.waiting)
            self.waiting = sorted
            let stillWaitingIDs = Set(sorted.map(\.id))
            self.waitingSince = self.waitingSince.filter { stillWaitingIDs.contains($0.key) }
            let now = Date()
            for session in newlyWaiting {
                self.waitingSince[session.id] = now
                self.scheduleNoticeCheck(for: session, generation: generation)
            }
        }
    }

    /// Fires once `AgentWaitSupport.minimumNoticeWait` has passed, and only
    /// sends the notice if the session is both still waiting and still the
    /// same one that started this check (a resolved-then-re-waiting session
    /// gets its own fresh timer via `rescan`, not this stale one).
    private func scheduleNoticeCheck(for session: AgentWaitingSession, generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + AgentWaitSupport.minimumNoticeWait) { [weak self] in
            guard let self, self.running, self.generation == generation,
                  let since = self.waitingSince[session.id], self.waiting.contains(session),
                  AgentWaitSupport.waitedLongEnough(since: since, now: Date())
            else { return }
            self.newlyWaiting.send(session)
        }
    }
}
