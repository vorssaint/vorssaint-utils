// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A place the person goes to often, saved by them and answering to a name of
/// their choosing: a site, a folder, a file, or a search that takes what they
/// type after the name.
///
/// This is the one thing a launcher cannot ship with, because it is different
/// for every person. Everything else the bar offers is discovered; this is
/// declared.
struct CommandBarLink: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        /// Anything with a scheme: a site, or a link another app answers to.
        case link
        /// A folder or a file on this Mac.
        case place
        /// A local executable, run with whatever follows the name as its one
        /// argument.
        case script

        var symbolName: String {
            switch self {
            case .link: return "link"
            case .place: return "folder"
            case .script: return "terminal"
            }
        }
    }

    var id = UUID()
    var name = ""
    var kind = Kind.link
    /// The destination, with placeholders still in it.
    var destination = ""
    /// Whether the bare name is enough to run a script, with nothing after it.
    ///
    /// Off unless the person says otherwise, because a script is run when
    /// typing pauses rather than when Return is pressed: a script that expects
    /// input would fire on nothing the moment its name finished being typed.
    /// Only the person who saved it knows whether it has anything to do with
    /// no input at all.
    var runsWithoutArgument = false

    /// True when the destination waits for whatever is typed after the name,
    /// which is what turns a link into a search.
    var takesQuery: Bool {
        destination.contains(CommandBarLinkPlaceholder.query.token)
    }

    /// True for anything that reads whatever follows its name: every query
    /// link, and every script, which always takes its argument implicitly
    /// rather than through a destination placeholder.
    var takesArgument: Bool {
        kind == .script || takesQuery
    }
}

extension CommandBarLink {
    /// Decoded a field at a time, so a shortcut saved before a field existed
    /// still loads. The list is decoded in one call, so a single missing key
    /// would otherwise throw and take every saved shortcut down with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .link
        destination = try container.decodeIfPresent(String.self, forKey: .destination) ?? ""
        runsWithoutArgument = try container.decodeIfPresent(Bool.self,
                                                            forKey: .runsWithoutArgument) ?? false
    }
}

/// The words a destination can carry that are filled in when it opens. They
/// are written the same way in every language: a stored destination has to
/// keep working when the person changes the interface language.
enum CommandBarLinkPlaceholder: String, CaseIterable, Identifiable {
    case query
    case clipboard
    case selection
    case date

    var id: String { rawValue }
    var token: String { "{\(rawValue)}" }
}

/// Reading, writing and filling in what the person saved. Pure, so every rule
/// here is pinned by tests.
enum CommandBarLinks {
    /// Enough for a person, few enough that the list stays a list.
    static let limit = 60

