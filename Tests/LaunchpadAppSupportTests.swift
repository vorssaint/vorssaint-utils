// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LaunchpadAppSupportTests {
    static func run(_ suite: TestSuite) {
        let finder = LaunchpadApp(id: "/System/Library/CoreServices/Finder.app", name: "Finder", bundleID: "com.apple.finder", path: "/System/Library/CoreServices/Finder.app")
        let safari = LaunchpadApp(id: "/Applications/Safari.app", name: "Safari", bundleID: "com.apple.Safari", path: "/Applications/Safari.app")
        let xcode = LaunchpadApp(id: "/Applications/Xcode.app", name: "Xcode", bundleID: "com.apple.dt.Xcode", path: "/Applications/Xcode.app")

        suite.expect(LaunchpadAppSupport.filtered([finder, safari, xcode], query: "").map(\.id) == [finder, safari, xcode].map(\.id),
                     "an empty query keeps every app in its given order")

        suite.expect(LaunchpadAppSupport.filtered([finder, safari, xcode], query: "  ").map(\.id) == [finder, safari, xcode].map(\.id),
                     "a blank query is treated the same as an empty one")

        suite.expect(LaunchpadAppSupport.filtered([finder, safari, xcode], query: "saf") == [safari],
                     "a query matches case-insensitively anywhere in the name")

        suite.expect(LaunchpadAppSupport.filtered([finder, safari, xcode], query: "SAFARI") == [safari],
                     "matching ignores case")

        suite.expect(LaunchpadAppSupport.filtered([finder, safari, xcode], query: "zzz").isEmpty,
                     "no match returns an empty grid rather than falling back to everything")

        suite.expect(LaunchpadAppSupport.pages([]).isEmpty, "no apps means no pages at all")

        let perPage = LaunchpadAppSupport.perPage
        let many = (0..<(perPage + 3)).map { LaunchpadApp(id: "\($0)", name: "App \($0)", bundleID: nil, path: "/tmp/\($0).app") }
        let pages = LaunchpadAppSupport.pages(many)
        suite.expect(pages.count == 2 && pages[0].count == perPage && pages[1].count == 3,
                     "apps split into fixed-size pages, the last page taking whatever remains")
        suite.expect(pages.flatMap { $0 }.map(\.id) == many.map(\.id),
                     "paging never reorders or drops an app")

        suite.expect(LaunchpadPagingSupport.pageStep(cumulativeX: 40) == 0,
                     "a swipe short of the threshold does not page")
        suite.expect(LaunchpadPagingSupport.pageStep(cumulativeX: 80) == 1
                     && LaunchpadPagingSupport.pageStep(cumulativeX: 200) == 1,
                     "a swipe past the threshold to the left reveals the next page")
        suite.expect(LaunchpadPagingSupport.pageStep(cumulativeX: -80) == -1,
                     "a swipe past the threshold to the right reveals the previous page")
        suite.expect(LaunchpadPagingSupport.pageStep(cumulativeX: .nan) == 0,
                     "a non-finite delta never pages")

        suite.expect(LaunchpadPagingSupport.targetPage(current: 0, step: 1, pageCount: 3) == 1,
                     "a forward step moves to the next page")
        suite.expect(LaunchpadPagingSupport.targetPage(current: 2, step: 1, pageCount: 3) == nil,
                     "a forward step past the last page does nothing")
        suite.expect(LaunchpadPagingSupport.targetPage(current: 0, step: -1, pageCount: 3) == nil,
                     "a backward step before the first page does nothing")
        suite.expect(LaunchpadPagingSupport.targetPage(current: 1, step: 0, pageCount: 3) == nil,
                     "no step means no page change")

        let folderApps = (0..<14).map { LaunchpadApp(id: "\($0)", name: "App \($0)", bundleID: nil, path: "/tmp/\($0).app") }
        let folderPages = LaunchpadAppSupport.folderPages(folderApps)
        suite.expect(folderPages.count == 2 && folderPages[0].count == LaunchpadAppSupport.folderPerPage && folderPages[1].count == 2,
                     "a folder past its own page size splits into its own pages, independent of the outer grid's page size")
        suite.expect(LaunchpadAppSupport.folderPages([]).isEmpty, "an empty folder has no pages")

        suite.expect(LaunchpadSelectionSupport.moved(current: nil, direction: .right, count: 10, columns: 5) == 0,
                     "nothing selected yet starts at the first tile")
        suite.expect(LaunchpadSelectionSupport.moved(current: nil, direction: .right, count: 0, columns: 5) == nil,
                     "an empty page has nothing to select")
        suite.expect(LaunchpadSelectionSupport.moved(current: 2, direction: .right, count: 10, columns: 5) == 3,
                     "right moves forward by one")
        suite.expect(LaunchpadSelectionSupport.moved(current: 0, direction: .left, count: 10, columns: 5) == 0,
                     "left at the first tile stays put rather than wrapping")
        suite.expect(LaunchpadSelectionSupport.moved(current: 9, direction: .right, count: 10, columns: 5) == 9,
                     "right at the last tile stays put rather than wrapping")
        suite.expect(LaunchpadSelectionSupport.moved(current: 2, direction: .down, count: 10, columns: 5) == 7,
                     "down moves forward by one full row")
        suite.expect(LaunchpadSelectionSupport.moved(current: 7, direction: .up, count: 10, columns: 5) == 2,
                     "up moves back by one full row")
        suite.expect(LaunchpadSelectionSupport.moved(current: 2, direction: .up, count: 10, columns: 5) == 2,
                     "up on the first row stays put")
        suite.expect(LaunchpadSelectionSupport.moved(current: 7, direction: .down, count: 10, columns: 5) == 7,
                     "down past the last row stays put rather than crossing to another page")

        suite.expect(LaunchpadPagingSupport.scrubbedPage(x: 0, width: 100, pageCount: 4) == 0,
                     "the very start of the dots row is the first page")
        suite.expect(LaunchpadPagingSupport.scrubbedPage(x: 100, width: 100, pageCount: 4) == 3,
                     "the very end of the dots row is the last page")
        suite.expect(LaunchpadPagingSupport.scrubbedPage(x: 26, width: 100, pageCount: 4) == 1,
                     "a position between dots rounds down to the page it's over")
        suite.expect(LaunchpadPagingSupport.scrubbedPage(x: -50, width: 100, pageCount: 4) == 0,
                     "a position before the row clamps to the first page")
        suite.expect(LaunchpadPagingSupport.scrubbedPage(x: 500, width: 100, pageCount: 4) == 3,
                     "a position past the row clamps to the last page")
        suite.expect(LaunchpadPagingSupport.scrubbedPage(x: 50, width: 100, pageCount: 0) == 0,
                     "no pages at all reads as page zero rather than crashing on the divide")

        suite.expect(LaunchpadPinchSupport.isPinchClose(startSpread: 0.5, endSpread: 0.2, duration: 0.3),
                     "a fast, large shrink reads as a deliberate pinch close")
        suite.expect(!LaunchpadPinchSupport.isPinchClose(startSpread: 0.5, endSpread: 0.48, duration: 0.3),
                     "a shrink this small is resting fingers, not a pinch")
        suite.expect(!LaunchpadPinchSupport.isPinchClose(startSpread: 0.5, endSpread: 0.2, duration: 1.2),
                     "a shrink this slow is fingers drifting apart, not a deliberate close")
        suite.expect(!LaunchpadPinchSupport.isPinchClose(startSpread: 0.5, endSpread: 0.6, duration: 0.3),
                     "a growing spread is an open, not a close")
        suite.expect(!LaunchpadPinchSupport.isPinchClose(startSpread: 0, endSpread: 0, duration: 0.3),
                     "a zero starting spread never divides by zero into a false close")
        suite.expect(!LaunchpadPinchSupport.isPinchClose(startSpread: 0.5, endSpread: 0.2, duration: 0),
                     "a zero duration is not a real gesture")
    }
}
