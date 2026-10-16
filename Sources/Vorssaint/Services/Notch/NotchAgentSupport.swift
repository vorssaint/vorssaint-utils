// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The cards the AI page can show, in the order a person arranges them. Raw
/// values are stored in the saved order, so cases are never renamed.
enum NotchAgentCard: String, CaseIterable, Identifiable {
    case limits, spend, live, trend, models, projects, activity, resets

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .limits: return "gauge.with.dots.needle.33percent"
        case .spend: return "dollarsign.circle"
        case .live: return "waveform.path.ecg"
        case .trend: return "chart.bar.xaxis"
        case .models: return "cpu"
        case .projects: return "folder"
        case .activity: return "square.grid.3x3.fill"
        case .resets: return "arrow.counterclockwise.circle"
        }
    }

    /// Charts need the island's width; everything else pairs up.
    var fullWidth: Bool { self == .trend || self == .activity }

    /// Cards that cover the period chosen in the island's top row.
    var followsPeriod: Bool { self == .spend || self == .trend || self == .models || self == .projects }
}

/// What the closed island shows beside the camera while an agent works.
enum NotchAgentReadout: String, CaseIterable, Identifiable {
    case elapsed, tokens, cost, limit
    var id: String { rawValue }

    /// Tokens and cost change only with a new snapshot. Limits still need
    /// the clock: an allowance can renew, or show elapsed time while unknown.
    var advancesWithClock: Bool { self == .elapsed || self == .limit }
}

enum NotchAgentLimitDisplay: String, CaseIterable, Identifiable {
    case remaining, used
    var id: String { rawValue }
}

/// Which allowance the closed island shows.
enum NotchAgentLimitFocus: String, CaseIterable, Identifiable {
    case mostUsed, session, weekly
    var id: String { rawValue }
}

struct NotchAgentTile: Identifiable, Equatable {
    let card: NotchAgentCard
    /// The account a limits card belongs to.
    let provider: AgentProvider?
    var id: String { card.rawValue + (provider.map { "." + $0.rawValue } ?? "") }
}

