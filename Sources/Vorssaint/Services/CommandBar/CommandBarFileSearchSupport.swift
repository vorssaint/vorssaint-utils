// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The rules behind finding a file from the bar: what is asked of Spotlight,
/// which folders are searched and what never comes back. Pure, so every rule
/// here is pinned by tests instead of being discovered against one Mac's disk.
///
/// Two of them are structural rather than preferences, and no setting can undo
/// them: a hidden path and the inside of a package are never offered. They are
/// what lets the whole feature work without asking for a single new permission,
/// because what is left is what the person can already see in Finder.
enum CommandBarFileSearchSupport {
    /// Names that are almost never what somebody meant, and that a search
    /// through a home folder otherwise fills up with. Shipped rather than
    /// stored, so a later version can change the list and reach the Macs that
    /// already ran this one.
    static let shippedIgnores = [
        "node_modules", ".git", "DerivedData", "Pods", ".build", "vendor",
    ]

    /// Below this a filename search says almost nothing and Spotlight is asked
    /// for the whole disk, so the bar simply does not ask.
    static let shortestQuery = 2

    /// How many names Spotlight is allowed to hand back before anything is
    /// filtered. A broad word like "a" would otherwise walk a hundred thousand
    /// results through a filter that drops nearly all of them.
    static let candidateLimit = 1000

    /// The same limit for a query written in the file syntax. A sort or a
    /// path word is applied to what Spotlight hands back, so it needs a wider
    /// net to find the biggest file, or the one in the right folder.
    static let focusedCandidateLimit = 5000

    /// How many rows survive to be ranked. Past this the ranking is deciding
    /// between files nobody will scroll to.
    static let resultLimit = 200

    // MARK: - What was typed

    /// The order files come back in. Name is the order the bar always used;
    /// size and modification date lead with the biggest and the newest, which
    /// is what somebody sorting by them is looking for.
    enum SortOrder: String, Equatable {
        case name, path, size, modified
    }

    /// When a file was last changed, in the few spans people actually ask for.
    enum ModifiedRange: String, Equatable {
        case today, yesterday, week, month, year
    }

    /// One bound on a file's size, in bytes.
    struct SizeBound: Equatable {
        let comparison: String
        let bytes: Int64
    }

    /// A typed query taken apart the way Everything reads one. Words become
    /// filename words unless they are one of a handful of `key:value` filters
    /// or hold a slash; anything that only looks like a filter, `foo:bar` or
    /// `size:huge`, stays a word, so no query is ever silently swallowed.
    struct FileQuery: Equatable {
        var nameWords: [String] = []
        var pathWords: [String] = []
        var extensions: [String] = []
        var contentTypes: [String] = []
        var sizeBounds: [SizeBound] = []
        var modified: ModifiedRange?
        var sort: SortOrder = .name
        var hasSort = false

        /// The person used the file syntax, so they asked for files and
        /// nothing else: the bar shows file rows on their own.
        var isFocused: Bool {
            !pathWords.isEmpty || !extensions.isEmpty || !contentTypes.isEmpty
                || !sizeBounds.isEmpty || modified != nil || hasSort
        }
    }

    /// What `kind:` understands, as the content type Spotlight files each
    /// kind under. A tree match, so `kind:image` takes PNG, HEIC and RAW alike.
    static let kinds: [String: String] = [
        "image": "public.image",
        "video": "public.movie",
        "audio": "public.audio",
        "pdf": "com.adobe.pdf",
        "folder": "public.folder",
        "text": "public.text",
        "archive": "public.archive",
        "app": "com.apple.application-bundle",
    ]

    static func parse(_ query: String) -> FileQuery {
        var result = FileQuery()
        for token in query.split(whereSeparator: \.isWhitespace).map(String.init) {
            if applyFilter(token, to: &result) { continue }
            // A slash on its own, as in `AC / DC`, can never be in a filename.
            if token.allSatisfy({ $0 == "/" }) { continue }
            if isPathWord(token) {
                result.pathWords.append(token)
                continue
            }
            result.nameWords.append(token)
        }
        return result
    }

    /// A word naming a folder ends in a slash: `Code/`, `~/Code/`,
    /// `app/Sources/`. Only a trailing slash counts, because a slash in the
    /// middle is how people write everything else the bar answers: `10/2`,
    /// `km/h`, `AC/DC`, `github.com/vorssaint`. A web address is never a
    /// folder, and a slash on its own says nothing about where a file lives.
    static func isPathWord(_ token: String) -> Bool {
        token.hasSuffix("/") && !token.contains("://") && token.contains(where: { $0 != "/" })
    }

