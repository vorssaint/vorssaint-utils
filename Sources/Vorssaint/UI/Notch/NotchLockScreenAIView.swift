// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The AI rail's colors for each agent's readings on the lock screen's
/// violet: its own color, lightened to read as type.
private extension AgentProvider {
    var lockScreenTint: Color {
        switch self {
        case .claude: return Color(red: 0xEB / 255, green: 0xA1 / 255, blue: 0x84 / 255)
        case .codex: return Color(red: 0xB3 / 255, green: 0xC3 / 255, blue: 1)
        default: return tint
        }
    }
}

/// What the AI rail covers: the two agents with plan limits.
private let notchLockScreenAgents: [AgentProvider] = [.claude, .codex]

/// The AI rail's read-only cards: Claude's limits and what its API key
/// spent, Codex's limits and the lifetime spending, as many as are shown and
/// where the layout puts them. Codex and Lifetime share a row when they
/// stand together. They take no input.
struct NotchLockScreenAICards: View {
    let size: CGSize
    /// Each card's frame from the panel's top left.
    let widgets: [NotchLockScreenPlacement]
    let privacy: NotchAgentPrivacy
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    // Read so a billing choice made before locking draws the right card.
    @AppStorage(DefaultsKey.notchAgentsClaudeBilling) private var billing = AgentClaudeBilling.automatic.rawValue

    @AppStorage(DefaultsKey.notchAgentsLockHiddenAccounts) private var hiddenAccounts = ""
    @AppStorage(DefaultsKey.notchAgentsLockHiddenProfiles) private var hiddenProfiles = ""

    /// Whether an API key pays for Claude Code, which splits Claude's card.
    private var claudeUsesAPI: Bool {
        _ = billing
        return AgentClaudeBilling.usesAPI()
    }

    /// The API key's spending is left on for the lock screen.
    private var showsAPI: Bool {
        _ = hiddenAccounts
        return NotchLimitVisibility.shows(.claudeAPI, in: .lockScreen)
    }

    var body: some View {
        let _ = hiddenProfiles
        let text = FeatureStrings.notchAgents(l10n.language)
        let shown = NotchAgentLimitDisplay(rawValue: display) ?? .remaining
        TimelineView(.periodic(from: .now, by: 10)) { context in
            let snapshot = usage.snapshot
            ZStack(alignment: .topLeading) {
                ForEach(widgets, id: \.widget) { placed in
                    Group {
                        switch placed.widget {
                        case .claude where !snapshot.claudeSeats.isEmpty:
                            // Only the seats left on for the lock screen, side by side.
                            let seats = NotchLimitVisibility.seats(snapshot, in: .lockScreen)
                            NotchAgentClaudeSeatsCard(snapshot: snapshot, seats: seats, now: context.date, display: shown,
                                                      text: text, columns: max(1, seats.count),
                                                      showsAPI: claudeUsesAPI && showsAPI, showsSessions: false)
                        case .claude where claudeUsesAPI && showsAPI:
                            NotchAgentClaudeBillingCard(snapshot: snapshot, now: context.date, display: shown, text: text,
                                                        wide: true, showsSessions: false)
                        case .claude, .codex:
                            NotchAgentLimitsCard(provider: placed.widget == .claude ? .claude : .codex, snapshot: snapshot,
                                                 now: context.date, display: shown, text: text)
                        case .lifetime:
                            NotchLockScreenLifetimeCard(snapshot: snapshot, hidesAmounts: privacy.hidesAmounts)
                        default:
                            EmptyView()
                        }
                    }
                    .frame(width: placed.frame.width, height: placed.frame.height)
                    .padding(.leading, placed.frame.minX)
                    .padding(.top, placed.frame.minY)
                }
            }
        }
        .environment(\.notchAgentsLockScreen, privacy)
        .environment(\.notchGlassSurface, true)
        // Only what the cards mark private: amounts, when they are hidden.
        .redacted(reason: .privacy)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .environment(\.locale, l10n.language.formattingLocale())
    }
}

