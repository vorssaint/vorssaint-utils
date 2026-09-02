// SPDX-License-Identifier: GPL-3.0-or-later

import EventKit
import Foundation

struct CalendarEventWindow: Equatable {
    let start: Date
    let end: Date
}

enum CalendarDateDisplayFormat: String, CaseIterable, Identifiable {
    case system, dayMonth, weekdayDay, monthDay, custom
    var id: String { rawValue }

    func string(from date: Date, customPattern: String, locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        switch self {
        case .system: formatter.setLocalizedDateFormatFromTemplate("dMMM")
        case .dayMonth: formatter.setLocalizedDateFormatFromTemplate("ddMM")
        case .weekdayDay: formatter.setLocalizedDateFormatFromTemplate("EEE d")
        case .monthDay: formatter.setLocalizedDateFormatFromTemplate("MMM d")
        case .custom:
            formatter.dateFormat = customPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "dd/MM" : customPattern
        }
        return formatter.string(from: date)
    }
}

enum CalendarEventDots: String, CaseIterable, Identifiable {
    case none, singleNeutral, singleHighlighted, multiple
    var id: String { rawValue }
}

enum CalendarMenuBarComponent: String, CaseIterable, Identifiable {
    case icon, date, nextEvent
    var id: String { rawValue }
}

struct CalendarQuickEventDraft: Equatable {
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var calendarName: String?
}

/// A deliberately small, predictable parser for the quick-add field. It only
/// removes instructions it understands, so an unfamiliar phrase stays part of
/// the event title rather than silently changing the user's event.
enum CalendarQuickEventParser {
    static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> CalendarQuickEventDraft {
        var title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var start = now
        var allDay = false
        var duration: TimeInterval = 60 * 60
        var calendarName: String?

        func remove(_ pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [String] {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
            let range = NSRange(title.startIndex..., in: title)
            let matches = expression.matches(in: title, range: range)
            let values = matches.compactMap { Range($0.range, in: title).map { String(title[$0]) } }
            title = expression.stringByReplacingMatches(in: title, range: range, withTemplate: " ")
            return values
        }

        let lower = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if lower.contains("tomorrow") || lower.contains("amanha") {
            start = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            _ = remove("\\b(tomorrow|amanhã|amanha)\\b")
        } else if lower.contains("today") || lower.contains("hoje") {
            _ = remove("\\b(today|hoje)\\b")
        }

        if lower.contains("all day") || lower.contains("dia todo") {
            allDay = true
            start = calendar.startOfDay(for: start)
            duration = 24 * 60 * 60
            _ = remove("\\b(all day|dia todo)\\b")
        }

        if let match = remove("\\b(?:at|às|as)\\s*(\\d{1,2})(?::(\\d{2}))?h?\\b").first,
           let expression = try? NSRegularExpression(pattern: "(\\d{1,2})(?::(\\d{2}))?"),
           let result = expression.firstMatch(in: match, range: NSRange(match.startIndex..., in: match)),
           let hoursRange = Range(result.range(at: 1), in: match),
           let hours = Int(match[hoursRange]) {
            let minutes = result.range(at: 2).location == NSNotFound ? 0 : Int(match[Range(result.range(at: 2), in: match)!]) ?? 0
            start = calendar.date(bySettingHour: min(23, hours), minute: min(59, minutes), second: 0, of: start) ?? start
        }

        if let value = remove("\\b(?:for|por)\\s*(\\d+)\\s*(minutes?|minutos?|hours?|horas?)\\b").first,
           let expression = try? NSRegularExpression(pattern: "(\\d+)\\s*(minutes?|minutos?|hours?|horas?)", options: [.caseInsensitive]),
           let result = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
           let amountRange = Range(result.range(at: 1), in: value), let unitRange = Range(result.range(at: 2), in: value),
           let amount = Int(value[amountRange]) {
            duration = TimeInterval(amount * (value[unitRange].lowercased().hasPrefix("h") ? 3_600 : 60))
        }

        if let name = remove("/(\\S+)").first?.dropFirst(), !name.isEmpty { calendarName = String(name) }
        title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(title: title.isEmpty ? input.trimmingCharacters(in: .whitespacesAndNewlines) : title,
                     startDate: start,
                     endDate: start.addingTimeInterval(duration),
                     isAllDay: allDay,
                     calendarName: calendarName)
    }
}

enum CalendarSupport {
    static func menuBarComponents(from rawValue: String?, fallbackStyle: CalendarIconStyle = .icon) -> [CalendarMenuBarComponent] {
        let parsed = rawValue?
            .split(separator: ",")
            .compactMap { CalendarMenuBarComponent(rawValue: String($0)) }
            .uniqued()
        if let parsed, !parsed.isEmpty {
            return parsed
        }
        switch fallbackStyle {
        case .icon: return [.icon]
        case .date: return [.date]
        case .nextEvent: return [.nextEvent]
        }
    }

