// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The AI page: cards the person picked, paired across the strip.
struct NotchAgentsView: View {
    let size: CGSize
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsPeriod) private var period = AgentPeriod.today.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsCardOrder) private var cardOrder = ""
    @AppStorage(DefaultsKey.notchAgentsHiddenCards) private var hiddenCards = ""
    @AppStorage(DefaultsKey.notchAgentsClaude) private var claude = true
    @AppStorage(DefaultsKey.notchAgentsCodex) private var codex = true
    @AppStorage(DefaultsKey.notchAgentsOpenCode) private var opencode = true
    @AppStorage(DefaultsKey.notchAgentsCopilot) private var copilot = true
    @AppStorage(DefaultsKey.notchAgentsCursor) private var cursor = true
    /// Nil shows every enabled assistant together. A provider filters the page to that one.
    @State private var focus: AgentProvider?

    private var text: NotchAgentStrings { FeatureStrings.notchAgents(l10n.language) }
    private var chosenPeriod: AgentPeriod { AgentPeriod(rawValue: period) ?? .today }

    /// Assistants turned on in Settings, in a stable order.
    private var enabledProviders: [AgentProvider] {
        [claude ? AgentProvider.claude : nil, codex ? .codex : nil, opencode ? .opencode : nil,
         copilot ? .copilot : nil, cursor ? .cursor : nil].compactMap { $0 }
    }

    /// Enabled assistants that may appear in the UI. Claude, Codex and Cursor need a CLI sign-in.
    private var admittedProviders: [AgentProvider] {
        enabledProviders.filter { AgentMeterAccounts.showsInUI($0, signedIn: usage.meterSignedIn) }
    }

    private var needsMeterSignIn: Bool {
        enabledProviders.contains { AgentMeterAccounts.requiresSignIn($0) }
            && !enabledProviders.filter { AgentMeterAccounts.requiresSignIn($0) }
                .allSatisfy { usage.meterSignedIn.contains($0) }
    }

    /// Cards for the current focus. "All" keeps anyone already seen or with a
    /// plan reading; a single assistant stays visible even before history lands.
    private var providers: [AgentProvider] {
        let enabled = admittedProviders
        if let focus { return enabled.filter { $0 == focus } }
        return enabled.filter { provider in
            usage.snapshot.seen.contains(provider) || usage.snapshot.limits[provider] != nil
                || usage.snapshot.live.contains { $0.provider == provider }
        }
    }

    private var rows: [[NotchAgentTile]] {
        // The strings are read here so a change in Settings redraws the page.
        _ = (cardOrder, hiddenCards)
        return NotchAgentSupport.rows(NotchAgentSupport.tiles(cards: NotchAgentSupport.cards(), providers: providers),
                                      width: size.width)
    }

    var body: some View {
        Group {
            if !usage.snapshot.loaded {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(text.loading).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if enabledProviders.isEmpty {
                NotchEmptyView(symbol: "sparkles", message: text.empty)
            } else if admittedProviders.isEmpty && needsMeterSignIn {
                signInPrompt
            } else {
                VStack(spacing: 8) {
                    if needsMeterSignIn { signInBanner }
                    if admittedProviders.count > 1 { switcher }
                    if providers.isEmpty {
                        NotchEmptyView(symbol: "sparkles", message: text.empty)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if rows.isEmpty {
                        NotchEmptyView(symbol: "square.grid.2x2", message: text.noCards)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        let rows = rows
                        let switcherHeight: CGFloat = admittedProviders.count > 1 ? 28 : 0
                        TimelineView(.periodic(from: .now, by: 15)) { context in
                            if NotchAgentSupport.contentHeight(rows) + switcherHeight > size.height + 0.5 {
                                ScrollView { grid(rows, now: context.date) }
                                    .scrollIndicators(.automatic)
                            } else {
                                grid(rows, now: context.date)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .environment(\.locale, l10n.language.formattingLocale())
        .onAppear { usage.pageDidAppear() }
        .onChange(of: enabledProviders.map(\.rawValue).joined(separator: ",")) { _, _ in
            if let focus, !admittedProviders.contains(focus) { self.focus = nil }
        }
    }

    private var signInPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text.signInPrompt)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                ForEach(usage.meterSignInAccounts) { account in
                    Button {
                        AgentMeterAccounts.signIn(account)
                        usage.refreshMeterSignIn()
                    } label: {
                        HStack(spacing: 6) {
                            NotchAgentMark(provider: account.provider, size: 10)
                            Text(text.signInTo(account.displayName))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.1), in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    private var signInBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text.signInBanner)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(usage.meterSignInAccounts) { account in
                    Button {
                        AgentMeterAccounts.signIn(account)
                        usage.refreshMeterSignIn()
                    } label: {
                        HStack(spacing: 4) {
                            NotchAgentMark(provider: account.provider, size: 9)
                            Text(account.displayName)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08), in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One chip per assistant, plus a combined view. Choosing a chip filters
    /// Limits, Spending and Now to that assistant.
    private var switcher: some View {
        HStack(spacing: 5) {
            switchChip(selected: focus == nil, tint: .white) {
                focus = nil
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 9, weight: .semibold))
            }
            .accessibilityLabel("All")
            ForEach(admittedProviders) { provider in
                switchChip(selected: focus == provider, tint: provider.tint) {
                    focus = provider
                } label: {
                    NotchAgentMark(provider: provider, size: 10)
                }
                .accessibilityLabel(provider.displayName)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 1)
    }

    private func switchChip<Label: View>(selected: Bool, tint: Color, action: @escaping () -> Void,
                                         @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label()
                .frame(width: 22, height: 22)
                .background(selected ? tint.opacity(0.22) : Color.white.opacity(0.06),
                            in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(selected ? tint.opacity(0.55) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func grid(_ rows: [[NotchAgentTile]], now: Date) -> some View {
        VStack(spacing: NotchAgentSupport.spacing) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(spacing: NotchAgentSupport.spacing) {
                    ForEach(row) { tile in card(tile, now: now) }
                }
                .frame(height: NotchAgentSupport.height(of: row))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder private func card(_ tile: NotchAgentTile, now: Date) -> some View {
        let snapshot = usage.snapshot
        let shown = chosenPeriod
        switch tile.card {
        case .limits:
            if let provider = tile.provider {
                NotchAgentLimitsCard(provider: provider, snapshot: snapshot, now: now,
                                     display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining, text: text)
            }
        case .spend:
            NotchAgentSpendCard(usage: snapshot.usage(shown).restricted(to: providers),
                                snapshot: snapshot, providers: providers, period: $period, text: text)
                .id(providers.map(\.rawValue).joined(separator: ","))
        case .live:
            NotchAgentLiveCard(snapshot: snapshot, providers: providers, text: text)
                .id("live-" + providers.map(\.rawValue).joined(separator: ","))
        case .trend:
            NotchAgentTrendCard(snapshot: snapshot, providers: providers, period: shown, text: text)
                .id("trend-" + providers.map(\.rawValue).joined(separator: ","))
        case .models:
            let usage = snapshot.usage(shown).restricted(to: providers)
            NotchAgentShareCard(title: text.modelsCard, symbol: NotchAgentCard.models.symbol,
                                shares: usage.models, byCost: usage.fullyPriced, text: text)
                .id("models-" + providers.map(\.rawValue).joined(separator: ","))
        case .projects:
            let usage = snapshot.usage(shown).restricted(to: providers)
            NotchAgentShareCard(title: text.projectsCard, symbol: NotchAgentCard.projects.symbol,
                                shares: usage.projects, byCost: usage.fullyPriced, text: text)
                .id("projects-" + providers.map(\.rawValue).joined(separator: ","))
        case .activity:
            NotchAgentActivityCard(snapshot: snapshot, providers: providers, text: text)
                .id("activity-" + providers.map(\.rawValue).joined(separator: ","))
        case .resets:
            NotchAgentResetsCard(now: now, text: text)
        }
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

private struct NotchAgentLimitsCard: View {
    let provider: AgentProvider
    let snapshot: AgentUsageSnapshot
    let now: Date
    let display: NotchAgentLimitDisplay
    let text: NotchAgentStrings
    @Environment(\.locale) private var locale

    /// A reading the Claude app saved a while ago: still the latest known,
    /// shown quieter until the app checks again.
    private var stale: Bool {
        guard let limits = snapshot.limits[provider], limits.source == .claudeApp else { return false }
        return now.timeIntervalSince(limits.observedAt) >= AgentClaudeAppUsage.freshness
    }

    /// Two rows fit: the session and whichever longer window binds first.
    private var windows: [AgentLimitWindow] {
        let all = (snapshot.limits[provider]?.windows ?? []).map { AgentLimitSupport.current($0, at: now) }
        let session = all.first { $0.kind == .session }
        let longer = all.filter { $0.kind != .session }.max { $0.usedPercent < $1.usedPercent }
        return [session, longer].compactMap { $0 }
    }

    var body: some View {
        let windows = windows
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: provider.displayName, symbol: provider.symbol, tint: provider.tint,
                                     provider: provider) {
                    HStack(spacing: 4) {
                        if let plan = snapshot.plans[provider] { NotchAgentChip(text: plan.name, tint: provider.tint) }
                        if !snapshot.working(provider).isEmpty { NotchAgentPulse(tint: provider.tint, size: 5) }
                    }
                }
                if windows.isEmpty {
                    estimate
                } else {
                    VStack(spacing: 5) {
                        ForEach(windows) { row($0) }
                    }
                    .opacity(stale ? 0.6 : 1)
                    if windows.count == 1 { caption }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// How old a reading is, once it is old enough to have missed use elsewhere.
    @ViewBuilder private var caption: some View {
        if let observed = snapshot.limits[provider]?.observedAt, now.timeIntervalSince(observed) > 600 {
            Text(text.updated(observed.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)
                .locale(locale))))
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    /// A usage-based forecast would read as a promise, so a row says only
    /// what is spent and when the window renews.
    private func row(_ window: AgentLimitWindow) -> some View {
        let pace = AgentLimitSupport.pace(for: window, now: now)
        let tint = agentLimitTint(provider, usedFraction: window.usedFraction)
        let remaining = display == .remaining
        let fraction = remaining ? window.remainingFraction : window.usedFraction
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(label(window))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .layoutPriority(1)
                Group {
                    if let resets = window.resetsAt {
                        Label(countdown(to: resets), systemImage: "arrow.clockwise")
                            .labelStyle(NotchAgentInlineLabel())
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 9.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Text(AgentFormat.percent(fraction))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint == provider.tint ? Color.white : tint)
                    .contentTransition(.numericText())
            }
            NotchAgentMeter(value: fraction, pace: pace.map { remaining ? 1 - $0.elapsed : $0.elapsed },
                            tint: tint, height: 4)
        }
        .help(help(window))
    }

    /// What the window covers: its length, or the model it is kept for.
    private func label(_ window: AgentLimitWindow) -> String {
        switch window.kind {
        case .session: return text.session
        case .weekly: return window.scope.map { "\(text.weekly) · \($0)" } ?? text.weekly
        case .other:
            guard let minutes = window.minutes else { return window.scope ?? text.readoutLimit }
            return AgentFormat.duration(TimeInterval(minutes) * 60, locale: locale, units: 1)
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
        if let resets = window.resetsAt {
            parts.append(resets.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))
        }
        if let observed = snapshot.limits[provider]?.observedAt, now.timeIntervalSince(observed) > 600 {
            parts.append(text.updated(observed.formatted(.relative(presentation: .named).locale(locale))))
        }
        return parts.joined(separator: " · ")
    }

    /// Without a recent reading from the Claude app, the session still ends
    /// five hours after its first request, so the window itself is known.
    @ViewBuilder private var estimate: some View {
        if provider == .claude, let block = snapshot.claudeBlock {
            let length = block.end.timeIntervalSince(block.start)
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
                    Text(AgentFormat.cost(block.totals.cost))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                NotchAgentMeter(value: length > 0 ? now.timeIntervalSince(block.start) / length : 0,
                                tint: provider.tint, height: 4, dimmed: true)
            }
            .help(text.estimated)
            setUpLimits
        } else if provider == .claude {
            Text(text.noSession).font(.system(size: 10.5)).foregroundStyle(.secondary)
            setUpLimits
        } else if provider == .opencode {
            let todayUsage = snapshot.usage(.today).byProvider[.opencode]
            if let todayUsage, todayUsage.tokens.total > 0 || todayUsage.requests > 0 || todayUsage.cost > 0 {
                let costText: String = {
                    if todayUsage.unpriced > 0 {
                        return todayUsage.cost > 0 ? "≥ " + AgentFormat.cost(todayUsage.cost) : "—"
                    }
                    return AgentFormat.cost(todayUsage.cost)
                }()
                VStack(alignment: .leading, spacing: 3) {
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
            } else {
                Text(text.noSession).font(.system(size: 10.5)).foregroundStyle(.secondary)
                lastUsed
            }
        } else {
            Text(text.waitingForLimits).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
            lastUsed
        }
    }

    /// Claude's plan limits come from the Claude app; the settings say how.
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

private struct NotchAgentSpendCard: View {
    /// Already limited to the assistants on this tab.
    let usage: AgentPeriodUsage
    let snapshot: AgentUsageSnapshot
    let providers: [AgentProvider]
    @Binding var period: String
    let text: NotchAgentStrings

    private var chosen: AgentPeriod { AgentPeriod(rawValue: period) ?? .today }

    var body: some View {
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 5) {
                NotchAgentCardHeader(title: text.spendCard, symbol: NotchAgentCard.spend.symbol) { periodMenu }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text((usage.fullyPriced ? "" : "≥ ") + AgentFormat.cost(usage.total.cost))
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(text.apiValue)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if chosen == .month { multiples }
                }
                .help(usage.fullyPriced ? text.valueNote : text.unpriced)
                split
                Text(footer)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .help(text.saved(AgentFormat.cost(usage.total.savings)))
            }
        }
    }

    private var periodMenu: some View {
        NotchMenuButton(title: text.period(chosen), items: AgentPeriod.allCases.map { option in
            NotchMenuItem(title: text.period(option), checked: option == chosen) { period = option.rawValue }
        }) {
            Text("\(text.period(chosen)) \(Image(systemName: "chevron.down"))")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
    }

    /// Thirty days of API value against a plan's monthly price.
    @ViewBuilder private var multiples: some View {
        HStack(spacing: 3) {
            ForEach(providers) { provider in
                if let plan = snapshot.plans[provider], let price = plan.monthlyPrice, price > 0,
                   let spent = usage.byProvider[provider]?.cost, spent > 0 {
                    let multiple = (spent / price).formatted(.number.precision(.fractionLength(spent / price < 10 ? 1 : 0))) + "×"
                    NotchAgentChip(text: multiple, tint: provider.tint)
                        .help(text.planMultiple(multiple, plan: "\(provider.displayName) \(plan.name)"))
                }
            }
        }
    }

    @ViewBuilder private var split: some View {
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

    private var footer: String {
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
            Text([AgentPricing.displayName(session.model),
                  session.tokens.output > 0 ? text.written(AgentFormat.tokens(session.tokens.output)) : "",
                  session.cost > 0 ? AgentFormat.cost(session.cost) : ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(text.tokens(AgentFormat.tokens(session.tokens.total)) + " · "
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
    let snapshot: AgentUsageSnapshot
    let providers: [AgentProvider]
    let period: AgentPeriod
    let text: NotchAgentStrings
    @State private var hovered: Date?
    @Environment(\.locale) private var locale

    private var buckets: [AgentBucket] {
        period == .today ? snapshot.hours : Array(snapshot.days.suffix(period.days))
    }

    var body: some View {
        let usage = snapshot.usage(period).restricted(to: providers)
        let byCost = usage.fullyPriced
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: text.trendCard, symbol: NotchAgentCard.trend.symbol) {
                    Text(caption(usage: usage, byCost: byCost))
                        .font(.system(size: 9.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                NotchAgentBars(buckets: buckets, providers: providers, byCost: byCost, hovered: $hovered)
                axis
            }
        }
    }

    private func caption(usage: AgentPeriodUsage, byCost: Bool) -> String {
        if let hovered, let bucket = buckets.first(where: { $0.start == hovered }) {
            // A pointed-at bar reads its tokens beside its cost, for this tab only.
            let totals = bucket.total(for: providers)
            let tokens = byCost ? " · " + value(totals, byCost: false) : ""
            return label(bucket.start, long: true) + " · " + value(totals, byCost: byCost) + tokens
        }
        return text.period(period) + " · " + value(usage.total, byCost: byCost)
    }

    private func value(_ totals: AgentTotals, byCost: Bool) -> String {
        byCost ? AgentFormat.cost(totals.cost) : text.tokens(AgentFormat.tokens(totals.tokens.total))
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
            Text(byCost ? AgentFormat.cost(share.totals.cost) : AgentFormat.tokens(share.totals.tokens.total))
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .frame(height: 14)
        .help([share.name, text.tokens(AgentFormat.tokens(share.totals.tokens.total)),
               AgentFormat.cost(share.totals.cost)].joined(separator: " · "))
    }
}

// MARK: Activity

private struct NotchAgentActivityCard: View {
    let snapshot: AgentUsageSnapshot
    let providers: [AgentProvider]
    let text: NotchAgentStrings
    @State private var hovered: Date?
    @Environment(\.locale) private var locale

    private var days: [AgentBucket] {
        snapshot.days.map { $0.restricted(to: providers) }
    }

    /// Days in a row with any use, counting today only once it has some.
    private var streak: Int {
        let days = days
        var count = 0
        for day in days.reversed() {
            if day.total.requests > 0 { count += 1 }
            else if count > 0 || day.id != days.last?.id { break }
        }
        return count
    }

    var body: some View {
        let days = days
        let byCost = days.allSatisfy { $0.total.unpriced == 0 }
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: text.activityCard, symbol: NotchAgentCard.activity.symbol) {
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
                    let map = NotchAgentHeatmap.width(height: proxy.size.height, days: days)
                    HStack(alignment: .top, spacing: 14) {
                        NotchAgentHeatmap(days: days, byCost: byCost, hovered: $hovered)
                            .frame(width: map, height: proxy.size.height)
                        figures(days: days, byCost: byCost)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
    }

    /// The total for the whole map, its active days and its busiest day; a
    /// hovered day takes the place of the busiest one.
    private func figures(days: [AgentBucket], byCost: Bool) -> some View {
        let active = days.filter { $0.total.requests > 0 }
        let busiest = active.max { $0.total.weight(byCost: byCost) < $1.total.weight(byCost: byCost) }
        let pointed = hovered.flatMap { date in days.first { $0.start == date } }
        return VStack(alignment: .leading, spacing: 2) {
            Text(value(days.reduce(into: AgentTotals()) { $0 += $1.total }, byCost: byCost))
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(AgentFormat.span(days: days.count, locale: locale))
                .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            figure(text.activeDays, "\(active.count)")
            if let day = pointed ?? busiest {
                figure(pointed == nil ? text.busiestDay : day.start.formatted(.dateTime.weekday(.wide).locale(locale)),
                       day.start.formatted(.dateTime.day().month(.abbreviated).locale(locale)) + " · " + value(day.total, byCost: byCost))
            }
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Text(value).monospacedDigit().lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium))
        .minimumScaleFactor(0.85)
    }

    private func value(_ totals: AgentTotals, byCost: Bool) -> String {
        byCost ? AgentFormat.cost(totals.cost) : AgentFormat.tokens(totals.tokens.total)
    }
}

// MARK: Resets

/// Codex's banked resets: how many the account holds, when the next one
/// expires, and a use that asks first. Cancel takes the place of the button
/// that asked, so a double click never spends one.
private struct NotchAgentResetsCard: View {
    let now: Date
    let text: NotchAgentStrings
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
