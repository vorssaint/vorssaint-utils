// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One text snippet: typing the trigger inserts the replacement. Stored as
/// JSON in defaults; ids and raw values are persisted, so keep them stable.
struct TextSnippet: Codable, Identifiable, Equatable {
    /// When the replacement fires relative to the trigger.
    enum Expansion: String, Codable, CaseIterable {
        /// The moment the last trigger character is typed.
        case immediate
        /// Only when space, Tab or Return follows the trigger (the delimiter
        /// itself is kept, typed after the replacement).
        case afterDelimiter
    }

    var id = UUID()
    var name = ""
    var trigger = ""
    var replacement = ""
    var expansion = Expansion.afterDelimiter
    var enabled = true
    var ignoresCase = false
    /// Plain folder name for the library; empty means no folder. Folders are
    /// derived from the snippets themselves, so there is no folder entity to
    /// migrate or orphan.
    var folder = ""
    var showsInLibrary = true

    enum CodingKeys: String, CodingKey {
        case id, name, trigger, replacement, expansion, enabled, ignoresCase, folder, showsInLibrary
    }
}

extension TextSnippet {
    /// Snippets stored before an option existed have no key for it; each one
    /// falls back to the behavior of its day (exact matching, no folder,
    /// visible in the library).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        trigger = try container.decode(String.self, forKey: .trigger)
        replacement = try container.decode(String.self, forKey: .replacement)
        expansion = try container.decode(Expansion.self, forKey: .expansion)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        ignoresCase = try container.decodeIfPresent(Bool.self, forKey: .ignoresCase) ?? false
        folder = try container.decodeIfPresent(String.self, forKey: .folder) ?? ""
        showsInLibrary = try container.decodeIfPresent(Bool.self, forKey: .showsInLibrary) ?? true
    }
}

/// The pure half of the snippets engine: buffer bookkeeping, trigger
/// matching and variable expansion, all deterministic and injectable so the
/// harness can pin the behavior down.
enum TextSnippetSupport {
    /// Keystrokes the buffer remembers; longer triggers cannot match.
    static let bufferLimit = 64
    static let maxTriggerLength = 40

    /// Characters that fire an afterDelimiter snippet.
    static let delimiters: Set<Character> = [" ", "\t", "\r", "\n"]

    static let systemSoundsPath = "/System/Library/Sounds"

    /// The classic macOS alert sounds, used when the sounds directory
    /// cannot be read.
    static let fallbackAlertSoundNames = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
        "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    /// The sound names among `entries` (a directory listing), sorted for a
    /// stable picker order. Falls back rather than returning nothing: an
    /// empty picker would leave the preference unsettable.
    static func alertSoundNames(from entries: [String]) -> [String] {
        let names = entries
            .filter { $0.lowercased().hasSuffix(".aiff") }
            .map { String($0.dropLast(".aiff".count)) }
            .sorted()
        return names.isEmpty ? fallbackAlertSoundNames : names
    }

    /// The alert sounds the picker offers. Read from the directory rather
    /// than hardcoded so a sound macOS adds shows up on its own.
    static let alertSoundNames: [String] = alertSoundNames(
        from: (try? FileManager.default.contentsOfDirectory(atPath: systemSoundsPath)) ?? [])

    /// The sound to actually use for a stored preference. A name saved on
    /// another Mac, or one this macOS no longer ships, would otherwise
    /// leave the picker blank and the expansion silent while the toggle
    /// still reads on.
    static func resolvedSoundName(stored: String?,
                                  available: [String] = alertSoundNames,
                                  fallback: String = Defaults.defaultSnippetSoundName) -> String? {
        if let stored, available.contains(stored) { return stored }
        if available.contains(fallback) { return fallback }
        return available.first
    }

    /// Triggers cannot contain whitespace (the buffer resets on it) and stay
    /// within a sane length.
    static func sanitizedTrigger(_ raw: String) -> String {
        String(raw.filter { !$0.isWhitespace }.prefix(maxTriggerLength))
    }

