// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The AI page: cards the person picked, paired across the strip.
struct NotchAgentsView: View {
    let size: CGSize
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var accounts = CodexProfileLimitsService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchSettingsPreview) private var preview
    @AppStorage(DefaultsKey.notchAgentsPeriod) private var period = AgentPeriod.today.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsCardOrder) private var cardOrder = ""
    @AppStorage(DefaultsKey.notchAgentsHiddenCards) private var hiddenCards = ""
    @AppStorage(DefaultsKey.notchAgentsClaude) private var claude = true
    @AppStorage(DefaultsKey.notchAgentsCodex) private var codex = true
    @AppStorage(DefaultsKey.notchAgentsOpenCode) private var opencode = true
    @AppStorage(DefaultsKey.notchAgentsCopilot) private var copilot = true
    @AppStorage(DefaultsKey.notchAgentsCursor) private var cursor = true
    @AppStorage(DefaultsKey.notchAgentsAntigravity) private var antigravity = true
    @AppStorage(DefaultsKey.notchAgentsGemini) private var gemini = true

    private var text: NotchAgentStrings { FeatureStrings.notchAgents(l10n.language) }
    private var chosenPeriod: AgentPeriod { AgentPeriod(rawValue: period) ?? .today }

    /// The Codex homes the person added, each with a card in the Limits
    /// card's place, so none while that card is hidden.
    private var codexAccounts: [CodexProfileLimitsState] {
        _ = (codex, hiddenCards)
        return NotchAgentSupport.showsCodexAccounts() ? accounts.states : []
    }

    /// Only agents that left something on this Mac, or whose accounts were
    /// added, get cards.
    private var providers: [AgentProvider] {
        _ = (claude, codex, opencode, copilot, cursor, antigravity, gemini)
        return NotchAgentSupport.pageProviders(snapshot: usage.snapshot, hasCodexAccounts: !codexAccounts.isEmpty,
                                               hasClaudeAccount: !usage.claudeProfile.isDefault)
    }

    private var tiles: [NotchAgentTile] {
        // The strings are read here so a change in Settings redraws the page.
        _ = (cardOrder, hiddenCards)
        return NotchAgentSupport.tiles(cards: NotchAgentSupport.cards(), providers: providers,
                                       codexAccounts: codexAccounts.map(\.id),
                                       claudeAccount: usage.claudeProfile.isDefault ? nil : usage.claudeProfile.id,
                                       snapshot: usage.snapshot)
    }

    /// Claude's card, tall, with two cards stacked beside it.
    private var lead: NotchAgentSupport.Lead? { NotchAgentSupport.lead(tiles, width: size.width) }

    private var rows: [[NotchAgentTile]] {
        NotchAgentSupport.rows(lead?.rest ?? tiles, width: size.width)
    }

    var body: some View {
        Group {
            if !usage.snapshot.loaded && codexAccounts.isEmpty {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(text.loading).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if providers.isEmpty {
                NotchEmptyView(symbol: "sparkles", message: text.empty)
            } else if rows.isEmpty && lead == nil {
                NotchEmptyView(symbol: "square.grid.2x2", message: text.noCards)
            } else {
                let rows = rows
                let lead = lead
                let content = NotchAgentSupport.contentHeight(rows)
                    + (lead.map { $0.height + (rows.isEmpty ? 0 : NotchAgentSupport.spacing) } ?? 0)
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    if content > size.height + 0.5 {
                        ScrollView { grid(rows, lead: lead, now: context.date) }
                            .scrollIndicators(.automatic)
                    } else {
                        grid(rows, lead: lead, now: context.date)
                    }
                }
                // The period drives several cards, so it sits in the island's
                // top row, beside the camera, while any of them shows.
                .notchBand(leading: {
                    if (rows.joined() + (lead.map { [$0.claude] + $0.stack + $0.rest } ?? [])).contains(where: { $0.card.followsPeriod }) { periodMenu }
                })
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .environment(\.locale, l10n.language.formattingLocale())
        .onAppear {
            usage.pageDidAppear(preview: preview)
            accounts.pageDidAppear(preview: preview)
        }
        .onDisappear {
            guard !preview else { return }
            usage.pageDidDisappear()
            accounts.pageDidDisappear()
        }
    }

    private var periodMenu: some View {
        NotchMenuButton(title: text.period(chosenPeriod), items: AgentPeriod.allCases.map { option in
            NotchMenuItem(title: text.period(option), checked: option == chosenPeriod) { period = option.rawValue }
        }, cornerRadius: 9) {
            NotchBandMenuLabel(title: text.period(chosenPeriod))
        }
    }

    private func grid(_ rows: [[NotchAgentTile]], lead: NotchAgentSupport.Lead?, now: Date) -> some View {
        VStack(spacing: NotchAgentSupport.spacing) {
            if let lead {
                // Claude's card runs the height of the two beside it.
                HStack(alignment: .top, spacing: NotchAgentSupport.spacing) {
                    card(lead.claude, now: now, expanded: true)
                    VStack(spacing: NotchAgentSupport.spacing) {
                        ForEach(lead.stack) { tile in
                            card(tile, now: now).frame(height: NotchAgentSupport.height(of: [tile]))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: lead.height)
            }
            ForEach(rows, id: \.first?.id) { row in
                HStack(spacing: NotchAgentSupport.spacing) {
                    ForEach(row) { tile in card(tile, now: now) }
                    // A card left without a partner keeps its half of the row.
                    if row.count == 1, !(row.first?.card.fullWidth ?? true), size.width >= NotchAgentSupport.pairWidth {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .frame(height: NotchAgentSupport.height(of: row))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder private func card(_ tile: NotchAgentTile, now: Date, expanded: Bool = false) -> some View {
        let snapshot = usage.snapshot
        let shown = chosenPeriod
        switch tile.card {
        case .limits:
            if let provider = tile.provider {
                NotchAgentLimitsCard(provider: provider, snapshot: snapshot, now: now,
                                     display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining, text: text,
                                     account: account(tile, now: now),
                                     accountName: provider == .claude ? claudeAccountName : nil,
                                     expanded: expanded)
            }
        case .spend:
            NotchAgentSpendCard(snapshot: snapshot, providers: providers, period: shown, text: text)
        case .live:
            NotchAgentLiveCard(snapshot: snapshot, providers: providers, text: text)
        case .trend:
            NotchAgentTrendCard(snapshot: snapshot, providers: providers, period: shown, text: text)
        case .models:
            NotchAgentShareCard(title: text.modelsCard, symbol: NotchAgentCard.models.symbol,
                                shares: snapshot.usage(shown).models, byCost: snapshot.usage(shown).fullyPriced, text: text)
        case .projects:
            NotchAgentShareCard(title: text.projectsCard, symbol: NotchAgentCard.projects.symbol,
                                shares: snapshot.usage(shown).projects, byCost: snapshot.usage(shown).fullyPriced, text: text)
        case .activity:
            NotchAgentActivityCard(snapshot: snapshot, providers: providers, text: text)
        case .resets:
            NotchAgentResetsCard(now: now, text: text, showsDefaultAccount: tile.namesDefaultAccount)
        case .kilo:
            NotchAgentKiloCard(period: shown, now: now, text: text)
        }
    }

    private func account(_ tile: NotchAgentTile, now: Date) -> NotchAgentAccount? {
        if tile.provider == .claude, tile.accountID != nil {
            let strings = FeatureStrings.codexAccounts(l10n.language)
            return NotchAgentAccount(name: claudeAccountName, limits: usage.snapshot.limits[.claude],
                plan: usage.snapshot.plans[.claude]?.name, checking: usage.claudeAccountChecking,
                failure: usage.claudeAccountFailure.map(text.claudeCode), refreshHint: strings.refreshHint,
                checkLabel: strings.check, refresh: usage.checkClaudeAccount)
        }
        guard let id = tile.accountID, let state = codexAccounts.first(where: { $0.id == id }) else { return nil }
        let strings = FeatureStrings.codexAccounts(l10n.language)
        let failure = state.failure.map { failure -> String in
            switch failure {
            case .missingCLI: return text.resetsNeedCodex
            case .invalidProfile: return strings.folderProblem
            case .needsSignIn: return strings.signIn
            case .outdated: return strings.update
            case .unavailable, .cancelled: return strings.failed
            }
        }
        return NotchAgentAccount(name: state.profile.name, limits: state.currentLimits(at: now), plan: state.plan,
                                 checking: state.checking, failure: failure, refreshHint: strings.refreshHint,
                                 checkLabel: strings.check) { accounts.refresh(id: id, force: true) }
    }

    private var claudeAccountName: String {
        let name = usage.claudeProfile.name(defaultName: FeatureStrings.claudeAccount(l10n.language).defaultAccount)
        guard let email = usage.claudeAccountIdentity?.email else { return name }
        return usage.claudeProfile.isDefault ? email : name + " · " + email
    }
}

private struct NotchAgentChip: View {
    let text: String
    var tint: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint.opacity(0.9))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(tint.opacity(0.14), in: Capsule(style: .continuous))
    }
}

// MARK: Limits

/// The share keeps its meaning at every width. A reset countdown uses spare
/// room, otherwise its full date remains in the row's tooltip.
private struct NotchAgentLimitReading: View {
    let title: String
    let share: String
    let countdown: String?
    let tint: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                heading.fixedSize()
                if let countdown {
                    Label(countdown, systemImage: "arrow.clockwise")
                        .labelStyle(NotchAgentInlineLabel())
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .accessibilityIdentifier("notch.agentLimitCountdown")
                }
                Spacer(minLength: 2)
                reading
            }
            HStack(spacing: 5) {
                heading.minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                reading
            }
        }
    }

    private var heading: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
    }

    private var reading: some View {
        Text(share)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .fixedSize()
            .contentTransition(.numericText())
            .accessibilityIdentifier("notch.agentLimitShare")
    }
}

/// An explicitly chosen account's card: only its own checks, never the reading the
/// logs give the provider's other account, even when its check failed.
private struct NotchAgentAccount {
    let name: String
    let limits: AgentLimits?
    let plan: String?
    let checking: Bool
    let failure: String?
    let refreshHint: String
    let checkLabel: String
    let refresh: () -> Void
}

private struct NotchAgentLimitsCard: View {
    let provider: AgentProvider
    let snapshot: AgentUsageSnapshot
    let now: Date
    let display: NotchAgentLimitDisplay
    let text: NotchAgentStrings
    var account: NotchAgentAccount? = nil
    var accountName: String? = nil
    /// Claude's tall card: its status line's details under the limits.
    var expanded = false
    @ObservedObject private var service = AgentUsageService.shared
    @Environment(\.locale) private var locale

    private var limits: AgentLimits? {
        guard let account else { return snapshot.limits[provider] }
        return account.limits
    }

    /// A reading from a while ago: still the latest known, shown quieter
    /// until it is checked again.
    private var stale: Bool {
        NotchAgentSupport.limitsAreStale(limits, provider: provider, account: account != nil, now: now)
    }

    /// Two rows fit: the session and whichever longer window binds first.
    private var windows: [AgentLimitWindow] {
        let all = (limits?.windows ?? []).map { AgentLimitSupport.current($0, at: now) }
        let session = all.filter { $0.kind == .session }.max { $0.usedPercent < $1.usedPercent }
        if session == nil, provider == .antigravity, !all.contains(where: { $0.kind == .weekly }) {
            return Array(all.sorted {
                $0.usedPercent != $1.usedPercent ? $0.usedPercent > $1.usedPercent : $0.id < $1.id
            }.prefix(2))
        }
        let longer = all.filter { $0.kind != .session }.max { $0.usedPercent < $1.usedPercent }
        return [session, longer].compactMap { $0 }
    }

    var body: some View {
        let windows = windows
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: (account?.name ?? accountName).map { provider.displayName + " · " + $0 }
                                        ?? provider.displayName,
                                     symbol: provider.symbol, tint: provider.tint, provider: provider) {
                    HStack(spacing: 4) {
                        if let account {
                            if let plan = account.plan { NotchAgentChip(text: plan, tint: provider.tint) }
                            // A check waiting its turn shows as one under way.
                            if account.checking {
                                ProgressView().controlSize(.mini).scaleEffect(0.65).frame(width: 12, height: 12)
                            } else {
                                Button(action: account.refresh) {
                                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                                .help(account.checkLabel)
                                .accessibilityLabel(account.checkLabel)
                            }
                        } else {
                            if let plan = snapshot.plans[provider] { NotchAgentChip(text: plan.name, tint: provider.tint) }
                            if !snapshot.working(provider).isEmpty { NotchAgentPulse(tint: provider.tint, size: 5) }
                        }
                    }
                }
                .help(account?.name ?? accountName ?? provider.displayName)
                if let account {
                    let notes = NotchAgentSupport.accountNotes(
                        hasWindows: !windows.isEmpty, checking: account.checking, failure: account.failure,
                        hint: account.refreshHint, loading: text.loading,
                        updated: limits.map { text.updated($0.observedAt.formatted(
                            .relative(presentation: .named, unitsStyle: .abbreviated).locale(locale))) })
                    if let placeholder = notes.placeholder {
                        Text(placeholder).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if !windows.isEmpty { meters(windows) }
                    // What went wrong since the reading shown, or how old it is.
                    if let note = notes.caption {
                        Text(note)
                            .font(.system(size: 8.5))
                            .foregroundStyle(account.failure == nil && !stale ? Color.secondary : Color.orange)
                            .lineLimit(1)
                    }
                } else if windows.isEmpty {
                    estimate
                } else {
                    meters(windows)
                    if windows.count == 1 { caption }
                }
                if expanded, provider == .claude, account == nil {
                    Divider().overlay(.white.opacity(0.12))
                    NotchAgentClaudeStatus(now: now)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func meters(_ windows: [AgentLimitWindow]) -> some View {
        VStack(spacing: 5) {
            ForEach(windows) { row($0) }
        }
        .opacity(stale ? 0.6 : 1)
    }

    /// How old a reading is, once it is old enough to have missed use elsewhere.
    @ViewBuilder private var caption: some View {
        if let observed = limits?.observedAt, now.timeIntervalSince(observed) > 600 {
            Text(text.updated(observed.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)
                .locale(locale))))
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    /// A usage-based forecast would read as a promise, so a row says only
    /// what is left or used, as chosen, and when the window renews.
    private func row(_ window: AgentLimitWindow) -> some View {
        let pace = AgentLimitSupport.pace(for: window, now: now)
        let tint = agentLimitTint(provider, usedFraction: window.usedFraction)
        let remaining = display == .remaining
        let fraction = remaining ? window.remainingFraction : window.usedFraction
        let reset = AgentLimitSupport.displayedReset(window, now: now).map {
            (window.estimatedResetsAt == nil ? "" : "≈ ") + countdown(to: $0)
        }
        return VStack(alignment: .leading, spacing: 2) {
            NotchAgentLimitReading(title: label(window),
                                  share: NotchAgentSupport.limitShare(window, display: display, text: text),
                                  countdown: reset, tint: tint == provider.tint ? Color.white : tint)
            NotchAgentMeter(value: fraction, pace: pace.map { remaining ? 1 - $0.elapsed : $0.elapsed },
                            tint: tint, height: 4)
        }
        .help(help(window))
    }

    /// What the window covers: its length, or the model it is kept for.
    private func label(_ window: AgentLimitWindow) -> String {
        switch window.kind {
        case .session: return window.scope.map { "\(text.session) · \($0)" } ?? text.session
        case .weekly: return window.scope.map { "\(text.weekly) · \($0)" } ?? text.weekly
        case .other:
            guard let minutes = window.minutes else { return window.scope ?? text.readoutLimit }
            let length = AgentFormat.duration(TimeInterval(minutes) * 60, locale: locale, units: 1)
            return window.scope.map { "\(length) · \($0)" } ?? length
        }
    }

    /// How long until the window renews: days and hours, or hours and
    /// minutes, never seconds on a card that redraws every few. The day and
    /// time are in the tooltip.
    private func countdown(to date: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        return AgentFormat.duration(max(60, seconds), locale: locale, units: seconds >= 3600 ? 2 : 1)
    }

    private func help(_ window: AgentLimitWindow) -> String {
        var parts = [label(window), text.usedShare(AgentFormat.percent(window.usedFraction)),
                     text.left(AgentFormat.percent(window.remainingFraction))]
        if let resets = AgentLimitSupport.displayedReset(window, now: now) {
            parts.append(resets.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))
            if window.estimatedResetsAt != nil { parts.append(text.estimated) }
        }
        if let observed = limits?.observedAt, now.timeIntervalSince(observed) > 600 {
            parts.append(text.updated(observed.formatted(.relative(presentation: .named).locale(locale))))
        }
        return parts.joined(separator: " · ")
    }

    /// Without a recent reading from the Claude app, the session still ends
    /// five hours after its first request, so the window itself is known.
    @ViewBuilder private var estimate: some View {
        if provider == .claude, let block = snapshot.claudeBlock {
            let length = block.end.timeIntervalSince(block.start)
            let amount = AgentFormat.cost(block.totals)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(text.session)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Label(countdown(to: block.end), systemImage: "arrow.clockwise")
                        .labelStyle(NotchAgentInlineLabel())
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Text(amount)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .accessibilityLabel(text.costDescription(amount, partial: block.totals.hasPartialCost))
                }
                NotchAgentMeter(value: length > 0 ? now.timeIntervalSince(block.start) / length : 0,
                                tint: provider.tint, height: 4, dimmed: true)
            }
            .help(text.costDescription(text.estimated, partial: block.totals.hasPartialCost))
            setUpLimits
        } else if provider == .claude {
            Text(text.noSession).font(.system(size: 10.5)).foregroundStyle(.secondary)
            setUpLimits
        } else if provider == .opencode {
            let todayUsage = snapshot.usage(.today).byProvider[.opencode]
            if let todayUsage, todayUsage.tokens.total > 0 || todayUsage.requests > 0 || todayUsage.cost > 0 {
                todaySummary(todayUsage)
            } else {
                Text(text.noSession).font(.system(size: 10.5)).foregroundStyle(.secondary)
                lastUsed
            }
        } else if provider == .antigravity {
            if let todayUsage = snapshot.usage(.today).byProvider[.antigravity] {
                if todayUsage.tokens.total > 0 {
                    todaySummary(todayUsage)
                } else {
                    setUpLimits
                    lastUsed
                }
            } else if service.antigravityAccountFailure != nil {
                setUpLimits
                lastUsed
            } else {
                Text(text.waitingForLimits).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
                lastUsed
            }
        } else {
            Text(text.waitingForLimits).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
            lastUsed
        }
    }

    private func todaySummary(_ todayUsage: AgentTotals) -> some View {
        let costText: String = {
            if todayUsage.unpriced > 0 {
                return todayUsage.cost > 0 ? "≥ " + AgentFormat.cost(todayUsage.cost) : "—"
            }
            return AgentFormat.cost(todayUsage.cost)
        }()
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(text.period(.today))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 2)
                Text(costText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .help(todayUsage.unpriced > 0 ? text.unpriced : text.valueNote)
            HStack(spacing: 4) {
                Text(AgentFormat.tokens(todayUsage.tokens.total))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                if let rate = todayUsage.tokens.cacheHitRate, rate > 0 {
                    Text("· " + text.cached(AgentFormat.percent(rate)))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                lastUsed
            }
        }
    }

    /// Claude's plan limits come from Claude Code or the Claude app; the
    /// settings say how, and why Claude Code could not check.
    private var setUpLimits: some View {
        Button {
            NotchService.shared.openSettings(showing: .agents)
        } label: {
            Label(text.claudeLimitsHint, systemImage: "arrow.up.forward")
                .labelStyle(NotchAgentInlineLabel())
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(provider.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var lastUsed: some View {
        if let last = snapshot.lastActivity[provider] {
            Text(last.formatted(.relative(presentation: .named, unitsStyle: .abbreviated).locale(locale)))
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
    }
}

/// A glyph and its words, closer together than a stock label.
private struct NotchAgentInlineLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

// MARK: Spending

/// The period it covers is chosen in the island's top row, which the trend,
/// models and projects follow too; the plan multiples take its place here.
private struct NotchAgentSpendCard: View {
    let snapshot: AgentUsageSnapshot
    let providers: [AgentProvider]
    let period: AgentPeriod
    let text: NotchAgentStrings

    var body: some View {
        let usage = snapshot.usage(period)
        let partial = snapshot.hasPartialCost(period)
        let amount = AgentFormat.cost(snapshot, for: period)
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 5) {
                NotchAgentCardHeader(title: text.spendCard, symbol: NotchAgentCard.spend.symbol) {
                    if period == .month { multiples(usage) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(amount)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(text.apiValue)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text.apiValue)
                .accessibilityValue(text.costDescription(amount, partial: partial))
                .help(partial ? text.partialCostNote : text.valueNote)
                split(usage)
                Text(footer(usage))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .help(text.saved(AgentFormat.cost(usage.total.savings)))
            }
        }
    }

    /// Thirty days of API value against a plan's monthly price.
    @ViewBuilder private func multiples(_ usage: AgentPeriodUsage) -> some View {
        HStack(spacing: 3) {
            ForEach(providers) { provider in
                if let plan = snapshot.plans[provider], let price = plan.monthlyPrice, price > 0,
                   let totals = usage.byProvider[provider], !totals.hasPartialCost, totals.cost > 0 {
                    let ratio = totals.cost / price
                    let multiple = ratio.formatted(.number.precision(.fractionLength(ratio < 10 ? 1 : 0))) + "×"
                    NotchAgentChip(text: multiple, tint: provider.tint)
                        .help(text.planMultiple(multiple, plan: "\(provider.displayName) \(plan.name)"))
                }
            }
        }
    }

    @ViewBuilder private func split(_ usage: AgentPeriodUsage) -> some View {
        let byCost = usage.fullyPriced
        let parts = providers.map { usage.byProvider[$0]?.weight(byCost: byCost) ?? 0 }
        let total = parts.reduce(0, +)
        let shown = parts.filter { $0 > 0 }.count
        GeometryReader { proxy in
            let gap: CGFloat = 2
            // Every agent keeps a visible sliver; the rest shares what is left.
            let room = max(0, proxy.size.width - gap * CGFloat(max(0, shown - 1)) - 4 * CGFloat(shown))
            HStack(spacing: gap) {
                if total <= 0 {
                    Capsule().fill(.white.opacity(0.13))
                } else {
                    ForEach(providers.indices, id: \.self) { index in
                        if parts[index] > 0 {
                            Capsule(style: .continuous).fill(providers[index].tint.opacity(0.9))
                                .frame(width: 4 + room * parts[index] / total)
                        }
                    }
                }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private func footer(_ usage: AgentPeriodUsage) -> String {
        var parts = [text.tokens(AgentFormat.tokens(usage.total.tokens.total))]
        if let rate = usage.total.tokens.cacheHitRate, rate > 0 { parts.append(text.cached(AgentFormat.percent(rate))) }
        return parts.joined(separator: " · ")
    }
}

// MARK: Now

private struct NotchAgentLiveCard: View {
    let snapshot: AgentUsageSnapshot
    let providers: [AgentProvider]
    let text: NotchAgentStrings
    @Environment(\.locale) private var locale

    var body: some View {
        let live = snapshot.live.filter { providers.contains($0.provider) }
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 7) {
                NotchAgentCardHeader(title: text.liveCard, symbol: NotchAgentCard.live.symbol,
                                     tint: live.first?.provider.tint ?? .secondary) {
                    HStack(spacing: 4) {
                        if live.count > 2 { NotchAgentChip(text: "+\(live.count - 2)") }
                        if let first = live.first { NotchAgentPulse(tint: first.provider.tint, size: 5) }
                    }
                }
                if live.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(providers) { idleRow($0) }
                    }
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(live.prefix(2)) { row($0, now: context.date) }
                        }
                    }
                }
            }
        }
    }

    private func row(_ session: AgentLiveSession, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                NotchAgentGlyph(provider: session.provider, size: 9)
                Text(session.project.isEmpty ? session.provider.displayName : session.project)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(AgentFormat.clock(now.timeIntervalSince(session.started)))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(session.provider.tint)
            }
            // Tokens the agent wrote, as its own window counts them; every
            // call also reads the whole context again, which the tooltip and
            // the cost include.
            if session.provider != .cursor {
                Text([AgentPricing.displayName(session.model),
                      session.tokens.output > 0 ? text.written(AgentFormat.tokens(session.tokens.output)) : "",
                      session.cost > 0 ? AgentFormat.cost(session.cost) : ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help(session.provider == .cursor ? session.provider.displayName : text.tokens(AgentFormat.tokens(session.tokens.total)) + " · "
              + text.cached(AgentFormat.percent(session.tokens.cacheHitRate ?? 0)))
    }

    private func idleRow(_ provider: AgentProvider) -> some View {
        HStack(spacing: 5) {
            NotchAgentGlyph(provider: provider, size: 9, working: false)
            Text(provider.displayName).font(.system(size: 10.5, weight: .medium))
            Spacer(minLength: 4)
            Text(snapshot.lastActivity[provider].map {
                $0.formatted(.relative(presentation: .named, unitsStyle: .abbreviated).locale(locale))
            } ?? text.idle)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: Trend

private struct NotchAgentTrendCard: View {
    let base: AgentUsageSnapshot
    let allProviders: [AgentProvider]
    let period: AgentPeriod
    let text: NotchAgentStrings
    @State private var hovered: Date?
    @State private var lensPage = 0
    @ObservedObject private var kilo = AgentKiloService.shared
    @Environment(\.locale) private var locale

    private var lenses: [NotchAgentLens] {
        NotchAgentLens.available(snapshot: base, providers: allProviders, kiloDays: kilo.days)
    }
    private var lens: NotchAgentLens { lenses.indices.contains(lensPage) ? lenses[lensPage] : .all }
    private var snapshot: AgentUsageSnapshot { lens.snapshot(from: base, kiloDays: kilo.days, kiloHours: kilo.hours) }
    private var providers: [AgentProvider] { lens.providers(all: allProviders) }

    init(snapshot: AgentUsageSnapshot, providers: [AgentProvider], period: AgentPeriod, text: NotchAgentStrings,
         hovered: Date? = nil) {
        base = snapshot
        allProviders = providers
        self.period = period
        self.text = text
        _hovered = State(initialValue: hovered)
    }

    private var buckets: [AgentBucket] {
        period == .today ? snapshot.hours : Array(snapshot.days.suffix(period.days))
    }

    var body: some View {
        let byCost = snapshot.usage(period).fullyPriced
        let caption = self.caption(byCost: byCost)
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: lens.name(kilo: text.kiloCard).map { text.trendCard + " · " + $0 } ?? text.trendCard,
                                     symbol: NotchAgentCard.trend.symbol) {
                    NotchAgentLensDots(count: lenses.count, current: lensPage)
                    Text(caption.reading)
                        .font(.system(size: 9.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel(text.costDescription(caption.reading, partial: caption.partial))
                }
                NotchAgentBars(buckets: buckets, providers: providers, byCost: byCost, hovered: $hovered, tint: lens.tint)
                axis
            }
        }
        .background(NotchAgentSwipe { move in swipe(move) })
        .onAppear { kilo.refreshIfStale(period: period) }
    }

    private func swipe(_ move: Int) {
        let count = lenses.count
        guard count > 1 else { return }
        withAnimation(.smooth(duration: 0.25)) { lensPage = (lensPage - move + count) % count }
    }

    private func caption(byCost: Bool) -> (reading: String, partial: Bool) {
        let buckets = self.buckets
        if let hovered, let bucket = buckets.first(where: { $0.start == hovered }) {
            // A pointed-at bar reads its tokens beside its cost.
            let total = bucket.total
            let partial = byCost && snapshot.hasPartialCost(total, byProvider: bucket.byProvider)
            let tokens = text.tokens(AgentFormat.tokens(total.tokens.total))
            let value = byCost ? AgentFormat.cost(total.cost, partial: partial) + " · " + tokens : tokens
            return (label(bucket.start, long: true) + " · " + value, partial)
        }
        let total = snapshot.usage(period).total
        let partial = byCost && snapshot.hasPartialCost(period)
        let value = byCost ? AgentFormat.cost(total.cost, partial: partial)
            : text.tokens(AgentFormat.tokens(total.tokens.total))
        return (text.period(period) + " · " + value, partial)
    }

    private func label(_ date: Date, long: Bool) -> String {
        if period == .today { return date.formatted(.dateTime.hour().locale(locale)) }
        if period == .week, !long { return date.formatted(.dateTime.weekday(.narrow).locale(locale)) }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    /// Every bar a letter over a week; the ends and the middle otherwise.
    private var axis: some View {
        let marks: [Int] = period == .week ? Array(buckets.indices)
            : buckets.isEmpty ? [] : [0, buckets.count / 2, buckets.count - 1]
        return HStack(spacing: 0) {
            if period == .week {
                ForEach(marks, id: \.self) { index in
                    Text(label(buckets[index].start, long: false)).frame(maxWidth: .infinity)
                }
            } else {
                ForEach(Array(marks.enumerated()), id: \.offset) { position, index in
                    if position > 0 { Spacer(minLength: 4) }
                    Text(label(buckets[index].start, long: false))
                }
            }
        }
        .font(.system(size: 8.5, weight: .medium))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .frame(height: 10)
    }
}

// MARK: Models and projects

private struct NotchAgentShareCard: View {
    let title: String
    let symbol: String
    let shares: [AgentShare]
    let byCost: Bool
    let text: NotchAgentStrings

    var body: some View {
        let shown = Array(shares.prefix(3))
        let peak = max(shown.map { $0.totals.weight(byCost: byCost) }.max() ?? 0, .leastNonzeroMagnitude)
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: title, symbol: symbol)
                if shown.isEmpty {
                    Text(text.noActivity).font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 5) {
                        ForEach(shown) { share in row(share, peak: peak) }
                    }
                }
            }
        }
    }

    private func row(_ share: AgentShare, peak: Double) -> some View {
        let weight = share.totals.weight(byCost: byCost)
        let tint = share.provider?.tint ?? .white
        let tokens = AgentFormat.tokens(share.totals.tokens.total)
        let amount = AgentFormat.cost(share.totals)
        let reading = text.costDescription([share.name, text.tokens(tokens), amount].joined(separator: " · "),
                                           partial: share.totals.hasPartialCost)
        return HStack(spacing: 6) {
            Text(share.name)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Capsule(style: .continuous)
                .fill(tint.opacity(0.85))
                .frame(width: max(3, 44 * weight / peak), height: 4)
                .frame(width: 44, alignment: .leading)
            Text(byCost ? amount : tokens)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .frame(height: 14)
        .accessibilityRepresentation { Text(verbatim: reading) }
        .help(reading)
    }
}

// MARK: Activity

private struct NotchAgentActivityCard: View {
    let base: AgentUsageSnapshot
    let allProviders: [AgentProvider]
    let text: NotchAgentStrings
    @State private var hovered: Date?
    @State private var lensPage = 0
    @ObservedObject private var kilo = AgentKiloService.shared
    @Environment(\.locale) private var locale

    private var lenses: [NotchAgentLens] {
        NotchAgentLens.available(snapshot: base, providers: allProviders, kiloDays: kilo.days)
    }
    private var lens: NotchAgentLens { lenses.indices.contains(lensPage) ? lenses[lensPage] : .all }
    private var snapshot: AgentUsageSnapshot { lens.snapshot(from: base, kiloDays: kilo.days, kiloHours: kilo.hours) }

    init(snapshot: AgentUsageSnapshot, providers: [AgentProvider] = [], text: NotchAgentStrings, hovered: Date? = nil) {
        base = snapshot
        allProviders = providers
        self.text = text
        _hovered = State(initialValue: hovered)
    }

    private func swipe(_ move: Int) {
        let count = lenses.count
        guard count > 1 else { return }
        withAnimation(.smooth(duration: 0.25)) { lensPage = (lensPage - move + count) % count }
    }

    private func hasActivity(_ day: AgentBucket) -> Bool {
        day.observedCursorActivity || day.byProvider.values.contains { $0.requests > 0 }
    }

    /// Days in a row with any use, counting today only once it has some.
    private var streak: Int {
        var count = 0
        for day in snapshot.days.reversed() {
            if hasActivity(day) { count += 1 }
            else if count > 0 || day.id != snapshot.days.last?.id { break }
        }
        return count
    }

    var body: some View {
        let total = snapshot.historyTotal
        let byCost = total.unpriced == 0
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: lens.name(kilo: text.kiloCard).map { text.activityCard + " · " + $0 } ?? text.activityCard,
                                     symbol: NotchAgentCard.activity.symbol) {
                    NotchAgentLensDots(count: lenses.count, current: lensPage)
                    if streak > 1 {
                        Label("\(streak)", systemImage: "flame.fill")
                            .labelStyle(NotchAgentInlineLabel())
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.orange)
                            .help(text.streak)
                            .accessibilityLabel(text.streak)
                            .accessibilityValue("\(streak)")
                    }
                }
                GeometryReader { proxy in
                    let map = NotchAgentHeatmap.width(height: proxy.size.height, days: snapshot.days)
                    HStack(alignment: .top, spacing: 14) {
                        NotchAgentHeatmap(days: snapshot.days, byCost: byCost, hovered: $hovered, tint: lens.tint ?? .white)
                            .frame(width: map, height: proxy.size.height)
                        figures(total: total, byCost: byCost)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
        .background(NotchAgentSwipe { move in swipe(move) })
        .onAppear { kilo.refreshIfStale(period: .month) }
    }

    /// The total for the whole map, its active days and its busiest day; a
    /// hovered day takes the place of the busiest one.
    private func figures(total: AgentTotals, byCost: Bool) -> some View {
        let activeDays = snapshot.days.lazy.filter(hasActivity).count
        let busiest = snapshot.days.lazy.filter { $0.total.requests > 0 }
            .max { $0.total.weight(byCost: byCost) < $1.total.weight(byCost: byCost) }
        let pointed = hovered.flatMap { date in snapshot.days.first { $0.start == date } }
        let partial = byCost && total.hasPartialCost
        let amount = value(total, byCost: byCost, partial: partial)
        return VStack(alignment: .leading, spacing: 2) {
            Text(amount)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel(text.costDescription(amount, partial: partial))
            Text(AgentFormat.span(days: snapshot.days.count, locale: locale))
                .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            figure(text.activeDays, "\(activeDays)")
            if let day = pointed ?? busiest {
                let dayPartial = byCost && day.total.hasPartialCost
                let date = day.start.formatted(.dateTime.day().month(.abbreviated).locale(locale))
                figure(pointed == nil ? text.busiestDay : day.start.formatted(.dateTime.weekday(.wide).locale(locale)),
                       date + " · " + value(day.total, byCost: byCost, partial: dayPartial), partial: dayPartial)
            }
        }
    }

    private func figure(_ label: String, _ value: String, partial: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Text(value).monospacedDigit().lineLimit(1)
                .accessibilityLabel(text.costDescription(value, partial: partial))
        }
        .font(.system(size: 10, weight: .medium))
        .minimumScaleFactor(0.85)
    }

    private func value(_ totals: AgentTotals, byCost: Bool, partial: Bool) -> String {
        byCost ? AgentFormat.cost(totals.cost, partial: partial) : AgentFormat.tokens(totals.tokens.total)
    }
}

// MARK: Kilo Code

/// Kilo Code's sessions, tokens, prompts and recency for the chosen period, from
/// its own database. Kilo keeps a session's totals on the session, so a
/// session still open when the period began counts whole.
private struct NotchAgentKiloCard: View {
    let period: AgentPeriod
    let now: Date
    let text: NotchAgentStrings
    @ObservedObject private var kilo = AgentKiloService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.locale) private var locale
    private var labels: KiloCardStrings { KiloCardStrings.localized(l10n.language) }

    static let tint = Color(red: 0.98, green: 0.84, blue: 0.22)
    /// Kilo writes to its database as it works, so a change this recent means it is running.
    static let activeWindow: TimeInterval = 120

    private var active: Bool {
        guard let last = kilo.summary?.lastUsed else { return false }
        return now.timeIntervalSince(last) < Self.activeWindow
    }

    var body: some View {
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 5) {
                NotchAgentCardHeader(title: text.kiloCard, symbol: NotchAgentCard.kilo.symbol, tint: Self.tint) {
                    if active {
                        Circle().fill(.green).frame(width: 6, height: 6)
                            .shadow(color: .green.opacity(0.7), radius: 3)
                            .help(labels.activeNow)
                    }
                    if let summary = kilo.summary, summary.sessions > 0 {
                        NotchAgentChip(text: summary.sessions.formatted(.number.locale(locale)), tint: Self.tint)
                            .help(text.kiloSessions)
                    } else if kilo.summary == nil {
                        ProgressView().controlSize(.mini)
                    }
                }
                content
            }
        }
        .help(text.kiloHelp)
        .onAppear { kilo.refreshIfStale(period: period, now: now) }
        .onChange(of: period) { _, next in kilo.refreshIfStale(period: next) }
        .onChange(of: now) { _, next in kilo.refreshIfStale(period: period, now: next) }
    }

    @ViewBuilder private var content: some View {
        if let summary = kilo.summary {
            if !summary.installed {
                line(text.kiloNotInstalled)
            } else if summary.sessions == 0 && summary.tokens == 0 {
                line(text.kiloEmpty)
                if !summary.signedIn { line(text.kiloSignedOut, symbol: "person.crop.circle.badge.exclamationmark") }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(AgentFormat.tokens(summary.tokens, locale: locale))
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(labels.tokens)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let share = summary.cacheShare {
                        Text("\(AgentFormat.percent(share, locale: locale)) \(labels.cache)")
                            .font(.system(size: 9.5, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Self.tint.opacity(0.9))
                            .lineLimit(1)
                    }
                }
                figures([(labels.input, AgentFormat.tokens(summary.input, locale: locale)),
                         (labels.output, AgentFormat.tokens(summary.output, locale: locale))])
                figures([(labels.prompts, summary.prompts.formatted(.number.locale(locale))),
                         (labels.steps, summary.steps.formatted(.number.locale(locale)))]
                        + (summary.linesAdded + summary.linesRemoved > 0
                           ? [("", "+\(summary.linesAdded) −\(summary.linesRemoved)")] : []))
                if active {
                    line(labels.activeNow, symbol: "bolt.fill")
                } else if let last = summary.lastUsed {
                    line(labels.used(last.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)
                                                        .locale(locale))), symbol: "clock")
                } else if !summary.signedIn {
                    line(text.kiloSignedOut, symbol: "person.crop.circle.badge.exclamationmark")
                }
            }
        }
    }

    private func line(_ message: String, symbol: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9)) }
            Text(message).lineLimit(1).minimumScaleFactor(0.85)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    /// Label–figure pairs on one line, as Claude's card shows its In and Out.
    private func figures(_ pairs: [(String, String)]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if !pair.0.isEmpty { Text(pair.0).foregroundStyle(.secondary) }
                    Text(pair.1).monospacedDigit().contentTransition(.numericText())
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}

