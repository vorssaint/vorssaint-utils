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
/// (a number, a unit and a direction, or a time word and a place). Anything
/// short of that is left to the search, because a launcher that guesses at
/// dates turns "3 dias" into an answer nobody asked for.
enum CommandBarDates {
    struct Result: Equatable {
        /// The answer itself, written the way this Mac writes dates.
        let formatted: String
        /// One line under it: the weekday, the place, whatever gives it sense.
        let detail: String
    }

    // MARK: - Parser vocabulary
    //
    // Not visible text: people type in their own words whatever the interface
    // language is, so each set carries the languages the app speaks. The words
    // are folded the same way as the question, so one the fold changes still
    // matches: the й in "дней" becomes и.

    private static let todayWords = folded([
        "today", "hoje", "heute", "hoy", "oggi", "aujourdhui", "aujourd'hui",
        "segodnya", "сегодня", "bugun", "今日", "오늘", "今天",
    ])
    private static let futureWords = folded([
        "in", "em", "en", "daqui", "dentro", "nach", "tra", "fra", "dans", "через",
        "sonra", "後", "후", "뒤", "后", "from",
    ])
    private static let pastWords = folded([
        "ago", "atras", "ha", "hace", "vor", "fa", "назад", "once", "前", "전",
    ])
    private static let untilWords = folded([
        "until", "till", "ate", "hasta", "bis", "fino", "jusqu", "до", "kadar",
        "까지", "까지는",
    ])
    private static let timeWords = folded([
        "time", "hora", "horas", "hour", "uhrzeit", "uhr", "ora", "heure",
        "время", "saat", "時刻", "時間", "시간", "时间", "现在",
    ])

    private static func folded(_ words: [String]) -> Set<String> {
        Set(words.map(CommandBarSearch.normalized))
    }

    private static let units: [String: Calendar.Component] = {
        var map: [String: Calendar.Component] = [:]
        func add(_ names: [String], _ component: Calendar.Component) {
            for name in names { map[CommandBarSearch.normalized(name)] = component }
        }
        add(["day", "days", "dia", "dias", "tag", "tage", "tagen", "giorno", "giorni",
             "jour", "jours", "den", "dnya", "dney", "дня", "дней", "день",
             "gun", "gunler", "日", "일", "天"], .day)
        add(["week", "weeks", "semana", "semanas", "woche", "wochen", "settimana",
             "settimane", "semaine", "semaines", "nedelya", "недели", "недель",
             "неделя", "неделю", "hafta", "週", "週間", "주", "周", "星期",
             "个星期", "個星期"], .weekOfYear)
        // A number of months takes a counter, as in 3か月, 3个月 and 3개월:
        // 3月 and 3월 on their own name March.
        add(["month", "months", "mes", "meses", "monat", "monate", "monaten", "mese", "mesi",
             "mois", "месяц", "месяца", "месяцев", "ay", "か月", "ヶ月", "カ月", "ヵ月",
             "ケ月", "개월", "个月", "個月"], .month)
        add(["year", "years", "ano", "anos", "jahr", "jahre", "jahren", "anno", "anni",
             "an", "ans", "annee", "annees", "god", "года", "лет", "год", "yil", "yıl",
             "年", "년"], .year)
        return map
    }()

    /// Places whose everyday name differs from the one the time zone database
    /// uses. The database covers the rest on its own, so this stays a handful
    /// rather than a table to maintain.
    private static let placeAliases: [String: String] = [
        "londres": "London", "lisboa": "Lisbon", "roma": "Rome",
        "moscou": "Moscow", "moscovo": "Moscow", "москва": "Moscow",
        "nova york": "New_York", "nueva york": "New_York", "nova iorque": "New_York",
        "cidade do mexico": "Mexico_City", "ciudad de mexico": "Mexico_City",
        "pequim": "Beijing", "pequin": "Beijing", "toquio": "Tokyo", "tokio": "Tokyo",
        "genebra": "Geneva", "viena": "Vienna", "copenhague": "Copenhagen",
        "praga": "Prague", "atenas": "Athens", "varsovia": "Warsaw",
        "bruxelas": "Brussels", "zurique": "Zurich", "munique": "Munich",
        "colonia": "Cologne", "estocolmo": "Stockholm", "hamburgo": "Hamburg",
    ]