    /// The typing buffer after one insertion. Anything beyond the limit
    /// slides off the front; the buffer only ever needs to hold the longest
    /// possible trigger.
    static func bufferAppending(_ buffer: String, typed: String) -> String {
        let next = buffer + typed
        return String(next.suffix(bufferLimit))
    }

    /// The snippet whose trigger the buffer just completed for the given
    /// expansion mode. The longest trigger wins, so ";email2" beats ";email"
    /// the way the user expects.
    static func match(buffer: String,
                      expansion: TextSnippet.Expansion,
                      snippets: [TextSnippet]) -> TextSnippet? {
        var best: TextSnippet?
        for snippet in snippets where snippet.enabled
            && snippet.expansion == expansion
            && !snippet.trigger.isEmpty
            && completes(buffer, trigger: snippet.trigger, ignoresCase: snippet.ignoresCase) {
            if let current = best, current.trigger.count >= snippet.trigger.count { continue }
            best = snippet
        }
        return best
    }

    /// Whether the buffer just finished typing the trigger. The insensitive
    /// path compares exactly `trigger.count` characters, so the deletes the
    /// expansion posts always erase precisely what the user typed.
    static func completes(_ buffer: String, trigger: String, ignoresCase: Bool) -> Bool {
        guard ignoresCase else { return buffer.hasSuffix(trigger) }
        guard buffer.count >= trigger.count else { return false }
        return String(buffer.suffix(trigger.count))
            .compare(trigger, options: .caseInsensitive) == .orderedSame
    }

    /// Replaces the dynamic variables. Unknown {{tags}} pass through
    /// untouched, so a typo stays visible instead of vanishing silently.
    /// The one variable whose value comes from somewhere that can hang: the
    /// general pasteboard may hold content an app renders only on demand, and
    /// an app that stops answering never answers. Both expansion paths ask
    /// this first, so a replacement without the variable pays nothing.
    static func needsClipboard(_ replacement: String) -> Bool {
        replacement.contains("{{clipboard}}")
    }

    static func requiresPaste(_ text: String) -> Bool {
        text.contains(where: \.isNewline)
    }

    static func pastePayload(text: String, trailingText: String) -> String {
        text + trailingText.replacingOccurrences(of: "\r", with: "\n")
    }

    static func expand(_ replacement: String,
                       date: Date,
                       clipboard: String?,
                       locale: Locale = .current) -> String {
        guard replacement.contains("{{") else { return replacement }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let dateText = dateFormatter.string(from: date)
        let timeText = timeFormatter.string(from: date)
        let expanded = replacement
            .replacingOccurrences(of: "{{date}}", with: dateText)
            .replacingOccurrences(of: "{{time}}", with: timeText)
            .replacingOccurrences(of: "{{datetime}}", with: "\(dateText) \(timeText)")
        // The clipboard goes in last so pasted text is never re-expanded.
        return expandingFormattedDates(expanded, date: date, locale: locale)
            .replacingOccurrences(of: "{{clipboard}}", with: clipboard ?? "")
    }

    /// The date variables also take an explicit pattern after a colon, in the
    /// system's own date-format language: {{date:yyyy-MM-dd}}, and the same
    /// for time and datetime so every spelling works. The pattern keeps the
    /// user's locale, so month and weekday names come out in their language.
    /// A variant with an explicit IANA identifier after the kind,
    /// {{date-tz(America/New_York):yyyy-MM-dd}}, overrides the device's
    /// current time zone for that one token.
    private static let formattedDateKinds = ["date", "time", "datetime"]

    /// Configures a DateFormatter's pattern and timezone override. Called by
    /// both expandingFormattedDates and configuredFormatter to ensure a single
    /// place decides how these two properties map from pattern and identifier.
    private static func configure(_ formatter: DateFormatter,
                                  pattern: String,
                                  timeZoneIdentifier: String?) {
        formatter.dateFormat = pattern
        formatter.timeZone = timeZoneIdentifier.flatMap { TimeZone(identifier: $0) }
    }

