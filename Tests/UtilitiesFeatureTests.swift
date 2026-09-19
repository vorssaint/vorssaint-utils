// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat

enum UtilitiesFeatureTests {
    static func run(_ suite: TestSuite) {
        // MARK: Port manager parser

        let lsofFixture = """
        p123
        cExample Server
        PTCP
        n127.0.0.1:3000
        n127.0.0.1:3000
        n[::1]:3000
        n*:3001
        p456
        cOther Server
        PTCP
        n*:3000
        """
        let parsedPorts = PortManagerSupport.parseLsof(lsofFixture)
        suite.expect(parsedPorts.map(\.port) == [3000, 3000, 3000, 3001],
               "port parser keeps every distinct listening endpoint and removes exact duplicates")
        suite.expect(parsedPorts.filter { $0.pid == 123 }.count == 3,
               "port parser keeps multiple ports and address families for one process")

        let invalidEndpointFixture = """
        p789
        cNo Port Process
        PTCP
        n*:4000
        n127.0.0.1
        """
        let parsedInvalid = PortManagerSupport.parseLsof(invalidEndpointFixture)
        suite.expect(parsedInvalid.count == 1 && parsedInvalid.first?.port == 4000,
               "port parser ignores address lines that lack a port instead of pairing with previous port")

        for lang in AppLanguage.allCases {
            let strings = FeatureStrings.portManager(lang)
            suite.expect(!strings.hubDescription.isEmpty,
                   "port manager has a non-empty hub description for \(lang)")
        }

        // MARK: Text snippets engine (issue #201)

        suite.expect(TextSnippetSupport.alertSoundNames(from: ["Tink.aiff", "Basso.aiff"])
                == ["Basso", "Tink"],
               "directory entries become sorted sound names without their extension")
        suite.expect(TextSnippetSupport.alertSoundNames(from: ["Glass.AIFF"]) == ["Glass"],
               "an uppercase extension is still recognized")
        suite.expect(!TextSnippetSupport.alertSoundNames(from: ["Readme.txt", "Sub.caf"]).isEmpty,
               "a listing with no aiff falls back rather than emptying the picker")
        suite.expect(TextSnippetSupport.alertSoundNames(from: ["Readme.txt"])
                == TextSnippetSupport.fallbackAlertSoundNames,
               "an unreadable or foreign sounds directory falls back to the known names")
        suite.expect(TextSnippetSupport.alertSoundNames(from: [])
                == TextSnippetSupport.fallbackAlertSoundNames,
               "an empty directory falls back to the known names")

        suite.expect(TextSnippetSupport.resolvedSoundName(stored: "Tink", available: ["Basso", "Tink"])
                == "Tink", "a stored sound the system still offers is kept")
        suite.expect(TextSnippetSupport.resolvedSoundName(stored: "Gone", available: ["Basso", "Tink"])
                == "Tink",
               "a stored sound this Mac no longer has falls back to the default instead of going silent")
        suite.expect(TextSnippetSupport.resolvedSoundName(stored: nil, available: ["Basso", "Tink"])
                == "Tink", "no stored sound uses the default")
        suite.expect(TextSnippetSupport.resolvedSoundName(stored: "Gone", available: ["Basso"])
                == "Basso",
               "with neither the stored sound nor the default present, the first offered one is used")
        suite.expect(TextSnippetSupport.resolvedSoundName(stored: "Gone", available: []) == nil,
               "nothing to play resolves to nothing rather than a name that cannot load")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.snippetSoundEnabled] as? Bool == false,
               "sound on expansion stays off until asked for")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.snippetSoundName] as? String
                == Defaults.defaultSnippetSoundName,
               "the registered default is the shared constant, not a second copy of the name")
        suite.expect(TextSnippetSupport.fallbackAlertSoundNames.contains(Defaults.defaultSnippetSoundName),
               "the default sound is one the fallback list offers")
        suite.expect(FileManager.default.fileExists(
                atPath: TextSnippetSupport.soundFileURL(for: Defaults.defaultSnippetSoundName).path),
               "the default sound is played from the file macOS ships for it")
        suite.expect(Set(TextSnippetSupport.fallbackAlertSoundNames).count
                == TextSnippetSupport.fallbackAlertSoundNames.count,
               "no duplicate names in the fallback list")

        suite.expect(AlertSoundStrings.displayName(for: "Tink", language: .enUS) == "Boop",
               "macOS has shown Tink as Boop in Sound settings since Big Sur")
        suite.expect(AlertSoundStrings.displayName(for: "Ping", language: .enUS) == "Sonar",
               "macOS has shown Ping as Sonar in Sound settings since Big Sur")
        suite.expect(AlertSoundStrings.displayName(for: "Tink", language: .fr) == "Boop",
               "a supported language other than English gets its own translated name")
        suite.expect(AlertSoundStrings.displayName(for: "Ping", language: .ru) == "Сонар",
               "a supported language other than English gets its own translated name")
        suite.expect(AlertSoundStrings.displayName(for: "Tink", language: .ja) == "Boop",
               "Apple's own table keeps the English display name for Japanese, Korean and Chinese")
        suite.expect(AlertSoundStrings.displayName(for: "Custom", language: .enUS) == "Custom",
               "a name outside the table is shown unchanged rather than dropped")
        suite.expect(TextSnippetSupport.fallbackAlertSoundNames.allSatisfy {
                AlertSoundStrings.displayName(for: $0, language: .enUS) != $0
            }, "every shipped alert sound has a display name distinct from its file name")

        suite.expect(AlertSoundStrings.sortedNames(TextSnippetSupport.fallbackAlertSoundNames,
                                                   language: .enUS)
                == ["Tink", "Blow", "Pop", "Glass", "Funk", "Hero", "Frog",
                    "Basso", "Bottle", "Purr", "Morse", "Ping", "Sosumi", "Submarine"],
               "the picker orders by what each name shows (Boop, Breeze, Bubble, ...), not by the file name")
        suite.expect(AlertSoundStrings.sortedNames(["Basso", "Tink"], language: .enUS).first
                == "Tink", "Boop sorts before Mezzo even though the file name Basso sorts before Tink")
        suite.expect(Set(AlertSoundStrings.sortedNames(TextSnippetSupport.fallbackAlertSoundNames,
                                                      language: .enUS))
                == Set(TextSnippetSupport.fallbackAlertSoundNames),
               "sorting only reorders the list, it never drops or adds a name")

        suite.expect(TextSnippetSupport.sanitizedTrigger("  ;e mail\n") == ";email", "triggers lose whitespace")
        suite.expect(TextSnippetSupport.bufferAppending(String(repeating: "a", count: 64), typed: "b").count
                == TextSnippetSupport.bufferLimit,
               "the buffer stays capped")
        suite.expect(TextSnippetSupport.bufferAppending("abc", typed: "d") == "abcd", "the buffer appends typing")

        let email = TextSnippet(name: "Email", trigger: ";email", replacement: "me@x.com",
                                expansion: .afterDelimiter, enabled: true)
        let email2 = TextSnippet(name: "Email 2", trigger: ";email2", replacement: "us@x.com",
                                 expansion: .afterDelimiter, enabled: true)
        let dateSnippet = TextSnippet(name: "Now", trigger: ";;dt", replacement: "{{datetime}}",
                                      expansion: .immediate, enabled: true)
        let disabledSnippet = TextSnippet(name: "Off", trigger: ";off", replacement: "x",
                                          expansion: .afterDelimiter, enabled: false)

        suite.expect(TextSnippetSupport.match(buffer: "hello ;email", expansion: .afterDelimiter,
                                        snippets: [email, email2, disabledSnippet]) == email,
               "a completed trigger matches at the buffer's end")
        suite.expect(TextSnippetSupport.match(buffer: "x ;email2", expansion: .afterDelimiter,
                                        snippets: [email, email2]) == email2,
               "the longest trigger wins")
        suite.expect(TextSnippetSupport.match(buffer: ";emai", expansion: .afterDelimiter,
                                        snippets: [email]) == nil,
               "a half-typed trigger stays quiet")
        suite.expect(TextSnippetSupport.match(buffer: "abc ;off", expansion: .afterDelimiter,
                                        snippets: [disabledSnippet]) == nil,
               "disabled snippets never fire")
        suite.expect(TextSnippetSupport.match(buffer: "a;;dt", expansion: .afterDelimiter,
                                        snippets: [dateSnippet]) == nil,
               "modes do not cross: immediate snippets ignore the delimiter path")
        suite.expect(TextSnippetSupport.match(buffer: "a;;dt", expansion: .immediate,
                                        snippets: [dateSnippet]) == dateSnippet,
               "immediate snippets fire the moment the trigger completes")

        let fixedDate = Date(timeIntervalSince1970: 1_752_000_000)
        let expandedText = TextSnippetSupport.expand("Report on {{date}} at {{time}}.",
                                                     date: fixedDate, clipboard: nil,
                                                     locale: Locale(identifier: "en_US"))
        suite.expect(expandedText.contains("2025") && !expandedText.contains("{{date}}")
                && !expandedText.contains("{{time}}"),
               "date and time variables expand")
        suite.expect(TextSnippetSupport.expand("clip: {{clipboard}}", date: fixedDate, clipboard: "X")
                == "clip: X",
               "the clipboard variable expands to the copied text")
        suite.expect(TextSnippetSupport.expand("clip: {{clipboard}}", date: fixedDate, clipboard: nil)
                == "clip: ",
               "a missing clipboard expands to nothing")
        suite.expect(TextSnippetSupport.expand("keep {{unknown}}", date: fixedDate, clipboard: nil)
                == "keep {{unknown}}",
               "unknown variables stay visible")
        suite.expect(TextSnippetSupport.expand("plain", date: fixedDate, clipboard: nil) == "plain",
               "text without variables passes through untouched")

        // Only a replacement that names the clipboard pays for reading it: the
        // pasteboard can hang on content nobody renders any more, and that read
        // sits on the keystroke path (issue #887).
        suite.expect(TextSnippetSupport.needsClipboard("clip: {{clipboard}}"),
               "a replacement naming the clipboard needs it read")
        suite.expect(!TextSnippetSupport.needsClipboard("Report on {{date}} at {{time}}."),
               "a replacement with only date variables never reads the clipboard")
        suite.expect(!TextSnippetSupport.needsClipboard("plain"),
               "a replacement without variables never reads the clipboard")
        suite.expect(!TextSnippetSupport.needsClipboard("keep {{unknown}}"),
               "an unknown variable is not the clipboard one")
        suite.expect(TextSnippetSupport.requiresPaste("first\nsecond")
               && TextSnippetSupport.requiresPaste("first\rsecond")
               && !TextSnippetSupport.requiresPaste("one line"),
               "multi-line snippets use paste while single-line snippets keep typed injection")
        suite.expect(TextSnippetSupport.pastePayload(text: "first\nsecond", trailingText: "\r")
                == "first\nsecond\n"
               && TextSnippetSupport.pastePayload(text: "first\nsecond", trailingText: " ")
                == "first\nsecond ",
               "multi-line snippets keep their delimiter in the same ordered paste")

        // Custom date patterns after a colon (issue #348)
        let enUS = Locale(identifier: "en_US")
        suite.expect(TextSnippetSupport.expand("{{date:yyyy-MM-dd}}", date: fixedDate, clipboard: nil,
                                         locale: enUS).hasPrefix("2025-07-0"),
               "a pattern after the colon formats the date")
        suite.expect(TextSnippetSupport.expand("{{time:HH:mm}}", date: fixedDate, clipboard: nil,
                                         locale: enUS)
                .range(of: "^[0-9]{2}:[0-9]{2}$", options: .regularExpression) != nil,
               "colons inside the pattern belong to the pattern")
        suite.expect(TextSnippetSupport.expand("{{datetime:yyyy}}", date: fixedDate, clipboard: nil,
                                         locale: enUS) == "2025",
               "every date variable takes a pattern")
        suite.expect(TextSnippetSupport.expand("{{date:MMMM}}", date: fixedDate, clipboard: nil,
                                         locale: Locale(identifier: "pt_BR")).lowercased() == "julho",
               "month and weekday names follow the locale")
        suite.expect(TextSnippetSupport.expand("on {{date}} ({{date:yyyy}})", date: fixedDate,
                                         clipboard: nil, locale: enUS).contains("(2025)"),
               "plain and formatted variables coexist")
        suite.expect(TextSnippetSupport.expand("{{date:}}", date: fixedDate, clipboard: nil) == "{{date:}}",
               "an empty pattern stays visible like any typo")
        suite.expect(TextSnippetSupport.expand("{{foo:yyyy}}", date: fixedDate, clipboard: nil)
                == "{{foo:yyyy}}",
               "unknown tags with a colon stay visible")
        suite.expect(TextSnippetSupport.expand("{{date:yyyy", date: fixedDate, clipboard: nil)
                == "{{date:yyyy",
               "an unclosed tag passes through untouched")
        suite.expect(TextSnippetSupport.expand("clip: {{clipboard}}", date: fixedDate,
                                         clipboard: "{{date:yyyy}}") == "clip: {{date:yyyy}}",
               "pasted clipboard text is never re-expanded")

        // Timezone-qualified date variables
        var tzTestCalendar = Calendar(identifier: .gregorian)
        tzTestCalendar.timeZone = TimeZone(identifier: "UTC")!
        let zonedDate = tzTestCalendar.date(from: DateComponents(year: 2025, month: 7, day: 1,
                                                                 hour: 12, minute: 30, second: 15))!
        suite.expect(TextSnippetSupport.expand("{{datetime-tz(UTC):yyyy-MM-dd'T'HH:mm:ss}}",
                                         date: zonedDate, clipboard: nil, locale: enUS)
                == "2025-07-01T12:30:15",
               "a UTC-tagged datetime token formats in UTC regardless of the device's zone")
        suite.expect(TextSnippetSupport.expand("{{date-tz(UTC):yyyy-MM-dd}}",
                                         date: zonedDate, clipboard: nil, locale: enUS) == "2025-07-01",
               "a UTC-tagged date token formats in UTC")
        suite.expect(TextSnippetSupport.expand("{{time-tz(UTC):HH:mm:ss}}",
                                         date: zonedDate, clipboard: nil, locale: enUS) == "12:30:15",
               "a UTC-tagged time token formats in UTC")
        suite.expect(TextSnippetSupport.expand("{{datetime-tz(Asia/Tokyo):yyyy-MM-dd HH:mm}}",
                                         date: zonedDate, clipboard: nil, locale: enUS)
                == "2025-07-01 21:30",
               "a token tagged with a specific zone shifts the clock by that zone's offset")
        // Asserted against a fixed non-UTC zone rather than the device's:
        // CI runners are UTC, where a leak and no leak look identical.
        suite.expect(TextSnippetSupport.expand("{{time-tz(Asia/Tokyo):HH:mm}} then {{time-tz(UTC):HH:mm}}",
                                         date: zonedDate, clipboard: nil, locale: enUS)
                == "21:30 then 12:30",
               "a time zone on one token does not leak into a later token with its own")
        // The likelier leak: one shared DateFormatter has to be reset back
        // to the device zone for a plain token following a zoned one.
        // Compared against the plain token's own output so it holds on
        // CI's UTC runners as well as a machine in any other zone.
        suite.expect(TextSnippetSupport.expand("{{time-tz(Asia/Tokyo):HH:mm}}|{{time:HH:mm}}",
                                         date: zonedDate, clipboard: nil, locale: enUS)
                == "21:30|" + TextSnippetSupport.expand("{{time:HH:mm}}", date: zonedDate,
                                                        clipboard: nil, locale: enUS),
               "a zoned token does not leak into a later plain one")
        suite.expect(TextSnippetSupport.expand("{{datetime-tz(Not/ARealZone):yyyy-MM-dd HH:mm}}",
                                         date: zonedDate, clipboard: nil, locale: enUS)
                == "{{datetime-tz(Not/ARealZone):yyyy-MM-dd HH:mm}}",
               "an unrecognized time zone stays a literal tag instead of quietly using the device zone")
        suite.expect(TextSnippetSupport.expand("{{datetime-tz(America/New York):yyyy-MM-dd HH:mm}}",
                                         date: zonedDate, clipboard: nil, locale: enUS)
                == "{{datetime-tz(America/New York):yyyy-MM-dd HH:mm}}",
               "a space where the identifier needs an underscore is visibly wrong, not silently local")

        // Date variable builder logic
        suite.expect(TextSnippetSupport.resolvedDatePattern(kind: .date, style: .iso8601,
                                                       customPattern: "", locale: enUS) == "yyyy-MM-dd",
               "ISO 8601 date style resolves to the fixed ISO date pattern")
        suite.expect(TextSnippetSupport.resolvedDatePattern(kind: .time, style: .iso8601,
                                                       customPattern: "", locale: enUS) == "HH:mm:ssXXX",
               "ISO 8601 time style resolves to the fixed ISO time pattern with an offset token")
        suite.expect(TextSnippetSupport.resolvedDatePattern(kind: .datetime, style: .iso8601,
                                                       customPattern: "", locale: enUS)
                == "yyyy-MM-dd'T'HH:mm:ssXXX",
               "ISO 8601 datetime style resolves to the fixed ISO datetime pattern")
        suite.expect(TextSnippetSupport.resolvedDatePattern(kind: .date, style: .custom,
                                                       customPattern: "dd/MM/yyyy", locale: enUS)
                == "dd/MM/yyyy",
               "custom style passes the raw pattern through untouched")
        suite.expect(!TextSnippetSupport.resolvedDatePattern(kind: .date, style: .medium,
                                                        customPattern: "", locale: enUS).isEmpty,
               "a system style resolves to some non-empty pattern (exact text is OS/locale dependent)")

        suite.expect(TextSnippetSupport.dateVariableText(kind: .date, style: .iso8601, customPattern: "",
                                                    timeZoneIdentifier: nil, locale: enUS)
                == "{{date:yyyy-MM-dd}}",
               "building a token with no timezone omits the -tz(...) suffix")
        suite.expect(TextSnippetSupport.dateVariableText(kind: .datetime, style: .iso8601, customPattern: "",
                                                    timeZoneIdentifier: "UTC", locale: enUS)
                == "{{datetime-tz(UTC):yyyy-MM-dd'T'HH:mm:ssXXX}}",
               "building a token with a timezone adds the -tz(...) suffix")
        suite.expect(TextSnippetSupport.dateVariableText(kind: .time, style: .custom, customPattern: "HH:mm",
                                                    timeZoneIdentifier: "Asia/Tokyo", locale: enUS)
                == "{{time-tz(Asia/Tokyo):HH:mm}}",
               "a custom pattern with a timezone builds the same tagged token shape")

        suite.expect(TextSnippetSupport.dateVariablePreview(kind: .datetime, style: .iso8601, customPattern: "",
                                                       timeZoneIdentifier: "UTC", date: zonedDate,
                                                       locale: enUS) == "2025-07-01T12:30:15Z",
               "the preview matches what expansion would produce for the same settings")
        suite.expect(TextSnippetSupport.dateVariablePreview(kind: .date, style: .custom, customPattern: "",
                                                       timeZoneIdentifier: nil, date: zonedDate,
                                                       locale: enUS).isEmpty,
               "an empty custom pattern previews as empty rather than crashing on an empty date format")

        // Date variable token detection
        let tokenSample = "Hi {{date:MMM d}} and {{datetime-tz(UTC):yyyy}} end"
        let insideDate = tokenSample.index(tokenSample.startIndex, offsetBy: 6)
        let detectedDate = TextSnippetSupport.dateToken(in: tokenSample, at: insideDate)
        suite.expect(detectedDate?.kind == .date && detectedDate?.pattern == "MMM d"
                && detectedDate?.timeZoneIdentifier == nil,
               "the cursor inside a plain date token detects its kind and pattern")

        let insideZoned = tokenSample.range(of: "UTC")!.lowerBound
        let detectedZoned = TextSnippetSupport.dateToken(in: tokenSample, at: insideZoned)
        suite.expect(detectedZoned?.kind == .datetime && detectedZoned?.pattern == "yyyy"
                && detectedZoned?.timeZoneIdentifier == "UTC",
               "the cursor inside a timezone-qualified token detects its kind, pattern and zone")

        suite.expect(TextSnippetSupport.dateToken(in: tokenSample, at: tokenSample.startIndex) == nil,
               "a cursor outside any tag detects nothing")

        // The detected range is what the editor later splices over, and it
        // reaches that splice as offsets so it cannot be read against a
        // string it was not measured from.
        suite.expect(detectedDate.map {
            String(tokenSample[TextSnippetSupport.selectionRange(in: tokenSample, offsets: $0.offsets)])
        } == "{{date:MMM d}}",
               "a detected token's offsets span exactly the token, braces included")
        suite.expect(detectedZoned.map {
            String(tokenSample[TextSnippetSupport.selectionRange(in: tokenSample, offsets: $0.offsets)])
        } == "{{datetime-tz(UTC):yyyy}}",
               "a timezone-qualified token's offsets span the whole tag")

        // The editor keeps the selection as offsets recorded when the
        // selection last moved, so an edit that shortened the text since
        // leaves them past the end. They must clamp, never trap.
        let selectionText = "abcdef"
        suite.expect(TextSnippetSupport.selectionRange(in: selectionText, offsets: 2..<4)
                == selectionText.index(selectionText.startIndex, offsetBy: 2)
                    ..< selectionText.index(selectionText.startIndex, offsetBy: 4),
               "an in-range selection maps to exactly those characters")
        suite.expect(TextSnippetSupport.selectionRange(in: selectionText, offsets: nil)
                == selectionText.endIndex..<selectionText.endIndex,
               "no tracked selection puts the caret at the end")
        suite.expect(TextSnippetSupport.selectionRange(in: "ab", offsets: 5..<9)
                == "ab".endIndex..<"ab".endIndex,
               "offsets left over from longer text clamp to the end instead of trapping")
        suite.expect(TextSnippetSupport.selectionRange(in: "abcd", offsets: 2..<99)
                == "abcd".index("abcd".startIndex, offsetBy: 2)..<"abcd".endIndex,
               "a selection running past the end clamps only its upper bound")
        suite.expect(TextSnippetSupport.selectionRange(in: "", offsets: 3..<7)
                == "".startIndex..<"".startIndex,
               "empty text clamps every offset to the start")
        suite.expect(TextSnippetSupport.selectionRange(in: "e\u{301}fg", offsets: 1..<2)
                == "e\u{301}fg".index("e\u{301}fg".startIndex, offsetBy: 1)
                    ..< "e\u{301}fg".index("e\u{301}fg".startIndex, offsetBy: 2),
               "offsets count characters, so a combining mark stays with its base")

        let unknownTagText = "see {{clipboard}} here"
        let insideUnknown = unknownTagText.index(unknownTagText.startIndex, offsetBy: 6)
        suite.expect(TextSnippetSupport.dateToken(in: unknownTagText, at: insideUnknown) == nil,
               "a cursor inside a non-date tag like clipboard detects nothing")

        let unclosedText = "start {{date:yyyy no close"
        let insideUnclosed = unclosedText.index(unclosedText.startIndex, offsetBy: 10)
        suite.expect(TextSnippetSupport.dateToken(in: unclosedText, at: insideUnclosed) == nil,
               "a cursor inside an unclosed tag detects nothing")

        suite.expect(TextSnippetSupport.dateToken(in: "", at: "".startIndex) == nil,
               "empty text detects nothing")

        let afterFirstTag = tokenSample.range(of: "{{date:MMM d}}")!.upperBound
        suite.expect(TextSnippetSupport.dateToken(in: tokenSample, at: afterFirstTag) == nil,
               "a cursor immediately after a token's closing braces is not inside that token")
        let beforeFirstTag = tokenSample.range(of: "{{date:MMM d}}")!.lowerBound
        suite.expect(TextSnippetSupport.dateToken(in: tokenSample, at: beforeFirstTag) == nil,
               "a cursor immediately before a token's opening braces is not inside that token")

        // Date variable builder support (timezone search and style matching)
        suite.expect(TextSnippetSupport.matchingDateStyle(pattern: "yyyy-MM-dd", kind: .date, locale: enUS) == .iso8601,
               "the ISO 8601 date pattern is recognized as that style")
        suite.expect(TextSnippetSupport.matchingDateStyle(pattern: "not a real pattern", kind: .date, locale: enUS) == .custom,
               "an unrecognized pattern falls back to Custom")

        suite.expect(TextSnippetSupport.matchingTimeZoneIdentifiers(for: "").isEmpty,
               "an empty query matches nothing")
        // Asserted as containment, not equality: the set of identifiers
        // comes from the OS timezone database, so a future release adding
        // another "New York" zone must not fail this.
        suite.expect(TextSnippetSupport.matchingTimeZoneIdentifiers(for: "new york").contains("America/New_York"),
               "a city name with a space matches the underscored identifier")
        // A broad query matches well over a hundred zones. The obvious
        // answer has to be reachable, and near the top: an alphabetical
        // list capped for the picker used to drop it entirely.
        let americaMatches = TextSnippetSupport.matchingTimeZoneIdentifiers(for: "america")
        suite.expect(americaMatches.contains("America/New_York"),
               "a broad region query still lists the major city zones")
        // "york" and the full identifier both narrow to a single match, so
        // neither can observe the ordering. "st" matches dozens, most of
        // which merely contain the letters, so only ranking puts a city
        // beginning with them at the head.
        suite.expect(TextSnippetSupport.matchingTimeZoneIdentifiers(for: "st").first?
                .split(separator: "/").last?.lowercased().hasPrefix("st") == true,
               "a city starting with the query outranks zones that merely contain it")
        suite.expect(TextSnippetSupport.matchingTimeZoneIdentifiers(for: "america/new_york").first
                == "America/New_York",
               "an exactly typed identifier resolves to itself")
        suite.expect(TextSnippetSupport.matchingTimeZoneIdentifiers(for: "xyz-nonsense").isEmpty,
               "a query matching nothing returns an empty list")

        suite.expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "America/New_York") == "America/New_York",
               "a full identifier resolves to itself")
        suite.expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "america/new york") == "America/New_York",
               "the full identifier resolves case- and separator-insensitively")
        suite.expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "new york", matches: ["America/New_York"])
                == "America/New_York",
               "a city name that narrows the suggestion list to exactly one result resolves to it")
        suite.expect(TextSnippetSupport.resolvedTimeZoneIdentifier(
                for: "new", matches: ["America/New_York", "Europe/Newtown"]) == nil,
               "a query still matching several identifiers stays unresolved")
        suite.expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "pst") == "America/Los_Angeles",
               "a common abbreviation resolves to its canonical identifier")
        suite.expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "utc") == "UTC",
               "UTC resolves even though it is not itself in TimeZone.knownTimeZoneIdentifiers")
        suite.expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "budapest")?.hasSuffix("Budapest") == true,
               "a query with no exact match but exactly one substring match resolves to it")
        suite.expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "america") == nil,
               "a query matching many identifiers with no exact hit stays unresolved")
        suite.expect(TextSnippetSupport.resolvedTimeZoneIdentifier(for: "xyz-nonsense") == nil,
               "a query matching nothing is unresolved")

        // A built token round-trips back through detection unchanged: this is
        // exactly the path the Insert/Edit button depends on.
        for kind in TextSnippetSupport.DateVariableKind.allCases {
            for timeZoneIdentifier in [nil, "UTC", "Asia/Tokyo"] as [String?] {
                let built = TextSnippetSupport.dateVariableText(kind: kind, style: .iso8601, customPattern: "",
                                                                 timeZoneIdentifier: timeZoneIdentifier, locale: enUS)
                let midpoint = built.index(built.startIndex, offsetBy: built.count / 2)
                let detected = TextSnippetSupport.dateToken(in: built, at: midpoint)
                suite.expect(detected?.kind == kind && detected?.timeZoneIdentifier == timeZoneIdentifier,
                       "a built \(kind.rawValue) token with timezone \(timeZoneIdentifier ?? "nil") round-trips through dateToken unchanged")
            }
        }

        // Per-snippet capitalization option (issue #304)
        let caseless = TextSnippet(name: "Caseless", trigger: ";email", replacement: "me@x.com",
                                   expansion: .afterDelimiter, enabled: true, ignoresCase: true)
        suite.expect(TextSnippetSupport.match(buffer: "x ;EMAIL", expansion: .afterDelimiter,
                                        snippets: [caseless]) == caseless
                && TextSnippetSupport.match(buffer: "x ;EmAiL", expansion: .afterDelimiter,
                                            snippets: [caseless]) == caseless,
               "a snippet that ignores capitalization fires on any casing")
        suite.expect(TextSnippetSupport.match(buffer: "x ;EMAIL", expansion: .afterDelimiter,
                                        snippets: [email]) == nil,
               "exact snippets still require the configured casing")
        suite.expect(TextSnippetSupport.match(buffer: ";EMAI", expansion: .afterDelimiter,
                                        snippets: [caseless]) == nil,
               "a half-typed trigger stays quiet regardless of casing")
        suite.expect(!TextSnippetSupport.completes(";e", trigger: ";email", ignoresCase: true),
               "a buffer shorter than the trigger never completes it")

        let storedSnippets = [email, dateSnippet, caseless]
        suite.expect(TextSnippetSupport.decode(TextSnippetSupport.encode(storedSnippets)) == storedSnippets,
               "snippets round-trip through persistence")
        suite.expect(TextSnippetSupport.decode(nil).isEmpty, "no stored data means no snippets")
        let legacySnippetJSON = """
        [{"id":"1B6E2F0A-1111-4222-8333-444455556666","name":"Old","trigger":";old",\
        "replacement":"x","expansion":"afterDelimiter","enabled":true}]
        """
        let legacySnippets = TextSnippetSupport.decode(legacySnippetJSON.data(using: .utf8))
        suite.expect(legacySnippets.count == 1 && legacySnippets.first?.ignoresCase == false,
               "snippets saved before the capitalization option decode and keep matching exactly")
        suite.expect(legacySnippets.first?.folder == "" && legacySnippets.first?.showsInLibrary == true,
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
        suite.expect(allSections.map(\.folder) == ["Home", "Work", ""],
               "library folders come alphabetically with loose snippets closing the list")
        suite.expect(allSections.last?.snippets == [loose],
               "disabled and hidden snippets never reach the library")
        suite.expect(allSections[1].snippets == [workMail, workSig],
               "snippets keep their stored order inside a folder")
        suite.expect(TextSnippetSupport.libraryRows(allSections).map(\.name)
                == ["Address", "Work mail", "Signature", "Loose"],
               "the flat row list walks the sections in reading order")

        suite.expect(TextSnippetSupport.librarySections(libraryPool, query: "WORK").flatMap(\.snippets).count == 2,
               "searching matches the folder name regardless of casing")
        suite.expect(TextSnippetSupport.librarySections(libraryPool, query: ";addr").flatMap(\.snippets) == [homeNote],
               "searching matches the trigger")
        suite.expect(TextSnippetSupport.librarySections(libraryPool, query: "loose text").flatMap(\.snippets) == [loose],
               "searching matches the snippet text")
        suite.expect(TextSnippetSupport.librarySections(libraryPool, query: "signat").flatMap(\.snippets) == [workSig],
               "searching matches the name")
        suite.expect(TextSnippetSupport.librarySections(libraryPool, query: "zzz").isEmpty,
               "a search with no matches yields no sections")
        suite.expect(TextSnippetSupport.librarySections(libraryPool, query: "  ").map(\.folder) == ["Home", "Work", ""],
               "a whitespace-only search counts as empty")

        suite.expect(TextSnippetSupport.folderSuggestions(libraryPool) == ["Home", "Work"],
               "folder suggestions are distinct and alphabetical")
        suite.expect(TextSnippetSupport.sanitizedFolder("  Work \n") == "Work",
               "folder names lose surrounding whitespace")
        suite.expect(TextSnippetSupport.sanitizedFolder("   ") == "",
               "a whitespace-only folder means no folder")

        suite.expect(GlobalShortcutRole.snippetLibrary.storageKey == DefaultsKey.snippetLibraryShortcut
                && GlobalShortcutRole.snippetLibrary.defaultShortcut == .snippetLibraryDefault
                && GlobalShortcutRole.snippetLibrary.requiredEnableKeys == [DefaultsKey.snippetLibraryEnabled]
                && GlobalShortcutRole.snippetLibrary.feature == .textSnippets,
               "the library shortcut role is wired to its own keys and the snippets feature")
        let roleDefaults = GlobalShortcutRole.allCases.map(\.defaultShortcut)
        suite.expect(Set(roleDefaults).count == roleDefaults.count,
               "no two shortcut roles ship the same default combination")

        // MARK: Radial menu (issue #220)

        suite.expect(RadialMenuGeometry.angle(dx: 0, dyUp: 1) == 0
                && abs(RadialMenuGeometry.angle(dx: 1, dyUp: 0) - .pi / 2) < 0.0001
                && abs(RadialMenuGeometry.angle(dx: 0, dyUp: -1) - .pi) < 0.0001
                && abs(RadialMenuGeometry.angle(dx: -1, dyUp: 0) - 3 * .pi / 2) < 0.0001,
               "wheel angles run clockwise from 12 o'clock")
        suite.expect(RadialMenuGeometry.index(forAngle: 0, itemCount: 4) == 0
                && RadialMenuGeometry.index(forAngle: .pi / 2, itemCount: 4) == 1
                && RadialMenuGeometry.index(forAngle: .pi, itemCount: 4) == 2
                && RadialMenuGeometry.index(forAngle: 3 * .pi / 2, itemCount: 4) == 3,
               "each slice claims the arc around its own center")
        suite.expect(RadialMenuGeometry.index(forAngle: 2 * .pi - 0.01, itemCount: 12) == 0
                && RadialMenuGeometry.index(forAngle: 2 * .pi - 0.3, itemCount: 12) == 11,
               "the top slice claims both sides of 12 o'clock and its left neighbor starts past it")
        suite.expect(RadialMenuGeometry.index(forAngle: 1, itemCount: 0) == nil,
               "an empty wheel highlights nothing")
        suite.expect(RadialMenuGeometry.highlightedIndex(dx: 10, dyUp: 0, deadZoneRadius: 40, itemCount: 4) == nil
                && RadialMenuGeometry.highlightedIndex(dx: 50, dyUp: 0, deadZoneRadius: 40, itemCount: 4) == 1,
               "the hub dead zone highlights nothing and past it the pointer picks a slice")
        let topUnit = RadialMenuGeometry.unitPosition(index: 0, itemCount: 6)
        let rightUnit = RadialMenuGeometry.unitPosition(index: 1, itemCount: 4)
        suite.expect(abs(topUnit.dx) < 0.0001 && abs(topUnit.dyUp - 1) < 0.0001
                && abs(rightUnit.dx - 1) < 0.0001 && abs(rightUnit.dyUp) < 0.0001,
               "slice centers land on the unit circle from the top clockwise")

        let starter = RadialMenuSupport.starterItems
        suite.expect(starter.count == 6 && RadialMenuSupport.sanitized(starter) == starter,
               "the starter wheel is already clean")
        suite.expect(starter.allSatisfy { !$0.effectiveSymbolName.isEmpty },
               "every starter slice has a symbol to draw")
        suite.expect(RadialMenuSupport.symbolNames.count >= 80
                && Set(RadialMenuSupport.symbolNames).count == RadialMenuSupport.symbolNames.count
                && RadialMenuSupport.symbolNames.contains("speaker.wave.2.fill")
                && RadialMenuSupport.symbolNames.contains("square.and.arrow.up"),
               "the radial editor offers a broad, duplicate-free built-in symbol catalog")
        suite.expect(RadialMenuSupport.decode(nil) == starter,
               "a fresh install decodes to the starter wheel")
        suite.expect(RadialMenuSupport.decode(RadialMenuSupport.encode([])) == [],
               "an emptied wheel stays empty instead of reseeding")

        let sampleWheel = [
            RadialMenuItem(kind: .app, name: "  Editor  ", payload: "/Applications/Editor.app"),
            RadialMenuItem(kind: .url, payload: "example.com/page"),
            RadialMenuItem(kind: .shortcut, payload: "control+option+command:49"),
            RadialMenuItem(kind: .submenu, name: "More", children: [
                RadialMenuItem(kind: .media, payload: "playPause"),
                RadialMenuItem(kind: .submenu, children: [RadialMenuItem(kind: .media, payload: "nextTrack")]),
            ]),
        ]
        let cleaned = RadialMenuSupport.sanitized(sampleWheel)
        suite.expect(cleaned.count == 4 && cleaned[0].name == "Editor"
                && cleaned[1].payload == "https://example.com/page",
               "sanitizing trims names and completes bare links")
        suite.expect(cleaned[3].children.count == 1 && cleaned[3].children[0].kind == .media,
               "submenus keep their actions but never nest another submenu")
        suite.expect(RadialMenuSupport.decode(RadialMenuSupport.encode(cleaned)) == cleaned,
               "radial menu items round-trip through persistence")
        let fullSubmenu = [RadialMenuItem(kind: .submenu, name: "Pack", children: (0 ..< 5).map {
            RadialMenuItem(kind: .url, payload: "example.com/\($0)")
        })]
        suite.expect(RadialMenuSupport.decode(RadialMenuSupport.encode(fullSubmenu)).first?.children.count == 5,
               "a submenu keeps every action through persistence, not just two")
        suite.expect(RadialMenuSupport.sanitized([
            RadialMenuItem(kind: .app, payload: ""),
            RadialMenuItem(kind: .url, payload: "not a link"),
            RadialMenuItem(kind: .shortcut, payload: "garbage"),
            RadialMenuItem(kind: .tool, payload: "unknownTool"),
            RadialMenuItem(kind: .windowLayout, payload: "unknownLayout"),
            RadialMenuItem(kind: .media, payload: "unknownKey"),
        ]).isEmpty,
               "slices that cannot run are dropped instead of rendering dead")
        suite.expect(RadialMenuSupport.sanitized((0 ..< 20).map {
            RadialMenuItem(kind: .url, payload: "example.com/\($0)")
        }).count == RadialMenuSupport.maxItemsPerWheel,
               "a wheel never holds more than 12 slices")
        let lossyJSON = """
        [{"kind":"media","payload":"playPause"},{"kind":"teleport","payload":"x"}]
        """
        suite.expect(RadialMenuSupport.decode(Data(lossyJSON.utf8)).count == 1,
               "unknown kinds from newer versions drop just that slice")

        suite.expect(RadialMenuSupport.normalizedURL("https://a.example/x") == "https://a.example/x"
                && RadialMenuSupport.normalizedURL("mailto:someone@example.com") == "mailto:someone@example.com"
                && RadialMenuSupport.normalizedURL("   ") == nil
                && RadialMenuSupport.normalizedURL("two words") == nil,
               "link normalization keeps schemes and rejects non-links")
        suite.expect(RadialMenuSupport.normalizedURL("tel:5551234") == "tel:5551234"
                && RadialMenuSupport.normalizedURL("example.com:8080/x") == "https://example.com:8080/x"
                && RadialMenuSupport.normalizedURL("localhost:3000") == "https://localhost:3000",
               "digit-after-colon means a port only when the prefix looks like a host")
        suite.expect(RadialMenuSupport.needsAccessibility([starter[3]]) == false
                && RadialMenuSupport.needsAccessibility(starter)
                && RadialMenuSupport.needsAccessibility([
                    RadialMenuItem(kind: .windowLayout, payload: WindowLayoutAction.leftThird.rawValue),
                ])
                && RadialMenuSupport.needsAccessibility([
                    RadialMenuItem(kind: .submenu, children: [RadialMenuItem(kind: .shortcut, payload: "command:8")]),
                ]),
               "keyboard and window actions need Accessibility, submenus included")
        let nowPlayingItem = RadialMenuItem(kind: .media, payload: RadialMenuMediaKey.nowPlaying.rawValue)
        suite.expect(!RadialMenuSupport.needsAccessibility([nowPlayingItem])
                && RadialMenuSupport.containsNowPlaying([nowPlayingItem])
                && RadialMenuSupport.containsNowPlaying([
                    RadialMenuItem(kind: .submenu, children: [nowPlayingItem]),
                ]),
               "Now Playing is found inside wheels without claiming a key-posting permission")
        let radialLayout = RadialMenuItem(kind: .windowLayout,
                                          payload: WindowLayoutAction.leftThird.rawValue)
        suite.expect(RadialMenuSupport.sanitized([radialLayout]) == [radialLayout]
                && radialLayout.windowLayoutAction == .leftThird
                && radialLayout.effectiveSymbolName == WindowLayoutAction.leftThird.symbolName
                && WindowLayoutAction.allCases.allSatisfy { !$0.symbolName.isEmpty }
                && RadialMenuSupport.usesWindowLayout([
                    RadialMenuItem(kind: .submenu, children: [radialLayout]),
                ]),
               "window-layout slices keep a valid placement and its automatic icon")
        suite.expect(RadialMenuMediaKey.playPause.auxKeyType == 16
                && RadialMenuMediaKey.previousTrack.auxKeyType == 20
                && RadialMenuMediaKey.nextTrack.auxKeyType == 19
                && RadialMenuMediaKey.nowPlaying.auxKeyType == nil,
               "media slices post the aux codes of the physical keys")
        let nowPlayingInfo: [String: Any] = [
            RadialNowPlayingSupport.titleKey: " Midnight City ",
            RadialNowPlayingSupport.artistKey: "M83",
            RadialNowPlayingSupport.albumKey: "Hurry Up, We're Dreaming",
            RadialNowPlayingSupport.artworkDataKey: Data([1, 2, 3]),
            RadialNowPlayingSupport.playbackRateKey: 1.0,
        ]
        suite.expect(RadialNowPlayingSupport.playbackIsActive(remoteIsPlaying: nil, info: nowPlayingInfo)
                && RadialNowPlayingSupport.playbackIsActive(remoteIsPlaying: true, info: [:])
                && !RadialNowPlayingSupport.playbackIsActive(remoteIsPlaying: false, info: nowPlayingInfo),
               "Now Playing accepts the remote state or a positive playback rate")
        let nowPlayingSnapshot = RadialNowPlayingSupport.snapshot(
            info: nowPlayingInfo,
            isPlaying: true,
            appBundleIdentifier: " com.apple.Music ",
            appPID: 42)
        suite.expect(nowPlayingSnapshot?.title == "Midnight City"
                && nowPlayingSnapshot?.artist == "M83"
                && nowPlayingSnapshot?.album == "Hurry Up, We're Dreaming"
                && nowPlayingSnapshot?.artworkData == Data([1, 2, 3])
                && nowPlayingSnapshot?.appBundleIdentifier == "com.apple.Music"
                && nowPlayingSnapshot?.appPID == 42
                && nowPlayingSnapshot?.radialLabel == "Midnight City\nM83",
               "Now Playing metadata is sanitized into the radial label and floating card")
        suite.expect(RadialNowPlayingSupport.snapshot(info: nowPlayingInfo,
                                                isPlaying: false,
                                                appBundleIdentifier: "com.apple.Music",
                                                appPID: 42) == nil
                && RadialNowPlayingSupport.snapshot(info: [:],
                                                    isPlaying: true,
                                                    appBundleIdentifier: nil,
                                                    appPID: 0) == nil,
               "paused or ownerless metadata degrades to Nothing Playing")
        let adapterLine = Data("""
            {"kMRMediaRemoteNowPlayingInfoTitle":"Midnight City","kMRMediaRemoteNowPlayingInfoArtist":"M83",\
            "kMRMediaRemoteNowPlayingInfoPlaybackRate":1,"artworkBase64":"AQID","pid":42,\
            "displayID":"com.apple.Music","isPlaying":true}
            """.utf8)
        let adapterReply = RadialNowPlayingSupport.adapterReply(from: adapterLine)
        suite.expect(adapterReply?.info[RadialNowPlayingSupport.titleKey] as? String == "Midnight City"
                && adapterReply?.info[RadialNowPlayingSupport.artistKey] as? String == "M83"
                && adapterReply?.info[RadialNowPlayingSupport.artworkDataKey] as? Data == Data([1, 2, 3])
                && (adapterReply?.info[RadialNowPlayingSupport.playbackRateKey] as? NSNumber)?.doubleValue == 1
                && adapterReply?.pid == 42
                && adapterReply?.displayID == "com.apple.Music"
                && adapterReply?.isPlaying == true,
               "the Now Playing adapter line is read back into the MediaRemote keys the snapshot builder takes")
        let adapterPaused = RadialNowPlayingSupport.adapterReply(
            from: Data(#"{"kMRMediaRemoteNowPlayingInfoTitle":"Midnight City","isPlaying":false}"#.utf8))
        suite.expect(adapterPaused?.pid == 0 && adapterPaused?.displayID == nil && adapterPaused?.isPlaying == false
                && RadialNowPlayingSupport.snapshot(
                    info: adapterPaused?.info ?? [:],
                    isPlaying: RadialNowPlayingSupport.playbackIsActive(remoteIsPlaying: adapterPaused?.isPlaying,
                                                                       info: adapterPaused?.info ?? [:]),
                    appBundleIdentifier: adapterPaused?.displayID,
                    appPID: adapterPaused?.pid ?? 0) == nil,
               "a paused adapter reply degrades to Nothing Playing through the same path as before")
        suite.expect(RadialNowPlayingSupport.adapterReply(from: Data(#"{"error":"MRMediaRemoteGetNowPlayingInfo unavailable"}"#.utf8)) == nil
                && RadialNowPlayingSupport.adapterReply(from: Data("[1,2]".utf8)) == nil
                && RadialNowPlayingSupport.adapterReply(from: Data("perl: cannot load".utf8)) == nil
                && RadialNowPlayingSupport.adapterReply(from: Data(#"{"artworkBase64":"***"}"#.utf8))?
                    .info[RadialNowPlayingSupport.artworkDataKey] == nil,
               "an adapter error, a non-object, shell noise or bad base64 never become a snapshot")
        let adapterAfterWarning = RadialNowPlayingSupport.adapterReply(from: Data("""
            perl: warning: Setting locale failed.
            perl: warning: Falling back to the standard locale ("C").
            {"kMRMediaRemoteNowPlayingInfoTitle":"Midnight City","pid":42,"isPlaying":true}

            """.utf8))
        suite.expect(adapterAfterWarning?.info[RadialNowPlayingSupport.titleKey] as? String == "Midnight City"
                && adapterAfterWarning?.pid == 42 && adapterAfterWarning?.isPlaying == true,
               "a perl warning on the shared stderr pipe ahead of the adapter's JSON line still parses")
        let nowPlayingBuildScript = (try? String(contentsOfFile: "build.sh", encoding: .utf8)) ?? ""
        suite.expect(nowPlayingBuildScript.contains("Sources/NowPlayingAdapter/NowPlayingAdapter.swift")
                && nowPlayingBuildScript.contains("Resources/now-playing.pl")
                && nowPlayingBuildScript.contains("Contents/Frameworks/$NOW_PLAYING_ADAPTER"),
               "build.sh compiles the Now Playing adapter and stages the library and its perl loader")
        let radialQuickToggle = RadialMenuItem(kind: .quickToggle,
                                               payload: RadialMenuQuickToggle.darkMode.rawValue)
        suite.expect(RadialMenuSupport.sanitized([radialQuickToggle]) == [radialQuickToggle]
                && radialQuickToggle.quickToggle == .darkMode
                && RadialMenuQuickToggle.allCases.allSatisfy { !$0.symbolName.isEmpty },
               "quick-toggle slices keep a valid action and automatic icon")
        suite.expect(RadialMenuSupport.sanitized([
            RadialMenuItem(kind: .quickToggle, payload: "unknownAction"),
        ]).isEmpty,
               "unknown quick-toggle slices cannot leave a dead action on the wheel")
        suite.expect(RadialMenuTool.allCases.allSatisfy { !$0.symbolName.isEmpty }
                && RadialMenuTool.screenshot.feature == .screenshot
                && RadialMenuTool.screenRecorder.feature == .screenRecorder
                && RadialMenuTool.clipboardHistory.feature == .clipboardHistory
                && RadialMenuTool.scratchpad.feature == .scratchpad
                && RadialMenuTool.shelf.feature == .shelf
                && RadialMenuTool.cleaner.feature == .cleaner
                && RadialMenuTool.uninstaller.feature == .uninstaller
                && RadialMenuTool.appUpdates.feature == .appUpdates
                && RadialMenuTool.cleaningMode.feature == .cleaningMode
                && RadialMenuTool.keepAwake.feature == .keepAwake,
               "every wheel tool maps to a real feature and symbol")
        let addedWheelTools: [RadialMenuTool] = [.screenRecorder, .cleaner, .uninstaller, .appUpdates]
        suite.expect(addedWheelTools.allSatisfy {
            $0.isRunnable(isFeatureAvailable: { _ in true }, boolFor: { _ in false })
        }, "recording and maintenance tools are selectable when their hub features are available")
        suite.expect(!RadialMenuTool.shelf.isRunnable(isFeatureAvailable: { _ in true },
                                                boolFor: { _ in false })
                && RadialMenuTool.shelf.isRunnable(isFeatureAvailable: { _ in true },
                                                   boolFor: { $0 == DefaultsKey.shelfEnabled })
                && !RadialMenuTool.shelf.isRunnable(isFeatureAvailable: { _ in false },
                                                    boolFor: { _ in true })
                && RadialMenuTool.cleaningMode.isRunnable(isFeatureAvailable: { _ in true },
                                                          boolFor: { _ in false }),
               "Shelf wheel slices follow the Shelf master switch without affecting on-demand tools")

        // MARK: Radial menu profiles

        let allColors = RadialMenuColor.allCases
        suite.expect(allColors.count == 12
                && Set(allColors.map(\.rawValue)).count == 12
                && allColors.allSatisfy { $0.id == $0.rawValue },
               "twelve distinct radial menu accent colors")
        let enStrings = FeatureStrings.radialMenu(.enUS)
        suite.expect(RadialMenuColor.accent.title(enStrings) == "Accent"
                && RadialMenuColor.blue.title(enStrings) == "Blue"
                && RadialMenuColor.purple.title(enStrings) == "Purple"
                && RadialMenuColor.pink.title(enStrings) == "Pink"
                && RadialMenuColor.red.title(enStrings) == "Red"
                && RadialMenuColor.orange.title(enStrings) == "Orange"
                && RadialMenuColor.yellow.title(enStrings) == "Yellow"
                && RadialMenuColor.green.title(enStrings) == "Green"
                && RadialMenuColor.mint.title(enStrings) == "Mint"
                && RadialMenuColor.cyan.title(enStrings) == "Cyan"
                && RadialMenuColor.indigo.title(enStrings) == "Indigo"
                && RadialMenuColor.graphite.title(enStrings) == "Graphite",
               "radial menu color titles localize properly")

        let allPresets = RadialMenuProfilePreset.allCases
        suite.expect(allPresets.count == 6
                && Set(allPresets.map(\.rawValue)).count == 6
                && allPresets.allSatisfy { $0.id == $0.rawValue },
               "six distinct radial profile presets")
        suite.expect(RadialMenuProfilePreset.general.makeItems().count == 6
                && RadialMenuProfilePreset.media.makeItems().count == 4
                && RadialMenuProfilePreset.tools.makeItems().count == 6
                && RadialMenuProfilePreset.windowLayout.makeItems().count == 5
                && RadialMenuProfilePreset.quickToggles.makeItems().count == 5
                && RadialMenuProfilePreset.blank.makeItems().isEmpty,
               "presets generate expected initial item layouts")

        let customProfile = RadialMenuProfile(
            id: UUID(),
            name: " Media Wheel ",
            color: .purple,
            shortcut: "control+command:49",
            mouseButton: RadialMenuMouseTrigger.back.rawValue,
            items: RadialMenuProfilePreset.media.makeItems()
        )
        suite.expect(customProfile.displayName(enStrings) == " Media Wheel ",
               "profile custom name is displayed")
        let blankNamedProfile = RadialMenuProfile(name: "", color: .accent)
        suite.expect(blankNamedProfile.displayName(enStrings) == enStrings.presetGeneral,
               "blank profile name falls back to General preset title")

        let encodedProfilesData = RadialMenuSupport.encodeProfiles([customProfile])
        let decodedProfiles = RadialMenuSupport.decodeProfiles(encodedProfilesData)
        suite.expect(decodedProfiles.count == 1
                && decodedProfiles[0].id == customProfile.id
                && decodedProfiles[0].name == "Media Wheel"
                && decodedProfiles[0].color == .purple
                && decodedProfiles[0].shortcut == "control+command:49"
                && decodedProfiles[0].mouseButton == RadialMenuMouseTrigger.back.rawValue
                && decodedProfiles[0].items.count == 4,
               "profile encodes and decodes accurately with trimmed name")

        let renamedPresetProfile = RadialMenuProfilePreset.media.createProfile(name: "Renamed")
        let presetRoundTrip = RadialMenuSupport.decodeProfiles(
            RadialMenuSupport.encodeProfiles([renamedPresetProfile]))
        suite.expect(renamedPresetProfile.preset == RadialMenuProfilePreset.media.rawValue
                && presetRoundTrip.first?.preset == RadialMenuProfilePreset.media.rawValue,
               "a wheel keeps the starter set it came from, whatever it is renamed to")
        let profileWithoutPreset = Data("""
        [{"id":"\(UUID().uuidString)","name":"Old Wheel","color":"accent",\
        "shortcut":"","mouseButton":"off","items":[]}]
        """.utf8)
        suite.expect(RadialMenuSupport.decodeProfiles(profileWithoutPreset).first?.preset == nil,
               "a wheel saved before the starter set was recorded decodes without one")

        let dupID = UUID()
        let dups = [
            RadialMenuProfile(id: dupID, name: "First"),
            RadialMenuProfile(id: dupID, name: "Duplicate"),
            RadialMenuProfile(id: UUID(), name: "  Trim Me  ", shortcut: "invalidShortcutFormat"),
        ]
        let sanitizedDups = RadialMenuSupport.sanitizedProfiles(dups)
        suite.expect(sanitizedDups.count == 2
                && sanitizedDups[0].name == "First"
                && sanitizedDups[1].name == "Trim Me"
                && sanitizedDups[1].shortcut.isEmpty,
               "sanitized profiles deduplicate IDs, trim names, and drop invalid shortcuts")

        let emptySanitized = RadialMenuSupport.sanitizedProfiles([])
        suite.expect(emptySanitized.count == 1
                && emptySanitized[0].color == .accent
                && !emptySanitized[0].shortcut.isEmpty
                && emptySanitized[0].items.count == 6,
               "sanitizing empty profile list provides one default starter profile")

        let appOnlyProfile = RadialMenuProfile(
            mouseButton: RadialMenuMouseTrigger.off.rawValue,
            items: [RadialMenuItem(kind: .app, payload: "/Applications/Safari.app")]
        )
        suite.expect(!RadialMenuSupport.needsAccessibility([appOnlyProfile]),
               "app-only profile without mouse button does not need Accessibility")
        let mouseProfile = RadialMenuProfile(
            mouseButton: RadialMenuMouseTrigger.forward.rawValue,
            items: [RadialMenuItem(kind: .app, payload: "/Applications/Safari.app")]
        )
        suite.expect(RadialMenuSupport.needsAccessibility([mouseProfile]),
               "profile with mouse trigger needs Accessibility")
        let shortcutProfile = RadialMenuProfile(
            mouseButton: RadialMenuMouseTrigger.off.rawValue,
            items: [RadialMenuItem(kind: .shortcut, payload: "command:8")]
        )
        suite.expect(RadialMenuSupport.needsAccessibility([shortcutProfile]),
               "profile with keyboard shortcut slice needs Accessibility")

        let profileTestDefaults = UserDefaults(suiteName: "com.vorssaint.tests.radialProfiles")!
        profileTestDefaults.removePersistentDomain(forName: "com.vorssaint.tests.radialProfiles")
        profileTestDefaults.set(true, forKey: AppFeature.radialMenu.availabilityKey)
        profileTestDefaults.set(true, forKey: DefaultsKey.radialMenuEnabled)

        let profileA = RadialMenuProfile(
            name: "Work",
            mouseButton: RadialMenuMouseTrigger.back.rawValue
        )
        let profileB = RadialMenuProfile(
            name: "Fun",
            mouseButton: RadialMenuMouseTrigger.button(4).rawValue
        )
        profileTestDefaults.set(RadialMenuSupport.encodeProfiles([profileA, profileB]), forKey: DefaultsKey.radialMenuProfiles)

        suite.expect(RadialMenuSupport.claimsMouseButton(MouseButtonShortcutSupport.backButtonNumber, defaults: profileTestDefaults),
               "claims button 3 from profile A")
        suite.expect(RadialMenuSupport.claimsMouseButton(4, defaults: profileTestDefaults),
               "claims button 4 from profile B")
        suite.expect(!RadialMenuSupport.claimsMouseButton(5, defaults: profileTestDefaults),
               "does not claim unclaimed button 5")

        profileTestDefaults.set(false, forKey: DefaultsKey.radialMenuEnabled)
        suite.expect(!RadialMenuSupport.claimsMouseButton(MouseButtonShortcutSupport.backButtonNumber, defaults: profileTestDefaults),
               "disabled radial menu never claims mouse buttons")
        profileTestDefaults.removePersistentDomain(forName: "com.vorssaint.tests.radialProfiles")

        let testImage = NSImage(size: NSSize(width: 16, height: 16))
        testImage.lockFocus()
        NSColor.red.set()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        testImage.unlockFocus()
        let samplePNG = RadialMenuFaviconFetcher.scaledPNGData(from: testImage, targetSize: 32)
        suite.expect(samplePNG != nil && (samplePNG?.count ?? 0) > 0, "scaledPNGData produces valid PNG")
        suite.expect(samplePNG.map { RadialMenuFaviconFetcher.sourceDimensionsAreSafe($0) } == true
               && !RadialMenuFaviconFetcher.sourceDimensionsAreSafe(Data("not an image".utf8)),
               "favicon decoding accepts bounded images and rejects invalid payloads")

        // The event taps read the cheap answer on every side-button event, so
        // it has to agree with the full decode, custom icons and all.
        let iconProfile = RadialMenuProfile(
            name: "Icons",
            mouseButton: RadialMenuMouseTrigger.button(6).rawValue,
            items: [RadialMenuItem(kind: .app,
                                   payload: "/Applications/Safari.app",
                                   customIconData: samplePNG)]
        )
        let iconProfilesData = RadialMenuSupport.encodeProfiles([iconProfile, profileA])
        let fullyDecodedButtons = RadialMenuSupport.decodeProfiles(iconProfilesData)
            .compactMap { RadialMenuMouseTrigger.sanitized($0.mouseButton).buttonNumber }
        suite.expect(fullyDecodedButtons == [6, MouseButtonShortcutSupport.backButtonNumber]
                && RadialMenuSupport.claimedMouseButtons(iconProfilesData) == fullyDecodedButtons,
               "claimed mouse buttons read without the items match the full profile decode")

        let legacyButtonDefaults = UserDefaults(suiteName: "com.vorssaint.tests.radialLegacyButton")!
        legacyButtonDefaults.removePersistentDomain(forName: "com.vorssaint.tests.radialLegacyButton")
        legacyButtonDefaults.set(RadialMenuMouseTrigger.forward.rawValue,
                                 forKey: DefaultsKey.radialMenuMouseButton)
        suite.expect(RadialMenuSupport.claimedMouseButtons(nil, defaults: legacyButtonDefaults)
                == [MouseButtonShortcutSupport.forwardButtonNumber]
                && RadialMenuSupport.claimedMouseButtons(Data("not profiles".utf8),
                                                         defaults: legacyButtonDefaults)
                == [MouseButtonShortcutSupport.forwardButtonNumber],
               "claimed mouse buttons fall back to the legacy button key like the full decode")
        legacyButtonDefaults.removePersistentDomain(forName: "com.vorssaint.tests.radialLegacyButton")

        var reorderItems = [
            RadialMenuItem(kind: .app, name: "A"),
            RadialMenuItem(kind: .app, name: "B"),
            RadialMenuItem(kind: .app, name: "C"),
        ]
        let itemToMove = reorderItems[0]
        let targetItem = reorderItems[2]
        if let from = reorderItems.firstIndex(where: { $0.id == itemToMove.id }),
           let to = reorderItems.firstIndex(where: { $0.id == targetItem.id }) {
            reorderItems.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        suite.expect(reorderItems.map(\.name) == ["B", "C", "A"],
               "radial items can be reordered correctly by drag target")

        var swapItems = [
            RadialMenuItem(kind: .app, name: "A"),
            RadialMenuItem(kind: .app, name: "B"),
            RadialMenuItem(kind: .app, name: "C"),
            RadialMenuItem(kind: .app, name: "D"),
        ]
        let firstToSwap = swapItems[0]
        let secondToSwap = swapItems[2]
        if let from = swapItems.firstIndex(where: { $0.id == firstToSwap.id }),
           let to = swapItems.firstIndex(where: { $0.id == secondToSwap.id }) {
            swapItems.swapAt(from, to)
        }
        suite.expect(swapItems.map(\.name) == ["C", "B", "A", "D"],
               "radial items can be swapped directly without displacing intermediate items")

        // The cheap read and the full decode can disagree on a corrupt blob,
        // so only one of them may decide whether the click is passed on: once
        // the button is claimed, nothing past that point hands an event back,
        // or the down and the up split.
        let radialServiceCode = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/RadialMenu/RadialMenuService.swift",
            encoding: .utf8)) ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let radialClaimedClick = radialServiceCode
            .components(separatedBy: "if type == .otherMouseDown {")
            .dropFirst().first?
            .components(separatedBy: "private func hotkeyPressed").first ?? ""
        suite.expect(!radialClaimedClick.isEmpty && !radialClaimedClick.contains("passUnretained"),
               "a claimed side button keeps both halves of its click whatever the full decode says")

        // The tap is the only thing that ends a button-held wheel, so handing
        // it back on resign has to end the session too; a wheel left open
        // across the switch would come back in hold phase with no release
        // coming for it.
        let radialSessionResign = radialServiceCode
            .components(separatedBy: "SessionActivity.shared.onChange")
            .dropFirst().first?
            .components(separatedBy: "var sessionActive").first ?? ""
        suite.expect(radialSessionResign.contains("endSession()"),
               "the radial menu ends its session when the mouse tap is handed back on resign")
        suite.expect(RadialMenuFaviconFetcher.faviconURL(
            for: "https://example.com:8443/path?q=1#part")?.absoluteString
                == "https://example.com:8443/favicon.ico"
               && RadialMenuFaviconFetcher.faviconURL(for: "not a url") == nil,
               "favicon download stays on the website origin and preserves its port")

        let itemWithFavicon = RadialMenuItem(kind: .url, name: "Site", payload: "https://example.com", customIconData: samplePNG)
        let encodedFaviconData = RadialMenuSupport.encode([itemWithFavicon])
        let decodedFaviconItem = RadialMenuSupport.decode(encodedFaviconData).first
        suite.expect(decodedFaviconItem?.customIconData == samplePNG,
               "customIconData survives encode and decode")

        let oversizedData = Data(repeating: 0xFF, count: 70_000)
        let itemWithOversizedIcon = RadialMenuItem(kind: .url, name: "Site", payload: "https://example.com", customIconData: oversizedData)
        let sanitizedOversized = RadialMenuSupport.sanitized([itemWithOversizedIcon]).first
        suite.expect(sanitizedOversized?.customIconData == nil,
               "sanitized drops oversized customIconData")

        let invalidImageData = Data([0x00, 0x01, 0x02, 0x03])
        let itemWithInvalidIcon = RadialMenuItem(kind: .url, name: "Site", payload: "https://example.com", customIconData: invalidImageData)
        let sanitizedInvalid = RadialMenuSupport.sanitized([itemWithInvalidIcon]).first
        suite.expect(sanitizedInvalid?.customIconData == nil,
               "sanitized drops corrupted customIconData that cannot form an NSImage")

        // MARK: Dock click with AX-blind apps (issue #200)

        suite.expect(DockClickSupport.effectiveHasUnminimized(unminimizedCount: 2,
                                                        minimizedCount: 0,
                                                        windowServerSeesWindows: false),
               "AX-visible windows count as always")
        suite.expect(DockClickSupport.effectiveHasUnminimized(unminimizedCount: 0,
                                                        minimizedCount: 0,
                                                        windowServerSeesWindows: true),
               "an AX-blind app with on-screen windows still minimizes")
        suite.expect(!DockClickSupport.effectiveHasUnminimized(unminimizedCount: 0,
                                                         minimizedCount: 3,
                                                         windowServerSeesWindows: true),
               "minimized-only apps keep the restore path")
        suite.expect(!DockClickSupport.effectiveHasUnminimized(unminimizedCount: 0,
                                                         minimizedCount: 0,
                                                         windowServerSeesWindows: false),
               "a truly windowless app passes the click through")
        suite.expect(!DockClickSupport.isDragMovement(from: CGPoint(x: 100, y: 100),
                                                to: CGPoint(x: 103, y: 103)),
               "click jitter stays a click")
        suite.expect(!DockClickSupport.isDragMovement(from: CGPoint(x: 100, y: 100),
                                                to: CGPoint(x: 106, y: 100)),
               "movement at the slop boundary still counts as a click")
        suite.expect(DockClickSupport.isDragMovement(from: CGPoint(x: 100, y: 100),
                                               to: CGPoint(x: 105, y: 105)),
               "a real drag crosses the slop and hands the press to the Dock")
        suite.expect(DockClickSupport.isDragMovement(from: CGPoint(x: 100, y: 100),
                                               to: CGPoint(x: 100, y: 93)),
               "vertical pulls count as drags too")

        // MARK: Dock click restore order (issue #357)

        // The AX array order is deliberately unhelpful in these cases: the
        // captured WindowServer stacking is what has to decide the outcome.
        suite.expect(DockClickSupport.restoreSequence(ids: [10, 20], frontToBack: [10, 20]) == [1, 0],
               "the window that was frontmost is restored last so it lands on top")
        suite.expect(DockClickSupport.restoreSequence(ids: [10, 20], frontToBack: [20, 10]) == [0, 1],
               "the batch follows the captured stacking, not the order it arrived in")
        suite.expect(DockClickSupport.restoreSequence(ids: [10, 20, 30], frontToBack: [20, 30, 10]) == [0, 2, 1],
               "a three window batch rebuilds the captured stacking bottom up")
        suite.expect(DockClickSupport.restoreSequence(ids: [10, 20, 10, 20], frontToBack: [10, 20]) == [1, 0],
               "the same window captured twice is restored once, in its captured slot")
        suite.expect(DockClickSupport.restoreSequence(ids: [10, 40], frontToBack: [10, 20]) == [1, 0],
               "a window missing from the capture counts as rearmost and restores first")
        suite.expect(DockClickSupport.restoreSequence(ids: [10], frontToBack: [10]) == [0],
               "a single window restores as itself")
        suite.expect(DockClickSupport.restoreSequence(ids: [], frontToBack: []).isEmpty,
               "an empty batch stays empty")
        suite.expect(DockClickSupport.restoreSequence(ids: [10, 20, 30],
                                                frontToBack: [],
                                                preferredFront: 20) == [0, 2, 1],
               "with no capture the app's main window is moved to the end")
        suite.expect(DockClickSupport.restoreSequence(ids: [10, 20], frontToBack: [], preferredFront: nil) == [0, 1],
               "with nothing to go on the batch keeps the order it arrived in")
        suite.expect(DockClickSupport.restoreSequence(ids: [nil, nil], frontToBack: []) == [0, 1],
               "unresolvable windows are never deduped away")

        // MARK: Quick toggles

        suite.expect(QuickTogglesSupport.emptyTrashSource == "tell application \"Finder\" to empty trash",
               "the Trash script asks the Finder and nothing else")
        suite.expect(QuickTogglesSupport.isPermissionError(-1743)
                && QuickTogglesSupport.isPermissionError(-1744),
               "both Apple Event consent errors read as a permission problem")
        suite.expect(!QuickTogglesSupport.isPermissionError(-1728)
                && !QuickTogglesSupport.isPermissionError(nil),
               "other script errors and success never read as a permission problem")
        suite.expect(QuickTogglesSupport.finderFlag(true, default: false)
                && !QuickTogglesSupport.finderFlag(false, default: true),
               "real booleans win over the default")
        suite.expect(QuickTogglesSupport.finderFlag("YES", default: false)
                && QuickTogglesSupport.finderFlag("true", default: false)
                && QuickTogglesSupport.finderFlag("1", default: false),
               "legacy YES, true and 1 strings read as on")
        suite.expect(!QuickTogglesSupport.finderFlag("NO", default: true)
                && !QuickTogglesSupport.finderFlag("false", default: true)
                && !QuickTogglesSupport.finderFlag("0", default: true),
               "legacy NO, false and 0 strings read as off")
        suite.expect(QuickTogglesSupport.finderFlag(NSNumber(value: 1), default: false)
                && !QuickTogglesSupport.finderFlag(NSNumber(value: 0), default: true),
               "numeric preference values read by their truthiness")
        suite.expect(QuickTogglesSupport.finderFlag(nil, default: true)
                && !QuickTogglesSupport.finderFlag(nil, default: false)
                && QuickTogglesSupport.finderFlag("maybe", default: true),
               "absent or unreadable values fall back to the given default")
        suite.expect(QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: true,
                                                    isEjectable: false, isLocal: true,
                                                    isRootFileSystem: false)
                && QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: false,
                                                        isEjectable: true, isLocal: true,
                                                        isRootFileSystem: false),
               "external removable or ejectable local volumes are offered")
        suite.expect(QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: false,
                                                    isEjectable: false, isLocal: true,
                                                    isRootFileSystem: false),
               "an external drive with fixed media is offered, the common desk drive")
        suite.expect(QuickTogglesSupport.shouldOfferEject(isInternal: true, isRemovable: true,
                                                    isEjectable: true, isLocal: true,
                                                    isRootFileSystem: false),
               "media that comes out of an internal reader is offered")
        suite.expect(!QuickTogglesSupport.shouldOfferEject(isInternal: true, isRemovable: false,
                                                     isEjectable: false, isLocal: true,
                                                     isRootFileSystem: false),
               "internal fixed drives are never ejected")
        suite.expect(!QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: true,
                                                     isEjectable: true, isLocal: false,
                                                     isRootFileSystem: false),
               "network volumes are never ejected")
        suite.expect(!QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: true,
                                                     isEjectable: true, isLocal: true,
                                                     isRootFileSystem: true),
               "the volume the Mac booted from is never ejected, even on an external drive")
        suite.expect(!QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: false,
                                                     isEjectable: true, isLocal: true,
                                                     isRootFileSystem: false,
                                                     volumeName: "Time Machine",
                                                     excludedVolumes: ["time machine"]),
               "a volume matching an excluded name case-insensitively is not offered for eject")
        suite.expect(!QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: true,
                                                     isEjectable: true, isLocal: true,
                                                     isRootFileSystem: false,
                                                     volumeName: "SD Card",
                                                     volumeUUID: "1234-5678-ABCD",
                                                     excludedVolumes: ["1234-5678-abcd"]),
               "a volume matching an excluded UUID is not offered for eject")
        suite.expect(QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: true,
                                                    isEjectable: true, isLocal: true,
                                                    isRootFileSystem: false,
                                                    volumeName: "USB Flash",
                                                    excludedVolumes: ["Time Machine"]),
               "a volume not on the exclusion list is offered for eject")
        suite.expect(Defaults.sanitizedDiskExclusionList(["  Backup  ", "backup", "", "  ", "Photos", "PHOTOS"])
                == ["Backup", "Photos"],
               "sanitized disk exclusion list trims and deduplicates case-insensitively")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.diskEjectExcludedVolumes] is [String],
               "disk eject exclusions are registered as an empty string array")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.diskEjectExcludedVolumes),
               "disk eject exclusions travel in backups")

        // MARK: A sleeping clock
        for shareService in ["Sources/Vorssaint/Services/QuickTools/ScreenshotShareService.swift",
                             "Sources/Vorssaint/Services/Recorder/RecordingShareService.swift"] {
            let shareCode = ((try? String(contentsOfFile: shareService, encoding: .utf8)) ?? "")
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            suite.expect(shareCode.contains("NSWorkspace.didWakeNotification"),
                   "\(shareService) recomputes share link expiry on wake, which its sleeping clock missed")
        }

        // The confirmation HUD is a hand-laid AppKit panel, so its width is
        // pinned as source shape. It used to be a fixed 300pt, which clipped
        // the longer translations. Sizing it from a separate
        // NSString measurement of the same text would leave whatever inset
        // the label's cell adds unaccounted for -- the labels have to be the
        // ones asked.
        let quitHUDSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/QuitProtection/QuitProtectionHUD.swift",
            encoding: .utf8)) ?? ""
        suite.expect(quitHUDSource.count > 1_000,
               "the quit protection HUD source is readable (\(quitHUDSource.count) bytes)")
        let quitHUDCode = quitHUDSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(quitHUDCode.contains("title.fittingSize.width")
                && quitHUDCode.contains("detail.fittingSize.width"),
               "the confirmation HUD takes its width from the labels that draw the text")
        suite.expect(!quitHUDCode.contains("size(withAttributes:"),
               "the confirmation HUD does not size itself from a separate text measurement")
        let quitHUDShow = quitHUDCode
            .components(separatedBy: "func show(title: String, detail: String").last ?? ""
        let quitHUDShowBody = quitHUDShow.components(separatedBy: "\n    func ").first ?? ""
        if let filled = quitHUDShowBody.range(of: "content.update("),
           let sized = quitHUDShowBody.range(of: "fittingSize(content)"),
           let applied = quitHUDShowBody.range(of: "setContentSize(size)") {
            suite.expect(filled.lowerBound < sized.lowerBound && sized.lowerBound < applied.lowerBound,
                   "the confirmation HUD fills its labels, then measures them, then resizes")
        } else {
            suite.expect(false,
                   "the confirmation HUD's show() fills the labels, measures them and resizes")
        }
        // MARK: A dropped identifier
        suite.expect(QuickTogglesSupport.isExcluded(volumeName: "SD Card",
                                              volumeUUID: "1234-5678-ABCD",
                                              mountPath: "/Volumes/SD Card",
                                              excludedVolumes: ["1234-5678-abcd"])
                && !QuickTogglesSupport.isExcluded(volumeName: "SD Card",
                                                   volumeUUID: nil,
                                                   mountPath: "/Volumes/SD Card",
                                                   excludedVolumes: ["1234-5678-abcd"]),
               "an excluded volume UUID is honoured only when the caller hands the UUID over")
        let diskExclusionsListCode = ((try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/DiskExclusionsList.swift",
            encoding: .utf8)) ?? "").components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(diskExclusionsListCode.contains(".volumeUUIDStringKey")
                && diskExclusionsListCode.contains("QuickTogglesSupport.isExcluded("),
               "the exclusions picker asks the shared exclusion test, UUID included, not a name-only one")

    }
}
