// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One screenshot a pass may file away, reduced to what the archive decision
/// needs: where it is, when it was last touched, and when it entered the
/// folder it now sits in.
struct ScreenshotCandidate: Equatable {
    let url: URL
    let touched: Date
    let added: Date?
}

/// Where a capture goes when the pass files it away, and the instant that
/// separates "been sitting here untouched" from "just arrived".
struct ScreenshotArchivePlan: Equatable {
    let folder: URL
    let destination: URL
    let boundary: Date
}

/// Decides which screenshots a scheduled pass may file away into an `Archive`
/// folder, and where. Nothing here reads or writes: the answer is a function of
/// the stored preferences and two dates, so the unattended move can be tested
/// without a real screenshot folder.
enum ScreenshotArchiveSupport {
    /// The single subfolder captures are filed into, never configurable: a
    /// name chosen here would need a string for it in every language.
    static let archiveFolderName = "Archive"

    /// Deliberately NOT `CleanerPolicy.screenshotAgeChoices`
    /// (`[7, 14, 30, 60, 90]`). That list ages screenshots out for DELETION
    /// and this one ages them out for FILING AWAY, so a year is a meaningful
    /// choice here and a dangerous one there. Two policies, two vocabularies:
    /// one shared list would silently couple them, and widening the cleaner's
    /// range would one day offer to delete a screenshot a person kept for a
    /// year.
    static let archiveAfterChoices = [7, 14, 30, 90, 365]

    static let archiveAfterKey = DefaultsKey.screenshotArchiveAfterDays

    /// Clamps a stored day count into something that can be reasoned about.
    /// Zero, and every negative value, mean the policy is off - the same
    /// idiom `DefaultsKey.cleanerScreenshotAgeDays` already uses.
    static func sanitizedArchiveAfterDays(_ raw: Int) -> Int {
        raw <= 0 ? 0 : min(raw, 3650)
    }

    /// The instant before which a capture counts as forgotten, or nil when the
    /// policy is off. Nil for "off" is what makes "nothing configured,
    /// nothing moves" one early return: a boundary of `now` instead would
    /// archive every screenshot in the folder on the first pass.
    static func archiveBoundary(now: Date, afterDays: Int,
                                calendar: Calendar = .current) -> Date? {
        let days = sanitizedArchiveAfterDays(afterDays)
        guard days > 0 else { return nil }
        return calendar.date(byAdding: .day, value: -days, to: now)
    }

    /// The whole plan in one value, or nil when the policy may not run.
    ///
    /// Both refusals are load-bearing and neither touches the file system:
    /// proving the folder exists is the caller's job, because a pure function
    /// that asked the disk would answer differently depending on when it was
    /// asked.
    static func archivePlan(folder: String?, afterDays: Int, now: Date,
                            calendar: Calendar = .current) -> ScreenshotArchivePlan? {
        guard let boundary = archiveBoundary(now: now, afterDays: afterDays,
                                             calendar: calendar) else { return nil }
        let raw = folder?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // No chosen folder is not a failure, it is the feature being off. This
        // is the guarantee that an installation which never picked a save
        // folder never has a screenshot moved out from under it.
        guard !raw.isEmpty else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath
        let folderURL = URL(fileURLWithPath: expanded, isDirectory: true)
            .standardizedFileURL
        return ScreenshotArchivePlan(
            folder: folderURL,
            destination: folderURL.appendingPathComponent(archiveFolderName,
                                                          isDirectory: true)
                .standardizedFileURL,
            boundary: boundary)
    }

    /// Whether one capture may be filed away. Both halves are load-bearing.
    ///
    /// `age <= boundary` is the rule the feature is named for: a screenshot
    /// nobody has touched in `archiveAfter` days.
    ///
    /// `added <= boundary` is what stops an oscillation. A move preserves the
    /// modification date, so a capture dragged into the folder a moment ago
    /// still carries an old `touched`; without this half it would be archived
    /// on the very next pass, land in `Archive/`, and the pass after that
    /// would find it old again - an unattended pass shuffling one file
    /// forever.
    ///
    /// A missing `added` refuses. Without a known entry date there is no way
    /// to tell a fresh arrival from a long-resident file, and this pass runs
    /// while nobody is watching, so refusing is the safe answer.
    static func shouldArchive(age: Date, added: Date?, boundary: Date) -> Bool {
        guard let added else { return false }
        return age <= boundary && added <= boundary
    }
}