    /// A fresh formatter for one-off use (a preview), as opposed to
    /// expandingFormattedDates's single instance reused across a whole
    /// replacement string's tokens.
    private static func configuredFormatter(pattern: String,
                                            timeZoneIdentifier: String?,
                                            locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        configure(formatter, pattern: pattern, timeZoneIdentifier: timeZoneIdentifier)
        return formatter
    }

    private static func expandingFormattedDates(_ text: String,
                                                date: Date,
                                                locale: Locale) -> String {
        guard formattedDateKinds.contains(where: { text.contains("{{\($0)") }) else { return text }
        let formatter = DateFormatter()
        formatter.locale = locale
        var result = ""
        var rest = Substring(text)
        while let start = rest.range(of: "{{") {
            result += rest[..<start.lowerBound]
            let tail = rest[start.lowerBound...]
            guard let close = tail.range(of: "}}"),
                  let match = formattedPattern(in: tail[..<close.lowerBound]) else {
                result += "{{"
                rest = rest[start.upperBound...]
                continue
            }
            configure(formatter, pattern: match.pattern, timeZoneIdentifier: match.timeZoneIdentifier)
            result += formatter.string(from: date)
            rest = rest[close.upperBound...]
        }
        return result + rest
    }

    /// The kind, pattern and optional time zone inside one "{{name:pattern"
    /// or "{{name-tz(identifier):pattern" chunk, nil when the tag is not a
    /// date variable, malformed, or the pattern is empty (all stay visible,
    /// like any unknown tag).
    private static func formattedPattern(in tag: Substring) -> (kind: String, pattern: String, timeZoneIdentifier: String?)? {
        for kind in formattedDateKinds {
            let tzPrefix = "{{\(kind)-tz("
            if tag.hasPrefix(tzPrefix) {
                let afterPrefix = tag.dropFirst(tzPrefix.count)
                guard let closeParen = afterPrefix.firstIndex(of: ")") else { return nil }
                let identifier = String(afterPrefix[..<closeParen])
                let afterIdentifier = afterPrefix[afterPrefix.index(after: closeParen)...]
                guard afterIdentifier.hasPrefix(":") else { return nil }
                let pattern = String(afterIdentifier.dropFirst())
                // An identifier this Mac cannot resolve leaves the tag
                // literal rather than quietly formatting in the device's
                // own zone: a plausible-looking wrong time is worse than a
                // tag the user can see is wrong, and the captions now
                // invite typing these by hand.
                guard !pattern.isEmpty, TimeZone(identifier: identifier) != nil else { return nil }
                return (kind, pattern, identifier)
            }
            let plainPrefix = "{{\(kind):"
            if tag.hasPrefix(plainPrefix) {
                let pattern = String(tag.dropFirst(plainPrefix.count))
                return pattern.isEmpty ? nil : (kind, pattern, nil)
            }
        }
        return nil
    }

    // MARK: - Date variable builder

    /// The three shapes a date/time snippet variable can take.
    enum DateVariableKind: String, CaseIterable {
        case date, time, datetime
    }

    /// How a date/time variable's pattern gets chosen: one of the system's
    /// built-in styles, the fixed ISO 8601 shape, or a hand-typed pattern.
    enum DateVariableStyle: String, CaseIterable {
        case short, medium, long, full, iso8601, custom

        /// The styles that resolve through the current locale, so the
        /// pattern saved in the token is the one that locale used at the
        /// time. iso8601 and custom are fixed patterns and carry no such
        /// dependency.
        static let localeDependent: Set<DateVariableStyle> = [.short, .medium, .long, .full]
    }

