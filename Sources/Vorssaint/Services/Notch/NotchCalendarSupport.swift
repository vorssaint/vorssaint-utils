// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import EventKit

struct NotchCalendarColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let fallback = Self(red: 0.35, green: 0.65, blue: 1)
}

struct NotchCalendarEvent: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let calendar: String
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String
    var color: NotchCalendarColor = .fallback
    var calendarItemIdentifier = ""
    var recurring = false
    /// How a countdown chosen from the event's menu remembers it; see
    /// `NotchCalendarSupport.countdownKey`.
    var countdownKey = ""
}

/// What the closed island counts down to: an event's start or, while the
/// event is happening, its end.
struct NotchCalendarCountdown: Equatable, Sendable {
    let event: NotchCalendarEvent
    let ongoing: Bool

    var target: Date { ongoing ? event.end : event.start }

    /// A start shows within `leadTime` before it; an end, during the hour
    /// before it and only once its event has begun.
    func isShown(at now: Date, leadTime: TimeInterval) -> Bool {
        target > now && target.timeIntervalSince(now) <= (ongoing ? NotchCalendarSupport.timeLeftLeadTime : leadTime)
            && (!ongoing || event.start <= now)
    }
}

/// Every countdown the closed island shows at once, nearest first. Events
/// that share the nearest moment take turns on the strip; a later one is
/// named by its time beside the clock.
struct NotchCalendarStack: Equatable, Sendable {
    let countdowns: [NotchCalendarCountdown]
    /// Seconds each event sharing the nearest moment stays on the strip.
    static let turn: TimeInterval = 5

    /// Nil for no countdowns, so a stack always has a first one.
    init?(_ countdowns: [NotchCalendarCountdown]) {
        guard !countdowns.isEmpty else { return nil }
        self.countdowns = countdowns
    }

    var first: NotchCalendarCountdown { countdowns[0] }
    /// The countdowns besides the one on the strip, for its "+1".
    var others: Int { countdowns.count - 1 }
    /// The countdowns that reach the nearest moment together.
    var together: [NotchCalendarCountdown] { countdowns.filter { $0.target == first.target } }
    /// Whether more than one event starts at the nearest moment. Ends that
    /// share it, with each other or with a start, do not count.
    var startsTogether: Bool { together.filter { !$0.ongoing }.count > 1 }
    /// The next later moment, when nothing shares the nearest one.
    var then: NotchCalendarCountdown? { together.count > 1 ? nil : countdowns.first { $0.target > first.target } }

    /// The countdown on the strip at `now`, turning every `turn` seconds.
    func shown(at now: Date) -> NotchCalendarCountdown {
        let together = together
        let turn = Int((now.timeIntervalSinceReferenceDate / Self.turn).rounded(.down))
        return together[((turn % together.count) + together.count) % together.count]
    }
}

/// The heads-up card under the closed island and the Up next list share
/// these measures, so the island sizes the card to what it draws.
enum NotchCalendarUpNextLayout {
    /// Rows the heads-up card shows; the rest read as "+N".
    static let headsUpRows = 3
    static let rowHeight: CGFloat = 44
    static let labelHeight: CGFloat = 14
    static let spacing: CGFloat = 6

    static func height(_ stack: NotchCalendarStack, limit: Int?) -> CGFloat {
        let shown = min(stack.countdowns.count, limit ?? .max)
        let labels = 1 + (stack.startsTogether ? 1 : 0) + (shown < stack.countdowns.count ? 1 : 0)
        return CGFloat(labels) * (labelHeight + spacing) + CGFloat(shown) * rowHeight
    }
}

/// One calendar offered in Settings, grouped under its account like Calendar.app.
struct NotchCalendarChoice: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let sourceID: String
    let source: String
    var color: NotchCalendarColor = .fallback
}

enum NotchCalendarSupport {
    /// How long before its end the event under way counts down.
    static let timeLeftLeadTime: TimeInterval = 60 * 60

