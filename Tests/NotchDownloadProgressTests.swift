// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Exercise the real native observer and filesystem reader against disposable
/// files, including callback bursts, renames and cancellation behind a busy lane.
enum NotchDownloadProgressTests {
    private final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var updates: [([NotchDownloadItem], [NotchDownloadItem])] = []
        private var onlyWorker = true
        let arrived = DispatchSemaphore(value: 0)
        func receive(_ items: [NotchDownloadItem], _ completed: [NotchDownloadItem]) {
            lock.lock()
            onlyWorker = onlyWorker && !Thread.isMainThread
            updates.append((items, completed))
            lock.unlock()
            arrived.signal()
        }
        var snapshot: (updates: [([NotchDownloadItem], [NotchDownloadItem])], onlyWorker: Bool) {
            lock.lock(); defer { lock.unlock() }
            return (updates, onlyWorker)
        }
        func wait() -> Bool { arrived.wait(timeout: .now() + 3) == .success }
    }

    static func run(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notch-progress-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            try progressAndCompletion(folder: folder, suite: suite)
            cancellation(folder: folder, suite: suite)
            capacity(folder: folder, suite: suite)
            try folderContents(folder: folder, suite: suite)
        } catch { suite.expect(false, "download progress fixture failed: \(error)") }
    }

    private static func folderContents(folder: URL, suite: TestSuite) throws {
        let root = folder.resolvingSymlinksInPath().appendingPathComponent("contents")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let image = root.appendingPathComponent("image.jpg")
        try Data([1, 2]).write(to: image)
        try Data().write(to: root.appendingPathComponent(".hidden"))
        try Data().write(to: root.appendingPathComponent("transfer.download"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: image)
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("child.txt"))
        // Exceed the old transfer watcher limit: complete files have no cap.
        for index in 0..<40 { try Data().write(to: root.appendingPathComponent("file-\(index)")) }
        guard let snapshot = NotchDownloadSupport.scanFolder(root) else {
            suite.expect(false, "folder contents can be scanned"); return
        }
        suite.expect(snapshot.files.count == 42 && snapshot.files.contains { $0.url.path == image.path && $0.completed },
               "directly saved images and every visible file are listed without a browser publication")
        suite.expect(snapshot.partials.count == 1 && snapshot.files.allSatisfy { $0.url.deletingLastPathComponent().path == root.path },
               "partial transfers remain separate and nested contents are not traversed")
        guard var old = snapshot.files.first(where: { $0.url.path == image.path }),
              var recent = snapshot.files.first(where: { $0.url.path == nested.path }) else {
            suite.expect(false, "the image and directory are retained by the folder reader"); return
        }
        old.date = Date(timeIntervalSince1970: 100)
        recent.date = Date(timeIntervalSince1970: 200)
        let sorted = NotchDownloadSupport.mergedItems(active: [], files: [old, recent], finished: [old])
        suite.expect(sorted.map { $0.url.path } == [nested.path, image.path], "newest folder items sort first and completion notices do not duplicate files")
        let active = NotchDownloadItem(id: image.path, url: image, name: image.lastPathComponent,
            receivedBytes: 1, fraction: 0.5, completed: false, date: old.date)
        let merged = NotchDownloadSupport.mergedItems(active: [active], files: [old], finished: [])
        suite.expect(merged == [active], "a destination on disk cannot hide ongoing native progress")
        try FileManager.default.removeItem(at: image)
        suite.expect(NotchDownloadSupport.scanFolder(root)?.files.contains { $0.url.path == image.path } == false,
               "deleted files disappear from the next folder snapshot")
    }

    private static func progressAndCompletion(folder: URL, suite: TestSuite) throws {
        let queue = DispatchQueue(label: "com.vorssaint.tests.download-progress")
        let results = Results()
        let observer = NotchDownloadProgressObserver(folder: folder, queue: queue, changed: results.receive)
        defer { observer.stop(); queue.sync {} }
        let partial = folder.appendingPathComponent("transfer.part")
        let final = folder.appendingPathComponent("transfer")
        try Data([1, 2, 3]).write(to: partial)
        let progress = Progress(totalUnitCount: 2000)
        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.fileURL = partial
        progress.completedUnitCount = 1
        let initial = NotchDownloadProgressSnapshot(progress)
        let id = UUID()
        observer.add(progress, id: id)
        suite.expect(results.wait(), "published progress becomes visible without running its reads on main")
        suite.expect(results.snapshot.updates.last?.0.first?.fraction == 1.0 / 2000,
               "initial progress retains its real percentage")
        let before = results.snapshot.updates.count
        queue.suspend()
        for completed in 2...1001 { progress.completedUnitCount = Int64(completed) }
        queue.resume()
        suite.expect(results.wait(), "a burst delivers the latest progress")
        let burst = results.snapshot
        suite.expect(burst.updates.count == before + 1 && burst.updates.last?.0.first?.fraction == 1001.0 / 2000,
               "one thousand native changes coalesce into one file-read batch with the final value")
        suite.expect(initial.completedUnitCount == 1 && initial.fractionCompleted == 1.0 / 2000,
               "a captured native snapshot cannot change while file validation is queued")

        try FileManager.default.moveItem(at: partial, to: final)
        progress.fileURL = final
        progress.completedUnitCount = 2000
        observer.remove(id)
        suite.expect(results.wait(), "unpublication delivers final evidence without waiting for a pending refresh")
        let completion = results.snapshot.updates.flatMap(\.1)
        suite.expect(completion.count == 1 && completion[0].url == final && completion[0].completed,
               "a proven final rename survives completion and immediate unpublication")
        suite.expect(results.snapshot.onlyWorker, "every publication read and result callback stays on the download worker")

        let invalid = Progress(totalUnitCount: 10)
        invalid.kind = .file
        invalid.fileOperationKind = .receiving
        invalid.fileURL = folder.appendingPathComponent("incoming")
        let invalidID = UUID()
        observer.add(invalid, id: invalidID)
        // Flush the earlier delayed refresh before inspecting this publication.
        let ready = DispatchSemaphore(value: 0)
        queue.asyncAfter(deadline: .now() + 0.12) { ready.signal() }
        suite.expect(ready.wait(timeout: .now() + 3) == .success, "the publication queue drains")
        invalid.fileURL = folder.deletingLastPathComponent().appendingPathComponent("outside")
        let checked = DispatchSemaphore(value: 0)
        queue.asyncAfter(deadline: .now() + 0.12) { checked.signal() }
        suite.expect(checked.wait(timeout: .now() + 3) == .success, "changed destination validation completes")
        suite.expect(results.snapshot.updates.last?.0.isEmpty == true,
               "a publication moved outside the authorized folder disappears instead of retaining stale progress")
    }

    private static func cancellation(folder: URL, suite: TestSuite) {
        let queue = DispatchQueue(label: "com.vorssaint.tests.download-cancel")
        let results = Results()
        let observer = NotchDownloadProgressObserver(folder: folder, queue: queue, changed: results.receive)
        let progress = Progress(totalUnitCount: 10)
        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.fileURL = folder.appendingPathComponent("cancelled.part")
        queue.suspend()
        observer.add(progress, id: UUID())
        for _ in 0..<1000 { observer.requestRefresh() }
        observer.stop()
        queue.resume()
        let drained = DispatchSemaphore(value: 0)
        queue.asyncAfter(deadline: .now() + 0.1) { drained.signal() }
        suite.expect(drained.wait(timeout: .now() + 3) == .success, "stopping does not block behind a paused file queue")
        suite.expect(results.snapshot.updates.isEmpty,
               "queued publication and refresh callbacks cannot repopulate downloads after stop")
    }

    private static func capacity(folder: URL, suite: TestSuite) {
        let queue = DispatchQueue(label: "com.vorssaint.tests.download-capacity")
        let results = Results()
        let observer = NotchDownloadProgressObserver(folder: folder, queue: queue, changed: results.receive)
        defer { observer.stop(); queue.sync {} }
        queue.suspend()
        for i in 0...NotchDownloadSupport.maximumObservedFiles {
            let progress = Progress(totalUnitCount: 10)
            progress.fileOperationKind = .downloading
            progress.fileURL = folder.appendingPathComponent("capacity-\(i).part")
            observer.add(progress, id: UUID())
        }
        queue.resume()
        suite.expect(results.wait(), "bounded progress publications are read")
        suite.expect(results.snapshot.updates.last?.0.count == NotchDownloadSupport.maximumObservedFiles,
               "moving observation off-main preserves the limit on live publishers")
    }
}
