// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The AI Accounts page: each provider's saved logins with their limits.
/// A tap on a login that is not in use makes it the one the tool signs in with.
struct NotchAccountsView: View {
    let size: CGSize
    @ObservedObject private var service = AgentAccountService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAccountsAutoSwapClaude) private var autoSwapClaude = false
    @AppStorage(DefaultsKey.notchAccountsAutoSwapCodex) private var autoSwapCodex = false

    private var text: NotchAccountStrings { FeatureStrings.notchAccounts(l10n.language) }

    /// Only providers with something to show: a saved login, or one to save.
    private var providers: [AgentProvider] {
        AgentAccountService.providers.filter { provider in
            if case .unsaved = service.liveLogin[provider] { return true }
            return service.accounts.contains { $0.account.provider == provider }
        }
    }

    var body: some View {
        let providers = providers
        Group {
            if providers.isEmpty {
                NotchEmptyView(symbol: NotchModule.accounts.symbol, message: text.empty) {
                    NotchPillButton(title: text.addLoginLabel, prominent: true) {
                        NotchService.shared.openSettings(showing: .accounts)
                    }
                }
            } else {
                // The countdowns are in minutes; nothing here moves faster.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(providers, id: \.self) { provider in
                                group(provider, first: provider == providers.first, now: context.date)
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .environment(\.locale, l10n.language.formattingLocale())
        .onAppear { service.pageDidAppear() }
    }

    private func group(_ provider: AgentProvider, first: Bool, now: Date) -> some View {
        let sessions = service.runningSessions[provider] ?? 0
        return NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 8) {
                NotchAgentCardHeader(title: provider.displayName, symbol: provider.symbol, tint: provider.tint,
                                     provider: provider) {
                    HStack(spacing: 6) {
                        if sessions > 0 {
                            Text(text.sessions(sessions, provider: provider))
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        if provider == .claude ? autoSwapClaude : autoSwapCodex {
                            NotchAgentChip(text: text.auto, tint: provider.tint)
                        }
                        // Signing in happens in Settings, where there is room for it.
                        Button {
                            NotchService.shared.openSettings(showing: .accounts)
                        } label: {
                            Image(systemName: "plus").font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 17, height: 17)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(text.addLoginLabel)
                        .accessibilityLabel(text.addLoginLabel)
                        if first {
                            Button {
                                NotchService.shared.openSettings(showing: .accounts)
                            } label: {
                                Image(systemName: "gearshape").font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 17, height: 17)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(text.settings)
                            .accessibilityLabel(text.settings)
                        }
                    }
                }
                switch service.liveLogin[provider] {
                case .unsaved(let email): unsaved(email, provider: provider)
                case .signedOut: note(text.notSignedInNote)
                case .unsupported: note(text.apiKeyLogin)
                case .saved, nil: EmptyView()
                }
                ForEach(service.accounts.filter { $0.account.provider == provider }) { state in
                    NotchAccountRow(state: state, switching: service.switching, now: now, text: text,
                                    agents: FeatureStrings.notchAgents(l10n.language)) {
                        service.switchTo(state.id)
                    }
                }
                if let error = error(for: provider, first: first) {
                    Text(error)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The login the tool uses now, which nobody saved yet: the person just
    /// signed in to another account.
    private func unsaved(_ email: String, provider: AgentProvider) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 12))
                .foregroundStyle(provider.tint)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text.unsaved(email))
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
            Spacer(minLength: 6)
            NotchPillButton(title: text.save, prominent: true) { service.saveLiveLogin(provider) }
        }
    }

    /// Why none of a provider's saved logins is the one in use.
    private func note(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    /// The last failure, under the provider it is about; one without a
    /// provider goes under the first.
    private func error(for provider: AgentProvider, first: Bool) -> String? {
        guard let error = service.lastError else { return nil }
        let owner: AgentProvider?
        switch error {
        case .switchFailed(let provider, _): owner = provider
        case .saveFailed(let provider, _): owner = provider
        case .removeFailed: owner = nil
        }
        return owner == provider || (owner == nil && first) ? text.message(error) : nil
    }
}

