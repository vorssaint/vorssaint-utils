// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The pending approval. A and D answer it only while this card is focused
/// and the composer is not. Escape is left to the island, so it never denies.
struct NotchCursorApprovalCard: View {
    @ObservedObject private var cursor = CursorNotchService.shared
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var focused: Bool
    @State private var confirming = false

    private var text: NotchCursorControlStrings { FeatureStrings.notchCursorControl(l10n.language) }
    private var options: NotchCursorOptionStrings { FeatureStrings.notchCursorOptions(l10n.language) }

    var body: some View {
        if let approval = cursor.approvals.first {
            let index = (cursor.approvals.firstIndex(where: { $0.id == approval.id }) ?? 0) + 1
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(text.of(index, cursor.approvals.count))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    if approval.risky { badge(options.risky) }
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = seconds(until: approval.deadline, now: context.date)
                        HStack(spacing: 4) {
                            Circle()
                                .trim(from: 0, to: ring(approval, now: context.date))
                                .stroke(Color.orange, lineWidth: 2)
                                .frame(width: 14, height: 14)
                                .rotationEffect(.degrees(-90))
                            Text(left)
                                .font(.system(size: 11, design: .monospaced))
                                .contentTransition(.numericText())
                        }
                    }
                }
                Text(approval.project)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if !approval.cwd.isEmpty {
                    Text(approval.cwd)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Text(subject(approval))
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(4)
                    .textSelection(.enabled)
                if confirming {
                    Text(text.tokens(subject(approval)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
                HStack(spacing: 8) {
                    Button(text.deny) { CursorNotchFeedback.tap(); cursor.deny(approval) }
                    Button(text.allow) { CursorNotchFeedback.tap(); cursor.allow(approval) }
                    Button(confirming ? text.confirmRule : text.alwaysAllow) {
                        if confirming { cursor.allowAlways(approval) } else { confirming = true }
                    }
                    .disabled(subject(approval).isEmpty)
                    if approval.canHandBack {
                        Button(text.answerInCursor) { cursor.handBack(approval) }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .focusable()
            .focused($focused)
            .onAppear { focused = true }
            .onKeyPress(phases: .down) { press in
                guard focused, !cursor.composerFocused else { return .ignored }
                switch press.characters.lowercased() {
                case "a": CursorNotchFeedback.tap(); cursor.allow(approval); return .handled
                case "d": CursorNotchFeedback.tap(); cursor.deny(approval); return .handled
                default: return .ignored
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func subject(_ approval: CursorApproval) -> String {
        switch approval.kind {
        case .edit: return approval.path
        case .mcp:
            let name = [approval.server, approval.tool].filter { !$0.isEmpty }.joined(separator: " ")
            return approval.command.isEmpty ? name : approval.command
        case .shell: return approval.command
        }
    }

    private func seconds(until deadline: Date, now: Date) -> String {
        "\(max(0, Int(deadline.timeIntervalSince(now).rounded(.up))))"
    }

    private func ring(_ approval: CursorApproval, now: Date) -> CGFloat {
        let total = max(1, approval.timeout)
        let left = max(0, approval.deadline.timeIntervalSince(now))
        return CGFloat(min(1, left / total))
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.35), in: Capsule())
    }
}

/// Queues a follow-up, or answers a turn that is waiting.
struct NotchCursorComposer: View {
    let session: CursorSession
    @ObservedObject private var cursor = CursorNotchService.shared
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var focused: Bool
    @State private var draft = ""

    private var text: NotchCursorControlStrings { FeatureStrings.notchCursorControl(l10n.language) }
    private var holding: Bool { cursor.replyConversationID == session.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(holding ? text.holdHint : text.queue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            TextField(text.queue, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
                .onChange(of: focused) { _, value in cursor.composerFocused = value }
                .onChange(of: draft) { _, value in cursor.composerDraft = value }
                .onChange(of: session.id) { _, _ in
                    draft = ""
                    cursor.composerDraft = ""
                }
                .onDisappear {
                    cursor.composerFocused = false
                    cursor.composerDraft = ""
                }
                .onExitCommand {
                    if holding { cursor.skipReply() }
                }
                .onSubmit(submit)
            HStack(spacing: 8) {
                Button(text.send, action: submit)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if holding {
                    Button(text.skip, action: cursor.skipReply)
                    if let deadline = cursor.replyDeadline {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("\(max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up))))")
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func submit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if holding {
            cursor.sendReply(trimmed)
        } else {
            cursor.queue(trimmed, for: session.id)
        }
        draft = ""
        focused = false
    }
}

struct NotchCursorSessionActions: View {
    let session: CursorSession
    @ObservedObject private var l10n = L10n.shared

    private var text: NotchCursorControlStrings { FeatureStrings.notchCursorControl(l10n.language) }
    private var canJump: Bool {
        !session.remote && session.root != nil && CursorAppBridge.applicationURL() != nil
    }

    var body: some View {
        if CursorAppBridge.applicationURL() != nil {
            Button(text.jump) {
                if let root = session.root { _ = CursorAppBridge.focus(workspace: root) }
            }
            .disabled(!canJump)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(session.remote ? text.remoteOff : text.jump)
        }
    }
}

struct NotchCursorNewChat: View {
    @ObservedObject private var cursor = CursorNotchService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var prompt = ""
    @State private var repo = ""

    private var text: NotchCursorControlStrings { FeatureStrings.notchCursorControl(l10n.language) }
    private var count: Int { CursorPromptLink.encodedCount(prompt) }
    private var ready: Bool {
        CursorAppBridge.applicationURL() != nil && !repo.isEmpty && CursorPromptLink.fits(prompt) && !prompt.isEmpty
    }

    var body: some View {
        if CursorAppBridge.applicationURL() != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text(text.newChat)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                if !cursor.recentRepos.isEmpty {
                    Picker(text.newChat, selection: $repo) {
                        Text(" ").tag("")
                        ForEach(cursor.recentRepos, id: \.self) { path in
                            Text(URL(fileURLWithPath: path).lastPathComponent).tag(path)
                        }
                    }
                    .labelsHidden()
                }
                TextField(text.newChat, text: $prompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                Text(CursorPromptLink.fits(prompt) ? "\(count) / \(CursorPromptLink.limit)" : text.promptTooLong)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(CursorPromptLink.fits(prompt) ? Color.white.opacity(0.55) : Color.orange)
                HStack(spacing: 8) {
                    Button(text.addFolder, action: chooseFolder)
                    Button(text.newChat, action: open)
                        .disabled(!ready)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            cursor.rememberRepo(url.path)
            repo = url.path
        }
    }

    private func open() {
        guard ready else { return }
        let folder = repo
        let message = prompt
        prompt = ""
        CursorAppBridge.openFolderThenPrompt(path: folder, text: message)
    }
}

struct NotchCursorPullRequestCard: View {
    let session: CursorSession
    @ObservedObject private var cursor = CursorNotchService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchCursorPullRequests) private var enabled = false
    @State private var title = ""
    @State private var confirmingCreate = false
    @State private var confirmingMerge = false

    private var text: NotchCursorControlStrings { FeatureStrings.notchCursorControl(l10n.language) }
    private var options: NotchCursorOptionStrings { FeatureStrings.notchCursorOptions(l10n.language) }

    var body: some View {
        if enabled {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(text.pullRequests)
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 0)
                    Button(options.refresh) { cursor.refreshGit() }
                        .disabled(session.remote)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if session.remote {
                    Text(text.remoteOff)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                } else if cursor.git.ghMissing {
                    Text(text.ghMissing).font(.system(size: 12))
                } else if !cursor.git.authenticated {
                    Text(text.signIn).font(.system(size: 12))
                } else {
                    status
                    if let pull = cursor.git.pullRequest { existing(pull) }
                    else { create }
                }
                if !cursor.git.error.isEmpty {
                    Text(cursor.git.error)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(3)
                }
            }
            .font(.system(size: 12))
        }
    }

    private var status: some View {
        HStack(spacing: 6) {
            Text(cursor.git.detached ? "HEAD" : cursor.git.branch).lineLimit(1)
            if cursor.git.dirty { badge(text.askCommit) }
            if cursor.git.ahead > 0 { badge("\(cursor.git.ahead)") }
        }
    }

    @ViewBuilder
    private var create: some View {
        if cursor.git.dirty {
            Button(text.askCommit) { cursor.queue(text.askCommit, for: session.id) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else if confirmingCreate {
            Text(pushLine).font(.system(size: 10, design: .monospaced))
            Text(createLine).font(.system(size: 10, design: .monospaced))
            TextField(text.createPR, text: $title)
                .textFieldStyle(.plain)
            HStack {
                Button(options.confirm) { cursor.createPullRequest(title: title); confirmingCreate = false }
                Button(options.cancel) { confirmingCreate = false }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            Button(text.createPR) { confirmingCreate = true }
                .disabled(!cursor.git.canCreate)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func existing(_ pull: CursorPullRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("#\(pull.number) \(pull.title)").lineLimit(2)
            Text("\(pull.base) ← \(pull.head)").font(.system(size: 10, design: .monospaced))
            if pull.isDraft { badge(text.draft) }
            HStack {
                Button(text.openFile) { cursor.openPullRequest() }
                    .disabled(!canOpen(pull))
                Button(text.checks) { cursor.openPullRequest() }
                    .disabled(!canOpen(pull))
                Button(text.merge) { confirmingMerge = true }
                    .disabled(!cursor.git.canMerge)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if confirmingMerge {
                let method = UserDefaults.standard.string(forKey: DefaultsKey.notchCursorMergeMethod) ?? "squash"
                Text("#\(pull.number) \(pull.title)").lineLimit(2)
                Text("\(pull.head) → \(pull.base) · \(method)")
                Text(mergeLine(pull, method: method)).font(.system(size: 10, design: .monospaced))
                HStack {
                    Button(options.confirm) { cursor.mergePullRequest(); confirmingMerge = false }
                    Button(options.cancel) { confirmingMerge = false }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var pushLine: String {
        "git " + CursorGitPlan.pushArguments(remote: cursor.git.remote).joined(separator: " ")
    }

    private var createLine: String {
        "gh " + CursorGitPlan.createArguments(draft: UserDefaults.standard.bool(forKey: DefaultsKey.notchCursorPRDraft),
                                               base: cursor.git.defaultBranch, title: title).joined(separator: " ")
    }

    private func mergeLine(_ pull: CursorPullRequest, method: String) -> String {
        let delete = UserDefaults.standard.bool(forKey: DefaultsKey.notchCursorDeleteBranch)
        var line = "gh pr merge \(pull.number) --\(method)"
        if delete { line += " --delete-branch" }
        return line
    }

    private func canOpen(_ pull: CursorPullRequest) -> Bool {
        CursorGitPlan.canOpen(url: pull.url, expectedHost: CursorGitPlan.host(of: pull.url))
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.08), in: Capsule())
    }
}

struct NotchCursorExperimentalControls: View {
    let session: CursorSession
    @ObservedObject private var cursor = CursorNotchService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchCursorExperimental) private var enabled = false
    @State private var note = ""
    @State private var confirmingUndo = false

    private var text: NotchCursorPolishStrings { FeatureStrings.notchCursorPolish(l10n.language) }

    var body: some View {
        if enabled {
            VStack(alignment: .leading, spacing: 6) {
                Text(text.experimental)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 8) {
                    action(.sendNow, text.sendNow)
                    action(.stop, text.stopRun)
                    action(.keepAll, text.keepAll)
                    action(.undoAll, text.undoAll)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if confirmingUndo {
                    Text(text.confirmUndo)
                        .font(.system(size: 11))
                    HStack {
                        Button(FeatureStrings.notchCursorOptions(l10n.language).confirm) {
                            run(.undoAll)
                            confirmingUndo = false
                        }
                        Button(FeatureStrings.notchCursorOptions(l10n.language).cancel) { confirmingUndo = false }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func action(_ kind: CursorExperimentalAction, _ title: String) -> some View {
        Button(title) {
            if kind == .undoAll { confirmingUndo = true } else { run(kind) }
        }
    }

    private func run(_ kind: CursorExperimentalAction) {
        let block = CursorExperimentalRunner.perform(session: session, action: kind, text: message)
        note = block.map { text.message($0) } ?? ""
    }

    /// The composer wins. A queued follow-up is used only when the field is empty.
    private var message: String {
        let typed = cursor.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return cursor.queued[session.id] ?? ""
    }
}
