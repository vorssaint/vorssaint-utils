// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Places and their clocks: the time somewhere else, a time converted, the
/// difference between two of them. Everything reads the time zone database
/// this Mac already carries; nothing goes to the network, because the bar
/// promised it never does.
extension CommandBarDates {
    static func zoneAnswer(_ tokens: [String], _ context: Context) -> Result? {
        if let result = differenceAnswer(tokens, context) { return result }
        return conversionAnswer(tokens, context)
    }

    // MARK: - The difference between two places

    /// "diff paris", "diff london & tokyo",
    /// "time difference between london and tokyo".
    static func differenceAnswer(_ tokens: [String], _ context: Context) -> Result? {
        var groups: [[String]]?
        if tokens.count >= 2, differenceWords.contains(tokens[0]) {
            groups = splitPlaces(tokens[1...])
        } else if let between = tokens.firstIndex(of: "between"),
                  tokens[..<between].contains(where: differenceWords.contains),
                  let and = tokens[(between + 1)...].firstIndex(of: "and") {
            groups = [Array(tokens[(between + 1)..<and]), Array(tokens[(and + 1)...])]
        }
        guard let groups, (1...3).contains(groups.count) else { return nil }
        let zones = groups.compactMap { zone(for: $0) }
        guard zones.count == groups.count else { return nil }

        // One place is asked about against where this Mac is; two are asked
        // about against each other, first to second.
        let reference = zones.count == 1 ? context.zone : zones[0]
        let target = zones[zones.count - 1]
        let seconds = target.secondsFromGMT(for: context.now) - reference.secondsFromGMT(for: context.now)
        guard let formatted = offsetText(seconds, context) else { return nil }
        let names = zones.map { placeName(of: $0) }
        return Result(formatted: formatted, detail: names.joined(separator: " · "))
    }

    /// "+2 hours", "-5 hours 30 minutes".
    static func offsetText(_ seconds: Int, _ context: Context) -> String? {
        var calendar = context.calendar
        calendar.locale = context.locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 2
        let magnitude = abs(seconds)
        var components = DateComponents()
        components.hour = magnitude / 3600
        components.minute = (magnitude % 3600) / 60
        guard let text = formatter.string(from: components) else { return nil }
        return (seconds < 0 ? "-" : "+") + text
    }

    // MARK: - A moment, somewhere else

    /// "5pm ldn in sf", "time in tokyo", "date in tokyo",
    /// "tomorrow 3pm pst", "5pm ldn in sf + 2h",
    /// "1pm et in london, tokyo, sydney", and the same questions in the
    /// languages the app speaks: "hora em londres", "heure à paris".
    static func conversionAnswer(_ tokens: [String], _ context: Context) -> Result? {
        // The preposition is read the same in every language the bar accepts;
        // the words around it are what carry the meaning.
        let words = tokens.map { localizedPrepositions.contains($0) ? "in" : $0 }


        // "time in tokyo when it's 5pm in london": the source moment is the
        // right half, the place asked about is the left one.
        if let when = words.firstIndex(of: "when"), when + 1 < words.count,
           let targetIn = words[..<when].lastIndex(of: "in") {
            let targetWords = Array(words[(targetIn + 1)..<when])
            let sourceWords = words[(when + 1)...].filter {
                !["it's", "its", "it", "is", "in", "at", "on"].contains($0)
            }
            guard zone(for: targetWords) != nil, !sourceWords.isEmpty else { return nil }
            var rewritten = Array(sourceWords)
            rewritten.append("in")
            rewritten.append(contentsOf: targetWords)
            return conversionAnswer(rewritten, context, targets: nil)
        }
        return conversionAnswer(words, context, targets: nil)
    }