    /// Whether the bar should show files and nothing else for this query: the
    /// file syntax was used and it still leaves Spotlight something to ask.
    /// `sort:size` or `Code/` alone asks nothing, so the ordinary list stays
    /// rather than an empty one.
    static func listsOnlyFiles(_ query: String) -> Bool {
        parse(query).isFocused && expression(for: query) != nil
    }

    /// Reads one `key:value` filter into the query, or leaves the query alone
    /// and answers false so the token is treated as an ordinary word.
    private static func applyFilter(_ token: String, to query: inout FileQuery) -> Bool {
        guard let colon = token.firstIndex(of: ":") else { return false }
        let key = token[..<colon].lowercased()
        let value = token[token.index(after: colon)...].lowercased()
        guard !value.isEmpty else { return false }
        switch key {
        case "ext":
            let extensions = value.split(whereSeparator: { $0 == ";" || $0 == "," })
                .map { $0.hasPrefix(".") ? String($0.dropFirst()) : String($0) }
            guard !extensions.isEmpty,
                  extensions.allSatisfy({ !$0.isEmpty && !$0.contains("/") })
            else { return false }
            query.extensions.append(contentsOf: extensions)
            return true
        case "kind":
            guard let type = kinds[value] else { return false }
            query.contentTypes.append(type)
            return true
        case "size":
            guard let bound = sizeBound(value) else { return false }
            query.sizeBounds.append(bound)
            return true
        case "modified":
            guard let range = ModifiedRange(rawValue: value) else { return false }
            query.modified = range
            return true
        case "sort":
            guard let order = SortOrder(rawValue: value == "date" ? "modified" : value)
            else { return false }
            query.sort = order
            query.hasSort = true
            return true
        default:
            return false
        }
    }

    /// `>10mb`, `<=500kb`, `>1.5g`. A comparison is required: a file of
    /// exactly ten megabytes is never what anybody meant. Units count in
    /// 1024s, as Finder's older readouts and Everything do.
    static func sizeBound(_ value: String) -> SizeBound? {
        var rest = Substring(value)
        var comparison = ""
        for candidate in [">=", "<=", ">", "<"] where rest.hasPrefix(candidate) {
            comparison = candidate
            rest = rest.dropFirst(candidate.count)
            break
        }
        guard !comparison.isEmpty else { return nil }
        let digits = rest.prefix { $0.isNumber || $0 == "." }
        let unit = rest.dropFirst(digits.count)
        let multipliers: [String: Double] = [
            "": 1, "b": 1,
            "k": 1024, "kb": 1024,
            "m": 1_048_576, "mb": 1_048_576,
            "g": 1_073_741_824, "gb": 1_073_741_824,
        ]
        guard let number = Double(digits), number >= 0,
              let multiplier = multipliers[String(unit)]
        else { return nil }
        // Whole bytes, rounded so the bound keeps the files it meant on
        // whole sizes: `>0.5` and `>=0.5` both start at one byte, `<0.5` and
        // `<=0.5` both mean an empty file.
        let exact = number * multiplier
        let bytes = comparison == ">" || comparison == "<=" ? exact.rounded(.down)
                                                             : exact.rounded(.up)
        guard bytes < Double(Int64.max) else { return nil }
        return SizeBound(comparison: comparison, bytes: Int64(bytes))
    }

    // MARK: - What is asked of Spotlight

    /// The query in Spotlight's own language, or nil when there is nothing
    /// worth asking. Every word has to appear in the file's name, in any
    /// order, which is what makes "annual report" find "Report annual.pdf".
    static func expression(for query: String) -> String? {
        guard query.trimmingCharacters(in: .whitespaces).count >= shortestQuery else { return nil }
        return expression(for: parse(query))
    }

