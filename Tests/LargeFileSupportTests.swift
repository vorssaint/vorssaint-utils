// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The large files finder's pure rules: which folders are skipped, which files
/// qualify, and what may still be removed at the last moment.
enum LargeFileSupportTests {
    static func run(_ suite: TestSuite) {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

        suite.expect(LargeFileSupport.shouldSkipDirectory(home.appendingPathComponent("Library"), home: home)
                     && LargeFileSupport.shouldSkipDirectory(home.appendingPathComponent(".Trash"), home: home)
                     && LargeFileSupport.shouldSkipDirectory(home.appendingPathComponent("Projects/.git"), home: home),
                     "Library, the Trash and hidden folders are never entered")
        suite.expect(!LargeFileSupport.shouldSkipDirectory(home.appendingPathComponent("Downloads"), home: home)
                     && !LargeFileSupport.shouldSkipDirectory(home.appendingPathComponent("Projects/Library"), home: home),
                     "ordinary folders are scanned, including one named Library deeper down")

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = now.addingTimeInterval(-400 * 86_400)
        let recent = now.addingTimeInterval(-10 * 86_400)
        suite.expect(!LargeFileSupport.qualifies(size: 99_999_999, lastOpened: old,
                                                 minimumSize: 100_000_000, olderThanDays: 0, now: now),
                     "a file under the size threshold is left out")
        suite.expect(LargeFileSupport.qualifies(size: 100_000_000, lastOpened: nil,
                                                minimumSize: 100_000_000, olderThanDays: 0, now: now),
                     "without an age filter a big file qualifies even with no last opened date")
        suite.expect(LargeFileSupport.qualifies(size: 2_000_000_000, lastOpened: old,
                                                minimumSize: 100_000_000, olderThanDays: 365, now: now)
                     && !LargeFileSupport.qualifies(size: 2_000_000_000, lastOpened: recent,
                                                    minimumSize: 100_000_000, olderThanDays: 365, now: now),
                     "an age filter keeps only files not opened for that long")
        suite.expect(!LargeFileSupport.qualifies(size: 2_000_000_000, lastOpened: nil,
                                                 minimumSize: 100_000_000, olderThanDays: 90, now: now),
                     "an age filter never guesses at a file with no last opened date")

        suite.expect(LargeFileSupport.mayRemove(home.appendingPathComponent("Downloads/movie.mov"), home: home),
                     "a file in Downloads may be removed")
        suite.expect(!LargeFileSupport.mayRemove(home.appendingPathComponent("Library/Mail/big.mbox"), home: home)
                     && !LargeFileSupport.mayRemove(home.appendingPathComponent(".Trash/old.zip"), home: home)
                     && !LargeFileSupport.mayRemove(home.appendingPathComponent("Projects/.git/pack.bin"), home: home)
                     && !LargeFileSupport.mayRemove(URL(fileURLWithPath: "/Applications/Big.app"), home: home)
                     && !LargeFileSupport.mayRemove(home, home: home),
                     "files in Library, the Trash, hidden folders, outside home, or home itself are refused")
        suite.expect(!LargeFileSupport.mayRemove(URL(fileURLWithPath: "/Users/someone2/file.bin"), home: home)
                     && !LargeFileSupport.mayRemove(home.appendingPathComponent("../other/file.bin"), home: home),
                     "a sibling folder with a similar name or a dot-dot path is refused")

        func hint(_ name: String) -> LargeFileSupport.Safety {
            LargeFileSupport.safety(of: home.appendingPathComponent(name))
        }
        suite.expect(hint("Downloads/App.DMG") == .replaceable && hint("a/b.zip") == .replaceable
                     && hint("Downloads/win.iso") == .replaceable,
                     "installers and archives are marked as replaceable, whatever the letter case")
        suite.expect(hint("Movies/trip.mov") == .yours && hint("Documents/report.pdf") == .yours
                     && hint("Pictures/shot.HEIC") == .yours,
                     "media and documents are marked as your own files")
        suite.expect(hint("VMs/disk.vmdk") == .check && hint("Mail/archive.pst") == .check
                     && hint("data/app.sqlite") == .check && hint("misc/noextension") == .check
                     && hint("misc/blob.bin") == .check,
                     "virtual disks, databases, mail stores and unknown types ask for a check")

        suite.expect(LargeFileSupport.sourceHost(from: ["https://dl.example.com/path/file.dmg", "https://example.com/"])
                     == "dl.example.com"
                     && LargeFileSupport.sourceHost(from: nil) == nil
                     && LargeFileSupport.sourceHost(from: []) == nil
                     && LargeFileSupport.sourceHost(from: ["not a url"]) == nil
                     && LargeFileSupport.sourceHost(from: ["mailto:someone@example.com"]) == nil,
                     "the download source is the first website address, and only the host is kept")

        let ranked = LargeFileSupport.ranked(Array(0..<(LargeFileSupport.maxResults + 50))) { Int64($0) }
        suite.expect(ranked.count == LargeFileSupport.maxResults
                     && ranked.first == LargeFileSupport.maxResults + 49,
                     "results are largest first and capped")
    }
}
