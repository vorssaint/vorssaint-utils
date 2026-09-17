// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum RecentCaptureStoreTests {
    static func run(expect: (Bool, String) -> Void) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("RecentCaptureStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }
        do {
            let fresh = RecentCaptureStore(directoryURL: root)
            expect(fresh.loadIfNeeded() && fresh.entries.isEmpty && fresh.persist(),
                   "a new capture history can create its first index")
            let id = UUID()
            let screenshot = root.appendingPathComponent("\(id.uuidString).png")
            let thumbnail = root.appendingPathComponent("\(id.uuidString)-thumbnail.png")
            let index = root.appendingPathComponent("history.json")
            let unrelated = root.appendingPathComponent("Notes.txt")
            let png = Data(base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aE1sAAAAASUVORK5CYII=")!
            try RecentCaptureStore.write(png, to: screenshot)
            try RecentCaptureStore.write(png, to: thumbnail)
            try Data("keep".utf8).write(to: unrelated)
            let entry = RecentCaptureEntry(
                id: id, kind: .screenshot, createdAt: Date(timeIntervalSince1970: 1),
                screenshotName: screenshot.lastPathComponent, recordingPath: nil,
                thumbnailName: thumbnail.lastPathComponent, scale: 2,
                anchorX: 0, anchorY: 0, anchorWidth: 1, anchorHeight: 1)
            fresh.entries = [entry]
            expect(fresh.persist(), "a capture is committed before old files can be cleaned")
            let validIndex = try Data(contentsOf: index)
            let healthy = RecentCaptureStore(directoryURL: root)
            expect(healthy.loadIfNeeded() && healthy.entries == [entry] && healthy.persist(),
                   "a readable capture history survives reload unchanged")
            expect((try? Data(contentsOf: screenshot)) == png && (try? Data(contentsOf: thumbnail)) == png,
                   "a valid index retains the full capture and thumbnail")
            let directoryMode = try manager.attributesOfItem(atPath: root.path)[.posixPermissions] as? Int
            let indexMode = try manager.attributesOfItem(atPath: index.path)[.posixPermissions] as? Int
            expect(directoryMode == 0o700 && indexMode == 0o600,
                   "capture history stays private to its owner")

            let corrupt = Data("{broken history".utf8)
            try corrupt.write(to: index)
            let unreadable = RecentCaptureStore(directoryURL: root)
            expect(!unreadable.loadIfNeeded() && !unreadable.persist(),
                   "a corrupt index permits neither cleanup nor replacement with an empty history")
            expect((try? Data(contentsOf: index)) == corrupt
                    && (try? Data(contentsOf: screenshot)) == png
                    && (try? Data(contentsOf: thumbnail)) == png,
                   "failed decoding preserves the original index and intact capture files")
            try validIndex.write(to: index)
            expect(unreadable.loadIfNeeded() && unreadable.entries == [entry],
                   "a failed load can retry after the index becomes readable")

            try manager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: index.path)
            let deniedRead = RecentCaptureStore(directoryURL: root)
            expect(!deniedRead.loadIfNeeded() && !deniedRead.persist()
                    && (try? Data(contentsOf: screenshot)) == png,
                   "a denied index read preserves captures and blocks replacement")
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: index.path)
            expect(deniedRead.loadIfNeeded() && deniedRead.entries == [entry],
                   "restored index access allows the same store to retry")

            try manager.removeItem(at: index)
            let missing = RecentCaptureStore(directoryURL: root)
            expect(!missing.loadIfNeeded() && !missing.persist()
                    && manager.fileExists(atPath: screenshot.path),
                   "a missing index with existing captures never authorizes a new empty history")

            try manager.createDirectory(at: index, withIntermediateDirectories: false)
            let blockedIndex = index.appendingPathComponent("keep")
            try validIndex.write(to: blockedIndex)
            let failedRead = RecentCaptureStore(directoryURL: root)
            expect(!failedRead.loadIfNeeded() && !failedRead.persist(),
                   "an index read error remains distinct from an absent history")
            unreadable.entries = []
            expect(!unreadable.persist()
                    && (try? Data(contentsOf: screenshot)) == png
                    && (try? Data(contentsOf: thumbnail)) == png
                    && (try? Data(contentsOf: blockedIndex)) == validIndex,
                   "failed persistence never deletes captures from the previously committed history")
            try manager.removeItem(at: index)
            try validIndex.write(to: index)
            expect(unreadable.persist()
                    && !manager.fileExists(atPath: screenshot.path)
                    && !manager.fileExists(atPath: thumbnail.path)
                    && manager.fileExists(atPath: unrelated.path),
                   "retrying an explicit removal cleans only owned images after a successful save")

            let video = root.appendingPathComponent("Original.mov")
            try Data("original video".utf8).write(to: video)
            let recordingID = UUID()
            let recordingThumbnail = root.appendingPathComponent("\(recordingID.uuidString)-thumbnail.png")
            try RecentCaptureStore.write(png, to: recordingThumbnail)
            unreadable.entries = [RecentCaptureEntry(
                id: recordingID, kind: .recording, createdAt: Date(),
                screenshotName: nil, recordingPath: video.path,
                thumbnailName: recordingThumbnail.lastPathComponent, scale: nil,
                anchorX: nil, anchorY: nil, anchorWidth: nil, anchorHeight: nil)]
            expect(unreadable.persist(), "a recording history entry can be saved")
            unreadable.entries = []
            expect(unreadable.persist() && manager.fileExists(atPath: video.path)
                    && !manager.fileExists(atPath: recordingThumbnail.path),
                   "clearing recording history keeps the original video")

            let link = root.appendingPathComponent("\(UUID().uuidString).png")
            try manager.createSymbolicLink(at: link, withDestinationURL: unrelated)
            expect(unreadable.persist() && manager.fileExists(atPath: link.path)
                    && (try? String(contentsOf: unrelated, encoding: .utf8)) == "keep",
                   "orphan cleanup never follows symbolic links")
            try manager.removeItem(at: index)
            try manager.createSymbolicLink(at: index, withDestinationURL: unrelated)
            let linkedIndex = RecentCaptureStore(directoryURL: root)
            expect(!linkedIndex.loadIfNeeded() && !linkedIndex.persist()
                    && (try? String(contentsOf: unrelated, encoding: .utf8)) == "keep",
                   "a symbolic index never grants permission to overwrite its target")
        } catch {
            expect(false, "capture history storage fixtures: \(error)")
        }
    }
}