enum NotchAgentSupport {
    static let defaultFinishMinimum: TimeInterval = 60
    static let finishMinimums: [TimeInterval] = [0, 30, 60, 120, 300]
    static let defaultLimitThreshold = 80.0
    static let limitThresholds = [50.0, 75.0, 80.0, 90.0, 95.0]
    static let budgets = [0.0, 5, 10, 25, 50, 100, 250]
    /// A turn silent for this long is not shown as working.
    static let idleTurn: TimeInterval = 10 * 60

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && sectionShows(in: defaults)
    }

    /// The AI section is installed, switched on and shown, whether or not the
    /// island itself is.
    static func sectionShows(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.notchAgents.isAvailable(in: defaults) && defaults.bool(forKey: DefaultsKey.notchAgentsEnabled)
            && NotchSupport.modules(in: defaults).contains(.agents)
    }

    /// Reading serves either surface. A pinned agent is an explicit opt-in,
    /// independent of the providers selected for the island's page.
    static func alertProviders(in defaults: UserDefaults = .standard) -> [AgentProvider] {
        isEnabled(in: defaults) ? providers(in: defaults) : []
    }

    static func alertSpend(_ snapshot: AgentUsageSnapshot, in defaults: UserDefaults = .standard) -> Double {
        alertProviders(in: defaults).reduce(0) { $0 + (snapshot.usage(.today).byProvider[$1]?.cost ?? 0) }
    }

    static func readingProviders(in defaults: UserDefaults = .standard) -> [AgentProvider] {
        let island = isEnabled(in: defaults) ? providers(in: defaults) : []
        let menuBar = MenuBarAgentSupport.providers(in: defaults)
        return AgentProvider.allCases.filter { island.contains($0) || menuBar.contains($0) }
    }

    static func providers(in defaults: UserDefaults = .standard) -> [AgentProvider] {
        AgentProvider.allCases.filter {
            defaults.object(forKey: key(for: $0)) as? Bool ?? true
        }
    }

    static func key(for provider: AgentProvider) -> String {
        switch provider {
        case .claude: return DefaultsKey.notchAgentsClaude
        case .codex: return DefaultsKey.notchAgentsCodex
        case .opencode: return DefaultsKey.notchAgentsOpenCode
        case .copilot: return DefaultsKey.notchAgentsCopilot
        }
    }

    /// Every card in the saved order; cards added later join at the end.
    static func orderedCards(in defaults: UserDefaults = .standard) -> [NotchAgentCard] {
        let stored = (defaults.string(forKey: DefaultsKey.notchAgentsCardOrder) ?? "")
            .split(separator: ",").compactMap { NotchAgentCard(rawValue: String($0)) }
        var seen = Set<NotchAgentCard>()
        return (stored + NotchAgentCard.allCases).filter { seen.insert($0).inserted }
    }

    static func hiddenCards(in defaults: UserDefaults = .standard) -> Set<NotchAgentCard> {
        Set((defaults.string(forKey: DefaultsKey.notchAgentsHiddenCards) ?? "")
            .split(separator: ",").compactMap { NotchAgentCard(rawValue: String($0)) })
    }

    static func cards(in defaults: UserDefaults = .standard) -> [NotchAgentCard] {
        let hidden = hiddenCards(in: defaults)
        return orderedCards(in: defaults).filter { !hidden.contains($0) }
    }

    static func period(in defaults: UserDefaults = .standard) -> AgentPeriod {
        AgentPeriod(rawValue: defaults.string(forKey: DefaultsKey.notchAgentsPeriod) ?? "") ?? .today
    }

    static func limitDisplay(in defaults: UserDefaults = .standard) -> NotchAgentLimitDisplay {
        NotchAgentLimitDisplay(rawValue: defaults.string(forKey: DefaultsKey.notchAgentsLimitDisplay) ?? "") ?? .remaining
    }

    static func limitFocus(in defaults: UserDefaults = .standard) -> NotchAgentLimitFocus {
        NotchAgentLimitFocus(rawValue: defaults.string(forKey: DefaultsKey.notchAgentsLimitFocus) ?? "") ?? .mostUsed
    }

    /// The allowance the closed island shows: the window the person chose,
    /// or the one closest to running out while the account reports no such
    /// window. A model's own allowance is never the chosen one.
    static func focusedLimit(_ limits: AgentLimits?, focus: NotchAgentLimitFocus, now: Date) -> AgentLimitWindow? {
        chosenLimit(limits, focus: focus, now: now) ?? AgentLimitSupport.binding(limits, now: now)
    }

    /// The plan-wide window of the chosen kind; nil for the most used one or
    /// while the account reports no such window.
    private static func chosenLimit(_ limits: AgentLimits?, focus: NotchAgentLimitFocus, now: Date) -> AgentLimitWindow? {
        let kind: AgentLimitWindow.Kind
        switch focus {
        case .mostUsed: return nil
        case .session: kind = .session
        case .weekly: kind = .weekly
        }
        return limits?.windows.first { $0.kind == kind && $0.scope == nil }.map { AgentLimitSupport.current($0, at: now) }
    }

    /// The resting island's allowance across every account: the most spent
    /// of the chosen windows, or of each account's most used window while no
    /// account reports the chosen one.
    static func restingLimit(_ snapshot: AgentUsageSnapshot, focus: NotchAgentLimitFocus,
                             now: Date) -> (provider: AgentProvider, window: AgentLimitWindow)? {
        func mostSpent(_ pick: (AgentLimits) -> AgentLimitWindow?) -> (provider: AgentProvider, window: AgentLimitWindow)? {
            snapshot.limits.compactMap { provider, limits in pick(limits).map { (provider: provider, window: $0) } }.max {
                $0.window.usedPercent != $1.window.usedPercent ? $0.window.usedPercent < $1.window.usedPercent
                    : $0.provider.rawValue > $1.provider.rawValue
            }
        }
        return mostSpent { chosenLimit($0, focus: focus, now: now) }
            ?? mostSpent { AgentLimitSupport.binding($0, now: now) }
    }

    static func showsLiveActivity(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && (defaults.object(forKey: DefaultsKey.notchAgentsLiveActivity) as? Bool ?? true)
    }

    static func readout(in defaults: UserDefaults = .standard) -> NotchAgentReadout {
        NotchAgentReadout(rawValue: defaults.string(forKey: DefaultsKey.notchAgentsReadout) ?? "") ?? .elapsed
    }

    /// The shortest turn worth a notice when it ends; nil while those are off.
    static func finishMinimum(in defaults: UserDefaults = .standard) -> TimeInterval? {
        guard defaults.object(forKey: DefaultsKey.notchAgentsFinishAlert) as? Bool ?? true else { return nil }
        let value = defaults.object(forKey: DefaultsKey.notchAgentsFinishMinimum) as? Double ?? defaultFinishMinimum
        return value.isFinite ? min(3600, max(0, value)) : defaultFinishMinimum
    }

    /// Percent used that earns a warning; nil while warnings are off.
    static func limitThreshold(in defaults: UserDefaults = .standard) -> Double? {
        guard defaults.object(forKey: DefaultsKey.notchAgentsLimitAlert) as? Bool ?? true else { return nil }
        let value = defaults.object(forKey: DefaultsKey.notchAgentsLimitThreshold) as? Double ?? defaultLimitThreshold
        return value.isFinite ? min(100, max(1, value)) : defaultLimitThreshold
    }

    static func dailyBudget(in defaults: UserDefaults = .standard) -> Double? {
        let value = defaults.double(forKey: DefaultsKey.notchAgentsDailyBudget)
        return value.isFinite && value > 0 ? value : nil
    }

    /// Whether the public price list may be downloaded once a day.
    static func updatesPrices(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchAgentsPriceUpdates) as? Bool ?? true
    }

    // MARK: Strip

    /// A wing is never narrower than the music strip's, nor wide enough to
    /// crowd the menus beside the camera.
    static let stripWingRange: ClosedRange<CGFloat> = 44...80
    /// Air between the camera and what sits beside it.
    static let stripCameraGap: CGFloat = 6

    static func stripTextSize(height: CGFloat) -> CGFloat { min(15, height - 7) }

    /// What the strip shows beside the camera while agents work: the reading
    /// the person chose, or the time elapsed while that one is unknown.
    static func stripReading(_ snapshot: AgentUsageSnapshot, readout: NotchAgentReadout,
                             display: NotchAgentLimitDisplay, focus: NotchAgentLimitFocus = .mostUsed,
                             now: Date) -> String {
        let live = snapshot.live
        func elapsed() -> String { AgentFormat.clock(now.timeIntervalSince(live.map(\.started).min() ?? now)) }
        switch readout {
        case .elapsed:
            return elapsed()
        case .tokens:
            // What the agent wrote, the count its own window shows; the
            // context it reads again on every call is in the cost.
            return AgentFormat.tokens(live.reduce(0) { $0 + $1.tokens.output })
        case .cost:
            return AgentFormat.cost(live.reduce(0) { $0 + $1.cost })
        case .limit:
            guard let provider = AgentProvider.allCases.first(where: { provider in live.contains { $0.provider == provider } }),
                  let window = focusedLimit(snapshot.limits[provider], focus: focus, now: now) else { return elapsed() }
            return AgentFormat.percent(display == .used ? window.usedFraction : window.remainingFraction)
        }
    }

    /// Every digit takes the same width, so a reading's shape, not its value,
    /// sets the strip's width: "12:34" and "59:59" match, "1:00:00" is wider.
    static func readingShape(_ reading: String) -> String {
        String(reading.map { $0.isNumber ? "0" : $0 })
    }

    // MARK: Layout

    static let spacing: CGFloat = 10
    static let cardHeight: CGFloat = 96
    static let chartHeight: CGFloat = 118
    /// Below this width every card takes a row of its own.
    static let pairWidth: CGFloat = 390

    static func tiles(cards: [NotchAgentCard], providers: [AgentProvider]) -> [NotchAgentTile] {
        cards.flatMap { card -> [NotchAgentTile] in
            switch card {
            case .limits: return providers.filter(\.reportsLimits).map { NotchAgentTile(card: .limits, provider: $0) }
            // Banked resets belong to a Codex account.
            case .resets: return providers.contains(.codex) ? [NotchAgentTile(card: .resets, provider: .codex)] : []
            default: return [NotchAgentTile(card: card, provider: nil)]
            }
        }
    }

    /// Cards pair up in reading order; a chart, or a card left without a
    /// partner, takes the whole row.
    static func rows(_ tiles: [NotchAgentTile], width: CGFloat) -> [[NotchAgentTile]] {
        let pairs = width >= pairWidth
        var rows: [[NotchAgentTile]] = []
        var waiting: NotchAgentTile?
        for tile in tiles {
            if tile.card.fullWidth || !pairs {
                if let waiting { rows.append([waiting]) }
                waiting = nil
                rows.append([tile])
            } else if let partner = waiting {
                rows.append([partner, tile])
                waiting = nil
            } else {
                waiting = tile
            }
        }
        if let waiting { rows.append([waiting]) }
        return rows
    }

    static func height(of row: [NotchAgentTile]) -> CGFloat {
        row.contains { $0.card.fullWidth } ? chartHeight : cardHeight
    }

    static func contentHeight(_ rows: [[NotchAgentTile]]) -> CGFloat {
        guard !rows.isEmpty else { return 0 }
        return rows.map(height).reduce(0, +) + spacing * CGFloat(rows.count - 1)
    }
}

