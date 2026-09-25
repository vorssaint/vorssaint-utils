// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
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
    var date: Date = .distantPast
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
    private let date = Date()

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
            completed: completed, active: !progress.isFinished && !progress.isPaused, date: date)
    }
}

enum NotchDownloadSupport {
    struct FolderSnapshot {
        let partials: [URL: NotchPartialDownload]
        let files: [NotchDownloadItem]
    }

    static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
        .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey,
    ]

    static func scanFolder(_ folder: URL) -> FolderSnapshot? {
        var readFailed = false
        guard let entries = FileManager.default.enumerator(at: folder,
            includingPropertiesForKeys: Array(keys), options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles],
            errorHandler: { _, _ in readFailed = true; return false }) else { return nil }
        var result: [URL: NotchPartialDownload] = [:]
        var files: [NotchDownloadItem] = []
        for case let entry as URL in entries {
            let url = entry.standardizedFileURL
            guard let values = try? entry.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true,
                  values.isRegularFile == true || values.isDirectory == true else { continue }
            guard let expected = expectedURL(for: url) else {
                files.append(NotchDownloadItem(id: url.path, url: url, name: url.lastPathComponent,
                    receivedBytes: values.fileSize.map(Int64.init), fraction: 1, completed: true,
                    active: false, date: values.addedToDirectoryDate ?? values.creationDate
                        ?? values.contentModificationDate ?? .distantPast))
                continue
            }
            guard result.count < maximumObservedFiles else { continue }
            var payloadValues = values
            var contentURL: URL?
            if values.isDirectory == true {
                // A partial package can hold the real file. Inspect only its
                // expected payload, never traverse other folders or resume data.
                let payload = url.appendingPathComponent(expected.lastPathComponent)
                if let found = try? payload.resourceValues(forKeys: keys),
                   found.isRegularFile == true, found.isSymbolicLink != true {
                    payloadValues = found
                    contentURL = payload
                }
            }
            result[url] = NotchPartialDownload(url: url, expectedURL: expected,
                bytes: payloadValues.isRegularFile == true ? Int64(payloadValues.fileSize ?? 0) : 0,
                resourceID: NotchDownloadSupport.fileIdentity(at: contentURL ?? url),
                modified: payloadValues.contentModificationDate ?? .distantPast,
                contentURL: contentURL)
        }
        // The main queue merges, sorts and compares this list on every
        // progress tick, so a crowded folder hands it only its newest entries.
        if files.count > maximumListedFiles {
            files.sort { $0.date != $1.date ? $0.date > $1.date : $0.url.path < $1.url.path }
            files.removeSubrange(maximumListedFiles...)
        }
        return readFailed ? nil : FolderSnapshot(partials: result, files: files)
    }

    /// Published progress owns its destination until it finishes. Folder files
    /// remain visible after the short completion notice expires.
    static func mergedItems(active: [NotchDownloadItem], files: [NotchDownloadItem],
                            finished: [NotchDownloadItem]) -> [NotchDownloadItem] {
        var seen = Set<URL>()
        let represented = Set(active.flatMap { [$0.url.standardizedFileURL,
            (expectedURL(for: $0.url) ?? $0.url).standardizedFileURL] })
        let candidates = active + files.filter { !represented.contains($0.url.standardizedFileURL) }
            + finished.filter { !represented.contains($0.url.standardizedFileURL) }
        return candidates.filter { seen.insert($0.url.standardizedFileURL).inserted }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.url.path < $1.url.path
        }
    }

    static let maximumObservedFiles = 32
    /// Folder entries the page lists, newest first.
    static let maximumListedFiles = 200
    static let percentSize: CGFloat = 10
    static let compactNameWingThreshold: CGFloat = 94
    private static let compactNameMinimumWing: CGFloat = 64
    private static let compactNameMaximumWing: CGFloat = 160
    /// Progress rounds up to a full hundred near the end, and four of the
    /// languages part the number from its sign, so the narrowest wing cannot
    /// hold the widest reading at full size. It shrinks rather than wrap or
    /// lose a digit.
    static let percentMinimumScale: CGFloat = 0.75

    static func percentFormat(_ language: AppLanguage) -> FloatingPointFormatStyle<Double>.Percent {
        .percent.precision(.fractionLength(0)).locale(Locale(identifier: language.rawValue))
    }

    /// Digits carry no descenders, so their ink is about the cap height.
    static func percentInset(in geometry: NotchGeometry) -> CGFloat {
        geometry.compactActivityEdgeInset(boxHeight: percentSize * 0.72, radius: 0)
    }

    /// Restore the file name only when menus leave a readable wing. Otherwise
    /// the arrow and percent keep their short strip beside the camera.
    static func compactWing(for name: String?, in geometry: NotchGeometry) -> CGFloat {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
              let room = geometry.compactSideRoom, room.isFinite,
              room >= compactNameWingThreshold else { return 56 }
        let provisional = geometry.compactDownloadGeometry(wing: compactNameWingThreshold)
        let icon = min(17, provisional.compactActivityContentHeight - NotchLayout.compactEdgeGap * 2)
        let inset = provisional.compactActivityEdgeInset(boxHeight: icon, radius: icon / 2)
        let title = (name as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium)
        ]).width
        return min(compactNameMaximumWing,
                   max(compactNameMinimumWing, (inset + icon + 6 + title + 4).rounded(.up)))
    }

    static func showsCompactName(in geometry: NotchGeometry) -> Bool {
        geometry.compactActivityWingWidth >= compactNameMinimumWing
    }

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
