// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The cards the AI page can show, in the order a person arranges them. Raw
/// values are stored in the saved order, so cases are never renamed.
enum NotchAgentCard: String, CaseIterable, Identifiable {
    // The order is the page's default. Sessions now sit in the limits cards
    // and models in Spending, so Now and Models are retired: the cases stay
    // only so saved orders still read.
    case limits, spend, trend, projects, resets, activity, live, models

    var id: String { rawValue }

    /// Cards the page no longer shows, whatever the saved settings say. A
    /// page whose hidden cards were saved before they retired would
    /// otherwise list the sessions and models a second time.
    var retired: Bool { self == .live || self == .models }

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
    var followsPeriod: Bool { self == .trend || self == .models || self == .projects }
}

/// What the AI page keeps back where anyone can read it, as on the lock
/// screen: the folders agents work in, and what the work cost.
struct NotchAgentPrivacy: Equatable {
    var hidesProjects = false
    var hidesAmounts = false
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

/// How the resting island lays out the accounts' allowances: the one the
/// focus picks, the first two accounts one per side, or each in turn.
enum NotchAgentRestingLayout: String, CaseIterable, Identifiable {
    case single, split, cycle
    var id: String { rawValue }
}

/// How close a window is to running out, as the resting island colors it.
enum NotchAgentRestingStatus: Equatable {
    case normal, low, almostOut
}

/// One account at rest: the limit "Limit to show" picks, which its ring
/// fills and its number and reset time read.
struct NotchAgentRestingMeter: Identifiable, Equatable {
    let provider: AgentProvider
    let window: AgentLimitWindow

    var id: String { provider.rawValue }
}

/// When a resting limit renews, in the two lengths a wing has room for.
struct NotchAgentRestingReset: Equatable {
    /// "16:26" within the day, "Sat 15:33" further off.
    let full: String
    /// "16:26" or "Sat", for a narrow wing.
    let short: String
}

struct NotchAgentTile: Identifiable, Equatable {
    let card: NotchAgentCard
    /// The account a limits card belongs to.
    let provider: AgentProvider?
    /// An added Codex home's card; nil for the one the logs feed.
    var accountID: String? = nil
    /// The Resets card beside added Codex homes, which says whose resets they are.
    var namesDefaultAccount = false
    /// Claude's limits card beside the API key's spending, which takes a row.
    var splitsBilling = false
    var id: String { card.rawValue + (provider.map { "." + $0.rawValue } ?? "") + (accountID.map { "." + $0 } ?? "") }
    var fullWidth: Bool { card.fullWidth || splitsBilling }
    /// Claude's and Codex's own limits cards list the sessions they pay for,
    /// a row each, and keep one row while none runs.
    var showsSessions: Bool {
        card == .limits && accountID == nil && (provider == .claude || provider == .codex)
    }
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
        orderedCards(defaults.string(forKey: DefaultsKey.notchAgentsCardOrder) ?? "")
    }

    /// The cards a saved order lists, without retired or repeated ones.
    static func orderedCards(_ saved: String) -> [NotchAgentCard] {
        let stored = saved.split(separator: ",").compactMap { NotchAgentCard(rawValue: String($0)) }
        var seen = Set<NotchAgentCard>()
        return (stored + NotchAgentCard.allCases).filter { !$0.retired && seen.insert($0).inserted }
    }

    /// Cards a new page leaves out until the person shows them.
    static let defaultHiddenCards = "live,models"

    static func hiddenCards(in defaults: UserDefaults = .standard) -> Set<NotchAgentCard> {
        Set((defaults.string(forKey: DefaultsKey.notchAgentsHiddenCards) ?? defaultHiddenCards)
            .split(separator: ",").compactMap { NotchAgentCard(rawValue: String($0)) })
    }

    static func cards(in defaults: UserDefaults = .standard) -> [NotchAgentCard] {
        let hidden = hiddenCards(in: defaults)
        return orderedCards(in: defaults).filter { !hidden.contains($0) }
    }