/// One saved login: who it is, whether it is the one in use, and how much of
/// its session, its week and its tightest model allowance is spent.
private struct NotchAccountRow: View {
    let state: AgentAccountState
    /// The login a swap is moving to; every row waits while one is under way.
    let switching: AgentAccount.ID?
    let now: Date
    let text: NotchAccountStrings
    let agents: NotchAgentStrings
    let onSwitch: () -> Void
    @Environment(\.locale) private var locale

    private var account: AgentAccount { state.account }
    private var canSwitch: Bool { !state.isActive && !account.needsLogin && switching == nil }

    /// The session, the longer window that covers every model, and the model
    /// allowance closest to its end.
    private var windows: [AgentLimitWindow] {
        let all = (state.limits?.windows ?? []).map { AgentLimitSupport.current($0, at: now) }
        let session = all.first { $0.kind == .session }
        let longer = all.filter { $0.kind != .session && $0.scope == nil }.max { $0.usedPercent < $1.usedPercent }
        let scoped = all.filter { $0.scope != nil }.max { $0.usedPercent < $1.usedPercent }
        return [session, longer, scoped].compactMap { $0 }
    }

    var body: some View {
        if canSwitch {
            Button(action: onSwitch) { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(text.switchTo(account.displayName))
                .help(text.switchTo(account.displayName))
        } else {
            content.accessibilityElement(children: .combine)
        }
    }

    private var content: some View {
        let windows = windows
        return HStack(alignment: .center, spacing: 10) {
            mark.frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(state.isActive ? 1 : 0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                let tag = [account.label.isEmpty ? "" : account.email, account.organization].filter { !$0.isEmpty }
                if !tag.isEmpty {
                    Text(tag.joined(separator: " · "))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if account.needsLogin {
                note(text.needsLogin, tint: .orange).help(text.needsLoginHint)
            } else if windows.isEmpty {
                note(state.usageError.map { text.message($0, provider: account.provider) } ?? text.noUsage, tint: .secondary)
            } else {
                HStack(spacing: 10) {
                    ForEach(windows) { meter($0) }
                }
                // A reading that could not be renewed is still the last known.
                .opacity(state.usageError == nil ? 1 : 0.6)
                .help(state.usageError.map { text.message($0, provider: account.provider) } ?? "")
            }
        }
    }

    @ViewBuilder private var mark: some View {
        if switching == state.id {
            ProgressView().controlSize(.small).scaleEffect(0.7)
        } else if state.isActive {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(account.provider.tint)
                .accessibilityLabel(text.active)
        } else {
            Image(systemName: "circle")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
                .accessibilityHidden(true)
        }
    }

    private func note(_ message: String, tint: Color) -> some View {
        Text(message)
            .font(.system(size: 10.5))
            .foregroundStyle(tint)
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
    }

    private func meter(_ window: AgentLimitWindow) -> some View {
        let tint = agentLimitTint(account.provider, usedFraction: window.usedFraction)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(label(window))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(AgentFormat.percent(window.usedFraction))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint == account.provider.tint ? Color.white : tint)
            }
            NotchAgentMeter(value: window.usedFraction, tint: tint, height: 4)
            // Kept as a line of its own so rows with and without a renewal line up.
            Group {
                if let resets = window.resetsAt {
                    Label(countdown(to: resets), systemImage: "arrow.clockwise").labelStyle(NotchAgentInlineLabel())
                } else {
                    Text(" ")
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        // A model's allowance is the third reading, narrower than the two that always show.
        .frame(width: window.scope == nil ? 86 : 70)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label(window)), \(agents.usedShare(AgentFormat.percent(window.usedFraction)))")
    }

    private func label(_ window: AgentLimitWindow) -> String {
        if let scope = window.scope { return scope }
        switch window.kind {
        case .session: return agents.session
        case .weekly: return agents.weekly
        case .other:
            return window.minutes.map { AgentFormat.duration(TimeInterval($0) * 60, locale: locale, units: 1) }
                ?? agents.readoutLimit
        }
    }

    private func countdown(to date: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        return AgentFormat.duration(max(60, seconds), locale: locale, units: seconds >= 3600 ? 2 : 1)
    }
}
