// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import UniformTypeIdentifiers

/// User-facing buckets for confirmed WhatsApp downloads. The raw values are
/// persisted, so cases may be appended but never renamed.
enum WhatsAppDownloadCategory: String, CaseIterable, Identifiable {
    case image, video, audio, document, archive, other

    var id: String { rawValue }
}

enum WhatsAppOrganizerLayout: String, CaseIterable, Identifiable {
    case flat, category, month

    var id: String { rawValue }
}

enum WhatsAppDuplicateAction: String, CaseIterable, Identifiable {
    case trashNew, keepBoth, replaceExisting

    var id: String { rawValue }
}

/// Pure classification and retention rules for the WhatsApp downloads
/// manager. Keeping every judgment here makes the destructive boundary easy
/// to test without touching a real Downloads folder.
enum WhatsAppDownloadSupport {
    static let allowedRetentionDays = [1, 2, 7, 14, 30]
    static let allowedOrganizerDelayMinutes = [1, 5, 15, 60]
    static let organizerUndoLifetime: TimeInterval = 7 * 86_400
    static let defaultCategories: Set<WhatsAppDownloadCategory> = [.image, .video, .audio]

    private static let incompleteExtensions: Set<String> = [
        "download", "part", "partial", "crdownload", "tmp",
    ]

    private static let archiveExtensions: Set<String> = [
        "7z", "bz", "bz2", "cab", "dmg", "gz", "iso", "rar", "tar", "tgz", "xz", "zip",
    ]

