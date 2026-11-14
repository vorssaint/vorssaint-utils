// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Writing the answer, and the questions whose answer is a day or a count.
///
/// Nothing here spells a word in English: dates come from `DateFormatter`,
/// counts from `DateComponentsFormatter`, and both read the language the
/// interface is in. A bar that answered "3 days" inside a Russian window would
/// be half-translated.
extension CommandBarDates {
    enum Text {
        static func date(_ date: Date, in zone: TimeZone, _ context: Context) -> String {
            let formatter = DateFormatter()
            formatter.locale = context.locale
            formatter.calendar = context.calendar
            formatter.timeZone = zone
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }

        static func clock(_ date: Date, in zone: TimeZone, _ context: Context) -> String {
            let formatter = DateFormatter()
            formatter.locale = context.locale
            formatter.calendar = context.calendar
            formatter.timeZone = zone
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        /// A day and its clock in one answer, joined the way the language
        /// joins them: "November 10, 2026 at 11:30 AM".
        static func moment(_ date: Date, in zone: TimeZone, _ context: Context) -> String {
            let formatter = DateFormatter()
            formatter.locale = context.locale
            formatter.calendar = context.calendar
            formatter.timeZone = zone
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        static func weekday(_ date: Date, in zone: TimeZone, _ context: Context) -> String {
            let formatter = DateFormatter()
            formatter.locale = context.locale
            formatter.calendar = context.calendar
            formatter.timeZone = zone
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
            return formatter.string(from: date)
        }

        static func monthAndYear(_ date: Date, in zone: TimeZone, _ context: Context) -> String {
            let formatter = DateFormatter()
            formatter.locale = context.locale
            formatter.calendar = context.calendar
            formatter.timeZone = zone
            formatter.setLocalizedDateFormatFromTemplate("MMMMy")
            return formatter.string(from: date)
        }

        static func interval(from start: Date, to end: Date, in zone: TimeZone,
                             _ context: Context) -> String {
            let formatter = DateIntervalFormatter()
            formatter.locale = context.locale
            formatter.calendar = context.calendar
            formatter.timeZone = zone
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: start, to: end)
        }

        /// "581 days", "23 hours", "150 minutes": one unit, because the
        /// question named one.
        static func count(_ value: Int, _ unit: Unit, _ context: Context) -> String? {
            var calendar = context.calendar
            calendar.locale = context.locale
            let formatter = DateComponentsFormatter()
            formatter.calendar = calendar
            formatter.unitsStyle = .full
            formatter.allowedUnits = unit.allowedUnits
            formatter.maximumUnitCount = 1
            var components = DateComponents()
            switch unit {
            case .second: components.second = value
            case .minute: components.minute = value
            case .hour: components.hour = value
            case .day, .weekday: components.day = value
            case .week: components.weekOfYear = value
            case .month: components.month = value
            case .year: components.year = value
            }
            return formatter.string(from: components)
        }

        /// A plain number: a week number is 46, never "2,046".
        static func number(_ value: Int, _ context: Context) -> String {
            let formatter = NumberFormatter()
            formatter.locale = context.locale
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            return formatter.string(from: NSNumber(value: value)) ?? String(value)
        }

        /// "(tomorrow)" and "(yesterday)", in the Mac's own words. Only a
        /// neighbouring day earns a note: a date a year away is not "tomorrow
        /// in 400 days".
        static func dayMarker(_ days: Int, _ context: Context) -> String? {
            guard days == 1 || days == -1 else { return nil }
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = context.locale
            formatter.dateTimeStyle = .named
            formatter.unitsStyle = .full
            let word = formatter.localizedString(from: DateComponents(day: days))
            return "(" + word + ")"
        }
    }

    // MARK: - A day on its own

    static func momentAnswer(_ tokens: [String], _ context: Context) -> Result? {
        guard let moment = moment(tokens[...], context) else { return nil }
        return result(for: moment, context)
    }

