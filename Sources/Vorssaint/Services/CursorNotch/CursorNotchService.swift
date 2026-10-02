// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Darwin
import Foundation
import os

/// Which Cursor sessions the island lists. Terminal sessions stay hidden
/// until the person asks for them.
enum CursorNotchSource: String {
    case app
    case appAndTerminal
}

/// The closed-island reading beside the Cursor mark.
enum CursorNotchReadout: String {
    case state, elapsed, project
}

/// What an unanswered approval does. Handing back applies to shell and MCP
/// only; edit approvals stay allow or deny.
enum CursorNotchApprovalFallback: String {
    case deny
    case handBack
}

enum CursorNotchMergeMethod: String {
    case squash, merge, rebase
}

/// The island hears that chats changed, or that a finish needs a notice.
enum CursorNotchSignal: Equatable {
    case sessionsChanged
    case notice(CursorNoticeFacts)
}

/// The Cursor page's service. It owns the hook socket, the sessions the page
/// draws, and the approvals and replies the page answers.
final class CursorNotchService: ObservableObject {
    static let shared = CursorNotchService()

    let events = PassthroughSubject<CursorNotchSignal, Never>()
    /// The ninth approval could not be held, so it was answered immediately.
    let approvalOverflow = PassthroughSubject<Void, Never>()
    /// A silent rewrite changed the hooks file after the first confirmed install.
    let hooksUpdated = PassthroughSubject<Void, Never>()
    /// The newest hook that was not a connection test.
    @Published private(set) var lastEvent: Date?
    @Published private(set) var sessions: [CursorSession] = []
    @Published private(set) var selectedID: String?
    /// True while the island is torn down. The socket keeps answering.
    @Published private(set) var paused = false
    @Published private(set) var approvals: [CursorApproval] = []
    @Published var queued: [String: String] = [:]
    @Published var composerFocused = false
    /// The unsent composer text. Send now pastes this before a queued follow-up.
    @Published var composerDraft = ""
    @Published private(set) var replyDeadline: Date?
    @Published private(set) var git = CursorGitSnapshot()
    @Published var pageVisible = false
    @Published private(set) var recentRepos: [String] = []

    @Published private(set) var replyConversationID: String?

    var keepsSurface: Bool { !approvals.isEmpty || replyConversationID != nil }

