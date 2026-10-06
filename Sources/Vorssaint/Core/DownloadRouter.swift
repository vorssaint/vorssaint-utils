// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A received file the organizer has been handed but not yet acted on: where
/// it is, which app macOS attributed the download to, and where the chosen
/// layout would put it.
struct DownloadCandidate: Equatable {
    let url: URL
    let agent: String?
    let destination: URL
}

/// Decides which received files the organizer may move, and where to. Nothing
/// here reads or writes: the answer is a function of the candidate and the
/// stored preferences alone, so the destructive decision can be tested
/// without a real Downloads folder.
enum DownloadRouter {
    /// The folder a candidate should be moved into, or nil when it must be
    /// left exactly where it is.
    static func destination(for candidate: DownloadCandidate,
                            configured: [String],
                            extensionWhitelist: Set<String>?) -> URL? {
        guard matchesAgent(candidate.agent, configured: configured) else { return nil }
        if let extensionWhitelist {
            guard extensionWhitelist.contains(
                candidate.url.pathExtension.lowercased()) else { return nil }
        }
        let destination = candidate.destination.standardizedFileURL
        // Routing a file into the folder it already sits in is not a route.
        // Allowing it would report a move that never happened and burn an
        // undo transaction on a no-op.
        guard destination.path
            != candidate.url.deletingLastPathComponent().standardizedFileURL.path else {
            return nil
        }
        return destination
    }

    /// Whether the app macOS attributed a download to is one the person chose
    /// to route.
    ///
    /// An empty `configured` list matches nothing, and that refusal is the
    /// load-bearing part of this function: "no source configured" has to mean
    /// "nothing moves", never "everything moves". A list that defaulted to
    /// matching all would make a cleared preference look like an instruction
    /// to tidy the whole Downloads folder.
    ///
    /// Quarantine agent names arrive padded and inconsistently cased, so both
    /// sides are trimmed and compared without case before anything is trusted.
    static func matchesAgent(_ value: String?, configured: [String]) -> Bool {
        guard let value else { return false }
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return false }
        return configured.contains { entry in
            entry.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(candidate) == .orderedSame
        }
    }

    /// Splits the stored comma-joined source list. Order is first-seen order
    /// because it is the order the person typed, and a repeated entry differing
    /// only in case is one source, not two.
    static func decodedSources(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        var seen = Set<String>()
        var sources: [String] = []
        for piece in raw.split(separator: ",", omittingEmptySubsequences: false) {
            let source = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { continue }
            guard seen.insert(source.lowercased()).inserted else { continue }
            sources.append(source)
        }
        return sources
    }

    /// Decodes the extension filter, where nil means "no extension rule".
    ///
    /// A string that holds nothing but separators decodes to nil as well: a
    /// whitelist of zero extensions would reject every file, turning a blank
    /// preference into a silently dead feature instead of an absent one.
    static func decodedExtensionWhitelist(_ raw: String?) -> Set<String>? {
        guard let raw, !raw.isEmpty else { return nil }
        let extensions = decodedSources(raw).map { $0.lowercased() }
        guard !extensions.isEmpty else { return nil }
        return Set(extensions)
    }
}