    static func result(for moment: Moment, _ context: Context) -> Result {
        let formatted = moment.hasTime
            ? Text.moment(moment.date, in: moment.zone, context)
            : Text.date(moment.date, in: moment.zone, context)
        return Result(formatted: formatted,
                      detail: Text.weekday(moment.date, in: moment.zone, context))
    }

    /// The card for a count: "150 days" over the day it lands on.
    static func result(count value: Int, unit: Unit, at target: Moment,
                       _ context: Context) -> Result? {
        guard let formatted = Text.count(value, unit, context) else { return nil }
        let detail = target.hasTime
            ? Text.moment(target.date, in: target.zone, context)
            : Text.date(target.date, in: target.zone, context)
        return Result(formatted: formatted, detail: detail)
    }

    // MARK: - How far away a moment is

    /// "days till 9 apr", "hrs since 9am", "2 weeks ago", "in 3 weeks".
    static func countdownAnswer(_ tokens: [String], _ context: Context) -> Result? {
        // A unit first: "days until …", "hrs till …", "weeks since …".
        if tokens.count >= 3, let unit = Unit.names[tokens[0]] {
            var backwards: Bool?
            if untilWords.contains(tokens[1]) {
                backwards = false
            } else if sinceWords.contains(tokens[1]) || pastWords.contains(tokens[1]) {
                backwards = true
            }
            if let backwards, tokens.count > 2, let target = moment(tokens[2...], context) {
                let aligned = withDirection(target, backwards: backwards, context)
                return counted(unit, to: aligned, backwards: backwards, context)
            }
        }

        // A number and a unit, with a direction somewhere in the sentence.
        var amount: Int?
        var unit: Unit?
        for index in tokens.indices.dropLast() {
            guard amount == nil, let value = Int(tokens[index]), value.magnitude <= 10_000,
                  let named = Unit.names[tokens[index + 1]] else { continue }
            amount = value
            unit = named
        }
        guard let amount, let unit else { return nil }

        let hasToday = tokens.contains(where: todayWords.contains)
        let hasPast = tokens.contains(where: pastWords.contains) || tokens.contains("-")
        let hasFuture = tokens.contains(where: futureWords.contains)
        // Without a direction "3 days" is not a question, and answering it
        // would push aside whatever the person was really looking for.
        guard hasToday || hasPast || hasFuture else { return nil }

        let backwards = hasPast
        guard let moved = shift(context.moment(at: context.now, hasTime: unit.isTime),
                                by: backwards ? -amount : amount, unit: unit, context) else {
            return nil
        }
        return result(for: moved, context)
    }

    /// A count of whole units between now and a moment.
    static func counted(_ unit: Unit, to target: Moment, backwards: Bool,
                        _ context: Context) -> Result? {
        let calendar = context.calendar(in: target.zone)
        let from = unit.isTime ? context.now : calendar.startOfDay(for: context.now)
        let to = unit.isTime ? target.date : calendar.startOfDay(for: target.date)
        guard let value = gap(from: from, to: to, unit: unit, context) else { return nil }
        return result(count: abs(value), unit: unit, at: target, context)
    }

    /// "till" looks forward and "since" looks back, whatever year the nearest
    /// reading of the written date landed in.
    static func withDirection(_ moment: Moment, backwards: Bool, _ context: Context) -> Moment {
        let calendar = context.calendar(in: moment.zone)
        let today = calendar.startOfDay(for: context.now)
        var candidate = moment
        for _ in 0..<8 {
            if backwards {
                if candidate.date <= context.now { return candidate }
            } else if candidate.date >= today {
                return candidate
            }
            guard let shifted = calendar.date(byAdding: .year, value: backwards ? -1 : 1,
                                              to: candidate.date) else { return candidate }
            candidate.date = shifted
        }
        return candidate
    }

