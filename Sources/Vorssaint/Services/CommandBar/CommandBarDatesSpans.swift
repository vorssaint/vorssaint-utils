// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The two questions that are about a stretch of time rather than a moment:
/// the gap between two of them, and the facts a calendar knows about one.
extension CommandBarDates {
    // MARK: - The gap between two moments

    /// "jul 4 - today", "may 1 to may 31", "days between june 1 and june 29",
    /// "9:30 - 7:00 to minutes", "10pm to 2am".
    static func spanAnswer(_ tokens: [String], _ context: Context) -> Result? {
        var words = tokens
        var requested: Unit?
        // A unit asked for at the end: "to minutes", "in hours".
        if words.count >= 3, words[words.count - 2] == "to" || words[words.count - 2] == "in",
           let unit = Unit.names[words[words.count - 1]] {
            requested = unit
            words.removeLast(2)
        }
        // …or at the start: "days between …".
        if words.count >= 2, let unit = Unit.names[words[0]], words[1] == "between" {
            requested = unit
            words.removeFirst()
        }

        var left: ArraySlice<String>
        var right: ArraySlice<String>
        var inclusive = false
        var arithmetic = false
        if let between = words.firstIndex(of: "between") {
            guard let and = words[(between + 1)...].firstIndex(of: "and") else { return nil }
            left = words[(between + 1)..<and]
            right = words[(and + 1)...]
        } else {
            var separator: Int?
            for index in words.indices where index > 0 {
                if words[index] == "through" || words[index] == "thru" {
                    separator = index
                    inclusive = true
                } else if words[index] == "to" {
                    separator = index
                } else if words[index] == "-" {
                    separator = index
                    arithmetic = true
                } else {
                    continue
                }
                break
            }
            guard let separator else { return nil }
            left = words[0..<separator]
            right = words[(separator + 1)...]
        }
        guard !left.isEmpty, !right.isEmpty,
              let start = moment(left, context), let end = moment(right, context) else {
            return nil
        }

        var endDate = end.date
        // Two times without a date run forward: 10pm to 2am is four hours.
        if start.hasTime, end.hasTime, endDate < start.date,
           let next = context.calendar.date(byAdding: .day, value: 1, to: endDate) {
            endDate = next
        }
        // Two dates read without a year each pick their own nearest year, which
        // can leave "may 1 to may 31" with the end a year before the start. A
        // span runs forward, so hold the end to the start's year.
        if !arithmetic, !start.hasTime, !end.hasTime, endDate < start.date,
           let next = context.calendar.date(byAdding: .year, value: 1, to: endDate) {
            endDate = next
        }
        // "through" counts the last day too.
        if inclusive, !end.hasTime, let next = context.calendar.date(byAdding: .day, value: 1, to: endDate) {
            endDate = next
        }

        let unit: Unit
        if let requested {
            unit = requested
        } else if start.hasTime, end.hasTime {
            // A quarter of an hour is not nothing: a span that is not whole
            // hours is answered in minutes.
            let seconds = endDate.timeIntervalSince(start.date)
            unit = seconds.truncatingRemainder(dividingBy: 3600) == 0 ? .hour : .minute
        } else {
            unit = .day
        }
        guard let value = gap(from: start.date, to: endDate, unit: unit, context) else { return nil }

        var target = end
        if inclusive, !end.hasTime,
           let last = context.calendar.date(byAdding: .day, value: -1, to: endDate) {
            target.date = last
        } else {
            target.date = endDate
        }

        // A "-" between two dates is subtraction, not a span: "jul 4 - today"
        // is a negative count and keeps its sign.
        if arithmetic, !start.hasTime, !end.hasTime {
            guard let signed = gap(from: end.date, to: start.date, unit: unit, context) else { return nil }
            return result(count: signed, unit: unit, at: start, context)
        }
        return result(count: abs(value), unit: unit, at: target, context)
    }

    // MARK: - Facts about a date

