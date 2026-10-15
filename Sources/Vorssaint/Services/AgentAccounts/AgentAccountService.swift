// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// The person's choices for the AI Accounts section, read by their keys
/// so the service does not depend on where they are registered.
struct AgentAccountPreferences {
    var isEnabled: () -> Bool
    var autoSwaps: (AgentProvider) -> Bool
    /// Percent of a limit at which an automatic swap leaves a login.
    var threshold: () -> Double

    static let enabledKey = "notchAccountsEnabled"
    static let autoSwapClaudeKey = "notchAccountsAutoSwapClaude"
    static let autoSwapCodexKey = "notchAccountsAutoSwapCodex"
    static let thresholdKey = "notchAccountsAutoSwapThreshold"
    static let defaultThreshold = 90.0

    static func stored(in defaults: UserDefaults = .standard) -> AgentAccountPreferences {
        AgentAccountPreferences(
            isEnabled: { defaults.bool(forKey: enabledKey) },
            autoSwaps: { provider in
                switch provider {
                case .claude: return defaults.bool(forKey: autoSwapClaudeKey)
                case .codex: return defaults.bool(forKey: autoSwapCodexKey)
                case .opencode, .copilot: return false
                }
            },
            threshold: {
                let value = defaults.double(forKey: thresholdKey)
                return (50...100).contains(value) ? value : defaultThreshold
            })
    }
}

/// Keeps several logins for Claude Code and Codex while the AI Accounts
/// section is on: reads each one's limits, swaps the live login when the
/// person taps another, and on its own when they asked for that and the
/// live one nears its limit.
///
/// A saved Claude login's token goes to Anthropic to read its limits, and
/// Codex's own tool is started for a Codex login; nothing else leaves the
/// Mac. Everything that reads or writes a login runs on one private queue,
/// one step at a time, so a swap never meets a refresh of the same login
/// half way. The queue never waits for the main thread.
final class AgentAccountService: ObservableObject {
    static let shared = AgentAccountService()

    /// The providers whose logins can be kept, in the order the page lists them.
    static let providers: [AgentProvider] = [.claude, .codex]

    @Published private(set) var accounts: [AgentAccountState] = []
    @Published private(set) var liveLogin: [AgentProvider: LiveLoginStatus] = [:]
    @Published private(set) var runningSessions: [AgentProvider: Int] = [:]
    /// The login a swap the person asked for is moving to.
    @Published private(set) var switching: AgentAccount.ID?
    @Published private(set) var lastSwap: SwapRecord?
    @Published private(set) var lastError: AgentAccountError?
    /// A login being added with the provider's own sign-in; one at a time.
    @Published private(set) var adding: AddLoginState?
    let events = PassthroughSubject<AgentAccountEvent, Never>()

    private static let tick: TimeInterval = 60
    /// "Every login is near its limit" is said once an hour at most.
    private static let exhaustedInterval: TimeInterval = 3_600
    /// After the live login changes, readings from outside this service
    /// still describe the login before it for a moment.
    private static let settle: TimeInterval = 60

    private let queue = DispatchQueue(label: "com.vorssaint.agent-accounts", qos: .utility, autoreleaseFrequency: .workItem)
    private let preferences: AgentAccountPreferences

    // Main thread.
    private var running = false
    /// Reading waits while the island is away, unless an automatic swap is
    /// on; what was read stays.
    private var paused = false
    private var session = 0
    private var timer: Timer?
    private var loginFlow: AgentLoginFlow?
    /// Counts the sign-ins begun, so one that was cancelled says nothing later.
    private var addAttempt = 0

    // Confined to `queue`.
    private struct Engine {
        let store: AgentAccountStore
        let adapters: [AgentProvider: AgentLoginAdapter]
        let switcher: AgentAccountSwitcher
    }
    private struct Reading {
        var limits: AgentLimits?
        var fetchedAt: Date?
        var error: AgentUsageFailure?
    }
    private var readerSession = -1
    private var engine: Engine?
    /// Kept across a stop: turning the section off and on must not spend a
    /// login's requests twice.
    private var polling = AgentAccountPolling()
    private var readings: [AgentAccount.ID: Reading] = [:]
    private var active: [AgentProvider: AgentAccount.ID] = [:]
    private var activeSince: [AgentProvider: Date] = [:]
    private var statuses: [AgentProvider: LiveLoginStatus] = [:]
    private var sessions: [AgentProvider: Int] = [:]
    private var lastAutoSwap: [AgentProvider: Date] = [:]
    private var lastExhausted: [AgentProvider: Date] = [:]
    /// The AI section's own limits, handed over with each tick.
    private var logLimits: [AgentProvider: AgentLimits] = [:]
    private var fetching = false
    private var appeared = false
    private var codexApps: [URL] = []
    /// A Terminal window's PATH, asked of the login shell once and only when
    /// a provider's tool is in none of the usual places: that runs the
    /// shell's startup files.
    private var shellPath: String?
    private var shellPathAsked = false

