// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The rules `ShelfFileResolution` owns: what counts as alive, when a dead
/// path heals through its bookmark, which directories are package content,
/// which dead files may be retired, and what a cancelled resolution returns.
enum ShelfFileResolutionTests {
    /// A flag two threads can share without a data race.
    private final class Flag {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.withLock { value } }
        func set() { lock.withLock { value = true } }
    }

    static func run(_ suite: TestSuite) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("vorss-shelf-resolution-\(UUID())")
        defer { try? fm.removeItem(at: root) }
        let resources = root.appendingPathComponent("Library.app/Contents/Resources", isDirectory: true)
        let inside = resources.appendingPathComponent("photo.jpeg")
        let plain = root.appendingPathComponent("plain.jpeg")
        let doomed = root.appendingPathComponent("doomed.txt")
        do {
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            try Data("package content".utf8).write(to: inside)
            try Data("ordinary file".utf8).write(to: plain)
            try Data("doomed".utf8).write(to: doomed)
        } catch {
            suite.expect(false, "shelf resolution fixture could not be created: \(error)")
            return
        }

        // MARK: Existing file

        let plainID = UUID()
        let alive = ShelfFileResolution.resolve(
            [.init(id: plainID, url: plain)])
        suite.expect(alive.livingURLs == [plain] && alive.living.first?.healed == false
                && alive.missingIDs.isEmpty && !alive.cancelled,
               "an existing file resolves alive in place and is never retired")

        // MARK: Dead bookmark

        let doomedID = UUID()
        try? fm.removeItem(at: doomed)
        let dead = ShelfFileResolution.resolve(
            [.init(id: doomedID, url: doomed, bookmark: Data([1, 2, 3]))],
            resolveBookmark: { _ in doomed.path })
        suite.expect(dead.living.isEmpty && dead.livingURLs.isEmpty
                && dead.missingIDs == [doomedID],
               "a dead path whose bookmark names another dead path is retired")

        // MARK: Healed bookmark

        let healedID = UUID()
        let moved = root.appendingPathComponent("renamed.jpeg")
        try? Data("renamed".utf8).write(to: moved)
        let healed = ShelfFileResolution.resolve(
            [.init(id: healedID, url: plain.appendingPathExtension("old"), bookmark: Data([4, 5]))],
            resolveBookmark: { _ in moved.path })
        suite.expect(healed.living.count == 1 && healed.living.first?.url == moved
                && healed.living.first?.healed == true && healed.missingIDs.isEmpty,
               "a bookmark that finds the file again resolves it under its new path")

        // MARK: Package directory

        let insideResult = ShelfFileResolution.resolve(
            [.init(id: UUID(), url: inside)], wantsPackageContent: true)
        let wholePackage = ShelfFileResolution.resolve(
            [.init(id: UUID(), url: root.appendingPathComponent("Library.app"))],
            wantsPackageContent: true)
        let ordinaryResult = ShelfFileResolution.resolve(
            [.init(id: UUID(), url: plain)], wantsPackageContent: true)
        suite.expect(insideResult.containsPackageContent,
               "a file inside a package is package content")
        suite.expect(!wholePackage.containsPackageContent && !ordinaryResult.containsPackageContent,
               "a whole package and an ordinary file are both safe to move")

        // MARK: Removable volume

        let volumeRoot = "/Volumes/VorssaintMissingVolume-\(UUID().uuidString)"
        let volumePath = volumeRoot + "/photo.jpeg"
        let volumeCandidate = ShelfFileResolution.Candidate(
            id: UUID(), url: URL(fileURLWithPath: volumePath))
        let absentVolume = ShelfFileResolution.resolve(
            [volumeCandidate], exists: { $0 != volumePath && $0 != volumeRoot })
        let mountedVolume = ShelfFileResolution.resolve(
            [volumeCandidate], exists: { $0 == volumeRoot })
        suite.expect(absentVolume.living.isEmpty && absentVolume.missingIDs.isEmpty,
               "a file on an absent volume is kept until its drive comes back")
        suite.expect(mountedVolume.missingIDs == [volumeCandidate.id],
               "the same file is retired once its volume is mounted and the file is gone")

        // MARK: Cancellation

        let cancelled = ShelfFileResolution.resolve(
            [.init(id: UUID(), url: plain)], isCancelled: { true })
        suite.expect(cancelled.cancelled && cancelled.living.isEmpty && cancelled.missingIDs.isEmpty,
               "a cancelled resolution returns nothing any action may use")

        // A resolution that is already walking a slow provider still finishes
        // cancelled once the gesture is dropped: the late completion carries no
        // files, so no action can run.
        let entered = DispatchSemaphore(value: 0)
        let gate = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let dropped = Flag()
        var lateResult: ShelfFileResolution.Result?
        let work = ShelfFileResolution.resolve(
            (0..<4).map { .init(id: UUID(), url: URL(fileURLWithPath: "/slow/\($0).txt")) },
            on: DispatchQueue(label: "shelf-resolution-cancellation-test"),
            exists: { _ in
                entered.signal()
                _ = gate.wait(timeout: .now() + 3)
                return true
            },
            isCancelled: { dropped.isSet },
            completion: { result in
                lateResult = result
                finished.signal()
            })
        _ = entered.wait(timeout: .now() + 3)
        dropped.set()
        work.cancel()
        gate.signal()
        _ = finished.wait(timeout: .now() + 3)
        suite.expect(lateResult?.cancelled == true && lateResult?.livingURLs.isEmpty == true,
               "a resolution finishing after cancellation delivers no files to act on")

        // MARK: A normal batch still completes

        var normal: [ShelfFileResolution.Candidate] = []
        for index in 0..<50 {
            let url = root.appendingPathComponent("normal-\(index).txt")
            try? Data("normal".utf8).write(to: url)
            normal.append(.init(id: UUID(), url: url))
        }
        let normalFinished = DispatchSemaphore(value: 0)
        var normalURLs: [URL] = []
        ShelfFileResolution.resolve(normal, on: DispatchQueue(label: "shelf-resolution-normal-test")) {
            normalURLs = $0.livingURLs
            normalFinished.signal()
        }
        _ = normalFinished.wait(timeout: .now() + 3)
        suite.expect(normalURLs == normal.map(\.url),
               "a normal batch of 50 files resolves every action target")

        // MARK: Menu latency — 20 local files

        var local: [ShelfFileResolution.Candidate] = []
        for index in 0..<20 {
            let url = root.appendingPathComponent("menu-\(index).txt")
            try? Data("local".utf8).write(to: url)
            local.append(.init(id: UUID(), url: url))
        }
        let menuFinished = DispatchSemaphore(value: 0)
        var menuURLs: [URL] = []
        let menuStarted = Date()
        ShelfFileResolution.resolve(local, on: DispatchQueue(label: "shelf-resolution-menu-latency")) {
            menuURLs = $0.livingURLs
            menuFinished.signal()
        }
        _ = menuFinished.wait(timeout: .now() + 3)
        let menuLatency = Date().timeIntervalSince(menuStarted)
        print(String(format: "shelf context menu: 20 local files resolved in %.2f ms before the menu is built",
                     menuLatency * 1000))
        suite.expect(menuURLs.count == 20,
               "a local 20-file menu resolves every action target")

        // MARK: Performance — 50 files on a simulated slow provider

        let count = 50
        let candidates = (0..<count).map {
            ShelfFileResolution.Candidate(id: UUID(),
                                          url: URL(fileURLWithPath: "/slow-volume/file-\($0).txt"))
        }
        let providerOnMain = Flag()
        let parked = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let perfFinished = DispatchSemaphore(value: 0)
        var perfResult: ShelfFileResolution.Result?
        let started = Date()
        ShelfFileResolution.resolve(
            candidates,
            on: DispatchQueue(label: "shelf-resolution-performance-test"),
            exists: { _ in
                if Thread.isMainThread { providerOnMain.set() }
                parked.signal()
                // The first call parks until the main thread has answered, so
                // a walk that ran on main would deadlock here and fail below.
                _ = release.wait(timeout: .now() + 5)
                usleep(2_000)
                return true
            },
            completion: { result in
                perfResult = result
                perfFinished.signal()
            })
        // Main must keep answering while the provider is busy, which is what a
        // button click during a network-volume check would feel like.
        _ = parked.wait(timeout: .now() + 3)
        var mainAnswered = false
        let pinged = Date()
        DispatchQueue.main.async { mainAnswered = true }
        let deadline = Date().addingTimeInterval(1)
        while !mainAnswered && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        let mainLatency = Date().timeIntervalSince(pinged)
        for _ in 0..<count { release.signal() }
        let drained = perfFinished.wait(timeout: .now() + 5)
        let elapsed = Date().timeIntervalSince(started)
        print(String(format: "shelf resolution: %d files on a 2 ms provider took %.1f ms "
                     + "(%.2f ms each); main queue answered in %.2f ms",
                     count, elapsed * 1000, elapsed * 1000 / Double(count), mainLatency * 1000))
        suite.expect(!providerOnMain.isSet,
               "a slow provider never runs on the main thread")
        suite.expect(mainAnswered,
               "the main thread answers while a slow provider is parked")
        suite.expect(drained == .success && perfResult?.living.count == count,
               "50 files resolve once the slow provider answers")
    }
}
