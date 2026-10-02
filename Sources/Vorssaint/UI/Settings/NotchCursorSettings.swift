// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Cursor section on the island's Content tab.
struct NotchCursorSettingsControls: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchCursorSources) private var sources = CursorNotchSource.app.rawValue
    @AppStorage(DefaultsKey.notchCursorLiveActivity) private var liveActivity = true
    @AppStorage(DefaultsKey.notchCursorReadout) private var readout = CursorNotchReadout.state.rawValue
    @AppStorage(DefaultsKey.notchCursorFinishAlert) private var finishAlert = true
    @AppStorage(DefaultsKey.notchCursorFinishMinimum) private var finishMinimum = 0
    @AppStorage(DefaultsKey.notchCursorFailureAlert) private var failureAlert = true
    @AppStorage(DefaultsKey.notchCursorQuietWhenFocused) private var quietWhenFocused = false
    @AppStorage(DefaultsKey.notchCursorApprovals) private var approvals = false
    @AppStorage(DefaultsKey.notchCursorApprovalTimeout) private var timeout = 60
    @AppStorage(DefaultsKey.notchCursorApprovalFallback) private var fallback = CursorNotchApprovalFallback.deny.rawValue
    @AppStorage(DefaultsKey.notchCursorApprovalOpensIsland) private var opensIsland = true
    @AppStorage(DefaultsKey.notchCursorApproveEdits) private var approveEdits = false
    @AppStorage(DefaultsKey.notchCursorProtectedPaths) private var protectedPaths = ""
    @AppStorage(DefaultsKey.notchCursorAllowRules) private var allowRules = ""
    @AppStorage(DefaultsKey.notchCursorDenyRules) private var denyRules = ""
    @AppStorage(DefaultsKey.notchCursorHoldForReply) private var holdForReply = 0
    @AppStorage(DefaultsKey.notchCursorQueueOnAbort) private var queueOnAbort = false
    @AppStorage(DefaultsKey.notchCursorContextNote) private var contextNote = ""
    @AppStorage(DefaultsKey.notchCursorPullRequests) private var pullRequests = false
    @AppStorage(DefaultsKey.notchCursorPRDraft) private var draft = false
    @AppStorage(DefaultsKey.notchCursorMergeMethod) private var mergeMethod = CursorNotchMergeMethod.squash.rawValue
    @AppStorage(DefaultsKey.notchCursorDeleteBranch) private var deleteBranch = false
    @AppStorage(DefaultsKey.notchCursorExperimental) private var experimental = false
    @AppStorage(DefaultsKey.notchCursorShortcuts) private var shortcuts = ""
    @AppStorage(DefaultsKey.notchCursorBuddy) private var buddy = true
    @AppStorage(DefaultsKey.notchCursorEyesFollow) private var eyesFollow = false
    @AppStorage(DefaultsKey.notchCursorGlow) private var glow = false
    @AppStorage(DefaultsKey.notchCursorTypewriter) private var typewriter = true
    @AppStorage(DefaultsKey.notchCursorSounds) private var sounds = false
    @State private var experimentalNote = ""

    private var text: NotchCursorControlStrings { FeatureStrings.notchCursorControl(l10n.language) }
    private var options: NotchCursorOptionStrings { FeatureStrings.notchCursorOptions(l10n.language) }
    private var polish: NotchCursorPolishStrings { FeatureStrings.notchCursorPolish(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CursorHookConnectControls(inNotch: false)
            DisclosureGroup(text.sources) {
                Picker(text.sources, selection: $sources) {
                    Text(text.appOnly).tag(CursorNotchSource.app.rawValue)
                    Text(text.appAndTerminal).tag(CursorNotchSource.appAndTerminal.rawValue)
                }
                .labelsHidden()
            }
            DisclosureGroup(options.liveActivity) {
                Toggle(options.liveActivity, isOn: $liveActivity)
                Picker(options.readout, selection: $readout) {
                    Text(options.stateWord).tag(CursorNotchReadout.state.rawValue)
                    Text(options.elapsedWord).tag(CursorNotchReadout.elapsed.rawValue)
                    Text(options.projectWord).tag(CursorNotchReadout.project.rawValue)
                }
            }
            DisclosureGroup(options.notices) {
                Toggle(options.finishNotice, isOn: $finishAlert)
                Stepper(value: $finishMinimum, in: 0...3600, step: 30) {
                    Text("\(options.finishNotice) \(finishMinimum)")
                }
                Toggle(options.failureNotice, isOn: $failureAlert)
                Toggle(options.quietFocused, isOn: $quietWhenFocused)
            }
            DisclosureGroup(text.approvals) {
                Toggle(text.approvals, isOn: $approvals)
                Picker(options.timeout, selection: $timeout) {
                    Text("30").tag(30)
                    Text("60").tag(60)
                    Text("90").tag(90)
                }
                Picker(options.handBack, selection: $fallback) {
                    Text(text.deny).tag(CursorNotchApprovalFallback.deny.rawValue)
                    Text(options.handBack).tag(CursorNotchApprovalFallback.handBack.rawValue)
                }
                Toggle(options.openIsland, isOn: $opensIsland)
                Toggle(options.editApprovals, isOn: $approveEdits)
                ruleField(text.protectedPaths, text: $protectedPaths)
                ruleField(text.allowRules, text: $allowRules)
                ruleField(text.denyRules, text: $denyRules)
            }
            DisclosureGroup(options.replies) {
                Text(text.holdHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker(options.holdForReply, selection: $holdForReply) {
                    Text("0").tag(0)
                    Text("30").tag(30)
                    Text("60").tag(60)
                    Text("120").tag(120)
                }
                Toggle(options.queueOnAbort, isOn: $queueOnAbort)
                Text(text.contextNote).font(.callout)
                TextField(text.contextNote, text: $contextNote, axis: .vertical)
                    .lineLimit(2...4)
            }
            DisclosureGroup(text.pullRequests) {
                Toggle(text.pullRequests, isOn: $pullRequests)
                Toggle(text.draft, isOn: $draft)
                Picker(text.merge, selection: $mergeMethod) {
                    Text(CursorNotchMergeMethod.squash.rawValue).tag(CursorNotchMergeMethod.squash.rawValue)
                    Text(CursorNotchMergeMethod.merge.rawValue).tag(CursorNotchMergeMethod.merge.rawValue)
                    Text(CursorNotchMergeMethod.rebase.rawValue).tag(CursorNotchMergeMethod.rebase.rawValue)
                }
                Toggle(text.deleteBranch, isOn: $deleteBranch)
            }
            DisclosureGroup(polish.experimental) {
                Toggle(polish.experimental, isOn: $experimental)
                    .onChange(of: experimental) { _, on in
                        if on { Permissions.shared.requestAccessibility() }
                    }
                ForEach(CursorExperimentalAction.allCases, id: \.self) { action in
                    shortcutRow(action)
                }
                if !experimentalNote.isEmpty {
                    Text(experimentalNote).font(.callout).foregroundStyle(.secondary)
                }
            }
            DisclosureGroup(polish.look) {
                Toggle(polish.buddy, isOn: $buddy)
                Toggle(polish.eyesFollow, isOn: $eyesFollow)
                Toggle(polish.glow, isOn: $glow)
                Toggle(polish.typewriter, isOn: $typewriter)
                Toggle(polish.sounds, isOn: $sounds)
            }
        }
        .onChange(of: contextNote) { _, _ in
            CursorNotchService.shared.refreshContextNote()
        }
    }

    private func shortcutRow(_ action: CursorExperimentalAction) -> some View {
        let stored = CursorShortcutStore.chord(action, in: shortcuts)
        return HStack {
            Text(actionTitle(action)).frame(width: 120, alignment: .leading)
            ShortcutRecorderButton(
                shortcut: stored ?? GlobalShortcut(keyCode: 0, modifiers: [.command]),
                isEnabled: true,
                waitingTitle: polish.record,
                emptyTitle: stored == nil ? polish.noShortcut : nil,
                clearAction: { save(nil, for: action) },
                invalidAction: {},
                captureAction: { save($0, for: action) }
            )
            .frame(width: 160)
            Button(polish.test) {
                let remote = CursorNotchService.shared.focusedSession?.remote == true
                let block = CursorExperimentalRunner.test(action: action, remote: remote)
                experimentalNote = block.map { polish.message($0) } ?? ""
            }
        }
    }

    private func actionTitle(_ action: CursorExperimentalAction) -> String {
        switch action {
        case .sendNow: return polish.sendNow
        case .stop: return polish.stopRun
        case .keepAll: return polish.keepAll
        case .undoAll: return polish.undoAll
        }
    }

    private func save(_ shortcut: GlobalShortcut?, for action: CursorExperimentalAction) {
        var map = CursorShortcutStore.chords(in: shortcuts)
        map[action] = shortcut?.storageValue ?? ""
        shortcuts = CursorShortcutStore.stored(map)
    }

    private func ruleField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout)
            TextField(title, text: text, axis: .vertical)
                .lineLimit(2...5)
                .font(.system(size: 12, design: .monospaced))
        }
    }
}