// MARK: Resets

/// Codex's banked resets: how many the account holds, when the next one
/// expires, and a use that asks first. Cancel takes the place of the button
/// that asked, so a double click never spends one.
private struct NotchAgentResetsCard: View {
    let now: Date
    let text: NotchAgentStrings
    /// Beside added Codex accounts, says which one its resets belong to.
    var showsDefaultAccount = false
    @ObservedObject private var resets = AgentCodexResetService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var confirming = false
    @Environment(\.locale) private var locale

    private let tint = AgentProvider.codex.tint

    /// What a use did stays on the card for a minute.
    private var finished: AgentCodexResetService.Finished? {
        resets.finished.flatMap { now.timeIntervalSince($0.date) < 60 ? $0 : nil }
    }

    var body: some View {
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: text.resetsCard, symbol: NotchAgentCard.resets.symbol, tint: tint,
                                     provider: .codex) {
                    if let summary = resets.summary, summary.available > 0 {
                        NotchAgentChip(text: summary.available.formatted(.number.locale(locale)), tint: tint)
                    } else if resets.checking {
                        ProgressView().controlSize(.mini)
                    }
                }
                if showsDefaultAccount {
                    Text("Codex · " + FeatureStrings.codexAccounts(l10n.language).defaultAccount)
                        .font(.system(size: 8.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                content
            }
        }
        .help(text.resetsHelp)
        .onAppear { resets.refreshIfStale() }
        // A count that changed while the question was open asks again.
        .onChange(of: resets.summary?.available) { _, _ in confirming = false }
    }

