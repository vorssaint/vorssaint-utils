// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The AI page, laid out the same way every time: Claude's limits across the
/// top, Trend and Spending side by side as squares, and the year's activity
/// under them.
struct NotchAgentsView: View {
    let size: CGSize
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchSettingsPreview) private var preview
    @AppStorage(DefaultsKey.notchAgentsPeriod) private var period = AgentPeriod.today.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsClaudeBilling) private var billing = AgentClaudeBilling.automatic.rawValue
    @AppStorage(DefaultsKey.notchAgentsIslandHiddenAccounts) private var hiddenAccounts = ""
    @AppStorage(DefaultsKey.notchAgentsIslandHiddenProfiles) private var hiddenProfiles = ""

    private var text: NotchAgentStrings { FeatureStrings.notchAgents(l10n.language) }
    private var chosenPeriod: AgentPeriod { AgentPeriod(rawValue: period) ?? .today }

    /// Claude gets the page once it left something on this Mac, or once
    /// seats are added.
    private var shows: Bool {
        usage.snapshot.seen.contains(.claude) || !usage.snapshot.claudeSeats.isEmpty
    }

    /// Whether an API key pays for Claude Code.
    private var apiPays: Bool {
        _ = billing
        return AgentClaudeBilling.usesAPI()
    }

    /// The API key's spending beside the plan's limits, unless the island
    /// leaves it out.
    private var showsAPI: Bool {
        _ = hiddenAccounts
        return apiPays && NotchLimitVisibility.shows(.claudeAPI, in: .island)
    }

    /// The seats the island keeps, in the person's order; nil without any.
    private var seats: [ClaudeSeat]? {
        _ = hiddenProfiles
        return usage.snapshot.claudeSeats.isEmpty ? nil : NotchLimitVisibility.seats(usage.snapshot, in: .island)
    }

    var body: some View {
        Group {
            if !usage.snapshot.loaded {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(text.loading).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !shows {
                NotchEmptyView(symbol: "sparkles", message: text.empty)
            } else {
                let seats = seats
                let layout = NotchAgentSupport.pageLayout(usage.snapshot, width: size.width, claudeUsesAPI: apiPays)
                TimelineView(.periodic(from: .now, by: 10)) { context in
                    if layout.total > size.height + 0.5 {
                        ScrollView { page(layout, seats: seats, now: context.date) }
                            .scrollIndicators(.automatic)
                    } else {
                        page(layout, seats: seats, now: context.date)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .environment(\.locale, l10n.language.formattingLocale())
        .onAppear { usage.pageDidAppear(preview: preview) }
        .onDisappear {
            guard !preview else { return }
            usage.pageDidDisappear()
        }
    }

    private func page(_ layout: NotchAgentPageLayout, seats: [ClaudeSeat]?, now: Date) -> some View {
        let snapshot = usage.snapshot
        let spacing = NotchAgentSupport.spacing
        return VStack(spacing: spacing) {
            limits(seats: seats, now: now)
                .frame(height: layout.limits)
            HStack(spacing: spacing) {
                NotchAgentTrendCard(snapshot: snapshot, period: chosenPeriod, text: text) { period = $0.rawValue }
                    .frame(width: layout.square, height: layout.square)
                NotchAgentSpendCard(snapshot: snapshot, text: text, claudeUsesAPI: apiPays)
                    .frame(width: layout.square, height: layout.square)
            }
            NotchAgentActivityCard(snapshot: snapshot, now: now,
                                   cell: NotchAgentSupport.activityCell(width: size.width), text: text)
                .frame(height: layout.activity)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// Every seat side by side, or Claude's own limits without seats: beside
    /// the API key's spending when it pays for Claude Code.
    @ViewBuilder private func limits(seats: [ClaudeSeat]?, now: Date) -> some View {
        let snapshot = usage.snapshot
        let shown = NotchAgentLimitDisplay(rawValue: display) ?? .remaining
        let wide = size.width >= NotchAgentSupport.pairWidth
        if let seats {
            NotchAgentClaudeSeatsCard(snapshot: snapshot, seats: seats, now: now, display: shown, text: text,
                                      columns: NotchAgentSupport.seatColumns(seats.count, width: size.width),
                                      showsAPI: showsAPI, wide: wide)
        } else if showsAPI {
            NotchAgentClaudeBillingCard(snapshot: snapshot, now: now, display: shown, text: text, wide: wide)
        } else {
            NotchAgentLimitsCard(snapshot: snapshot, now: now, display: shown, text: text, showsSessions: true)
        }
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

/// Claude's plan limits without seats: the session and the week that binds
/// first, what the plan covered, and, on the page, the sessions it pays for.
struct NotchAgentLimitsCard: View {
    let snapshot: AgentUsageSnapshot
    let now: Date
    let display: NotchAgentLimitDisplay
    let text: NotchAgentStrings
    /// Its sessions' row under the meters; the page sizes the card for it.
    var showsSessions = false
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.locale) private var locale

    private let provider = AgentProvider.claude
    private var limits: AgentLimits? { snapshot.limits[provider] }

    /// A reading from a while ago: still the latest known, shown quieter
    /// until it is checked again.
    private var stale: Bool {
        NotchAgentSupport.limitsAreStale(limits, seat: false, now: now)
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
                    meters(windows)
                    planValue(weekly: windows.count > 1)
                }
                if showsSessions {
                    Spacer(minLength: 0)
                    NotchAgentSessionRow(snapshot: snapshot, text: text)
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
            ForEach(windows) { window in
                NotchAgentLimitRow(window: window, provider: provider, now: now, display: display, text: text,
                                   observedAt: limits?.observedAt)
            }
        }
        .opacity(stale ? 0.6 : 1)
    }

    /// Without a recent reading from the Claude app, the session still ends
    /// five hours after its first request, so the window itself is known.
    @ViewBuilder private var estimate: some View {
        if let block = snapshot.claudeBlock {
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
        } else {
            Text(text.noSession).font(.system(size: 10.5)).foregroundStyle(.secondary)
            setUpLimits
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

/// Where Claude's sessions run, side by side under its limits: the Claude
/// app and the terminal.
private struct NotchAgentSessionRow: View {
    let snapshot: AgentUsageSnapshot
    let text: NotchAgentStrings

    var body: some View {
        let provider = AgentProvider.claude
        let working = snapshot.working(provider)
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(NotchAgentSupport.sessionPlaces.enumerated()), id: \.offset) { index, place in
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
        NotchAgentSupport.limitsAreStale(limits, seat: false, now: now)
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
/// the balance entered, on Claude's split card.
private struct NotchAgentClaudeAPIFigures: View {
    let snapshot: AgentUsageSnapshot
    let now: Date
    let text: NotchAgentStrings
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
            Text(billing.api.uppercased())
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
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

/// One seat: its email, its session's and its week's meters and renewals,
/// and the Claude app's work under it this session and this month, or what
/// keeps it from showing them.
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

    /// The week that binds first, where the plan keeps more than one.
    private var week: AgentLimitWindow? {
        (seat.limits?.windows ?? []).filter { $0.kind == .weekly }.map { AgentLimitSupport.current($0, at: now) }
            .max { $0.usedPercent < $1.usedPercent }
    }

    private var stale: Bool {
        NotchAgentSupport.limitsAreStale(seat.limits, seat: true, now: now)
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
                if let week {
                    NotchAgentLimitRow(window: week, provider: provider, now: now, display: display, text: text,
                                       observedAt: seat.limits?.observedAt)
                        .opacity(stale ? 0.6 : 1)
                }
                if lockScreen == nil, let note {
                    Text(note)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // The lock screen shows no sessions, and its widget has room
                // for the week only in place of this one's amount.
                if lockScreen == nil {
                    NotchAgentAmountRow(label: places.thisSession, value: seat.sessionValue)
                }
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

    /// Only Claude Code outside the Claude app: the plan pays for the app's.
    private func cost(_ days: [AgentBucket]) -> String {
        let totals = days.map(\.claudeAPI)
        return (totals.contains { $0.unpriced > 0 } ? "≥ " : "") + AgentFormat.cost(totals.reduce(0) { $0 + $1.cost })
    }
}

// MARK: Spending

/// Claude's work at API prices since the ledger began, whatever period the
/// island's top row shows, colored by how much it is, with the models that
/// did most of it under it. The plan multiple stays on thirty days.
private struct NotchAgentSpendCard: View {
    let snapshot: AgentUsageSnapshot
    let text: NotchAgentStrings
    /// Claude Code's spending was paid from API credits, not the plan.
    var claudeUsesAPI = false
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let lifetime = snapshot.lifetime
        let places = FeatureStrings.notchAgentPlaces(l10n.language)
        return NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 5) {
                NotchAgentCardHeader(title: text.spendCard, symbol: NotchAgentCard.spend.symbol) {
                    multiple(snapshot.usage(.month))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text((lifetime.fullyPriced ? "" : "≥ ") + AgentFormat.cost(lifetime.total.cost))
                        .agentAmount()
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(agentSpendTint(lifetime.total.cost))
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(places.allTime)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .help(lifetime.fullyPriced ? text.valueNote : text.unpriced)
                models(lifetime)
                Spacer(minLength: 0)
            }
        }
    }

    /// The models that did most of the work.
    @ViewBuilder private func models(_ usage: AgentPeriodUsage) -> some View {
        let shown = Array(usage.models.prefix(4))
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
                                        tint: AgentProvider.claude.tint, height: 3)
                        Text(byCost ? AgentFormat.cost(share.totals.cost) : AgentFormat.tokens(share.totals.tokens.total))
                            .agentAmount()
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .lineLimit(1)
                            .frame(minWidth: 34, alignment: .trailing)
                    }
                }
            }
        }
    }

    /// Thirty days of API value against the plan's monthly price.
    @ViewBuilder private func multiple(_ usage: AgentPeriodUsage) -> some View {
        let provider = AgentProvider.claude
        let spent = usage.total.cost
        if !claudeUsesAPI, let plan = snapshot.plans[provider], let price = plan.monthlyPrice, price > 0, spent > 0 {
            let multiple = (spent / price).formatted(.number.precision(.fractionLength(spent / price < 10 ? 1 : 0))) + "×"
            NotchAgentChip(text: multiple, tint: provider.tint)
                .help(text.planMultiple(multiple, plan: "\(provider.displayName) \(plan.name)"))
        }
    }
}

// MARK: Trend

private struct NotchAgentTrendCard: View {
    let snapshot: AgentUsageSnapshot
    let period: AgentPeriod
    let text: NotchAgentStrings
    /// The card picks the period itself.
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
                NotchAgentBars(buckets: buckets, byCost: byCost, hovered: $hovered)
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

// MARK: Activity

/// The year as GitHub draws contributions: a column a week from Sunday, a
/// cell a day in five greens by what it was worth at API prices, and today
/// outlined. Pointing at a day names it and its value.
private struct NotchAgentActivityCard: View {
    let snapshot: AgentUsageSnapshot
    let now: Date
    /// A day's side, so the year fills the card's width.
    let cell: CGFloat
    let text: NotchAgentStrings
    @Environment(\.locale) private var locale

    /// GitHub's ramp: a day with nothing, then its four greens.
    static let levels: [Color] = [
        .white.opacity(0.08),
        Color(red: 0x0E / 255, green: 0x44 / 255, blue: 0x29 / 255),
        Color(red: 0x00 / 255, green: 0x6D / 255, blue: 0x32 / 255),
        Color(red: 0x26 / 255, green: 0xA6 / 255, blue: 0x41 / 255),
        Color(red: 0x39 / 255, green: 0xD3 / 255, blue: 0x53 / 255)
    ]

    var body: some View {
        let grid = NotchAgentSupport.activityGrid(snapshot.year, now: now)
        let gap = NotchAgentSupport.activityGap
        let pitch = cell + gap
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: text.activityCard, symbol: NotchAgentCard.activity.symbol) {
                    Text(text.yearTotal(AgentFormat.cost(grid.total, locale: locale)))
                        .agentAmount()
                        .font(.system(size: 9.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 3) {
                    months(grid, pitch: pitch)
                    HStack(alignment: .top, spacing: 0) {
                        weekdays(pitch: pitch)
                            .frame(width: NotchAgentSupport.activityLabelWidth, alignment: .leading)
                        HStack(alignment: .top, spacing: gap) {
                            ForEach(grid.weeks.indices, id: \.self) { column in
                                VStack(spacing: gap) {
                                    ForEach(0..<7, id: \.self) { row in day(grid.weeks[column][row]) }
                                }
                            }
                        }
                    }
                }
                legend(grid)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Each month's name over the first week that begins in it.
    private func months(_ grid: NotchAgentActivityGrid, pitch: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(grid.months, id: \.column) { month in
                Text(month.start.formatted(.dateTime.month(.abbreviated).locale(locale)))
                    .fixedSize()
                    .offset(x: CGFloat(month.column) * pitch)
            }
        }
        .font(.system(size: 8.5, weight: .medium))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 11, alignment: .topLeading)
        .padding(.leading, NotchAgentSupport.activityLabelWidth)
    }

    /// Mon, Wed and Fri beside their rows, as GitHub names them.
    private func weekdays(pitch: CGFloat) -> some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let names = calendar.shortWeekdaySymbols
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<7, id: \.self) { row in
                Text(row % 2 == 1 && row < names.count ? names[row] : "")
                    .frame(height: pitch, alignment: .leading)
            }
        }
        .font(.system(size: 8.5, weight: .medium))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }

    @ViewBuilder private func day(_ day: NotchAgentActivityGrid.Day?) -> some View {
        let radius = min(2, cell / 4)
        if let day {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Self.levels[min(Self.levels.count - 1, max(0, day.level))])
                .overlay {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(.white.opacity(0.85), lineWidth: 1)
                    }
                }
                .frame(width: cell, height: cell)
                .help(day.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year().locale(locale))
                      + " · " + AgentFormat.cost(day.cost, locale: locale))
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }

    /// The year's active days on the left, the ramp on the right.
    private func legend(_ grid: NotchAgentActivityGrid) -> some View {
        HStack(spacing: 4) {
            Text(text.activeDays + " " + grid.activeDays.formatted(.number.locale(locale)))
            Spacer(minLength: 4)
            Text(text.less)
            ForEach(Self.levels.indices, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.levels[level])
                    .frame(width: 9, height: 9)
            }
            Text(text.more)
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(height: 13)
    }
}