    private static let isoPatterns: [DateVariableKind: String] = [
        .date: "yyyy-MM-dd",
        .time: "HH:mm:ssXXX",
        .datetime: "yyyy-MM-dd'T'HH:mm:ssXXX"
    ]

    private static func systemStyle(_ style: DateVariableStyle) -> DateFormatter.Style {
        switch style {
        case .short: return .short
        case .medium: return .medium
        case .long: return .long
        case .full: return .full
        case .iso8601, .custom: return .none
        }
    }

    /// The ICU pattern a builder selection resolves to: the raw text for
    /// Custom, a fixed shape for ISO 8601, or whatever DateFormatter reports
    /// for a system style at this locale.
    static func resolvedDatePattern(kind: DateVariableKind,
                                    style: DateVariableStyle,
                                    customPattern: String,
                                    locale: Locale) -> String {
        switch style {
        case .custom:
            return customPattern
        case .iso8601:
            return isoPatterns[kind] ?? ""
        case .short, .medium, .long, .full:
            let formatter = DateFormatter()
            formatter.locale = locale
            let dateStyle = systemStyle(style)
            switch kind {
            case .date:
                formatter.dateStyle = dateStyle
                formatter.timeStyle = .none
            case .time:
                formatter.dateStyle = .none
                formatter.timeStyle = dateStyle
            case .datetime:
                formatter.dateStyle = dateStyle
                formatter.timeStyle = dateStyle
            }
            return formatter.dateFormat
        }
    }

    /// The literal "{{kind:pattern}}" (or "{{kind-tz(id):pattern}}") text a
    /// builder selection inserts into a snippet's replacement.
    static func dateVariableText(kind: DateVariableKind,
                                 style: DateVariableStyle,
                                 customPattern: String,
                                 timeZoneIdentifier: String?,
                                 locale: Locale) -> String {
        let pattern = resolvedDatePattern(kind: kind, style: style,
                                          customPattern: customPattern, locale: locale)
        let tzPart = timeZoneIdentifier.map { "-tz(\($0))" } ?? ""
        return "{{\(kind.rawValue)\(tzPart):\(pattern)}}"
    }

    /// What a builder selection would format the given date as, using the
    /// same formatter configuration expandingFormattedDates uses, so the
    /// preview always matches what expansion actually produces.
    static func dateVariablePreview(kind: DateVariableKind,
                                    style: DateVariableStyle,
                                    customPattern: String,
                                    timeZoneIdentifier: String?,
                                    date: Date,
                                    locale: Locale) -> String {
        let pattern = resolvedDatePattern(kind: kind, style: style,
                                          customPattern: customPattern, locale: locale)
        guard !pattern.isEmpty else { return "" }
        let formatter = configuredFormatter(pattern: pattern,
                                            timeZoneIdentifier: timeZoneIdentifier,
                                            locale: locale)
        return formatter.string(from: date)
    }

    /// Reconstructs which Style an already-built pattern came from, by
    /// comparing it against what each style would resolve to right now.
    /// Falls back to Custom when nothing matches (e.g. a hand-typed
    /// pattern, or a system style whose OS-resolved text has since
    /// changed).
    static func matchingDateStyle(pattern: String,
                                  kind: DateVariableKind,
                                  locale: Locale) -> DateVariableStyle {
        let candidates: [DateVariableStyle] = [.iso8601, .short, .medium, .long, .full]
        for candidate in candidates {
            if resolvedDatePattern(kind: kind, style: candidate,
                                   customPattern: "", locale: locale) == pattern {
                return candidate
            }
        }
        return .custom
    }

