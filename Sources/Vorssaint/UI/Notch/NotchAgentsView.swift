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

    private var text: NotchAgentStrings { FeatureStrings.notchAgents(l10n.language) }
    private var chosenPeriod: AgentPeriod { AgentPeriod(rawValue: period) ?? .today }

    /// Only agents that left something on this Mac get cards.
    private var providers: [AgentProvider] {
        [claude ? AgentProvider.claude : nil, codex ? .codex : nil, opencode ? .opencode : nil].compactMap { $0 }
            .filter(usage.snapshot.seen.contains)
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
            } else if providers.isEmpty {
                NotchEmptyView(symbol: "sparkles", message: text.empty)
            } else if rows.isEmpty {
                NotchEmptyView(symbol: "square.grid.2x2", message: text.noCards)
            } else {
                let rows = rows
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    if NotchAgentSupport.contentHeight(rows) > size.height + 0.5 {
                        ScrollView { grid(rows, now: context.date) }
                            .scrollIndicators(.automatic)
                    } else {
                        grid(rows, now: context.date)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .environment(\.locale, l10n.language.formattingLocale())
        .onAppear { usage.pageDidAppear() }
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
            NotchAgentSpendCard(snapshot: snapshot, providers: providers, period: $period, text: text)
        case .live:
            NotchAgentLiveCard(snapshot: snapshot, providers: providers, text: text)
        case .trend:
            NotchAgentTrendCard(snapshot: snapshot, providers: providers, period: shown, text: text)
        case .models:
            NotchAgentShareCard(id: "agent.models", title: text.modelsCard, symbol: NotchAgentCard.models.symbol,
                                shares: snapshot.usage(shown).models, byCost: snapshot.usage(shown).fullyPriced, text: text)
        case .projects:
            NotchAgentShareCard(id: "agent.projects", title: text.projectsCard, symbol: NotchAgentCard.projects.symbol,
                                shares: snapshot.usage(shown).projects, byCost: snapshot.usage(shown).fullyPriced, text: text)
        case .activity:
            NotchAgentActivityCard(snapshot: snapshot, text: text)
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

    private var allWindows: [AgentLimitWindow] {
        (snapshot.limits[provider]?.windows ?? []).map { AgentLimitSupport.current($0, at: now) }
    }

    private var windows: [AgentLimitWindow] { NotchAgentSupport.compactLimitWindows(allWindows) }
    private var expansionID: String { "agent.limits.\(provider.rawValue)" }
    private var hiddenCount: Int {
        let visibleIDs = Set(windows.map(\.id))
        return allWindows.filter { !visibleIDs.contains($0.id) }.count
    }

    var body: some View {
        if !allWindows.isEmpty {
            compact.notchExpansionTap(id: expansionID)
                .notchExpandable(id: expansionID, title: provider.displayName,
                                    preferredSize: CGSize(width: 360, height: 72 + CGFloat(allWindows.count) * 46),
                                    header: AnyView(header(expanded: true))) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(allWindows) { row($0, expanded: true) }
                        caption
                    }
                    .opacity(stale ? 0.6 : 1)
                }
                .scrollIndicators(.automatic)
            }
        } else {
            compact
        }
    }

    private func header(expanded: Bool = false) -> some View {
        NotchAgentCardHeader(title: provider.displayName, symbol: provider.symbol, tint: provider.tint,
                             provider: provider) {
            HStack(spacing: 4) {
                if let plan = snapshot.plans[provider] { NotchAgentChip(text: plan.name, tint: provider.tint) }
                if !snapshot.working(provider).isEmpty { NotchAgentPulse(tint: provider.tint, size: 5) }
                if !expanded, !allWindows.isEmpty {
                    NotchExpandButton(id: expansionID, title: "\(provider.displayName), \(L10n.shared.s.menuShowAll)",
                                      hiddenCount: hiddenCount > 0 ? hiddenCount : nil)
                }
            }
        }
    }

    private var compact: some View {
        let windows = windows
        return NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                header()
                if windows.isEmpty {
                    estimate
                } else {
                    VStack(spacing: 5) { ForEach(windows) { row($0) } }
                        .opacity(stale ? 0.6 : 1)
                    if windows.count == 1 { caption }
                }
            }
        }
        .accessibilityElement(children: .contain)
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
    private func row(_ window: AgentLimitWindow, expanded: Bool = false) -> some View {
        let pace = AgentLimitSupport.pace(for: window, now: now)
        let tint = agentLimitTint(provider, usedFraction: window.usedFraction)
        let remaining = display == .remaining
        let fraction = remaining ? window.remainingFraction : window.usedFraction
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(label(window, expanded: expanded))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(expanded ? nil : 1)
                    .fixedSize(horizontal: false, vertical: expanded)
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
    private func label(_ window: AgentLimitWindow, expanded: Bool = false) -> String {
        let name: String
        switch window.kind {
        case .session: name = text.session
        case .weekly: return window.scope.map { "\(text.weekly) · \($0)" } ?? text.weekly
        case .other:
            guard let minutes = window.minutes else { return window.scope ?? text.readoutLimit }
            name = AgentFormat.duration(TimeInterval(minutes) * 60, locale: locale, units: 1)
        }
        return expanded ? window.scope.map { "\(name) · \($0)" } ?? name : name
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
                            Text("· \(AgentFormat.percent(rate)) \(text.cached(""))".trimmingCharacters(in: .whitespaces))
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
    let snapshot: AgentUsageSnapshot
    let providers: [AgentProvider]
    @Binding var period: String
    let text: NotchAgentStrings

    private var chosen: AgentPeriod { AgentPeriod(rawValue: period) ?? .today }

    var body: some View {
        let usage = snapshot.usage(chosen)
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 5) {
                header()
                summary(usage)
            }
        }
        .notchExpansionTap(id: "agent.spend")
        .notchExpandable(id: "agent.spend", title: text.spendCard, header: AnyView(header(expanded: true))) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    summary(usage, expanded: true)
                    Text(usage.fullyPriced ? text.valueNote : text.unpriced)
                        .font(.system(size: 9.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(providers) { provider in
                        if let totals = usage.byProvider[provider] {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label(provider.displayName, systemImage: provider.symbol)
                                        .foregroundStyle(provider.tint)
                                    Spacer(minLength: 4)
                                    Text((totals.unpriced == 0 ? "" : "≥ ") + AgentFormat.cost(totals.cost))
                                        .monospacedDigit()
                                }
                                Text(text.tokens(AgentFormat.tokens(totals.tokens.total)))
                                Text(text.written(AgentFormat.tokens(totals.tokens.output)))
                                if let rate = totals.tokens.cacheHitRate {
                                    Text(text.cached(AgentFormat.percent(rate)))
                                }
                                Text(text.saved(AgentFormat.cost(totals.savings)))
                            }
                            .font(.system(size: 11))
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .textSelection(.enabled)
            }
        }
    }

    private func summary(_ usage: AgentPeriodUsage, expanded: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text((usage.fullyPriced ? "" : "≥ ") + AgentFormat.cost(usage.total.cost))
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
                if chosen == .month { multiples(usage) }
            }
            .help(usage.fullyPriced ? text.valueNote : text.unpriced)
            split(usage)
            Text(footer(usage))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 1)
                .minimumScaleFactor(0.85)
                .help(text.saved(AgentFormat.cost(usage.total.savings)))
        }
    }

    private func header(expanded: Bool = false) -> some View {
        NotchAgentCardHeader(title: text.spendCard, symbol: NotchAgentCard.spend.symbol) {
            HStack(spacing: 4) {
                if !expanded {
                    periodMenu
                    NotchExpandButton(id: "agent.spend", title: text.spendCard)
                } else {
                    Text(text.period(chosen)).font(.system(size: 9.5)).foregroundStyle(.secondary)
                }
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
    @ViewBuilder private func multiples(_ usage: AgentPeriodUsage) -> some View {
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
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.locale) private var locale
    private var live: [AgentLiveSession] { snapshot.live.filter { providers.contains($0.provider) } }
    private var hiddenCount: Int { NotchAgentSupport.hiddenCount(total: live.count, visible: 2) }
    private let expansionID = "agent.live"

    var body: some View {
        if !live.isEmpty {
            compact.notchExpansionTap(id: expansionID)
                .notchExpandable(id: expansionID, title: text.liveCard,
                                    preferredSize: CGSize(width: 360, height: 60 + CGFloat(live.count) * 36),
                                    header: AnyView(header(expanded: true))) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ScrollView { liveRows(live, now: context.date, expanded: true) }
                        .scrollIndicators(.automatic)
                }
            }
        } else {
            compact
        }
    }

    private func header(expanded: Bool = false) -> some View {
        NotchAgentCardHeader(title: text.liveCard, symbol: NotchAgentCard.live.symbol,
                             tint: live.first?.provider.tint ?? .secondary) {
            HStack(spacing: 4) {
                if !expanded, !live.isEmpty {
                    NotchExpandButton(id: expansionID, title: "\(text.liveCard), \(l10n.s.menuShowAll)",
                                      hiddenCount: hiddenCount > 0 ? hiddenCount : nil)
                }
                if let first = live.first { NotchAgentPulse(tint: first.provider.tint, size: 5) }
            }
        }
    }

    private var compact: some View {
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 7) {
                header()
                if live.isEmpty {
                    VStack(alignment: .leading, spacing: 5) { ForEach(providers) { idleRow($0) } }
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        liveRows(Array(live.prefix(2)), now: context.date)
                    }
                }
            }
        }
    }

    private func liveRows(_ sessions: [AgentLiveSession], now: Date, expanded: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: expanded ? 10 : 5) {
            ForEach(sessions) { row($0, now: now, expanded: expanded) }
        }
    }

    private func row(_ session: AgentLiveSession, now: Date, expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                NotchAgentGlyph(provider: session.provider, size: 9)
                Text(session.project.isEmpty ? session.provider.displayName : session.project)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(expanded ? nil : 1)
                    .fixedSize(horizontal: false, vertical: expanded)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(AgentFormat.clock(now.timeIntervalSince(session.started)))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(session.provider.tint)
            }
            Text([AgentPricing.displayName(session.model),
                  session.tokens.output > 0 ? text.written(AgentFormat.tokens(session.tokens.output)) : "",
                  session.cost > 0 ? AgentFormat.cost(session.cost) : ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 1)
                .fixedSize(horizontal: false, vertical: expanded)
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
        if buckets.isEmpty {
            compact
        } else {
            compact.notchExpansionTap(id: "agent.trend")
                .notchExpandable(id: "agent.trend", title: text.trendCard, header: AnyView(header(expanded: true))) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            NotchAgentBars(buckets: buckets, providers: providers,
                                           byCost: snapshot.usage(period).fullyPriced, hovered: $hovered)
                                .frame(height: 80)
                            axis
                            NotchAgentBucketRows(buckets: buckets, hourly: period == .today, text: text)
                        }
                    }
                }
        }
    }

    private func header(expanded: Bool = false) -> some View {
        let byCost = snapshot.usage(period).fullyPriced
        return NotchAgentCardHeader(title: text.trendCard, symbol: NotchAgentCard.trend.symbol) {
            Text(caption(byCost: byCost))
                .font(.system(size: 9.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !expanded, !buckets.isEmpty {
                NotchExpandButton(id: "agent.trend", title: text.trendCard)
            }
        }
    }

    private var compact: some View {
        let byCost = snapshot.usage(period).fullyPriced
        return NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                header()
                NotchAgentBars(buckets: buckets, providers: providers, byCost: byCost, hovered: $hovered)
                axis
            }
        }
    }

    private func caption(byCost: Bool) -> String {
        if let hovered, let bucket = buckets.first(where: { $0.start == hovered }) {
            return label(bucket.start, long: true) + " · " + value(bucket.total, byCost: byCost)
        }
        return text.period(period) + " · " + value(snapshot.usage(period).total, byCost: byCost)
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
    let id: String
    let title: String
    let symbol: String
    let shares: [AgentShare]
    let byCost: Bool
    let text: NotchAgentStrings
    private var hiddenCount: Int { NotchAgentSupport.hiddenCount(total: shares.count, visible: 3) }
    private var peak: Double { max(shares.map { $0.totals.weight(byCost: byCost) }.max() ?? 0, .leastNonzeroMagnitude) }

    var body: some View {
        if !shares.isEmpty {
            compact.notchExpansionTap(id: id)
                .notchExpandable(id: id, title: title,
                                    preferredSize: CGSize(width: 360, height: 60 + CGFloat(shares.count) * 26),
                                    header: AnyView(header(expanded: true))) {
                ScrollView {
                    VStack(spacing: 10) { ForEach(shares) { row($0, expanded: true) } }
                }
                .scrollIndicators(.automatic)
            }
        } else {
            compact
        }
    }

    private func header(expanded: Bool = false) -> some View {
        NotchAgentCardHeader(title: title, symbol: symbol) {
            if !expanded, !shares.isEmpty {
                NotchExpandButton(id: id, title: "\(title), \(L10n.shared.s.menuShowAll)",
                                  hiddenCount: hiddenCount > 0 ? hiddenCount : nil)
            }
        }
    }

    private var compact: some View {
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                header()
                if shares.isEmpty {
                    Text(text.noActivity).font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 5) { ForEach(Array(shares.prefix(3))) { row($0) } }
                }
            }
        }
    }

    private func row(_ share: AgentShare, expanded: Bool = false) -> some View {
        let weight = share.totals.weight(byCost: byCost)
        let tint = share.provider?.tint ?? .white
        return HStack(spacing: 6) {
            Text(share.name)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(expanded ? nil : 1)
                .fixedSize(horizontal: false, vertical: expanded)
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
        .frame(minHeight: 14)
        .help([share.name, text.tokens(AgentFormat.tokens(share.totals.tokens.total)),
               AgentFormat.cost(share.totals.cost)].joined(separator: " · "))
    }
}

