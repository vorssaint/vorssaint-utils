// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reading a moment out of words: a clock, a date, a named day.
///
/// Every reader here consumes tokens from a fixed start and reports where it
/// stopped, so the caller can require that the whole question was understood.
/// That requirement is what keeps a launcher safe: "the 3 body problem" is not
/// a date because no reader can swallow all of it.
extension CommandBarDates {
    struct TimeOfDay {
        var hour: Int
        var minute: Int
    }

    // MARK: - Clocks

    /// A clock at `index`: "9am", "9:30", "17:45", "5 pm", "noon".
    static func scanClock(_ tokens: [String], _ index: Int, _ context: Context)
        -> (time: TimeOfDay, next: Int)? {
        guard index < tokens.count else { return nil }
        let token = tokens[index]
        if token == "midday" || token == "noon" { return (TimeOfDay(hour: 12, minute: 0), index + 1) }
        if token == "midnight" { return (TimeOfDay(hour: 0, minute: 0), index + 1) }

        var body = token
        var meridiem: String?
        for suffix in ["am", "pm"] where body.hasSuffix(suffix) {
            meridiem = suffix
            body.removeLast(suffix.count)
            break
        }
        var next = index + 1
        // "5 pm" written as two words.
        if meridiem == nil, index + 1 < tokens.count,
           (tokens[index + 1] == "am" || tokens[index + 1] == "pm"),
           !body.isEmpty, body.allSatisfy(\.isNumber) {
            meridiem = tokens[index + 1]
            next = index + 2
        }

        let parts = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 2 && $0.allSatisfy(\.isNumber) }),
              let value = Int(parts[0]) else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) ?? -1 : 0
        guard (0..<60).contains(minute) else { return nil }

        if let meridiem {
            guard (1...12).contains(value) else { return nil }
            return (TimeOfDay(hour: value % 12 + (meridiem == "pm" ? 12 : 0), minute: minute), next)
        }
        // Without am or pm only a written hour with a colon is a clock: "9"
        // alone is a number, and a number alone is a search.
        guard parts.count == 2, (0...23).contains(value) else { return nil }
        return (TimeOfDay(hour: value, minute: minute), next)
    }

    /// Puts a clock on a day, in that day's own time zone.
    static func attaching(_ time: TimeOfDay, to date: Date, in zone: TimeZone,
                          _ context: Context) -> Date? {
        let calendar = context.calendar(in: zone)
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: date)
    }

    // MARK: - Moments

    /// A moment that has to cover the whole question.
    static func moment(_ tokens: ArraySlice<String>, _ context: Context) -> Moment? {
        let words = Array(tokens)
        var index = 0
        guard let moment = scanMoment(words, &index, context), index == words.count else {
            return nil
        }
        return moment
    }

    /// A moment starting at `index`; on success `index` sits just after it.
    static func scanMoment(_ tokens: [String], _ index: inout Int, _ context: Context) -> Moment? {
        // "monday in 3 weeks" names a weekday and moves the whole week.
        if index + 3 < tokens.count,
           let weekday = weekdays[foldedWord(tokens[index])],
           tokens[index + 1] == "in",
           let count = Int(tokens[index + 2]), (0...520).contains(count),
           Unit.names[tokens[index + 3]] == .week,
           let base = context.workingCalendar.date(byAdding: .weekOfYear, value: count,
                                                   to: context.now),
           let date = weekdayDate(weekday, inWeekOf: base, context) {
            index += 4
            return context.moment(at: date, hasTime: false)
        }

        guard var moment = scanBase(tokens, &index, context) else { return nil }

        // "tomorrow at 9am", and "tomorrow 3pm" without the word.
        if index < tokens.count, tokens[index] == "at" || tokens[index] == "@" {
            if let clock = scanClock(tokens, index + 1, context) {
                moment = withClock(moment, clock.time, context)
                index = clock.next
            }
        } else if index < tokens.count, let clock = scanClock(tokens, index, context),
                  moment.hasTime == false {
            moment = withClock(moment, clock.time, context)
            index = clock.next
        }
        return moment
    }

    private static func withClock(_ moment: Moment, _ time: TimeOfDay, _ context: Context) -> Moment {
        guard let date = attaching(time, to: moment.date, in: moment.zone, context) else {
            return moment
        }
        return Moment(date: date, hasTime: true, zone: moment.zone)
    }

    /// The one-token moment forms: a named day, a written date, a clock.
    static func scanBase(_ tokens: [String], _ index: inout Int, _ context: Context) -> Moment? {
        guard index < tokens.count else { return nil }
        let token = tokens[index]
        let calendar = context.calendar

        if token == "now" {
            index += 1
            return context.moment(at: context.now, hasTime: true)
        }
        if todayWords.contains(token) {
            index += 1
            return context.moment(at: calendar.startOfDay(for: context.now), hasTime: false)
        }
        if tomorrowWords.contains(token) {
            index += 1
            guard let date = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: context.now))
            else { return nil }
            return context.moment(at: date, hasTime: false)
        }
        if yesterdayWords.contains(token) {
            index += 1
            guard let date = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: context.now))
            else { return nil }
            return context.moment(at: date, hasTime: false)
        }

        // "next monday", "last friday", "this friday", "next week".
        if let direction = leadingDirection(token), index + 1 < tokens.count {
            let following = tokens[index + 1]
            if let weekday = weekdays[foldedWord(following)] {
                guard let date = weekdayDate(weekday, direction: direction, context) else { return nil }
                index += 2
                return context.moment(at: date, hasTime: false)
            }
            if let unit = Unit.names[following], let component = unit.component {
                guard let shifted = calendar.date(byAdding: component, value: direction, to: context.now)
                else { return nil }
                index += 2
                return context.moment(at: unit.isTime ? shifted : calendar.startOfDay(for: shifted),
                                      hasTime: unit.isTime)
            }
        }

        // "end of month", "start of next year".
        if (endWords.contains(token) || startWords.contains(token)),
           let period = scanPeriod(tokens, index, context) {
            index = period.next
            return context.moment(at: period.date, hasTime: false)
        }

        // A written date: "aug 25", "25 august", "october 28th", "19.2.27",
        // "9/4", "9jul".
        if let dated = scanDate(tokens, index, context) {
            index = dated.next
            return context.moment(at: dated.date, hasTime: false, zone: context.zone)
        }

        // A clock on its own means today, at that time.
        if let clock = scanClock(tokens, index, context) {
            guard let date = attaching(clock.time, to: calendar.startOfDay(for: context.now),
                                       in: context.zone, context) else { return nil }
            index = clock.next
            return context.moment(at: date, hasTime: true)
        }
        return nil
    }

    /// +1 for "next", -1 for "last", 0 for "this".
    static func leadingDirection(_ token: String) -> Int? {
        if nextWords.contains(token) { return 1 }
        if lastWords.contains(token) { return -1 }
        if thisWords.contains(token) { return 0 }
        return nil
    }

    // MARK: - Written dates

    /// Reads a date at `index`. Years are optional and, when missing, the
    /// nearest one wins: a date three days in the past means three days ago,
    /// not eleven months from now.
    static func scanDate(_ tokens: [String], _ index: Int, _ context: Context)
        -> (date: Date, next: Int)? {
        let token = tokens[index]

        // "19.2.27", "25/12", "9/4": dots are day first, slashes follow the
        // Mac's own order.
        if let written = scanNumericDate(token, context) {
            return (written, index + 1)
        }

        // "9jul", "25aug": a day and a month typed as one word.
        if let first = token.first, first.isNumber {
            let digits = token.prefix(while: \.isNumber)
            let rest = token.dropFirst(digits.count)
            if !digits.isEmpty, !rest.isEmpty, let day = Int(digits), (1...31).contains(day),
               let month = months[foldedWord(String(rest))],
               let date = nearestDate(month: month, day: day, year: nil, context) {
                return (date, index + 1)
            }
        }

        // "aug 25", "august 25th", "sept 3 2027".
        if let month = months[foldedWord(token)] {
            guard index + 1 < tokens.count else { return nil }
            // "apr 2027": a month followed by a year has no day to read, so it
            // is the first of that month.
            if let year = yearNumber(tokens[index + 1]) {
                guard let date = nearestDate(month: month, day: 1, year: year, context)
                else { return nil }
                return (date, index + 2)
            }
            guard let day = dayNumber(tokens[index + 1]),
                  (1...31).contains(day) else { return nil }
            var next = index + 2
            var year: Int?
            if next < tokens.count, let written = yearNumber(tokens[next]) {
                year = written
                next += 1
            }
            guard let date = nearestDate(month: month, day: day, year: year, context) else { return nil }
            return (date, next)
        }

        // "25 august", "9 april", "29th of october", "3 may 1990".
        if let day = dayNumber(token), (1...31).contains(day) {
            var next = index + 1
            if next < tokens.count, tokens[next] == "of" { next += 1 }
            guard next < tokens.count, let month = months[foldedWord(tokens[next])] else { return nil }
            next += 1
            var year: Int?
            if next < tokens.count, let written = yearNumber(tokens[next]) {
                year = written
                next += 1
            }
            guard let date = nearestDate(month: month, day: day, year: year, context) else { return nil }
            return (date, next)
        }
        return nil
    }

    /// "19.2.27", "28.8", "25/12", "12/25/2026", "19.2.2027".
    static func scanNumericDate(_ token: String, _ context: Context) -> Date? {
        let separator: Character
        if token.contains("/") { separator = "/" }
        else if token.contains(".") && !token.contains(":") { separator = "." }
        else { return nil }
        var parts = token.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        // A trailing dot is punctuation, not an empty part: "28. aug".
        if parts.count > 1, parts.last?.isEmpty == true { parts.removeLast() }
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && $0.count <= 4 }),
              let first = Int(parts[0]), let second = Int(parts[1]) else { return nil }

        let dayFirst: Bool
        if separator == "." {
            dayFirst = true
        } else {
            dayFirst = dayComesFirst(locale: context.locale)
        }

        var day = dayFirst ? first : second
        var month = dayFirst ? second : first
        var year: Int?
        // "2026.07.28": a four-digit first part is a year, whatever the order.
        if parts.count == 3, parts[0].count == 4 {
            year = first
            month = second
            day = Int(parts[2]) ?? 0
        } else if parts.count == 3 {
            year = Int(parts[2]).map(normalizedYear)
        }
        guard (1...31).contains(day), (1...12).contains(month) else { return nil }
        return nearestDate(month: month, day: day, year: year, context)
    }

    /// Whether this Mac writes the day before the month.
    static func dayComesFirst(locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale)
            ?? "M/d/y"
        guard let day = format.firstIndex(of: "d"), let month = format.firstIndex(of: "M")
        else { return false }
        return day < month
    }

    /// 00 to 68 are this century, 69 to 99 the last one — the rule every
    /// two-digit year in every form has followed since 1998.
    static func normalizedYear(_ year: Int) -> Int {
        switch year {
        case 0...68: return 2000 + year
        case 69...99: return 1900 + year
        default: return year
        }
    }

    /// The day written as a number, with or without an ordinal suffix.
    static func dayNumber(_ token: String) -> Int? {
        var text = token
        if text.hasSuffix(".") { text.removeLast() }
        for suffix in ["st", "nd", "rd", "th"] where text.hasSuffix(suffix) {
            let digits = text.dropLast(suffix.count)
            guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
            return Int(digits)
        }
        guard !text.isEmpty, text.count <= 2, text.allSatisfy(\.isNumber) else { return nil }
        return Int(text)
    }

    /// A four-digit year, or a two-digit one after a date that is already
    /// unmistakable.
    static func yearNumber(_ token: String) -> Int? {
        let text = token.hasSuffix(".") ? String(token.dropLast()) : token
        guard text.count == 4, text.allSatisfy(\.isNumber), let year = Int(text),
              (1000...2999).contains(year) else { return nil }
        return year
    }

    /// The nearest year in which that day exists. 29 February waits for the
    /// next leap year instead of sliding into 1 March.
    static func nearestDate(month: Int, day: Int, year: Int?, _ context: Context) -> Date? {
        let calendar = context.calendar
        func make(_ year: Int) -> Date? {
            let components = DateComponents(year: year, month: month, day: day, hour: 0)
            guard let date = calendar.date(from: components),
                  calendar.component(.month, from: date) == month,
                  calendar.component(.day, from: date) == day else { return nil }
            return date
        }
        if let year { return make(year) }

        let current = calendar.component(.year, from: context.now)
        var best: Date?
        for candidate in (current - 8)...(current + 8) {
            guard let date = make(candidate) else { continue }
            if let known = best,
               abs(date.timeIntervalSince(context.now)) >= abs(known.timeIntervalSince(context.now)) {
                continue
            }
            best = date
        }
        return best
    }

    // MARK: - Weekdays

    /// "next monday" (direction 1), "last friday" (-1), "this friday" (0).
    static func weekdayDate(_ weekday: Int, direction: Int, _ context: Context) -> Date? {
        let calendar = context.workingCalendar
        let today = calendar.startOfDay(for: context.now)
        let current = calendar.component(.weekday, from: today)
        var delta = weekday - current
        switch direction {
        case 0:
            break
        case 1:
            // "next" is strictly after today: on a Monday, "next monday" is
            // a week away, not this minute.
            if delta <= 0 { delta += 7 }
        default:
            if delta >= 0 { delta -= 7 }
        }
        return calendar.date(byAdding: .day, value: delta, to: today)
    }

    /// The weekday inside the week that holds `base`.
    static func weekdayDate(_ weekday: Int, inWeekOf base: Date, _ context: Context) -> Date? {
        let calendar = context.workingCalendar
        guard let week = calendar.dateInterval(of: .weekOfYear, for: base) else { return nil }
        let first = calendar.component(.weekday, from: week.start)
        let delta = (weekday - first + 7) % 7
        return calendar.date(byAdding: .day, value: delta, to: week.start)
    }

    // MARK: - Periods

    /// "end of month", "start of next year": the first or last day of a month,
    /// a year or a week.
    static func scanPeriod(_ tokens: [String], _ index: Int, _ context: Context)
        -> (date: Date, next: Int)? {
        let isEnd = endWords.contains(tokens[index])
        var cursor = index + 1
        while cursor < tokens.count, tokens[cursor] == "of" || tokens[cursor] == "the" {
            cursor += 1
        }
        var forward = 0
        if cursor < tokens.count, let direction = leadingDirection(tokens[cursor]) {
            forward = direction
            cursor += 1
        }
        guard cursor < tokens.count, let unit = Unit.names[tokens[cursor]],
              let component = unit.component, !unit.isTime else { return nil }
        let calendar = context.workingCalendar
        var anchor = context.now
        if forward != 0 {
            guard let shifted = calendar.date(byAdding: component, value: forward, to: anchor)
            else { return nil }
            anchor = shifted
        }
        guard let interval = calendar.dateInterval(of: component, for: anchor) else { return nil }
        if isEnd {
            guard let last = calendar.date(byAdding: .second, value: -1, to: interval.end)
            else { return nil }
            return (calendar.startOfDay(for: last), cursor + 1)
        }
        return (calendar.startOfDay(for: interval.start), cursor + 1)
    }
}
