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
}

/// What the closed island counts down to: an event's start or, while the
/// event is happening, its end.
struct NotchCalendarCountdown: Equatable, Sendable {
    let event: NotchCalendarEvent
    let ongoing: Bool

    var target: Date { ongoing ? event.end : event.start }

    /// Each moment shows during the hour before it; an end, only once its event has begun.
    func isShown(at now: Date) -> Bool {
        target > now && target.timeIntervalSince(now) <= NotchCalendarSupport.countdownLeadTime
            && (!ongoing || event.start <= now)
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
    static let countdownLeadTime: TimeInterval = 60 * 60

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
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchCalendarCountdown)
    }

    static func showsTimeLeft(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchCalendarTimeLeft)
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
    /// a timed event's start and, with time left on, the end of one in
    /// progress. A start that coincides with an end leaves the event under way.
    static func countdown(_ events: [NotchCalendarEvent], now: Date,
                          starts: Bool, ends: Bool) -> NotchCalendarCountdown? {
        let kinds = (starts ? [false] : []) + (ends ? [true] : [])
        return ordered(events).filter { !$0.allDay }
            .flatMap { event in kinds.map { NotchCalendarCountdown(event: event, ongoing: $0) } }
            .filter { $0.isShown(at: now) }
            .min { $0.target != $1.target ? $0.target < $1.target : $0.ongoing && !$1.ongoing }
    }

    /// The Controls tile names the next start at any distance within the
    /// week read, not only in the countdown's hour. An appointment already
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

    /// The hour before each moment followed opens and closes; an end's hour
    /// opens no earlier than its event's start.
    static func countdownTransition(_ events: [NotchCalendarEvent], now: Date,
                                    starts: Bool, ends: Bool) -> Date? {
        ordered(events).filter { !$0.allDay }
            .flatMap { event in
                (starts ? [event.start.addingTimeInterval(-countdownLeadTime), event.start] : [])
                    + (ends ? [max(event.start, event.end.addingTimeInterval(-countdownLeadTime)), event.end] : [])
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