/// The values behind both charts, without requiring pointer hover over a tiny cell.
private struct NotchAgentBucketRows: View {
    let buckets: [AgentBucket]
    var hourly = false
    let text: NotchAgentStrings
    @Environment(\.locale) private var locale

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(buckets) { bucket in
                VStack(alignment: .leading, spacing: 4) {
                    Text(bucket.start.formatted(hourly
                        ? .dateTime.hour().locale(locale)
                        : .dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale)))
                        .font(.system(size: 11, weight: .semibold))
                    HStack {
                        Text(text.tokens(AgentFormat.tokens(bucket.total.tokens.total)))
                        Spacer(minLength: 4)
                        Text((bucket.total.unpriced == 0 ? "" : "≥ ") + AgentFormat.cost(bucket.total.cost))
                    }
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .textSelection(.enabled)
    }
}

// MARK: Activity

private struct NotchAgentActivityCard: View {
    let snapshot: AgentUsageSnapshot
    let text: NotchAgentStrings
    @State private var hovered: Date?
    @Environment(\.locale) private var locale

    /// Days in a row with any use, counting today only once it has some.
    private var streak: Int {
        var count = 0
        for day in snapshot.days.reversed() {
            if day.total.requests > 0 { count += 1 }
            else if count > 0 || day.id != snapshot.days.last?.id { break }
        }
        return count
    }

