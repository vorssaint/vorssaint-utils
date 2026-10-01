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

    private var text: NotchAgentStrings { FeatureStrings.notchAgents(l10n.language) }
    private var chosenPeriod: AgentPeriod { AgentPeriod(rawValue: period) ?? .today }

    /// Only agents that left something on this Mac get cards.
    private var providers: [AgentProvider] {
        [claude ? AgentProvider.claude : nil, codex ? .codex : nil].compactMap { $0 }
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
            NotchAgentShareCard(title: text.modelsCard, symbol: NotchAgentCard.models.symbol,
                                shares: snapshot.usage(shown).models, byCost: snapshot.usage(shown).fullyPriced, text: text)
        case .projects:
            NotchAgentShareCard(title: text.projectsCard, symbol: NotchAgentCard.projects.symbol,
                                shares: snapshot.usage(shown).projects, byCost: snapshot.usage(shown).fullyPriced, text: text)
        case .activity:
            NotchAgentActivityCard(snapshot: snapshot, text: text)
        case .tokens:
            NotchAgentTokensCard(usage: snapshot.usage(shown), providers: providers, text: text)
        case .skills:
            NotchAgentSkillsCard(usage: snapshot.usage(shown), text: text)
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

    /// Without a recent reading from the Claude app, the session still starts
    /// and ends on the hour of its first request, so the window itself is known.
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
                NotchAgentCardHeader(title: text.spendCard, symbol: NotchAgentCard.spend.symbol) { periodMenu }
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
        let byCost = snapshot.usage(period).fullyPriced
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: text.trendCard, symbol: NotchAgentCard.trend.symbol) {
                    Text(caption(byCost: byCost))
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
    let title: String
    let symbol: String
    let shares: [AgentShare]
    let byCost: Bool
    let text: NotchAgentStrings
    /// The row opened into its token breakdown.
    @State private var opened: String?

    var body: some View {
        if let share = shares.first(where: { $0.id == opened }) {
            NotchAgentCardChrome {
                VStack(alignment: .leading, spacing: 7) {
                    NotchAgentCardHeader(title: share.name, symbol: symbol) {
                        Button { opened = nil } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(text.back)
                        .accessibilityLabel(text.back)
                    }
                    NotchAgentTokenRings(rings: [NotchAgentTokenRings.Ring(id: share.id, tokens: share.totals.tokens)],
                                         text: text)
                }
            }
        } else {
            list
        }
    }

    @ViewBuilder private var list: some View {
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
        return Button { opened = share.id } label: {
            HStack(spacing: 6) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help([share.name, text.tokens(AgentFormat.tokens(share.totals.tokens.total)),
               AgentFormat.cost(share.totals.cost)].joined(separator: " · "))
    }
}

// MARK: Breakdowns

/// Token kinds as rings beside one legend: a ring for each agent on the
/// Tokens card, or one for a model or project opened on its card. Kinds never
/// overlap, so each ring is exactly its total.
private struct NotchAgentTokenRings: View {
    struct Ring: Identifiable {
        let id: String
        var label: String? = nil
        var tint: Color = .secondary
        let tokens: AgentTokens
    }

    struct Part: Identifiable {
        let id: String
        let name: String
        let value: Int
        let color: Color
        var note: String? = nil
    }

    let rings: [Ring]
    let text: NotchAgentStrings

    var body: some View {
        let total = rings.reduce(into: AgentTokens()) { $0 += $1.tokens }
        HStack(alignment: .center, spacing: 10) {
            ForEach(rings) { ring($0) }
            legend(total)
        }
    }

    private func ring(_ ring: Ring) -> some View {
        let parts = Self.parts(ring.tokens, text: text)
        return VStack(spacing: 2) {
            NotchAgentDonut(parts: parts)
                .frame(width: 38, height: 38)
                .overlay {
                    Text(AgentFormat.tokens(ring.tokens.total))
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                }
            if let label = ring.label {
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(ring.tint)
                    .lineLimit(1)
            }
        }
        .help(help(ring.label, parts))
        .accessibilityElement(children: .combine)
    }

    /// Each kind's count for one ring, with its reasoning where known.
    private func help(_ label: String?, _ parts: [Part]) -> String {
        var lines = label.map { [$0] } ?? []
        for part in parts where part.value > 0 {
            var line = part.name + " " + AgentFormat.tokens(part.value)
            if let note = part.note { line += " (" + note + ")" }
            lines.append(line)
        }
        return lines.joined(separator: " · ")
    }

    /// Beside two rings a name has no room to share with its percentage,
    /// which then moves to the tooltip.
    private func legend(_ tokens: AgentTokens) -> some View {
        let roomy = rings.count < 2
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Self.parts(tokens, text: text).filter { $0.value > 0 }) { part in
                let share = Self.share(part.value, of: tokens.total)
                HStack(spacing: 5) {
                    Circle().fill(part.color).frame(width: 6, height: 6)
                    Text(part.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if roomy {
                        Text(share)
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 11)
                .help(part.name + " " + AgentFormat.tokens(part.value) + (roomy ? "" : " · " + share))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// A share that rounds to nothing but is not reads as under one percent.
    static func share(_ value: Int, of total: Int) -> String {
        let fraction = Double(value) / Double(max(total, 1))
        return value > 0 && fraction < 0.005 ? "<" + AgentFormat.percent(0.01) : AgentFormat.percent(fraction)
    }

    /// Kinds of token that add up to a total. Reasoning is part of output,
    /// so it is only mentioned there.
    static func parts(_ tokens: AgentTokens, text: NotchAgentStrings) -> [Part] {
        AgentTokenPart.allCases.map { part in
            switch part {
            case .input: return Part(id: "input", name: text.tokenInput, value: tokens.input, color: .blue)
            case .cacheWrite:
                return Part(id: "cacheWrite", name: text.tokenCacheWrite, value: tokens.cacheWrite, color: .orange)
            case .cacheRead:
                return Part(id: "cacheRead", name: text.tokenCacheRead, value: tokens.cacheRead, color: .teal)
            case .output:
                return Part(id: "output", name: text.tokenOutput, value: tokens.output, color: .pink,
                            note: tokens.reasoning > 0 ? text.reasoning(AgentFormat.tokens(tokens.reasoning)) : nil)
            }
        }
    }
}

/// Where the period's tokens went: a ring for each agent that used any.
private struct NotchAgentTokensCard: View {
    let usage: AgentPeriodUsage
    let providers: [AgentProvider]
    let text: NotchAgentStrings

    var body: some View {
        let tokens = usage.total.tokens
        let rings = providers.compactMap { provider -> NotchAgentTokenRings.Ring? in
            guard let used = usage.byProvider[provider]?.tokens, used.total > 0 else { return nil }
            return NotchAgentTokenRings.Ring(id: provider.rawValue, label: provider.displayName,
                                             tint: provider.tint, tokens: used)
        }
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: text.tokensTitle, symbol: NotchAgentCard.tokens.symbol) {
                    if tokens.total > 0 { NotchAgentHeaderFigure(value: AgentFormat.tokens(tokens.total)) }
                }
                if rings.isEmpty {
                    Text(text.noActivity).font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    NotchAgentTokenRings(rings: rings, text: text)
                }
            }
        }
    }
}

/// Parts of a whole around a circle. Every part keeps a visible arc and the
/// rest shares what is left.
private struct NotchAgentDonut: View {
    let parts: [NotchAgentTokenRings.Part]

    var body: some View {
        let shown = parts.filter { $0.value > 0 }
        let total = Double(shown.reduce(0) { $0 + $1.value })
        let gap = shown.count > 1 ? 0.015 : 0
        let sliver = 0.02
        let room = max(0, 1 - Double(shown.count) * (gap + sliver))
        let lengths = shown.map { sliver + room * Double($0.value) / max(total, 1) }
        ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: 5)
            ForEach(shown.indices, id: \.self) { index in
                let start = lengths[..<index].reduce(0, +) + gap * Double(index)
                Circle()
                    .trim(from: start, to: start + lengths[index])
                    .stroke(shown[index].color, style: StrokeStyle(lineWidth: 5, lineCap: .butt))
            }
        }
        .rotationEffect(.degrees(-90))
        .padding(2.5)
        .accessibilityHidden(true)
    }
}