/// Each supported agent has independent pins and readout choices. Product
/// names and the existing agent strings cover these controls in every locale.
enum MenuBarAgentSupport {
    static func enabledKey(for provider: AgentProvider) -> String { "menuBarAgent.\(provider.rawValue).enabled" }
    static func readoutKey(for provider: AgentProvider) -> String { "menuBarAgent.\(provider.rawValue).readout" }
    static func focusKey(for provider: AgentProvider) -> String { "menuBarAgent.\(provider.rawValue).focus" }
    static func displayKey(for provider: AgentProvider) -> String { "menuBarAgent.\(provider.rawValue).display" }
    static func periodKey(for provider: AgentProvider) -> String { "menuBarAgent.\(provider.rawValue).period" }

    static var registeredDefaults: [String: Any] {
        AgentProvider.allCases.reduce(into: [:]) { values, provider in
            values[enabledKey(for: provider)] = false
            values[readoutKey(for: provider)] = defaultReadout(for: provider).rawValue
            values[focusKey(for: provider)] = NotchAgentLimitFocus.mostUsed.rawValue
            values[displayKey(for: provider)] = NotchAgentLimitDisplay.used.rawValue
            values[periodKey(for: provider)] = AgentPeriod.today.rawValue
        }
    }

    static func providers(in defaults: UserDefaults = .standard) -> [AgentProvider] {
        guard AppFeature.notchAgents.isAvailable(in: defaults) else { return [] }
        return AgentProvider.allCases.filter { defaults.bool(forKey: enabledKey(for: $0)) }
    }

