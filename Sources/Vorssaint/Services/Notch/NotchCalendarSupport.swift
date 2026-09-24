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

    /// The compact island counts down to a start, never to an event already in progress.
    static func countdownEvent(_ events: [NotchCalendarEvent], now: Date) -> NotchCalendarEvent? {
        ordered(events).first {
            !$0.allDay && $0.start > now && $0.start.timeIntervalSince(now) <= countdownLeadTime
        }
    }

    static func countdownTransition(_ events: [NotchCalendarEvent], now: Date) -> Date? {
        ordered(events).filter { !$0.allDay && $0.start > now }
            .flatMap { [$0.start.addingTimeInterval(-countdownLeadTime), $0.start] }
            .filter { $0 > now }.min()
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
