// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum SnippetTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Text snippets engine (issue #201)

        expect(TextSnippetSupport.sanitizedTrigger("  ;e mail\n") == ";email", "triggers lose whitespace")
        expect(TextSnippetSupport.bufferAppending(String(repeating: "a", count: 64), typed: "b").count
                == TextSnippetSupport.bufferLimit,
               "the buffer stays capped")
        expect(TextSnippetSupport.bufferAppending("abc", typed: "d") == "abcd", "the buffer appends typing")

        let email = TextSnippet(name: "Email", trigger: ";email", replacement: "me@x.com",
                                expansion: .afterDelimiter, enabled: true)
        let email2 = TextSnippet(name: "Email 2", trigger: ";email2", replacement: "us@x.com",
                                 expansion: .afterDelimiter, enabled: true)
        let dateSnippet = TextSnippet(name: "Now", trigger: ";;dt", replacement: "{{datetime}}",
                                      expansion: .immediate, enabled: true)
        let disabledSnippet = TextSnippet(name: "Off", trigger: ";off", replacement: "x",
                                          expansion: .afterDelimiter, enabled: false)

        expect(TextSnippetSupport.match(buffer: "hello ;email", expansion: .afterDelimiter,
                                        snippets: [email, email2, disabledSnippet]) == email,
               "a completed trigger matches at the buffer's end")
        expect(TextSnippetSupport.match(buffer: "x ;email2", expansion: .afterDelimiter,
                                        snippets: [email, email2]) == email2,
               "the longest trigger wins")
        expect(TextSnippetSupport.match(buffer: ";emai", expansion: .afterDelimiter,
                                        snippets: [email]) == nil,
               "a half-typed trigger stays quiet")
        expect(TextSnippetSupport.match(buffer: "abc ;off", expansion: .afterDelimiter,
                                        snippets: [disabledSnippet]) == nil,
               "disabled snippets never fire")
        expect(TextSnippetSupport.match(buffer: "a;;dt", expansion: .afterDelimiter,
                                        snippets: [dateSnippet]) == nil,
               "modes do not cross: immediate snippets ignore the delimiter path")
        expect(TextSnippetSupport.match(buffer: "a;;dt", expansion: .immediate,
                                        snippets: [dateSnippet]) == dateSnippet,
               "immediate snippets fire the moment the trigger completes")

        let fixedDate = Date(timeIntervalSince1970: 1_752_000_000)
        let expandedText = TextSnippetSupport.expand("Report on {{date}} at {{time}}.",
                                                     date: fixedDate, clipboard: nil,
                                                     locale: Locale(identifier: "en_US"))
        expect(expandedText.contains("2025") && !expandedText.contains("{{date}}")
                && !expandedText.contains("{{time}}"),
               "date and time variables expand")
        expect(TextSnippetSupport.expand("clip: {{clipboard}}", date: fixedDate, clipboard: "X")
                == "clip: X",
               "the clipboard variable expands to the copied text")
        expect(TextSnippetSupport.expand("clip: {{clipboard}}", date: fixedDate, clipboard: nil)
                == "clip: ",
               "a missing clipboard expands to nothing")
        expect(TextSnippetSupport.expand("keep {{unknown}}", date: fixedDate, clipboard: nil)
                == "keep {{unknown}}",
               "unknown variables stay visible")
        expect(TextSnippetSupport.expand("plain", date: fixedDate, clipboard: nil) == "plain",
               "text without variables passes through untouched")

        // Only a replacement that names the clipboard pays for reading it: the
        // pasteboard can hang on content nobody renders any more, and that read
        // sits on the keystroke path (issue #887).
        expect(TextSnippetSupport.needsClipboard("clip: {{clipboard}}"),
               "a replacement naming the clipboard needs it read")
        expect(!TextSnippetSupport.needsClipboard("Report on {{date}} at {{time}}."),
               "a replacement with only date variables never reads the clipboard")
        expect(!TextSnippetSupport.needsClipboard("plain"),
               "a replacement without variables never reads the clipboard")
        expect(!TextSnippetSupport.needsClipboard("keep {{unknown}}"),
               "an unknown variable is not the clipboard one")
        expect(TextSnippetSupport.requiresPaste("first\nsecond")
               && TextSnippetSupport.requiresPaste("first\rsecond")
               && !TextSnippetSupport.requiresPaste("one line"),
               "multi-line snippets use paste while single-line snippets keep typed injection")
        expect(TextSnippetSupport.pastePayload(text: "first\nsecond", trailingText: "\r")
                == "first\nsecond\n"
               && TextSnippetSupport.pastePayload(text: "first\nsecond", trailingText: " ")
                == "first\nsecond ",
               "multi-line snippets keep their delimiter in the same ordered paste")

        // Custom date patterns after a colon (issue #348)
        let enUS = Locale(identifier: "en_US")
        expect(TextSnippetSupport.expand("{{date:yyyy-MM-dd}}", date: fixedDate, clipboard: nil,
                                         locale: enUS).hasPrefix("2025-07-0"),
               "a pattern after the colon formats the date")
        expect(TextSnippetSupport.expand("{{time:HH:mm}}", date: fixedDate, clipboard: nil,
                                         locale: enUS)
                .range(of: "^[0-9]{2}:[0-9]{2}$", options: .regularExpression) != nil,
               "colons inside the pattern belong to the pattern")
        expect(TextSnippetSupport.expand("{{datetime:yyyy}}", date: fixedDate, clipboard: nil,
                                         locale: enUS) == "2025",
               "every date variable takes a pattern")
        expect(TextSnippetSupport.expand("{{date:MMMM}}", date: fixedDate, clipboard: nil,
                                         locale: Locale(identifier: "pt_BR")).lowercased() == "julho",
               "month and weekday names follow the locale")
        expect(TextSnippetSupport.expand("on {{date}} ({{date:yyyy}})", date: fixedDate,
                                         clipboard: nil, locale: enUS).contains("(2025)"),
               "plain and formatted variables coexist")
        expect(TextSnippetSupport.expand("{{date:}}", date: fixedDate, clipboard: nil) == "{{date:}}",
               "an empty pattern stays visible like any typo")
        expect(TextSnippetSupport.expand("{{foo:yyyy}}", date: fixedDate, clipboard: nil)
                == "{{foo:yyyy}}",
               "unknown tags with a colon stay visible")
        expect(TextSnippetSupport.expand("{{date:yyyy", date: fixedDate, clipboard: nil)
                == "{{date:yyyy",
               "an unclosed tag passes through untouched")
        expect(TextSnippetSupport.expand("clip: {{clipboard}}", date: fixedDate,
                                         clipboard: "{{date:yyyy}}") == "clip: {{date:yyyy}}",
               "pasted clipboard text is never re-expanded")

        // Timezone-qualified date variables
        var tzTestCalendar = Calendar(identifier: .gregorian)
        tzTestCalendar.timeZone = TimeZone(identifier: "UTC")!
        let zonedDate = tzTestCalendar.date(from: DateComponents(year: 2025, month: 7, day: 1,
                                                                 hour: 12, minute: 30, second: 15))!
        expect(TextSnippetSupport.expand("{{datetime-tz(UTC):yyyy-MM-dd'T'HH:mm:ss}}",
                                         date: zonedDate, clipboard: nil, locale: enUS)
                == "2025-07-01T12:30:15",
               "a UTC-tagged datetime token formats in UTC regardless of the device's zone")
        expect(TextSnippetSupport.expand("{{date-tz(UTC):yyyy-MM-dd}}",
                                         date: zonedDate, clipboard: nil, locale: enUS) == "2025-07-01",
               "a UTC-tagged date token formats in UTC")
        expect(TextSnippetSupport.expand("{{time-tz(UTC):HH:mm:ss}}",
                                         date: zonedDate, clipboard: nil, locale: enUS) == "12:30:15",
               "a UTC-tagged time token formats in UTC")
        expect(TextSnippetSupport.expand("{{datetime-tz(Asia/Tokyo):yyyy-MM-dd HH:mm}}",
                                         date: zonedDate, clipboard: nil, locale: enUS)
                == "2025-07-01 21:30",
               "a token tagged with a specific zone shifts the clock by that zone's offset")
        // Asserted against a fixed non-UTC zone rather than the device's:
        // CI runners are UTC, where a leak and no leak look identical.
        expect(TextSnippetSupport.expand("{{time-tz(Asia/Tokyo):HH:mm}} then {{time-tz(UTC):HH:mm}}",
                                         date: zonedDate, clipboard: nil, locale: enUS)
                == "21:30 then 12:30",
               "a time zone on one token does not leak into a later token with its own")
        // The likelier leak: one shared DateFormatter has to be reset back
        // to the device zone for a plain token following a zoned one.
        // Compared against the plain token's own output so it holds on
        // CI's UTC runners as well as a machine in any other zone.
        expect(TextSnippetSupport.expand("{{time-tz(Asia/Tokyo):HH:mm}}|{{time:HH:mm}}",
                                         date: zonedDate, clipboard: nil, locale: enUS)
                == "21:30|" + TextSnippetSupport.expand("{{time:HH:mm}}", date: zonedDate,
                                                        clipboard: nil, locale: enUS),
               "a zoned token does not leak into a later plain one")
        expect(TextSnippetSupport.expand("{{datetime-tz(Not/ARealZone):yyyy-MM-dd HH:mm}}",
                                         date: zonedDate, clipboard: nil, locale: enUS)
                == "{{datetime-tz(Not/ARealZone):yyyy-MM-dd HH:mm}}",
               "an unrecognized time zone stays a literal tag instead of quietly using the device zone")
        expect(TextSnippetSupport.expand("{{datetime-tz(America/New York):yyyy-MM-dd HH:mm}}",
                                         date: zonedDate, clipboard: nil, locale: enUS)
                == "{{datetime-tz(America/New York):yyyy-MM-dd HH:mm}}",
               "a space where the identifier needs an underscore is visibly wrong, not silently local")

        // Date variable builder logic
        expect(TextSnippetSupport.resolvedDatePattern(kind: .date, style: .iso8601,
                                                       customPattern: "", locale: enUS) == "yyyy-MM-dd",
               "ISO 8601 date style resolves to the fixed ISO date pattern")
        expect(TextSnippetSupport.resolvedDatePattern(kind: .time, style: .iso8601,
                                                       customPattern: "", locale: enUS) == "HH:mm:ssXXX",
               "ISO 8601 time style resolves to the fixed ISO time pattern with an offset token")
        expect(TextSnippetSupport.resolvedDatePattern(kind: .datetime, style: .iso8601,
                                                       customPattern: "", locale: enUS)
                == "yyyy-MM-dd'T'HH:mm:ssXXX",
               "ISO 8601 datetime style resolves to the fixed ISO datetime pattern")
        expect(TextSnippetSupport.resolvedDatePattern(kind: .date, style: .custom,
                                                       customPattern: "dd/MM/yyyy", locale: enUS)
                == "dd/MM/yyyy",
               "custom style passes the raw pattern through untouched")
        expect(!TextSnippetSupport.resolvedDatePattern(kind: .date, style: .medium,
                                                        customPattern: "", locale: enUS).isEmpty,
               "a system style resolves to some non-empty pattern (exact text is OS/locale dependent)")

        expect(TextSnippetSupport.dateVariableText(kind: .date, style: .iso8601, customPattern: "",
                                                    timeZoneIdentifier: nil, locale: enUS)
                == "{{date:yyyy-MM-dd}}",
               "building a token with no timezone omits the -tz(...) suffix")
        expect(TextSnippetSupport.dateVariableText(kind: .datetime, style: .iso8601, customPattern: "",
                                                    timeZoneIdentifier: "UTC", locale: enUS)
                == "{{datetime-tz(UTC):yyyy-MM-dd'T'HH:mm:ssXXX}}",
               "building a token with a timezone adds the -tz(...) suffix")
        expect(TextSnippetSupport.dateVariableText(kind: .time, style: .custom, customPattern: "HH:mm",
                                                    timeZoneIdentifier: "Asia/Tokyo", locale: enUS)
                == "{{time-tz(Asia/Tokyo):HH:mm}}",
               "a custom pattern with a timezone builds the same tagged token shape")

        expect(TextSnippetSupport.dateVariablePreview(kind: .datetime, style: .iso8601, customPattern: "",
                                                       timeZoneIdentifier: "UTC", date: zonedDate,
                                                       locale: enUS) == "2025-07-01T12:30:15Z",
               "the preview matches what expansion would produce for the same settings")
        expect(TextSnippetSupport.dateVariablePreview(kind: .date, style: .custom, customPattern: "",
                                                       timeZoneIdentifier: nil, date: zonedDate,
                                                       locale: enUS).isEmpty,
               "an empty custom pattern previews as empty rather than crashing on an empty date format")

        // Date variable token detection
        let tokenSample = "Hi {{date:MMM d}} and {{datetime-tz(UTC):yyyy}} end"
        let insideDate = tokenSample.index(tokenSample.startIndex, offsetBy: 6)
        let detectedDate = TextSnippetSupport.dateToken(in: tokenSample, at: insideDate)
        expect(detectedDate?.kind == .date && detectedDate?.pattern == "MMM d"
                && detectedDate?.timeZoneIdentifier == nil,
               "the cursor inside a plain date token detects its kind and pattern")

        let insideZoned = tokenSample.range(of: "UTC")!.lowerBound
        let detectedZoned = TextSnippetSupport.dateToken(in: tokenSample, at: insideZoned)
        expect(detectedZoned?.kind == .datetime && detectedZoned?.pattern == "yyyy"
                && detectedZoned?.timeZoneIdentifier == "UTC",
               "the cursor inside a timezone-qualified token detects its kind, pattern and zone")

        expect(TextSnippetSupport.dateToken(in: tokenSample, at: tokenSample.startIndex) == nil,
               "a cursor outside any tag detects nothing")

        // The detected range is what the editor later splices over, and it
        // reaches that splice as offsets so it cannot be read against a
        // string it was not measured from.
        expect(detectedDate.map {
            String(tokenSample[TextSnippetSupport.selectionRange(in: tokenSample, offsets: $0.offsets)])
        } == "{{date:MMM d}}",
               "a detected token's offsets span exactly the token, braces included")
        expect(detectedZoned.map {
            String(tokenSample[TextSnippetSupport.selectionRange(in: tokenSample, offsets: $0.offsets)])
        } == "{{datetime-tz(UTC):yyyy}}",
               "a timezone-qualified token's offsets span the whole tag")

        // The editor keeps the selection as offsets recorded when the
        // selection last moved, so an edit that shortened the text since
        // leaves them past the end. They must clamp, never trap.
        let selectionText = "abcdef"
        expect(TextSnippetSupport.selectionRange(in: selectionText, offsets: 2..<4)
                == selectionText.index(selectionText.startIndex, offsetBy: 2)
                    ..< selectionText.index(selectionText.startIndex, offsetBy: 4),
               "an in-range selection maps to exactly those characters")
        expect(TextSnippetSupport.selectionRange(in: selectionText, offsets: nil)
                == selectionText.endIndex..<selectionText.endIndex,
               "no tracked selection puts the caret at the end")
        expect(TextSnippetSupport.selectionRange(in: "ab", offsets: 5..<9)
                == "ab".endIndex..<"ab".endIndex,
               "offsets left over from longer text clamp to the end instead of trapping")
        expect(TextSnippetSupport.selectionRange(in: "abcd", offsets: 2..<99)
                == "abcd".index("abcd".startIndex, offsetBy: 2)..<"abcd".endIndex,
               "a selection running past the end clamps only its upper bound")
        expect(TextSnippetSupport.selectionRange(in: "", offsets: 3..<7)
                == "".startIndex..<"".startIndex,
               "empty text clamps every offset to the start")
        expect(TextSnippetSupport.selectionRange(in: "e\u{301}fg", offsets: 1..<2)
                == "e\u{301}fg".index("e\u{301}fg".startIndex, offsetBy: 1)
                    ..< "e\u{301}fg".index("e\u{301}fg".startIndex, offsetBy: 2),
               "offsets count characters, so a combining mark stays with its base")

        let unknownTagText = "see {{clipboard}} here"
        let insideUnknown = unknownTagText.index(unknownTagText.startIndex, offsetBy: 6)
        expect(TextSnippetSupport.dateToken(in: unknownTagText, at: insideUnknown) == nil,
               "a cursor inside a non-date tag like clipboard detects nothing")

        let unclosedText = "start {{date:yyyy no close"
        let insideUnclosed = unclosedText.index(unclosedText.startIndex, offsetBy: 10)
        expect(TextSnippetSupport.dateToken(in: unclosedText, at: insideUnclosed) == nil,
               "a cursor inside an unclosed tag detects nothing")

        expect(TextSnippetSupport.dateToken(in: "", at: "".startIndex) == nil,
               "empty text detects nothing")

        let afterFirstTag = tokenSample.range(of: "{{date:MMM d}}")!.upperBound
        expect(TextSnippetSupport.dateToken(in: tokenSample, at: afterFirstTag) == nil,
               "a cursor immediately after a token's closing braces is not inside that token")
        let beforeFirstTag = tokenSample.range(of: "{{date:MMM d}}")!.lowerBound
        expect(TextSnippetSupport.dateToken(in: tokenSample, at: beforeFirstTag) == nil,
               "a cursor immediately before a token's opening braces is not inside that token")

        // Date variable builder support (timezone search and style matching)
        expect(TextSnippetSupport.matchingDateStyle(pattern: "yyyy-MM-dd", kind: .date, locale: enUS) == .iso8601,
               "the ISO 8601 date pattern is recognized as that style")
        expect(TextSnippetSupport.matchingDateStyle(pattern: "not a real pattern", kind: .date, locale: enUS) == .custom,
               "an unrecognized pattern falls back to Custom")

        expect(TextSnippetSupport.matchingTimeZoneIdentifiers(for: "").isEmpty,
               "an empty query matches nothing")
        // Asserted as containment, not equality: the set of identifiers
        // comes from the OS timezone database, so a future release adding
        // another "New York" zone must not fail this.
        expect(TextSnippetSupport.matchingTimeZoneIdentifiers(for: "new york").contains("America/New_York"),
               "a city name with a space matches the underscored identifier")
        // A broad query matches well over a hundred zones. The obvious
        // answer has to be reachable, and near the top: an alphabetical
        // list capped for the picker used to drop it entirely.
        let americaMatches = TextSnippetSupport.matchingTimeZoneIdentifiers(for: "america")
        expect(americaMatches.contains("America/New_York"),
               "a broad region query still lists the major city zones")
        // "york" and the full identifier both narrow to a single match, so
        // neither can observe the ordering. "st" matches dozens, most of
        // which merely contain the letters, so only ranking puts a city
        // beginning with them at the head.
        expect(TextSnippetSupport.matchingTimeZoneIdentifiers(for: "st").first?
                .split(separator: "/").last?.lowercased().hasPrefix("st") == true,
               "a city starting with the query outranks zones that merely contain it")
        expect(TextSnippetSupport.matchingTimeZoneIdentifiers(for: "america/new_york").first
                == "America/New_York",
               "an exactly typed identifier resolves to itself")
        expect(TextSnippetSupport.matchingTimeZoneIdentifiers(for: "xyz-nonsense").isEmpty,
               "a query matching nothing returns an empty list")

        expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "America/New_York") == "America/New_York",
               "a full identifier resolves to itself")
        expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "america/new york") == "America/New_York",
               "the full identifier resolves case- and separator-insensitively")
        expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "new york", matches: ["America/New_York"])
                == "America/New_York",
               "a city name that narrows the suggestion list to exactly one result resolves to it")
        expect(TextSnippetSupport.resolvedTimeZoneIdentifier(
                for: "new", matches: ["America/New_York", "Europe/Newtown"]) == nil,
               "a query still matching several identifiers stays unresolved")
        expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "pst") == "America/Los_Angeles",
               "a common abbreviation resolves to its canonical identifier")
        expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "utc") == "UTC",
               "UTC resolves even though it is not itself in TimeZone.knownTimeZoneIdentifiers")
        expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "budapest")?.hasSuffix("Budapest") == true,
               "a query with no exact match but exactly one substring match resolves to it")
        expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "america") == nil,
               "a query matching many identifiers with no exact hit stays unresolved")
        expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "xyz-nonsense") == nil,
               "a query matching nothing is unresolved")

        // A built token round-trips back through detection unchanged: this is
        // exactly the path the Insert/Edit button depends on.
        for kind in TextSnippetSupport.DateVariableKind.allCases {
            for timeZoneIdentifier in [nil, "UTC", "Asia/Tokyo"] as [String?] {
                let built = TextSnippetSupport.dateVariableText(kind: kind, style: .iso8601, customPattern: "",
                                                                 timeZoneIdentifier: timeZoneIdentifier, locale: enUS)
                let midpoint = built.index(built.startIndex, offsetBy: built.count / 2)
                let detected = TextSnippetSupport.dateToken(in: built, at: midpoint)
                expect(detected?.kind == kind && detected?.timeZoneIdentifier == timeZoneIdentifier,
                       "a built \(kind.rawValue) token with timezone \(timeZoneIdentifier ?? "nil") round-trips through dateToken unchanged")
            }
        }

        // Per-snippet capitalization option (issue #304)
        let caseless = TextSnippet(name: "Caseless", trigger: ";email", replacement: "me@x.com",
                                   expansion: .afterDelimiter, enabled: true, ignoresCase: true)
        expect(TextSnippetSupport.match(buffer: "x ;EMAIL", expansion: .afterDelimiter,
                                        snippets: [caseless]) == caseless
                && TextSnippetSupport.match(buffer: "x ;EmAiL", expansion: .afterDelimiter,
                                            snippets: [caseless]) == caseless,
               "a snippet that ignores capitalization fires on any casing")
        expect(TextSnippetSupport.match(buffer: "x ;EMAIL", expansion: .afterDelimiter,
                                        snippets: [email]) == nil,
               "exact snippets still require the configured casing")
        expect(TextSnippetSupport.match(buffer: ";EMAI", expansion: .afterDelimiter,
                                        snippets: [caseless]) == nil,
               "a half-typed trigger stays quiet regardless of casing")
        expect(!TextSnippetSupport.completes(";e", trigger: ";email", ignoresCase: true),
               "a buffer shorter than the trigger never completes it")

        let storedSnippets = [email, dateSnippet, caseless]
        expect(TextSnippetSupport.decode(TextSnippetSupport.encode(storedSnippets)) == storedSnippets,
               "snippets round-trip through persistence")
        expect(TextSnippetSupport.decode(nil).isEmpty, "no stored data means no snippets")
        let legacySnippetJSON = """
        [{"id":"1B6E2F0A-1111-4222-8333-444455556666","name":"Old","trigger":";old",\
        "replacement":"x","expansion":"afterDelimiter","enabled":true}]
        """
        let legacySnippets = TextSnippetSupport.decode(legacySnippetJSON.data(using: .utf8))
        expect(legacySnippets.count == 1 && legacySnippets.first?.ignoresCase == false,
               "snippets saved before the capitalization option decode and keep matching exactly")
        expect(legacySnippets.first?.folder == "" && legacySnippets.first?.showsInLibrary == true,
               "snippets saved before the library have no folder and stay visible in it")

        // MARK: Snippet library (issue #340)

        let workMail = TextSnippet(name: "Work mail", trigger: ";wmail", replacement: "work@x.com",
                                   expansion: .afterDelimiter, enabled: true, folder: "Work")
        let workSig = TextSnippet(name: "Signature", trigger: ";sig", replacement: "Best, V",
                                  expansion: .afterDelimiter, enabled: true, folder: "Work")
        let homeNote = TextSnippet(name: "Address", trigger: ";addr", replacement: "Elm St 1",
                                   expansion: .afterDelimiter, enabled: true, folder: "Home")
        let loose = TextSnippet(name: "Loose", trigger: ";loose", replacement: "loose text",
                                expansion: .afterDelimiter, enabled: true)
        let hidden = TextSnippet(name: "Hidden", trigger: ";hide", replacement: "hidden",
                                 expansion: .afterDelimiter, enabled: true, showsInLibrary: false)
        let disabled = TextSnippet(name: "Off", trigger: ";off", replacement: "off",
                                   expansion: .afterDelimiter, enabled: false)
        let libraryPool = [loose, workMail, hidden, homeNote, disabled, workSig]

        let allSections = TextSnippetSupport.librarySections(libraryPool, query: "")
        expect(allSections.map(\.folder) == ["Home", "Work", ""],
               "library folders come alphabetically with loose snippets closing the list")
        expect(allSections.last?.snippets == [loose],
               "disabled and hidden snippets never reach the library")
        expect(allSections[1].snippets == [workMail, workSig],
               "snippets keep their stored order inside a folder")
        expect(TextSnippetSupport.libraryRows(allSections).map(\.name)
                == ["Address", "Work mail", "Signature", "Loose"],
               "the flat row list walks the sections in reading order")

        expect(TextSnippetSupport.librarySections(libraryPool, query: "WORK").flatMap(\.snippets).count == 2,
               "searching matches the folder name regardless of casing")
        expect(TextSnippetSupport.librarySections(libraryPool, query: ";addr").flatMap(\.snippets) == [homeNote],
               "searching matches the trigger")
        expect(TextSnippetSupport.librarySections(libraryPool, query: "loose text").flatMap(\.snippets) == [loose],
               "searching matches the snippet text")
        expect(TextSnippetSupport.librarySections(libraryPool, query: "signat").flatMap(\.snippets) == [workSig],
               "searching matches the name")
        expect(TextSnippetSupport.librarySections(libraryPool, query: "zzz").isEmpty,
               "a search with no matches yields no sections")
        expect(TextSnippetSupport.librarySections(libraryPool, query: "  ").map(\.folder) == ["Home", "Work", ""],
               "a whitespace-only search counts as empty")

        expect(TextSnippetSupport.folderSuggestions(libraryPool) == ["Home", "Work"],
               "folder suggestions are distinct and alphabetical")
        expect(TextSnippetSupport.sanitizedFolder("  Work \n") == "Work",
               "folder names lose surrounding whitespace")
        expect(TextSnippetSupport.sanitizedFolder("   ") == "",
               "a whitespace-only folder means no folder")

        expect(GlobalShortcutRole.snippetLibrary.storageKey == DefaultsKey.snippetLibraryShortcut
                && GlobalShortcutRole.snippetLibrary.defaultShortcut == .snippetLibraryDefault
                && GlobalShortcutRole.snippetLibrary.requiredEnableKeys == [DefaultsKey.snippetLibraryEnabled]
                && GlobalShortcutRole.snippetLibrary.feature == .textSnippets,
               "the library shortcut role is wired to its own keys and the snippets feature")
        let roleDefaults = GlobalShortcutRole.allCases.map(\.defaultShortcut)
        expect(Set(roleDefaults).count == roleDefaults.count,
               "no two shortcut roles ship the same default combination")
    }
}
