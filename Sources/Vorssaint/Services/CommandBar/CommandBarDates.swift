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
    // language is, so each set carries the languages the app speaks, already
    // folded (no accents, lower case).

    private static let todayWords: Set<String> = [
        "today", "hoje", "heute", "hoy", "oggi", "aujourdhui", "aujourd'hui",
        "segodnya", "сегодня", "bugun", "今日", "오늘", "今天",
    ]
    private static let futureWords: Set<String> = [
        "in", "em", "daqui", "dentro", "nach", "tra", "fra", "dans", "через",
        "sonra", "後", "후", "后", "from",
    ]
    private static let pastWords: Set<String> = [
        "ago", "atras", "ha", "hace", "vor", "fa", "назад", "once", "前", "전",
    ]
    private static let untilWords: Set<String> = [
        "until", "till", "ate", "hasta", "bis", "fino", "jusqu", "до", "kadar",
        "까지", "까지는",
    ]
    private static let timeWords: Set<String> = [
        "time", "hora", "horas", "hour", "uhrzeit", "uhr", "ora", "heure",
        "время", "saat", "時刻", "時間", "시간", "时间", "现在",
    ]

    private static let units: [String: Calendar.Component] = {
        var map: [String: Calendar.Component] = [:]
        func add(_ names: [String], _ component: Calendar.Component) {
            for name in names { map[name] = component }
        }
        add(["day", "days", "dia", "dias", "tag", "tage", "giorno", "giorni",
             "jour", "jours", "den", "dnya", "dney", "дня", "дней", "день",
             "gun", "gunler", "日", "일", "天"], .day)
        add(["week", "weeks", "semana", "semanas", "woche", "wochen", "settimana",
             "settimane", "semaine", "semaines", "nedelya", "недели", "недель",
             "неделя", "hafta", "週", "주", "周", "星期"], .weekOfYear)
        add(["month", "months", "mes", "meses", "monat", "monate", "mese", "mesi",
             "mois", "месяц", "месяца", "месяцев", "ay", "月", "월", "个月"], .month)
        add(["year", "years", "ano", "anos", "jahr", "jahre", "anno", "anni",
             "an", "ans", "annee", "annees", "god", "года", "лет", "год", "yil",
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
        let tokens = CommandBarSearch.normalized(trimmed).split(separator: " ").map(String.init)
        guard tokens.count >= 2 else { return nil }

        if let result = relativeDate(tokens, now: now, calendar: calendar, locale: locale) {
            return result
        }
        if let result = daysUntil(tokens, now: now, calendar: calendar, locale: locale) {
            return result
        }
        return timeSomewhereElse(tokens, now: now, locale: locale)
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
        for index in tokens.indices.dropLast() {
            guard let value = Int(tokens[index]), abs(value) <= 10_000,
                  let unit = units[tokens[index + 1]] else { continue }
            amount = value
            component = unit
            break
        }
        guard let amount, let component else { return nil }

        let hasToday = tokens.contains(where: todayWords.contains)
        let hasPast = tokens.contains(where: pastWords.contains)
        let hasFuture = tokens.contains(where: futureWords.contains)
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
        // in: this year, or the next one if the day has already gone by.
        let parts = written.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let order = dayComesFirst(locale: locale)
        let day = order ? parts[0] : parts[1]
        let month = order ? parts[1] : parts[0]
        guard (1...31).contains(day), (1...12).contains(month) else { return nil }
        let year = calendar.component(.year, from: now)
        var components = DateComponents(year: year, month: month, day: day)
        guard let candidate = calendar.date(from: components) else { return nil }
        if candidate < calendar.startOfDay(for: now) {
            components.year = year + 1
            return calendar.date(from: components)
        }
        return candidate
    }

    /// Whether this Mac writes the day before the month.
    private static func dayComesFirst(locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) ?? "M/d/y"
        guard let day = format.firstIndex(of: "d"), let month = format.firstIndex(of: "M")
        else { return false }
        return day < month
    }
}