    /// "weekday on 1 january 2030", "days in february 2028", "week number",
    /// "day of year", "age 3 may 1990", "days left in 2026",
    /// "hours left in today".
    static func factAnswer(_ tokens: [String], _ context: Context) -> Result? {
        guard tokens.count >= 2 else { return nil }

        if tokens[0] == "weekday", tokens[1] == "on" || tokens[1] == "of",
           let target = moment(tokens[2...], context) {
            return Result(formatted: Text.weekday(target.date, in: target.zone, context),
                          detail: Text.date(target.date, in: target.zone, context))
        }

        if tokens[0] == "week", tokens[1] == "number"
            || (tokens[1] == "of" && tokens.count > 2 && tokens[2] == "year") {
            let week = context.workingCalendar.component(.weekOfYear, from: context.now)
            return Result(formatted: Text.number(week, context),
                          detail: Text.date(context.now, in: context.zone, context))
        }

        if tokens[0] == "day", tokens[1] == "of", tokens.count > 2, tokens[2] == "year" {
            let day = context.workingCalendar.ordinality(of: .day, in: .year, for: context.now) ?? 0
            return Result(formatted: Text.number(day, context),
                          detail: Text.date(context.now, in: context.zone, context))
        }

        if tokens[0] == "age", let birth = moment(tokens[1...], context) {
            let calendar = context.calendar(in: birth.zone)
            guard let years = calendar.dateComponents([.year], from: birth.date, to: context.now).year,
                  let formatted = Text.count(years, .year, context) else { return nil }
            return Result(formatted: formatted, detail: Text.date(birth.date, in: birth.zone, context))
        }

        // "days left in 2026", "hours left in today".
        if let unit = Unit.names[tokens[0]], tokens.count >= 3, tokens[1] == "left",
           tokens[2] == "in", let period = periodEnd(tokens[3...], context) {
            // What is left of a day of days starts tomorrow: part of today
            // was never a whole day.
            let from: Date
            if unit.isTime {
                from = context.now
            } else {
                from = context.calendar.date(byAdding: .day, value: 1,
                                             to: context.calendar.startOfDay(for: context.now))
                    ?? context.now
            }
            guard let value = gap(from: from, to: period.end, unit: unit, context),
                  let formatted = Text.count(value, unit, context) else { return nil }
            return Result(formatted: formatted, detail: Text.date(period.last, in: context.zone, context))
        }

        // "days in february 2028", "days in 2028".
        if let unit = Unit.names[tokens[0]], tokens.count >= 3, tokens[1] == "in" {
            let calendar = context.workingCalendar
            if let month = months[foldedWord(tokens[2])] {
                let year = tokens.count > 3 ? (yearNumber(tokens[3]) ?? calendar.component(.year, from: context.now))
                    : calendar.component(.year, from: context.now)
                guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                      let days = calendar.range(of: .day, in: .month, for: start)?.count,
                      let formatted = Text.count(days, unit, context) else { return nil }
                return Result(formatted: formatted,
                              detail: Text.monthAndYear(start, in: context.zone, context))
            }
            if let year = yearNumber(tokens[2]), tokens.count == 3 {
                guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                      let days = calendar.range(of: .day, in: .year, for: start)?.count,
                      let formatted = Text.count(days, unit, context) else { return nil }
                return Result(formatted: formatted, detail: Text.number(year, context))
            }
        }
        return nil
    }

    /// The end of a period named in words — "2026", "today", "march", "this
    /// month" — and the last day inside it.
    static func periodEnd(_ tokens: ArraySlice<String>, _ context: Context)
        -> (end: Date, last: Date)? {
        let words = Array(tokens)
        let calendar = context.workingCalendar
        var cursor = 0
        while cursor < words.count, words[cursor] == "the" || words[cursor] == "this" { cursor += 1 }
        guard cursor < words.count else { return nil }
        if todayWords.contains(words[cursor]) {
            guard let end = calendar.date(byAdding: .day, value: 1,
                                          to: calendar.startOfDay(for: context.now)),
                  let last = calendar.date(byAdding: .day, value: -1, to: end) else { return nil }
            return (end, last)
        }
        var forward = 0
        if let direction = leadingDirection(words[cursor]) {
            forward = direction
            cursor += 1
        }
        guard cursor == words.count - 1 else { return nil }
        let period = words[cursor]

        if let year = yearNumber(period) {
            let target = year + forward
            guard let start = calendar.date(from: DateComponents(year: target, month: 1, day: 1)),
                  let end = calendar.date(byAdding: .year, value: 1, to: start),
                  let last = calendar.date(byAdding: .day, value: -1, to: end) else { return nil }
            return (end, last)
        }
        if let month = months[foldedWord(period)] {
            let year = calendar.component(.year, from: context.now) + forward
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start),
                  let last = calendar.date(byAdding: .day, value: -1, to: end) else { return nil }
            return (end, last)
        }
        if let unit = Unit.names[period], let component = unit.component {
            guard let anchor = calendar.date(byAdding: component, value: forward, to: context.now),
                  let interval = calendar.dateInterval(of: component, for: anchor),
                  let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else {
                return nil
            }
            return (interval.end, last)
        }
        return nil
    }
}