    /// Minutes before a start the countdown appears; the settings menu
    /// offers the presets, and any stored value is held to the range.
    static let defaultCountdownLeadMinutes = 60
    static let countdownLeadPresets = [15, 30, 60, 120]
    static let countdownLeadRange = 5...240

    static func countdownLeadMinutes(_ minutes: Int) -> Int {
        min(countdownLeadRange.upperBound, max(countdownLeadRange.lowerBound, minutes))
    }

    static func countdownLeadTime(in defaults: UserDefaults = .standard) -> TimeInterval {
        let stored = defaults.object(forKey: DefaultsKey.notchCalendarCountdownLead) as? Int
        return TimeInterval(countdownLeadMinutes(stored ?? defaultCountdownLeadMinutes) * 60)
    }

    static func monthDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        let offset = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: month.start) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// The seven days around `date`, from the calendar's first weekday. Every
    /// week lies inside the 42-day grid `monthDays` reads for any of its days.
    static func weekDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: day) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func readInterval(month: Date?, now: Date, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? now
        if let month {
            let days = monthDays(containing: month, calendar: calendar)
            if let first = days.first, let last = days.last,
               let end = calendar.date(byAdding: .day, value: 1, to: last) {
                return DateInterval(start: first, end: calendar.isDate(month, equalTo: now, toGranularity: .month)
                                    ? max(end, weekEnd) : end)
            }
        }
        return DateInterval(start: today, end: weekEnd)
    }

    static func needsCurrentRead(visible: DateInterval, current: DateInterval,
                                 countdownEnabled: Bool) -> Bool {
        countdownEnabled && (visible.start > current.start || visible.end < current.end)
    }

    /// End dates are exclusive, including all-day events and midnight boundaries.
    static func events(_ events: [NotchCalendarEvent], on day: Date,
                       calendar: Calendar = .current) -> [NotchCalendarEvent] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return events.filter { $0.start < interval.end && $0.end > interval.start }.sorted {
            if $0.allDay != $1.allDay { return $0.allDay }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id < $1.id
        }
    }

    static func requestFailed(status: EKAuthorizationStatus, hasError: Bool) -> Bool {
        hasError || ![.fullAccess, .denied, .restricted].contains(status)
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults)
            && AppFeature.notchCalendar.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchCalendarEnabled)
            && NotchSupport.modules(in: defaults).contains(.calendar)
    }

    static func showsCountdown(in defaults: UserDefaults = .standard) -> Bool {
        showsCountdown(chosen: false, in: defaults)
    }

    /// An event chosen from its menu counts down even while the countdown
    /// for every event is off.
    static func showsCountdown(chosen: Bool, in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && (chosen || defaults.bool(forKey: DefaultsKey.notchCalendarCountdown))
    }

    static func showsTimeLeft(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchCalendarTimeLeft)
    }

    /// The number beside a row of the month grid. Rows start on the calendar's
    /// first weekday, so the same calendar numbers them: every day of a row
    /// then shares one number, where ISO weeks would straddle two rows on a
    /// Mac whose week starts on Sunday.
    static func weekNumber(of date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.weekOfYear, from: date)
    }

    /// What VoiceOver reads for that number, since no day's label names its week.
    static func weekNumberLabel(of date: Date, text: NotchCalendarStrings, calendar: Calendar = .current) -> String {
        String(format: text.weekNumber, weekNumber(of: date, calendar: calendar))
    }

    static func startsWeek(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.weekday, from: date) == calendar.firstWeekday
    }

    /// Whether a heads-up opens the island over a full-screen app that
    /// otherwise hides it.
    static func announcesInFullscreen(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.notchCalendarAnnounceInFullscreen)
    }

    /// Names the event a countdown was chosen for across refreshes, edits and
    /// relaunches: the event itself or, in a series, one occurrence by the
    /// date it first fell on, which moving that occurrence leaves unchanged.
    static func countdownKey(identifier: String, occurrence: Date?) -> String {
        guard let occurrence else { return identifier }
        return identifier + "@" + String(occurrence.timeIntervalSinceReferenceDate.rounded())
    }

    static func isChosen(_ event: NotchCalendarEvent, in chosen: Set<String>) -> Bool {
        !event.countdownKey.isEmpty && chosen.contains(event.countdownKey)
    }

    /// Events chosen from their menu in the island, by countdown key, each
    /// with the end it had when last read. Only these identifiers are kept,
    /// never an event's text, and each is forgotten once its event ends.
    static func chosenCountdowns(in defaults: UserDefaults = .standard) -> [String: Date] {
        (defaults.dictionary(forKey: DefaultsKey.notchCalendarChosenCountdowns) ?? [:]).compactMapValues { $0 as? Date }
    }

    static func setCountdown(_ chosen: Bool, for event: NotchCalendarEvent, in defaults: UserDefaults = .standard) {
        guard !event.countdownKey.isEmpty else { return }
        var choices = chosenCountdowns(in: defaults)
        choices[event.countdownKey] = chosen ? event.end : nil
        storeChosenCountdowns(choices, in: defaults)
    }

    static func storeChosenCountdowns(_ choices: [String: Date], in defaults: UserDefaults = .standard) {
        if choices.isEmpty { defaults.removeObject(forKey: DefaultsKey.notchCalendarChosenCountdowns) }
        else { defaults.set(choices, forKey: DefaultsKey.notchCalendarChosenCountdowns) }
    }

    /// The choices after a read: an event read again keeps its current end,
    /// so a moved event stays chosen, and a choice whose event has ended is
    /// forgotten. Nil when nothing changes, so a read writes no preference.
    static func refreshedChoices(_ choices: [String: Date], events: [NotchCalendarEvent],
                                 now: Date) -> [String: Date]? {
        var refreshed = choices
        for event in events where refreshed[event.countdownKey] != nil { refreshed[event.countdownKey] = event.end }
        refreshed = refreshed.filter { $0.value > now }
        return refreshed == choices ? nil : refreshed
    }

    /// Stored as excluded identifiers so a calendar added later starts shown.
    static func excludedCalendars(in defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: DefaultsKey.notchCalendarExcluded) ?? [])
    }

    static func setCalendar(_ identifier: String, shown: Bool, in defaults: UserDefaults = .standard) {
        var excluded = excludedCalendars(in: defaults)
        if shown { excluded.remove(identifier) } else { excluded.insert(identifier) }
        defaults.set(excluded.sorted(), forKey: DefaultsKey.notchCalendarExcluded)
    }

    /// The calendars to pass to EventKit: nil reads every calendar, including
    /// ones added later. An empty result means read nothing; the caller must
    /// not hand `[]` to EventKit, which treats it like nil.
    static func calendarsToRead<C>(_ calendars: [C], excluded: Set<String>,
                                   identifier: (C) -> String) -> [C]? {
        guard calendars.contains(where: { excluded.contains(identifier($0)) }) else { return nil }
        return calendars.filter { !excluded.contains(identifier($0)) }
    }

    /// Accounts in name order, each with its calendars in name order.
    static func grouped(_ choices: [NotchCalendarChoice]) -> [[NotchCalendarChoice]] {
        Dictionary(grouping: choices, by: \.sourceID).values
            .map { $0.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
            .sorted {
                let order = $0[0].source.localizedStandardCompare($1[0].source)
                return order == .orderedSame ? $0[0].sourceID < $1[0].sourceID : order == .orderedAscending
            }
    }

    static func ordered(_ events: [NotchCalendarEvent]) -> [NotchCalendarEvent] {
        var seen = Set<String>()
        return events.filter {
            $0.start.timeIntervalSinceReferenceDate.isFinite
                && $0.end.timeIntervalSinceReferenceDate.isFinite
                && $0.end > $0.start && seen.insert($0.id).inserted
        }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.id < $1.id
        }
    }

    static func upcoming(_ events: [NotchCalendarEvent], now: Date) -> [NotchCalendarEvent] {
        ordered(events).filter { $0.end > now }
    }

    static func next(_ events: [NotchCalendarEvent], now: Date) -> NotchCalendarEvent? {
        upcoming(events, now: now).first { !$0.allDay }
    }

    /// The compact island counts down to the nearer of the moments it follows:
    /// a timed event's start, with the countdown on or for an event chosen
    /// from its menu, and, with time left on, the end of one in progress. A
    /// start that coincides with an end leaves the event under way. Starts
    /// show within `leadTime`; see `NotchCalendarCountdown.isShown`.
    static func countdown(_ events: [NotchCalendarEvent], now: Date, starts: Bool, ends: Bool,
                          chosen: Set<String> = [], leadTime: TimeInterval) -> NotchCalendarCountdown? {
        countdowns(events, now: now, starts: starts, ends: ends, chosen: chosen, leadTime: leadTime).first
    }

    /// Every countdown shown at `now`, in the order `countdown` picks from:
    /// two meetings at one time both count down, so neither goes unseen.
    static func countdowns(_ events: [NotchCalendarEvent], now: Date, starts: Bool, ends: Bool,
                           chosen: Set<String> = [], leadTime: TimeInterval) -> [NotchCalendarCountdown] {
        ordered(events).filter { !$0.allDay }
            .flatMap { event in
                followedMoments(event, starts: starts, ends: ends, chosen: chosen)
                    .map { NotchCalendarCountdown(event: event, ongoing: $0) }
            }
            .filter { $0.isShown(at: now, leadTime: leadTime) }
            .enumerated()
            .sorted { lhs, rhs in
                let (a, b) = (lhs.element, rhs.element)
                if a.target != b.target { return a.target < b.target }
                if a.ongoing != b.ongoing { return a.ongoing }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Whether the island follows the event's start (false) and its end (true).
    private static func followedMoments(_ event: NotchCalendarEvent, starts: Bool, ends: Bool,
                                        chosen: Set<String>) -> [Bool] {
        (starts || isChosen(event, in: chosen) ? [false] : []) + (ends ? [true] : [])
    }

    /// The Controls tile names the next start at any distance within the
    /// week read, not only in the countdown's lead time. An appointment already
    /// in progress is known; the one after it is what comes next. The month
    /// grid can load weeks further ahead, where a weekday alone would read as
    /// this week's, so the tile stops at the week.
    static func tileEvent(_ events: [NotchCalendarEvent], now: Date,
                          calendar: Calendar = .current) -> NotchCalendarEvent? {
        let week = readInterval(month: nil, now: now, calendar: calendar)
        return ordered(events).first { !$0.allDay && $0.start > now && $0.start < week.end }
    }

    /// A start later today reads as its time; a later day adds its weekday.
    static func tileStartText(_ start: Date, now: Date, locale: Locale, calendar: Calendar = .current) -> String {
        var style = calendar.isDate(start, inSameDayAs: now)
            ? Date.FormatStyle.dateTime.hour().minute()
            : Date.FormatStyle.dateTime.weekday(.abbreviated).hour().minute()
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return start.formatted(style)
    }

    /// When the window before each moment followed opens and closes: the lead
    /// time before a start, the hour before an end, which opens no earlier
    /// than its event's start.
    static func countdownTransition(_ events: [NotchCalendarEvent], now: Date, starts: Bool, ends: Bool,
                                    chosen: Set<String> = [], leadTime: TimeInterval) -> Date? {
        ordered(events).filter { !$0.allDay }
            .flatMap { event in
                followedMoments(event, starts: starts, ends: ends, chosen: chosen).flatMap { ongoing in
                    ongoing ? [max(event.start, event.end.addingTimeInterval(-timeLeftLeadTime)), event.end]
                        : [event.start.addingTimeInterval(-leadTime), event.start]
                }
            }
            .filter { $0 > now }.min()
    }

    static let stripDotWidth: CGFloat = 6
    static let stripTitleSpacing: CGFloat = 5
    static let stripClockSpacing: CGFloat = 4

    /// The time beside the countdown clock in the closed island: when the
    /// event starts or, while it is happening, when it ends.
    static func timeText(_ countdown: NotchCalendarCountdown, locale: Locale) -> String {
        (countdown.ongoing ? "→\u{2009}" : "·\u{2009}")
            + countdown.target.formatted(.dateTime.hour().minute().locale(locale))
    }

    /// Whether the island announces `countdowns`: a start new since the
    /// last read that joins another countdown. A start alone needs no
    /// heads-up, the strip shows it. Returns the starts to remember, so each
    /// is announced once.
    static func headsUp(_ countdowns: [NotchCalendarCountdown],
                        announced: Set<String>) -> (announces: Bool, starts: Set<String>) {
        let ids = Set(countdowns.filter { !$0.ongoing }.map(\.event.id))
        return (!ids.subtracting(announced).isEmpty && countdowns.count > 1, ids)
    }

    /// Beside the clock when a later event follows the one counting down:
    /// "· then 2:15".
    static func thenText(_ countdown: NotchCalendarCountdown, then: String, locale: Locale) -> String {
        "·\u{2009}" + then + " " + countdown.target.formatted(.dateTime.hour().minute().locale(locale))
    }

    /// The time beside the strip's clock: the shown event's own time, or
    /// what follows it when nothing shares its moment.
    static func stackTimeText(_ stack: NotchCalendarStack, shown: NotchCalendarCountdown, then: String,
                              locale: Locale) -> String {
        stack.then.map { thenText($0, then: then, locale: locale) } ?? timeText(shown, locale: locale)
    }

    /// What leads the title: one event's dot and the gap after it. Several
    /// countdowns lead with the title alone; the "+1" after it counts them.
    static func titleMarkWidth(_ count: Int, dot: CGFloat = stripDotWidth, spacing: CGFloat) -> CGFloat {
        count > 1 ? 0 : dot + spacing
    }

    /// Beside another activity, where no title shows: one event's dot, or
    /// the "+1" for several.
    static func clockMarkWidth(_ count: Int, dot: CGFloat = stripDotWidth) -> CGFloat {
        count > 1 ? NotchCapsuleLayout.calendarBadgeWidth(count - 1) : dot
    }

    static func countdownText(until start: Date, now: Date) -> String {
        let seconds = max(0, Int(ceil(start.timeIntervalSince(now))))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func countdownAccessibilityText(until start: Date, now: Date, locale: Locale) -> String {
        let seconds = max(0, ceil(start.timeIntervalSince(now)))
        return Duration.seconds(seconds).formatted(.units(
            allowed: [.minutes, .seconds], width: .wide,
            fractionalPart: .hide(rounded: .down)).locale(locale))
    }

    /// The link Calendar resolves to one appointment. A series shares one
    /// identifier across its occurrences, so the clicked start (UTC, or the
    /// local day for all-day events) picks the right one.
    static func eventURL(_ event: NotchCalendarEvent, calendar: Calendar = .current) -> URL? {
        guard !event.calendarItemIdentifier.isEmpty,
              let identifier = event.calendarItemIdentifier
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var path = "ical://ekevent/"
        if event.recurring {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = event.allDay ? calendar.timeZone : TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            path += formatter.string(from: event.start) + "/"
        }
        return URL(string: path + identifier + "?method=show&options=more")
    }

    static func nextRefresh(_ events: [NotchCalendarEvent], now: Date,
                            calendar: Calendar = .current) -> Date {
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(900)
        return (upcoming(events, now: now).flatMap { [$0.start, $0.end] } + [midnight, now.addingTimeInterval(900)])
            .filter { $0 > now }.min() ?? now.addingTimeInterval(900)
    }
}