/// Skills started in the period, by the person and by the agent. A count
/// beside the tokens, not a share of them: a skill is paid for by every
/// later request that reads it.
private struct NotchAgentSkillsCard: View {
    let usage: AgentPeriodUsage
    let text: NotchAgentStrings

    private struct Row {
        let name: String
        var person = 0
        var agent = 0
        var total: Int { person + agent }
    }

    private static let personTint = Color.mint
    private static let agentTint = Color.purple

    private var rows: [Row] {
        var rows: [String: Row] = [:]
        for (skill, count) in usage.skills {
            if skill.byPerson { rows[skill.name, default: Row(name: skill.name)].person += count }
            else { rows[skill.name, default: Row(name: skill.name)].agent += count }
        }
        return rows.values.sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
    }

    var body: some View {
        let rows = rows
        let peak = Double(rows.first?.total ?? 1)
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: text.skillsTitle, symbol: NotchAgentCard.skills.symbol) {
                    HStack(spacing: 6) {
                        origin(rows.reduce(0) { $0 + $1.person }, tint: Self.personTint, label: text.skillsByYou)
                        origin(rows.reduce(0) { $0 + $1.agent }, tint: Self.agentTint, label: text.skillsByAgent)
                    }
                }
                if rows.isEmpty {
                    Text(text.noActivity).font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 5) {
                        ForEach(rows.prefix(3), id: \.name) { row($0, peak: peak) }
                    }
                }
            }
        }
    }

    /// One side's count in the header, which doubles as the bars' legend.
    @ViewBuilder
    private func origin(_ count: Int, tint: Color, label: String) -> some View {
        if count > 0 {
            HStack(spacing: 3) {
                Circle().fill(tint).frame(width: 5, height: 5)
                NotchAgentHeaderFigure(value: "×\(count)")
            }
            .help(label)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) ×\(count)")
        }
    }

    private func row(_ row: Row, peak: Double) -> some View {
        HStack(spacing: 6) {
            Text(row.name)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 1) {
                if row.person > 0 { bar(row.person, peak: peak, tint: Self.personTint) }
                if row.agent > 0 { bar(row.agent, peak: peak, tint: Self.agentTint) }
            }
            .frame(width: 44, alignment: .leading)
            Text("×\(row.total)")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .trailing)
        }
        .frame(height: 14)
        .help([row.name, row.person > 0 ? "\(text.skillsByYou) ×\(row.person)" : nil,
               row.agent > 0 ? "\(text.skillsByAgent) ×\(row.agent)" : nil].compactMap { $0 }
            .joined(separator: " · "))
    }

    private func bar(_ count: Int, peak: Double, tint: Color) -> some View {
        Capsule(style: .continuous)
            .fill(tint.gradient)
            .frame(width: max(3, 40 * Double(count) / peak), height: 4)
    }
}

/// A card's headline number, set small beside its title.
private struct NotchAgentHeaderFigure: View {
    let value: String

    var body: some View {
        Text(value)
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
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
        let byCost = snapshot.days.allSatisfy { $0.total.unpriced == 0 }
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