    @ViewBuilder private var content: some View {
        if resets.redeeming {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                line(text.resetting)
            }
        } else if confirming, let summary = resets.summary, summary.available > 0 {
            action(text.resetConfirm, emphasized: true) {
                pill(FeatureStrings.clipboard(l10n.language).cancel, prominent: false) { confirming = false }
                pill(text.confirmReset) {
                    confirming = false
                    resets.redeem()
                }
            }
        } else if let finished {
            if finished.outcome == nil, let summary = resets.summary, summary.available > 0 {
                // Trying again repeats the same use, which never spends a second reset.
                VStack(alignment: .leading, spacing: 0) {
                    outcome(nil)
                    Spacer(minLength: 4)
                    useButton
                }
            } else {
                outcome(finished.outcome)
            }
        } else if resets.summary == nil, let failure = resets.failure {
            action(message(failure)) {
                pill(FeatureStrings.notchMusicExtras(l10n.language).retry, prominent: false) {
                    resets.refresh(searchingShell: failure == .missing)
                }
            }
        } else if let summary = resets.summary {
            if summary.available > 0 {
                // A reset a day from expiring is worth using soon.
                let soon = summary.nextExpiry.map { $0.timeIntervalSince(now) < 86_400 } ?? false
                action(summary.nextExpiry.map(expiry) ?? "", tint: soon ? .orange : nil) { useButton }
            } else {
                line(text.resetsNone)
            }
        }
    }

    private var useButton: some View {
        pill(text.useReset, symbol: "arrow.counterclockwise") { confirming = true }
    }

    /// A line above the card's buttons, which keep to its bottom edge.
    private func action<Buttons: View>(_ message: String, emphasized: Bool = false, tint: Color? = nil,
                                       @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 10.5, weight: emphasized ? .medium : .regular))
                    .foregroundStyle(tint.map { AnyShapeStyle($0) }
                                     ?? (emphasized ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary)))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) { buttons() }
        }
    }

    private func expiry(_ date: Date) -> String {
        text.resetsExpiry(date.formatted(.relative(presentation: .named).locale(locale)))
    }

    @ViewBuilder private func outcome(_ outcome: AgentCodexServer.Outcome?) -> some View {
        switch outcome {
        case .reset?:
            line(text.resetDone, symbol: "checkmark.circle.fill", tint: .green)
        case .nothingToReset?:
            line(text.resetNotNeeded, symbol: "info.circle.fill", tint: .secondary)
        case .alreadyRedeemed?:
            line(text.resetTaken, symbol: "info.circle.fill", tint: .secondary)
        case .noCredit?:
            line(text.resetsNone)
        case nil:
            line(text.resetFailed, symbol: "exclamationmark.circle.fill", tint: .orange)
        }
    }

    private func message(_ failure: AgentCodexServer.Failure) -> String {
        switch failure {
        case .missing: return text.resetsNeedCodex
        case .needsSignIn: return text.resetsSignIn
        case .outdated: return text.resetsUpdate
        case .unreachable, .refused: return text.resetsCheckFailed
        }
    }

    private func line(_ message: String, symbol: String? = nil, tint: Color = .secondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let symbol { Image(systemName: symbol).foregroundStyle(tint) }
            Text(message).foregroundStyle(symbol == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white.opacity(0.9)))
        }
        .font(.system(size: 10.5, weight: .medium))
        .lineLimit(2)
        .minimumScaleFactor(0.85)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func pill(_ title: String, symbol: String? = nil, prominent: Bool = true,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                // A narrow island shrinks a long label before cutting it.
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(.white.opacity(0.85)))
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(prominent ? tint.opacity(0.2) : .white.opacity(0.1), in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 10))
    }
}


