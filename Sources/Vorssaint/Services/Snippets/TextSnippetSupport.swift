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
            && buffer.hasSuffix(snippet.trigger) {
            if let current = best, current.trigger.count >= snippet.trigger.count { continue }
            best = snippet
        }
        return best
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
        return replacement
            .replacingOccurrences(of: "{{date}}", with: dateText)
            .replacingOccurrences(of: "{{time}}", with: timeText)
            .replacingOccurrences(of: "{{datetime}}", with: "\(dateText) \(timeText)")
            .replacingOccurrences(of: "{{clipboard}}", with: clipboard ?? "")
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
