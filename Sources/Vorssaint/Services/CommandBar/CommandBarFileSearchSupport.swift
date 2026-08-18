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

    /// How many rows survive to be ranked. Past this the ranking is deciding
    /// between files nobody will scroll to.
    static let resultLimit = 200

    // MARK: - What is asked of Spotlight

    /// The query in Spotlight's own language, or nil when there is nothing
    /// worth asking. Every word has to appear in the file's name, in any
    /// order, which is what makes "annual report" find "Report annual.pdf".
    static func expression(for query: String) -> String? {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty,
              query.trimmingCharacters(in: .whitespaces).count >= shortestQuery
        else { return nil }
        let clauses = words.map { "kMDItemFSName == \"*\(escaped($0))*\"cd" }
        return clauses.joined(separator: " && ")
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
