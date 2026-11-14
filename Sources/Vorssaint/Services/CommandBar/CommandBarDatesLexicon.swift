// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The words and places the date parser reads.
///
/// Kept apart from the parser itself because this is the part that grows: a new
/// city, a new spelling, a month named differently in one of the languages the
/// app speaks. None of it is visible text — people type in their own language
/// whatever the interface says — so every set is folded (no accents, lower
/// case) and carries all of them at once.
extension CommandBarDates {
    /// A unit somebody can count or shift by. Not a `Calendar.Component`: a
    /// weekday is not a field the calendar can add in one step.
    enum Unit: Equatable {
        case second
        case minute
        case hour
        case day
        case weekday
        case week
        case month
        case year

        var component: Calendar.Component? {
            switch self {
            case .second: return .second
            case .minute: return .minute
            case .hour: return .hour
            case .day: return .day
            case .week: return .weekOfYear
            case .month: return .month
            case .year: return .year
            case .weekday: return nil
            }
        }

        /// Units that live inside a day: a question about them is about a
        /// clock, so its answer carries a time.
        var isTime: Bool {
            switch self {
            case .second, .minute, .hour: return true
            default: return false
            }
        }

        var allowedUnits: NSCalendar.Unit {
            switch self {
            case .second: return .second
            case .minute: return .minute
            case .hour: return .hour
            case .day, .weekday: return .day
            case .week: return .weekOfYear
            case .month: return .month
            case .year: return .year
            }
        }

        /// Singular names, the ones a person types. Every language the app
        /// speaks contributes; "hours" is the same unit as "hour".
        static let names: [String: Unit] = {
            var map: [String: Unit] = [:]
            func add(_ names: [String], _ unit: Unit) {
                for name in names { map[CommandBarSearch.normalized(name)] = unit }
            }
            add(["second", "seconds", "sec", "secs", "segundo", "segundos", "sekunde",
                 "seconde", "secondo", "segundo", "секунда", "секунды", "секунд", "sekund",
                 "saniye", "秒", "초", "秒"], .second)
            add(["minute", "minutes", "min", "mins", "m", "minuto", "minutos", "minute",
                 "minuten", "minuti", "минута", "минуты", "минут", "dakika", "分", "분",
                 "分钟"], .minute)
            add(["hour", "hours", "hr", "hrs", "h", "hora", "horas", "stunde", "stunden",
                 "heure", "heures", "ora", "ore", "час", "часа", "часов", "saat", "時",
                 "时", "時間", "小时", "시"], .hour)
            add(["day", "days", "dia", "dias", "tag", "tage", "giorno", "giorni", "jour",
                 "jours", "den", "dnya", "dney", "дня", "дней", "день", "gun", "gunler",
                 "日", "일", "天"], .day)
            add(["weekday", "weekdays", "workday", "workdays", "business day",
                 "business days", "work day", "work days", "working day", "working days",
                 "будние", "будних", "рабочие", "рабочих"], .weekday)
            add(["week", "weeks", "semana", "semanas", "woche", "wochen", "settimana",
                 "settimane", "semaine", "semaines", "nedelya", "недели", "недель",
                 "неделя", "hafta", "週", "주", "周", "星期"], .week)
            add(["month", "months", "mes", "meses", "monat", "monate", "mese", "mesi",
                 "mois", "месяц", "месяца", "месяцев", "ay", "月", "월", "个月"], .month)
            add(["year", "years", "ano", "anos", "jahr", "jahre", "anno", "anni", "an",
                 "ans", "annee", "annees", "god", "года", "лет", "год", "yil", "年", "년"],
                .year)
            return map
        }()
    }

    // MARK: - Words that point at a moment

