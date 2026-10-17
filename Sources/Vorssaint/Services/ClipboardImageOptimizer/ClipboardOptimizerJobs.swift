// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Darwin
import Foundation
import ImageIO

/// The folder optimized files live in, and the only code that deletes from it.
enum ClipboardOptimizerStore {
    typealias Files = ClipboardOptimizerFileSupport

    static var rootURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("ClipboardOptimizer", isDirectory: true)
    }

    static let sourceFileName = ".source"

    /// A fresh `<root>/<uuid>` folder for one job. It remembers the copied
    /// file, so history can point back at it once the copy is deleted.
    static func makeJobDirectory(source: URL) -> URL? {
        guard let root = rootURL else { return nil }
        let job = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard PrivateFileStore.createDirectory(at: job),
              PrivateFileStore.write(Data(source.standardizedFileURL.path.utf8),
                                     to: job.appendingPathComponent(sourceFileName))
        else { return nil }
        return job
    }

    static func jobs() -> [Files.StoredJob] {
        guard let root = rootURL,
              let dirs = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles])
        else { return [] }
        return dirs.compactMap { dir in
            let values = try? dir.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey])
            guard values?.isDirectory == true else { return nil }
            return Files.StoredJob(url: dir, created: values?.creationDate ?? .distantPast, bytes: bytes(in: dir))
        }
    }

    static func bytes(in dir: URL) -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: [])) ?? []
        return files.reduce(Int64(0)) {
            $0 + Int64((try? $1.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
    }

    static func totalBytes(protected: Set<String>) -> (all: Int64, protected: Int64) {
        let all = jobs()
        let kept = Set(Files.clearCandidates(all, protected: [])).subtracting(Files.clearCandidates(all, protected: protected))
        return (all.reduce(0) { $0 + $1.bytes }, all.filter { kept.contains($0.url) }.reduce(0) { $0 + $1.bytes })
    }

    /// Each returns the removed copies mapped to the files they came from.
    @discardableResult
    static func sweep(protected: Set<String>, referenced: Set<String>, now: Date = Date()) -> [String: String] {
        remove(Files.sweepCandidates(jobs(), now: now, protected: protected, referenced: referenced,
                                     policy: Files.SweepPolicy()))
    }

    @discardableResult
    static func clear(protected: Set<String>) -> [String: String] {
        remove(Files.clearCandidates(jobs(), protected: protected))
    }

    @discardableResult
    static func remove(_ urls: [URL]) -> [String: String] {
        guard let root = rootURL else { return [:] }
        var originals: [String: String] = [:]
        for url in urls where Files.isOwnOutput(url.appendingPathComponent("x"), root: root) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            if let source = try? String(contentsOf: url.appendingPathComponent(sourceFileName), encoding: .utf8),
               FileManager.default.fileExists(atPath: source) {
                for name in names where !name.hasPrefix(".") {
                    originals[url.appendingPathComponent(name).standardizedFileURL.path] = source
                }
            }
            try? FileManager.default.removeItem(at: url)
        }
        return originals
    }

    // MARK: Encoder processes

    static let pidFileName = ".avconvert.pid"

    static func recordProcess(_ process: Process, in job: URL) {
        PrivateFileStore.write(Data("\(process.processIdentifier)".utf8),
                               to: job.appendingPathComponent(pidFileName))
    }

    /// After a crash an encoder can outlive the app. Kill it only if that pid
    /// still runs avconvert, since pids are reused.
    /// A job that never produced its final file (quit or crash mid-encode)
    /// holds only hidden partial files. Called at start, before any new job.
    static func removeIncompleteJobs() {
        _ = remove(jobs().map(\.url).filter { dir in
            ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
                .allSatisfy { $0.hasPrefix(".") }
        })
    }

    static func killOrphanedEncoders() {
        for job in jobs() {
            let file = job.url.appendingPathComponent(pidFileName)
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0,
               String(cString: buffer) == MediaVideoEncoder.avconvertURL.path {
                kill(pid, SIGKILL)
            }
            try? FileManager.default.removeItem(at: file)
        }
    }
}

/// Turns one copied file into a smaller one inside a job folder. Runs on the
/// optimizer's job queue; never touches the pasteboard or the main thread.
enum ClipboardFileOptimizer {
    typealias Files = ClipboardOptimizerFileSupport

    enum Failure: Error, Equatable {
        case cancelled, skipped(String), failed(String)
    }

    struct Result: Equatable {
        let url: URL
        let originalBytes: Int64
        let outputBytes: Int64
    }