    private static func conversionAnswer(_ words: [String], _ context: Context,
                                         targets known: [TimeZone]?) -> Result? {
        var words = words
        // A shift after the answer: "in sf + 2h" moves the converted time.
        var later: (amount: Int, unit: Unit?)?
        if let plus = words.lastIndex(where: { $0 == "+" || $0 == "-" }), plus > 0 {
            var cursor = plus + 1
            if let term = scanTerm(words, &cursor), cursor == words.count {
                later = (words[plus] == "-" ? -term.amount : term.amount, term.unit)
                words.removeSubrange(plus..<words.count)
            }
        }

        // The last "in" whose right side names places is the conversion.
        var splitIndex: Int?
        var targets: [TimeZone] = known ?? []
        if known == nil {
            for index in words.indices where words[index] == "in" {
                let groups = splitPlaces(words[(index + 1)...])
                guard !groups.isEmpty else { continue }
                let zones = groups.compactMap { zone(for: $0) }
                guard zones.count == groups.count else { continue }
                splitIndex = index
                targets = zones
            }
        }
        if let splitIndex {
            var prefix = Array(words[0..<splitIndex])
            let mode = takeMode(&prefix)
            var source = context.zone
            _ = takeSource(&prefix, &source)

            // "time in 4 hours in san francisco": the shift belongs to the
            // source moment and moves it before the conversion.
            var lead: (amount: Int, unit: Unit?)?
            if let inIndex = prefix.lastIndex(of: "in"), inIndex + 3 == prefix.count,
               let amount = Int(prefix[inIndex + 1]),
               let unit = Unit.names[prefix[inIndex + 2]] {
                lead = (amount, unit)
                prefix.removeSubrange(inIndex..<prefix.count)
            }

            let sourceContext = Context(now: context.now,
                                        calendar: context.calendar(in: source),
                                        locale: context.locale)
            // An empty moment is only allowed when the question named what it
            // wanted: "time in tokyo", never a bare "in tokyo".
            let base: Moment?
            if prefix.isEmpty {
                base = mode == nil ? nil : sourceContext.moment(at: context.now, hasTime: true)
            } else {
                base = moment(prefix[...], sourceContext)
            }
            guard let base,
                  let converted = convert(base, to: targets, mode: mode ?? .clock, later: later,
                                          lead: lead, context: context) else {
                return nil
            }
            return converted
        }

        // No "in": "tomorrow 3pm pst" names a place for the moment and asks
        // for it where this Mac is.
        return sourceOnly(words, context)
    }

    /// The words that say what the answer should be — "time" or "date" — and
    /// that are then removed from the moment's own words. Nil means the
    /// question did not say, so an empty moment is not allowed.
    private static func takeMode(_ words: inout [String]) -> Mode? {
        var mode: Mode?
        for word in words {
            if word == "date" { mode = .date }
            if timeWords.contains(word) { mode = mode ?? .clock }
        }
        words.removeAll {
            ["what", "which", "is", "it", "its", "it's", "local", "current", "clock",
             "date", "time"].contains($0) || timeWords.contains($0)
        }
        return mode
    }

    enum Mode { case clock, date }

    /// Strips a place written at the end of the prefix: the "ldn" in
    /// "5pm ldn in sf". Longest reading wins, so "new york" survives as one.
    private static func takeSource(_ words: inout [String], _ source: inout TimeZone) -> Bool {
        var count = min(3, words.count)
        var taken = false
        while count > 0 {
            let tail = Array(words.suffix(count))
            if let zone = exactZone(tail) {
                source = zone
                words.removeLast(count)
                taken = true
                break
            }
            count -= 1
        }
        // The preposition that introduced it: "5pm in london in sf".
        if words.last == "in" || words.last == "at" || words.last == "on" {
            words.removeLast()
        }
        return taken
    }

    /// A place with no target: the moment is written where that place is and
    /// read where this Mac is.
    private static func sourceOnly(_ words: [String], _ context: Context) -> Result? {
        var count = min(3, words.count - 1)
        while count > 0 {
            let tail = Array(words.suffix(count))
            let head = Array(words.prefix(words.count - count))
            if let source = exactZone(tail), !head.isEmpty {
                if let base = sourceMoment(head, in: source, context) {
                    return convert(base, to: [context.zone], mode: .clock, later: nil,
                                   lead: nil, context: context)
                }
            }
            count -= 1
        }
        return nil
    }