    static func decode(_ data: Data?) -> [CommandBarLink] {
        guard let data, let links = try? JSONDecoder().decode([CommandBarLink].self, from: data)
        else { return [] }
        return links.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !$0.destination.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func encode(_ links: [CommandBarLink]) -> Data? {
        try? JSONEncoder().encode(Array(links.prefix(limit)))
    }

    /// The destination with every placeholder filled in. A value going into a
    /// web address is escaped; one going into a path is not, because a path is
    /// not a URL and escaping it would break the folder name.
    static func expand(_ destination: String,
                       kind: CommandBarLink.Kind,
                       query: String = "",
                       clipboard: String = "",
                       selection: String = "",
                       date: String = "") -> String {
        var result = destination
        let values: [CommandBarLinkPlaceholder: String] = [
            .query: query, .clipboard: clipboard, .selection: selection, .date: date,
        ]
        for placeholder in CommandBarLinkPlaceholder.allCases {
            guard result.contains(placeholder.token) else { continue }
            let raw = values[placeholder] ?? ""
            let value = kind == .link ? escaped(raw) : raw
            result = result.replacingOccurrences(of: placeholder.token, with: value)
        }
        return result
    }

    /// Where a saved place sits on the disk, for the rows that can be shown
    /// in Finder. Only a destination that is already a finished path
    /// qualifies: one still holding a placeholder is a different folder every
    /// time it runs, and there is nothing to reveal until it does.
    static func revealPath(for link: CommandBarLink) -> String? {
        guard link.kind == .place else { return nil }
        let trimmed = link.destination.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !CommandBarLinkPlaceholder.allCases.contains(where: { trimmed.contains($0.token) })
        else { return nil }
        return (trimmed as NSString).expandingTildeInPath
    }

    /// What a value has to look like inside a web address. Everything that is
    /// not unreserved is escaped, including the "+" and "&" that would
    /// otherwise change the meaning of a search.
    static func escaped(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// What the person typed after the name of a link, which is what a search
    /// link opens with. Nil when the query does not name this link at all.
    ///
    /// The name is matched whole and case-insensitively, so "gh vorssaint"
    /// finds the link called "gh" and "ghost" does not.
    static func trailingArgument(query: String, name: String) -> String? {
        let normalizedName = CommandBarSearch.normalized(name)
        guard !normalizedName.isEmpty else { return nil }
        let normalizedQuery = CommandBarSearch.normalized(query)
        guard normalizedQuery.hasPrefix(normalizedName + " ") else { return nil }
        // The remainder comes from the ORIGINAL text: what someone searches for
        // keeps its capitals and its accents. Splitting on any whitespace — not
        // just the ASCII space — keeps a full-width space (U+3000), which some
        // input methods produce, in step with the width-insensitive prefix check
        // above.
        let words = query.split(whereSeparator: \.isWhitespace)
        let nameWords = normalizedName.split(separator: " ").count
        guard words.count > nameWords else { return nil }
        return words.dropFirst(nameWords).joined(separator: " ")
    }

    /// What a link's row is scored against. Its own name works until the
    /// person types something after it — from there the row has to be scored
    /// against everything typed, or the extra words sink it out of the list.
    ///
    /// Only for a row that does something with those words: a link that opens
    /// the same place no matter what follows its name keeps answering to the
    /// name, so it never leads a list it has no answer for.
    static func rankingTitle(name: String, query: String) -> String {
        trailingArgument(query: query, name: name) != nil ? query : name
    }

    /// What a script would run with for this query, or nil when the query does
    /// not name it. Ordinarily that is whatever follows the name; a script that
    /// was marked as needing nothing also answers to its bare name, and runs
    /// with an empty argument.
    ///
    /// The bare name has to match the whole query. A script cannot run off a
    /// prefix of its name, or it would fire while the name is still being
    /// typed towards a longer one.
    static func scriptArgument(for link: CommandBarLink, query: String) -> String? {
        if let trailing = trailingArgument(query: query, name: link.name) { return trailing }
        guard link.runsWithoutArgument else { return nil }
        let normalizedName = CommandBarSearch.normalized(link.name)
        guard !normalizedName.isEmpty,
              CommandBarSearch.normalized(query) == normalizedName else { return nil }
        return ""
    }

    /// Every script the query names. The answer row stands in for all of them,
    /// so these are the rows the list drops once it has one.
    ///
    /// One question, asked in one place: the row that is removed has to be
    /// decided by exactly the rule that decided the script would run, or a
    /// query that runs a script leaves that script's own row in the list
    /// beside the answer.
    static func matchingScriptLinks(in links: [CommandBarLink],
                                    query: String) -> [CommandBarLink] {
        links.filter { $0.kind == .script && scriptArgument(for: $0, query: query) != nil }
    }

    /// The most specific script-kind link the query names, with what it would
    /// run with, or nil when nothing matches. A longer name wins over one that
    /// is only its prefix.
    static func matchingScriptLink(in links: [CommandBarLink],
                                   query: String) -> (link: CommandBarLink, argument: String)? {
        var best: (link: CommandBarLink, argument: String, nameLength: Int)?
        for link in matchingScriptLinks(in: links, query: query) {
            guard let argument = scriptArgument(for: link, query: query) else { continue }
            let nameLength = CommandBarSearch.normalized(link.name).count
            if let best, nameLength <= best.nameLength { continue }
            best = (link, argument, nameLength)
        }
        return best.map { ($0.link, $0.argument) }
    }

    /// What a script printed, reduced to what the answer row shows: no
    /// wrapping whitespace, and empty output means nothing is ready yet.
    static func resultText(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The URL a link opens, or nil when what was saved cannot be opened. A
    /// destination without a scheme is treated as a site, which is what people
    /// mean when they paste one in.
    static func url(for link: CommandBarLink, expanded: String) -> URL? {
        let trimmed = expanded.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        switch link.kind {
        case .place:
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        case .link:
            if let url = URL(string: trimmed), url.scheme != nil { return url }
            return URL(string: "https://" + trimmed)
        case .script:
            // A script runs; it does not open anything.
            return nil
        }
    }

    /// A web address typed on its own, or nil when the text should remain a
    /// search. The system detector keeps ordinary filenames, numbers and email
    /// addresses out; parsing the result again rejects incomplete URLs.
    static func typedURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let linkDetector else { return nil }
        let wholeValue = NSRange(location: 0, length: trimmed.utf16.count)
        guard let match = linkDetector.firstMatch(in: trimmed, options: [], range: wholeValue),
              match.range == wholeValue,
              let detectedScheme = match.url?.scheme?.lowercased(),
              detectedScheme == "http" || detectedScheme == "https"
        else { return nil }

        let url: URL?
        if let explicit = URL(string: trimmed),
           let scheme = explicit.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            url = explicit
        } else {
            url = URL(string: "https://" + trimmed)
        }
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else { return nil }
        return url
    }

    private static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue)
}
