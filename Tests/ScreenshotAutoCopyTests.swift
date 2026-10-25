// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production automatic copy against a private cache and a fake
/// pasteboard. Delayed encodes exercise delivery order without desktop access.
enum ScreenshotAutoCopyTests {
    enum ScreenshotSelectionController {
        typealias Capture = Int
    }

    struct Export {
        let image: Int
        let scale: CGFloat
    }

    enum Preferences {
        static let standard = Values()
        final class Values {
            var imageOnly = false
            func bool(forKey key: String) -> Bool {
                key == DefaultsKey.screenshotCopyImageOnly && imageOnly
            }
        }
    }

    enum AppFeature {
        case screenshot
        static var available = true
        var isAvailable: Bool { Self.available }
    }

    enum NSSound {
        static var beeps = 0
        static func beep() { beeps += 1 }
    }

    enum QuickToolHUD {
        static var messages: [String] = []
        static func show(icon: String, message: String) { messages.append(message) }
    }

    final class Pasteboard {
        var changeCount = 0
        var png: Data?
        var url: URL?

        func replace(png: Data?, url: URL? = nil) {
            changeCount += 1
            self.png = png
            self.url = url
        }
    }

    enum NSPasteboard {
        static let general = Pasteboard()
    }

    final class EncodingGate: @unchecked Sendable {
        private let image: Int
        private let lock = NSLock()
        private var entered = false
        let resume = DispatchSemaphore(value: 0)
        var started: Bool { lock.withLock { entered } }

        init(image: Int) { self.image = image }

        func wait(for image: Int) {
            guard image == self.image else { return }
            lock.withLock { entered = true }
            _ = resume.wait(timeout: .now() + 5)
        }
    }

    enum ScreenshotEditorController {
        struct ClipboardPayload: Sendable {
            let png: Data?
            let tiff: Data?
        }

        static var gate: EncodingGate?
        static var accepts = true
        static var attemptedModes: [Bool] = []

        static func clipboardPayload(from export: Export) -> ClipboardPayload {
            gate?.wait(for: export.image)
            return ClipboardPayload(png: Data([UInt8(export.image)]),
                                    tiff: Data([0xff, UInt8(export.image)]))
        }

        static func copyFile(_ url: URL?, payload: ClipboardPayload, imageOnly: Bool) -> Bool {
            attemptedModes.append(imageOnly)
            guard accepts else { return false }
            NSPasteboard.general.replace(png: payload.png, url: url)
            return true
        }
    }

    enum ScreenshotSupport {
        static var folder: URL?
        static var directoryReads = 0
        static var pruned: [URL] = []
        private static let lock = NSLock()
        private static var files: [URL] = []
        static var createdFiles: [URL] { lock.withLock { files } }

        static func copiedFilesDirectory() -> URL? {
            directoryReads += 1
            return folder
        }

        static func fileName(prefix: String, date: Date) -> String { "\(prefix).png" }

        static func copiedFile(data: Data, name: String, directory: URL) throws -> URL {
            let url = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
            try data.write(to: url, options: .atomic)
            lock.withLock { files.append(url) }
            return url
        }

        static func pruneCopiedFiles(in directory: URL, preserving current: URL) {
            pruned.append(current)
        }

        static func reset(folder: URL?) {
            self.folder = folder
            directoryReads = 0
            pruned = []
            lock.withLock { files = [] }
        }
    }

    @MainActor class State {
        typealias UserDefaults = Preferences
        let strings = ScreenshotFeatureStrings.enUS
        var autoCopyTask: Task<Void, Never>?
        var autoCopyGeneration = 0

        nonisolated static func flatten(_ capture: Int, downscaleTo1x: Bool) -> Export? {
            Export(image: capture, scale: 2)
        }
    }

    static func run(_ suite: TestSuite) {
        var completed = false
        let task = Task { @MainActor in
            await checks(suite)
            completed = true
        }
        let deadline = Date().addingTimeInterval(10)
        while !completed && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        if !completed {
            ScreenshotEditorController.gate?.resume.signal()
            task.cancel()
        }
        suite.expect(completed, "automatic screenshot copy checks finish")
    }

    @MainActor private static func reset(folder: URL?, imageOnly: Bool) {
        Preferences.standard.imageOnly = imageOnly
        AppFeature.available = true
        NSSound.beeps = 0
        QuickToolHUD.messages = []
        ScreenshotEditorController.gate = nil
        ScreenshotEditorController.accepts = true
        ScreenshotEditorController.attemptedModes = []
        ScreenshotSupport.reset(folder: folder)
        NSPasteboard.general.replace(png: nil)
    }