/// Connect, preview, and the health line. The empty Cursor page uses the same flow.
struct CursorHookConnectControls: View {
    var inNotch: Bool
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var model = CursorHookConnectModel.shared
    @ObservedObject private var service = CursorNotchService.shared

    private var text: NotchCursorStrings { FeatureStrings.notchCursor(l10n.language) }
    private var connect: NotchCursorConnectStrings { FeatureStrings.notchCursorConnect(l10n.language) }
    private var ink: Color { inNotch ? .white : .primary }
    private var quiet: Color { inNotch ? .white.opacity(0.72) : .secondary }

    private var waiting: Bool {
        guard let confirmedAt = model.confirmedAt, model.status == .installed || model.status == .needsUpdate else { return false }
        guard let last = service.lastEvent else { return true }
        return last < confirmedAt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: inNotch ? 8 : 10) {
            Text(text.connectTitle)
                .font(inNotch ? .callout.weight(.semibold) : .callout.weight(.semibold))
                .foregroundStyle(ink)
            Text(statusLine)
                .font(.callout)
                .foregroundStyle(statusColor)
            if model.status == .unreadable {
                Text(connect.manualSteps)
                    .font(.callout)
                    .foregroundStyle(quiet)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.showingConnect, !model.otherCopies.isEmpty, model.preview == nil {
                Text(connect.otherCopyWarning)
                    .font(.callout)
                    .foregroundStyle(quiet)
                    .fixedSize(horizontal: false, vertical: true)
                buttonRow {
                    Button(connect.replaceCopiesButton, action: model.replaceAndPreview)
                    Button(connect.cancelButton, action: model.cancelConnect)
                }
            } else if let preview = model.preview {
                Text(connect.previewHeading)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ink)
                ScrollView {
                    Text(preview)
                        .font(.system(size: inNotch ? 9 : 11, design: .monospaced))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: inNotch ? 120 : 180)
                buttonRow {
                    Button(connect.confirmButton, action: model.confirm)
                        .disabled(model.working)
                    Button(connect.cancelButton, action: model.cancelConnect)
                }
            } else if waiting {
                Text(connect.waitingTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(quiet)
                Text(connect.waitingHint)
                    .font(.callout)
                    .foregroundStyle(quiet)
                health
            } else if model.status == .installed || model.status == .needsUpdate {
                Text(connect.connectedTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.green)
                health
                buttonRow {
                    if model.status == .needsUpdate {
                        Button(connect.repairButton, action: model.repair)
                    }
                    Button(connect.testConnection, action: model.testConnection)
                        .disabled(model.working)
                    Button(connect.disconnectButton, action: model.disconnect)
                }
            } else {
                Text(inNotch ? text.connectBody : text.settingsDescription)
                    .font(.callout)
                    .foregroundStyle(quiet)
                    .fixedSize(horizontal: false, vertical: true)
                Button(text.connectTitle, action: model.startConnect)
                    .disabled(model.status == .unreadable)
            }
            if model.helperMissing {
                Text(connect.helperMissing)
                    .font(.callout)
                    .foregroundStyle(quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let testResult = model.testResult {
                Text(testResult ? connect.testSucceeded : connect.testFailed)
                    .font(.callout)
                    .foregroundStyle(testResult ? Color.green : quiet)
            }
        }
        .onAppear {
            model.refresh()
            model.alignIfSettingsChanged()
        }
    }

    private var statusLine: String {
        switch model.status {
        case .notInstalled: return connect.statusNotInstalled
        case .installed: return connect.statusInstalled
        case .needsUpdate: return connect.statusNeedsUpdate
        case .unreadable: return connect.statusUnreadable
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .installed: return Color.green
        case .needsUpdate, .unreadable: return inNotch ? .white : .orange
        case .notInstalled: return quiet
        }
    }

    private var health: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let last = service.lastEvent {
                Text("\(connect.lastEventPrefix): \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.callout)
                    .foregroundStyle(quiet)
            } else {
                Text("\(connect.lastEventPrefix): \(connect.lastEventNone)")
                    .font(.callout)
                    .foregroundStyle(quiet)
            }
            if waiting {
                HStack(spacing: 8) {
                    Button(connect.testConnection, action: model.testConnection)
                        .disabled(model.working)
                    Button(connect.disconnectButton, action: model.disconnect)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func buttonRow(@ViewBuilder _ buttons: () -> some View) -> some View {
        HStack(spacing: 8) {
            buttons()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