    /// "today" and its relatives, folded. A word nobody can mistake for a
    /// search: answering it is always what the person wanted.
    static let todayWords: Set<String> = [
        "today", "hoje", "heute", "hoy", "oggi", "aujourdhui", "aujourd'hui",
        "segodnya", "сегодня", "bugun", "今日", "오늘", "今天",
    ]
    static let tomorrowWords: Set<String> = ["tomorrow", "amanha", "morgen", "manana",
                                             "domani", "завтра", "yarin", "明日", "내일", "明天"]
    static let yesterdayWords: Set<String> = ["yesterday", "ontem", "gestern", "ayer",
                                              "ieri", "вчера", "dun", "昨日", "어제", "昨天"]
    /// Words that count forward, and the ones that count back.
    static let futureWords: Set<String> = [
        "in", "em", "daqui", "dentro", "nach", "fra", "dans", "через", "sonra", "後",
        "후", "后", "from", "after", "apres", "despues", "depois", "dopo", "posle", "после",
    ]
    static let pastWords: Set<String> = [
        "ago", "atras", "ha", "hace", "vor", "fa", "назад", "once", "前", "전", "before",
        "avant", "antes", "prima", "do", "до",
    ]
    static let untilWords: Set<String> = [
        "until", "till", "til", "ate", "hasta", "bis", "fino", "jusqu", "jusqua", "до",
        "kadar", "까지", "까지는", "to",
    ]
    /// "since" counts backwards from a moment that has already happened; it is
    /// not the same word as "until", and confusing the two turns a past date
    /// into a future one.
    static let sinceWords: Set<String> = ["since", "desde", "seit", "depuis", "с",
                                          "от", "beri", "から", "부터", "以来"]
    static let timeWords: Set<String> = [
        "time", "hora", "horas", "hour", "uhrzeit", "uhr", "ora", "heure", "время",
        "saat", "時刻", "時間", "시간", "时间", "现在",
    ]
    /// Words that ask for a difference rather than a place's clock.
    static let differenceWords: Set<String> = ["diff", "difference", "diferenca",
                                               "differenz", "differenza", "raznica",
                                               "разница", "fark", "差", "차이", "时差"]
    /// The preposition that introduces a place, in every language the bar
    /// accepts. Folded, so "à" arrives as "a" and "в" keeps its own letters.
    static let localizedPrepositions: Set<String> = ["in", "em", "en", "a", "в"]
    /// Words that start or end a period: "end of month", "start of next year".
    static let endWords: Set<String> = ["end", "fim", "ende", "final", "fin", "konec",
                                        "конец", "конца", "son", "末", "끝", "结束"]
    static let startWords: Set<String> = ["start", "beginning", "inicio", "comeco",
                                          "anfang", "inizio", "debut", "nachalo",
                                          "начало", "начала", "baslangic", "初め", "开始"]
    /// "next monday" is not "this monday"; the two words move a week apart.
    static let nextWords: Set<String> = ["next", "proximo", "proxima", "prochaine",
                                         "nachtse", "naechste", "prossimo", "prossima",
                                         "sleduyushchiy", "следующий", "следующая", "gelecek",
                                         "次", "다음", "下", "下个"]
    static let lastWords: Set<String> = ["last", "previous", "prev", "passado",
                                         "passada", "letzte", "letzten", "derniere",
                                         "scorso", "scorsa", "proshlyy", "прошлый",
                                         "прошлая", "gecen", "前の", "지난", "上个"]
    static let thisWords: Set<String> = ["this", "este", "esta", "dieser", "diese",
                                         "ce", "cette", "questo", "questa", "etot",
                                         "этот", "эта", "bu", "この", "이", "这个"]

    // MARK: - Months and weekdays

    /// The languages the interface can use. A month is read in any of them:
    /// the person who wrote "aug" may well be running the app in Japanese.
    private static let appLanguages = [
        "en-US", "pt-BR", "tr", "ru", "es", "sk", "de", "fr", "it", "ja", "ko", "uk",
        "zh-Hans", "zh-TW", "zh-HK",
    ]

