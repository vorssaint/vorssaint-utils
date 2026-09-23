// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LocalizationTests {
    static let languages: [(AppLanguage, Strings)] = [
        (.enUS, .enUS), (.ptBR, .ptBR), (.tr, .tr), (.ru, .ru), (.es, .es),
        (.de, .de), (.fr, .fr), (.it, .it), (.ja, .ja), (.ko, .ko), (.uk, .uk),
        (.zhHans, .zhHans), (.zhTW, .zhTW), (.zhHK, .zhHK),
    ]

    static func fields(_ value: Any) -> [String: String] {
        Dictionary(uniqueKeysWithValues: Mirror(reflecting: value).children.compactMap {
            guard let name = $0.label, let text = $0.value as? String else { return nil }
            return (name, text)
        })
    }

    static func check(_ value: Any, against english: Any, name: String, suite: TestSuite) {
        let values = fields(value)
        let base = fields(english)
        suite.expect(!values.isEmpty && Set(values.keys) == Set(base.keys),
                     "\(name): translated fields match the English schema")
        let empty = values.filter { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.keys.sorted()
        suite.expect(empty.isEmpty, "\(name): missing text in \(empty.joined(separator: ", "))")
        let dashes = values.filter { $0.value.contains("\u{2014}") }.keys.sorted()
        suite.expect(dashes.isEmpty, "\(name): em-dash in \(dashes.joined(separator: ", "))")
        for (field, original) in base {
            let expected = TestFormat.parse(original)
            guard field.lowercased().contains("format") || expected?.arguments.isEmpty == false else { continue }
            let actual = values[field].flatMap(TestFormat.parse)
            suite.expect(expected != nil && actual?.arguments == expected?.arguments,
                         "\(name).\(field): format arguments retain their positions and types")
        }
    }

    static func formattingChecks(_ suite: TestSuite) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let late = utc.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 23, minute: 5))!
        func clock(_ language: AppLanguage, _ system: String) -> String {
            var style = Date.FormatStyle.dateTime.hour().minute().locale(language.formattingLocale(system: Locale(identifier: system)))
            style.timeZone = utc.timeZone
            return late.formatted(style)
        }
        suite.expect(clock(.enUS, "en_BR") == "23:05" && clock(.enUS, "en_US@hours=h23") == "23:05",
                     "English follows a 24-hour region or clock setting instead of its own 12-hour default")
        suite.expect(clock(.ptBR, "en_US").hasPrefix("11:05"), "a 12-hour system clock is kept in any app language")
        let month = late.formatted(Date.FormatStyle.dateTime.month(.wide)
            .locale(AppLanguage.ptBR.formattingLocale(system: Locale(identifier: "en_US"))))
        suite.expect(month == "setembro", "month and weekday names stay in the app's language")
        suite.expect(AppLanguage.enUS.formattingLocale(system: Locale(identifier: "de_DE")).firstDayOfWeek == .monday,
                     "the first day of the week follows the region")
    }

    static func run(_ suite: TestSuite) {
        formattingChecks(suite)
        suite.expect(Set(languages.map { $0.0 }) == Set(AppLanguage.allCases)
                     && languages.count == AppLanguage.allCases.count,
                     "the base strings cover each app language exactly once")
        suite.expect(!factories.isEmpty, "feature localization factories were discovered")
        for (language, strings) in languages {
            check(strings, against: Strings.enUS, name: "strings/\(language.rawValue)", suite: suite)
            let additional: [(String, (AppLanguage) -> Any)] = [
                ("imageConverter", { MediaImageConverterStrings.localized($0) }),
                ("directionalLayout", { WindowDirectionalStrings.localized($0) }),
                ("downloadOrganizer", { WhatsAppOrganizerStrings.localized($0) }),
                ("shelfDelivery", { ShelfPromiseDeliveryStrings.localized($0) }),
            ]
            for (name, factory) in factories + additional {
                check(factory(language), against: factory(.enUS),
                      name: "\(name)/\(language.rawValue)", suite: suite)
            }
        }
    }
}

/// Compare argument identities, not sorted conversion letters: swapping %1$d
/// and %2$@ is unsafe even though the old sorted list looked unchanged.
struct TestFormat {
    let arguments: [Int: String]
    let conversions: [String]
    private static let token = try! NSRegularExpression(
        pattern: #"%(?:([1-9][0-9]*)\$)?[-+ #0']*[0-9]*(?:\.[0-9]+)?(hh|ll|[hljztLq])?([@diuoxXfFeEgGaAcCsSp])"#)

    static func parse(_ text: String) -> TestFormat? {
        let string = text as NSString
        var cursor = 0
        var nextArgument = 1
        var arguments: [Int: String] = [:]
        var conversions: [String] = []
        var usesPositions: Bool?
        while cursor < string.length {
            guard string.character(at: cursor) == 37 else { cursor += 1; continue }
            if cursor + 1 < string.length, string.character(at: cursor + 1) == 37 {
                cursor += 2
                continue
            }
            guard let match = token.firstMatch(in: text, options: .anchored,
                range: NSRange(location: cursor, length: string.length - cursor)) else { return nil }
            func capture(_ index: Int) -> String {
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : string.substring(with: range)
            }
            let position = Int(capture(1))
            if !capture(1).isEmpty && position == nil { return nil }
            if let usesPositions, usesPositions != (position != nil) { return nil }
            usesPositions = position != nil
            let index = position ?? nextArgument
            let conversion = capture(2) + capture(3)
            if let previous = arguments[index], previous != conversion { return nil }
            arguments[index] = conversion
            conversions.append(conversion)
            nextArgument += 1
            cursor = NSMaxRange(match.range)
        }
        return TestFormat(arguments: arguments, conversions: conversions)
    }
}