    private static let documentExtensions: Set<String> = [
        "csv", "doc", "docm", "docx", "epub", "key", "md", "numbers", "odp", "ods", "odt",
        "pages", "pdf", "ppt", "pptm", "pptx", "rtf", "tex", "txt", "xls", "xlsm", "xlsx",
    ]

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.whatsAppDownloadsEnabled)
    }

    static func sanitizedRetentionDays(_ value: Int) -> Int {
        allowedRetentionDays.contains(value) ? value : 7
    }

    static func sanitizedOrganizerDelayMinutes(_ value: Int) -> Int {
        allowedOrganizerDelayMinutes.contains(value) ? value : 5
    }

    static func encodedCategories(_ categories: Set<WhatsAppDownloadCategory>) -> String {
        WhatsAppDownloadCategory.allCases
            .filter(categories.contains)
            .map(\.rawValue)
            .joined(separator: ",")
    }

    static func decodedCategories(_ raw: String?) -> Set<WhatsAppDownloadCategory> {
        guard let raw else { return defaultCategories }
        let decoded = Set(raw.split(separator: ",").compactMap {
            WhatsAppDownloadCategory(rawValue: String($0))
        })
        return decoded
    }

    static func isIncompleteFile(extension rawExtension: String) -> Bool {
        incompleteExtensions.contains(rawExtension.lowercased())
    }

    static func isDirectChild(_ candidate: URL, of root: URL) -> Bool {
        candidate.standardizedFileURL.deletingLastPathComponent().path
            == root.standardizedFileURL.path
    }

    static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let candidateParts = candidate.standardizedFileURL.pathComponents
        let rootParts = root.standardizedFileURL.pathComponents
        return candidateParts.count > rootParts.count
            && candidateParts.prefix(rootParts.count).elementsEqual(rootParts)
    }

    static func isStableForOrganization(downloadedAt: Date,
                                        modifiedAt: Date,
                                        now: Date,
                                        delayMinutes: Int) -> Bool {
        let delay = TimeInterval(sanitizedOrganizerDelayMinutes(delayMinutes) * 60)
        return now.timeIntervalSince(max(downloadedAt, modifiedAt)) >= delay
    }

    static func organizerUndoIsValid(createdAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(createdAt)
        return age >= 0 && age < organizerUndoLifetime
    }

    /// Whether an organizer move stays on one volume, which is the only case
    /// where the move is a rename and the destination needs no re-hash.
    /// `volumeIdentifier` is opaque and only `isEqual` is defined on it, so
    /// that is what decides here. An unknown identity answers "not the same
    /// volume": guessing wrong that way only costs a verified copy, while the
    /// opposite guess would let a real cross-volume copy through unchecked.
    /// The inverse fallback in `CutPasteProgressSupport.isCrossVolume` is
    /// deliberate - there an unknown identity only hides a progress bar.
    static func isSameVolume(source: NSObject?, destination: NSObject?) -> Bool {
        guard let source, let destination else { return false }
        return source.isEqual(destination)
    }

    static func organizerCategoryFolder(_ category: WhatsAppDownloadCategory) -> String {
        switch category {
        case .image: return "Images"
        case .video: return "Videos"
        case .audio: return "Audio"
        case .document: return "Documents"
        case .archive: return "Archives"
        case .other: return "Other"
        }
    }

    static func organizerRelativeComponents(layout: WhatsAppOrganizerLayout,
                                            category: WhatsAppDownloadCategory,
                                            date: Date,
                                            calendar: Calendar = .current) -> [String] {
        switch layout {
        case .flat:
            return []
        case .category:
            return [organizerCategoryFolder(category)]
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let year = components.year, let month = components.month else { return [] }
            return [String(format: "%04d", year), String(format: "%02d", month)]
        }
    }

    static func category(contentTypeIdentifier: String?,
                         extension rawExtension: String) -> WhatsAppDownloadCategory {
        let ext = rawExtension.lowercased()
        if archiveExtensions.contains(ext) { return .archive }
        if documentExtensions.contains(ext) { return .document }

        if let identifier = contentTypeIdentifier,
           let type = UTType(identifier) {
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
            if type.conforms(to: .audio) { return .audio }
            if type.conforms(to: .archive) { return .archive }
            if type.conforms(to: .pdf) || type.conforms(to: .text) { return .document }
        }
        return .other
    }

    /// A file is old enough only when both its download/addition date and its
    /// latest edit are beyond the retention window. Editing a document in
    /// place therefore postpones cleanup instead of losing recent work.
    static func isOldEnough(downloadedAt: Date,
                            modifiedAt: Date,
                            now: Date,
                            retentionDays: Int,
                            calendar: Calendar = .current) -> Bool {
        let days = sanitizedRetentionDays(retentionDays)
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: now) else { return false }
        return downloadedAt <= cutoff && modifiedAt <= cutoff
    }

    static func isEligibleForRules(category: WhatsAppDownloadCategory,
                                   downloadedAt: Date,
                                   modifiedAt: Date,
                                   now: Date,
                                   retentionDays: Int,
                                   enabledCategories: Set<WhatsAppDownloadCategory>) -> Bool {
        enabledCategories.contains(category)
            && isOldEnough(downloadedAt: downloadedAt, modifiedAt: modifiedAt,
                           now: now, retentionDays: retentionDays)
    }

    static func isEligibleForAutomaticCleanup(category: WhatsAppDownloadCategory,
                                              downloadedAt: Date,
                                              modifiedAt: Date,
                                              now: Date,
                                              retentionDays: Int,
                                              enabledCategories: Set<WhatsAppDownloadCategory>,
                                              includeExisting: Bool,
                                              automaticStartDate: Date?) -> Bool {
        guard isEligibleForRules(category: category,
                                 downloadedAt: downloadedAt,
                                 modifiedAt: modifiedAt,
                                 now: now,
                                 retentionDays: retentionDays,
                                 enabledCategories: enabledCategories) else { return false }
        if includeExisting { return true }
        guard let automaticStartDate else { return false }
        return downloadedAt >= automaticStartDate
    }

    static func nextAutomaticCheck(after date: Date,
                                   calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        return calendar.nextDate(after: date, matching: components,
                                 matchingPolicy: .nextTime)
    }

    static func missedAutomaticCheck(now: Date,
                                     lastRun: Date?,
                                     calendar: Calendar = .current) -> Bool {
        guard let lastRun,
              let today = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now),
              now >= today else { return false }
        return lastRun < today
    }

    /// One file the organizer placed, with everything needed to tell whether
    /// the person has touched it since. The property names and their order
    /// are the persisted JSON keys, so cases may be appended but never
    /// renamed.
    struct Record: Codable, Equatable {
        let digest: String
        let destinationPath: String
        let originalName: String
        let size: Int64
        let organizedAt: Date
    }

    /// One reversible step of an organizer pass: a move that can be put
    /// back, or a trash that can be emptied from the trash.
    struct UndoTransaction: Codable {
        enum ActionKind: String, Codable { case move, trash }
        struct Action: Codable {
            let kind: ActionKind
            let currentPath: String
            let restorePath: String?
        }

        let id: UUID
        let actions: [Action]
        let recordsBefore: [Record]
        let recordsAfter: [Record]
        let createdAt: Date
    }

    /// The undo transaction is the most expensive correctness property in
    /// this subsystem, and it is expensive because undo destroys work:
    /// restoring a pass means overwriting whatever sits at the organized path
    /// today, so it is only safe while every file that pass wrote is provably
    /// still that file. The organizer owns the moving; the deciding does not.
    /// Keeping these rules pure and here is what lets the destructive
    /// boundary be exercised by tests that never touch a real Downloads
    /// folder.
    static func recordMap(_ records: [Record]) -> [String: Record] {
        Dictionary(records.map { ($0.destinationPath, $0) },
                   uniquingKeysWith: { _, latest in latest })
    }

    /// The paths whose record a transaction actually changed. Only a
    /// difference counts: a record the transaction wrote and then wrote back
    /// identically involved nothing and must not block the undo.
    static func affectedRecordPaths(_ transaction: UndoTransaction) -> Set<String> {
        let before = recordMap(transaction.recordsBefore)
        let after = recordMap(transaction.recordsAfter)
        return Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
    }

    /// Whether undo may proceed. A record that changed since the transaction
    /// was written means the person moved or replaced the file themselves,
    /// and restoring would destroy that; the whole transaction is refused
    /// rather than partly applied, because a half-undone pass leaves the
    /// records describing files that no longer exist.
    static func recordsAllowUndo(_ transaction: UndoTransaction,
                                 current: [Record]) -> Bool {
        let expected = recordMap(transaction.recordsAfter)
        let current = recordMap(current)
        return affectedRecordPaths(transaction).allSatisfy { current[$0] == expected[$0] }
    }

    static func recordsAfterUndo(_ transaction: UndoTransaction,
                                 current: [Record]) -> [Record] {
        let before = recordMap(transaction.recordsBefore)
        var result = recordMap(current)
        for path in affectedRecordPaths(transaction) {
            result[path] = before[path]
        }
        return result.values.sorted { $0.organizedAt < $1.organizedAt }
    }

    /// Finds the record that makes a freshly downloaded file a duplicate.
    /// Records that share the digest but whose file is gone or no longer has
    /// those bytes are dropped and the search continues, so a stale record
    /// cannot hide the real duplicate further down the list - and equally a
    /// record that merely claims the digest is not treated as a duplicate,
    /// because acting on one would trash a file the person still has.
    static func firstValidRecordIndex(digest: String,
                                      records: inout [Record],
                                      isIntact: (Record) -> Bool) -> Int? {
        var index = 0
        while index < records.count {
            guard records[index].digest == digest else {
                index += 1
                continue
            }
            guard isIntact(records[index]) else {
                records.remove(at: index)
                continue
            }
            return index
        }
        return nil
    }

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

    /// Splits a stored comma-joined list. Order is first-seen order because
    /// it is the order the person typed, and a repeated entry differing only
    /// in case is one entry, not two.
    static func splitList(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        var seen = Set<String>()
        var entries: [String] = []
        for piece in raw.split(separator: ",", omittingEmptySubsequences: false) {
            let entry = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.isEmpty else { continue }
            guard seen.insert(entry.lowercased()).inserted else { continue }
            entries.append(entry)
        }
        return entries
    }

    /// The source list the person chose to route.
    static func decodedSources(_ raw: String?) -> [String] {
        splitList(raw)
    }

    /// The apps the cleanup may touch.
    ///
    /// The cleanup is destructive, so its scope is fixed here rather than
    /// read from a preference the person sets for a different reason: the
    /// routing list says where a download is moved to, and letting it also
    /// say what may be trashed would widen a destructive policy with nobody
    /// asking for it.
    static let cleanupSources = ["WhatsApp"]

    /// Decodes the extension filter, where nil means "no extension rule".
    ///
    /// A string that holds nothing but separators decodes to nil as well: a
    /// whitelist of zero extensions would reject every file, turning a blank
    /// preference into a silently dead feature instead of an absent one.
    static func decodedExtensionWhitelist(_ raw: String?) -> Set<String>? {
        guard let raw, !raw.isEmpty else { return nil }
        let extensions = splitList(raw).map { $0.lowercased() }
        guard !extensions.isEmpty else { return nil }
        return Set(extensions)
    }
}

/// A received file the organizer has been handed but not yet acted on: where
/// it is, which app macOS attributed the download to, and where the chosen
/// layout would put it.
struct DownloadCandidate: Equatable {
    let url: URL
    let agent: String?
    let destination: URL
}