    /// Every time zone by the folded name of the city in its identifier, built
    /// once. "America/Sao_Paulo" answers to "sao paulo".
    private static let zonesByCity: [String: TimeZone] = {
        var map: [String: TimeZone] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let zone = TimeZone(identifier: identifier) else { continue }
            guard let city = identifier.split(separator: "/").last else { continue }
            let name = CommandBarSearch.normalized(
                city.replacingOccurrences(of: "_", with: " "))
            // The first identifier wins: the list is sorted, and the plain
            // "Europe/London" comes before any legacy link to it.
            if map[name] == nil { map[name] = zone }
        }
        for (alias, city) in placeAliases {
            let name = CommandBarSearch.normalized(city.replacingOccurrences(of: "_", with: " "))
            if let zone = map[name] { map[alias] = zone }
        }
        return map
    }()

    // MARK: - Answering

    static func evaluate(_ input: String,
                         now: Date = Date(),
                         calendar: Calendar = .current,
                         locale: Locale = .current) -> Result? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.count <= 80 else { return nil }
        let tokens = words(in: trimmed)
        guard tokens.count >= 2 else { return nil }

        if let result = relativeDate(tokens, now: now, calendar: calendar, locale: locale) {
            return result
        }
        if let result = daysUntil(tokens, now: now, calendar: calendar, locale: locale) {
            return result
        }
        return timeSomewhereElse(tokens, now: now, locale: locale)
    }

    /// The words of a question. Chinese and Japanese put no space between a
    /// number, its unit and the direction ("3日後", "3天后"), and Korean none
    /// between the number and its unit ("3일 후"), so a word in those scripts
    /// is split again, into the words above and the numbers between them.
    private static func words(in text: String) -> [String] {
        CommandBarSearch.normalized(text).split(separator: " ").flatMap { word -> [String] in
            word.unicodeScalars.contains(where: isCJK) ? segmented(Array(word)) : [String(word)]
        }
    }

    private static let cjkWords: Set<String> = todayWords.union(futureWords).union(pastWords)
        .union(untilWords).union(timeWords).union(units.keys)
        .filter { $0.unicodeScalars.contains(where: isCJK) }
    private static let longestCJKWord = cjkWords.map(\.count).max() ?? 1

    /// The longest known word wins, so "3週間後" reads as 3 / 週間 / 後 with
    /// nothing left over. A word is only split when it holds nothing but
    /// numbers and known words. Anything else is another word that happens to
    /// contain them, like "오후", the afternoon, or "以前", "before", and stays
    /// whole.
    private static func segmented(_ characters: [Character]) -> [String] {
        var words: [String] = []
        var index = 0
        while index < characters.count {
            if characters[index].isASCII, characters[index].isNumber {
                var end = index
                while end < characters.count, characters[end].isASCII, characters[end].isNumber { end += 1 }
                words.append(String(characters[index..<end]))
                index = end
                continue
            }
            let longest = min(longestCJKWord, characters.count - index)
            guard let length = stride(from: longest, through: 1, by: -1).first(where: {
                cjkWords.contains(String(characters[index..<index + $0]))
            }) else { return [String(characters)] }
            words.append(String(characters[index..<index + length]))
            index += length
        }
        return words
    }

    /// Han, kana and Hangul.
    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF, 0x3040...0x30FF, 0x3130...0x318F, 0x3400...0x4DBF,
             0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    /// "in 3 weeks", "daqui 3 semanas", "3 days ago", "hoje + 10 dias".
    private static func relativeDate(_ tokens: [String],
                                     now: Date,
                                     calendar: Calendar,
                                     locale: Locale) -> Result? {
        // The number and its unit have to sit together; everything else in the
        // phrase only decides which way to count.
        var amount: Int?
        var component: Calendar.Component?
        var numberIndex = 0
        for index in tokens.indices.dropLast() {
            guard let value = Int(tokens[index]), value.magnitude <= 10_000,
                  let unit = units[tokens[index + 1]] else { continue }
            amount = value
            component = unit
            numberIndex = index
            break
        }
        guard let amount, let component else { return nil }

        // In Chinese, Japanese and Korean the same words turn up in so many
        // other searches, "2박 3일 후기" or "12월 25일 후" among them, that only
        // the bare question answers: the number, its unit and a direction
        // ("3日後", "3일 후"), or today and a sign ("今天 + 3天"). A number of
        // 1000 or more before 年 or 년 is a year on the calendar: "1949年后" is
        // after 1949.
        if tokens[numberIndex + 1].unicodeScalars.contains(where: isCJK) {
            let bare = tokens.count == 3 && numberIndex == 0
                && (futureWords.contains(tokens[2]) || pastWords.contains(tokens[2]))
            let fromToday = tokens.count == 4 && numberIndex == 2
                && todayWords.contains(tokens[0]) && (tokens[1] == "+" || tokens[1] == "-")
            guard bare || fromToday, component != .year || abs(amount) < 1000 else { return nil }
        }

        let hasToday = tokens.contains(where: todayWords.contains)
        // Two directions only count right before the number. French writes its
        // "ago" there as three words, "il y a 3 jours", that anywhere else mean
        // "there is". Spanish writes "en 3 días", and "en" is also Turkish for
        // "most": "en az 3 gün" is "at least 3 days".
        let before = tokens[..<numberIndex]
        let hasPast = tokens.contains(where: pastWords.contains) || before.suffix(3) == ["il", "y", "a"]
        let hasFuture = tokens.contains { $0 != "en" && futureWords.contains($0) } || before.last == "en"
        let hasMinus = tokens.contains("-")
        // Without a direction "3 days" is not a question, and answering it
        // would push aside whatever the person was really looking for.
        guard hasToday || hasPast || hasFuture else { return nil }

        let backwards = hasPast || hasMinus
        guard let date = calendar.date(byAdding: component,
                                       value: backwards ? -amount : amount,
                                       to: now) else { return nil }
        return Result(formatted: longDate(date, locale: locale),
                      detail: weekday(date, locale: locale))
    }

    /// "days until 25/12", "dias ate 25/12": how far away a written date is.
    private static func daysUntil(_ tokens: [String],
                                  now: Date,
                                  calendar: Calendar,
                                  locale: Locale) -> Result? {
        guard let untilIndex = tokens.firstIndex(where: untilWords.contains),
              untilIndex + 1 < tokens.count else { return nil }
        let written = tokens[(untilIndex + 1)...].joined(separator: " ")
        guard let target = parseDate(written, now: now, calendar: calendar, locale: locale)
        else { return nil }
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTarget = calendar.startOfDay(for: target)
        guard let days = calendar.dateComponents([.day], from: startOfToday, to: startOfTarget).day
        else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.calendar = {
            var calendar = calendar
            calendar.locale = locale
            return calendar
        }()
        formatter.allowedUnits = [.day]
        formatter.unitsStyle = .full
        guard let counted = formatter.string(from: DateComponents(day: abs(days)))
        else { return nil }
        return Result(formatted: counted, detail: longDate(target, locale: locale))
    }

    /// "time in tokyo", "hora em londres", "tokyo time".
    private static func timeSomewhereElse(_ tokens: [String],
                                          now: Date,
                                          locale: Locale) -> Result? {
        guard tokens.contains(where: timeWords.contains) else { return nil }
        // Whatever is left after the time word and the little joining words is
        // the name of the place, which may well be two words long.
        let rest = tokens.filter { !timeWords.contains($0) && !futureWords.contains($0)
            && $0 != "a" && $0 != "at" && $0 != "de" }
        guard !rest.isEmpty else { return nil }
        let name = rest.joined(separator: " ")
        guard let zone = zonesByCity[name] ?? zonesByCity[rest[rest.count - 1]] else { return nil }

        let time = DateFormatter()
        time.locale = locale
        time.timeZone = zone
        time.dateStyle = .none
        time.timeStyle = .short
        let day = DateFormatter()
        day.locale = locale
        day.timeZone = zone
        day.dateStyle = .full
        day.timeStyle = .none
        let place = zone.identifier.split(separator: "/").last
            .map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
        return Result(formatted: time.string(from: now),
                      detail: place + " · " + day.string(from: now))
    }

    // MARK: - Writing and reading dates

    private static func longDate(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func weekday(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter.string(from: date)
    }

    /// A date the person wrote, read the way their Mac writes dates. A year
    /// left out means the next time that day comes around, which is what
    /// someone counting the days to a birthday means.
    private static func parseDate(_ written: String,
                                  now: Date,
                                  calendar: Calendar,
                                  locale: Locale) -> Date? {
        let short = DateFormatter()
        short.locale = locale
        short.calendar = calendar
        short.dateStyle = .short
        short.timeStyle = .none
        if let date = short.date(from: written) { return date }

        // Without a year the formatter refuses, so the missing year is filled
        // in: the first year, from this one, where that day exists and has not
        // gone by. A 29 February waits for the next leap year instead of
        // sliding into a neighbouring day.
        let parts = written.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let order = dayComesFirst(locale: locale)
        let day = order ? parts[0] : parts[1]
        let month = order ? parts[1] : parts[0]
        guard (1...31).contains(day), (1...12).contains(month) else { return nil }
        let year = calendar.component(.year, from: now)
        let startOfToday = calendar.startOfDay(for: now)
        for candidateYear in year...(year + 8) {
            let components = DateComponents(year: candidateYear, month: month, day: day)
            guard let candidate = calendar.date(from: components),
                  calendar.component(.month, from: candidate) == month,
                  calendar.component(.day, from: candidate) == day,
                  candidate >= startOfToday else { continue }
            return candidate
        }
        return nil
    }

    /// Whether this Mac writes the day before the month.
    private static func dayComesFirst(locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) ?? "M/d/y"
        guard let day = format.firstIndex(of: "d"), let month = format.firstIndex(of: "M")
        else { return false }
        return day < month
    }
}