    /// Lowercased with underscores folded to spaces, so "New_York" and
    /// "new york" compare equal: identifiers spell city names with
    /// underscores, but nobody types a timezone query that way.
    private static func normalizedTimeZoneText(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "_", with: " ")
    }

    /// How well an identifier answers a query, lowest first, so that a
    /// zone whose city the user actually typed leads the list instead of
    /// whichever zone merely contains those letters earliest in the
    /// alphabet.
    private static func timeZoneMatchRank(_ identifier: String, query: String) -> Int {
        let normalized = normalizedTimeZoneText(identifier)
        if normalized == query { return 0 }
        // The city is what people type; it is the part after the region.
        let city = normalized.split(separator: "/").last.map(String.init) ?? normalized
        if city == query { return 1 }
        if city.hasPrefix(query) { return 2 }
        if normalized.hasPrefix(query) { return 3 }
        return 4
    }

    /// Every timezone identifier whose name or common abbreviation
    /// contains the query, case- and separator-insensitive, best matches
    /// first. Uncapped: the picker scrolls, and any cap drops the very
    /// identifier a broad query is looking for.
    static func matchingTimeZoneIdentifiers(for query: String) -> [String] {
        guard !query.isEmpty else { return [] }
        let normalizedQuery = normalizedTimeZoneText(query)
        var seen = Set<String>()
        var matches: [String] = []
        for identifier in TimeZone.knownTimeZoneIdentifiers
        where normalizedTimeZoneText(identifier).contains(normalizedQuery) {
            if seen.insert(identifier).inserted { matches.append(identifier) }
        }
        for (abbreviation, identifier) in TimeZone.abbreviationDictionary
        where normalizedTimeZoneText(abbreviation).contains(normalizedQuery) {
            if seen.insert(identifier).inserted { matches.append(identifier) }
        }
        return matches.sorted {
            let left = timeZoneMatchRank($0, query: normalizedQuery)
            let right = timeZoneMatchRank($1, query: normalizedQuery)
            return left == right ? $0 < $1 : left < right
        }
    }

    /// The single timezone identifier the query unambiguously names, if
    /// any: an exact match on a full identifier or a common abbreviation
    /// (e.g. "PST"), or the one candidate left when the substring search
    /// in matchingTimeZoneIdentifiers(for:) narrows to exactly one result
    /// (e.g. "new york" narrows to only "America/New_York", so it counts
    /// as confirmed even though it isn't a literal identifier spelling).
    /// Never a raw UTC offset: several cities can share one offset, and
    /// daylight saving makes the mapping depend on the date, so an offset
    /// alone doesn't name one timezone.
    /// Pass `matches` when the caller already has the list for this same
    /// query (the picker renders it), so the search is not repeated.
    static func resolvedTimeZoneIdentifier(for query: String,
                                           matches: [String]? = nil) -> String? {
        guard !query.isEmpty else { return nil }
        let normalizedQuery = normalizedTimeZoneText(query)
        if let identifier = TimeZone.knownTimeZoneIdentifiers.first(where: {
            normalizedTimeZoneText($0) == normalizedQuery
        }) {
            return identifier
        }
        if let abbreviation = TimeZone.abbreviationDictionary.first(where: {
            normalizedTimeZoneText($0.key) == normalizedQuery
        }) {
            return abbreviation.value
        }
        let candidates = matches ?? matchingTimeZoneIdentifiers(for: query)
        return candidates.count == 1 ? candidates.first : nil
    }

    struct DetectedDateToken: Equatable {
        /// Character offsets, not String.Index: the editor holds this
        /// across the popover's lifetime and uses it to splice the text
        /// afterwards, and an index is only valid against the exact string
        /// it was computed from.
        let offsets: Range<Int>
        let kind: DateVariableKind
        let pattern: String
        let timeZoneIdentifier: String?
    }

    /// Turns the editor's tracked selection offsets into a range of `text`,
    /// clamping them to it. The offsets are recorded against whatever the
    /// text was when the selection last moved, so an edit that shortened
    /// the text since then leaves them pointing past the end; nil means
    /// nothing is tracked yet and the caret belongs at the end.
    static func selectionRange(in text: String, offsets: Range<Int>?) -> Range<String.Index> {
        let count = text.count
        let lower = min(max(offsets?.lowerBound ?? count, 0), count)
        let upper = min(max(offsets?.upperBound ?? count, lower), count)
        return text.index(text.startIndex, offsetBy: lower)
            ..< text.index(text.startIndex, offsetBy: upper)
    }

    /// The recognized date/time tag containing `index`, if any: used by the
    /// snippet editor to tell whether the cursor sits inside an existing
    /// token (so the builder edits it) or not (so it inserts a new one).
    /// Mirrors expandingFormattedDates's own traversal (skip past a bare
    /// "{{" on any mismatch, rather than jumping to an unrelated "}}"), so
    /// an earlier malformed or unrecognized tag never swallows a later
    /// well-formed one.
    static func dateToken(in text: String, at index: String.Index) -> DetectedDateToken? {
        var rest = Substring(text)
        while let start = rest.range(of: "{{") {
            let tail = rest[start.lowerBound...]
            guard let close = tail.range(of: "}}"),
                  let match = formattedPattern(in: tail[..<close.lowerBound]),
                  let kind = DateVariableKind(rawValue: match.kind) else {
                rest = rest[start.upperBound...]
                continue
            }
            let tagEnd = close.upperBound
            if index > start.lowerBound, index < tagEnd {
                return DetectedDateToken(
                    offsets: text.distance(from: text.startIndex, to: start.lowerBound)
                        ..< text.distance(from: text.startIndex, to: tagEnd),
                    kind: kind,
                    pattern: match.pattern,
                    timeZoneIdentifier: match.timeZoneIdentifier)
            }
            rest = rest[tagEnd...]
        }
        return nil
    }

    // MARK: - Library

    /// One folder worth of library rows. An empty name is the loose group,
    /// rendered without a header.
    struct LibrarySection: Equatable {
        let folder: String
        let snippets: [TextSnippet]
    }

    /// The library's content for a search text: enabled snippets marked to
    /// show, matched against name, trigger, text and folder (case and
    /// diacritic insensitive), grouped by folder. Folders come first in
    /// alphabetical order; snippets without one close the list, both keeping
    /// the stored order inside. An empty search shows everything.
    static func librarySections(_ snippets: [TextSnippet], query: String) -> [LibrarySection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = snippets.filter { snippet in
            guard snippet.enabled, snippet.showsInLibrary else { return false }
            guard !trimmed.isEmpty else { return true }
            return snippet.name.localizedStandardContains(trimmed)
                || snippet.trigger.localizedStandardContains(trimmed)
                || snippet.replacement.localizedStandardContains(trimmed)
                || snippet.folder.localizedStandardContains(trimmed)
        }
        var byFolder: [String: [TextSnippet]] = [:]
        for snippet in visible {
            byFolder[snippet.folder, default: []].append(snippet)
        }
        var sections = byFolder
            .filter { !$0.key.isEmpty }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { LibrarySection(folder: $0.key, snippets: $0.value) }
        if let loose = byFolder[""], !loose.isEmpty {
            sections.append(LibrarySection(folder: "", snippets: loose))
        }
        return sections
    }

    /// The same content as one flat list, in reading order, for the keyboard
    /// selection to walk.
    static func libraryRows(_ sections: [LibrarySection]) -> [TextSnippet] {
        sections.flatMap(\.snippets)
    }

    /// Existing folder names for the editor's suggestions, distinct and
    /// alphabetical.
    static func folderSuggestions(_ snippets: [TextSnippet]) -> [String] {
        Set(snippets.map(\.folder).filter { !$0.isEmpty })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Folder names travel inside each snippet; a rename is a plain rewrite
    /// of every member. Whitespace-only names mean no folder.
    static func sanitizedFolder(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Persistence

    static func decode(_ data: Data?) -> [TextSnippet] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([TextSnippet].self, from: data)) ?? []
    }

    static func encode(_ snippets: [TextSnippet]) -> Data? {
        try? JSONEncoder().encode(snippets)
    }
}
