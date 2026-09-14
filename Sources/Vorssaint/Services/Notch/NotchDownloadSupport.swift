// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

struct NotchDownloadItem: Identifiable, Equatable {
    let id: String
    let url: URL
    let name: String
    let receivedBytes: Int64?
    let fraction: Double?
    let completed: Bool
    var active = true
}

struct NotchPartialDownload: Equatable {
    let url: URL
    let expectedURL: URL
    let bytes: Int64
    let resourceID: String?
    let modified: Date
    var contentURL: URL? = nil
}

/// Capture native progress values once before validating paths on the file queue.
struct NotchDownloadProgressSnapshot {
    let fileURL: URL?
    let fileOperationKind: Progress.FileOperationKind?
    let isFile: Bool
    let isFinished: Bool
    let isPaused: Bool
    let isCancelled: Bool
    let completedUnitCount: Int64
    let totalUnitCount: Int64
    let fractionCompleted: Double
    let isIndeterminate: Bool

    init(_ progress: Progress) {
        fileURL = progress.fileURL
        fileOperationKind = progress.fileOperationKind
        isFile = progress.kind == .file
        isFinished = progress.isFinished
        isPaused = progress.isPaused
        isCancelled = progress.isCancelled
        completedUnitCount = progress.completedUnitCount
        totalUnitCount = progress.totalUnitCount
        fractionCompleted = progress.fractionCompleted
        isIndeterminate = progress.isIndeterminate
    }
}

/// A publisher can change its URL while a transfer is running. Keep the first
/// observed state of each destination so an unrelated existing file cannot
/// become a successful download just because the reported count reaches 100%.
struct NotchDownloadPublication {
    private var url: URL
    private var initialFile: NotchDownloadSupport.FileSnapshot?
    private var lastFileIdentity: String?

    init?(_ progress: NotchDownloadProgressSnapshot, folder: URL) {
        guard !progress.isFinished, let url = NotchDownloadSupport.publishedURL(progress, folder: folder) else { return nil }
        self.url = url
        initialFile = NotchDownloadSupport.fileSnapshot(at: url)
        lastFileIdentity = initialFile?.identity
    }

    mutating func item(_ progress: NotchDownloadProgressSnapshot, folder: URL) -> NotchDownloadItem? {
        guard let current = NotchDownloadSupport.publishedURL(progress, folder: folder) else { return nil }
        let file = NotchDownloadSupport.fileSnapshot(at: current)
        if current != url {
            // A moved file is new evidence at its final destination, even if
            // the URL and finished count arrive together. Existing aliases or
            // unrelated files must still establish their own baseline.
            let renamed = file != nil && file?.identity == lastFileIdentity
                && !FileManager.default.fileExists(atPath: url.path)
            initialFile = renamed ? nil : file
            url = current
            lastFileIdentity = file?.identity
        } else if let file {
            lastFileIdentity = file.identity
        }
        let completed = progress.isFinished && file != nil && file != initialFile
            && NotchDownloadSupport.expectedURL(for: current) == nil
        return NotchDownloadItem(id: current.path, url: current, name: current.lastPathComponent,
            receivedBytes: completed ? file?.bytes : progress.isFile ? max(0, progress.completedUnitCount) : nil,
            fraction: completed ? 1 : progress.isFinished ? nil : NotchDownloadSupport.fraction(
                completed: progress.completedUnitCount, total: progress.totalUnitCount,
                reportedFraction: progress.fractionCompleted, indeterminate: progress.isIndeterminate),
            completed: completed, active: !progress.isFinished && !progress.isPaused)
    }
}

enum NotchDownloadSupport {
    static let maximumObservedFiles = 32
    static let maximumDirectoryEntries = 4096

    struct FileSnapshot: Equatable {
        let identity: String
        let bytes: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
    }

    static func publishedURL(_ progress: NotchDownloadProgressSnapshot, folder: URL) -> URL? {
        guard !progress.isCancelled, let url = progress.fileURL,
              progress.fileOperationKind == .downloading || progress.fileOperationKind == .receiving,
              isDirectChild(url, of: folder),
              isDirectChild(url.resolvingSymlinksInPath(), of: folder.resolvingSymlinksInPath()) else { return nil }
        return url.standardizedFileURL
    }

    static func fraction(completed: Int64, total: Int64, reportedFraction: Double,
                         indeterminate: Bool) -> Double? {
        guard !indeterminate, total > 0, completed >= 0,
              reportedFraction.isFinite else { return nil }
        return min(1, max(0, reportedFraction))
    }

    static func expectedURL(for partialURL: URL) -> URL? {
        guard partialURL.isFileURL,
              ["crdownload", "download", "part"].contains(partialURL.pathExtension.lowercased()) else { return nil }
        let output = partialURL.deletingPathExtension()
        return output.lastPathComponent.isEmpty ? nil : output
    }

    static func isDirectChild(_ url: URL, of folder: URL) -> Bool {
        url.isFileURL && folder.isFileURL
            && url.standardizedFileURL.deletingLastPathComponent() == folder.standardizedFileURL
    }

    static func fileIdentity(at url: URL) -> String? {
        fileSnapshot(at: url)?.identity
    }

    static func fileSnapshot(at url: URL) -> FileSnapshot? {
        guard url.isFileURL else { return nil }
        var info = stat()
        guard url.withUnsafeFileSystemRepresentation({ path in
            path.map { lstat($0, &info) == 0 } ?? false
        }), (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return FileSnapshot(identity: "\(info.st_dev):\(info.st_ino)", bytes: info.st_size,
                            modifiedSeconds: info.st_mtimespec.tv_sec,
                            modifiedNanoseconds: info.st_mtimespec.tv_nsec)
    }

    static func didFinish(_ partial: NotchPartialDownload, at finalURL: URL,
                          resourceID: String?) -> Bool {
        guard partial.expectedURL.standardizedFileURL == finalURL.standardizedFileURL,
              let previousID = partial.resourceID, let resourceID else { return false }
        return previousID == resourceID
    }
}