    /// A moment whose day words ("today", "tomorrow") are read where this Mac
    /// sits, but whose clock is read where the place is: "tomorrow 3pm pst" is
    /// tomorrow here at 3 in San Francisco, not the place's already-passed day.
    private static func sourceMoment(_ head: [String], in source: TimeZone,
                                     _ context: Context) -> Moment? {
        guard let own = moment(head[...], context) else { return nil }
        guard own.hasTime else { return own }
        let wall = context.calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                                   from: own.date)
        guard let date = context.calendar(in: source).date(from: wall) else { return nil }
        return Moment(date: date, hasTime: true, zone: source)
    }

    // MARK: - Writing a converted moment

    private static func convert(_ base: Moment, to targets: [TimeZone], mode: Mode,
                                later: (amount: Int, unit: Unit?)?,
                                lead: (amount: Int, unit: Unit?)?,
                                context: Context) -> Result? {
        guard let first = targets.first else { return nil }
        var date = base.date
        if let lead {
            let unit = lead.unit ?? (base.hasTime ? .hour : .day)
            guard let moved = adding(lead.amount, unit, to: date, context.calendar(in: base.zone))
            else { return nil }
            date = moved
        }
        if let later {
            let unit = later.unit ?? (base.hasTime ? .hour : .day)
            guard let moved = adding(later.amount, unit, to: date, context.calendar(in: first))
            else { return nil }
            date = moved
        }

        switch mode {
        case .date:
            let formatted = Text.date(date, in: first, context)
            return Result(formatted: formatted,
                          detail: placeName(of: first) + " · "
                              + Text.weekday(date, in: first, context))
        case .clock:
            let marker = Text.dayMarker(dayOffset(from: base.date, in: base.zone, to: date,
                                                  in: first, context), context)
            var formatted = Text.clock(date, in: first, context)
            if let marker { formatted += " " + marker }
            let detail: String
            if targets.count == 1 {
                detail = placeName(of: first) + " · " + Text.date(date, in: first, context)
            } else {
                // Several places on one card: the first is the answer, the
                // rest sit under it. Listing every clock keeps the card
                // honest without pretending to have one headline for three.
                detail = targets.map {
                    placeName(of: $0) + " " + Text.clock(date, in: $0, context)
                }.joined(separator: " · ")
            }
            return Result(formatted: formatted, detail: detail)
        }
    }

    /// How many days the answer sits from the day the question named: 1 is
    /// tomorrow, -1 yesterday, anything else needs no note. Compared as pure
    /// calendar days, not hours, so a midnight crossing in the target zone is
    /// "tomorrow" even when the two instants are only a few hours apart.
    static func dayOffset(from reference: Date, in referenceZone: TimeZone,
                          to date: Date, in zone: TimeZone, _ context: Context) -> Int {
        let here = context.calendar(in: referenceZone)
        let there = context.calendar(in: zone)
        let sourceDay = here.dateComponents([.year, .month, .day], from: reference)
        let targetDay = there.dateComponents([.year, .month, .day], from: date)
        var neutral = Calendar(identifier: .gregorian)
        neutral.timeZone = TimeZone(identifier: "UTC")!
        guard let source = neutral.date(from: sourceDay),
              let target = neutral.date(from: targetDay) else { return 0 }
        return neutral.dateComponents([.day], from: source, to: target).day ?? 0
    }

    /// Places written as a list: "london, tokyo, sydney" or "london & tokyo".
    static func splitPlaces(_ words: ArraySlice<String>) -> [[String]] {
        var groups: [[String]] = []
        var current: [String] = []
        for word in words {
            switch word {
            case ",", "&", "and", "+", "vs", "versus":
                if !current.isEmpty {
                    groups.append(current)
                    current = []
                }
            case "in", "at", "the":
                continue
            default:
                current.append(word)
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }
}