    init(preferences: AgentAccountPreferences = .stored()) {
        self.preferences = preferences
    }

    // MARK: Lifecycle (main thread)

    func syncWithPreferences() {
        guard preferences.isEnabled() else { stop(); return }
        if !running {
            running = true
            session += 1
            start(session: session)
        } else if paused {
            paused = false
            if timer == nil { startTimer() }
            refreshUsage(force: false)
        }
    }

    /// Stops asking while the island is away, as with the display asleep or
    /// the Mac locked, and keeps what was read; goes on asking when an
    /// automatic swap is on. Called again when a choice changes meanwhile.
    func pause() {
        guard running else { return }
        paused = true
        if AgentAutoSwap.runsWhileAway(Self.providers, autoSwaps: preferences.autoSwaps) {
            guard timer == nil else { return }
            startTimer()
            refreshUsage(force: false)
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    func stop() {
        guard running else { return }
        running = false
        paused = false
        session += 1
        timer?.invalidate()
        timer = nil
        accounts = []
        liveLogin = [:]
        runningSessions = [:]
        switching = nil
        lastSwap = nil
        lastError = nil
        cancelAdd()
        queue.async { [self] in
            readerSession = -1
            engine = nil
            readings.removeAll()
            active.removeAll()
            activeSince.removeAll()
            statuses.removeAll()
            sessions.removeAll()
            logLimits.removeAll()
            appeared = false
        }
    }

    /// Opening the page reads again what has grown old.
    func pageDidAppear() {
        refreshUsage(force: true)
    }

    /// Looks at the live logins again and asks for the limits that are due;
    /// `force` asks sooner, though never twice within two minutes.
    func refreshUsage(force: Bool) {
        guard running else { return }
        // Only Claude's reading there is known to be the live login's: a
        // Codex session keeps writing the limits of the login it started with.
        let logged = AgentUsageService.shared.snapshot.limits.filter { $0.key == .claude }
        let apps = Self.codexApps()
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            logLimits = logged
            codexApps = apps
            if force { appeared = true }
            refresh(now: Date())
        }
    }

    // MARK: Actions (main thread)

    /// Saves the login the provider's tool uses now, or updates its copy.
    func saveLiveLogin(_ provider: AgentProvider) {
        guard running else { return }
        lastError = nil
        queue.async { [self] in
            guard readerSession >= 0, let engine else { return }
            do {
                guard let live = try engine.adapters[provider]?.readLive() else {
                    report(.saveFailed(provider, "nobody is signed in"))
                    return
                }
                let account = try engine.store.capture(live)
                polling.forget(account.id)
                readings[account.id] = nil
            } catch {
                report(.saveFailed(provider, "\(error)"))
            }
            refresh(now: Date())
        }
    }

    func switchTo(_ id: AgentAccount.ID) {
        guard running, switching == nil else { return }
        switching = id
        lastError = nil
        let session = self.session
        queue.async { [self] in
            if readerSession >= 0 { perform(id, automatic: false, now: Date()) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.session == session else { return }
                self.switching = nil
            }
        }
    }

    /// Forgets a saved login and its copy; the live login stays as it is.
    func remove(_ id: AgentAccount.ID) {
        guard running else { return }
        lastError = nil
        queue.async { [self] in
            guard readerSession >= 0, let engine else { return }
            do {
                try engine.store.remove(id)
                polling.forget(id)
                readings[id] = nil
            } catch {
                report(.removeFailed("\(error)"))
            }
            readLive(now: Date())
            publish()
        }
    }

    func rename(_ id: AgentAccount.ID, label: String) {
        guard running else { return }
        queue.async { [self] in
            guard readerSession >= 0, let engine else { return }
            try? engine.store.rename(id, label: label)
            publish()
        }
    }

    // MARK: Adding a login (main thread)

    /// Starts the provider's own sign-in for an account to add. It runs in a
    /// private folder of its own, so the login in use stays as it is.
    func beginAdd(_ provider: AgentProvider) {
        guard running, adding?.isUnderWay != true else { return }
        addAttempt += 1
        let attempt = addAttempt
        adding = .starting(provider)
        queue.async { [self] in
            let flow = readerSession >= 0 ? makeLoginFlow(provider) : nil
            DispatchQueue.main.async { [self] in
                guard attempt == addAttempt else { return }
                guard let flow else {
                    adding = .toolMissing(provider)
                    return
                }
                loginFlow = flow
                Thread.detachNewThread { [self] in run(flow, attempt: attempt) }
            }
        }
    }

    /// The code the browser showed after the Claude sign-in.
    func submitCode(_ code: String) {
        guard case .claude = adding, let loginFlow,
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        adding = .finishing(.claude)
        loginFlow.submit(code)
    }

    /// Ends the sign-in under way, or puts away how the last one ended.
    func cancelAdd() {
        addAttempt += 1
        loginFlow?.cancel()
        loginFlow = nil
        adding = nil
    }

    /// Runs on a thread of its own for as long as the person takes to sign in.
    private func run(_ flow: AgentLoginFlow, attempt: Int) {
        let provider = flow.provider
        let outcome = flow.run(progress: { [weak self] step in
            DispatchQueue.main.async {
                guard let self, attempt == self.addAttempt else { return }
                switch step {
                case .claude(let url): self.adding = .claude(url: url)
                case .codex(let url, let code): self.adding = .codex(url: url, code: code)
                case .finishing: self.adding = .finishing(provider)
                }
            }
        }, capture: { [self] live in
            try queue.sync {
                guard readerSession >= 0, let engine else { throw AgentLoginError.unreadable("the section was turned off") }
                let account = try engine.store.capture(live)
                polling.forget(account.id)
                readings[account.id] = nil
            }
        })
        DispatchQueue.main.async { [self] in
            // A login kept just as the person cancelled is still a saved one.
            if case .added = outcome { refreshUsage(force: true) }
            guard attempt == addAttempt else { return }
            loginFlow = nil
            switch outcome {
            case .added, .cancelled: adding = nil
            case .failed(let message): adding = .failed(provider, message: message)
            }
        }
    }

    // MARK: Reading (queue)

    /// Nil when the provider's tool is not on this Mac.
    private func makeLoginFlow(_ provider: AgentProvider) -> AgentLoginFlow? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let container = PrivateFileStore.containerURL, let executable = executable(provider, home: home) else { return nil }
        let keychain = ClaudeKeychain()
        return AgentLoginFlow(provider: provider, executable: executable,
                              environment: AgentCodexServer.environment(for: executable, searchPath: shellPath),
                              container: container.appending(path: "AgentAccounts", directoryHint: .isDirectory),
                              secrets: keychain, services: keychain.claudeServices)
    }

