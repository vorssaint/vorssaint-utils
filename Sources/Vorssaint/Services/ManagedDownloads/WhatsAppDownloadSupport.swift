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

    static func isWhatsAppAgent(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("WhatsApp") == .orderedSame
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
}