    /// Path words are not part of it: Spotlight cannot match on a path, so
    /// they are checked against each answer afterwards. A query made only of
    /// them has nothing to ask and asks nothing.
    static func expression(for query: FileQuery) -> String? {
        // Each word is asked of the display name as well as the file name.
        // Spotlight's file-name index misses many Chinese and Japanese
        // substrings: a word such as 入门 ("getting started") can match no
        // file names at all, while the display names of the same files match.
        // The display name alone is not enough either, since it drops an
        // extension Finder hides.
        var clauses = query.nameWords.map { word -> String in
            let pattern = "\"*\(escaped(word))*\"cd"
            return "(kMDItemFSName == \(pattern) || kMDItemDisplayName == \(pattern))"
        }
        if !query.extensions.isEmpty {
            clauses.append(anyOf(query.extensions.map { "kMDItemFSName == \"*.\(escaped($0))\"c" }))
        }
        if !query.contentTypes.isEmpty {
            clauses.append(anyOf(query.contentTypes.map { "kMDItemContentTypeTree == \"\($0)\"" }))
        }
        clauses += query.sizeBounds.map { "kMDItemFSSize \($0.comparison) \($0.bytes)" }
        if let modified = query.modified {
            let date = "kMDItemFSContentChangeDate"
            switch modified {
            case .today: clauses.append("\(date) >= $time.today")
            case .yesterday:
                clauses.append("\(date) >= $time.today(-1) && \(date) < $time.today")
            case .week: clauses.append("\(date) >= $time.this_week")
            case .month: clauses.append("\(date) >= $time.this_month")
            case .year: clauses.append("\(date) >= $time.this_year")
            }
        }
        guard !clauses.isEmpty else { return nil }
        return clauses.joined(separator: " && ")
    }

    private static func anyOf(_ clauses: [String]) -> String {
        clauses.count == 1 ? clauses[0] : "(" + clauses.joined(separator: " || ") + ")"
    }