    /// The provider's command-line tool, looked for along the login shell's
    /// PATH as well when it is in none of the usual places.
    private func executable(_ provider: AgentProvider, home: URL) -> URL? {
        let apps = provider == .codex ? codexApps : []
        let tool = provider == .codex ? "codex" : "claude"
        var executable = AgentCodexServer.executable(apps: apps, home: home, searchPath: shellPath, tool: tool)
        if executable == nil, !shellPathAsked {
            shellPathAsked = true
            shellPath = HomebrewEnvironment.loginShellExports(shellPath: HomebrewCommandBuilder.currentShellPath)["PATH"]
            executable = AgentCodexServer.executable(apps: apps, home: home, searchPath: shellPath, tool: tool)
        }
        return executable
    }

    private func startTimer() {
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in self?.refreshUsage(force: false) }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func start(session: Int) {
        startTimer()
        queue.async { [self] in
            readerSession = session
            engine = makeEngine()
        }
        refreshUsage(force: false)
    }

    /// Nil outside a real bundle, which has no folder to keep logins in.
    private func makeEngine() -> Engine? {
        guard let container = PrivateFileStore.containerURL else { return nil }
        let directory = container.appending(path: "AgentAccounts", directoryHint: .isDirectory)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let keychain = ClaudeKeychain()
        let codexCopies = CodexCredentialCopies(directory: directory.appending(path: "codex", directoryHint: .isDirectory))
        let store = AgentAccountStore(directory: directory, copies: [.claude: ClaudeCredentialCopies(secrets: keychain),
                                                                     .codex: codexCopies])
        let adapters: [AgentProvider: AgentLoginAdapter] = [
            .claude: ClaudeLoginAdapter(home: home, secrets: keychain),
            .codex: CodexLoginAdapter(home: home, copies: codexCopies,
                                      limits: { [weak self] in self?.codexLimits($0, home: home) ?? .failure(.missing) })]
        return Engine(store: store, adapters: adapters, switcher: AgentAccountSwitcher(store: store, adapters: adapters))
    }

