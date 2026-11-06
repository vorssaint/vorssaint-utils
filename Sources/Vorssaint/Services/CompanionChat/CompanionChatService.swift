// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

final class CompanionChatService: NSObject, ObservableObject {
    static let shared = CompanionChatService()
    @Published private(set) var messages: [CompanionMessage] = []
    @Published var draft = ""
    @Published private(set) var busy = false
    @Published private(set) var sending = false
    @Published private(set) var status = ""
    @Published private(set) var agent = CompanionAgent.current
    /// check result for the current ai, nil till it ran or was already known
    @Published private(set) var health: CompanionHealth?
    /// last check for every ai, settings shows these
    @Published private(set) var results: [CompanionAgent: CompanionHealth] = [:]
    @Published private(set) var checkingAgents: Set<CompanionAgent> = []
    /// a check runs on its own, closing the chat or switching ai doesnt stop it
    var checking: Bool { checkingAgents.contains(agent) }
    /// ais being watched after sign in/install started
    @Published private(set) var watching: Set<CompanionAgent> = []
    /// true while chat is on the islands page, ends when island closes or goes to another page (dismiss)
    @Published private(set) var presented = false
    /// page island was on when chat opened, leaving it ends the chat
    private(set) var anchor: NotchModule?
    private let queue = DispatchQueue(label: "com.vorssaint.companion-chat", qos: .userInitiated)
    private let watchQueue = DispatchQueue(label: "com.vorssaint.companion-chat.watch", qos: .utility)
    private var cancellation: BoundedProcessCancellation?
    private var generation = 0

    /// click on companion opens chat
    func companionClicked() { show() }

    /// opens island w/ chat instead of its page
    func show() {
        let notch = NotchService.shared
        guard NotchSupport.isEnabled() else { return }
        let page: NotchModule? = notch.modules.contains(.agents) ? .agents : nil
        anchor = page ?? notch.selected
        presented = true
        notch.open(page)
        if agent != CompanionAgent.current { agent = CompanionAgent.current; messages = []; status = ""; health = nil }
        prepare()
    }

    /// ai that passed once is ready right away, nothing runs. only never-passed ones get checked,
    /// full check comes back only if a q fails or check now
    private func prepare() {
        guard health != .ready else { return }
        if agent.isVerified, agent.executable() != nil {
            health = .ready; results[agent] = .ready; status = ""
        } else {
            runHealthCheck()
        }
    }

    func dismiss() {
        guard presented else { return }
        presented = false; anchor = nil
        if sending { status = CompanionChatText.uncertain }
        generation += 1
        cancellation?.cancel(); cancellation = nil
        busy = false; sending = false
        // chat text + drafts never go to disk
        messages = []; draft = ""
    }

    /// installed, signed in, one word q answered. if it fails chat shows the one fix
    func runHealthCheck() {
        health = nil
        status = CompanionSetupText.text(.checkingNamed, ai: agent.title)
        checkNow(agent)
    }