    /// Checks shared by every kind, before a byte of the file is read.
    static func preflight(_ url: URL, capMB: Int, job: URL) throws -> Int64 {
        guard Files.isAvailableLocally(url) else { throw Failure.skipped("not downloaded") }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true else { throw Failure.skipped("not a file") }
        let bytes = Int64(values?.fileSize ?? 0)
        switch Files.sizeGate(bytes: bytes, capMB: capMB) {
        case .ok: break
        default: throw Failure.skipped("size")
        }
        let free = (try? job.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        guard Files.hasRoom(freeBytes: free, sourceBytes: bytes) else { throw Failure.skipped("disk space") }
        return bytes
    }

    /// Moves the checked partial file to its final name, with the original's
    /// permissions so a pasted copy behaves like the file that was copied.
    static func finish(partial: URL, output: URL, source: URL) throws -> Int64 {
        try FileManager.default.moveItem(at: partial, to: output)
        if let mode = (try? FileManager.default.attributesOfItem(atPath: source.path))?[.posixPermissions] {
            try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: output.path)
        }
        return Int64((try? output.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    static func worthKeeping(original: Int64, output: Int64) -> Bool {
        ClipboardImageOptimizerSupport.shouldReplace(originalBytes: Int(clamping: original),
                                                     encodedBytes: Int(clamping: output))
    }

    // MARK: Video

    struct VideoFacts {
        let duration: Double
        let hasVideo: Bool
        let displaySize: CGSize
    }

    /// Loads what the gates need, giving up rather than waiting forever on a
    /// file AVFoundation cannot make sense of.
    static func videoFacts(_ url: URL, timeout: TimeInterval = 10) -> VideoFacts? {
        let asset = AVURLAsset(url: url)
        let semaphore = DispatchSemaphore(value: 0)
        let box = FactsBox()
        Task {
            defer { semaphore.signal() }
            guard let (duration, tracks) = try? await asset.load(.duration, .tracks) else { return }
            let video = tracks.first { $0.mediaType == .video }
            var size = CGSize.zero
            if let video, let (natural, transform) = try? await video.load(.naturalSize, .preferredTransform) {
                let rect = CGRect(origin: .zero, size: natural).applying(transform)
                size = CGSize(width: abs(rect.width), height: abs(rect.height))
            }
            box.set(VideoFacts(duration: duration.seconds, hasVideo: video != nil, displaySize: size))
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        return box.get()
    }

    private final class FactsBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: VideoFacts?
        func set(_ facts: VideoFacts) { lock.lock(); value = facts; lock.unlock() }
        func get() -> VideoFacts? { lock.lock(); defer { lock.unlock() }; return value }
    }

    static func optimizeVideo(_ source: URL, options: Files.VideoOptions, job: URL,
                              isCancelled: @escaping () -> Bool,
                              launched: @escaping (Process) -> Void) throws -> Result {
        let original = try preflight(source, capMB: options.maxMB, job: job)
        guard let facts = videoFacts(source), facts.hasVideo else { throw Failure.skipped("no video") }
        guard Files.durationGate(seconds: facts.duration, capMinutes: options.maxMinutes) == .ok else {
            throw Failure.skipped("duration")
        }
        let output = Files.outputURL(root: job.deletingLastPathComponent(), id: UUID(uuidString: job.lastPathComponent)
                                     ?? UUID(), source: source, outputExtension: nil)
        let partial = Files.partialURL(for: output)
        let longEdge = Int(max(facts.displaySize.width, facts.displaySize.height))
        let target = options.maxDimension > 0 ? min(options.maxDimension, longEdge) : longEdge
        let preset = MediaVideoEncoder.avconvertPreset(codec: options.codec, maxDimension: target,
                                                       quality: options.quality)
        do {
            try MediaVideoEncoder.run(
                arguments: MediaVideoEncoder.avconvertArguments(
                    input: source, output: partial, preset: preset, trim: nil,
                    multiPass: MediaVideoEncoder.wantsMultiPass(quality: options.quality)),
                launch: { process in
                    guard !isCancelled() else { throw Failure.cancelled }
                    try process.run()
                    launched(process)
                    ClipboardOptimizerStore.recordProcess(process, in: job)
                },
                isCancelled: isCancelled, tick: {})
        } catch MediaVideoEncoder.RunError.cancelled {
            throw Failure.cancelled
        } catch MediaVideoEncoder.RunError.failed(let message) {
            throw Failure.failed(message)
        }
        try? FileManager.default.removeItem(at: job.appendingPathComponent(ClipboardOptimizerStore.pidFileName))
        if options.removeAudio {
            try dropAudio(partial, isCancelled: isCancelled)
        }
        guard !isCancelled() else { throw Failure.cancelled }
        guard let result = videoFacts(partial),
              Files.validVideo(sourceDuration: facts.duration, outputDuration: result.duration,
                               hasVideo: result.hasVideo) else { throw Failure.failed("incomplete output") }
        let size = Int64((try? partial.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        guard worthKeeping(original: original, output: size) else { throw Failure.skipped("not smaller") }
        return Result(url: output, originalBytes: original,
                      outputBytes: try finish(partial: partial, output: output, source: source))
    }

    /// Copies the video track alone into a new file, without re-encoding.
    static func dropAudio(_ url: URL, isCancelled: @escaping () -> Bool) throws {
        let asset = AVURLAsset(url: url)
        let composition = AVMutableComposition()
        let semaphore = DispatchSemaphore(value: 0)
        let inserted = InsertBox()
        Task {
            defer { semaphore.signal() }
            guard let (duration, tracks) = try? await asset.load(.duration, .tracks),
                  let video = tracks.first(where: { $0.mediaType == .video }),
                  let track = composition.addMutableTrack(withMediaType: .video,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid),
                  (try? track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: video, at: .zero))
                    != nil
            else { return }
            track.preferredTransform = (try? await video.load(.preferredTransform)) ?? .identity
            inserted.set()
        }
        guard semaphore.wait(timeout: .now() + 30) == .success, inserted.value,
              let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
        else { throw Failure.failed("audio") }
        let silent = url.deletingLastPathComponent().appendingPathComponent(".silent." + url.pathExtension)
        try? FileManager.default.removeItem(at: silent)
        session.outputURL = silent
        session.outputFileType = url.pathExtension.lowercased() == "mov" ? .mov
            : url.pathExtension.lowercased() == "m4v" ? .m4v : .mp4
        let done = DispatchSemaphore(value: 0)
        session.exportAsynchronously { done.signal() }
        while done.wait(timeout: .now() + 0.1) == .timedOut {
            if isCancelled() { session.cancelExport() }
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: silent)
            throw isCancelled() ? Failure.cancelled : Failure.failed("audio")
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: silent)
    }

    private final class InsertBox: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func set() { lock.lock(); done = true; lock.unlock() }
        var value: Bool { lock.lock(); defer { lock.unlock() }; return done }
    }

    // MARK: PDF

    static func optimizePDF(_ source: URL, options: Files.PDFOptions, job: URL,
                            isCancelled: () -> Bool) throws -> Result {
        let original = try preflight(source, capMB: options.maxMB, job: job)
        let output = Files.outputURL(root: job.deletingLastPathComponent(),
                                     id: UUID(uuidString: job.lastPathComponent) ?? UUID(),
                                     source: source, outputExtension: nil)
        let partial = Files.partialURL(for: output)
        do {
            try MediaPDFCompressor.rewrite(source: source, to: partial, settings: options.settings,
                                           filterName: Files.pdfFilterName, scratchDirectory: job,
                                           isCancelled: isCancelled)
        } catch let failure as MediaPDFCompressor.Failure {
            switch failure {
            case .unreadable: throw Failure.skipped("unreadable")
            case .protected: throw Failure.skipped("protected")
            case .empty: throw Failure.skipped("empty")
            case .cancelled: throw Failure.cancelled
            case .filter: throw Failure.failed("filter")
            case .incompleteOutput: throw Failure.failed("incomplete output")
            }
        }
        let size = Int64((try? partial.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        guard worthKeeping(original: original, output: size) else { throw Failure.skipped("not smaller") }
        return Result(url: output, originalBytes: original,
                      outputBytes: try finish(partial: partial, output: output, source: source))
    }

    // MARK: Converted images

    static func convertImage(_ source: URL, options: ClipboardImageOptimizerSupport.Options, job: URL,
                             isCancelled: () -> Bool) throws -> Result {
        let original = try preflight(source, capMB: ClipboardImageOptimizerSupport.maxBytes / (1024 * 1024),
                                     job: job)
        guard let data = try? Data(contentsOf: source), !isCancelled() else {
            throw isCancelled() ? Failure.cancelled : Failure.skipped("unreadable")
        }
        guard let output = ClipboardImageOptimizerEncoding.convert(data: data, options: options,
                                                                   isCancelled: isCancelled)
        else { throw isCancelled() ? Failure.cancelled : Failure.skipped("image") }
        let ext = output.type == "public.jpeg" ? "jpg" : "png"
        let url = Files.outputURL(root: job.deletingLastPathComponent(),
                                  id: UUID(uuidString: job.lastPathComponent) ?? UUID(),
                                  source: source, outputExtension: ext)
        let partial = Files.partialURL(for: url)
        guard PrivateFileStore.write(output.data, to: partial),
              let check = CGImageSourceCreateWithURL(partial as CFURL, nil),
              let info = CGImageSourceCopyPropertiesAtIndex(check, 0, nil) as? [CFString: Any],
              let width = info[kCGImagePropertyPixelWidth] as? Int,
              let height = info[kCGImagePropertyPixelHeight] as? Int,
              abs(max(width, height) - output.longEdge) <= 1
        else { throw Failure.failed("incomplete output") }
        return Result(url: url, originalBytes: original,
                      outputBytes: try finish(partial: partial, output: url, source: source))
    }
}