    private static func codexApps() -> [URL] {
        AgentCodexServer.appIdentifiers.flatMap { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) }
    }

    /// Runs on `queue`, called by the Codex adapter.
    private func codexLimits(_ codexHome: URL?, home: URL) -> Result<AgentLimits, AgentCodexServer.Failure> {
        guard let executable = executable(.codex, home: home) else { return .failure(.missing) }
        return CodexLogin.limits(executable, codexHome: codexHome, searchPath: shellPath)
    }

    private func refresh(now: Date) {
        guard engine != nil else { return }
        readLive(now: now)
        publish()
        Self.providers.forEach { evaluate($0, now: now) }
        fetchNext()
    }

    /// Whose login each tool uses now, and how many of its sessions run.
    private func readLive(now: Date) {
        guard let engine else { return }
        for provider in Self.providers {
            guard let adapter = engine.adapters[provider] else { continue }
            var status = LiveLoginStatus.signedOut
            var id: AgentAccount.ID?
            do {
                if let live = try adapter.readLive() {
                    if let saved = engine.store.account(live.id) {
                        status = .saved(live.id)
                        id = live.id
                        // A login marked dead that the person signed in to
                        // again has new tokens: that is the re-capture.
                        if saved.needsLogin, (try? engine.store.credential(for: live.id)) != live.credential,
                           (try? engine.store.capture(live, now: now)) != nil {
                            polling.forget(live.id)
                            readings[live.id]?.error = nil
                        }
                    } else {
                        status = .unsaved(email: live.email)
                    }
                }
            } catch AgentLoginError.unsupported {
                status = .unsupported
            } catch {
                // Unreadable for a moment is not signed out.
                status = statuses[provider] ?? .signedOut
                id = active[provider]
            }
            if active[provider] != id || activeSince[provider] == nil { activeSince[provider] = now }
            active[provider] = id
            statuses[provider] = status
            sessions[provider] = adapter.runningSessions()
        }
    }

    private func states() -> [AgentAccountState] {
        guard let engine else { return [] }
        return engine.store.accounts
            .sorted { lhs, rhs in
                let order = (Self.providers.firstIndex(of: lhs.provider) ?? 0, Self.providers.firstIndex(of: rhs.provider) ?? 0)
                return order.0 != order.1 ? order.0 < order.1 : lhs.added < rhs.added
            }
            .map { account in
                let reading = readings[account.id]
                return AgentAccountState(account: account, limits: reading?.limits, fetchedAt: reading?.fetchedAt,
                                         usageError: reading?.error, isActive: active[account.provider] == account.id)
            }
    }

    /// Hands what is known to the main thread.
    private func publish() {
        let session = readerSession
        guard session >= 0 else { return }
        let states = states(), statuses = statuses, sessions = sessions
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session else { return }
            if self.accounts != states { self.accounts = states }
            if self.liveLogin != statuses { self.liveLogin = statuses }
            if self.runningSessions != sessions { self.runningSessions = sessions }
        }
    }

    private func report(_ error: AgentAccountError) {
        let session = readerSession
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session else { return }
            self.lastError = error
        }
    }

    // MARK: Limits (queue)

    /// The active login's limits as the automatic swap sees them: the newer
    /// of this service's reading and the AI section's.
    private func activeLimits(_ provider: AgentProvider) -> AgentLimits? {
        var logged = logLimits[provider]
        if let reading = logged, reading.observedAt < (activeSince[provider] ?? .distantPast).addingTimeInterval(Self.settle) {
            logged = nil
        }
        return AgentAutoSwap.current(active[provider].flatMap { readings[$0]?.limits }, logged)
    }

    private func pace(_ account: AgentAccount) -> AgentAccountPolling.Pace {
        let isActive = active[account.provider] == account.id
        let near = preferences.autoSwaps(account.provider)
            && AgentAccountPolling.isNear(activeLimits(account.provider), threshold: preferences.threshold())
        if isActive { return near ? .urgent : .active }
        return near ? .candidate : .idle
    }

    /// Asks for one login's limits, then comes back for the next: a swap the
    /// person taps waits behind one request at most.
    private func fetchNext() {
        guard !fetching else { return }
        fetching = true
        fetchStep()
    }

    private func fetchStep() {
        let now = Date()
        // The login in use first: its reading is the one that matters.
        let due = states().sorted { $0.isActive && !$1.isActive }.first {
            !$0.account.needsLogin && polling.isDue($0.id, pace: pace($0.account), appeared: appeared, now: now)
        }
        guard readerSession >= 0, engine != nil, let due else {
            fetching = false
            appeared = false
            return
        }
        fetch(due.account, now: now)
        queue.async { [self] in fetchStep() }
    }

    private func fetch(_ account: AgentAccount, now: Date) {
        guard let engine, let adapter = engine.adapters[account.provider] else { return }
        let isActive = active[account.provider] == account.id
        guard let credential = try? engine.store.credential(for: account.id) else {
            failed(account.id, .unavailable("the saved login has no copy"), now: now)
            return
        }
        let answer = adapter.fetchUsage(account, credential: credential, isActive: isActive)
        var result = answer.limits
        if let rotated = answer.rotated {
            do { try engine.store.storeCredential(rotated, for: account.id) } catch {
                result = .failure(.unavailable("new tokens could not be stored: \(error)"))
            }
        }
        let finished = Date()
        switch result {
        case .success(let limits):
            readings[account.id] = Reading(limits: limits, fetchedAt: finished, error: nil)
            polling.succeeded(account.id, now: finished)
            // The same reading Codex's own card would ask for.
            if isActive, account.provider == .codex {
                DispatchQueue.main.async { AgentUsageService.shared.noteLimits(limits) }
            }
        case .failure(let failure):
            failed(account.id, failure, now: finished)
            if failure == .needsLogin { try? engine.store.setNeedsLogin(account.id, true) }
        }
        publish()
        evaluate(account.provider, now: finished)
    }

    /// The last good reading stays on the page beside the failure.
    private func failed(_ id: AgentAccount.ID, _ failure: AgentUsageFailure, now: Date) {
        readings[id, default: Reading()].error = failure
        polling.failed(id, failure, now: now)
    }

    // MARK: Swaps (queue)

    /// Applies the automatic swap's decision for one provider. A swap the
    /// person asked for runs on this same queue, so the two never overlap.
    private func evaluate(_ provider: AgentProvider, now: Date) {
        guard preferences.autoSwaps(provider) else { return }
        let states = states().filter { $0.account.provider == provider }
        let input = AutoSwapInput(active: states.first(where: \.isActive), candidates: states.filter { !$0.isActive },
                                  threshold: preferences.threshold(), now: now, lastAutoSwap: lastAutoSwap[provider],
                                  logLimits: activeLimits(provider))
        switch AgentAutoSwap.decide(input) {
        case .stay:
            break
        case .swap(let id, _):
            perform(id, automatic: true, now: now)
        case .exhausted(let nextReset):
            if let last = lastExhausted[provider], now.timeIntervalSince(last) < Self.exhaustedInterval { return }
            lastExhausted[provider] = now
            send(.exhausted(provider: provider, nextReset: nextReset))
        }
    }

    private func perform(_ id: AgentAccount.ID, automatic: Bool, now: Date) {
        guard let engine, let target = engine.store.account(id) else {
            report(.switchFailed(nil, .targetMissing))
            return
        }
        let provider = target.provider
        var from = states().first { $0.isActive && $0.account.provider == provider }
        // The reading that made the swap happen, when it was the newer one.
        if automatic { from?.limits = activeLimits(provider) }
        let result = engine.switcher.switch(to: id)
        readLive(now: now)
        switch result {
        case .success(.switched):
            if automatic { lastAutoSwap[provider] = now }
            let record = SwapRecord(provider: provider, from: from?.id, to: id, date: now, automatic: automatic)
            let session = readerSession
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running, self.session == session else { return }
                self.lastSwap = record
            }
            if let to = states().first(where: { $0.id == id }) {
                send(.swapped(provider: provider, from: from, to: to, automatic: automatic))
            }
            // Its limits are the ones that count from here on.
            appeared = true
            fetchNext()
        case .success(.alreadyActive):
            break
        case .failure(let failure):
            report(.switchFailed(provider, failure))
        }
        publish()
    }

    private func send(_ event: AgentAccountEvent) {
        let session = readerSession
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session else { return }
            self.events.send(event)
        }
    }
}