    var body: some View {
        if snapshot.days.isEmpty {
            compact
        } else {
            compact.notchExpansionTap(id: "agent.activity")
                .notchExpandable(id: "agent.activity", title: text.activityCard, header: AnyView(header(expanded: true))) {
                    let byCost = snapshot.days.allSatisfy { $0.total.unpriced == 0 }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 14) {
                                NotchAgentHeatmap(days: snapshot.days, byCost: byCost, hovered: $hovered)
                                    .frame(width: NotchAgentHeatmap.width(height: 80, days: snapshot.days))
                                figures(byCost: byCost)
                            }
                            .frame(height: 80)
                            NotchAgentBucketRows(buckets: snapshot.days, text: text)
                        }
                    }
                }
        }
    }

    private func header(expanded: Bool = false) -> some View {
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
            if !expanded, !snapshot.days.isEmpty {
                NotchExpandButton(id: "agent.activity", title: text.activityCard)
            }
        }
    }

    private var compact: some View {
        let byCost = snapshot.days.allSatisfy { $0.total.unpriced == 0 }
        return NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                header()
                GeometryReader { proxy in
                    let map = NotchAgentHeatmap.width(height: proxy.size.height, days: snapshot.days)
                    HStack(alignment: .top, spacing: 14) {
                        NotchAgentHeatmap(days: snapshot.days, byCost: byCost, hovered: $hovered)
                            .frame(width: map, height: proxy.size.height)
                        figures(byCost: byCost)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
    }

    /// The total for the whole map, its active days and its busiest day; a
    /// hovered day takes the place of the busiest one.
    private func figures(byCost: Bool) -> some View {
        let active = snapshot.days.filter { $0.total.requests > 0 }
        let busiest = active.max { $0.total.weight(byCost: byCost) < $1.total.weight(byCost: byCost) }
        let pointed = hovered.flatMap { date in snapshot.days.first { $0.start == date } }
        return VStack(alignment: .leading, spacing: 2) {
            Text(value(snapshot.days.reduce(into: AgentTotals()) { $0 += $1.total }, byCost: byCost))
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(AgentFormat.span(days: snapshot.days.count, locale: locale))
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
                header()
                content
            }
        }
        .notchExpansionTap(id: "agent.resets")
        .notchExpandable(id: "agent.resets", title: text.resetsCard, header: AnyView(header(expanded: true))) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text.resetsHelp).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    if let summary = resets.summary {
                        Text(summary.available, format: .number.locale(locale))
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(tint).monospacedDigit()
                        ForEach(summary.resets) { reset in
                            if let expiresAt = reset.expiresAt {
                                Text(text.resetsExpiry(expiresAt.formatted(
                                    Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))))
                                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                            }
                        }
                    } else if let failure = resets.failure {
                        Text(message(failure)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
        }
        .help(text.resetsHelp)
        .onAppear { resets.refreshIfStale() }
        // A count that changed while the question was open asks again.
        .onChange(of: resets.summary?.available) { _, _ in confirming = false }
    }

    private func header(expanded: Bool = false) -> some View {
        NotchAgentCardHeader(title: text.resetsCard, symbol: NotchAgentCard.resets.symbol, tint: tint,
                             provider: .codex) {
            if let summary = resets.summary, summary.available > 0 {
                NotchAgentChip(text: summary.available.formatted(.number.locale(locale)), tint: tint)
            } else if resets.checking {
                ProgressView().controlSize(.mini)
            }
            if !expanded { NotchExpandButton(id: "agent.resets", title: text.resetsCard) }
        }
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