    @MainActor private static func started(_ gate: EncodingGate) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while !gate.started && Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return gate.started
    }

    @MainActor private static func checks(_ suite: TestSuite) async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vorssaint-AutoCopy-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            suite.expect(false, "automatic copy creates its private test directory")
            return
        }
        defer {
            ScreenshotEditorController.gate?.resume.signal()
            ScreenshotEditorController.gate = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let pasteboard = NSPasteboard.general

        reset(folder: nil, imageOnly: true)
        let imageService = Service()
        let imageGate = EncodingGate(image: 1)
        ScreenshotEditorController.gate = imageGate
        imageService.autoCopy(1)
        suite.expect(await started(imageGate), "image-only copying starts without a cache directory")
        Preferences.standard.imageOnly = false
        imageGate.resume.signal()
        await imageService.autoCopyTask?.value
        suite.expect(pasteboard.png == Data([1]) && pasteboard.url == nil
                && ScreenshotEditorController.attemptedModes == [true]
                && ScreenshotSupport.directoryReads == 0 && ScreenshotSupport.createdFiles.isEmpty
                && NSSound.beeps == 0,
                     "an image-only copy keeps its selected mode and needs neither a cache nor a file URL")

        reset(folder: directory, imageOnly: false)
        let fileService = Service()
        fileService.autoCopy(2)
        await fileService.autoCopyTask?.value
        let fileURL = pasteboard.url
        let fileData = fileURL.flatMap { try? Data(contentsOf: $0) }
        suite.expect(fileURL != nil && fileData == Data([2]) && pasteboard.png == fileData
                && ScreenshotEditorController.attemptedModes == [false]
                && ScreenshotSupport.pruned == ScreenshotSupport.createdFiles,
                     "file-compatible copying publishes a readable file alongside the same image bytes")

        reset(folder: directory, imageOnly: false)
        let lateService = Service()
        let lateGate = EncodingGate(image: 3)
        ScreenshotEditorController.gate = lateGate
        lateService.autoCopy(3)
        let lateTask = lateService.autoCopyTask
        suite.expect(await started(lateGate), "the raw capture is still encoding when an edit is copied")
        pasteboard.replace(png: Data([30]))
        lateGate.resume.signal()
        await lateTask?.value
        suite.expect(pasteboard.png == Data([30]) && ScreenshotEditorController.attemptedModes.isEmpty
                && ScreenshotSupport.createdFiles.count == 1
                && ScreenshotSupport.createdFiles.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) },
                     "a late automatic copy preserves a newer edited image and removes its unpublished file")

        reset(folder: directory, imageOnly: false)
        let generationService = Service()
        let oldGate = EncodingGate(image: 4)
        ScreenshotEditorController.gate = oldGate
        generationService.autoCopy(4)
        let oldTask = generationService.autoCopyTask
        suite.expect(await started(oldGate), "the first capture stays in its encoder while a second starts")
        generationService.autoCopy(5)
        await generationService.autoCopyTask?.value
        let publishedURL = pasteboard.url
        oldGate.resume.signal()
        await oldTask?.value
        suite.expect(pasteboard.png == Data([5]) && pasteboard.url == publishedURL
                && ScreenshotEditorController.attemptedModes == [false]
                && ScreenshotSupport.createdFiles.count == 2
                && ScreenshotSupport.createdFiles.filter { FileManager.default.fileExists(atPath: $0.path) }
                    == (publishedURL.map { [$0] } ?? []),
                     "a newer generation cancels the slow capture and keeps only the published file")

        reset(folder: nil, imageOnly: true)
        let invalidatedService = Service()
        let invalidatedGate = EncodingGate(image: 8)
        ScreenshotEditorController.gate = invalidatedGate
        invalidatedService.autoCopy(8)
        let invalidatedTask = invalidatedService.autoCopyTask
        suite.expect(await started(invalidatedGate), "an in-flight capture can have its generation invalidated")
        invalidatedService.autoCopyGeneration += 1
        invalidatedGate.resume.signal()
        await invalidatedTask?.value
        suite.expect(pasteboard.png == nil && ScreenshotEditorController.attemptedModes.isEmpty,
                     "an obsolete generation never publishes even when its task was not cancelled")

        reset(folder: nil, imageOnly: true)
        let cancelledService = Service()
        let cancelledGate = EncodingGate(image: 6)
        ScreenshotEditorController.gate = cancelledGate
        cancelledService.autoCopy(6)
        let cancelledTask = cancelledService.autoCopyTask
        suite.expect(await started(cancelledGate), "an image-only capture can be cancelled during encoding")
        cancelledTask?.cancel()
        cancelledGate.resume.signal()
        await cancelledTask?.value
        suite.expect(pasteboard.png == nil && ScreenshotEditorController.attemptedModes.isEmpty
                && NSSound.beeps == 0,
                     "a cancelled image-only capture never publishes or reports a copy failure")

        reset(folder: directory, imageOnly: false)
        ScreenshotEditorController.accepts = false
        let rejectedService = Service()
        rejectedService.autoCopy(7)
        await rejectedService.autoCopyTask?.value
        suite.expect(pasteboard.png == nil && ScreenshotSupport.createdFiles.count == 1
                && ScreenshotSupport.createdFiles.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }
                && ScreenshotSupport.pruned.isEmpty && NSSound.beeps == 1
                && QuickToolHUD.messages.isEmpty,
                     "a refused pasteboard write removes its file and signals failure without reporting success")
    }
}