    /// What a word has to look like inside that expression. The wildcards are
    /// escaped along with the quotes: a person typing an asterisk means the
    /// character, and leaving it live would quietly widen their search.
    static func escaped(_ word: String) -> String {
        var result = ""
        for character in word {
            if character == "\\" || character == "\"" || character == "*" || character == "?" {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    // MARK: - Where it looks

    /// The folders a saved list actually means.
    ///
    /// Paths are stored abbreviated with a tilde so a list made on one Mac
    /// still points somewhere on another, and the home folder is expanded into
    /// the folders inside it: handing Spotlight the home itself would drag in
    /// `~/Library`, which is tens of thousands of files nobody was looking for
    /// and the one place a filename search turns into noise.
    ///
    /// An empty list searches nothing. That is the feature being off, and it
    /// is deliberate: falling back to the home folder would turn a list the
    /// person cleared into the broadest search the bar can make.
    static func resolvedScopes(_ saved: [String],
                               homeDirectory: String,
                               homeChildren: [String],
                               isSearchableDirectory: (String) -> Bool) -> [String] {
        let home = standardized(homeDirectory)
        var seen = Set<String>()
        var scopes: [String] = []
        for raw in saved {
            let path = standardized(expandingTilde(raw, home: home))
            guard !path.isEmpty else { continue }
            if path == home {
                for child in homeChildren where child != "Library" && !child.hasPrefix(".") {
                    let expanded = home + "/" + child
                    if isSearchableDirectory(expanded), seen.insert(expanded).inserted {
                        scopes.append(expanded)
                    }
                }
                continue
            }
            if isSearchableDirectory(path), seen.insert(path).inserted { scopes.append(path) }
        }
        return scopes
    }

    /// A tilde stands for the home folder handed in, never for whoever the
    /// process happens to be running as. The whole point of taking the home
    /// as an argument is that this file can be reasoned about without one.
    private static func expandingTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    private static func standardized(_ path: String) -> String {
        var result = (path as NSString).standardizingPath
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }

    // MARK: - What never comes back

    /// Whether a path can be offered at all, before any preference is read.
    /// Package status comes from filesystem metadata rather than a suffix
    /// list, so a package type this app has never seen is still sealed.
    static func isOfferable(path: String, isPackage: (String) -> Bool) -> Bool {
        let standardizedPath = standardized(path)
        let components = standardizedPath.split(separator: "/").map(String.init)
        guard let last = components.last, !last.hasPrefix(".") else { return false }
        var ancestor = ""
        for component in components.dropLast() {
            if component.hasPrefix(".") { return false }
            ancestor += "/" + component
            if isPackage(ancestor) { return false }
        }
        return true
    }

    /// Whether one of the names the person never wants to see stands in this
    /// path. A pattern matches a whole folder or file name, never half of one:
    /// "build" must not take out "rebuild-notes.md".
    static func isIgnored(path: String, patterns: [String]) -> Bool {
        guard !patterns.isEmpty else { return false }
        let components = path.split(separator: "/").map { $0.lowercased() }
        for pattern in patterns {
            let wanted = pattern.trimmingCharacters(in: .whitespaces).lowercased()
            guard !wanted.isEmpty else { continue }
            if components.contains(wanted) { return true }
            // A pattern written as an extension takes out the kind of file
            // rather than a folder: "*.log", or just ".log".
            if wanted.hasPrefix("*."), let name = components.last,
               name.hasSuffix(String(wanted.dropFirst())) {
                return true
            }
            if wanted.hasPrefix("."), !wanted.contains("/"), let name = components.last,
               name != wanted, name.hasSuffix(wanted) {
                return true
            }
        }
        return false
    }

    /// The paths worth showing, in the order they should be ranked in: the
    /// ones Spotlight found, minus what is structurally out and what the
    /// person asked never to see, capped so the list stays a list.
    static func offerable(paths: [String],
                          patterns: [String],
                          isPackage: (String) -> Bool) -> [String] {
        var packageCache: [String: Bool] = [:]
        func cachedIsPackage(_ path: String) -> Bool {
            if let cached = packageCache[path] { return cached }
            let value = isPackage(path)
            packageCache[path] = value
            return value
        }

        var seen = Set<String>()
        var result: [String] = []
        for path in paths {
            guard isOfferable(path: path, isPackage: cachedIsPackage),
                  !isIgnored(path: path, patterns: patterns) else { continue }
            guard seen.insert(path).inserted else { continue }
            result.append(path)
            if result.count >= resultLimit { break }
        }
        return result
    }

    // MARK: - In what order, and where

    /// One answer from Spotlight, with the two attributes a sort may need.
    /// They are only read when the sort asks for them.
    struct Candidate: Equatable {
        let path: String
        var size: Int64? = nil
        var modified: Date? = nil
    }

    /// Whether every path word appears somewhere in the path, ignoring case
    /// and accents. A word starting with a tilde is read against the short
    /// form, so `~/Code/` means the Code folder in this home and no other.
    static func matchesPathWords(path: String, words: [String], homeDirectory: String) -> Bool {
        guard !words.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let short = abbreviating(path, homeDirectory: homeDirectory)
        return words.allSatisfy { word in
            // A tilde is where the path starts, never a character inside it.
            if word.hasPrefix("~") {
                return short.range(of: word, options: options.union(.anchored)) != nil
            }
            return path.range(of: word, options: options) != nil
        }
    }

    /// Answers in the order asked for. The name comparison breaks every tie,
    /// then the path, so two Macs with the same files answer in the same order.
    static func sorted(_ candidates: [Candidate], by order: SortOrder) -> [String] {
        func byName(_ left: Candidate, _ right: Candidate) -> Bool {
            let leftName = (left.path as NSString).lastPathComponent
            let rightName = (right.path as NSString).lastPathComponent
            let result = leftName.localizedCaseInsensitiveCompare(rightName)
            return result == .orderedSame ? left.path < right.path : result == .orderedAscending
        }
        let ordered: [Candidate]
        switch order {
        case .name:
            ordered = candidates.sorted(by: byName)
        case .path:
            ordered = candidates.sorted {
                let result = $0.path.localizedCaseInsensitiveCompare($1.path)
                return result == .orderedSame ? $0.path < $1.path : result == .orderedAscending
            }
        case .size:
            ordered = candidates.sorted {
                let left = $0.size ?? -1, right = $1.size ?? -1
                return left == right ? byName($0, $1) : left > right
            }
        case .modified:
            ordered = candidates.sorted {
                let left = $0.modified ?? .distantPast, right = $1.modified ?? .distantPast
                return left == right ? byName($0, $1) : left > right
            }
        }
        return ordered.map(\.path)
    }

    // MARK: - What is stored

    /// One path or pattern per line, which is what makes the lists readable in
    /// a settings export and easy to paste into.
    static func decodeList(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func encodeList(_ items: [String]) -> String {
        decodeList(items.joined(separator: "\n")).joined(separator: "\n")
    }

    /// A path written the short way, for the row underneath a file's name and
    /// for the list in Settings.
    static func abbreviating(_ path: String, homeDirectory: String) -> String {
        let home = standardized(homeDirectory)
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// Only the latest query may refresh the visible bar. Older searches may
    /// finish and warm their cache, but their late completion stays invisible.
    static func shouldPublishResult(for query: String, currentQuery: String?) -> Bool {
        query == currentQuery
    }
}