    /// Added Codex accounts have cards only in the Limits card's place.
    static func showsCodexAccounts(in defaults: UserDefaults = .standard) -> Bool {
        providers(in: defaults).contains(.codex) && !hiddenCards(in: defaults).contains(.limits)
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

    // MARK: Resting meters

    static func restingLayout(in defaults: UserDefaults = .standard) -> NotchAgentRestingLayout {
        NotchAgentRestingLayout(rawValue: defaults.string(forKey: DefaultsKey.notchAgentsRestingLayout) ?? "") ?? .single
    }

    /// Accounts switched off in Show at rest.
    static func restingHidden(in defaults: UserDefaults = .standard) -> Set<AgentProvider> {
        parseRestingHidden(defaults.string(forKey: DefaultsKey.notchAgentsRestingHidden) ?? "")
    }

    static func parseRestingHidden(_ stored: String) -> Set<AgentProvider> {
        Set(stored.split(separator: ",").compactMap { AgentProvider(rawValue: String($0)) })
    }

    static func restingStatus(usedFraction: Double) -> NotchAgentRestingStatus {
        if usedFraction >= 0.95 { return .almostOut }
        if usedFraction >= 0.8 { return .low }
        return .normal
    }

    /// The Developer build's stand-in usage, so the resting colors can be
    /// checked by eye: `claude.session=0.86,codex.weekly=0.97`. Anything
    /// malformed is skipped, and a release build never reads the key.
    static func simulatedRestingUsage(in defaults: UserDefaults = .standard,
                                      developer: Bool = AppInfo.isDeveloperBuild) -> [AgentProvider: [AgentLimitWindow.Kind: Double]] {
        guard developer, let stored = defaults.string(forKey: DefaultsKey.simulateRestingUsage) else { return [:] }
        return parseSimulatedRestingUsage(stored)
    }

    static func parseSimulatedRestingUsage(_ stored: String) -> [AgentProvider: [AgentLimitWindow.Kind: Double]] {
        var result: [AgentProvider: [AgentLimitWindow.Kind: Double]] = [:]
        for entry in stored.split(separator: ",") {
            let pair = entry.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, let value = Double(pair[1]), value.isFinite else { continue }
            let name = pair[0].split(separator: ".", maxSplits: 1).map(String.init)
            guard name.count == 2, let provider = AgentProvider(rawValue: name[0]),
                  let kind = AgentLimitWindow.Kind(rawValue: name[1]), kind != .other else { continue }
            result[provider, default: [:]][kind] = min(1, max(0, value))
        }
        return result
    }

    /// A copy of the snapshot with the simulated windows' usage in place of
    /// the real one. Only the resting island reads it.
    static func applyingSimulation(_ snapshot: AgentUsageSnapshot,
                                   _ overrides: [AgentProvider: [AgentLimitWindow.Kind: Double]]) -> AgentUsageSnapshot {
        guard !overrides.isEmpty else { return snapshot }
        var copy = snapshot
        for (provider, kinds) in overrides {
            guard var limits = copy.limits[provider] else { continue }
            limits.windows = limits.windows.map { window in
                guard window.scope == nil, let fraction = kinds[window.kind] else { return window }
                return AgentLimitWindow(id: window.id, kind: window.kind, minutes: window.minutes, scope: nil,
                                        usedPercent: fraction * 100, resetsAt: window.resetsAt)
            }
            copy.limits[provider] = limits
        }
        return copy
    }

    /// Every account that rests, in the order the person keeps them: switched
    /// on, not left out at rest, and reporting a plan-wide window. Each shows
    /// the window "Limit to show" picks, or its most used one while the
    /// account reports none of that kind.
    static func restingMeters(_ snapshot: AgentUsageSnapshot, providers: [AgentProvider],
                              hidden: Set<AgentProvider>, focus: NotchAgentLimitFocus,
                              now: Date) -> [NotchAgentRestingMeter] {
        providers.compactMap { provider -> NotchAgentRestingMeter? in
            guard !hidden.contains(provider), let limits = snapshot.limits[provider] else { return nil }
            let planWide = limits.windows.filter { $0.scope == nil }.map { AgentLimitSupport.current($0, at: now) }
            let kind: AgentLimitWindow.Kind?
            switch focus {
            case .mostUsed: kind = nil
            case .session: kind = .session
            case .weekly: kind = .weekly
            }
            // Of two windows as spent, the one renewing later stops you longer.
            let window = kind.flatMap { kind in planWide.first { $0.kind == kind } } ?? planWide.max {
                $0.usedPercent != $1.usedPercent ? $0.usedPercent < $1.usedPercent
                    : ($0.resetsAt ?? .distantPast) < ($1.resetsAt ?? .distantPast)
            }
            return window.map { NotchAgentRestingMeter(provider: provider, window: $0) }
        }
    }

    /// Single's meter: the limit closest to stopping you among the accounts
    /// that rest, the same one the working strip's ring shows.
    static func singleRestingMeter(_ snapshot: AgentUsageSnapshot, hidden: Set<AgentProvider>,
                                   focus: NotchAgentLimitFocus, now: Date) -> NotchAgentRestingMeter? {
        var shown = snapshot
        shown.limits = snapshot.limits.filter { !hidden.contains($0.key) }
        return restingLimit(shown, focus: focus, now: now).map { NotchAgentRestingMeter(provider: $0.provider, window: $0.window) }
    }

    /// What a layout shows, in its order: Single's one meter, the first two
    /// for One per side, and for Rotate the tightest number first, then the
    /// rest in the person's order.
    static func restingSequence(_ snapshot: AgentUsageSnapshot, layout: NotchAgentRestingLayout,
                                providers: [AgentProvider], hidden: Set<AgentProvider>,
                                focus: NotchAgentLimitFocus, now: Date) -> [NotchAgentRestingMeter] {
        switch layout {
        case .single:
            return singleRestingMeter(snapshot, hidden: hidden, focus: focus, now: now).map { [$0] } ?? []
        case .split:
            return Array(restingMeters(snapshot, providers: providers, hidden: hidden, focus: focus, now: now).prefix(2))
        case .cycle:
            var meters = restingMeters(snapshot, providers: providers, hidden: hidden, focus: focus, now: now)
            // The first of the most spent, so a tie keeps the person's order.
            if let tightest = meters.indices.max(by: { meters[$0].window.usedPercent < meters[$1].window.usedPercent
                                                        || (meters[$0].window.usedPercent == meters[$1].window.usedPercent && $0 > $1) }) {
                meters.insert(meters.remove(at: tightest), at: 0)
            }
            return meters
        }
    }

    /// When a resting limit renews: the 24-hour clock time on the same day or
    /// within twelve hours, the weekday and time within the week, the date
    /// beyond. The short form keeps only the weekday. "≈" marks a time the
    /// island estimated; nil while the time is unknown.
    static func restingReset(_ window: AgentLimitWindow, now: Date, locale: Locale,
                             calendar: Calendar = .autoupdatingCurrent) -> NotchAgentRestingReset? {
        guard let resets = AgentLimitSupport.displayedReset(window, now: now) else { return nil }
        let mark = window.estimatedResetsAt == nil ? "" : "≈"
        let style = Date.FormatStyle(locale: AgentFormat.resetClock(locale), calendar: calendar, timeZone: calendar.timeZone)
        let away = resets.timeIntervalSince(now)
        if calendar.isDate(resets, inSameDayAs: now) || away < 12 * 3_600 {
            let clock = mark + resets.formatted(style.hour(.twoDigits(amPM: .omitted)).minute())
            return NotchAgentRestingReset(full: clock, short: clock)
        }
        let full = AgentFormat.resetTime(resets, now: now, locale: locale, calendar: calendar)
        return NotchAgentRestingReset(full: mark + full,
                                      short: mark + (away < 6 * 86_400 ? resets.formatted(style.weekday(.abbreviated)) : full))
    }

    /// What VoiceOver reads for the meters: each account's limit, as left or
    /// used, when it renews, and a word once it runs low.
    static func restingSpeech(_ meters: [NotchAgentRestingMeter], used: Bool, text: NotchAgentStrings,
                              locale: Locale, now: Date) -> String {
        meters.map { meter in
            let window = meter.window
            let share = AgentFormat.percent(used ? window.usedFraction : window.remainingFraction, locale: locale)
            var parts = [text.restingWindow(window.kind == .weekly ? text.weekly : text.session,
                                            used ? text.usedShare(share) : text.left(share))]
            if let resets = AgentLimitSupport.displayedReset(window, now: now) {
                parts.append(text.restingResets(AgentFormat.resetTime(resets, now: now, locale: locale)))
            }
            switch restingStatus(usedFraction: window.usedFraction) {
            case .normal: break
            case .low: parts.append(text.restingLow)
            case .almostOut: parts.append(text.restingAlmostOut)
            }
            return meter.provider.displayName + ": " + parts.joined(separator: ", ")
        }.joined(separator: "; ")
    }

    /// Rotate's place in its sequence: every wing reads the same clock, so
    /// both sides turn together.
    static let restingCycle: TimeInterval = 4

    static func restingCycleIndex(at date: Date, count: Int) -> Int {
        guard count > 1 else { return 0 }
        let step = Int((date.timeIntervalSinceReferenceDate / restingCycle).rounded(.down))
        return ((step % count) + count) % count
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

    /// Whether anything shows or alerts on the plan limits: their alerts, the
    /// live reading when it shows a limit, the resting island's allowance or,
    /// while the AI page shows, its Limits card. Nothing asks for them otherwise.
    static func limitsInUse(pageShown: Bool, in defaults: UserDefaults = .standard) -> Bool {
        limitThreshold(in: defaults) != nil
            || (showsLiveActivity(in: defaults) && readout(in: defaults) == .limit)
            || NotchSupport.idleContent(in: defaults) == .agents
            || (pageShown && !hiddenCards(in: defaults).contains(.limits))
    }

    /// Whether a limit is on screen, the page's or the closed island's,
    /// which keeps Claude's account check at its shortest wait.
    static func limitsOnScreen(pageShown: Bool, in defaults: UserDefaults = .standard) -> Bool {
        (pageShown && !hiddenCards(in: defaults).contains(.limits))
            || NotchSupport.idleContent(in: defaults) == .agents
            || (showsLiveActivity(in: defaults) && readout(in: defaults) == .limit)
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
    /// An account card also says when it was checked, and the Resets card
    /// beside account cards names the account its resets belong to.
    static let accountCardHeight: CGFloat = 116
    /// An account card's reading, checked every five minutes, has missed two.
    static let accountStaleness: TimeInterval = 10 * 60
    /// Claude's split card: the plan and the API key side by side, or one
    /// above the other where cards do not pair. Each size holds one session
    /// row per slot; a card grows a row for every session past the first.
    static let splitHeight: CGFloat = 178
    static let stackedSplitHeight: CGFloat = 300
    /// A limits card with one row of sessions under the meters.
    static let sessionCardHeight: CGFloat = 156
    /// One running session in a limits card.
    static let sessionRowHeight: CGFloat = 26
    /// Below this width every card takes a row of its own.
    static let pairWidth: CGFloat = 390

    /// Codex homes the person added take the place of Codex's one limits
    /// card, the usual home among them when they add it.
    static func tiles(cards: [NotchAgentCard], providers: [AgentProvider],
                      codexAccounts: [String] = [], claudeUsesAPI: Bool = false) -> [NotchAgentTile] {
        cards.flatMap { card -> [NotchAgentTile] in
            switch card {
            case .limits: return providers.filter(\.reportsLimits).flatMap { provider -> [NotchAgentTile] in
                guard provider == .codex, !codexAccounts.isEmpty else {
                    return [NotchAgentTile(card: .limits, provider: provider,
                                           splitsBilling: provider == .claude && claudeUsesAPI)]
                }
                return codexAccounts.map { NotchAgentTile(card: .limits, provider: provider, accountID: $0) }
            }
            // Banked resets belong to a Codex account: the default one, which
            // the card names once others have cards.
            case .resets: return providers.contains(.codex)
                ? [NotchAgentTile(card: .resets, provider: .codex, namesDefaultAccount: !codexAccounts.isEmpty)] : []
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
            if tile.fullWidth || !pairs {
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

    /// A row's cards share its height, so a card beside a taller one, such
    /// as Spending beside Codex's sessions, grows with it.
    static func height(of row: [NotchAgentTile], width: CGFloat = .infinity, live: [AgentLiveSession] = []) -> CGFloat {
        let growth = row.map { sessionGrowth($0, live: live, width: width) }.max() ?? 0
        if row.contains(where: \.splitsBilling) { return (width >= pairWidth ? splitHeight : stackedSplitHeight) + growth }
        if row.contains(where: \.card.fullWidth) { return chartHeight }
        let height = row.contains { $0.accountID != nil || $0.namesDefaultAccount } ? accountCardHeight : cardHeight
        // Spending lists its top models under the total.
        return (row.contains { $0.showsSessions || $0.card == .spend } ? max(height, sessionCardHeight) : height) + growth
    }

    /// Where a limits card's sessions show: the app and the terminal for
    /// Claude, the app alone for Codex unless its command line is working too.
    static func sessionPlaces(_ provider: AgentProvider, live: [AgentLiveSession]) -> [AgentSessionPlace] {
        provider == .codex && !live.contains { $0.provider == .codex && $0.place == .terminal }
            ? [.app] : [.app, .terminal]
    }

    /// A slot's rows: one for each session, or one saying none is running.
    static func sessionRows(provider: AgentProvider, place: AgentSessionPlace, live: [AgentLiveSession]) -> Int {
        max(1, live.filter { $0.provider == provider && $0.place == place }.count)
    }

    /// How much a card grows past its one-row size to list every session:
    /// slots side by side by the fuller one's rows, Claude's split card
    /// stacked by both.
    static func sessionGrowth(_ tile: NotchAgentTile, live: [AgentLiveSession], width: CGFloat) -> CGFloat {
        guard tile.showsSessions, let provider = tile.provider else { return 0 }
        let extra = sessionPlaces(provider, live: live).map { sessionRows(provider: provider, place: $0, live: live) - 1 }
        let rows = tile.splitsBilling && width < pairWidth ? extra.reduce(0, +) : extra.max() ?? 0
        return CGFloat(rows) * sessionRowHeight
    }

    // MARK: Month

    /// This calendar month's days from those the summary keeps, so a month's
    /// first days are never mixed with the last one's.
    static func monthDays(_ snapshot: AgentUsageSnapshot, now: Date,
                          calendar: Calendar = .autoupdatingCurrent) -> [AgentBucket] {
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        return snapshot.days.filter { $0.start >= month }
    }

    /// What Claude's plan covered this month at API prices: every Claude
    /// response, less Claude Code's outside the app when an API key pays.
    static func claudePlanMonth(_ snapshot: AgentUsageSnapshot, splitsBilling: Bool, now: Date,
                                calendar: Calendar = .autoupdatingCurrent) -> Double {
        monthDays(snapshot, now: now, calendar: calendar).reduce(0) { total, day in
            total + (day.byProvider[.claude]?.cost ?? 0) - (splitsBilling ? day.claudeAPI.cost : 0)
        }
    }

    /// Every agent's work this month at API prices.
    static func monthTotal(_ snapshot: AgentUsageSnapshot, providers: [AgentProvider], now: Date,
                           calendar: Calendar = .autoupdatingCurrent) -> Double {
        monthDays(snapshot, now: now, calendar: calendar).reduce(0) { total, day in
            total + providers.reduce(0) { $0 + (day.byProvider[$1]?.cost ?? 0) }
        }
    }

    /// The open five-hour window's value: the Claude app's share when an API
    /// key pays for Claude Code elsewhere. Nil once the window has closed.
    static func claudeSessionValue(_ snapshot: AgentUsageSnapshot, splitsBilling: Bool) -> Double? {
        (splitsBilling ? snapshot.claudeAppBlock : snapshot.claudeBlock)?.totals.cost
    }

    /// An account card's line in place of its windows while it has none, or
    /// under them: a failure takes one of the two, never both.
    static func accountNotes(hasWindows: Bool, checking: Bool, failure: String?, hint: String, loading: String,
                             updated: String?) -> (placeholder: String?, caption: String?) {
        guard hasWindows else { return (checking ? loading : failure ?? hint, nil) }
        return (nil, failure ?? updated)
    }

    /// A reading old enough to have missed use elsewhere shows quieter: an
    /// account card's after missed checks, and among the others only
    /// Claude's, which the Claude app or Claude Code took a while ago.
    static func limitsAreStale(_ limits: AgentLimits?, provider: AgentProvider, account: Bool, now: Date) -> Bool {
        guard let limits else { return false }
        let age = now.timeIntervalSince(limits.observedAt)
        if account { return age >= accountStaleness }
        return provider == .claude && age >= AgentClaudeAppUsage.freshness
    }

    static func contentHeight(_ rows: [[NotchAgentTile]], width: CGFloat = .infinity,
                              live: [AgentLiveSession] = []) -> CGFloat {
        guard !rows.isEmpty else { return 0 }
        return rows.map { height(of: $0, width: width, live: live) }.reduce(0, +) + spacing * CGFloat(rows.count - 1)
    }
}

/// Numbers in the reader's region; costs in US dollars, the currency both
/// providers list their prices in.
/// The closed island's mark while agents work: the agent whose turn runs
/// longest inside its limit ring, and on the ring a badge for each place it
/// works, the app at 4:30 and the terminal at 1:30 beside it, with a count
/// inside the badge from two sessions up.
struct NotchAgentWorkingLayout: Equatable {
    /// How far from the ring's centre a badge sits, as a share of the ring:
    /// just outside the stroke, so it hides as little of the arc as it can.
    static let badgeReach: CGFloat = 0.523
    /// The black that parts a badge from the arc beneath it.
    static let cut: CGFloat = 1.5

    let provider: AgentProvider
    let terminal: Int
    let app: Int
    let ring: CGFloat

    init(provider: AgentProvider, terminal: Int, app: Int, budget: CGFloat) {
        self.provider = provider
        self.terminal = terminal
        self.app = app
        ring = max(10, min(22, budget))
    }

    /// The working agent's sessions by place, from the snapshot's turns.
    init?(_ live: [AgentLiveSession], budget: CGFloat) {
        // The snapshot keeps turns oldest first: its first runs longest.
        guard let provider = live.first?.provider else { return nil }
        let own = live.filter { $0.provider == provider }
        self.init(provider: provider, terminal: own.filter { $0.place == .terminal }.count,
                  app: own.filter { $0.place == .app }.count, budget: budget)
    }

    var stacked: Bool { terminal > 0 && app > 0 }
    var lineWidth: CGFloat { max(1.6, ring * 0.114) }
    var markSize: CGFloat { ring * 0.48 }
    var badgeHeight: CGFloat { ring * (stacked ? 0.4545 : 0.5) }
    var countSize: CGFloat { badgeHeight * 0.78 }

    func glyph(_ place: AgentSessionPlace) -> CGFloat {
        badgeHeight * (place == .terminal ? 0.8 : 0.68)
    }

    func padding(_ place: AgentSessionPlace) -> CGFloat { (badgeHeight - glyph(place)) / 2 }

    /// A badge's centre in the ring's box: 4:30, or 1:30 for the terminal
    /// while the app works too.
    func anchor(_ place: AgentSessionPlace) -> CGPoint {
        let reach = ring * Self.badgeReach * 0.5.squareRoot()
        let up = stacked && place == .terminal
        return CGPoint(x: ring / 2 + reach, y: ring / 2 + (up ? -reach : reach))
    }

    /// A square tile, widening to the right for a count's digits.
    func badgeWidth(_ place: AgentSessionPlace, count: Int) -> CGFloat {
        guard count > 1 else { return badgeHeight }
        let digits = CGFloat(String(count).count) * countSize * 0.62
        return padding(place) * 2 + 0.5 + glyph(place) + 1 + digits
    }

    var width: CGFloat {
        let badges = [(AgentSessionPlace.terminal, terminal), (.app, app)].filter { $0.1 > 0 }.map { place, count in
            anchor(place).x - badgeHeight / 2 + badgeWidth(place, count: count)
        }
        return max(ring, badges.max() ?? ring)
    }
}

enum AgentFormat {
    /// Spending colors: green under $100, yellow to $500, red beyond.
    enum SpendLevel: Equatable {
        case low, medium, high
    }

    static func spendLevel(_ value: Double) -> SpendLevel {
        if value >= 500 { return .high }
        if value >= 100 { return .medium }
        return .low
    }

    /// When a limit renews, on a 24-hour clock: "16:26" today, "Sat 15:33"
    /// on a later day, "Oct 30" beyond a week.
    static func resetTime(_ date: Date, now: Date, locale: Locale, calendar: Calendar = .autoupdatingCurrent) -> String {
        let style = Date.FormatStyle(locale: resetClock(locale), calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(style.hour(.twoDigits(amPM: .omitted)).minute())
        }
        if date.timeIntervalSince(now) < 6 * 86_400 {
            return date.formatted(style.weekday(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute())
        }
        return date.formatted(style.month(.abbreviated).day())
    }

    /// Reset times read on a 24-hour clock whatever the region's, so the
    /// resting island's narrow wing, which has no room for AM or PM, and the
    /// open island never seem to name different times.
    static func resetClock(_ locale: Locale) -> Locale {
        var components = Locale.Components(locale: locale)
        components.hourCycle = .zeroToTwentyThree
        return Locale(components: components)
    }

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
