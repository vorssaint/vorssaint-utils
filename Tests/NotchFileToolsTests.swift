// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchFileToolsTests {
    static func run(expect: (Bool, String) -> Void) {
        NotchDownloadFolderChoiceTests.run(expect: expect)
        MediaDialogHostTests.run(expect: expect)
        ShelfDragCompletionTests.run(expect: expect)
        let suite = "com.vorssaint.tests.notch-files"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        expect(Defaults.registeredDefaults[DefaultsKey.notchDownloadsEnabled] as? Bool == false,
               "download observation is opt-in")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchDownloadsEnabled),
               "the download preference is portable")
        expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchDownloadsFolderBookmark),
               "folder authority never leaves this Mac in a settings backup")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: DefaultsKey.notchDownloadsEnabled)
        defaults.set(true, forKey: AppFeature.notch.availabilityKey)
        defaults.set(true, forKey: AppFeature.notchDownloads.availabilityKey)
        expect(NotchSupport.routes(.download, in: defaults), "enabled downloads can present in the notch")
        defaults.set("downloads", forKey: DefaultsKey.notchHiddenModules)
        expect(!NotchSupport.routes(.download, in: defaults), "hidden downloads stop automatic presentation")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set(false, forKey: AppFeature.notchDownloads.availabilityKey)
        expect(!NotchSupport.routes(.download, in: defaults), "uninstalled downloads cannot present")

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.notchFiles(language)
            expect(Mirror(reflecting: strings).children.allSatisfy {
                guard let value = $0.value as? String else { return false }
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !value.contains("—")
            }, "file tools and downloads have complete human-facing strings for \(language.rawValue)")
        }
        expect(NotchDownloadSupport.fraction(completed: 30, total: 100, reportedFraction: 0.3,
                                            indeterminate: false) == 0.3,
               "download percent follows the publisher's real progress")
        for total in [Int64(-1), Int64(0)] {
            expect(NotchDownloadSupport.fraction(completed: 30, total: total, reportedFraction: 0.3,
                                                indeterminate: false) == nil,
                   "unknown totals never become a made-up percentage")
        }
        expect(NotchDownloadSupport.fraction(completed: 30, total: 100, reportedFraction: .nan,
                                            indeterminate: false) == nil,
               "invalid published fractions are indeterminate")
        expect(NotchDownloadSupport.fraction(completed: 30, total: 100, reportedFraction: 0.3,
                                            indeterminate: true) == nil,
               "a publisher's indeterminate state is respected")
        let folder = URL(fileURLWithPath: "/tmp/notch-files-download-contract", isDirectory: true)
        let partial = folder.appendingPathComponent("example.crdownload")
        let destination = folder.appendingPathComponent("example")
        expect(NotchDownloadSupport.expectedURL(for: partial) == destination,
               "only the partial suffix is removed when identifying a finished file")
        expect(NotchDownloadSupport.expectedURL(for: folder.appendingPathComponent("photo.jpg")) == nil,
               "ordinary files are never treated as active downloads")
        expect(!NotchDownloadSupport.isDirectChild(folder.appendingPathComponent("private/deeper/file"), of: folder),
               "a selected folder never grants observation of deeper folders")
        let snapshot = NotchPartialDownload(url: partial, expectedURL: destination, bytes: 50,
                                            resourceID: "original", modified: Date())
        expect(NotchDownloadSupport.didFinish(snapshot, at: destination, resourceID: "original"),
               "a renamed partial with the same file identity can complete")
        expect(!NotchDownloadSupport.didFinish(snapshot, at: destination, resourceID: "unrelated")
               && !NotchDownloadSupport.didFinish(snapshot, at: destination, resourceID: nil),
               "deleting a partial cannot claim an unrelated existing file as a completed download")
        expect(!NotchFileToolsSupport.destinationIsOutsideInputs(destination, inputs: [URL(string: "https://example.com/file")!]),
               "remote input URLs cannot reach the file archive process")
        archiveContainmentContracts(expect: expect)
        collisionContracts(expect: expect)
        publicationContracts(expect: expect)
        renamedPublicationContracts(expect: expect)
        archiveCancellationContracts(expect: expect)
        durationLoadingContracts(expect: expect)
        dropGeometryContracts(expect: expect)
        MediaWorkspaceLayoutTests.run(expect: expect)
    }

    private static func dropGeometryContracts(expect: (Bool, String) -> Void) {
        for safeArea: CGFloat in [0, 32] {
            for layout in NotchSize.allCases {
                for width in [360.0, 440, 600] {
                    let geometry = NotchGeometry(screen: CGRect(x: -1440, y: 200, width: 1440, height: 900),
                                                 safeAreaTop: safeArea, cameraWidth: safeArea == 0 ? 0 : 180,
                                                 layout: layout, customWidth: width, customHeight: 400)
                    let size = geometry.expandedSize(module: .files)
                    let area = NotchFileToolsSupport.mediaDropArea(in: geometry, size: size)
                    let content = geometry.contentSize(for: size)
                    expect(area.minX > size.width / 2 && area.maxX == size.width - NotchLayout.horizontalInset,
                           "the media target is confined to the right-hand card at every island width")
                    expect(area.minY == geometry.safeContentTop + NotchLayout.headerHeight + NotchLayout.spacing
                           && area.maxY == size.height - NotchLayout.bottomInset,
                           "the target excludes the header and margins on both physical and simulated cutouts")
                    expect(area.width * 2 + NotchFileToolsSupport.dropSpacing == content.width && area.height == content.height,
                           "native hit testing and the two equal SwiftUI cards share the same content bounds")
                }
            }
        }
    }

    private static func archiveContainmentContracts(expect: (Bool, String) -> Void) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("notch-containment-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }
        do {
            let source = root.appendingPathComponent("OriginalCase", isDirectory: true)
            try manager.createDirectory(at: source, withIntermediateDirectories: true)
            let input = source.appendingPathComponent("source.txt")
            try Data("original".utf8).write(to: input)
            expect(!NotchFileToolsSupport.destinationIsOutsideInputs(source.appendingPathComponent("inside.zip"), inputs: [source]),
                   "an archive cannot write its output inside its source directory")
            expect(NotchFileToolsSupport.destinationIsOutsideInputs(source.appendingPathComponent("other.zip"), inputs: [input]),
                   "an archive can be saved beside the selected file")
            let alias = root.appendingPathComponent("originalcase", isDirectory: true)
            if manager.fileExists(atPath: alias.path) {
                expect(!NotchFileToolsSupport.destinationIsOutsideInputs(alias.appendingPathComponent("inside.zip"), inputs: [source])
                       && !NotchFileToolsSupport.destinationIsOutsideInputs(alias, inputs: [source]),
                       "case-insensitive path aliases cannot put an archive inside its own source")
            }
            let link = root.appendingPathComponent("linked", isDirectory: true)
            try manager.createSymbolicLink(at: link, withDestinationURL: source)
            expect(!NotchFileToolsSupport.destinationIsOutsideInputs(link.appendingPathComponent("inside.zip"), inputs: [source]),
                   "a symbolic link cannot bypass archive containment")
        } catch { expect(false, "archive containment fixtures: \(error)") }
    }

    private static func publicationContracts(expect: (Bool, String) -> Void) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("notch-progress-contract-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("watched", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent("result.bin")
            let published = Progress(totalUnitCount: 10)
            published.kind = .file
            published.fileOperationKind = .downloading
            published.fileURL = destination
            var publication = NotchDownloadPublication(NotchDownloadProgressSnapshot(published), folder: folder)!
            published.completedUnitCount = 5
            expect(publication.item(NotchDownloadProgressSnapshot(published), folder: folder)?.fraction == 0.5,
                   "a live Progress contributes its actual fraction inside the selected folder")
            published.completedUnitCount = 10
            let missing = publication.item(NotchDownloadProgressSnapshot(published), folder: folder)
            expect(missing?.completed == false && missing?.fraction == nil && missing?.active == false,
                   "finished units without a final file cannot show completion or a misleading 100 percent")
            try Data(repeating: 1, count: 10).write(to: destination)
            expect(publication.item(NotchDownloadProgressSnapshot(published), folder: folder)?.completed == true,
                   "a newly materialized final file can confirm the publisher's completed download")

            published.completedUnitCount = 0
            publication = NotchDownloadPublication(NotchDownloadProgressSnapshot(published), folder: folder)!
            published.completedUnitCount = 10
            expect(publication.item(NotchDownloadProgressSnapshot(published), folder: folder)?.completed == false,
                   "an unchanged pre-existing destination is not evidence of a successful new download")
            try Data(repeating: 2, count: 12).write(to: destination)
            expect(publication.item(NotchDownloadProgressSnapshot(published), folder: folder)?.completed == true,
                   "a changed destination distinguishes actual completed work from an unrelated existing file")

            let outside = root.appendingPathComponent("outside.bin")
            try Data(repeating: 3, count: 20).write(to: outside)
            published.fileURL = outside
            expect(publication.item(NotchDownloadProgressSnapshot(published), folder: folder) == nil,
                   "a mutable Progress URL cannot move a completion outside the selected folder")
            published.fileURL = URL(string: "https://example.invalid/result.bin")
            expect(publication.item(NotchDownloadProgressSnapshot(published), folder: folder) == nil,
                   "a file publication cannot turn into a remote item after acceptance")
            published.fileURL = folder.appendingPathComponent("deeper/result.bin")
            expect(publication.item(NotchDownloadProgressSnapshot(published), folder: folder) == nil,
                   "a mutable file publication does not grant access to descendants")

            let redirected = folder.appendingPathComponent("redirected.bin")
            try fm.createSymbolicLink(at: redirected, withDestinationURL: outside)
            published.fileURL = redirected
            expect(publication.item(NotchDownloadProgressSnapshot(published), folder: folder) == nil,
                   "a direct child symlink cannot redirect file evidence outside folder authority")
            published.fileURL = destination
            published.fileOperationKind = .copying
            expect(publication.item(NotchDownloadProgressSnapshot(published), folder: folder) == nil,
                   "a publisher that changes operation kind is no longer treated as a download")
            published.fileOperationKind = .downloading
            published.cancel()
            expect(publication.item(NotchDownloadProgressSnapshot(published), folder: folder) == nil,
                   "cancelled work never gains a completion from a file left on disk")

            let renamed = Progress(totalUnitCount: 10)
            renamed.kind = .file
            renamed.fileOperationKind = .receiving
            renamed.fileURL = folder.appendingPathComponent("first-name.bin")
            var moved = NotchDownloadPublication(NotchDownloadProgressSnapshot(renamed), folder: folder)!
            renamed.fileURL = destination
            renamed.completedUnitCount = 10
            expect(moved.item(NotchDownloadProgressSnapshot(renamed), folder: folder)?.completed == false,
                   "renaming a publication to an already present file cannot borrow its completed state")
            renamed.completedUnitCount = 0
            let newName = folder.appendingPathComponent("second-name.bin")
            renamed.fileURL = newName
            expect(moved.item(NotchDownloadProgressSnapshot(renamed), folder: folder)?.active == true,
                   "a new valid destination can be observed while the transfer is still running")
            try Data(repeating: 4, count: 10).write(to: newName)
            renamed.completedUnitCount = 10
            expect(moved.item(NotchDownloadProgressSnapshot(renamed), folder: folder)?.completed == true,
                   "a renamed publication completes only with new evidence for its new destination")
            renamed.completedUnitCount = 0
            let partial = folder.appendingPathComponent("result.part")
            renamed.fileURL = partial
            var partialPublication = NotchDownloadPublication(NotchDownloadProgressSnapshot(renamed), folder: folder)!
            try Data(repeating: 5, count: 10).write(to: partial)
            renamed.completedUnitCount = 10
            expect(partialPublication.item(NotchDownloadProgressSnapshot(renamed), folder: folder)?.completed == false,
                   "a remaining partial file never becomes a final download just because its counter finishes")
        } catch { expect(false, "published download fixture failed: \(error)") }
    }

    private static func renamedPublicationContracts(expect: (Bool, String) -> Void) {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("notch-renamed-progress-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: folder) }
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for existsInitially in [false, true] {
                for callbackOrder in 0..<3 {
                    let temporary = folder.appendingPathComponent(UUID().uuidString + ".tmp")
                    let final = temporary.deletingPathExtension().appendingPathExtension("bin")
                    if existsInitially { try Data(repeating: 1, count: 10).write(to: temporary) }
                    let progress = Progress(totalUnitCount: 10)
                    progress.kind = .file
                    progress.fileOperationKind = .downloading
                    progress.fileURL = temporary
                    progress.completedUnitCount = 5
                    var publication = NotchDownloadPublication(NotchDownloadProgressSnapshot(progress), folder: folder)!
                    if !existsInitially {
                        try Data(repeating: 1, count: 10).write(to: temporary)
                        _ = publication.item(NotchDownloadProgressSnapshot(progress), folder: folder)
                    }
                    let identity = NotchDownloadSupport.fileIdentity(at: temporary)
                    try manager.moveItem(at: temporary, to: final)
                    if callbackOrder == 1 {
                        progress.completedUnitCount = 10
                        expect(publication.item(NotchDownloadProgressSnapshot(progress), folder: folder)?.completed == false,
                               "finished units wait for the renamed destination instead of using a vanished path")
                    }
                    progress.fileURL = final
                    if callbackOrder == 2 {
                        expect(publication.item(NotchDownloadProgressSnapshot(progress), folder: folder)?.completed == false,
                               "a proven rename still waits for the publisher to finish")
                    }
                    progress.completedUnitCount = 10
                    let item = publication.item(NotchDownloadProgressSnapshot(progress), folder: folder)
                    expect(identity == NotchDownloadSupport.fileIdentity(at: final)
                           && item?.completed == true && item?.fraction == 1 && item?.active == false,
                           "a completed file rename is recognized across URL and progress callback ordering")
                    expect(publication.item(NotchDownloadProgressSnapshot(progress), folder: folder)?.completed == true,
                           "completion evidence survives the later unpublication read")
                }
            }

            let source = folder.appendingPathComponent("still-present.tmp")
            let alias = folder.appendingPathComponent("existing-link.bin")
            try Data(repeating: 2, count: 10).write(to: source)
            try manager.linkItem(at: source, to: alias)
            let progress = Progress(totalUnitCount: 10)
            progress.kind = .file
            progress.fileOperationKind = .receiving
            progress.fileURL = source
            var publication = NotchDownloadPublication(NotchDownloadProgressSnapshot(progress), folder: folder)!
            progress.fileURL = alias
            progress.completedUnitCount = 10
            expect(publication.item(NotchDownloadProgressSnapshot(progress), folder: folder)?.completed == false,
                   "an existing hard link is not evidence of a rename while the source remains")

            let unrelated = folder.appendingPathComponent("unrelated.bin")
            try Data(repeating: 3, count: 10).write(to: unrelated)
            progress.completedUnitCount = 0
            progress.fileURL = source
            publication = NotchDownloadPublication(NotchDownloadProgressSnapshot(progress), folder: folder)!
            try manager.removeItem(at: source)
            progress.fileURL = unrelated
            progress.completedUnitCount = 10
            expect(publication.item(NotchDownloadProgressSnapshot(progress), folder: folder)?.completed == false,
                   "deleting a known source cannot turn an unrelated destination into a completed download")
        } catch { expect(false, "renamed download fixtures failed: \(error)") }
    }

    private final class ArchiveOutcome: @unchecked Sendable {
        // Written by the archive lane, read only after its completion semaphore.
        var cancelled = false
        var staged: URL?
    }

    private static func archiveCancellationContracts(expect: (Bool, String) -> Void) {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("notch-archive-stop-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: folder) }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let input = folder.appendingPathComponent("input.txt")
            let output = folder.appendingPathComponent("result.zip")
            try Data("fixture".utf8).write(to: input)
            let successful = NotchArchiveOperation()
            try successful.archive(input, to: output)
            expect(try Data(contentsOf: output).prefix(2) == Data([0x50, 0x4B]),
                   "the real archive operation produces a complete ZIP for an isolated input")
            let original = try Data(contentsOf: output)
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/bin/sh")
            child.arguments = ["-c", "trap '' TERM; exec /bin/sleep 30"]
            let outcome = ArchiveOutcome()
            let operation = NotchArchiveOperation { _, staged, _ in
                outcome.staged = staged
                return child
            }
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                do { try operation.archive(input, to: output) }
                catch is CancellationError { outcome.cancelled = true }
                catch {}
                finished.signal()
            }
            let launchDeadline = Date().addingTimeInterval(2)
            while !child.isRunning, Date() < launchDeadline { Thread.sleep(forTimeInterval: 0.01) }
            expect(child.isRunning, "the cancellation fixture owns a running child")
            operation.cancel(immediately: true)
            let stopped = finished.wait(timeout: .now() + 3) == .success
            expect(stopped && !child.isRunning,
                   "immediate stop terminates an owned child without requiring a future main-loop callback")
            if stopped {
                expect(outcome.cancelled, "a terminated archive is reported as cancelled")
                expect(outcome.staged.map { !fm.fileExists(atPath: $0.deletingLastPathComponent().path) } == true,
                       "archive cancellation removes its private staged directory")
            }
            expect(try Data(contentsOf: output) == original, "cancellation cannot overwrite a previously completed archive")
            var madeProcess = false
            let neverStarted = NotchArchiveOperation { _, _, _ in madeProcess = true; return Process() }
            neverStarted.cancel(immediately: true)
            do {
                try neverStarted.archive(input, to: folder.appendingPathComponent("cancelled.zip"))
                expect(false, "a stopped archive cannot restart")
            } catch is CancellationError {
                expect(!madeProcess, "stopping a queued operation prevents even preparing its child")
            }
        } catch { expect(false, "archive cancellation fixture failed: \(error)") }
    }

    private static func durationLoadingContracts(expect: (Bool, String) -> Void) {
        let first = URL(fileURLWithPath: "/tmp/first-duration-fixture.mov")
        let second = URL(fileURLWithPath: "/tmp/second-duration-fixture.mov")
        var loading = MediaDurationLoading()
        let cancelled = loading.start(url: first, tool: .videoCompressor)!
        loading.cancel()
        expect(loading.finish(cancelled, duration: 10) == nil,
               "a duration reply cannot apply after its view has cancelled the lookup")
        let resumed = loading.start(url: first, tool: .videoCompressor)!
        expect(resumed != cancelled && loading.finish(resumed, duration: 120.25) == 120.3,
               "reopening the same input retries a cancelled duration lookup with a new identity")
        loading.cancel()
        expect(loading.start(url: first, tool: .videoCompressor) == nil,
               "reopening after a successful lookup preserves the user's trim instead of reapplying defaults")
        loading.reset()
        let replaced = loading.start(url: first, tool: .videoCompressor)!
        let replacement = loading.start(url: second, tool: .videoCompressor)!
        expect(loading.finish(replaced, duration: 15) == nil && loading.finish(replacement, duration: 300) == 300,
               "an older input cannot replace the duration of the newly selected video")
        let gif = loading.start(url: second, tool: .gifMaker)!
        expect(loading.finish(gif, duration: nil) == nil,
               "an unavailable duration never marks media defaults as loaded")
        let retry = loading.start(url: second, tool: .gifMaker)!
        expect(loading.finish(retry, duration: .infinity) == nil,
               "a non-finite duration remains retryable")
        expect(loading.start(url: first, tool: .textExtractor) == nil && loading.pending == nil,
               "switching to a non-video tool invalidates pending video defaults")
        let untrimmed = MediaSupport.sanitizedTrim(start: 0, end: 0, assetDuration: 300)
        expect(untrimmed.start == 0 && untrimmed.end == 300,
               "a new input's cleared range exports the full recording while its duration lookup is pending")
    }

    private static func collisionContracts(expect: (Bool, String) -> Void) {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("notch-output-contract-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: directory) }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let existing = directory.appendingPathComponent("original.txt")
            let staged = directory.appendingPathComponent("new.txt")
            try Data("original".utf8).write(to: existing)
            try Data("generated".utf8).write(to: staged)
            let stagedIdentity = NotchDownloadSupport.fileIdentity(at: staged)
            expect(stagedIdentity != nil && stagedIdentity != NotchDownloadSupport.fileIdentity(at: existing),
                   "file identities distinguish unrelated files without relying on description strings")
            do {
                try MediaSupport.installStagedOutput(staged, at: existing, replacingExisting: false)
                expect(false, "an output collision must fail")
            } catch {
                expect(try Data(contentsOf: existing) == Data("original".utf8),
                       "archive and shelf media outputs preserve a colliding original")
                expect(fm.fileExists(atPath: staged.path), "a rejected install leaves staged data available for cleanup")
            }
            let newOutput = directory.appendingPathComponent("new-output.txt")
            try MediaSupport.installStagedOutput(staged, at: newOutput, replacingExisting: false)
            expect(try Data(contentsOf: newOutput) == Data("generated".utf8),
                   "a unique shelf output is installed intact")
            expect(!fm.fileExists(atPath: staged.path), "installing output does not retain a redundant staged copy")
            expect(NotchDownloadSupport.fileIdentity(at: newOutput) == stagedIdentity,
                   "a real filesystem rename preserves the identity used by download completion")
        } catch { expect(false, "file output contract fixture failed: \(error)") }
    }
}
