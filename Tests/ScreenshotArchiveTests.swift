// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The archive policy's decisions, exercised as pure values: what "off"
/// means, where a capture would be filed, and the two halves that stop a
/// scheduled pass from shuffling one file forever. Nothing here touches a real
/// screenshot folder - the point of the rules is that they can be checked
/// without one.
enum ScreenshotArchiveTests {
    private static let folder = "/Users/test/Screenshots"
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Fixed to UTC so a day-count assertion cannot drift across a daylight
    /// saving change on the machine running it.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    static func run(_ suite: TestSuite) {
        runSanitizing(suite)
        runBoundary(suite)
        runPlan(suite)
        runShouldArchive(suite)
        runDefaults(suite)
    }

    private static func runSanitizing(_ suite: TestSuite) {
        suite.expect(ScreenshotArchiveSupport.sanitizedArchiveAfterDays(0) == 0
                     && ScreenshotArchiveSupport.sanitizedArchiveAfterDays(-1) == 0
                     && ScreenshotArchiveSupport.sanitizedArchiveAfterDays(-365) == 0
                     && ScreenshotArchiveSupport.sanitizedArchiveAfterDays(
                        Int.min) == 0,
                     "zero and every negative day count are off, never a backwards window")
        suite.expect(ScreenshotArchiveSupport.sanitizedArchiveAfterDays(7) == 7
                     && ScreenshotArchiveSupport.sanitizedArchiveAfterDays(1) == 1
                     && ScreenshotArchiveSupport.sanitizedArchiveAfterDays(3650) == 3650,
                     "a positive day count is used exactly as chosen")
        suite.expect(ScreenshotArchiveSupport.sanitizedArchiveAfterDays(Int.max) == 3650
                     && ScreenshotArchiveSupport.sanitizedArchiveAfterDays(365_000) == 3650,
                     "an absurd day count clamps to ten years rather than to a date far past")
    }

    private static func runBoundary(_ suite: TestSuite) {
        suite.expect(ScreenshotArchiveSupport.archiveBoundary(now: now, afterDays: 0) == nil
                     && ScreenshotArchiveSupport.archiveBoundary(now: now, afterDays: -30) == nil,
                     "'off' has no boundary at all, never a boundary of now that archives everything")
        for days in [7, 14, 30, 90, 365] {
            let boundary = ScreenshotArchiveSupport.archiveBoundary(
                now: now, afterDays: days, calendar: calendar)
            let expected = calendar.date(byAdding: .day, value: -days, to: now)
            suite.expect(boundary != nil && expected != nil && boundary == expected,
                         "a \(days) day window ends exactly \(days) days before the pass")
        }
    }

    private static func runPlan(_ suite: TestSuite) {
        suite.expect(ScreenshotArchiveSupport.archivePlan(
                        folder: folder, afterDays: 0, now: now, calendar: calendar) == nil,
                     "with the policy off no plan exists, however good the folder looks")

        // The most important assertion in this file: with no screenshot folder
        // configured, nothing can be moved, for any number of days.
        for blank in ["", " ", "   ", "\t", "\n", " \t\n "] {
            suite.expect(ScreenshotArchiveSupport.archivePlan(
                            folder: blank, afterDays: 30, now: now, calendar: calendar) == nil,
                         "a blank screenshot folder means nothing moves, whatever the day count")
        }
        suite.expect(ScreenshotArchiveSupport.archivePlan(
                        folder: nil, afterDays: 30, now: now, calendar: calendar) == nil,
                     "an unset screenshot folder means nothing moves")

        let plan = ScreenshotArchiveSupport.archivePlan(
            folder: folder, afterDays: 30, now: now, calendar: calendar)
        let expectedFolder = URL(fileURLWithPath: folder, isDirectory: true)
            .standardizedFileURL
        suite.expect(plan?.folder == expectedFolder
                     && plan?.destination == expectedFolder.appendingPathComponent(
                        ScreenshotArchiveSupport.archiveFolderName, isDirectory: true)
                            .standardizedFileURL
                     && plan?.boundary == ScreenshotArchiveSupport.archiveBoundary(
                        now: now, afterDays: 30, calendar: calendar),
                     "a plan is the chosen folder, an Archive folder inside it, and the cutoff")

        let tilde = ScreenshotArchiveSupport.archivePlan(
            folder: "  ~/Pictures/Screenshots  ", afterDays: 14, now: now, calendar: calendar)
        let expanded = URL(
            fileURLWithPath: ("~/Pictures/Screenshots" as NSString).expandingTildeInPath,
            isDirectory: true).standardizedFileURL
        suite.expect(tilde?.folder == expanded
                     && tilde?.destination == expanded.appendingPathComponent(
                        ScreenshotArchiveSupport.archiveFolderName, isDirectory: true)
                            .standardizedFileURL,
                     "a saved folder keeps its leading tilde expanded and its padding ignored")

        // The plan is a decision, not a probe: existence is the caller's check,
        // and a pure function that asked the disk would answer differently
        // depending on when it was asked.
        suite.expect(ScreenshotArchiveSupport.archivePlan(
                        folder: "/Users/test/nowhere/at/all/Screenshots",
                        afterDays: 30, now: now, calendar: calendar) != nil,
                     "a plan is produced for a folder that does not exist; proving it is the caller's job")
    }

    private static func runShouldArchive(_ suite: TestSuite) {
        let boundary = ScreenshotArchiveSupport.archiveBoundary(
            now: now, afterDays: 30, calendar: calendar)
        guard let boundary else {
            suite.expect(false, "a positive day count always produces a boundary")
            return
        }
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: boundary) ?? boundary
        }

        suite.expect(ScreenshotArchiveSupport.shouldArchive(
                        age: daysAgo(30), added: daysAgo(45), boundary: boundary),
                     "a capture untouched and undisturbed for longer than the window is filed away")
        suite.expect(!ScreenshotArchiveSupport.shouldArchive(
                        age: daysAgo(30), added: boundary.addingTimeInterval(1),
                        boundary: boundary),
                     "a capture that just arrived is left alone even though it looks untouched")
        suite.expect(!ScreenshotArchiveSupport.shouldArchive(
                        age: now.addingTimeInterval(1), added: daysAgo(400),
                        boundary: boundary),
                     "a capture edited today is never filed away, however long it sat")
        suite.expect(!ScreenshotArchiveSupport.shouldArchive(
                        age: daysAgo(90), added: nil, boundary: boundary),
                     "an unknown entry date refuses, because a fresh arrival is indistinguishable")
        suite.expect(ScreenshotArchiveSupport.shouldArchive(
                        age: boundary, added: boundary, boundary: boundary),
                     "the boundary instant itself still files away")
        suite.expect(!ScreenshotArchiveSupport.shouldArchive(
                        age: boundary.addingTimeInterval(1), added: boundary,
                        boundary: boundary),
                     "one second newer than the boundary does not")
    }

    private static func runDefaults(_ suite: TestSuite) {
        let raw = Defaults.registeredDefaults[DefaultsKey.screenshotArchiveAfterDays] as? Int
        suite.expect(raw == 0, "an untouched installation has no archive window configured")
        suite.expect(ScreenshotArchiveSupport.sanitizedArchiveAfterDays(raw ?? 0) == 0
                     && ScreenshotArchiveSupport.archiveBoundary(now: now, afterDays: raw ?? 0) == nil
                     && ScreenshotArchiveSupport.archivePlan(
                        folder: folder, afterDays: raw ?? 0, now: now, calendar: calendar) == nil,
                     "the shipped default is a pass that files nothing away")
        suite.expect(ScreenshotArchiveSupport.archiveAfterChoices == [7, 14, 30, 90, 365],
                     "filing away offers a year, which deleting never would")
        suite.expect(ScreenshotArchiveSupport.archiveAfterChoices
                        != CleanerPolicy.screenshotAgeChoices,
                     "the archive window is its own list, not the cleaner's deletion ages")
    }
}