    /// the one step after a failed check, sign in or install, runs in terminal so u can see it. vorssaint notices after
    func runFix(_ target: CompanionAgent) {
        let tool = target.tool
        let command: String
        switch results[target] ?? health {
        case .notSignedIn?:
            guard let path = target.executable() else { return }
            let quoted = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
            command = quoted + " " + CompanionSetupSupport.loginArguments(for: tool).joined(separator: " ")
        case .notInstalled?:
            guard let install = CompanionSetupSupport.installCommand(for: tool) else { return }
            command = install
        default: return
        }
        Self.sweepSetupScripts()
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-setup-\(UUID().uuidString).command")
        let body = "#!/bin/zsh\necho 'Vorssaint setup for \(target.title):'; echo '  \(command.replacingOccurrences(of: "'", with: ""))'; echo\n\(command)\necho; echo 'Done. Go back to Vorssaint; it will finish setting up by itself.'\nrm -f -- \"$0\"\n"
        guard (try? body.write(to: script, atomically: true, encoding: .utf8)) != nil,
              (try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)) != nil else { return }
        NSWorkspace.shared.open(script)
        status = CompanionSetupText.text(.finishInTerminal, ai: target.title)
        watchFix(target)
    }

    /// setup scripts delete themselves at the end, leftovers from closed terminals get cleaned next time
    private static func sweepSetupScripts() {
        let folder = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasPrefix("vorssaint-setup-") && name.hasSuffix(".command") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// after sign in/install starts it checks every few secs up to 10 min then does the full check,
    /// nothing else to press. tool keeps the login so later it just works
    private func watchFix(_ target: CompanionAgent) {
        guard !watching.contains(target) else { return }
        watching.insert(target)
        watchQueue.async { [weak self] in
            let deadline = Date().addingTimeInterval(600)
            var done = false
            while Date() < deadline, !done {
                Thread.sleep(forTimeInterval: 5)
                done = target.isReadyToCheck(cancellation: BoundedProcessCancellation())
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.watching.remove(target)
                guard done else { return }
                if target == self.agent, self.presented { self.status = CompanionSetupText.text(.signedInChecking, ai: target.title) }
                self.checkNow(target)
            }
        }
    }

    /// the check for any ai, from settings or the chat. it finishes even if the chat
    /// closes or u switch ai, so a slow test q is never thrown away halfway.
    func checkNow(_ target: CompanionAgent) {
        guard !checkingAgents.contains(target) else { return }
        checkingAgents.insert(target)
        queue.async { [weak self] in
            let result = target.checkHealth(cancellation: BoundedProcessCancellation(), onSignedIn: {
                DispatchQueue.main.async { [weak self] in
                    guard let self, target == self.agent, self.presented else { return }
                    self.status = CompanionSetupText.text(.verifying)
                }
            })
            DispatchQueue.main.async {
                guard let self else { return }
                self.checkingAgents.remove(target)
                self.results[target] = result
                if target == self.agent {
                    self.health = result
                    self.status = CompanionSetupSupport.fix(tool: target.tool, result) ?? ""
                }
            }
        }
    }

    /// refresh button, checks current ai again from scratch
    func recheck() { messages = []; runHealthCheck() }

    func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, question.count <= 16000, !busy else { return }
        sendToTool(question)
    }

    /// one q to a local ai tool, answers stay in memory
    private func sendToTool(_ question: String) {
        let agent = agent
        let prompt = CompanionAgent.prompt(history: messages, question: question)
        busy = true; sending = true; status = ""; draft = ""
        messages.append(.init(id: UUID().uuidString, isUser: true, text: question))
        let token = BoundedProcessCancellation()
        cancellation = token
        let current = generation
        queue.async { [weak self] in
            let result = Result { try agent.ask(prompt, cancellation: token) }
            DispatchQueue.main.async {
                guard let self, self.generation == current else { return }
                self.busy = false; self.sending = false; self.cancellation = nil
                switch result {
                case .success(let answer): self.messages.append(.init(id: UUID().uuidString, isUser: false, text: answer))
                case .failure(let error):
                    if let failure = error as? CompanionFailure, case .missing = failure {
                        self.status = CompanionSetupText.text(.notInstalledOnMac, ai: agent.title)
                    } else { self.health = nil; self.runHealthCheck() }
                }
            }
        }
    }

    /// switch ai + remember it (same as settings). nothing sent to the one u left
    func switchAgent(_ next: CompanionAgent) {
        guard next != agent, !sending else { return }
        UserDefaults.standard.set(next.rawValue, forKey: DefaultsKey.companionChatAgent)
        generation += 1
        cancellation?.cancel(); cancellation = nil
        busy = false
        messages = []; status = ""; health = nil
        agent = next
        prepare()
    }

    func openApp() {
        let bundle: String
        switch agent {
        case .claude: bundle = "com.anthropic.claudefordesktop"
        case .cursor: bundle = "com.todesktop.230313mzl4w4u92"
        case .chatgpt: bundle = "com.openai.chat"
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        // open (not just activate) so a closed window comes back
        NSWorkspace.shared.open(url)
    }
}
