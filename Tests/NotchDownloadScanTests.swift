// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The production scan and completion methods run with the real filesystem
/// and progress observer. Only UI refreshes and file watchers are replaced.
enum NotchDownloadScanTests {
    class Fixture {
        let queue = DispatchQueue(label: "com.vorssaint.tests.download-scan")
        var folder: URL?
        var generation = UUID()
        var progressObserver: NotchDownloadProgressObserver?
        var partials: [URL: NotchPartialDownload] = [:]
        var folderItems: [NotchDownloadItem] = []
        var fileSources: [URL: DispatchSourceFileSystemObject] = [:]
        var finished: [NotchDownloadItem] = []
        var expiry: DispatchWorkItem?
        var scanning = false
        var rescan = false
        var folderUnavailable = false
        var onArrival: ((NotchDownloadItem) -> Void)?
        var onFailure: (() -> Void)?
        var refreshes = 0
        func watch(_ url: URL, directory: Bool) -> DispatchSourceFileSystemObject? { nil }
        func scheduleScan() {}
        func refreshItems() { refreshes += 1 }
        func stop() {
            generation = UUID()
            expiry?.cancel()
            progressObserver?.stop()
            progressObserver = nil
            folder = nil
        }
    }

    static func run(_ suite: TestSuite, folder: URL) throws {
        try concurrentDownloads(suite, folder: folder)
        for completion in ["before", "after", "cancelled", "unknown", "stopped"] {
            try archive(suite, folder: folder, completion: completion)
        }
    }

    private static func wait(timeout: TimeInterval = 3, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private static func concurrentDownloads(_ suite: TestSuite, folder: URL) throws {
        let root = folder.appendingPathComponent("concurrent-downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let success = root.appendingPathComponent("success.part")
        let cancelled = root.appendingPathComponent("cancelled.part")
        try Data([1]).write(to: success)
        try Data([2]).write(to: cancelled)
        let service = Service()
        service.folder = root
        service.partials = NotchDownloadSupport.scanFolder(root)?.partials ?? [:]
        var arrivals = 0
        var failures = 0
        service.onArrival = { _ in arrivals += 1 }
        service.onFailure = { failures += 1 }
        defer { service.stop(); service.queue.sync {} }
        try FileManager.default.moveItem(at: success, to: success.deletingPathExtension())
        try FileManager.default.removeItem(at: cancelled)
        service.scan()
        suite.expect(wait { arrivals == 1 && failures == 1 },
                     "one completed download cannot suppress another download's cancellation in the same scan")
        suite.expect(service.partials.isEmpty && service.finished.count == 1,
                     "the scan retires both partials while retaining only the successful arrival")
    }

    private static func archive(_ suite: TestSuite, folder: URL, completion: String) throws {
        let root = folder.appendingPathComponent("archive-\(completion)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let package = root.appendingPathComponent("archive.zip.download", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        try Data([1]).write(to: package.appendingPathComponent("archive.zip"))
        let service = Service()
        service.folder = root
        service.partials = NotchDownloadSupport.scanFolder(root)?.partials ?? [:]
        let observer = NotchDownloadProgressObserver(folder: root, queue: service.queue) { _, _ in }
        service.progressObserver = observer
        var failures = 0
        service.onFailure = { failures += 1 }
        defer { service.stop(); service.queue.sync {} }
        let progress = Progress(totalUnitCount: 10)
        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.fileURL = package
        let id = UUID()
        if completion != "unknown" {
            observer.add(progress, id: id)
            service.queue.sync {}
        }
        let extracted = root.appendingPathComponent("unrelated extracted name", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: false)
        try FileManager.default.removeItem(at: package)
        func finish() {
            progress.fileURL = extracted
            progress.completedUnitCount = 10
            observer.remove(id)
            service.queue.sync {}
        }
        if completion == "before" { finish() }
        if completion == "cancelled" { progress.cancel(); observer.remove(id); service.queue.sync {} }
        service.scan()
        suite.expect(wait { service.refreshes > 0 && !service.scanning },
                     "\(completion): the folder scan sees the missing package")
        if completion == "after" { finish() }
        if completion == "stopped" { service.stop() }
        let deadline = Date().addingTimeInterval(2.2)
        _ = wait { Date() >= deadline }
        let expected = completion == "cancelled" || completion == "unknown" ? 1 : 0
        suite.expect(failures == expected,
                     "\(completion): only this transfer's proven success or an invalidated generation suppresses failure")
    }
}