    static func defaultReadout(for provider: AgentProvider) -> NotchAgentReadout {
        provider.reportsLimits ? .limit : .tokens
    }

    static func readouts(for provider: AgentProvider) -> [NotchAgentReadout] {
        NotchAgentReadout.allCases.filter { provider.reportsLimits || $0 != .limit }
    }

    static func readout(for provider: AgentProvider, in defaults: UserDefaults = .standard) -> NotchAgentReadout {
        let stored = NotchAgentReadout(rawValue: defaults.string(forKey: readoutKey(for: provider)) ?? "")
        return stored.flatMap { readouts(for: provider).contains($0) ? $0 : nil } ?? defaultReadout(for: provider)
    }

    static func focus(for provider: AgentProvider, in defaults: UserDefaults = .standard) -> NotchAgentLimitFocus {
        NotchAgentLimitFocus(rawValue: defaults.string(forKey: focusKey(for: provider)) ?? "") ?? .mostUsed
    }

    static func display(for provider: AgentProvider, in defaults: UserDefaults = .standard) -> NotchAgentLimitDisplay {
        NotchAgentLimitDisplay(rawValue: defaults.string(forKey: displayKey(for: provider)) ?? "") ?? .used
    }

    static func period(for provider: AgentProvider, in defaults: UserDefaults = .standard) -> AgentPeriod {
        AgentPeriod(rawValue: defaults.string(forKey: periodKey(for: provider)) ?? "") ?? .today
    }

    static func window(for provider: AgentProvider, in snapshot: AgentUsageSnapshot,
                       defaults: UserDefaults = .standard, now: Date = Date()) -> AgentLimitWindow? {
        guard snapshot.loaded, var limits = snapshot.limits[provider] else { return nil }
        limits.windows.removeAll { !$0.usedPercent.isFinite || $0.scope != nil }
        return NotchAgentSupport.focusedLimit(limits, focus: focus(for: provider, in: defaults), now: now)
    }

    struct Reading {
        var value = "—"
        var fraction: Double?
        /// Bar fill may show what is left; warning colors always mean usage.
        var usedFraction: Double?
    }

