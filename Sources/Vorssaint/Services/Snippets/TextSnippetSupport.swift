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
    private static let formattedDatePrefixes = ["{{date:", "{{time:", "{{datetime:"]

    private static func expandingFormattedDates(_ text: String,
                                                date: Date,
                                                locale: Locale) -> String {
        guard formattedDatePrefixes.contains(where: text.contains) else { return text }
        let formatter = DateFormatter()
        formatter.locale = locale
        var result = ""
        var rest = Substring(text)
        while let start = rest.range(of: "{{") {
            result += rest[..<start.lowerBound]
            let tail = rest[start.lowerBound...]
            guard let close = tail.range(of: "}}"),
                  let pattern = formattedPattern(in: tail[..<close.lowerBound]) else {
                result += "{{"
                rest = rest[start.upperBound...]
                continue
            }
            formatter.dateFormat = pattern
            result += formatter.string(from: date)
            rest = rest[close.upperBound...]
        }
        return result + rest
    }

    /// The pattern inside one "{{name:pattern" chunk, nil when the tag is not
    /// a date variable or the pattern is empty (both stay visible, like any
    /// unknown tag).
    private static func formattedPattern(in tag: Substring) -> String? {
        for prefix in formattedDatePrefixes where tag.hasPrefix(prefix) {
            let pattern = String(tag.dropFirst(prefix.count))
            return pattern.isEmpty ? nil : pattern
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