/// Every agent's work at API prices since the ledger began, Claude's and
/// Codex's shares on a bar. With amounts hidden it counts tokens instead.
private struct NotchLockScreenLifetimeCard: View {
    let snapshot: AgentUsageSnapshot
    let hidesAmounts: Bool
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.locale) private var locale

    private typealias Tile = NotchLockScreenTile

    var body: some View {
        let text = FeatureStrings.notchLockScreenWidgets(l10n.language)
        let parts = notchLockScreenAgents.map { snapshot.lifetime.byProvider[$0] ?? AgentTotals() }
        let total = parts.reduce(into: AgentTotals()) { $0 += $1 }
        let byCost = !hidesAmounts
        let priced = total.unpriced == 0
        func value(_ totals: AgentTotals) -> String {
            byCost ? AgentFormat.cost(totals.cost, locale: locale) : AgentFormat.tokens(totals.tokens.total, locale: locale)
        }
        let weights = parts.map { $0.weight(byCost: byCost) }
        let sum = weights.reduce(0, +)
        return VStack(alignment: .leading, spacing: 6) {
            NotchLockScreenSection(title: text.lifetime, symbol: "dollarsign.circle")
            VStack(alignment: .leading, spacing: 0) {
                Text((byCost && !priced ? "≥ " : "") + value(total))
                    .font(Tile.rounded(32))
                    .tracking(-0.8)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(byCost ? FeatureStrings.notchAgentPlaces(l10n.language).allAgentsLifetime : text.tokensAllTime)
                    .font(.system(size: 10))
                    .foregroundStyle(Tile.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    if sum <= 0 {
                        Capsule().fill(Tile.track)
                    } else {
                        ForEach(notchLockScreenAgents.indices, id: \.self) { index in
                            if weights[index] > 0 {
                                Capsule(style: .continuous).fill(notchLockScreenAgents[index].tint)
                                    .frame(width: max(8, (proxy.size.width - 2) * weights[index] / sum))
                            }
                        }
                    }
                }
            }
            .frame(height: 6)
            HStack(spacing: 5) {
                ForEach(notchLockScreenAgents.indices, id: \.self) { index in
                    if index > 0 { Spacer(minLength: 4) }
                    RoundedRectangle(cornerRadius: 2).fill(notchLockScreenAgents[index].tint).frame(width: 6, height: 6)
                    Text(value(parts[index])).foregroundStyle(Tile.text)
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .lockScreenTile(horizontal: 17, vertical: 13)
        .accessibilityElement(children: .combine)
    }
}

/// Every Claude and Codex session running, longest first: where it runs,
/// its project, its model and how long it has worked. The list scrolls once
/// it outgrows the card, with a fade at its foot.
struct NotchLockScreenAgentsAtWork: View {
    let size: CGSize
    let privacy: NotchAgentPrivacy
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared

    private typealias Tile = NotchLockScreenTile
    static let rowHeight: CGFloat = 32
    static let rowGap: CGFloat = 3
    /// The card's padding and heading above the list.
    private static let chrome: CGFloat = 14 + 10 + 14 + 6

    /// The terminal's tile, grey beside the agents' app tiles.
    private static let terminalFill = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255)

    var body: some View {
        let text = FeatureStrings.notchLockScreenWidgets(l10n.language)
        let live = usage.snapshot.live.filter { notchLockScreenAgents.contains($0.provider) }
        let overflows = CGFloat(live.count) * (Self.rowHeight + Self.rowGap) - Self.rowGap > size.height - Self.chrome
        VStack(alignment: .leading, spacing: 6) {
            NotchLockScreenSection(title: text.agentsAtWork, symbol: "sparkle") {
                if !live.isEmpty {
                    Text(String(format: text.runningFormat, live.count))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Tile.text)
                }
            }
            if live.isEmpty {
                quiet(text: text)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ScrollView {
                        VStack(spacing: Self.rowGap) {
                            ForEach(live) { row($0, now: context.date, text: text) }
                        }
                        .padding(.bottom, overflows ? 14 : 0)
                    }
                    .scrollIndicators(.automatic)
                    .scrollDisabled(!overflows)
                    .mask {
                        if overflows { Self.fade } else { Color.black }
                    }
                }
            }
        }
        .lockScreenTile(horizontal: 18, vertical: 14)
        .frame(width: size.width, height: size.height)
        .environment(\.locale, l10n.language.formattingLocale())
    }

    private func row(_ session: AgentLiveSession, now: Date, text: NotchLockScreenWidgetStrings) -> some View {
        let provider = session.provider
        let place = session.place == .app ? String(format: text.appFormat, provider.displayName) : text.terminal
        let model = AgentPricing.displayName(session.model)
        return HStack(spacing: 10) {
            tile(session)
            VStack(alignment: .leading, spacing: 0) {
                Text(session.project.isEmpty || privacy.hidesProjects ? provider.displayName : session.project)
                    .font(.system(size: 13.5, weight: .semibold))
                    .truncationMode(.middle)
                Text(model.isEmpty ? place : place + " · " + model)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Tile.dim)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(AgentFormat.clock(now.timeIntervalSince(session.started)))
                .font(Tile.rounded(17))
                .monospacedDigit()
                .foregroundStyle(provider.lockScreenTint)
                .lineLimit(1)
        }
        .frame(height: Self.rowHeight)
        .accessibilityElement(children: .combine)
    }

    private func tile(_ session: AgentLiveSession) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(session.place == .app ? session.provider.tint : Self.terminalFill)
            .overlay {
                if session.place == .app {
                    NotchAgentMark(provider: session.provider, size: 13, tint: .white)
                } else {
                    NotchAgentTerminalMark()
                        .stroke(.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 13, height: 13)
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }

    private func quiet(text: NotchLockScreenWidgetStrings) -> some View {
        let last = notchLockScreenAgents.compactMap { usage.snapshot.lastActivity[$0] }.max()
        return VStack(alignment: .leading, spacing: 3) {
            Text(text.allQuiet)
                .font(Tile.rounded(24))
            Text(text.noneRunning + (last.map { " " + String(format: text.lastEndedFormat,
                                                             $0.formatted(.dateTime.hour().minute())) } ?? ""))
                .font(.system(size: 12))
                .foregroundStyle(Tile.dim)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private static let fade = LinearGradient(
        stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.8),
                .init(color: .clear, location: 1)],
        startPoint: .top, endPoint: .bottom)
}

