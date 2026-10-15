// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The AI Accounts options, under its row in the Dynamic Island settings.
/// `isOn` is the section's own switch, the one its row in the list toggles.
struct NotchAccountsSettingsControls: View {
    @Binding var isOn: Bool
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = AgentAccountService.shared
    @AppStorage(DefaultsKey.notchAccountsAutoSwapClaude) private var autoSwapClaude = false
    @AppStorage(DefaultsKey.notchAccountsAutoSwapCodex) private var autoSwapCodex = false
    @AppStorage(DefaultsKey.notchAccountsAutoSwapThreshold) private var threshold = AgentAccountPreferences.defaultThreshold
    @State private var removing: AgentAccount?

    /// Percent of a limit used at which an automatic swap leaves a login.
    private static let thresholds = [80.0, 90.0, 95.0]

    private var text: NotchAccountStrings { FeatureStrings.notchAccounts(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsFeatureSwitchRow(symbol: AppFeature.notchAccounts.symbolName, title: text.title,
                                     caption: text.settingsDescription, isOn: $isOn, feature: .notchAccounts)
            if isOn {
                ForEach(AgentAccountService.providers, id: \.self) { provider in
                    Divider()
                    section(provider)
                }
                Divider()
                SettingsChoiceRow(symbol: "gauge.with.dots.needle.67percent", title: text.threshold, selection: $threshold) {
                    ForEach(Self.thresholds, id: \.self) { value in
                        Text(FeatureStrings.notchAgents(l10n.language).usedShare(AgentFormat.percent(value / 100))).tag(value)
                    }
                }
                if let error = service.lastError {
                    Label(text.message(error), systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(text.privacy).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        // The service reads these itself; the island follows the section's state.
        .onChange(of: [String(autoSwapClaude), String(autoSwapCodex), String(threshold)]) { _, _ in
            NotchService.shared.syncWithPreferences()
        }
        .alert(text.removeConfirm(removing?.displayName ?? ""),
               isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
               presenting: removing) { account in
            Button(l10n.s.uninstallerCancel, role: .cancel) {}
            Button(text.remove, role: .destructive) { service.remove(account.id) }
        } message: { _ in
            Text(text.removeHint)
        }
    }

    @ViewBuilder private func section(_ provider: AgentProvider) -> some View {
        let status = service.liveLogin[provider]
        HStack(spacing: 12) {
            NotchAgentMark(provider: provider, size: 13)
                .frame(width: 26, height: 26)
                .background(provider.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                // Nothing is known while the island, and so the service, is off.
                if let status {
                    Text(caption(status)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            if case .unsaved = status {
                Button(text.saveThisLogin) { service.saveLiveLogin(provider) }
            }
            // One sign-in at a time, and none while the island is off.
            Button(text.addLogin) { service.beginAdd(provider) }
                .disabled(status == nil || service.adding?.isUnderWay == true)
        }
        if let adding = service.adding, adding.provider == provider {
            NotchAccountAddPanel(state: adding, text: text, cancel: l10n.s.uninstallerCancel, service: service)
                .padding(.leading, settingsRowTextInset)
        }
        ForEach(service.accounts.filter { $0.account.provider == provider }) { state in
            NotchAccountSettingsRow(state: state, text: text) { service.rename(state.id, label: $0) }
                remove: { removing = state.account }
                .padding(.leading, settingsRowTextInset)
        }
        SettingsRow(symbol: "arrow.left.arrow.right", title: text.autoSwap(provider.displayName), caption: text.autoSwapHint) {
            Toggle(text.autoSwap(provider.displayName), isOn: provider == .claude ? $autoSwapClaude : $autoSwapCodex)
                .labelsHidden()
        }
    }

    private func caption(_ status: LiveLoginStatus) -> String {
        switch status {
        case .signedOut: return text.notSignedIn
        case .unsupported: return text.apiKeyLogin
        case .unsaved(let email): return text.signedIn(email)
        case .saved(let id):
            return text.signedIn(service.accounts.first { $0.id == id }?.account.email ?? "")
        }
    }
}

/// A login being added, under its provider: what the person does next while
/// the provider's own sign-in runs, and how it ended when it did not work.
private struct NotchAccountAddPanel: View {
    let state: AddLoginState
    let text: NotchAccountStrings
    let cancel: String
    let service: AgentAccountService
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch state {
            case .starting:
                waiting(text.addStarting)
            case .claude(let url):
                hint(text.addClaudeHint)
                HStack(spacing: 8) {
                    TextField(text.addCodePlaceholder, text: $code)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(maxWidth: 260)
                        .onSubmit(submit)
                    Button(text.addContinue, action: submit)
                        .keyboardShortcut(.defaultAction)
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack(spacing: 8) {
                    Button(text.addOpenBrowser) { NSWorkspace.shared.open(url) }
                    Button(cancel, role: .cancel) { service.cancelAdd() }
                }
            case .codex(let url, let code):
                hint(text.addCodexHint)
                Button(url.absoluteString) { NSWorkspace.shared.open(url) }
                    .buttonStyle(.link)
                HStack(spacing: 12) {
                    Text(code)
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    Button(text.addCopy) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    }
                }
                HStack(spacing: 12) {
                    waiting(text.addWaiting)
                    Button(cancel, role: .cancel) { service.cancelAdd() }
                }
            case .finishing:
                waiting(text.addFinishing)
            case .failed(let provider, let message):
                failure(text.addFailed, detail: message, provider: provider)
            case .toolMissing(let provider):
                failure(text.message(.toolMissing, provider: provider), detail: "", provider: provider)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func submit() {
        service.submitCode(code)
    }

    private func hint(_ message: String) -> some View {
        Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
    }

    private func waiting(_ message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
    }

    /// `detail` is the sign-in tool's own last line, in its own language.
    @ViewBuilder private func failure(_ message: String, detail: String, provider: AgentProvider) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        if !detail.isEmpty {
            Text(detail).font(.caption.monospaced()).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        HStack(spacing: 8) {
            Button(text.addTryAgain) { service.beginAdd(provider) }
            Button(text.addDismiss) { service.cancelAdd() }
        }
    }
}

/// One saved login: a label of the person's own, whose login it is, and the
/// way to forget it.
private struct NotchAccountSettingsRow: View {
    let state: AgentAccountState
    let text: NotchAccountStrings
    let rename: (String) -> Void
    let remove: () -> Void
    @State private var label: String
    @FocusState private var editing: Bool

    init(state: AgentAccountState, text: NotchAccountStrings, rename: @escaping (String) -> Void, remove: @escaping () -> Void) {
        self.state = state
        self.text = text
        self.rename = rename
        self.remove = remove
        _label = State(initialValue: state.account.label)
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                TextField(text.labelPlaceholder, text: $label)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .focused($editing)
                    .onSubmit(commit)
                Text([state.account.email, state.account.organization].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if state.isActive { badge(text.active, tint: .green) }
            if state.account.needsLogin { badge(text.needsLogin, tint: .orange).help(text.needsLoginHint) }
            Spacer(minLength: 8)
            Button(text.remove, role: .destructive, action: remove)
        }
        // Leaving the field saves the label, like pressing Return in it.
        .onChange(of: editing) { _, editing in if !editing { commit() } }
    }

    private func commit() {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != state.account.label else { return }
        rename(trimmed)
    }

    private func badge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.16), in: Capsule(style: .continuous))
    }
}
