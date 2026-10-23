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
    @AppStorage(DefaultsKey.notchAgentsHiddenCards) private var hiddenCards = NotchAgentSupport.defaultHiddenCards
    @AppStorage(DefaultsKey.notchAgentsClaude) private var claude = true
    @AppStorage(DefaultsKey.notchAgentsCodex) private var codex = true
    @AppStorage(DefaultsKey.notchAgentsOpenCode) private var opencode = true
    @AppStorage(DefaultsKey.notchAgentsCopilot) private var copilot = true
    @AppStorage(DefaultsKey.notchAgentsClaudeBilling) private var billing = AgentClaudeBilling.automatic.rawValue
    @AppStorage(DefaultsKey.notchAgentsIslandHiddenAccounts) private var hiddenAccounts = ""
    @AppStorage(DefaultsKey.notchAgentsIslandHiddenProfiles) private var hiddenProfiles = ""

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
        [claude ? AgentProvider.claude : nil, codex ? .codex : nil, opencode ? .opencode : nil, copilot ? .copilot : nil].compactMap { $0 }
            .filter { usage.snapshot.seen.contains($0) || ($0 == .codex && !codexAccounts.isEmpty)
                || ($0 == .claude && !usage.snapshot.claudeSeats.isEmpty) }
    }

    /// Whether an API key pays for Claude Code, which splits Claude's card.
    private var claudeUsesAPI: Bool {
        _ = billing
        return AgentClaudeBilling.usesAPI()
    }

    private var rows: [[NotchAgentTile]] {
        // The strings are read here so a change in Settings redraws the page.
        _ = (cardOrder, hiddenCards, hiddenAccounts, hiddenProfiles)
        let tiles = NotchAgentSupport.pageTiles(usage.snapshot, providers: providers,
                                                codexAccounts: codexAccounts.map(\.id), claudeUsesAPI: claudeUsesAPI)
        return NotchAgentSupport.rows(tiles, width: size.width)
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
            } else if rows.isEmpty {
                NotchEmptyView(symbol: "square.grid.2x2", message: text.noCards)
            } else {
                let rows = rows
                TimelineView(.periodic(from: .now, by: 10)) { context in
                    if NotchAgentSupport.contentHeight(rows, width: size.width, live: usage.snapshot.live)
                        > size.height + 0.5 {
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

    private func grid(_ rows: [[NotchAgentTile]], now: Date) -> some View {
        VStack(spacing: NotchAgentSupport.spacing) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(spacing: NotchAgentSupport.spacing) {
                    ForEach(row) { tile in card(tile, now: now) }
                }
                .frame(height: NotchAgentSupport.height(of: row, width: size.width, live: usage.snapshot.live))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder private func card(_ tile: NotchAgentTile, now: Date) -> some View {
        let snapshot = usage.snapshot
        let shown = chosenPeriod
        switch tile.card {
        case .limits:
            if tile.claudeSeats {
                let seats = NotchLimitVisibility.seats(snapshot, in: .island)
                NotchAgentClaudeSeatsCard(snapshot: snapshot, seats: seats, now: now,
                                          display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining, text: text,
                                          columns: NotchAgentSupport.seatColumns(seats.count, width: size.width),
                                          showsAPI: tile.seatsShowAPI, wide: size.width >= NotchAgentSupport.pairWidth)
            } else if tile.claudeAPI {
                NotchAgentClaudeAPICard(snapshot: snapshot, now: now, text: text)
            } else if tile.splitsBilling {
                NotchAgentClaudeBillingCard(snapshot: snapshot, now: now,
                                            display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining, text: text,
                                            wide: size.width >= NotchAgentSupport.pairWidth)
            } else if let provider = tile.provider {
                NotchAgentLimitsCard(provider: provider, snapshot: snapshot, now: now,
                                     display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining, text: text,
                                     account: account(tile, now: now), showsSessions: tile.showsSessions)
            }
        case .spend:
            NotchAgentSpendCard(snapshot: snapshot, providers: providers, text: text, claudeUsesAPI: claudeUsesAPI)
        case .live:
            NotchAgentLiveCard(snapshot: snapshot, providers: providers, text: text)
        case .trend:
            NotchAgentTrendCard(snapshot: snapshot, providers: providers, period: shown, text: text) { period = $0.rawValue }
        case .models:
            NotchAgentShareCard(title: text.modelsCard, symbol: NotchAgentCard.models.symbol,
                                shares: snapshot.usage(shown).models, byCost: showsCost(snapshot.usage(shown)), text: text)
        case .projects:
            NotchAgentShareCard(title: text.projectsCard, symbol: NotchAgentCard.projects.symbol,
                                shares: snapshot.usage(shown).projects, byCost: showsCost(snapshot.usage(shown)), text: text)
        case .activity:
            NotchAgentActivityCard(snapshot: snapshot, text: text, compact: tile.paired)
        case .resets:
            NotchAgentResetsCard(now: now, text: text, showsDefaultAccount: tile.namesDefaultAccount)
        }
    }

    private func showsCost(_ usage: AgentPeriodUsage) -> Bool { usage.fullyPriced }

    private func account(_ tile: NotchAgentTile, now: Date) -> NotchAgentAccount? {
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
}

extension EnvironmentValues {
    /// The AI cards on the lock screen, with what they keep back; nil in the
    /// island and in Settings.
    var notchAgentsLockScreen: NotchAgentPrivacy? {
        get { self[NotchAgentsLockScreenKey.self] }
        set { self[NotchAgentsLockScreenKey.self] = newValue }
    }
}

private struct NotchAgentsLockScreenKey: EnvironmentKey {
    static let defaultValue: NotchAgentPrivacy? = nil
}

/// An amount of money, which a lock screen set to hide amounts redacts.
private struct NotchAgentAmount: ViewModifier {
    @Environment(\.notchAgentsLockScreen) private var lockScreen

    func body(content: Content) -> some View {
        content.privacySensitive(lockScreen?.hidesAmounts == true)
    }
}

private extension View {
    func agentAmount() -> some View { modifier(NotchAgentAmount()) }
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

/// An added Codex home's card: only its own checks, never the reading the
/// logs give the provider's other account, even when its check failed.
struct NotchAgentAccount {
    let name: String
    let limits: AgentLimits?
    let plan: String?
    let checking: Bool
    let failure: String?
    let refreshHint: String
    let checkLabel: String
    let refresh: () -> Void
}

struct NotchAgentLimitsCard: View {
    let provider: AgentProvider
    let snapshot: AgentUsageSnapshot
    let now: Date
    let display: NotchAgentLimitDisplay
    let text: NotchAgentStrings
    var account: NotchAgentAccount? = nil
    /// Its sessions' row under the meters; the page sizes the card for it.
    var showsSessions = false
    @Environment(\.notchAgentsLockScreen) private var lockScreen
    @ObservedObject private var l10n = L10n.shared
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
        let session = all.first { $0.kind == .session }
        let longer = all.filter { $0.kind != .session }.max { $0.usedPercent < $1.usedPercent }
        return [session, longer].compactMap { $0 }
    }

    var body: some View {
        let windows = windows
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                // A profile is often named after its owner, so the lock
                // screen keeps it to the agent's name.
                NotchAgentCardHeader(title: account.flatMap { lockScreen == nil ? provider.displayName + " · " + $0.name : nil }
                                        ?? provider.displayName,
                                     symbol: provider.symbol, tint: provider.tint, provider: provider) {
                    HStack(spacing: 4) {
                        if let account {
                            if let plan = account.plan { NotchAgentChip(text: plan, tint: provider.tint) }
                            // A check waiting its turn shows as one under way.
                            if account.checking {
                                ProgressView().controlSize(.mini).scaleEffect(0.65).frame(width: 12, height: 12)
                            } else if lockScreen == nil {
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
                    if provider == .claude {
                        planValue(weekly: windows.count > 1)
                    } else if windows.count == 1 {
                        caption
                    }
                }
                if showsSessions {
                    Spacer(minLength: 0)
                    NotchAgentSessionRow(provider: provider, snapshot: snapshot, text: text)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// With a weekly limit beside the session, the plan's value this month
    /// fits in a line; a plan with only the session gets the open window's
    /// value and the month's on rows of their own.
    @ViewBuilder private func planValue(weekly: Bool) -> some View {
        let places = FeatureStrings.notchAgentPlaces(l10n.language)
        let month = NotchAgentSupport.claudePlanMonth(snapshot, splitsBilling: false, now: now)
        if weekly {
            Text(places.monthCaption(AgentFormat.cost(month)))
                .agentAmount()
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        } else {
            NotchAgentAmountRow(label: places.thisSession,
                                value: NotchAgentSupport.claudeSessionValue(snapshot, splitsBilling: false))
            NotchAgentAmountRow(label: places.thisMonth, value: month)
        }
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

    private func row(_ window: AgentLimitWindow) -> some View {
        NotchAgentLimitRow(window: window, provider: provider, now: now, display: display, text: text,
                           observedAt: limits?.observedAt)
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
                    Label(AgentFormat.resetTime(block.end, now: now, locale: locale), systemImage: "arrow.clockwise")
                        .labelStyle(NotchAgentInlineLabel())
                        .font(.system(size: 9.5))
                        .foregroundStyle(agentResetTint)
                    Spacer(minLength: 2)
                    Text(AgentFormat.cost(block.totals.cost))
                        .agentAmount()
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
                            .agentAmount()
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

/// The sessions one place runs for an agent, under the limits that pay for
/// them: a row each, longest running first, and one row saying so when none
/// does. The page grows the card to fit them.
private struct NotchAgentSessionSlot: View {
    let provider: AgentProvider
    let place: AgentSessionPlace
    let sessions: [AgentLiveSession]
    /// The session whose time the closed island shows.
    let timed: String?
    /// An API key pays for these sessions, so each says what it cost.
    var showsCost = false
    /// The Claude seat each session runs under, named in its line.
    var seat: ((AgentLiveSession) -> String?)? = nil
    let text: NotchAgentStrings
    @ObservedObject private var l10n = L10n.shared

    static let rowHeight = NotchAgentSupport.sessionRowHeight

    var body: some View {
        let places = FeatureStrings.notchAgentPlaces(l10n.language)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                NotchAgentPlaceIcon(place: place, provider: provider, size: 9, tint: .white.opacity(0.5))
                Text((place == .app ? places.inApp(provider) : places.inTerminal).uppercased())
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if !sessions.isEmpty {
                    Text("\(sessions.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(provider.tint)
                    NotchAgentPulse(tint: provider.tint, size: 5)
                }
            }
            if sessions.isEmpty {
                Text(places.noSessions)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Self.rowHeight)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 0) {
                        ForEach(sessions) { row($0, now: context.date, places: places) }
                    }
                }
            }
        }
    }

    private func row(_ session: AgentLiveSession, now: Date, places: NotchAgentPlaceStrings) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(session.project.isEmpty ? provider.displayName : session.project)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if session.id == timed {
                        Text(places.inIsland.uppercased())
                            .font(.system(size: 6.5, weight: .bold))
                            .tracking(0.3)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                }
                Text(detail(session))
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(AgentFormat.clock(now.timeIntervalSince(session.started)))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(provider.tint)
                .lineLimit(1)
        }
        .frame(height: Self.rowHeight)
    }

    private func detail(_ session: AgentLiveSession) -> String {
        [seat?(session) ?? "", AgentPricing.displayName(session.model),
         session.tokens.output > 0 ? text.written(AgentFormat.tokens(session.tokens.output)) : "",
         showsCost && session.cost > 0 ? AgentFormat.cost(session.cost) : ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Where an agent's sessions run, side by side under its limits: the app
/// and the terminal for Claude, the app alone for Codex unless its command
/// line is working too.
private struct NotchAgentSessionRow: View {
    let provider: AgentProvider
    let snapshot: AgentUsageSnapshot
    let text: NotchAgentStrings

    var body: some View {
        let working = snapshot.working(provider)
        let places = NotchAgentSupport.sessionPlaces(provider, live: snapshot.live)
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(places.enumerated()), id: \.offset) { index, place in
                    if index > 0 { Rectangle().fill(.white.opacity(0.1)).frame(width: 1).frame(maxHeight: .infinity) }
                    NotchAgentSessionSlot(provider: provider, place: place, sessions: working.filter { $0.place == place },
                                          timed: snapshot.live.first?.id, text: text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// An amount at API prices beside its label, in spending's colors; grey
/// while there is nothing to count.
private struct NotchAgentAmountRow: View {
    let label: String
    let value: Double?

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(value == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white.opacity(0.85)))
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(value.map { AgentFormat.cost($0) } ?? AgentFormat.cost(0))
                .agentAmount()
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(value.map { agentSpendTint($0) } ?? Color.secondary)
                .lineLimit(1)
                .contentTransition(.numericText())
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

/// One allowance: what it covers, when it renews, and how much is left.
private struct NotchAgentLimitRow: View {
    let window: AgentLimitWindow
    let provider: AgentProvider
    let now: Date
    let display: NotchAgentLimitDisplay
    let text: NotchAgentStrings
    let observedAt: Date?
    @Environment(\.locale) private var locale

    /// A usage-based forecast would read as a promise, so a row says only
    /// what is spent and when the window renews.
    var body: some View {
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
                    if let resets = AgentLimitSupport.displayedReset(window, now: now) {
                        Label((window.estimatedResetsAt == nil ? "" : "≈ ")
                              + AgentFormat.resetTime(resets, now: now, locale: locale),
                              systemImage: "arrow.clockwise")
                            .labelStyle(NotchAgentInlineLabel())
                            .foregroundStyle(agentResetTint)
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

    private func help(_ window: AgentLimitWindow) -> String {
        var parts = [label(window), text.usedShare(AgentFormat.percent(window.usedFraction)),
                     text.left(AgentFormat.percent(window.remainingFraction))]
        if let resets = AgentLimitSupport.displayedReset(window, now: now) {
            parts.append(resets.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(AgentFormat.resetClock(locale))))
            if window.estimatedResetsAt != nil { parts.append(text.estimated) }
        }
        if let observed = observedAt, now.timeIntervalSince(observed) > 600 {
            parts.append(text.updated(observed.formatted(.relative(presentation: .named).locale(locale))))
        }
        return parts.joined(separator: " · ")
    }
}

/// Claude when the plan and an API key pay for different work: the plan's
/// limits, which the Claude app's chats spend, beside what Claude Code's
/// sessions took from the API credits.
struct NotchAgentClaudeBillingCard: View {
    let snapshot: AgentUsageSnapshot
    let now: Date
    let display: NotchAgentLimitDisplay
    let text: NotchAgentStrings
    /// Halves side by side; one above the other where cards do not pair.
    let wide: Bool
    /// The sessions under the plan and the API key; the lock screen lists
    /// them in Agents at work instead.
    var showsSessions = true
    @ObservedObject private var l10n = L10n.shared

    private let provider = AgentProvider.claude
    private var billing: ClaudeBillingStrings { FeatureStrings.claudeBilling(l10n.language) }

    private var limits: AgentLimits? { snapshot.limits[.claude] }

    private var stale: Bool {
        NotchAgentSupport.limitsAreStale(limits, provider: provider, account: false, now: now)
    }

    /// The session and whichever longer window binds first, as on the usual card.
    private var windows: [AgentLimitWindow] {
        let all = (limits?.windows ?? []).map { AgentLimitSupport.current($0, at: now) }
        let session = all.first { $0.kind == .session }
        let longer = all.filter { $0.kind != .session }.max { $0.usedPercent < $1.usedPercent }
        return [session, longer].compactMap { $0 }
    }

    var body: some View {
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: provider.displayName, symbol: provider.symbol, tint: provider.tint,
                                     provider: provider) {
                    if let plan = snapshot.plans[provider] { NotchAgentChip(text: plan.name, tint: provider.tint) }
                }
                let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                layout {
                    subscription.frame(maxWidth: .infinity, alignment: .topLeading)
                    if wide {
                        Rectangle().fill(.white.opacity(0.1)).frame(width: 1).frame(maxHeight: .infinity)
                    }
                    NotchAgentClaudeAPIFigures(snapshot: snapshot, now: now, text: text)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .fixedSize(horizontal: false, vertical: true)
                if showsSessions {
                    Spacer(minLength: 0)
                    sessions
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The Claude app's sessions under the plan and Claude Code's under the
    /// API key, in one row so both start level.
    private var sessions: some View {
        let working = snapshot.working(provider)
        let timed = snapshot.live.first?.id
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
        return VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            layout {
                NotchAgentSessionSlot(provider: provider, place: .app, sessions: working.filter { $0.place == .app },
                                      timed: timed, text: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if wide {
                    Rectangle().fill(.white.opacity(0.1)).frame(width: 1).frame(maxHeight: .infinity)
                }
                NotchAgentSessionSlot(provider: provider, place: .terminal,
                                      sessions: working.filter { $0.place == .terminal },
                                      timed: timed, showsCost: true, text: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// With a weekly limit the meters fill the column, and the plan's value
    /// this month moves to the section's line; otherwise the open window's
    /// value and the month's take rows of their own.
    private var weekly: Bool { windows.count > 1 }

    private var planMonth: Double {
        NotchAgentSupport.claudePlanMonth(snapshot, splitsBilling: true, now: now)
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 8.5, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }

    private var subscription: some View {
        let places = FeatureStrings.notchAgentPlaces(l10n.language)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                section(billing.subscription)
                Spacer(minLength: 2)
                if weekly {
                    Text(places.monthCaption(AgentFormat.cost(planMonth)))
                        .agentAmount()
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            if windows.isEmpty {
                Text(billing.noLimits)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 5) {
                    ForEach(windows) { window in
                        NotchAgentLimitRow(window: window, provider: provider, now: now, display: display, text: text,
                                           observedAt: limits?.observedAt)
                    }
                }
                .opacity(stale ? 0.6 : 1)
            }
            if !weekly {
                NotchAgentAmountRow(label: places.thisSession,
                                    value: NotchAgentSupport.claudeSessionValue(snapshot, splitsBilling: true))
                NotchAgentAmountRow(label: places.thisMonth, value: planMonth)
            }
        }
    }

}

/// The API key's spending: today, this calendar month and what is left of
/// the balance entered, on Claude's split card and its own half card.
private struct NotchAgentClaudeAPIFigures: View {
    let snapshot: AgentUsageSnapshot
    let now: Date
    let text: NotchAgentStrings
    /// The split card names its half; the half card's header already does.
    var showsSection = true
    @ObservedObject private var l10n = L10n.shared
    // Read so a balance saved in Settings redraws the card.
    @AppStorage(DefaultsKey.notchAgentsClaudeCredits) private var balance = 0.0
    @AppStorage(DefaultsKey.notchAgentsClaudeCreditsSince) private var since = 0.0
    @Environment(\.locale) private var locale

    private let provider = AgentProvider.claude
    private var billing: ClaudeBillingStrings { FeatureStrings.claudeBilling(l10n.language) }

    var body: some View { api }

    /// Today and this calendar month from the days the summary keeps, so a
    /// month's first days are never mixed with the last one's.
    private var api: some View {
        let calendar = Calendar.autoupdatingCurrent
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        let days = snapshot.days
        let monthDays = days.filter { $0.start >= month }
        let today = days.last.flatMap { calendar.isDate($0.start, inSameDayAs: now) ? $0 : nil }
        return VStack(alignment: .leading, spacing: 4) {
            if showsSection {
                Text(billing.api.uppercased())
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            figure(text.period(.today), cost(today.map { [$0] } ?? []))
            figure(billing.thisMonth, cost(monthDays))
            credits(days: days)
        }
    }

    /// Only Claude Code outside the Claude app: the plan pays for the app's
    /// sessions, and the Spending card counts everything.
    private func cost(_ days: [AgentBucket]) -> String {
        let totals = days.map(\.claudeAPI)
        let spent = totals.reduce(0) { $0 + $1.cost }
        return (totals.contains { $0.unpriced > 0 } ? "≥ " : "") + AgentFormat.cost(spent)
    }

    private func figure(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(value)
                .agentAmount()
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .help(text.valueNote)
    }

    /// What is left of the balance entered, or where to enter it.
    @ViewBuilder private func credits(days: [AgentBucket]) -> some View {
        let _ = (balance, since)
        if let stored = AgentClaudeCredits.stored(), let left = stored.remaining(days: days),
           let fraction = stored.remainingFraction(days: days) {
            let tint = agentLimitTint(provider, usedFraction: 1 - fraction)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(billing.credits)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.green)
                    Spacer(minLength: 2)
                    Text("~ " + AgentFormat.cost(max(0, left)))
                        .agentAmount()
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint == provider.tint ? Color.green : tint)
                }
                NotchAgentMeter(value: fraction, tint: tint, height: 4)
            }
            .help(billing.creditsLeft(AgentFormat.cost(max(0, left)),
                                      since: stored.since.formatted(.relative(presentation: .named).locale(locale))))
        } else {
            Button {
                NotchService.shared.openSettings(showing: .agents)
            } label: {
                Label(billing.addCredits, systemImage: "arrow.up.forward")
                    .labelStyle(NotchAgentInlineLabel())
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(provider.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Claude's seats side by side, each with its session, its renewal and what
/// the Claude app's work under it is worth; the sessions running under them
/// below. The seat the Claude app uses wears a dot.
struct NotchAgentClaudeSeatsCard: View {
    let snapshot: AgentUsageSnapshot
    /// The seats this place shows, in the person's order.
    let seats: [ClaudeSeat]
    let now: Date
    let display: NotchAgentLimitDisplay
    let text: NotchAgentStrings
    /// Seats a row; one means they stack, as every card does where cards
    /// do not pair.
    let columns: Int
    /// The API key's figures in the header.
    var showsAPI = false
    /// The lock screen lists the sessions in Agents at work instead.
    var showsSessions = true
    /// The sessions' slots side by side.
    var wide = true
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsClaudeOrgLabel) private var organization = ""

    private let provider = AgentProvider.claude
    private var seatText: ClaudeSeatStrings { FeatureStrings.claudeSeats(l10n.language) }

    var body: some View {
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                header
                if !seats.isEmpty { grid }
                if showsSessions {
                    Spacer(minLength: 0)
                    sessions
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Claude's mark with the organization and plan, and the API key's
    /// figures on the right, or on a line of their own where seats stack.
    @ViewBuilder private var header: some View {
        let chips = HStack(spacing: 6) {
            NotchAgentMark(provider: provider, size: 13, tint: provider.tint)
                .frame(width: 17, height: 17)
                .accessibilityLabel(seatText.subscriptionTitle)
            let label = organization.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty { NotchAgentChip(text: label, tint: NotchTopBarPalette.yellow) }
            if let plan = (seats.first(where: \.active) ?? snapshot.activeClaudeSeat)?.plan {
                NotchAgentChip(text: plan, tint: provider.tint)
            }
        }
        if showsAPI && columns == 1 && !wide {
            VStack(alignment: .leading, spacing: 4) {
                chips.frame(height: 17)
                NotchAgentClaudeAPIPill(snapshot: snapshot, now: now, text: text)
            }
        } else {
            HStack(spacing: 6) {
                chips
                Spacer(minLength: 4)
                if showsAPI { NotchAgentClaudeAPIPill(snapshot: snapshot, now: now, text: text) }
            }
            .frame(height: 17)
        }
    }

    /// The seats in rows of `columns`, a line between each.
    private var grid: some View {
        let rows = stride(from: 0, to: seats.count, by: max(1, columns)).map {
            Array(seats[$0..<min($0 + max(1, columns), seats.count)])
        }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<max(1, columns), id: \.self) { slot in
                        if slot > 0 {
                            Rectangle().fill(.white.opacity(slot < row.count ? 0.1 : 0)).frame(width: 1)
                                .frame(maxHeight: .infinity)
                        }
                        if slot < row.count {
                            NotchAgentClaudeSeatColumn(seat: row[slot], now: now, display: display, text: text)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The Claude app's sessions, each naming its seat, and Claude Code's
    /// elsewhere, in one row so both start level.
    private var sessions: some View {
        let working = snapshot.working(provider)
        let timed = snapshot.live.first?.id
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
        return VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            layout {
                NotchAgentSessionSlot(provider: provider, place: .app, sessions: working.filter { $0.place == .app },
                                      timed: timed, seat: { snapshot.claudeSeat(for: $0)?.email }, text: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if wide {
                    Rectangle().fill(.white.opacity(0.1)).frame(width: 1).frame(maxHeight: .infinity)
                }
                NotchAgentSessionSlot(provider: provider, place: .terminal,
                                      sessions: working.filter { $0.place == .terminal },
                                      timed: timed, showsCost: AgentClaudeBilling.usesAPI(), text: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One seat: its email, its session's meter and renewal, and the Claude
/// app's work under it this session and this month, or what keeps it from
/// showing them.
private struct NotchAgentClaudeSeatColumn: View {
    let seat: ClaudeSeat
    let now: Date
    let display: NotchAgentLimitDisplay
    let text: NotchAgentStrings
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.locale) private var locale
    /// The lock screen's widget has no room for a note under the meter.
    @Environment(\.notchAgentsLockScreen) private var lockScreen

    private let provider = AgentProvider.claude
    private var seats: ClaudeSeatStrings { FeatureStrings.claudeSeats(l10n.language) }

    private var session: AgentLimitWindow? {
        seat.limits?.windows.first { $0.kind == .session && $0.scope == nil }.map { AgentLimitSupport.current($0, at: now) }
    }

    private var stale: Bool {
        NotchAgentSupport.limitsAreStale(seat.limits, provider: provider, account: true, now: now)
    }

    var body: some View {
        let places = FeatureStrings.notchAgentPlaces(l10n.language)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if seat.active {
                    Circle().fill(provider.tint).frame(width: 6, height: 6)
                        .background(Circle().fill(provider.tint.opacity(0.22)).padding(-2))
                        .help(seats.activeHelp)
                        .accessibilityLabel(seats.activeHelp)
                }
                Text(seat.email.isEmpty ? seats.notSignedIn : seat.email)
                    .font(.system(size: 10.5, weight: seat.active ? .semibold : .medium))
                    .foregroundStyle(seat.active ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(seat.email)
            }
            if seat.failure == .needsSignIn || seat.account == nil {
                signIn
            } else {
                limit
                if lockScreen == nil, let note {
                    Text(note)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                NotchAgentAmountRow(label: places.thisSession, value: seat.sessionValue)
                NotchAgentAmountRow(label: places.thisMonth, value: seat.monthValue)
            }
        }
    }

    /// The open session's meter, a quiet empty one while none is open, or a
    /// moving one through the first check.
    @ViewBuilder private var limit: some View {
        if let session {
            NotchAgentLimitRow(window: session, provider: provider, now: now, display: display, text: text,
                               observedAt: seat.limits?.observedAt)
                .opacity(stale ? 0.6 : 1)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(text.session)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    if seat.checking && seat.limits == nil {
                        Text(seats.checking).font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 2)
                    Text(seat.limits == nil ? "–" : AgentFormat.percent(display == .remaining ? 1 : 0))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                NotchAgentMeter(value: display == .remaining && seat.limits != nil ? 1 : 0, tint: provider.tint,
                                height: 4, dimmed: true)
            }
        }
    }

    /// Why the numbers may be behind: a check that failed, an old reading,
    /// or no session open yet.
    private var note: String? {
        switch seat.failure {
        case .missing?: return seats.missing
        case .outdated?: return seats.outdated
        case .unreachable? where seat.limits == nil || stale: return seats.failed
        default: break
        }
        if stale, let checked = seat.checked {
            return text.updated(checked.formatted(.relative(presentation: .named).locale(locale)))
        }
        if session == nil, seat.limits != nil { return seats.noSession }
        return nil
    }

    /// The command that signs the seat in again, to copy or run in Terminal.
    private var signIn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(seats.signInNeeded, systemImage: "exclamationmark.triangle.fill")
                .labelStyle(NotchAgentInlineLabel())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
            Text(seat.signInCommand)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .help(seat.signInCommand)
            HStack(spacing: 8) {
                Button(seats.copyCommand) { ClaudeSeatActions.copy(seat.signInCommand) }
                Button(seats.openTerminal) { ClaudeSeatActions.openTerminal() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(provider.tint)
        }
    }
}

/// The API key's half of Claude's card on its own, while the island leaves
/// Claude's plan out.
struct NotchAgentClaudeAPICard: View {
    let snapshot: AgentUsageSnapshot
    let now: Date
    let text: NotchAgentStrings
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let provider = AgentProvider.claude
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: FeatureStrings.claudeSeats(l10n.language).apiTitle, symbol: provider.symbol,
                                     tint: provider.tint, provider: provider) { EmptyView() }
                NotchAgentClaudeAPIFigures(snapshot: snapshot, now: now, text: text, showsSection: false)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The API key's figures in the seats' card header: today, this month and
/// what is left of the credits entered, in one pill whose label stands out
/// from the organization and plan chips beside it.
private struct NotchAgentClaudeAPIPill: View {
    let snapshot: AgentUsageSnapshot
    let now: Date
    let text: NotchAgentStrings
    @ObservedObject private var l10n = L10n.shared
    // Read so a balance saved in Settings redraws the pill.
    @AppStorage(DefaultsKey.notchAgentsClaudeCredits) private var balance = 0.0
    @AppStorage(DefaultsKey.notchAgentsClaudeCreditsSince) private var since = 0.0

    static let tint = Color(red: 0x64 / 255, green: 0xD2 / 255, blue: 1)

    var body: some View {
        let _ = (balance, since)
        let billing = FeatureStrings.claudeBilling(l10n.language)
        let strings = FeatureStrings.limitVisibility(l10n.language)
        let calendar = Calendar.autoupdatingCurrent
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        let days = snapshot.days
        let today = days.last.flatMap { calendar.isDate($0.start, inSameDayAs: now) ? [$0] : nil } ?? []
        let left = AgentClaudeCredits.stored()?.remaining(days: days)
        HStack(spacing: 6) {
            Text(billing.api.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Self.tint, in: Capsule(style: .continuous))
            figure(text.period(.today), cost(today))
            divider
            figure(strings.apiMonth, cost(days.filter { $0.start >= month }))
            if let left {
                divider
                Text(strings.creditsLeft(AgentFormat.cost(max(0, left))))
                    .agentAmount()
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.green)
            }
        }
        .lineLimit(1)
        .padding(.leading, 3)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(Self.tint.opacity(0.1), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Self.tint.opacity(0.35), lineWidth: 0.5))
        .fixedSize()
        .help(text.valueNote)
    }

    private var divider: some View { Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 10) }

    private func figure(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 9.5)).foregroundStyle(.secondary)
            Text(value)
                .agentAmount()
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.numericText())
        }
    }

    /// Only Claude Code outside the Claude app, as the API card counts it.
    private func cost(_ days: [AgentBucket]) -> String {
        let totals = days.map(\.claudeAPI)
        return (totals.contains { $0.unpriced > 0 } ? "≥ " : "") + AgentFormat.cost(totals.reduce(0) { $0 + $1.cost })
    }
}

// MARK: Spending

/// Every agent's work at API prices since the ledger began, whatever period
/// the island's top row shows, colored by how much it is, with the models
/// that did most of it under it. The plan multiples stay on thirty days.
private struct NotchAgentSpendCard: View {
    let snapshot: AgentUsageSnapshot
    let providers: [AgentProvider]
    let text: NotchAgentStrings
    /// Claude Code's spending was paid from API credits, not the plan.
    var claudeUsesAPI = false
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        var lifetime = AgentPeriodUsage()
        for provider in providers {
            guard let totals = snapshot.lifetime.byProvider[provider] else { continue }
            lifetime.total += totals
            lifetime.byProvider[provider] = totals
        }
        lifetime.models = snapshot.lifetime.models.filter { $0.provider.map(providers.contains) ?? false }
        let thirty = snapshot.usage(.month)
        let places = FeatureStrings.notchAgentPlaces(l10n.language)
        return NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 5) {
                NotchAgentCardHeader(title: text.spendCard, symbol: NotchAgentCard.spend.symbol) {
                    multiples(thirty)
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text((lifetime.fullyPriced ? "" : "≥ ") + AgentFormat.cost(lifetime.total.cost))
                        .agentAmount()
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(agentSpendTint(lifetime.total.cost))
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(places.allAgentsLifetime)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .help(lifetime.fullyPriced ? text.valueNote : text.unpriced)
                split(lifetime)
                models(lifetime)
            }
        }
    }

    /// The top three models, as the Models card listed them.
    @ViewBuilder private func models(_ usage: AgentPeriodUsage) -> some View {
        let shown = Array(usage.models.prefix(3))
        let byCost = usage.fullyPriced
        let peak = shown.map { $0.totals.weight(byCost: byCost) }.max() ?? 0
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(text.modelsCard.uppercased())
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                ForEach(shown) { share in
                    HStack(spacing: 6) {
                        Text(share.name)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .frame(width: 70, alignment: .leading)
                        NotchAgentMeter(value: peak > 0 ? share.totals.weight(byCost: byCost) / peak : 0,
                                        tint: share.provider?.tint ?? .white, height: 3)
                        Text(byCost ? AgentFormat.cost(share.totals.cost) : AgentFormat.tokens(share.totals.tokens.total))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .lineLimit(1)
                            .frame(minWidth: 34, alignment: .trailing)
                    }
                }
            }
        }
    }

    /// Thirty days of API value against a plan's monthly price.
    @ViewBuilder private func multiples(_ usage: AgentPeriodUsage) -> some View {
        HStack(spacing: 3) {
            ForEach(providers) { provider in
                if !(provider == .claude && claudeUsesAPI),
                   let plan = snapshot.plans[provider], let price = plan.monthlyPrice, price > 0,
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
    /// The card picks the period itself; the cards that follow it change too.
    let choose: (AgentPeriod) -> Void
    @State private var hovered: Date?
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var buckets: [AgentBucket] {
        period == .today ? snapshot.hours : Array(snapshot.days.suffix(period.days))
    }

    var body: some View {
        let byCost = snapshot.usage(period).fullyPriced
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                // Half a row has no room for the reading beside the picker:
                // it takes a line of its own, so a pointed-at bar reads whole.
                ViewThatFits(in: .horizontal) {
                    NotchAgentCardHeader(title: text.trendCard, symbol: NotchAgentCard.trend.symbol) {
                        periodPicker
                        captionText(byCost: byCost)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        NotchAgentCardHeader(title: text.trendCard, symbol: NotchAgentCard.trend.symbol) { periodPicker }
                        captionText(byCost: byCost)
                    }
                }
                NotchAgentBars(buckets: buckets, providers: providers, byCost: byCost, hovered: $hovered)
                axis
            }
        }
    }

    /// Today, 7 days and 30 days as small segments; the chosen one is filled.
    private var periodPicker: some View {
        HStack(spacing: 1) {
            ForEach(AgentPeriod.allCases, id: \.self) { option in
                let selected = option == period
                Button {
                    hovered = nil
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { choose(option) }
                } label: {
                    Text(text.period(option))
                        .font(.system(size: 9.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? .black : .white.opacity(0.6))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .frame(height: 17)
                        .background(selected ? AnyShapeStyle(NotchTopBarPalette.clay) : AnyShapeStyle(.clear), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: 9, lifts: false))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(1.5)
        .background(.white.opacity(0.07), in: Capsule())
    }

    private func captionText(byCost: Bool) -> some View {
        Text(caption(byCost: byCost))
            .font(.system(size: 9.5, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func caption(byCost: Bool) -> String {
        if let hovered, let bucket = buckets.first(where: { $0.start == hovered }) {
            // A pointed-at bar reads its tokens beside its cost.
            let tokens = byCost ? " · " + value(bucket.total, byCost: false) : ""
            return label(bucket.start, long: true) + " · " + value(bucket.total, byCost: byCost) + tokens
        }
        // The picker names the period, so the caption gives its total alone.
        return value(snapshot.usage(period).total, byCost: byCost)
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
    let text: NotchAgentStrings
    /// Half a row: the map takes the card's width, the figures a line under it.
    var compact = false
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
                if compact {
                    NotchAgentHeatmap(days: snapshot.days, byCost: byCost, hovered: $hovered)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    line(byCost: byCost)
                } else {
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
    }

    /// The map's total, and its active days or the hovered day's value.
    private func line(byCost: Bool) -> some View {
        let pointed = hovered.flatMap { date in snapshot.days.first { $0.start == date } }
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value(snapshot.days.reduce(into: AgentTotals()) { $0 += $1.total }, byCost: byCost))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            Text(AgentFormat.span(days: snapshot.days.count, locale: locale))
                .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Group {
                if let day = pointed {
                    Text(day.start.formatted(.dateTime.day().month(.abbreviated).locale(locale)) + " · "
                         + value(day.total, byCost: byCost))
                } else {
                    Text(text.activeDays + " " + "\(snapshot.days.filter { $0.total.requests > 0 }.count)")
                }
            }
            .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
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