/// Days in a row with any agent's use, the best run, and the last thirty
/// days as bars. Pointing at a bar says what that day held.
struct NotchLockScreenStreak: View {
    let size: CGSize
    let privacy: NotchAgentPrivacy
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var hovered: Int?

    private typealias Tile = NotchLockScreenTile
    static let dayCount = 30
    private static let barGap: CGFloat = 3

    var body: some View {
        let text = FeatureStrings.notchLockScreenWidgets(l10n.language)
        let locale = l10n.language.formattingLocale()
        let days = usage.snapshot.days
        let run = NotchLockScreenSupport.streak(days.map { $0.total.requests > 0 })
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 1) {
                NotchLockScreenSection(title: text.streak, symbol: "flame",
                                       symbolTint: Color(red: 0xE8 / 255, green: 0x90 / 255, blue: 0x6F / 255))
                Spacer(minLength: 0)
                Text("\(run.current)")
                    .font(Tile.rounded(52))
                    .tracking(-1.5)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(text.daysInARow)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tile.dim)
                    .lineLimit(1)
                Text(String(format: text.bestFormat, AgentFormat.span(days: run.best, locale: locale)))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Tile.dim)
                    .lineLimit(1)
            }
            .frame(width: 110, alignment: .leading)
            bars(days, current: run.current, text: text, locale: locale)
        }
        .lockScreenTile(horizontal: 18, vertical: 14)
        .frame(width: size.width, height: size.height)
        .environment(\.locale, locale)
    }

    private var byCost: Bool {
        !privacy.hidesAmounts && usage.snapshot.days.suffix(Self.dayCount).allSatisfy { $0.total.unpriced == 0 }
    }

    private func bars(_ all: [AgentBucket], current: Int, text: NotchLockScreenWidgetStrings,
                      locale: Locale) -> some View {
        let days = Array(all.suffix(Self.dayCount))
        let weights = days.map { $0.total.weight(byCost: byCost) }
        let peak = max(weights.max() ?? 0, .leastNonzeroMagnitude)
        // The run ends today, or yesterday while today has nothing yet.
        let runEnd = days.last.map { $0.total.requests > 0 } == true ? days.count : days.count - 1
        return VStack(spacing: 6) {
            GeometryReader { proxy in
                let slot = proxy.size.width / CGFloat(max(1, days.count))
                HStack(alignment: .bottom, spacing: Self.barGap) {
                    ForEach(days.indices, id: \.self) { index in
                        let active = days[index].total.requests > 0
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(hovered == index ? Color.white
                                  : !active ? Tile.track
                                  : index >= runEnd - current && index < runEnd ? AgentProvider.claude.tint
                                  : AgentProvider.claude.tint.opacity(0.5))
                            .frame(height: active ? max(4, proxy.size.height * weights[index] / peak) : 3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .overlay {
                    NotchLockScreenHover { point in
                        hovered = point.map { min(days.count - 1, max(0, Int($0.x / slot))) }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let hovered, hovered < days.count {
                        tip(days[hovered], models: models(of: hovered, total: all.count), text: text, locale: locale)
                            .offset(x: min(max(0, slot * CGFloat(hovered) - 75), proxy.size.width - 160))
                            .allowsHitTesting(false)
                    }
                }
            }
            HStack {
                Text(days.first.map { $0.start.formatted(.dateTime.month(.abbreviated).day().locale(locale)) } ?? "")
                Spacer(minLength: 4)
                Text(text.hoverHint)
                Spacer(minLength: 4)
                Text(FeatureStrings.notchCalendar(l10n.language).today)
            }
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(Tile.dim)
            .lineLimit(1)
        }
    }

    /// The day's models, busiest first, from the summary's per-day record.
    private func models(of index: Int, total: Int) -> [AgentShare] {
        let all = usage.snapshot.dayModels
        let offset = all.count - (min(total, Self.dayCount)) + index
        guard all.indices.contains(offset) else { return [] }
        return all[offset].values.sorted { $0.totals.weight(byCost: byCost) > $1.totals.weight(byCost: byCost) }
    }

    private func tip(_ day: AgentBucket, models: [AgentShare], text: NotchLockScreenWidgetStrings,
                     locale: Locale) -> some View {
        let totals = day.total
        var lines: [(String, String)] = []
        if totals.requests > 0 {
            if !privacy.hidesAmounts {
                lines.append((text.spent, (totals.unpriced > 0 ? "≥ " : "") + AgentFormat.cost(totals.cost, locale: locale)))
            }
            lines.append((text.tokens, String(format: text.inOutFormat,
                                              AgentFormat.tokens(totals.tokens.prompt, locale: locale),
                                              AgentFormat.tokens(totals.tokens.output, locale: locale))))
            lines.append((text.requests, totals.requests.formatted(.number.locale(locale))))
            if let top = models.first { lines.append((text.topModel, top.name)) }
        } else {
            lines.append((text.noUse, ""))
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(day.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(locale)))
                .font(.system(size: 10, weight: .bold))
            ForEach(lines.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Text(lines[index].0).foregroundStyle(Color(white: 0.37))
                    Spacer(minLength: 4)
                    Text(lines[index].1).fontWeight(.semibold)
                }
                .font(.system(size: 9))
                .monospacedDigit()
                .lineLimit(1)
            }
        }
        .foregroundStyle(Color(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(width: 160, alignment: .leading)
        .background(Color(red: 250 / 255, green: 249 / 255, blue: 1).opacity(0.97),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }
}