    /// Month number for every name and abbreviation the app's languages write.
    /// Built from the formatters so a language's own symbols are never guessed.
    static let months: [String: Int] = {
        var table: [String: Int] = [:]
        for identifier in appLanguages {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: identifier)
            let names = (formatter.monthSymbols ?? [])
                + (formatter.shortMonthSymbols ?? [])
                + (formatter.standaloneMonthSymbols ?? [])
            for (offset, name) in names.enumerated() {
                let key = foldedWord(name)
                guard !key.isEmpty else { continue }
                table[key] = offset + 1
            }
        }
        // Typed far more often than it is printed.
        table["sept"] = 9
        return table
    }()

    /// Weekday number (1 is Sunday, the way Calendar counts them) for every
    /// name the app's languages write. A month of the same spelling wins,
    /// because "mar" is March far more often than it is a Tuesday.
    static let weekdays: [String: Int] = {
        var table: [String: Int] = [:]
        for identifier in appLanguages {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: identifier)
            let names = (formatter.weekdaySymbols ?? []) + (formatter.shortWeekdaySymbols ?? [])
            for (offset, name) in names.enumerated() {
                let key = foldedWord(name)
                guard !key.isEmpty else { continue }
                table[key] = offset + 1
            }
        }
        table["tues"] = 3
        table["thur"] = 5
        table["thurs"] = 5
        table["weds"] = 4
        for key in months.keys { table[key] = nil }
        return table
    }()

    /// One spelling, folded and stripped of the periods abbreviations carry:
    /// "Jan." and "jan" are the same month.
    static func foldedWord(_ value: String) -> String {
        var folded = CommandBarSearch.normalized(value)
        while folded.hasSuffix(".") { folded.removeLast() }
        return folded
    }

    // MARK: - Places

    /// Every time zone by the folded name of the city in its identifier, built
    /// once. "America/Sao_Paulo" answers to "sao paulo". The database macOS
    /// carries is the first source; everything it does not name lives in the
    /// tables below.
    static let zonesByCity: [String: TimeZone] = {
        var map: [String: TimeZone] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let zone = TimeZone(identifier: identifier) else { continue }
            guard let city = identifier.split(separator: "/").last else { continue }
            let name = CommandBarSearch.normalized(city.replacingOccurrences(of: "_", with: " "))
            // The first identifier wins: the list is sorted, and the plain
            // "Europe/London" comes before any legacy link to it.
            if map[name] == nil { map[name] = zone }
        }
        for (alias, identifier) in placeNames {
            guard let zone = TimeZone(identifier: identifier) else { continue }
            if map[alias] == nil { map[alias] = zone }
        }
        return map
    }()

    /// Resolves a place written as several words, longest first: "san
    /// francisco" before "francisco", "new york" before "york".
    static func zone(for words: [String]) -> TimeZone? {
        guard !words.isEmpty else { return nil }
        let folded = words.map(foldedWord)
        var candidate = folded.count
        while candidate > 0 {
            let name = folded.suffix(candidate).joined(separator: " ")
            if let zone = zonesByCity[name] { return zone }
            candidate -= 1
        }
        // An offset is a place too: "utc+5:30", "gmt-3".
        if folded.count == 1, let zone = offsetZone(folded[0]) { return zone }
        return nil
    }

    /// A bare UTC offset: "utc", "utc+5", "utc+5:30", "gmt-3".
    static func offsetZone(_ word: String) -> TimeZone? {
        var text = word
        guard text.hasPrefix("utc") || text.hasPrefix("gmt") else { return nil }
        text.removeFirst(3)
        if text.isEmpty { return TimeZone(secondsFromGMT: 0) }
        let sign: Int
        if text.hasPrefix("+") { sign = 1 } else if text.hasPrefix("-") { sign = -1 }
        else { return nil }
        text.removeFirst()
        let parts = text.split(separator: ":").map(String.init)
        guard parts.count <= 2, let hours = Int(parts[0]), hours <= 18 else { return nil }
        let minutes = parts.count == 2 ? Int(parts[1]) ?? -1 : 0
        guard (0..<60).contains(minutes) else { return nil }
        return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
    }

    /// The name a person would recognize for a zone: the city its identifier
    /// ends with, or the offset for a zone the database does not name.
    static func placeName(of zone: TimeZone) -> String {
        let identifier = zone.identifier
        if identifier.hasPrefix("GMT"), let seconds = zone.secondsFromGMT(for: Date(timeIntervalSince1970: 0)) as Int? {
            let sign = seconds < 0 ? "-" : "+"
            let total = abs(seconds) / 60
            let minutes = total % 60
            return "UTC" + sign + String(total / 60)
                + (minutes == 0 ? "" : String(format: ":%02d", minutes))
        }
        let city = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return city.replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - Places the database does not name

    /// Everyday names, abbreviations, airport codes and the cities macOS
    /// leaves out of its zone database: Salzburg and Basel are real places,
    /// and so are `nyc` and `lhr`. Values are full identifiers so nothing
    /// depends on which city a zone happens to be filed under.
    private static let placeNames: [String: String] = {
        var map: [String: String] = [:]
        func add(_ names: [String], _ identifier: String) {
            for name in names { map[CommandBarSearch.normalized(name)] = identifier }
        }

        // Abbreviations read as regions, not as fixed offsets: "pst" in July
        // is Pacific daylight time, and the person meant the place, not the
        // number the letters spell.
        add(["pst", "pdt", "pt", "pacific"], "America/Los_Angeles")
        add(["mst", "mdt", "mt", "mountain"], "America/Denver")
        add(["cst", "cdt", "ct", "central"], "America/Chicago")
        add(["est", "edt", "et", "eastern"], "America/New_York")
        add(["bst", "gmt", "uk time"], "Europe/London")
        add(["cet", "cest", "met", "mest", "central european"], "Europe/Paris")
        add(["eet", "eest"], "Europe/Athens")
        add(["wet", "west"], "Europe/Lisbon")
        add(["msk"], "Europe/Moscow")
        add(["jst"], "Asia/Tokyo")
        add(["kst"], "Asia/Seoul")
        add(["hkt"], "Asia/Hong_Kong")
        add(["sgt"], "Asia/Singapore")
        // "ist" is India's standard time here; Israel and Ireland write the
        // same letters, and a launcher cannot ask which one was meant.
        add(["ist"], "Asia/Kolkata")
        add(["aest", "aedt"], "Australia/Sydney")
        add(["acst", "acdt"], "Australia/Adelaide")
        add(["awst", "awt"], "Australia/Perth")
        add(["nzst", "nzdt"], "Pacific/Auckland")
        add(["brt", "brst"], "America/Sao_Paulo")
        add(["art"], "America/Argentina/Buenos_Aires")
        add(["clt", "clst"], "America/Santiago")
        add(["cot"], "America/Bogota")
        add(["pet"], "America/Lima")
        add(["utc", "z", "universal"], "UTC")

        // Cities typed short.
        add(["sf", "san fran", "frisco", "bay area"], "America/Los_Angeles")
        add(["nyc", "new york city", "big apple"], "America/New_York")
        add(["ldn"], "Europe/London")
        add(["la", "l.a."], "America/Los_Angeles")
        add(["dc", "washington dc"], "America/New_York")
        add(["spb", "petersburg", "saint petersburg", "st petersburg"], "Europe/Moscow")
        add(["rio", "rio de janeiro"], "America/Sao_Paulo")
        add(["saigon"], "Asia/Ho_Chi_Minh")

        // Airports: the three letters on a boarding pass.
        add(["lhr", "lgw", "stn", "ltn"], "Europe/London")
        add(["cdg", "orly"], "Europe/Paris")
        add(["ams"], "Europe/Amsterdam")
        add(["fra", "ber", "muc", "dus"], "Europe/Berlin")
        add(["mad", "bcn"], "Europe/Madrid")
        add(["fco", "mxp", "lin"], "Europe/Rome")
        add(["zrh"], "Europe/Zurich")
        add(["vie"], "Europe/Vienna")
        add(["cph"], "Europe/Copenhagen")
        add(["arn"], "Europe/Stockholm")
        add(["osl"], "Europe/Oslo")
        add(["hel"], "Europe/Helsinki")
        add(["dub"], "Europe/Dublin")
        add(["lis"], "Europe/Lisbon")
        add(["prg"], "Europe/Prague")
        add(["waw"], "Europe/Warsaw")
        add(["bud"], "Europe/Budapest")
        add(["ist airport", "saw"], "Europe/Istanbul")
        add(["svo", "dme", "led"], "Europe/Moscow")
        add(["kbp"], "Europe/Kyiv")
        add(["jfk", "ewr", "lga", "bos", "iad", "dca", "mia", "atl"], "America/New_York")
        add(["ord", "dfw", "hou"], "America/Chicago")
        add(["den"], "America/Denver")
        add(["lax", "sfo", "sea", "san", "las", "pdx"], "America/Los_Angeles")
        add(["phx"], "America/Phoenix")
        add(["yyz", "yul"], "America/Toronto")
        add(["yvr"], "America/Vancouver")
        add(["mex"], "America/Mexico_City")
        add(["gru", "cgh"], "America/Sao_Paulo")
        add(["eze"], "America/Argentina/Buenos_Aires")
        add(["bog"], "America/Bogota")
        add(["lim"], "America/Lima")
        add(["scl"], "America/Santiago")
        add(["nrt", "hnd", "kix", "itm"], "Asia/Tokyo")
        add(["icn", "gmp"], "Asia/Seoul")
        add(["pek", "pvg", "sha", "can"], "Asia/Shanghai")
        add(["hkg"], "Asia/Hong_Kong")
        add(["tpe"], "Asia/Taipei")
        add(["sin"], "Asia/Singapore")
        add(["bkk"], "Asia/Bangkok")
        add(["kul"], "Asia/Kuala_Lumpur")
        add(["cgk", "dps"], "Asia/Jakarta")
        add(["mnl"], "Asia/Manila")
        add(["del", "bom", "blr", "maa"], "Asia/Kolkata")
        add(["dxb", "auh"], "Asia/Dubai")
        add(["doh"], "Asia/Qatar")
        add(["tlv"], "Asia/Jerusalem")
        add(["syd"], "Australia/Sydney")
        add(["mel"], "Australia/Melbourne")
        add(["bne"], "Australia/Brisbane")
        add(["per"], "Australia/Perth")
        add(["akl", "chc"], "Pacific/Auckland")
        add(["jnb", "cpt"], "Africa/Johannesburg")
        add(["cai"], "Africa/Cairo")
        add(["nbo"], "Africa/Nairobi")
        add(["los"], "Africa/Lagos")

        // Cities macOS leaves out. Each one answers with the zone it really
        // sits in, which is not always the country's capital.
        add(["salzburg", "innsbruck", "graz", "linz", "klagenfurt"], "Europe/Vienna")
        add(["basel", "bern", "lausanne", "lucerne", "luzern", "winterthur"], "Europe/Zurich")
        add(["bonn", "dresden", "leipzig", "stuttgart", "nuremberg", "nuernberg",
             "dortmund", "essen", "bremen", "hanover", "hannover", "kiel", "aachen",
             "heidelberg", "mainz", "wiesbaden", "freiburg", "regensburg"], "Europe/Berlin")
        add(["lyon", "marseille", "toulouse", "nice", "nantes", "bordeaux", "lille",
             "strasbourg", "montpellier", "rennes", "grenoble"], "Europe/Paris")
        add(["milan", "milano", "turin", "torino", "naples", "napoli", "florence",
             "firenze", "bologna", "venice", "venezia", "verona", "palermo", "genoa",
             "genova"], "Europe/Rome")
        add(["barcelona", "valencia", "seville", "sevilla", "bilbao", "malaga", "zaragoza",
             "granada", "palma", "alicante"], "Europe/Madrid")
        add(["porto", "coimbra", "faro"], "Europe/Lisbon")
        add(["rotterdam", "the hague", "den haag", "utrecht", "eindhoven", "groningen"],
            "Europe/Amsterdam")
        add(["antwerp", "antwerpen", "ghent", "gent", "bruges", "brugge", "liege",
             "leuven"], "Europe/Brussels")
        add(["manchester", "birmingham", "liverpool", "leeds", "bristol", "edinburgh",
             "glasgow", "cardiff", "belfast", "oxford", "cambridge", "brighton",
             "newcastle", "sheffield"], "Europe/London")
        add(["cork", "galway"], "Europe/Dublin")
        add(["gothenburg", "goteborg", "malmo", "uppsala", "linkoping"], "Europe/Stockholm")
        add(["bergen", "trondheim", "stavanger"], "Europe/Oslo")
        add(["aarhus", "arhus", "odense", "aalborg"], "Europe/Copenhagen")
        add(["tampere", "espoo", "turku"], "Europe/Helsinki")
        add(["krakow", "cracow", "wroclaw", "gdansk", "poznan", "lodz", "katowice"],
            "Europe/Warsaw")
        add(["brno", "ostrava"], "Europe/Prague")
        add(["debrecen", "szeged"], "Europe/Budapest")
        add(["thessaloniki", "patras"], "Europe/Athens")
        add(["ankara", "izmir", "antalya", "bursa"], "Europe/Istanbul")
        add(["kazan", "sochi", "samara", "ufa", "murmansk"], "Europe/Moscow")
        add(["novosibirsk", "siberia", "omsk"], "Asia/Novosibirsk")
        add(["yekaterinburg", "chelyabinsk"], "Asia/Yekaterinburg")
        add(["vladivostok", "khabarovsk"], "Asia/Vladivostok")
        add(["kaliningrad"], "Europe/Kaliningrad")
        add(["kyiv", "kiev", "lviv", "odesa", "odessa", "kharkiv", "dnipro"],
            "Europe/Kyiv")
        add(["boston", "philadelphia", "washington", "miami", "atlanta", "detroit",
             "cleveland", "pittsburgh", "baltimore", "charlotte", "orlando", "tampa"],
            "America/New_York")
        add(["minneapolis", "dallas", "houston", "austin", "san antonio", "nashville",
             "memphis", "new orleans", "st louis", "saint louis", "kansas city"],
            "America/Chicago")
        add(["salt lake city", "albuquerque", "boulder"], "America/Denver")
        add(["las vegas", "vegas", "san diego", "san jose", "sacramento", "portland",
             "seattle", "oakland", "long beach"], "America/Los_Angeles")
        add(["honolulu", "maui"], "Pacific/Honolulu")
        add(["toronto", "montreal", "ottawa", "quebec", "quebec city"], "America/Toronto")
        add(["calgary", "edmonton"], "America/Edmonton")
        add(["winnipeg"], "America/Winnipeg")
        add(["halifax"], "America/Halifax")
        add(["vancouver", "victoria bc"], "America/Vancouver")
        add(["guadalajara", "monterrey", "cancun", "tijuana", "puebla"], "America/Mexico_City")
        add(["brasilia", "belo horizonte", "curitiba", "porto alegre"], "America/Sao_Paulo")
        add(["salvador", "recife", "fortaleza", "manaus"], "America/Bahia")
        add(["cordoba", "rosario", "mendoza"], "America/Argentina/Cordoba")
        add(["valparaiso"], "America/Santiago")
        add(["medellin", "cali", "cartagena"], "America/Bogota")
        add(["cusco", "machu picchu"], "America/Lima")
        add(["havana"], "America/Havana")
        add(["san juan"], "America/Puerto_Rico")
        add(["kingston"], "America/Jamaica")
        add(["santo domingo"], "America/Santo_Domingo")
        add(["panama city"], "America/Panama")
        add(["reykjavik"], "Atlantic/Reykjavik")
        add(["osaka", "kyoto", "yokohama", "sapporo", "nagoya", "fukuoka", "kobe",
             "okinawa"], "Asia/Tokyo")
        add(["busan", "incheon", "daegu"], "Asia/Seoul")
        add(["guangzhou", "chengdu", "xian", "shenzhen", "chongqing"], "Asia/Shanghai")
        add(["mumbai", "bombay", "delhi", "new delhi", "bangalore", "bengaluru",
             "chennai", "hyderabad", "kolkata", "pune", "ahmedabad"], "Asia/Kolkata")
        add(["jakarta", "bali", "denpasar", "surabaya"], "Asia/Jakarta")
        add(["bangkok", "phuket", "chiang mai"], "Asia/Bangkok")
        add(["manila", "cebu"], "Asia/Manila")
        add(["kuala lumpur"], "Asia/Kuala_Lumpur")
        add(["hanoi", "ho chi minh", "ho chi minh city"], "Asia/Ho_Chi_Minh")
        add(["melbourne"], "Australia/Melbourne")
        add(["brisbane", "gold coast"], "Australia/Brisbane")
        add(["canberra"], "Australia/Sydney")
        add(["hobart"], "Australia/Hobart")
        add(["darwin"], "Australia/Darwin")
        add(["adelaide"], "Australia/Adelaide")
        add(["perth", "fremantle"], "Australia/Perth")
        add(["christchurch", "wellington", "queenstown"], "Pacific/Auckland")
        add(["abu dhabi", "sharjah"], "Asia/Dubai")
        add(["riyadh", "jeddah", "mecca"], "Asia/Riyadh")
        add(["doha"], "Asia/Qatar")
        add(["jerusalem", "tel aviv", "haifa"], "Asia/Jerusalem")
        add(["beirut"], "Asia/Beirut")
        add(["amman"], "Asia/Amman")
        add(["baghdad"], "Asia/Baghdad")
        add(["baku"], "Asia/Baku")
        add(["tbilisi"], "Asia/Tbilisi")
        add(["yerevan"], "Asia/Yerevan")
        add(["almaty", "astana"], "Asia/Almaty")
        add(["tashkent"], "Asia/Tashkent")
        add(["cairo", "alexandria", "luxor"], "Africa/Cairo")
        add(["casablanca", "marrakesh", "marrakech", "tangier", "rabat", "fes"],
            "Africa/Casablanca")
        add(["tunis"], "Africa/Tunis")
        add(["algiers"], "Africa/Algiers")
        add(["lagos", "abuja"], "Africa/Lagos")
        add(["accra"], "Africa/Accra")
        add(["addis ababa"], "Africa/Addis_Ababa")
        add(["johannesburg", "cape town", "durban", "pretoria"], "Africa/Johannesburg")
        add(["zagreb", "split", "dubrovnik"], "Europe/Zagreb")
        add(["belgrade", "novi sad"], "Europe/Belgrade")
        add(["sofia", "plovdiv"], "Europe/Sofia")
        add(["bucharest", "cluj", "cluj napoca"], "Europe/Bucharest")
        add(["bratislava", "kosice"], "Europe/Bratislava")
        add(["ljubljana", "maribor"], "Europe/Ljubljana")
        add(["vilnius", "kaunas"], "Europe/Vilnius")
        add(["riga"], "Europe/Riga")
        add(["tallinn", "tartu"], "Europe/Tallinn")
        add(["minsk"], "Europe/Minsk")
        add(["valletta"], "Europe/Malta")
        add(["nicosia", "limassol"], "Asia/Nicosia")

        // The same cities under the names the languages the app speaks give
        // them. Folded, so the accents never matter: "toquio" and "tóquio"
        // are one word here.
        add(["londres", "лондон"], "Europe/London")
        add(["lisboa", "lisbonne", "лиссабон"], "Europe/Lisbon")
        add(["roma", "рим"], "Europe/Rome")
        add(["moscou", "moscovo", "москва"], "Europe/Moscow")
        add(["nova york", "nova iorque", "ню-йорк"], "America/New_York")
        add(["cidade do mexico", "ciudad de mexico", "мехико"], "America/Mexico_City")
        add(["pequim", "pequin", "пекин"], "Asia/Shanghai")
        add(["toquio", "tokio", "токио"], "Asia/Tokyo")
        add(["genebra", "genf", "женева"], "Europe/Zurich")
        add(["viena", "венна"], "Europe/Vienna")
        add(["copenhague", "copenhaga", "копенгаген"], "Europe/Copenhagen")
        add(["praga", "прага"], "Europe/Prague")
        add(["atenas", "афины"], "Europe/Athens")
        add(["varsovia", "варшава"], "Europe/Warsaw")
        add(["bruxelas", "брюссель"], "Europe/Brussels")
        add(["zurique", "цюрих"], "Europe/Zurich")
        add(["munique", "munchen", "мюнхен"], "Europe/Berlin")
        add(["colonia", "кельн", "кёльн"], "Europe/Berlin")
        add(["estocolmo", "стокгольм"], "Europe/Stockholm")
        add(["hamburgo", "гамбург"], "Europe/Berlin")
        add(["berlim", "берлин"], "Europe/Berlin")
        add(["madri", "мадрид"], "Europe/Madrid")
        add(["париж"], "Europe/Paris")
        add(["киев", "київ"], "Europe/Kyiv")
        return map
    }()
}
