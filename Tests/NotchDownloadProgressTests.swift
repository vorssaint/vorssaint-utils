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
            try fastCompletion(folder: folder, suite: suite)
            try safariPackage(folder: folder, suite: suite)
            try sourceCompletion(folder: folder, suite: suite)
            try queuedSourceReplacement(folder: folder, suite: suite)
            cancellation(folder: folder, suite: suite)
            capacity(folder: folder, suite: suite)
            try folderContents(folder: folder, suite: suite)
            try announcements(folder: folder, suite: suite)
            try NotchDownloadScanTests.run(suite, folder: folder)
        } catch { suite.expect(false, "download progress fixture failed: \(error)") }
    }

    private static func fastCompletion(folder: URL, suite: TestSuite) throws {
        let queue = DispatchQueue(label: "com.vorssaint.tests.download-fast")
        let results = Results()
        let observer = NotchDownloadProgressObserver(folder: folder, queue: queue, changed: results.receive)
        defer { observer.stop(); queue.sync {} }
        let partial = folder.appendingPathComponent("fast.part")
        let final = folder.appendingPathComponent("fast")
        try Data([1, 2, 3]).write(to: partial)
        let progress = Progress(totalUnitCount: 10)
        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.fileURL = partial
        progress.completedUnitCount = 1
        let id = UUID()
        observer.add(progress, id: id)
        queue.sync {}
        try FileManager.default.moveItem(at: partial, to: final)
        progress.fileURL = final
        progress.completedUnitCount = 10
        observer.remove(id)
        queue.sync {}
        let completed = results.snapshot.updates.flatMap(\.1)
        suite.expect(completed.count == 1 && completed.first?.url == final,
                     "a valid publication completing before its first refresh preserves the arrival")
    }

    private static func sourceCompletion(folder: URL, suite: TestSuite) throws {
        let root = folder.appendingPathComponent("source-completion")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let queue = DispatchQueue(label: "com.vorssaint.tests.download-source")
        let observer = NotchDownloadProgressObserver(folder: root, queue: queue) { _, _ in }
        defer { observer.stop(); queue.sync {} }
        let package = root.appendingPathComponent("archive.zip.download", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        guard let partial = NotchDownloadSupport.scanFolder(root)?.partials[package.standardizedFileURL] else {
            suite.expect(false, "the original Safari package is observed"); return
        }
        suite.expect(partial.source != nil && partial.resourceID == nil,
                     "the wrapper identifies a transfer before its payload exists")
        let progress = Progress(totalUnitCount: 10)
        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.fileURL = package
        let id = UUID()
        observer.add(progress, id: id)
        queue.sync {}
        let extracted = root.appendingPathComponent("a different folder", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: false)
        // Keep the old inode allocated while its path is reused below.
        try FileManager.default.moveItem(at: package, to: root.appendingPathComponent("old-wrapper"))
        suite.expect(!queue.sync { observer.didFinish(partial) },
                     "a missing package is not successful while its publisher is still running")
        progress.fileURL = extracted
        progress.completedUnitCount = 10
        suite.expect(queue.sync { observer.didFinish(partial) },
                     "the native completion is visible before a queued refresh and ignores the extracted name")
        observer.remove(id)
        queue.sync {}
        suite.expect(queue.sync { observer.didFinish(partial) },
                     "unpublication retains the original transfer's completion for a pending scan")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        guard let replacement = NotchDownloadSupport.scanFolder(root)?.partials[package.standardizedFileURL] else {
            suite.expect(false, "a replacement package is observed"); return
        }
        suite.expect(replacement.source != partial.source && !queue.sync { observer.didFinish(replacement) },
                     "reusing a download path cannot borrow the previous transfer's success")
        let cancelled = Progress(totalUnitCount: 10)
        cancelled.fileOperationKind = .downloading
        cancelled.fileURL = package
        let cancelledID = UUID()
        observer.add(cancelled, id: cancelledID)
        queue.sync {}
        cancelled.completedUnitCount = 10
        cancelled.cancel()
        observer.remove(cancelledID)
        queue.sync {}
        suite.expect(!queue.sync { observer.didFinish(replacement) },
                     "cancellation wins over a completed count and another transfer's success")
        suite.expect(!queue.sync { observer.didFinish(partial, at: Date().addingTimeInterval(6)) },
                     "completion evidence expires instead of accumulating indefinitely")
        observer.stop()
        suite.expect(!queue.sync { observer.didFinish(partial) },
                     "a stopped observer cannot validate a delayed failure callback")
    }

    private static func queuedSourceReplacement(folder: URL, suite: TestSuite) throws {
        let root = folder.appendingPathComponent("queued-source")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let package = root.appendingPathComponent("archive.zip.download", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        let queue = DispatchQueue(label: "com.vorssaint.tests.download-queued-source")
        let observer = NotchDownloadProgressObserver(folder: root, queue: queue) { _, _ in }
        defer { observer.stop(); queue.sync {} }
        let progress = Progress(totalUnitCount: 10)
        progress.fileOperationKind = .downloading
        progress.fileURL = package
        let id = UUID()
        queue.suspend()
        observer.add(progress, id: id)
        let extracted = root.appendingPathComponent("old-wrapper", isDirectory: true)
        do {
            try FileManager.default.moveItem(at: package, to: extracted)
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        } catch { queue.resume(); throw error }
        let replacement = NotchDownloadSupport.scanFolder(root)?.partials[package.standardizedFileURL]
        progress.fileURL = extracted
        progress.completedUnitCount = 10
        observer.remove(id)
        queue.resume()
        queue.sync {}
        suite.expect(replacement.map { partial in !queue.sync { observer.didFinish(partial) } } == true,
                     "a publication ending behind a busy queue cannot adopt a replacement package's identity")
    }

    /// Safari 27 publishes progress on its .download folder from another
    /// process, so the file URL arrives after the publication itself. When
    /// it ends, the file moves out under a unique name and the progress
    /// points there before it is unpublished.
    private static func safariPackage(folder: URL, suite: TestSuite) throws {
        let queue = DispatchQueue(label: "com.vorssaint.tests.download-safari")
        let results = Results()
        let observer = NotchDownloadProgressObserver(folder: folder, queue: queue, changed: results.receive)
        defer { observer.stop(); queue.sync {} }
        let package = folder.appendingPathComponent("report.pdf.download", isDirectory: true)
        let payload = package.appendingPathComponent("report.pdf")
        let delivered = folder.appendingPathComponent("report-1.pdf")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        try Data([1, 2, 3, 4]).write(to: payload)
        let progress = Progress(totalUnitCount: 10)
        progress.kind = .file
        progress.completedUnitCount = 2
        observer.add(progress, id: UUID())
        suite.expect(results.wait() && results.snapshot.updates.last?.0.isEmpty == true,
               "a publication waits for its file URL instead of being judged without it")
        progress.fileURL = package
        suite.expect(results.wait() && results.snapshot.updates.last?.0.isEmpty == true,
               "a file URL arriving before the operation kind keeps waiting for that metadata")
        progress.fileOperationKind = .downloading
        progress.completedUnitCount = 4
        suite.expect(results.wait(), "the file URL arriving after the publication refreshes it")
        let item = results.snapshot.updates.last?.0.first
        suite.expect(item?.url.path == package.path && item?.fraction == 0.4 && item?.active == true,
               "a late file URL still shows the transfer's percentage")
        suite.expect(item?.name == "report.pdf", "Safari's .download folder is named after the file it becomes")

        try FileManager.default.moveItem(at: payload, to: delivered)
        try FileManager.default.removeItem(at: package)
        progress.fileURL = delivered
        progress.completedUnitCount = 10
        suite.expect(results.wait(), "the delivered file refreshes the publication")
        let last = results.snapshot.updates.last?.0.first
        suite.expect(last?.url.path == delivered.path && last?.name == "report-1.pdf" && last?.active == false,
               "the transfer stops showing once Safari points at the file it delivered")
    }

    private static func announcements(folder: URL, suite: TestSuite) throws {
        let root = folder.appendingPathComponent("announced")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("report-1.pdf")
        try Data([1, 2]).write(to: file)
        let opened = root.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: opened, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: file)
        try Data().write(to: root.appendingPathComponent("transfer.crdownload"))
        let nested = opened.appendingPathComponent("inside.txt")
        try Data().write(to: nested)

        // The temporary folder is also reached through /private, which the
        // announcing app may have resolved.
        let viaPrivate = file.path.hasPrefix("/var/") ? "/private" + file.path : file.path
        let announced = NotchDownloadSupport.announcedItem(atPath: viaPrivate, folder: root)
        suite.expect(announced?.id == file.standardizedFileURL.path && announced?.name == "report-1.pdf"
                     && announced?.completed == true && announced?.receivedBytes == 2,
               "a finished download announced by its browser keeps the folder's own path")
        suite.expect(NotchDownloadSupport.announcedItem(atPath: opened.path, folder: root)?.name == "archive",
               "an archive Safari opened is announced as the folder it held")
        let rejected = [root.appendingPathComponent("alias").path, root.appendingPathComponent("transfer.crdownload").path,
                        root.appendingPathComponent("missing").path, nested.path, folder.appendingPathComponent("outside").path,
                        "announced/report-1.pdf"]
        suite.expect(rejected.allSatisfy { NotchDownloadSupport.announcedItem(atPath: $0, folder: root) == nil },
               "aliases, partial transfers, missing, nested, outside and relative paths are not downloads")
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
        let crowded = folder.resolvingSymlinksInPath().appendingPathComponent("crowded")
        try FileManager.default.createDirectory(at: crowded, withIntermediateDirectories: true)
        for index in 0..<(NotchDownloadSupport.maximumListedFiles + 20) {
            try Data().write(to: crowded.appendingPathComponent("entry-\(index)"))
        }
        let listed = NotchDownloadSupport.scanFolder(crowded)?.files ?? []
        let listedNames = Set(listed.map(\.name))
        let unlistedDates = try FileManager.default.contentsOfDirectory(at: crowded,
            includingPropertiesForKeys: Array(NotchDownloadSupport.keys))
            .filter { !listedNames.contains($0.lastPathComponent) }
            .compactMap { try? $0.resourceValues(forKeys: NotchDownloadSupport.keys) }
            .map { $0.addedToDirectoryDate ?? $0.creationDate ?? $0.contentModificationDate ?? .distantPast }
        suite.expect(listed.count == NotchDownloadSupport.maximumListedFiles && unlistedDates.count == 20
                     && unlistedDates.allSatisfy { date in listed.allSatisfy { $0.date >= date } },
               "a crowded folder hands the main queue only its newest entries")
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
