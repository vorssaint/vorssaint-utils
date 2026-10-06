// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The complete production search class runs with a manually drained queue and
/// filesystem boundary. This distinguishes cancelling the debounce from skipping
/// work already waiting behind another filesystem call.
enum CommandBarPathCancellationTests {
    final class DispatchQueue {
        enum QoS { case userInitiated }
        static let main = DispatchQueue(isMain: true)
        static var debounce: [DispatchWorkItem] = []
        static var background: [() -> Void] = []
        static var completions: [() -> Void] = []
        let isMain: Bool

        init(isMain: Bool) { self.isMain = isMain }
        convenience init(label: String, qos: QoS) { self.init(isMain: false) }
        func asyncAfter(deadline: DispatchTime, execute: DispatchWorkItem) {
            Self.debounce.append(execute)
        }
        func async(execute: @escaping () -> Void) {
            if isMain { Self.completions.append(execute) }
            else { Self.background.append(execute) }
        }
        static func startPending() {
            let work = debounce
            debounce = []
            for item in work where !item.isCancelled { item.perform() }
        }
        static func finishOne() {
            if !background.isEmpty { background.removeFirst()() }
            while !completions.isEmpty { completions.removeFirst()() }
        }
        static func clear() {
            debounce = []
            background = []
            completions = []
        }
    }

    final class FileManager {
        static let `default` = FileManager()
        static var checked: [String] = []
        func fileExists(atPath path: String) -> Bool {
            Self.checked.append(path)
            return true
        }
        func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
            isDirectory?.pointee = true
            return fileExists(atPath: path)
        }
    }

    static func run(_ suite: TestSuite) {
        func fresh() -> CommandBarFileSearch {
            DispatchQueue.clear()
            FileManager.checked = []
            return CommandBarFileSearch()
        }
        func enqueue(_ search: CommandBarFileSearch, _ path: String) {
            search.schedule(query: path, scopes: [], patterns: [])
            DispatchQueue.startPending()
        }
        defer { DispatchQueue.clear(); FileManager.checked = [] }

        var search = fresh()
        var published = 0
        search.onResult = { published += 1 }
        enqueue(search, "/old")
        enqueue(search, "/new")
        DispatchQueue.finishOne()
        suite.expect(FileManager.checked.isEmpty && published == 0
                     && search.cachedPaths(for: "/old") == nil,
                     "a superseded queued path never reaches the filesystem")
        DispatchQueue.finishOne()
        suite.expect(FileManager.checked == ["/new"] && published == 1 && !search.isAwaiting,
                     "only the current path runs and cancelled bookkeeping is cleared")
        enqueue(search, "/old")
        DispatchQueue.finishOne()
        suite.expect(FileManager.checked == ["/new", "/old"] && published == 2,
                     "a cancelled path can be requested again after cleanup")

        search = fresh()
        published = 0
        search.onResult = { published += 1 }
        enqueue(search, "/same")
        search.reset()
        enqueue(search, "/same")
        DispatchQueue.finishOne()
        suite.expect(FileManager.checked.isEmpty && search.isAwaiting,
                     "a closed session skips its queued lookup without clearing the new session")
        enqueue(search, "/same")
        suite.expect(DispatchQueue.background.count == 1,
                     "old-session cleanup retains deduplication of the new same-path request")
        DispatchQueue.finishOne()
        suite.expect(FileManager.checked == ["/same"] && published == 1 && !search.isAwaiting,
                     "the reopened session resolves the same path exactly once")

        search = fresh()
        enqueue(search, "/return")
        enqueue(search, "/other")
        enqueue(search, "/return")
        DispatchQueue.finishOne()
        enqueue(search, "/return")
        suite.expect(DispatchQueue.background.count == 2,
                     "old same-session cleanup cannot remove the replacement request's record")
        while !DispatchQueue.background.isEmpty { DispatchQueue.finishOne() }
        suite.expect(FileManager.checked == ["/return"]
                     && search.cachedPaths(for: "/return") == ["/return"] && !search.isAwaiting,
                     "returning to a cancelled in-flight path schedules a live replacement")
    }
}