    static func reading(for provider: AgentProvider, snapshot: AgentUsageSnapshot,
                        defaults: UserDefaults = .standard, now: Date = Date()) -> Reading {
        guard snapshot.loaded else { return Reading() }
        switch readout(for: provider, in: defaults) {
        case .limit:
            guard let window = window(for: provider, in: snapshot, defaults: defaults, now: now) else { return Reading() }
            let fraction = display(for: provider, in: defaults) == .used ? window.usedFraction : window.remainingFraction
            return Reading(value: AgentFormat.percent(fraction), fraction: fraction, usedFraction: window.usedFraction)
        case .tokens, .cost:
            guard snapshot.seen.contains(provider) else { return Reading() }
            let totals = snapshot.usage(period(for: provider, in: defaults)).byProvider[provider] ?? AgentTotals()
            if readout(for: provider, in: defaults) == .tokens {
                return Reading(value: AgentFormat.tokens(totals.tokens.output))
            }
            return Reading(value: totals.unpriced == 0 ? AgentFormat.cost(totals.cost) : "—")
        case .elapsed:
            guard let started = snapshot.working(provider).map(\.started).min() else { return Reading() }
            return Reading(value: AgentFormat.clock(now.timeIntervalSince(started)))
        }
    }

    static func tooltip(for provider: AgentProvider, snapshot: AgentUsageSnapshot,
                        defaults: UserDefaults = .standard, now: Date = Date()) -> String {
        let text = FeatureStrings.notchAgents(L10n.shared.language)
        let readout = readout(for: provider, in: defaults)
        let value = reading(for: provider, snapshot: snapshot, defaults: defaults, now: now).value
        if readout == .limit {
            guard let window = window(for: provider, in: snapshot, defaults: defaults, now: now) else {
                return provider.displayName + " · " + text.waitingForLimits
            }
            let meaning = display(for: provider, in: defaults) == .used ? text.usedShare(value) : text.left(value)
            let kind = window.kind == .session ? text.session : window.kind == .weekly ? text.weekly : text.limitsCard
            return provider.displayName + " · " + kind + " · " + meaning
        }
        let span = readout == .elapsed ? text.liveCard : text.period(period(for: provider, in: defaults))
        return provider.displayName + " · " + span + " · " + text.readout(readout) + ": " + value
    }
}

/// Numbers in the reader's region; costs in US dollars, the currency both
/// providers list their prices in.
enum AgentFormat {
    static func cost(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        guard value.isFinite else { return "$0" }
        let magnitude = abs(value)
        if magnitude >= 10_000 { return "$" + scaled(magnitude / 1000, locale: locale) + "K" }
        let digits = magnitude >= 100 ? 0 : 2
        return "$" + value.formatted(.number.precision(.fractionLength(digits)).grouping(.automatic).locale(locale))
    }

    static func tokens(_ value: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let magnitude = Double(max(0, value))
        switch magnitude {
        case ..<1000: return Int(magnitude).formatted(.number.locale(locale))
        case ..<1_000_000: return scaled(magnitude / 1000, locale: locale) + "K"
        case ..<1_000_000_000: return scaled(magnitude / 1_000_000, locale: locale) + "M"
        default: return scaled(magnitude / 1_000_000_000, locale: locale) + "B"
        }
    }

    /// One decimal below ten, none above: "4.2", "48", "120".
    private static func scaled(_ value: Double, locale: Locale) -> String {
        let digits = value < 10 ? 1 : 0
        let rounded = (value * (digits == 1 ? 10 : 1)).rounded(.down) / (digits == 1 ? 10 : 1)
        return rounded.formatted(.number.precision(.fractionLength(0...digits)).locale(locale))
    }

    static func percent(_ fraction: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let value = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return value.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// "4m 12s", "1h 05m", "2d 3h", in the app's language.
    static func duration(_ seconds: TimeInterval, locale: Locale, units: Int = 2,
                         style: DateComponentsFormatter.UnitsStyle = .abbreviated) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = style
        formatter.maximumUnitCount = units
        formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        return formatter.string(from: max(0, seconds.isFinite ? seconds : 0)) ?? ""
    }

    /// "13 weeks" or "30 days", spelled out in the app's language.
    static func span(days: Int, locale: Locale) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        let weeks = days % 7 == 0
        formatter.allowedUnits = weeks ? [.weekOfMonth] : [.day]
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        // Components, not an interval: an interval is measured from today and
        // can lose a week across a month.
        let count = max(0, days)
        return formatter.string(from: weeks ? DateComponents(weekOfMonth: count / 7) : DateComponents(day: count)) ?? ""
    }

    /// A running stopwatch: "0:42", "12:05", "1:02:05".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// A calendar day kept in UTC, like the price list's, read as that same
    /// day wherever the Mac is.
    static func day(_ date: Date, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
        style.timeZone = .gmt
        return date.formatted(style)
    }
}