    private let server = CursorHookServer()
    private let queueLock = OSAllocatedUnfairLock(initialState: [String: String]())
    private var replyHoldID: UUID?
    private var islandCanShow: () -> Bool = { false }
    private var islandBusy: () -> Bool = { false }
    private var islandPresent: () -> Void = {}
    private var timeouts: [UUID: DispatchWorkItem] = [:]
    private var gitTimer: DispatchSourceTimer?
    private var islandPaused = false
    private var store = CursorSessionStore()
    private var tick: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults)
            && AppFeature.notchCursor.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchCursorEnabled)
    }

    var visibleSessions: [CursorSession] {
        let includeTerminal = UserDefaults.standard.string(forKey: DefaultsKey.notchCursorSources)
            == CursorNotchSource.appAndTerminal.rawValue
        return sessions.filter { includeTerminal || $0.source == .app }
    }

    var focusedSession: CursorSession? {
        let visible = visibleSessions
        if let selectedID, let match = visible.first(where: { $0.id == selectedID }) { return match }
        return visible.max { $0.lastEvent < $1.lastEvent }
    }

    func select(_ id: String) {
        guard visibleSessions.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    static func readout(in defaults: UserDefaults = .standard) -> CursorNotchReadout {
        CursorNotchReadout(rawValue: defaults.string(forKey: DefaultsKey.notchCursorReadout) ?? "") ?? .state
    }

    func syncWithPreferences() {
        paused = false
        guard Self.isEnabled() else {
            stop()
            return
        }
        startWatching()
        CursorHookInstall.refreshInstalledCopyIfPresent()
        guard let container = PrivateFileStore.containerURL,
              PrivateFileStore.createDirectory(at: container) else { return }
        let path = CursorHookProtocol.socketPath(container: container)
        writeContextNote(container: container)
        recentRepos = UserDefaults.standard.stringArray(forKey: DefaultsKey.notchCursorRecentRepos) ?? []
        islandPaused = false
        _ = server.start(CursorHookServerConfiguration(
            socketPath: path,
            overflow: { CursorNotchService.shared.fallback($0, overflow: true) },
            stopped: { CursorNotchService.shared.fallback($0, overflow: false) },
            decide: { CursorNotchService.shared.decide($0) },
            onHold: { CursorNotchService.shared.hold($0, $1) },
            onOverflow: { CursorNotchService.shared.approvalOverflow.send() },
            onMessage: { CursorNotchService.shared.note($0) }
        ))
        syncTick()
    }

    /// Background work stops when the feature is off. Held hooks are answered first.
    func stop() {
        server.stop()
        stopWatching()
        stopTick()
        stopGitTimer()
        timeouts.values.forEach { $0.cancel() }
        timeouts.removeAll()
        store = CursorSessionStore()
        sessions = []
        selectedID = nil
        approvals = []
        replyConversationID = nil
        replyHoldID = nil
        replyDeadline = nil
        paused = false
        islandPaused = false
    }

    /// Hides motion only. The socket keeps answering while the island is hidden.
    func pause() {
        paused = true
        islandPaused = true
    }

    func noteHooksUpdated() {
        hooksUpdated.send()
    }

    func stripReading(language: AppLanguage) -> String {
        let title = FeatureStrings.notchCursor(language).title
        guard let session = focusedSession else { return title }
        switch Self.readout() {
        case .elapsed:
            return "00:00:00"
        case .project:
            return session.project
        case .state:
            return FeatureStrings.notchCursorView(language).stateName(session.state)
        }
    }

    func queue(_ text: String, for conversation: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        queueLock.withLock { state in
            if trimmed.isEmpty { state[conversation] = nil } else { state[conversation] = String(trimmed.prefix(4000)) }
        }
        queued = queueLock.withLock { $0 }
    }

    func allow(_ approval: CursorApproval) { finish(approval, reply: CursorHookReplies.allow()) }
    func deny(_ approval: CursorApproval) { finish(approval, reply: CursorHookReplies.deny()) }
    func handBack(_ approval: CursorApproval) {
        guard approval.canHandBack else { return }
        finish(approval, reply: CursorHookReplies.ask())
    }

    func allowAlways(_ approval: CursorApproval) {
        let command = approval.kind == .mcp
            ? [approval.server, approval.tool].filter { !$0.isEmpty }.joined(separator: " ")
            : approval.command
        var rules = CursorApprovalRules.lines(UserDefaults.standard.string(forKey: DefaultsKey.notchCursorAllowRules) ?? "")
        if !command.isEmpty, !rules.contains(command) { rules.append(command) }
        UserDefaults.standard.set(CursorApprovalRules.stored(rules), forKey: DefaultsKey.notchCursorAllowRules)
        allow(approval)
    }

    func bindIsland(canShow: @escaping () -> Bool, busy: @escaping () -> Bool, present: @escaping () -> Void) {
        islandCanShow = canShow
        islandBusy = busy
        islandPresent = present
    }

    func refreshContextNote() {
        guard let container = PrivateFileStore.containerURL else { return }
        writeContextNote(container: container)
    }

    func sendReply(_ text: String) {
        guard let conversation = replyConversationID else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { skipReply(); return }
        completeReply(CursorHookReplies.followUp(trimmed), conversation: conversation)
    }

    func skipReply() {
        guard let conversation = replyConversationID else { return }
        completeReply(.empty, conversation: conversation)
    }

    func refreshGit() {
        guard pageVisible, UserDefaults.standard.bool(forKey: DefaultsKey.notchCursorPullRequests),
              let session = focusedSession, !session.remote, let root = session.root else {
            git = CursorGitSnapshot()
            stopGitTimer()
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let snapshot = CursorGitService.refresh(root: root, remote: false)
            DispatchQueue.main.async {
                CursorNotchService.shared.git = snapshot
                CursorNotchService.shared.syncGitTimer()
            }
        }
    }

    func createPullRequest(title: String) {
        guard let session = focusedSession, !session.remote, let root = session.root, git.canCreate, !git.dirty else { return }
        let draft = UserDefaults.standard.bool(forKey: DefaultsKey.notchCursorPRDraft)
        let remote = git.remote
        let base = git.defaultBranch
        DispatchQueue.global(qos: .utility).async {
            let error = CursorGitService.pushAndCreate(root: root, remote: remote, draft: draft, base: base, title: title)
            DispatchQueue.main.async {
                if !error.isEmpty { CursorNotchService.shared.git.error = error }
                CursorNotchService.shared.refreshGit()
            }
        }
    }

    func mergePullRequest() {
        guard let session = focusedSession, !session.remote, let root = session.root,
              let pull = git.pullRequest, git.canMerge else { return }
        let method = CursorNotchMergeMethod(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.notchCursorMergeMethod) ?? "") ?? .squash
        let deleteBranch = UserDefaults.standard.bool(forKey: DefaultsKey.notchCursorDeleteBranch)
        let number = pull.number
        DispatchQueue.global(qos: .utility).async {
            let error = CursorGitService.merge(root: root, number: number, method: method, deleteBranch: deleteBranch)
            DispatchQueue.main.async {
                if !error.isEmpty { CursorNotchService.shared.git.error = error }
                CursorNotchService.shared.refreshGit()
            }
        }
    }

    func openPullRequest() {
        guard let url = git.pullRequest?.url else { return }
        let host = CursorGitPlan.host(of: url)
        guard CursorGitPlan.canOpen(url: url, expectedHost: host), let link = URL(string: url) else { return }
        NSWorkspace.shared.open(link)
    }

    func rememberRepo(_ path: String) {
        let current = UserDefaults.standard.stringArray(forKey: DefaultsKey.notchCursorRecentRepos) ?? []
        let next = CursorRepoList.remember(path, existing: current)
        UserDefaults.standard.set(next, forKey: DefaultsKey.notchCursorRecentRepos)
        recentRepos = next
    }

    private func decide(_ message: CursorHookMessage) -> CursorHookReply? {
        let queues = queueLock.withLock { $0 }
        let reply = CursorHookDecider.reply(message, queues: queues)
        if message.hook == "stop", let reply, reply.stdout.contains("followup_message") {
            let id = CursorHookDecoder.decode(message)?.conversationID ?? ""
            queueLock.withLock { $0[id] = nil }
            DispatchQueue.main.async { self.queued = self.queueLock.withLock { $0 } }
        }
        return reply
    }

    private func fallback(_ message: CursorHookMessage, overflow _: Bool) -> CursorHookReply {
        if message.hook == "stop" { return .empty }
        let handBack = UserDefaults.standard.string(forKey: DefaultsKey.notchCursorApprovalFallback)
            == CursorNotchApprovalFallback.handBack.rawValue
        if handBack { return CursorHookReplies.deferral(hook: message.hook) }
        return CursorHookReplies.deny()
    }

    private func hold(_ id: UUID, _ message: CursorHookMessage) {
        if message.hook == "stop" {
            holdReply(id, message)
            return
        }
        if islandPaused || !islandCanShow() {
            server.complete(id, reply: CursorHookReplies.deferral(hook: message.hook))
            return
        }
        let fields = CursorHookDecoder.decode(message)
        let conversation = fields?.conversationID ?? ""
        let session = sessions.first { $0.id == conversation }
        let kind: CursorApprovalKind = message.hook == "preToolUse" ? .edit : message.hook == "beforeMCPExecution" ? .mcp : .shell
        let command = fields?.command ?? ""
        let seconds = approvalSeconds()
        let approval = CursorApproval(
            id: id, hook: message.hook, conversationID: conversation, project: session?.project ?? "Cursor",
            command: command, cwd: fields?.cwd ?? "", path: fields?.path ?? "", server: fields?.server ?? "",
            tool: fields?.toolName ?? "", risky: CursorApprovalRules.isRisky(command),
            deadline: Date().addingTimeInterval(TimeInterval(seconds)), timeout: TimeInterval(seconds), kind: kind
        )
        approvals.append(approval)
        if islandBusy()
            || !UserDefaults.standard.bool(forKey: DefaultsKey.notchCursorApprovalOpensIsland) {
            events.send(.notice(CursorNoticeFacts(kind: .needsYou, project: approval.project, files: 0,
                                                   commands: 0, failures: 0, duration: 0, waiting: approvals.count)))
        } else {
            islandPresent()
        }
        schedule(id, after: seconds) { [weak self] in
            self?.finish(approval, reply: self?.fallback(message, overflow: false) ?? CursorHookReplies.deny())
        }
    }

    private func holdReply(_ id: UUID, _ message: CursorHookMessage) {
        let conversation = CursorHookDecoder.decode(message)?.conversationID ?? ""
        if replyHoldID != nil, let previous = replyConversationID {
            completeReply(.empty, conversation: previous)
        }
        replyConversationID = conversation
        replyHoldID = id
        let seconds = approvalHold()
        replyDeadline = Date().addingTimeInterval(TimeInterval(seconds))
        if !islandPaused, islandCanShow() {
            islandPresent()
        }
        schedule(id, after: seconds) { [weak self] in
            self?.completeReply(.empty, conversation: conversation)
        }
    }

    private func finish(_ approval: CursorApproval, reply: CursorHookReply) {
        timeouts[approval.id]?.cancel()
        timeouts[approval.id] = nil
        approvals.removeAll { $0.id == approval.id }
        server.complete(approval.id, reply: reply)
    }

    private func completeReply(_ reply: CursorHookReply, conversation: String) {
        guard replyConversationID == conversation, let id = replyHoldID else { return }
        timeouts[id]?.cancel()
        timeouts[id] = nil
        replyConversationID = nil
        replyHoldID = nil
        replyDeadline = nil
        server.complete(id, reply: reply)
    }

    private func writeContextNote(container: URL) {
        let folder = container.appendingPathComponent(CursorHookProtocol.directoryName, isDirectory: true)
        let url = folder.appendingPathComponent("context-note")
        var info = stat()
        if lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) != S_IFREG { return }
        let note = (UserDefaults.standard.string(forKey: DefaultsKey.notchCursorContextNote) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data(CursorHookProtocol.prefix(note, 4_000).utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func syncGitTimer() {
        let pending = pageVisible && git.pullRequest?.checksPending == true
        guard pending else { stopGitTimer(); return }
        guard gitTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { CursorNotchService.shared.refreshGit() }
        timer.resume()
        gitTimer = timer
    }

    private func stopGitTimer() {
        gitTimer?.cancel()
        gitTimer = nil
    }

    private func schedule(_ id: UUID, after seconds: Int, _ body: @escaping () -> Void) {
        let work = DispatchWorkItem(block: body)
        timeouts[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(max(1, seconds)), execute: work)
    }

    private func approvalSeconds() -> Int {
        let value = UserDefaults.standard.integer(forKey: DefaultsKey.notchCursorApprovalTimeout)
        return [30, 60, 90].contains(value) ? value : 60
    }

    private func approvalHold() -> Int {
        let value = UserDefaults.standard.integer(forKey: DefaultsKey.notchCursorHoldForReply)
        return [30, 60, 120].contains(value) ? value : 0
    }

    private func note(_ message: CursorHookMessage) {
        guard !CursorHookInstaller.isProbe(message) else { return }
        let now = Date()
        lastEvent = now
        let fields = CursorHookDecoder.decode(message)
        let gate = CursorApprovalGate.decide(
            hook: message.hook, command: fields?.command ?? "", path: fields?.path ?? "",
            server: fields?.server ?? "", tool: fields?.toolName ?? "",
            approvals: UserDefaults.standard.bool(forKey: DefaultsKey.notchCursorApprovals),
            edits: UserDefaults.standard.bool(forKey: DefaultsKey.notchCursorApproveEdits),
            allow: CursorApprovalRules.lines(UserDefaults.standard.string(forKey: DefaultsKey.notchCursorAllowRules) ?? ""),
            deny: CursorApprovalRules.lines(UserDefaults.standard.string(forKey: DefaultsKey.notchCursorDenyRules) ?? ""),
            protected: CursorApprovalRules.lines(UserDefaults.standard.string(forKey: DefaultsKey.notchCursorProtectedPaths) ?? "")
        )
        let result = CursorSessionReducer.reduce(store, message: message, now: now, holdApprovals: gate == .hold)
        publish(result)
        if let id = result.focusID, let index = store.sessions.firstIndex(where: { $0.id == id }),
           let step = store.sessions[index].steps.indices.last {
            if gate == .allow { store.sessions[index].steps[step].automatic = .allowed; store.sessions[index].steps[step].status = .done }
            if gate == .deny { store.sessions[index].steps[step].automatic = .denied; store.sessions[index].steps[step].status = .denied }
            if gate == .allow || gate == .deny {
                sessions = store.sessions
            }
        }
        if message.remote == false, let root = fields?.roots.first, !root.isEmpty {
            rememberRepo(root)
        }
        if message.hook == "stop" { refreshGit() }
    }

    private func publish(_ result: CursorReduceResult) {
        store = result.store
        sessions = store.sessions
        if let focus = result.focusID, sessions.contains(where: { $0.id == focus }) {
            selectedID = focus
        } else if selectedID == nil || !sessions.contains(where: { $0.id == selectedID }) {
            selectedID = focusedSession?.id
        }
        events.send(.sessionsChanged)
        deliver(result.notices)
        syncTick()
    }

    private func deliver(_ notices: [CursorNoticeFacts]) {
        let defaults = UserDefaults.standard
        let front = Self.cursorIsFrontmost()
        let finish = defaults.object(forKey: DefaultsKey.notchCursorFinishAlert) as? Bool ?? true
        let failure = defaults.object(forKey: DefaultsKey.notchCursorFailureAlert) as? Bool ?? true
        let minimum = defaults.integer(forKey: DefaultsKey.notchCursorFinishMinimum)
        let quiet = defaults.bool(forKey: DefaultsKey.notchCursorQuietWhenFocused)
        for notice in notices where CursorNoticePolicy.include(notice, finishAlerts: finish, failureAlerts: failure,
                                                                minimumSeconds: minimum, cursorIsFrontmost: front,
                                                                quietWhenFocused: quiet) {
            events.send(.notice(notice))
        }
    }

    private func applyClock(_ transform: (CursorSessionStore, Date) -> CursorSessionStore) {
        let now = Date()
        let next = transform(store, now)
        guard next != store else { return }
        store = next
        sessions = store.sessions
        if selectedID == nil || !sessions.contains(where: { $0.id == selectedID }) {
            selectedID = focusedSession?.id
        }
        events.send(.sessionsChanged)
        syncTick()
    }

    private func syncTick() {
        guard !sessions.isEmpty else {
            stopTick()
            return
        }
        guard tick == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            self?.applyClock(CursorSessionReducer.tick)
        }
        timer.resume()
        tick = timer
    }

    private func stopTick() {
        tick?.cancel()
        tick = nil
    }

    private func startWatching() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            self?.cursorTerminated(note)
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.applyClock(CursorSessionReducer.wake)
        })
    }

    private func stopWatching() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    private func cursorTerminated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard CursorSessionReducer.isCursorApp(bundleIdentifier: app?.bundleIdentifier,
                                               name: app?.localizedName) else { return }
        applyClock(CursorSessionReducer.cursorQuit)
    }

    private static func cursorIsFrontmost() -> Bool {
        let app = NSWorkspace.shared.frontmostApplication
        return CursorSessionReducer.isCursorApp(bundleIdentifier: app?.bundleIdentifier, name: app?.localizedName)
    }
}
