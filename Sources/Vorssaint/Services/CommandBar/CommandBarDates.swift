// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The questions about time that people put into a search field: what day is
/// it three weeks from now, how many days until a date, what time it is
/// somewhere else. Answered by the calendar this Mac already carries, never by
/// the network: the bar promised it does not go to the internet, and that
/// promise is worth more than a currency rate.
///
/// Deliberately narrow, like the calculator: every answer needs a full pattern
/// (a number, a unit and a direction, or a time word and a place, or a date
/// somebody would recognize as one). Anything short of that is left to the
/// search, because a launcher that guesses at dates turns "3 dias" into an
/// answer nobody asked for.
///
/// The parser is split over three files: this one holds the answer itself and
/// the gate in front of it, `CommandBarDatesLexicon` the words and places, and
/// `CommandBarDatesParsing` the reading of a moment. Nothing below reads a
/// clock: the current time, the calendar and the locale arrive as parameters,
/// so the same sentence always gives the same answer.
enum CommandBarDates {
    struct Result: Equatable {
        /// The answer itself, written the way this Mac writes dates.
        let formatted: String
        /// One line under it: the weekday, the place, whatever gives it sense.
        let detail: String
    }

    /// A moment the parser understood, with the zone it was written in and
    /// whether it carries a clock. "aug 25" is a date, "aug 25 9am" is not,
    /// and the difference decides whether an answer is a day or a time.
    struct Moment {
        var date: Date
        var hasTime: Bool
        var zone: TimeZone
    }

    /// Everything an answer is allowed to depend on.
    struct Context {
        let now: Date
        let calendar: Calendar
        let locale: Locale

        var zone: TimeZone { calendar.timeZone }

        /// The same calendar, read in another city's time. A date written as
        /// "oct 28 1pm et" is built in New York, not where this Mac sits.
        func calendar(in zone: TimeZone) -> Calendar {
            var copy = calendar
            copy.timeZone = zone
            return copy
        }

        /// The calendar with the interface's language, which is what decides
        /// where a week starts and whether a week number is ISO or not.
        var workingCalendar: Calendar {
            var copy = calendar
            copy.locale = locale
            return copy
        }

        func moment(at date: Date, hasTime: Bool, zone: TimeZone? = nil) -> Moment {
            Moment(date: date, hasTime: hasTime, zone: zone ?? self.zone)
        }
    }

    static func evaluate(_ input: String,
                         now: Date = Date(),
                         calendar: Calendar = .current,
                         locale: Locale = .current) -> Result? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // The bar answers on every keystroke, so the parser never sees a
        // paragraph; a date question is far shorter than this.
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return nil }
        // A pasted timestamp stays a search. People paste one looking for the
        // file or the note it came from, and a card in front of it costs them
        // the search they were doing.
        guard !isISOStamp(trimmed) else { return nil }
        let tokens = tokenize(trimmed)
        guard !tokens.isEmpty else { return nil }
        let context = Context(now: now, calendar: calendar, locale: locale)
        return answer(tokens, context)
    }

    /// The order is the safety: the stricter question wins, and the loosest
    /// reading — a bare date — only runs when nothing else wanted the query.
    static func answer(_ tokens: [String], _ context: Context) -> Result? {
        if let result = zoneAnswer(tokens, context) { return result }
        if let result = factAnswer(tokens, context) { return result }
        if let result = spanAnswer(tokens, context) { return result }
        if let result = shiftAnswer(tokens, context) { return result }
        if let result = countdownAnswer(tokens, context) { return result }
        if let result = momentAnswer(tokens, context) { return result }
        return nil
    }

    /// "2026-07-28" with or without a clock behind it.
    private static func isISOStamp(_ input: String) -> Bool {
        let head = input.prefix(10)
        guard head.count == 10 else { return false }
        let parts = head.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts[0].allSatisfy(\.isNumber), parts[1].allSatisfy(\.isNumber),
              parts[2].allSatisfy(\.isNumber) else { return false }
        return true
    }

    /// The query as words, with the signs and commas that carry meaning kept
    /// as words of their own. Everything else stays glued: "9:30" is a time
    /// and "19.2.27" is a date.
    static func tokenize(_ input: String) -> [String] {
        var text = CommandBarSearch.normalized(input)
        // "5 p.m." is how people typed before phones; every reader below
        // knows "pm" and nothing else.
        text = text.replacingOccurrences(of: "a.m.", with: "am")
        text = text.replacingOccurrences(of: "p.m.", with: "pm")
        var tokens: [String] = []
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            tokens.append(buffer)
            buffer = ""
        }
        for character in text {
            switch character {
            case " ":
                flush()
            case "+", "-", ",", "&", "\u{2013}", "\u{2014}", "\u{2212}":
                // A sign glued to "utc" is an offset, not a sum: "utc+5:30"
                // is one token, or the arithmetic would eat it.
                if character == "+" || character == "-", buffer.isEmpty,
                   let last = tokens.last, last == "utc" || last == "gmt" {
                    tokens.removeLast()
                    buffer = last + String(character)
                    continue
                }
                flush()
                switch character {
                case "\u{2013}", "\u{2014}", "\u{2212}": tokens.append("-")
                default: tokens.append(String(character))
                }
            default:
                buffer.append(character)
            }
        }
        flush()
        return tokens
    }
}