    static func encodedMenuBarComponents(_ components: [CalendarMenuBarComponent]) -> String {
        let unique = components.uniqued()
        return unique.isEmpty ? CalendarMenuBarComponent.icon.rawValue : unique.map(\.rawValue).joined(separator: ",")
    }

    /// The cache covers the visible month and enough future time to keep local
    /// notifications current. A calendar control must never reduce this range
    /// to a single day, otherwise past-day selection and month indicators lie.
    static func eventWindow(around date: Date, calendar: Calendar = .autoupdatingCurrent) -> CalendarEventWindow {
        let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let end = calendar.date(byAdding: .month, value: 3, to: monthStart) ?? monthStart.addingTimeInterval(90 * 86_400)
        return .init(start: start, end: end)
    }

    static func overlapsDay(start: Date, end: Date, day: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else { return false }
        return start < dayEnd && end > calendar.startOfDay(for: day)
    }

    static func visibleEvents(_ events: [EKEvent],
                              showPastEvents: Bool,
                              showDeclinedEvents: Bool,
                              now: Date = Date()) -> [EKEvent] {
        events.filter {
            (showPastEvents || $0.endDate >= now)
                && (showDeclinedEvents || !isDeclined($0))
        }
    }

    static func dayEvents(for day: Date,
                          in events: [EKEvent],
                          showDeclinedEvents: Bool,
                          calendar: Calendar = .autoupdatingCurrent) -> [EKEvent] {
        events.filter {
            overlapsDay(start: $0.startDate, end: $0.endDate, day: day, calendar: calendar)
                && (showDeclinedEvents || !isDeclined($0))
        }
    }

    static func dayEventDotMode(for day: Date,
                                in events: [EKEvent],
                                showDeclinedEvents: Bool,
                                calendar: Calendar = .autoupdatingCurrent) -> CalendarEventDots {
        let count = dayEvents(for: day, in: events, showDeclinedEvents: showDeclinedEvents, calendar: calendar).count
        if count == 0 { return .none }
        if count == 1 { return .singleHighlighted }
        return .multiple
    }

    static func eventListHeight(for eventCount: Int,
                                maximumVisibleRows: Int = 5,
                                rowHeight: CGFloat = 44,
                                minimumHeight: CGFloat = 60) -> CGFloat {
        guard eventCount > 0 else { return minimumHeight }
        let visibleRows = min(maximumVisibleRows, eventCount)
        return max(minimumHeight, CGFloat(visibleRows) * rowHeight)
    }

    static func eventDetailHeight() -> CGFloat {
        132
    }

    static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) ?? false
    }

    static func calendarDays(for month: Date, calendar: Calendar = .autoupdatingCurrent) -> [[Date?]] {
        calendarDays(for: month, showAdjacentMonthDays: false, calendar: calendar)
    }

    static func calendarDays(for month: Date,
                             showAdjacentMonthDays: Bool,
                             calendar: Calendar = .autoupdatingCurrent) -> [[Date?]] {
        guard let range = calendar.dateInterval(of: .month, for: month),
              let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: range.start) - calendar.firstWeekday
        let padding = (firstWeekday + 7) % 7
        let totalDays = padding + days.count
        let totalCells = Int(ceil(Double(totalDays) / 7.0)) * 7
        let trailing = max(0, totalCells - totalDays)
        var cells: [Date?] = []
        for offset in 0..<padding {
            let leadDate = calendar.date(byAdding: .day, value: offset - padding, to: range.start)
            cells.append(showAdjacentMonthDays ? leadDate : nil)
        }
        for day in days {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: range.start))
        }
        if showAdjacentMonthDays {
            for offset in 0..<trailing {
                let nextDate = calendar.date(byAdding: .day, value: days.count + offset, to: range.start)
                cells.append(nextDate)
            }
        } else {
            cells.append(contentsOf: Array(repeating: nil, count: trailing))
        }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }

    static func duration(from interval: TimeInterval,
                         strings: CalendarStrings = .current(.enUS)) -> String {
        strings.duration(from: interval)
    }

    static func selectedCalendarIDs(from data: Data?) -> Set<String>? {
        guard let data, let ids = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return Set(ids)
    }

    static func encodedCalendarIDs(_ ids: Set<String>) -> Data? {
        try? JSONEncoder().encode(ids.sorted())
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