// MARK: Claude's status line

/// The details Claude Code gives its status line, under the limits on
/// Claude's tall card: the model and branch, how full the context is, what the
/// session has used and cost, and what it changed.
private struct NotchAgentClaudeStatus: View {
    let now: Date
    @Environment(\.locale) private var locale

    var body: some View {
        if let status = ClaudeStatus.latest(now: now) {
            let stale = now.timeIntervalSince(status.observedAt) > 900
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    if let model = status.model { NotchAgentChip(text: model, tint: AgentProvider.claude.tint) }
                    if let branch = status.branch { NotchAgentChip(text: "⎇ " + branch) }
                    if let style = status.outputStyle { NotchAgentChip(text: style) }
                    if let agent = status.agent { NotchAgentChip(text: agent) }
                    Spacer(minLength: 0)
                    if let version = status.version {
                        Text("v" + version).font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
                if let percent = status.contextPercent {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("Context").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                            Spacer(minLength: 2)
                            Text(Int(percent.rounded()).formatted() + "%" + (status.contextSize.map { " of " + Self.tokens($0) } ?? ""))
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(percent >= 80 ? .red : percent >= 50 ? .yellow : .green)
                        }
                        NotchAgentMeter(value: min(1, max(0, percent / 100)), pace: nil,
                                        tint: percent >= 80 ? .red : percent >= 50 ? .yellow : .green, height: 4)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8, alignment: .leading),
                                    GridItem(.flexible(), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 2) {
                    ForEach(stats(status), id: \.0) { stat in
                        HStack(spacing: 4) {
                            Text(stat.0).foregroundStyle(.secondary)
                            Text(stat.1).foregroundStyle(.white.opacity(0.9)).monospacedDigit()
                        }
                        .font(.system(size: 9.5)).lineLimit(1)
                    }
                }
                if stale {
                    Text("Updated " + status.observedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated).locale(locale)))
                        .font(.system(size: 8.5)).foregroundStyle(.orange)
                }
            }
            .opacity(stale ? 0.65 : 1)
        } else {
            Text("Run Claude Code to see its model, context, cost and session details here.")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3)
        }
    }

    private func stats(_ status: ClaudeStatus) -> [(String, String)] {
        var items: [(String, String)] = []
        if let input = status.tokensIn { items.append(("In", Self.tokens(input))) }
        if let output = status.tokensOut { items.append(("Out", Self.tokens(output))) }
        if let cache = status.cacheRead, cache > 0 { items.append(("Cache", Self.tokens(cache))) }
        if let cost = status.cost { items.append(("Cost", AgentFormat.cost(cost, locale: locale))) }
        if let wall = status.wallMilliseconds {
            items.append(("Time", AgentFormat.duration(TimeInterval(wall) / 1000, locale: locale, units: 2)))
        }
        if let added = status.linesAdded, let removed = status.linesRemoved { items.append(("Lines", "+\(added) −\(removed)")) }
        return items
    }

    private static func tokens(_ value: Int) -> String {
        value >= 1_000_000 ? String(format: "%.1fM", locale: .current, Double(value) / 1e6)
            : value >= 1_000 ? String(format: "%.1fk", locale: .current, Double(value) / 1e3) : String(value)
    }
}
