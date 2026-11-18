// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Asks the agents known only by their plan limits (Command Code and
/// Antigravity) how much of their plan is left, and hands each answer to
/// `AgentUsageService`, which keeps it with the others, warns on it and shows
/// it. Nothing runs while the section or the agent is off.
///
/// - Command Code: one request set at most every five minutes.
/// - Antigravity: runs `agy`, which costs more than a request, so at most
///   every fifteen minutes and only while its page shows or on a deliberate
///   check. After any failure it waits for such a check: a keychain question
///   the person declined is not asked again by itself.
///
/// Main thread, except the work, which runs on its own queue.
final class AgentAccountLimitsService {
    static let shared = AgentAccountLimitsService()

    private static let tick: TimeInterval = 60
    private static let backgroundGap: TimeInterval = 10 * 60

    private let queue = DispatchQueue(label: "vorssaint.agent.account-limits", qos: .utility)
    private var timer: Timer?
    private var visible = false
    private var paused = false
    private var asked: [AgentProvider: Date] = [:]
    private var running: Set<AgentProvider> = []
    /// Providers whose last check failed: only a deliberate check asks again.
    private var failed: Set<AgentProvider> = []
    private var session = 0

    private init() {}

    private static let covered: [AgentProvider] = [.commandcode, .antigravity]

    /// The preferences changed, or the island came back.
    func synchronize() {
        paused = false
        guard !wanted.isEmpty else { stopTimer(); return }
        if timer == nil {
            let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in self?.check() }
            timer.tolerance = 5
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        check()
    }

    func pause() {
        paused = true
        visible = false
        session += 1
        running = []
        stopTimer()
    }

    /// A Settings preview shows what is known without asking.
    func pageDidAppear(preview: Bool = false) {
        guard !preview else { return }
        visible = true
        check(forced: true)
    }

    func pageDidDisappear() {
        visible = false
    }

    private var wanted: [AgentProvider] {
        guard NotchAgentSupport.isEnabled() else { return [] }
        let on = NotchAgentSupport.providers()
        return Self.covered.filter(on.contains)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// A deliberate check ignores the failure wait but never the gap.
    private func check(forced: Bool = false, now: Date = Date()) {
        guard !paused, NotchAgentSupport.limitsInUse(pageShown: visible) else { return }
        for provider in wanted where due(provider, forced: forced, now: now) {
            ask(provider, now: now)
        }
    }

    private func due(_ provider: AgentProvider, forced: Bool, now: Date) -> Bool {
        guard !running.contains(provider) else { return false }
        if !forced, failed.contains(provider) { return false }
        switch provider {
        case .commandcode:
            // Away from the page, only as often as the notices need.
            let gap = visible ? AgentCommandCodeAccount.minimumGap : max(Self.backgroundGap, AgentCommandCodeAccount.minimumGap)
            return now.timeIntervalSince(asked[provider] ?? .distantPast) >= gap
        case .antigravity:
            guard visible || forced else { return false }
            return now.timeIntervalSince(asked[provider] ?? .distantPast) >= AgentAntigravityAccount.minimumGap
        default:
            return false
        }
    }

    private func ask(_ provider: AgentProvider, now: Date) {
        asked[provider] = now
        running.insert(provider)
        let session = self.session
        queue.async { [weak self] in
            let reading: AgentLimits?
            switch provider {
            case .commandcode: reading = Self.commandCode(now: now)
            case .antigravity: reading = Self.antigravity(now: now)
            default: reading = nil
            }
            DispatchQueue.main.async {
                guard let self, self.session == session else { return }
                self.running.remove(provider)
                if let reading {
                    self.failed.remove(provider)
                    AgentUsageService.shared.noteLimits(reading)
                } else {
                    self.failed.insert(provider)
                }
            }
        }
    }

    // MARK: Work (off the main thread)

    private static func commandCode(now: Date) -> AgentLimits? {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".commandcode")
        let auth = try? Data(contentsOf: folder.appending(path: "auth.json"))
        let installed = FileManager.default.fileExists(atPath: folder.appending(path: "config.json").path)
        guard case .success(let key) = AgentCommandCodeAccount.apiKey(authFile: auth, installed: installed),
              case .success(let summary) = AgentCommandCodeAccount.check(key: key, now: now, fetch: fetch) else { return nil }
        return summary.limits
    }

    private static func antigravity(now: Date) -> AgentLimits? {
        guard AgentAntigravityAccount.executable() != nil else { return nil }
        guard case .success(let limits) = AgentAntigravityAccount.check(
            keychain: AgentAntigravityAccount.readKeychain(), now: now, run: { AgentAntigravityAccount.runProgram($0) })
        else { return nil }
        return limits
    }

    /// One request, answered or not. The key goes only where `request` sent it.
    private static func fetch(_ request: URLRequest) -> AgentCommandCodeAccount.Reply? {
        let done = DispatchSemaphore(value: 0)
        var reply: AgentCommandCodeAccount.Reply?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse { reply = .init(status: http.statusCode, body: data ?? Data()) }
            done.signal()
        }
        task.resume()
        guard done.wait(timeout: .now() + AgentCommandCodeAccount.timeout + 5) == .success else {
            task.cancel()
            return nil
        }
        return reply
    }
}