    /// The whole units from one moment to another.
    static func gap(from start: Date, to end: Date, unit: Unit,
                    _ context: Context) -> Int? {
        let calendar = context.calendar
        switch unit {
        case .second: return calendar.dateComponents([.second], from: start, to: end).second
        case .minute: return calendar.dateComponents([.minute], from: start, to: end).minute
        case .hour: return calendar.dateComponents([.hour], from: start, to: end).hour
        case .day, .weekday:
            return calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: end)).day
        case .week:
            return calendar.dateComponents([.weekOfYear], from: start, to: end).weekOfYear
        case .month:
            return calendar.dateComponents([.month], from: start, to: end).month
        case .year:
            return calendar.dateComponents([.year], from: start, to: end).year
        }
    }

    // MARK: - A moment shifted

    /// "today + 3 weeks", "now + 90 min", "17.2.26 + 100 weekdays - 4".
    static func shiftAnswer(_ tokens: [String], _ context: Context) -> Result? {
        guard let firstOperator = tokens.firstIndex(where: { $0 == "+" || $0 == "-" }),
              firstOperator > 0 else { return nil }
        // A sign needs something to move: "+1 day" is the calculator's.
        guard var moved = moment(tokens[0..<firstOperator], context) else { return nil }

        var cursor = firstOperator
        while cursor < tokens.count {
            let sign = tokens[cursor] == "-" ? -1 : 1
            cursor += 1
            guard cursor < tokens.count, let term = scanTerm(tokens, &cursor) else { return nil }
            // A number without a unit means hours after a clock and days
            // after a date, which is how a person writes "3:45pm + 5".
            let unit = term.unit ?? (moved.hasTime ? .hour : .day)
            guard let shifted = shift(moved, by: sign * term.amount, unit: unit, context)
            else { return nil }
            moved = shifted
        }
        return result(for: moved, context)
    }

    /// The amount and unit after a sign: "3 weeks", "2h", "5" (hours after a
    /// clock, days after a date).
    static func scanTerm(_ tokens: [String], _ cursor: inout Int) -> (amount: Int, unit: Unit?)? {
        guard cursor < tokens.count else { return nil }
        let token = tokens[cursor]
        let digits = token.prefix(while: \.isNumber)
        guard !digits.isEmpty, let amount = Int(digits), amount.magnitude <= 10_000 else {
            return nil
        }
        let rest = String(token.dropFirst(digits.count))
        cursor += 1
        if !rest.isEmpty, let unit = Unit.names[rest] {
            return (amount, unit)
        }
        guard rest.isEmpty else { return nil }
        if cursor < tokens.count, let unit = Unit.names[tokens[cursor]] {
            cursor += 1
            return (amount, unit)
        }
        return (amount, nil)
    }

    /// Moves a moment. A day keeps the clock it was written with, across a
    /// daylight saving change; an hour adds exactly sixty minutes.
    static func shift(_ moment: Moment, by amount: Int, unit: Unit,
                      _ context: Context) -> Moment? {
        let calendar = context.calendar(in: moment.zone)
        guard let date = adding(amount, unit, to: moment.date, calendar) else { return nil }
        var shifted = moment
        shifted.date = date
        if unit.isTime { shifted.hasTime = true }
        return shifted
    }

    static func adding(_ amount: Int, _ unit: Unit, to date: Date, _ calendar: Calendar) -> Date? {
        if unit == .weekday { return addWeekdays(amount, to: date, calendar) }
        guard let component = unit.component else { return nil }
        return calendar.date(byAdding: component, value: amount, to: date)
    }

    /// Weekdays skip Saturday and Sunday. Public holidays are somebody else's
    /// calendar and are not skipped.
    static func addWeekdays(_ amount: Int, to date: Date, _ calendar: Calendar) -> Date? {
        var cursor = date
        var left = abs(amount)
        let step = amount < 0 ? -1 : 1
        var guardrail = 0
        while left > 0 {
            guardrail += 1
            if guardrail > 4_000 { return nil }
            guard let next = calendar.date(byAdding: .day, value: step, to: cursor) else { return nil }
            cursor = next
            let weekday = calendar.component(.weekday, from: cursor)
            if weekday != 1 && weekday != 7 { left -= 1 }
        }
        return cursor
    }
}
