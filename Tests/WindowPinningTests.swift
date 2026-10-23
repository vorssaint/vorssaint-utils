// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum WindowPinningTests {
    /// Pure window-pinning logic: the pinned-window store, its JSON
    /// persistence, and the injected-window resolution the service scans.
    /// No Accessibility, SkyLight or live window-server calls happen here.
    static func run(_ suite: TestSuite) {
        makeEntryAssertions(suite)
        persistenceAssertions(suite)
        filterAssertions(suite)
        frontmostWindowAssertions(suite)
        clickRoutingAssertions(suite)
        coverageAssertions(suite)
        backupAssertions(suite)
    }

    private static func makeEntry(windowID: UInt32, ownerPID: pid_t = 100,
                                  bundleID: String = "com.example.app") -> PinnedWindowEntry {
        PinnedWindowEntry(windowID: windowID, ownerPID: ownerPID, bundleID: bundleID,
                          pinnedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    // MARK: - PinnedWindowStore

    private static func makeEntryAssertions(_ suite: TestSuite) {
        var store = PinnedWindowStore()
        store.upsert(makeEntry(windowID: 42))
        store.upsert(makeEntry(windowID: 43))
        suite.expect(store.count == 2, "two upserts hold two entries")
        store.upsert(makeEntry(windowID: 42, bundleID: "com.example.other"))
        suite.expect(store.count == 2, "re-upserting a windowID replaces instead of appending")
        suite.expect(store.entries.first { $0.windowID == 42 }?.bundleID == "com.example.other",
                     "the replaced entry carries its new owner")

        suite.expect(store.remove(windowID: 43)?.windowID == 43, "remove returns the removed entry")
        suite.expect(store.remove(windowID: 43) == nil, "removing an absent window returns nil")
        suite.expect(store.contains(windowID: 42) && !store.contains(windowID: 43),
                     "contains tracks membership after removals")

        var pruning = PinnedWindowStore()
        pruning.upsert(makeEntry(windowID: 1))
        pruning.upsert(makeEntry(windowID: 2))
        pruning.upsert(makeEntry(windowID: 3))
        let removed = pruning.prune(keeping: [1, 3, 99])
        suite.expect(removed.map(\.windowID) == [2], "prune returns exactly the dropped entries")
        suite.expect(Set(pruning.entries.map(\.windowID)) == [1, 3],
                     "prune keeps every entry whose window still exists")
        suite.expect(pruning.prune(keeping: [1, 3]).isEmpty && pruning.count == 2,
                     "a second prune over the survivors removes nothing")
    }

    private static func persistenceAssertions(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.window-pinning.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }

        var store = PinnedWindowStore()
        store.upsert(makeEntry(windowID: 11))
        store.upsert(makeEntry(windowID: 12, ownerPID: 200, bundleID: ""))
        store.save(defaultsKey: "pinned.test", to: defaults)
        suite.expect(PinnedWindowStore.load(defaultsKey: "pinned.test", from: defaults) == store,
                     "a saved store loads back identical")
        suite.expect(PinnedWindowStore.load(defaultsKey: "pinned.never-written", from: defaults).count == 0,
                     "an absent key loads an empty store")
        defaults.set(Data("not json".utf8), forKey: "pinned.corrupt")
        suite.expect(PinnedWindowStore.load(defaultsKey: "pinned.corrupt", from: defaults).count == 0,
                     "corrupt JSON loads an empty store, never a half-read pin")
    }

    // MARK: - WindowPinningResolver

    private static func window(pid: Int, layer: Int = 0, alpha: Double = 1,
                               number: UInt32 = 0) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowNumber as String: number,
        ]
    }

    private static func window(pid: Int, frame: CGRect, number: UInt32) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: 0,
            kCGWindowAlpha as String: 1,
            kCGWindowNumber as String: number,
            kCGWindowBounds as String: [
                "X": frame.origin.x, "Y": frame.origin.y,
                "Width": frame.width, "Height": frame.height,
            ],
        ]
    }

    private static func filterAssertions(_ suite: TestSuite) {
        let own: pid_t = 50
        let windows: [[String: Any]] = [
            window(pid: Int(own), number: 1),               // a normal window
            window(pid: Int(own), layer: 1, number: 2),     // an in-app overlay
            window(pid: Int(own), layer: 25, number: 3),    // another app's layer
            window(pid: Int(own), alpha: 0, number: 4),     // fully transparent
            window(pid: Int(own), alpha: 0.005, number: 5), // below the visibility threshold
            window(pid: Int(own), alpha: 0.02, number: 6),  // barely visible still counts
            window(pid: Int(own) + 1, number: 7),           // another owner
            window(pid: Int(own), number: 8),               // a second normal window
        ]
        let numbers = WindowPinningResolver.filteredAppWindows(windows, ownerPID: own)
            .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        suite.expect(numbers == [1, 6, 8],
                     "the filter keeps only normal-layer, visible, owned windows, in list order")
    }

    private static func frontmostWindowAssertions(_ suite: TestSuite) {
        let own: pid_t = 50
        let target: pid_t = 60
        // CGWindowListCopyWindowInfo orders back to front: index zero is the
        // frontmost candidate.
        let front = CGRect(x: 0, y: 0, width: 800, height: 600)
        let back = CGRect(x: 100, y: 100, width: 400, height: 300)
        let windows = [
            window(pid: Int(target), frame: front, number: 101),
            window(pid: Int(target), frame: back, number: 102),
            window(pid: Int(own), frame: CGRect(x: 0, y: 0, width: 10, height: 10), number: 103),
        ]
        suite.expect(WindowPinningResolver.frontmostWindowID(
            ownPID: own, windows: windows, focusedPID: target, focusedWindowFrame: back) == 102,
            "a provided frame picks the exact window over the frontmost")
        suite.expect(WindowPinningResolver.frontmostWindowID(
            ownPID: own, windows: windows, focusedPID: target, focusedWindowFrame: nil) == 101,
            "without a frame the frontmost filtered window answers")
        suite.expect(WindowPinningResolver.frontmostWindowID(
            ownPID: own, windows: windows, focusedPID: target,
            focusedWindowFrame: CGRect(x: 9_999, y: 9_999, width: 1, height: 1)) == 101,
            "a frame matching nothing still falls back to the frontmost")

        let onlyOwn = [window(pid: Int(own), number: 201)]
        suite.expect(WindowPinningResolver.frontmostWindowID(
            ownPID: own, windows: onlyOwn, focusedPID: own, focusedWindowFrame: nil) == nil,
            "focusing ourselves pins nothing")
        suite.expect(WindowPinningResolver.frontmostWindowID(
            ownPID: own, windows: onlyOwn, focusedPID: nil, focusedWindowFrame: nil) == nil,
            "no focused app resolves nothing")
        suite.expect(WindowPinningResolver.frontmostWindowID(
            ownPID: own, windows: onlyOwn, focusedPID: target, focusedWindowFrame: nil) == nil,
            "a focused app with no eligible windows resolves nothing")
    }

    private static func clickRoutingAssertions(_ suite: TestSuite) {
        let own: pid_t = 50
        let target: pid_t = 60
        let other: pid_t = 70
        let pinned = CGRect(x: 0, y: 0, width: 800, height: 600)
        let point = CGPoint(x: 400, y: 300)
        func fallsThrough(_ windows: [[String: Any]]) -> Bool {
            WindowPinningResolver.clickFallsThrough(at: point, pinnedWindowID: 101, pinnedOwnerPID: target,
                                                    ownPID: own, windows: windows)
        }
        // The list is front to back; our clone panel sits on top of all of it.
        let clone = window(pid: Int(own), frame: pinned, number: 900)
        let original = window(pid: Int(target), frame: pinned, number: 101)

        suite.expect(fallsThrough([clone, original]),
                     "the original in front under the pointer takes the click")
        suite.expect(!fallsThrough([clone, window(pid: Int(other), frame: pinned, number: 201), original]),
                     "another app's window covering the original makes the clone catch the click")
        suite.expect(!fallsThrough([clone, window(pid: Int(target), frame: CGRect(x: 300, y: 200, width: 900, height: 700),
                                                  number: 102), original]),
                     "a second window of the same app covering the original also makes the clone catch it")
        suite.expect(fallsThrough([clone, window(pid: Int(target), frame: CGRect(x: 350, y: 250, width: 200, height: 100),
                                                 number: 103), original]),
                     "the pinned app's child UI inside the original keeps the clone click-through")
        suite.expect(fallsThrough([clone, window(pid: Int(other), frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                                                 number: 202), original]),
                     "a window elsewhere on screen does not change the routing")
        suite.expect(!fallsThrough([clone]),
                     "a clone whose original is on another Space catches the click to lead back to it")
    }

    private static func coverageAssertions(_ suite: TestSuite) {
        let own: pid_t = 50
        let target: pid_t = 60
        let other: pid_t = 70
        let pinned = CGRect(x: 0, y: 0, width: 800, height: 600)
        func covered(_ windows: [[String: Any]], offScreenIsCovered: Bool = false) -> Bool {
            WindowPinningResolver.isCovered(pinnedWindowID: 101, pinnedOwnerPID: target,
                                            ownPID: own, windows: windows,
                                            offScreenIsCovered: offScreenIsCovered)
        }
        let clone = window(pid: Int(own), frame: pinned, number: 900)
        let original = window(pid: Int(target), frame: pinned, number: 101)

        suite.expect(!covered([clone, original]),
                     "an original with only our clone in front is uncovered")
        suite.expect(covered([clone, window(pid: Int(other), frame: CGRect(x: 700, y: 500, width: 400, height: 400),
                                            number: 201), original]),
                     "another app's window overlapping part of the original covers it")
        suite.expect(!covered([window(pid: Int(other), frame: CGRect(x: 900, y: 0, width: 300, height: 300),
                                      number: 202), original]),
                     "a window in front that does not overlap leaves the original uncovered")
        suite.expect(!covered([window(pid: Int(target), frame: CGRect(x: 100, y: 100, width: 200, height: 50),
                                      number: 102), original]),
                     "the pinned app's child UI inside the original does not cover it")
        suite.expect(!covered([original, window(pid: Int(other), frame: pinned, number: 203)]),
                     "a window behind the original does not cover it")
        suite.expect(!covered([clone]),
                     "an original missing from the on-screen list (another Space) hides its clone")
        suite.expect(covered([clone], offScreenIsCovered: true),
                     "with Show on All Spaces, an original on another Space keeps its clone showing")
        suite.expect(!covered([clone, original], offScreenIsCovered: true),
                     "Show on All Spaces leaves an uncovered on-screen original showing directly")
    }

    private static func backupAssertions(_ suite: TestSuite) {
        let keys = SettingsBackupSupport.exportKeys()
        suite.expect(keys.contains(DefaultsKey.windowPinningEnabled)
                && keys.contains(DefaultsKey.windowPinningShortcut)
                && keys.contains(DefaultsKey.windowPinningShowOnAllSpaces),
                     "the backup carries the pinning switch, its shortcut and Show on All Spaces")
        suite.expect(!keys.contains(DefaultsKey.windowPinnedWindows),
                     "the backup leaves out the pins themselves: window ids only mean something on this Mac")
    }
}
