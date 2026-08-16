// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

typealias VideoDownloaderArtworkFetching = (URL, TimeInterval, () -> Bool) -> Data?

private enum VideoDownloaderProcessTermination: Equatable {
    case failedToStart
    case exited(Int32)
    case timedOut
}

/// Control-flow errors for optional embedding passes. If subtitle injection or cover art
/// embedding fails, we still publish the main video/audio file with a warning rather
/// than failing the entire download.
private enum VideoDownloaderOptionalEmbedError: Error {
    case subtitle
    case artwork
}

protocol VideoDownloaderProcessServicing: AnyObject {
    func probeDependencies(completion: @escaping (VideoDownloaderDependencies) -> Void)
    func inspect(_ source: ValidatedVideoURL, id: UUID,
                 completion: @escaping VideoDownloaderProcessService.InspectionCompletion)
    func download(_ request: VideoDownloaderRequest, id: UUID,
                  progress: @escaping (UUID, VideoDownloaderProtocolEvent) -> Void,
                  completion: @escaping VideoDownloaderProcessService.DownloadCompletion)
    func installMissingTools(brewPath: String, missing: Set<VideoDownloaderTool>,
                             id: UUID,
                             completion: @escaping VideoDownloaderProcessService.SetupCompletion)
    func cancelInspection(wait: Bool)
    func cancelDownload(wait: Bool)
    func cancelSetup(wait: Bool)
    func cancelAll(wait: Bool)
    func cancelAll(completion: @escaping () -> Void)
}

extension VideoDownloaderProcessServicing {
    func cancelAll(completion: @escaping () -> Void) {
        cancelAll(wait: false)
        DispatchQueue.main.async(execute: completion)
    }
}

final class VideoDownloaderProcessService: VideoDownloaderProcessServicing {
    static let shared = VideoDownloaderProcessService()
    // A single retry absorbs transient socket drops without hammering servers that returned hard 429s or CAPTCHAs.
    private static let maximumTransientInspectionAttempts = 2
    private static let maximumTransientDownloadAttempts = 2
    private static let transientRetryDelays: [TimeInterval] = [0.75]

    typealias InspectionCompletion = (UUID, Result<VideoDownloaderMedia, VideoDownloaderFailure>) -> Void
    typealias DownloadCompletion = (UUID, Result<VideoDownloaderDownloadResult, VideoDownloaderFailure>) -> Void
    typealias SetupCompletion = (UUID, Result<Void, VideoDownloaderFailure>) -> Void

    private let workQueue = DispatchQueue(label: "com.vorssaint.video-downloader", qos: .userInitiated)
    private let dependencyQueue = DispatchQueue(label: "com.vorssaint.video-downloader.dependencies",
                                                qos: .utility)
    private let operationLock = NSLock()
    private let dependencyCacheLock = NSLock()
    private let mutationGate: HomebrewMutationGate
    private let timeoutPolicy: VideoDownloaderTimeoutPolicy
    private let artworkFetcher: VideoDownloaderArtworkFetching
    private var inspectionOperation: VideoDownloaderProcessOperation?
    private var downloadOperation: VideoDownloaderProcessOperation?
    private var setupOperation: VideoDownloaderProcessOperation?
    private var cachedToolPaths: [VideoDownloaderTool: String] = [:]
    private var dependencyProbeInFlight = false
    private var dependencyProbeCompletions: [(VideoDownloaderDependencies) -> Void] = []

    init(initialToolPaths: [VideoDownloaderTool: String] = [:],
         mutationGate: HomebrewMutationGate = .shared,
         timeoutPolicy: VideoDownloaderTimeoutPolicy = .default,
         artworkFetcher: @escaping VideoDownloaderArtworkFetching = VideoDownloaderArtworkFetcher.fetch) {
        cachedToolPaths = initialToolPaths
        self.mutationGate = mutationGate
        self.timeoutPolicy = timeoutPolicy
        self.artworkFetcher = artworkFetcher
    }

    func probeDependencies(completion: @escaping (VideoDownloaderDependencies) -> Void) {
        dependencyCacheLock.lock()
        dependencyProbeCompletions.append(completion)
        guard !dependencyProbeInFlight else {
            dependencyCacheLock.unlock()
            return
        }
        dependencyProbeInFlight = true
        dependencyCacheLock.unlock()

        dependencyQueue.async { [weak self] in
            guard let self else { return }
            // Deduplicate concurrent probe requests so multiple UI callers share the same dependency scan.
            let previousPaths = self.cachedPathsSnapshot()
            var paths: [VideoDownloaderTool: String] = [:]
            for tool in VideoDownloaderTool.allCases {
                let discovered = VideoDownloaderDependencySupport.candidatePaths(
                    for: tool,
                    home: FileManager.default.homeDirectoryForCurrentUser,
                    pathEnvironment: ProcessInfo.processInfo.environment["PATH"]
                )
                // Prioritize previously verified paths so tools in non-standard directories aren't lost if PATH changes.
                let candidates = ([previousPaths[tool]].compactMap { $0 } + discovered)
                    .reduce(into: [String]()) { result, candidate in
                        if !result.contains(candidate) { result.append(candidate) }
                    }
                if let path = candidates.first(where: { candidate in
                    FileManager.default.isExecutableFile(atPath: candidate) && self.probe(tool, path: candidate)
                }) {
                    paths[tool] = path
                }
            }
            self.replaceCachedPaths(with: paths)
            self.dependencyCacheLock.lock()
            let completions = self.dependencyProbeCompletions
            self.dependencyProbeCompletions.removeAll()
            self.dependencyProbeInFlight = false
            self.dependencyCacheLock.unlock()
            let dependencies = VideoDownloaderDependencies(paths: paths)
            DispatchQueue.main.async {
                completions.forEach { $0(dependencies) }
            }
        }
    }

    func inspect(_ source: ValidatedVideoURL,
                 id: UUID,
                 completion: @escaping InspectionCompletion) {
        cancelInspection(wait: false)
        let operation = VideoDownloaderProcessOperation()
        setOperation(operation, kind: .inspection)
        workQueue.async { [weak self] in
            guard let self else { operation.finish(); return }
            let outcome: Result<VideoDownloaderMedia, VideoDownloaderFailure>
            if operation.wasCancelled {
                outcome = .failure(.cancelled)
            } else if let ytDlp = self.cachedPath(for: .ytDlp),
                      let deno = self.cachedPath(for: .deno) {
                let browserCookies = self.cookiesFromBrowser
                let result = self.runInspection(source: source,
                                                ytDlpPath: ytDlp,
                                                denoPath: deno,
                                                cookiesFromBrowser: browserCookies,
                                                operation: operation)
                if operation.wasCancelled {
                    outcome = .failure(.cancelled)
                } else if result.didTimeOut {
                    outcome = .failure(.inspectionTimedOut)
                } else if result.stdoutOverflow {
                    outcome = .failure(.inspectionTooLarge)
                } else if !result.succeeded {
                    outcome = .failure(VideoDownloaderFailureClassifier.failure(
                        stderr: self.withoutIgnoredImpersonationWarnings(result.stderr),
                        cookiesFromBrowser: browserCookies,
                        fallback: .inspectionFailed))
                } else {
                    do {
                        outcome = .success(try VideoDownloaderInspectionParser.parse(
                            result.stdout,
                            allowAuthenticatedContent: browserCookies != nil))
                    } catch let failure as VideoDownloaderFailure {
                        outcome = .failure(failure)
                    } catch {
                        outcome = .failure(.malformedInspection)
                    }
                }
            } else {
                outcome = .failure(.missingDependencies)
            }
            operation.finish()
            self.clearOperation(operation, kind: .inspection)
            self.completeInspection(id, outcome, completion)
        }
    }

    func download(_ request: VideoDownloaderRequest,
                  id: UUID,
                  progress: @escaping (UUID, VideoDownloaderProtocolEvent) -> Void,
                  completion: @escaping DownloadCompletion) {
        cancelInspection(wait: false)
        let operation = VideoDownloaderProcessOperation()
        operationLock.lock()
        let alreadyActive = downloadOperation != nil || setupOperation != nil
        if !alreadyActive { downloadOperation = operation }
        operationLock.unlock()
        guard !alreadyActive else {
            DispatchQueue.main.async { completion(id, .failure(.downloadFailed)) }
            return
        }
        workQueue.async { [weak self] in
            guard let self else { operation.finish(); return }
            let outcome = self.performDownload(request, id: id, operation: operation, progress: progress)
            operation.finish()
            self.clearOperation(operation, kind: .download)
            self.completeDownload(id, outcome, completion)
        }
    }

    private func performDownload(_ request: VideoDownloaderRequest,
                                 id: UUID,
                                 operation: VideoDownloaderProcessOperation,
                                 progress: @escaping (UUID, VideoDownloaderProtocolEvent) -> Void)
        -> Result<VideoDownloaderDownloadResult, VideoDownloaderFailure> {
        guard let ytDlp = cachedPath(for: .ytDlp),
              let ffmpeg = cachedPath(for: .ffmpeg),
              let ffprobe = cachedPath(for: .ffprobe),
              let deno = cachedPath(for: .deno) else {
            return .failure(.missingDependencies)
        }
        if operation.wasCancelled { return .failure(.cancelled) }

        let browserCookies = cookiesFromBrowser
        do {
            let published = try VideoDownloaderFileSupport.withStagingDirectory(in: request.destination, id: id) {
                created -> VideoDownloaderDownloadResult in
                var warnings: [VideoDownloaderWarning] = []
                let expectsSeparateMediaTransfers = request.mode == .video
                    && request.media.videoAvailability == .available
                    && request.media.audioAvailability == .available
                let command = VideoDownloaderCommandBuilder.download(ytDlpPath: ytDlp,
                                                                      ffmpegPath: ffmpeg,
                                                                      denoPath: deno,
                                                                      staging: created,
                                                                      request: request,
                                                                      cookiesFromBrowser: browserCookies)
                let attempt = self.runMediaDownload(
                    command: command,
                    request: request,
                    id: id,
                    staging: created,
                    operation: operation,
                    expectsSeparateMediaTransfers: expectsSeparateMediaTransfers,
                    progress: progress)
                var result = attempt.result
                var reportedPath = attempt.reportedPath
                if !result.succeeded,
                   request.mode == .video,
                   request.quality != .best,
                   self.isFormatSelectionFailure(result.stderr),
                   !operation.wasCancelled,
                   self.clearStagingForRetry(created) {
                    // Quality caps are preferences. If an extractor can't satisfy a specific resolution query,
                    // fallback to the default selector so the user still gets the best available video.
                    let fallbackRequest = request.withQuality(.best)
                    let fallbackCommand = VideoDownloaderCommandBuilder.download(
                        ytDlpPath: ytDlp,
                        ffmpegPath: ffmpeg,
                        denoPath: deno,
                        staging: created,
                        request: fallbackRequest,
                        cookiesFromBrowser: browserCookies)
                    let fallbackAttempt = self.runMediaDownload(
                        command: fallbackCommand,
                        request: fallbackRequest,
                        id: id,
                        staging: created,
                        operation: operation,
                        expectsSeparateMediaTransfers: expectsSeparateMediaTransfers,
                        progress: progress)
                    result = fallbackAttempt.result
                    reportedPath = fallbackAttempt.reportedPath
                }
                if operation.wasCancelled { throw VideoDownloaderFailure.cancelled }

                let diagnostics = self.analyzeStderr(result.stderr, request: request)
                let stagedMedia = self.stagedMediaCandidate(in: created, mode: request.mode)
                let subtitleWarning = diagnostics.subtitleWarning
                var optionalWarnings = diagnostics.optionalWarnings
                if stagedMedia != nil, let subtitleWarning {
                    self.appendWarning(subtitleWarning, to: &optionalWarnings)
                }
                let hasIgnoredImpersonationWarning = diagnostics.hasIgnoredImpersonationWarning
                // yt-dlp can exit non-zero for non-fatal reasons (like missing impersonation targets
                // or failed optional captions). As long as ffprobe validates the media, we treat the download as successful.
                let optionalMediaFailure = !result.succeeded
                    && (!optionalWarnings.isEmpty || hasIgnoredImpersonationWarning)
                    && stagedMedia.map {
                        !diagnostics.hasNonOptionalFailureSignal
                            && self.isValidMediaCandidate($0,
                                                          request: request,
                                                          ffprobePath: ffprobe,
                                                          operation: operation)
                    } == true
                if optionalMediaFailure, reportedPath == nil {
                    reportedPath = stagedMedia?.path
                }
                if !result.succeeded && !optionalMediaFailure {
                    throw self.downloadFailure(diagnostics.failureStderr,
                                                request: request,
                                                cookiesFromBrowser: browserCookies)
                }
                optionalWarnings.forEach { self.appendWarning($0, to: &warnings) }

                guard let reportedPath else { throw VideoDownloaderFailure.fileSafety }
                var mediaFile = try VideoDownloaderFileSupport.finalMedia(in: created,
                                                                          reportedPath: reportedPath,
                                                                          mode: request.mode)
                let subtitleFailedDuringMediaDownload = optionalMediaFailure
                    && subtitleWarning != nil
                var suppressMissingSubtitleWarning = subtitleFailedDuringMediaDownload
                    && request.mode == .video
                if request.mode == .video, let subtitle = request.subtitle, !subtitleFailedDuringMediaDownload {
                    do {
                        mediaFile = try self.embedSubtitle(
                            in: mediaFile,
                            subtitle: subtitle,
                            staging: created,
                            ffmpegPath: ffmpeg,
                            operation: operation)
                        suppressMissingSubtitleWarning = false
                    } catch let failure as VideoDownloaderFailure where failure == .cancelled {
                        throw failure
                    } catch {
                        self.appendWarning(.subtitle, to: &warnings)
                    }
                }
                if request.options.thumbnail, let thumbnailURL = request.media.thumbnailURL {
                    do {
                        mediaFile = try self.embedArtwork(in: mediaFile,
                                                          thumbnailURL: thumbnailURL,
                                                          staging: created,
                                                          mode: request.mode,
                                                          ffmpegPath: ffmpeg,
                                                          operation: operation)
                    } catch let failure as VideoDownloaderFailure where failure == .cancelled {
                        throw failure
                    } catch {
                        self.appendWarning(.artwork, to: &warnings)
                    }
                }
                let normalized = try self.verifyAndNormalizeMedia(in: mediaFile,
                                                                  staging: created,
                                                                  request: request,
                                                                  ffprobePath: ffprobe,
                                                                  operation: operation,
                                                                  suppressMissingSubtitleWarning: suppressMissingSubtitleWarning)
                mediaFile = normalized.file
                normalized.warnings.forEach { self.appendWarning($0, to: &warnings) }
                if operation.wasCancelled { throw VideoDownloaderFailure.cancelled }
                let published = try VideoDownloaderFileSupport.publish(mediaFile,
                                                                        into: request.destination)
                return VideoDownloaderDownloadResult(file: published, warnings: warnings)
            }
            return .success(published)
        } catch let failure as VideoDownloaderFailure {
            return .failure(operation.wasCancelled ? .cancelled : failure)
        } catch {
            return .failure(operation.wasCancelled ? .cancelled : .fileSafety)
        }
    }

    private func runMediaDownload(
        command: VideoDownloaderToolCommand,
        request: VideoDownloaderRequest,
        id: UUID,
        staging: URL,
        operation: VideoDownloaderProcessOperation,
        expectsSeparateMediaTransfers: Bool,
        progress: @escaping (UUID, VideoDownloaderProtocolEvent) -> Void
    ) -> (result: ProcessResult, reportedPath: String?) {
        var attempt = 0
        while true {
            let protocolCollector = VideoDownloaderProtocolCollector(
                id: id,
                expectsSeparateMediaTransfers: expectsSeparateMediaTransfers,
                videoWeight: request.videoWeight,
                progress: progress)
            let result = self.run(
                command,
                standardInput: Data((request.source.string + "\n").utf8),
                operation: operation,
                timeout: timeoutPolicy.download,
                stdoutLimit: 1024 * 1024,
                stderrLimit: 256 * 1024,
                currentDirectory: staging
            ) { chunk in
                protocolCollector.consume(chunk, from: .standardOutput)
            } onStderr: { chunk in
                protocolCollector.consume(chunk, from: .standardError)
            }
            let reportedPath = protocolCollector.finish()
            let diagnostics = self.analyzeStderr(result.stderr, request: request)
            let optionalSubtitleFailure = request.subtitle != nil
                && self.stagedMediaCandidate(in: staging, mode: request.mode) != nil
                && diagnostics.subtitleWarning != nil
                && !diagnostics.hasNonOptionalFailureSignal
            let canRetry = !result.succeeded
                && attempt + 1 < Self.maximumTransientDownloadAttempts
                && !operation.wasCancelled
                && !optionalSubtitleFailure
                && self.isRetryableDownloadFailure(result.stderr, request: request)
                && self.clearStagingForRetry(staging)
            guard canRetry else { return (result, reportedPath) }
            attempt += 1
            let delayIndex = min(attempt - 1, Self.transientRetryDelays.count - 1)
            Thread.sleep(forTimeInterval: Self.transientRetryDelays[delayIndex])
        }
    }

    private func runInspection(source: ValidatedVideoURL,
                               ytDlpPath: String,
                               denoPath: String,
                               cookiesFromBrowser: String?,
                               operation: VideoDownloaderProcessOperation) -> ProcessResult {
        var attempt = 0
        while true {
            let result = self.run(
                VideoDownloaderCommandBuilder.inspection(ytDlpPath: ytDlpPath,
                                                          denoPath: denoPath,
                                                          cookiesFromBrowser: cookiesFromBrowser),
                standardInput: Data((source.string + "\n").utf8),
                operation: operation,
                timeout: timeoutPolicy.inspection,
                stdoutLimit: VideoDownloaderInspectionParser.maximumJSONBytes + 1,
                stderrLimit: 128 * 1024
            )
            let stderrText = String(decoding: result.stderr, as: UTF8.self)
            let canRetry = !result.succeeded
                && attempt + 1 < Self.maximumTransientInspectionAttempts
                && !operation.wasCancelled
                && !VideoDownloaderRateLimitSupport.isRateLimited(stderrText)
                && (result.didTimeOut || self.isRetryableExtractorFailure(stderrText))
            guard canRetry else { return result }
            attempt += 1
            let delayIndex = min(attempt - 1, Self.transientRetryDelays.count - 1)
            Thread.sleep(forTimeInterval: Self.transientRetryDelays[delayIndex])
        }
    }

    private func clearStagingForRetry(_ staging: URL) -> Bool {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: staging, includingPropertiesForKeys: nil, options: []) else { return false }
        do {
            for url in contents where url.lastPathComponent != VideoDownloaderFileSupport.ownerMarkerName {
                try fileManager.removeItem(at: url)
            }
            return true
        } catch {
            return false
        }
    }

    private func isRetryableDownloadFailure(_ stderr: Data,
                                            request: VideoDownloaderRequest) -> Bool {
        let coreLines = String(decoding: stderr, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.lowercased() }
            .filter {
                !isIgnoredImpersonationWarning($0)
                    && optionalWarning(in: $0, request: request) == nil
            }
        guard !coreLines.isEmpty else { return false }
        let coreStderrText = coreLines.joined(separator: "\n")
        guard !VideoDownloaderRateLimitSupport.isRateLimited(coreStderrText) else { return false }
        return isRetryableExtractorFailure(coreStderrText)
    }

    private func isFormatSelectionFailure(_ stderr: Data) -> Bool {
        isFormatSelectionFailure(String(decoding: stderr, as: UTF8.self))
    }

    private func isFormatSelectionFailure(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return [
            "requested format is not available",
            "requested format not available",
            "requested format is unavailable",
            "there are no formats available",
            "video+audio formats are not available",
        ].contains(where: normalized.contains)
    }

    private func isRetryableExtractorFailure(_ stderr: Data) -> Bool {
        isRetryableExtractorFailure(String(decoding: stderr, as: UTF8.self))
    }

    private func isRetryableExtractorFailure(_ message: String) -> Bool {
        let normalized = message.lowercased()
        let transientSignals = [
            "http error 403", "http error 429", "403 forbidden", "429 too many requests",
            "too many requests", "http error 500", "http error 502", "http error 503",
            "http error 504", "temporarily unavailable", "temporary failure",
            "connection reset", "timed out", "unable to extract", "failed to extract",
        ]
        return transientSignals.contains(where: normalized.contains)
    }

    private func stagedMediaCandidate(in staging: URL,
                                      mode: VideoDownloaderOutputMode) -> URL? {
        let candidates = VideoDownloaderFileSupport.mediaCandidates(in: staging, mode: mode)
        return candidates.count == 1 ? candidates[0] : nil
    }

    func installMissingTools(brewPath: String,
                             missing: Set<VideoDownloaderTool>,
                             id: UUID,
                             completion: @escaping SetupCompletion) {
        guard let command = VideoDownloaderCommandBuilder.homebrewInstall(brewPath: brewPath,
                                                                          missingTools: missing),
              let reservation = mutationGate.reserve() else {
            DispatchQueue.main.async { completion(id, .failure(.setupBusy)) }
            return
        }
        let operation = VideoDownloaderProcessOperation()
        operationLock.lock()
        let alreadyActive = setupOperation != nil || downloadOperation != nil
        if !alreadyActive { setupOperation = operation }
        operationLock.unlock()
        guard !alreadyActive else {
            reservation.release()
            DispatchQueue.main.async { completion(id, .failure(.setupBusy)) }
            return
        }
        workQueue.async { [weak self] in
            guard let self else { operation.finish(); reservation.release(); return }
            let result = self.run(command,
                                  standardInput: nil,
                                  operation: operation,
                                  timeout: self.timeoutPolicy.homebrewSetup,
                                  stdoutLimit: 256 * 1024,
                                  stderrLimit: 256 * 1024)
            let outcome: Result<Void, VideoDownloaderFailure>
            if operation.wasCancelled { outcome = .failure(.cancelled) }
            else if result.succeeded { outcome = .success(()) }
            else if HomebrewCommandBuilder.needsTerminalFallback(
                output: String(decoding: result.stdout, as: UTF8.self)
                    + "\n"
                    + String(decoding: result.stderr, as: UTF8.self)) {
                outcome = .failure(.terminalPermission)
            }
            else { outcome = .failure(.setupFailed) }
            operation.finish()
            // Hold the Homebrew mutation lock until all descendant processes have completely stopped.
            reservation.release()
            self.clearOperation(operation, kind: .setup)
            DispatchQueue.main.async { completion(id, outcome) }
        }
    }

    func cancelInspection(wait: Bool) { cancel(kind: .inspection, wait: wait) }
    func cancelDownload(wait: Bool) { cancel(kind: .download, wait: wait) }
    func cancelSetup(wait: Bool) { cancel(kind: .setup, wait: wait) }

    func cancelAll(wait: Bool) {
        cancelInspection(wait: wait)
        cancelDownload(wait: wait)
        cancelSetup(wait: wait)
    }

    func cancelAll(completion: @escaping () -> Void) {
        operationLock.lock()
        let operations = [inspectionOperation, downloadOperation, setupOperation].compactMap { $0 }
        operationLock.unlock()

        operations.forEach { $0.cancel() }
        guard !operations.isEmpty else {
            DispatchQueue.main.async(execute: completion)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            operations.forEach { $0.wait() }
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func probe(_ tool: VideoDownloaderTool, path: String) -> Bool {
        // Freshly installed Homebrew binaries can take several seconds on first run while Python compiles bytecode
        // and macOS verifies signatures. Give cold binaries extra time before declaring them missing.
        let attempts: [(timeout: TimeInterval, delay: TimeInterval)] = [(4, 0), (15, 0.25)]
        for (index, attempt) in attempts.enumerated() {
            if index > 0 { Thread.sleep(forTimeInterval: attempt.delay) }
            let operation = VideoDownloaderProcessOperation()
            let result = run(VideoDownloaderCommandBuilder.dependencyProbe(tool: tool,
                                                                           executablePath: path),
                             standardInput: nil,
                             operation: operation,
                             timeout: attempt.timeout,
                             stdoutLimit: 256 * 1024,
                             stderrLimit: 16 * 1024)
            operation.finish()
            if result.succeeded
                && VideoDownloaderDependencySupport.supportsRequiredCapabilities(tool,
                                                                                  output: result.stdout) {
                return true
            }
        }
        return false
    }

    private func cachedPath(for tool: VideoDownloaderTool) -> String? {
        dependencyCacheLock.lock()
        defer { dependencyCacheLock.unlock() }
        return cachedToolPaths[tool]
    }

    private func cachedPathsSnapshot() -> [VideoDownloaderTool: String] {
        dependencyCacheLock.lock()
        defer { dependencyCacheLock.unlock() }
        return cachedToolPaths
    }

    private func replaceCachedPaths(with paths: [VideoDownloaderTool: String]) {
        dependencyCacheLock.lock()
        cachedToolPaths = paths
        dependencyCacheLock.unlock()
    }

    /// Read browser cookies dynamically so inspection and download always share the latest session state.
    private var cookiesFromBrowser: String? {
        VideoDownloaderCookiesSupport.selectedBrowser()
    }

    private func downloadFailure(_ stderr: Data,
                                 request: VideoDownloaderRequest,
                                 cookiesFromBrowser: String?) -> VideoDownloaderFailure {
        // Videos that bypass inspection via fallback will first encounter auth/DRM errors during download.
        // We route those through the same classifier so error messages stay consistent.
        let remuxSignals = ["conversion failed", "could not write header", "not supported in container",
                            "could not find tag for codec",
                            "muxer does not support", "error opening output", "mergeformats",
                            "videoremuxer", "ffmpeg video remuxer"]
        return VideoDownloaderFailureClassifier.failure(
            stderr: stderr,
            cookiesFromBrowser: cookiesFromBrowser,
            fallback: .downloadFailed
        ) { message in
            request.mode == .video && remuxSignals.contains(where: message.contains)
                ? .mp4Remux : nil
        }
    }

    private struct StderrDiagnostics {
        let subtitleWarning: VideoDownloaderWarning?
        let optionalWarnings: [VideoDownloaderWarning]
        let hasIgnoredImpersonationWarning: Bool
        let hasNonOptionalFailureSignal: Bool
        let failureStderr: Data
    }

    private func analyzeStderr(_ stderr: Data,
                               request: VideoDownloaderRequest) -> StderrDiagnostics {
        let rawLines = String(decoding: stderr, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        var subtitleWarning: VideoDownloaderWarning?
        var optionalWarnings: [VideoDownloaderWarning] = []
        var hasIgnoredImpersonationWarning = false
        var hasNonOptionalFailure = false
        var nonIgnoredLines: [String] = []
        var coreFailureLines: [String] = []

        for line in rawLines {
            let lower = line.lowercased()
            let isIgnored = isIgnoredImpersonationWarning(lower)
            if isIgnored {
                hasIgnoredImpersonationWarning = true
            } else {
                nonIgnoredLines.append(line)
            }

            let optWarn = optionalWarning(in: lower, request: request)
            if let optWarn {
                switch optWarn {
                case .subtitle, .subtitleRateLimited:
                    if subtitleWarning == nil { subtitleWarning = optWarn }
                case .artwork, .metadata, .chapters:
                    if !optionalWarnings.contains(optWarn) { optionalWarnings.append(optWarn) }
                }
            } else if !isIgnored {
                if failureLanguage(in: lower) {
                    hasNonOptionalFailure = true
                }
                coreFailureLines.append(line)
            }
        }

        let failureData = hasNonOptionalFailure
            ? Data(coreFailureLines.joined(separator: "\n").utf8)
            : Data(nonIgnoredLines.joined(separator: "\n").utf8)

        return StderrDiagnostics(
            subtitleWarning: subtitleWarning,
            optionalWarnings: optionalWarnings,
            hasIgnoredImpersonationWarning: hasIgnoredImpersonationWarning,
            hasNonOptionalFailureSignal: hasNonOptionalFailure,
            failureStderr: failureData
        )
    }

    private func isIgnoredImpersonationWarning(_ line: String) -> Bool {
        let normalized = line.lowercased()
        guard normalized.contains("no impersonate target is available") else { return false }
        return normalized.contains("attempting impersonation")
            || normalized.contains("specified to use impersonation")
    }

    private func withoutIgnoredImpersonationWarnings(_ stderr: Data) -> Data {
        let lines = String(decoding: stderr, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !isIgnoredImpersonationWarning($0) }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func optionalWarning(in line: String,
                                 request: VideoDownloaderRequest) -> VideoDownloaderWarning? {
        let mentionsSubtitle = line.contains("subtitle") || line.contains("caption")
        if request.mode == .video, request.subtitle != nil, mentionsSubtitle {
            if VideoDownloaderRateLimitSupport.isRateLimited(line) {
                return .subtitleRateLimited
            }
            if line.contains("requested subtitles not available")
                || line.contains("no subtitles for the requested languages")
                || line.contains("unable to download video subtitles")
                || line.contains("subtitle download failed")
                || failureLanguage(in: line) {
                return .subtitle
            }
        }
        if request.options.thumbnail, request.media.thumbnailURL != nil,
           (line.contains("thumbnail") || line.contains("cover art")),
           failureLanguage(in: line) {
            return .artwork
        }
        if request.options.metadata, line.contains("metadata"), failureLanguage(in: line) {
            return .metadata
        }
        if request.mode == .video, request.options.chapters, request.media.hasChapters,
           line.contains("chapter"), failureLanguage(in: line) {
            return .chapters
        }
        return nil
    }

    private func appendWarning(_ warning: VideoDownloaderWarning,
                               to warnings: inout [VideoDownloaderWarning]) {
        if !warnings.contains(warning) { warnings.append(warning) }
    }

    private func failureLanguage(in message: String) -> Bool {
        ["error", "failed", "failure", "unable", "cannot", "could not", "not supported"]
            .contains(where: message.contains)
    }

    private func isValidMediaCandidate(_ mediaFile: URL,
                                       request: VideoDownloaderRequest,
                                       ffprobePath: String,
                                       operation: VideoDownloaderProcessOperation) -> Bool {
        guard let inspection = try? embeddedMediaInspection(in: mediaFile,
                                                             ffprobePath: ffprobePath,
                                                             operation: operation) else {
            return false
        }
        return VideoDownloaderEmbeddedDataVerifier.failure(in: inspection, for: request) == nil
    }

    private func embeddedMediaInspection(in mediaFile: URL,
                                         ffprobePath: String,
                                         operation: VideoDownloaderProcessOperation)
        throws -> VideoDownloaderEmbeddedDataInspection {
        guard FileManager.default.isExecutableFile(atPath: ffprobePath) else {
            throw VideoDownloaderFailure.missingDependencies
        }
        let result = run(VideoDownloaderCommandBuilder.ffprobe(ffprobePath: ffprobePath, input: mediaFile),
                         standardInput: nil,
                         operation: operation,
                         timeout: 15,
                         stdoutLimit: VideoDownloaderEmbeddedDataParser.maximumJSONBytes + 1,
                         stderrLimit: 128 * 1024,
                         currentDirectory: mediaFile.deletingLastPathComponent())
        if operation.wasCancelled { throw VideoDownloaderFailure.cancelled }
        guard result.succeeded, !result.stdoutOverflow,
              let inspection = VideoDownloaderEmbeddedDataParser.parse(result.stdout) else {
            throw VideoDownloaderFailure.fileSafety
        }
        return inspection
    }

    private func verifyAndNormalizeMedia(in mediaFile: URL,
                                         staging: URL,
                                         request: VideoDownloaderRequest,
                                         ffprobePath: String,
                                         operation: VideoDownloaderProcessOperation,
                                         suppressMissingSubtitleWarning: Bool = false)
        throws -> (file: URL, warnings: [VideoDownloaderWarning]) {
        let inspection = try embeddedMediaInspection(in: mediaFile,
                                                     ffprobePath: ffprobePath,
                                                     operation: operation)
        if let failure = VideoDownloaderEmbeddedDataVerifier.failure(in: inspection, for: request) {
            throw failure
        }
        guard let container = inspection.container else {
            throw VideoDownloaderFailure.fileSafety
        }
        let normalized = try VideoDownloaderFileSupport.normalizeExtension(of: mediaFile,
                                                                           in: staging,
                                                                           for: container)
        return (normalized, VideoDownloaderEmbeddedDataVerifier.warnings(in: inspection,
                                                                          for: request,
                                                                          includeSubtitleWarning: !suppressMissingSubtitleWarning))
    }

    private func embedSubtitle(in mediaFile: URL,
                               subtitle: VideoDownloaderSubtitleTrack,
                               staging: URL,
                               ffmpegPath: String,
                               operation: VideoDownloaderProcessOperation) throws -> URL {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: staging,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: []) else {
            throw VideoDownloaderOptionalEmbedError.subtitle
        }
        let subtitles = enumerator.compactMap { $0 as? URL }.filter {
            ["srt", "vtt"].contains($0.pathExtension.lowercased())
                && VideoDownloaderFileSupport.isContained($0, in: staging)
        }
        guard subtitles.count == 1,
              let size = try? subtitles[0].resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 8 * 1024 * 1024 else {
            throw VideoDownloaderOptionalEmbedError.subtitle
        }
        let sidecar = subtitles[0]
        let temporary = staging.appendingPathComponent(
            ".vorssaint-subtitle-\(UUID().uuidString).\(mediaFile.pathExtension.lowercased())")
        defer {
            try? fileManager.removeItem(at: sidecar)
            try? fileManager.removeItem(at: temporary)
        }
        let result = run(VideoDownloaderCommandBuilder.ffmpegSubtitle(
            ffmpegPath: ffmpegPath,
            input: mediaFile,
            subtitle: sidecar,
            output: temporary,
            language: subtitle.code),
                         standardInput: nil,
                         operation: operation,
                         timeout: timeoutPolicy.postProcessing,
                         stdoutLimit: 64 * 1024,
                         stderrLimit: 128 * 1024,
                         currentDirectory: staging)
        if operation.wasCancelled { throw VideoDownloaderFailure.cancelled }
        guard result.succeeded,
              VideoDownloaderFileSupport.isContained(temporary, in: staging),
              let outputSize = try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              outputSize > 0 else {
            throw VideoDownloaderOptionalEmbedError.subtitle
        }
        _ = try fileManager.replaceItemAt(mediaFile, withItemAt: temporary,
                                          backupItemName: nil, options: [])
        return mediaFile
    }

    private func embedArtwork(in mediaFile: URL,
                              thumbnailURL: URL,
                              staging: URL,
                              mode: VideoDownloaderOutputMode,
                              ffmpegPath: String,
                              operation: VideoDownloaderProcessOperation) throws -> URL {
        guard VideoDownloaderThumbnailURLPolicy.sanitizedURL(thumbnailURL) != nil else {
            throw VideoDownloaderOptionalEmbedError.artwork
        }
        guard let artworkData = artworkFetcher(thumbnailURL, 20, { operation.wasCancelled }) else {
            throw operation.wasCancelled ? VideoDownloaderFailure.cancelled : VideoDownloaderOptionalEmbedError.artwork
        }
        let fileManager = FileManager.default
        let artwork = staging.appendingPathComponent(".vorssaint-artwork-\(UUID().uuidString).jpg")
        let temporary = staging.appendingPathComponent(
            ".vorssaint-artwork-output-\(UUID().uuidString).\(mediaFile.pathExtension.lowercased())")
        defer {
            try? fileManager.removeItem(at: artwork)
            try? fileManager.removeItem(at: temporary)
        }
        do {
            try artworkData.write(to: artwork, options: [.atomic])
        } catch {
            throw VideoDownloaderOptionalEmbedError.artwork
        }
        let result = run(VideoDownloaderCommandBuilder.ffmpegArtwork(ffmpegPath: ffmpegPath,
                                                                      input: mediaFile,
                                                                      artwork: artwork,
                                                                      output: temporary,
                                                                      mode: mode),
                         standardInput: nil,
                         operation: operation,
                         timeout: timeoutPolicy.postProcessing,
                         stdoutLimit: 64 * 1024,
                         stderrLimit: 128 * 1024,
                         currentDirectory: staging)
        if operation.wasCancelled { throw VideoDownloaderFailure.cancelled }
        guard result.succeeded,
              VideoDownloaderFileSupport.isContained(temporary, in: staging),
              let outputSize = try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              outputSize > 0 else { throw VideoDownloaderOptionalEmbedError.artwork }
        _ = try fileManager.replaceItemAt(mediaFile, withItemAt: temporary,
                                          backupItemName: nil, options: [])
        return mediaFile
    }

    private struct ProcessResult {
        let termination: VideoDownloaderProcessTermination
        let stdout: Data
        let stderr: Data
        let stdoutOverflow: Bool

        var didTimeOut: Bool {
            if case .timedOut = termination { return true }
            return false
        }

        var succeeded: Bool {
            if case .exited(0) = termination { return true }
            return false
        }
    }

    private func run(_ command: VideoDownloaderToolCommand,
                     standardInput: Data?,
                     operation: VideoDownloaderProcessOperation,
                     timeout: TimeInterval?,
                     stdoutLimit: Int,
                     stderrLimit: Int,
                     currentDirectory: URL? = nil,
                     onStdout: ((Data) -> Void)? = nil,
                     onStderr: ((Data) -> Void)? = nil) -> ProcessResult {
        guard !operation.wasCancelled else {
            return ProcessResult(termination: .failedToStart, stdout: Data(), stderr: Data(),
                                 stdoutOverflow: false)
        }
        // Reset timeout trackers between retry attempts so a second attempt gets a fresh timer.
        operation.prepareForRun()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.environment = VideoDownloaderExecutionEnvironment.make(
            executable: command.executable,
            additionalDirectories: command.executableSearchDirectories
        )
        process.currentDirectoryURL = currentDirectory
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            try? inputPipe.fileHandleForWriting.close()
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            return ProcessResult(termination: .failedToStart, stdout: Data(), stderr: Data(),
                                 stdoutOverflow: false)
        }
        operation.attach(process)
        try? outputPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()

        let readers = DispatchGroup()
        let readerStop = VideoDownloaderPipeDrainSignal()
        let stdoutBox = VideoDownloaderDataBox(limit: stdoutLimit)
        let stderrBox = VideoDownloaderDataBox(limit: stderrLimit)
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            Self.drain(outputPipe.fileHandleForReading, into: stdoutBox,
                       stop: readerStop, onChunk: onStdout)
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            Self.drain(errorPipe.fileHandleForReading, into: stderrBox,
                       stop: readerStop, onChunk: onStderr)
            readers.leave()
        }

        if let standardInput {
            try? inputPipe.fileHandleForWriting.write(contentsOf: standardInput)
        }
        try? inputPipe.fileHandleForWriting.close()

        if let timeout {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                operation.timeoutIfRunning(process)
            }
        }
        process.waitUntilExit()
        // Allow a brief drain window for child processes that inherited open pipe handles before tearing down staging.
        readerStop.requestStop()
        readers.wait()
        operation.detach(process)
        // Wait for timed-out children to exit before removing staging so they can't write to deleted directories.
        operation.waitForPendingTerminations()
        let termination = operation.termination(for: process.terminationStatus)
        let stdout = stdoutBox.snapshot()
        let stderr = stderrBox.snapshot().data
        return ProcessResult(termination: termination,
                             stdout: stdout.data,
                             stderr: stderr,
                             stdoutOverflow: stdout.overflow)
    }

    private static func drain(_ handle: FileHandle,
                              into box: VideoDownloaderDataBox,
                              stop: VideoDownloaderPipeDrainSignal,
                              onChunk: ((Data) -> Void)?) {
        defer { try? handle.close() }
        let descriptor = handle.fileDescriptor
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        var stoppingDeadline: Date?
        while true {
            // Use POSIX poll with a bounded drain deadline to avoid deadlocking if a child process leaks a pipe handle.
            if stop.isRequested, stoppingDeadline == nil {
                stoppingDeadline = Date().addingTimeInterval(0.1)
            }
            if let stoppingDeadline, Date() >= stoppingDeadline { return }

            var state = pollfd(fd: descriptor,
                               events: Int16(POLLIN | POLLHUP | POLLERR),
                               revents: 0)
            let timeout: Int32 = stoppingDeadline == nil ? 50 : 0
            let readiness = Darwin.poll(&state, 1, timeout)
            if readiness == 0 {
                if stoppingDeadline != nil { return }
                continue
            }
            if readiness < 0 {
                if errno == EINTR { continue }
                return
            }
            if state.revents & Int16(POLLNVAL | POLLERR) != 0 { return }
            guard state.revents & Int16(POLLIN | POLLHUP) != 0 else { continue }

            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count == 0 { return }
            if count < 0 {
                if errno == EINTR { continue }
                return
            }
            let chunk = Data(buffer.prefix(count))
            box.append(chunk)
            onChunk?(chunk)
        }
    }

    private enum OperationKind { case inspection, download, setup }

    private func setOperation(_ operation: VideoDownloaderProcessOperation, kind: OperationKind) {
        operationLock.lock()
        defer { operationLock.unlock() }
        switch kind {
        case .inspection: inspectionOperation = operation
        case .download: downloadOperation = operation
        case .setup: setupOperation = operation
        }
    }

    private func clearOperation(_ operation: VideoDownloaderProcessOperation, kind: OperationKind) {
        operationLock.lock()
        defer { operationLock.unlock() }
        switch kind {
        case .inspection where inspectionOperation === operation: inspectionOperation = nil
        case .download where downloadOperation === operation: downloadOperation = nil
        case .setup where setupOperation === operation: setupOperation = nil
        default: break
        }
    }

    private func cancel(kind: OperationKind, wait: Bool) {
        operationLock.lock()
        let operation: VideoDownloaderProcessOperation?
        switch kind {
        case .inspection: operation = inspectionOperation
        case .download: operation = downloadOperation
        case .setup: operation = setupOperation
        }
        operationLock.unlock()
        operation?.cancel()
        if wait { operation?.wait() }
    }

    private func completeInspection(_ id: UUID,
                                    _ result: Result<VideoDownloaderMedia, VideoDownloaderFailure>,
                                    _ completion: @escaping InspectionCompletion) {
        DispatchQueue.main.async { completion(id, result) }
    }

    private func completeDownload(_ id: UUID,
                                  _ result: Result<VideoDownloaderDownloadResult, VideoDownloaderFailure>,
                                  _ completion: @escaping DownloadCompletion) {
        DispatchQueue.main.async { completion(id, result) }
    }
}

private enum VideoDownloaderArtworkFetcher {
    static func fetch(_ url: URL,
                      timeout: TimeInterval,
                      isCancelled: () -> Bool) -> Data? {
        guard let data = VideoDownloaderImageFetcher.fetchData(url: url,
                                                                timeout: timeout,
                                                                isCancelled: isCancelled) else {
            return nil
        }
        return normalizedJPEG(data)
    }

    private static func normalizedJPEG(_ data: Data) -> Data? {
        guard !data.isEmpty,
              data.count <= VideoDownloaderThumbnailURLPolicy.maximumResponseBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0,
              width <= VideoDownloaderThumbnailURLPolicy.maximumPixelDimension,
              height <= VideoDownloaderThumbnailURLPolicy.maximumPixelDimension,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              output.length > 0,
              output.length <= VideoDownloaderThumbnailURLPolicy.maximumResponseBytes else { return nil }
        return output as Data
    }
}

private enum VideoDownloaderProtocolStream {
    case standardOutput
    case standardError
}

/// Read both output pipes because yt-dlp can put progress on either one. This
/// prevents a full pipe from stalling the process and gives callers one stream
/// of progress events and the final output path.
private final class VideoDownloaderProtocolCollector {
    private let lock = NSLock()
    private let id: UUID
    private let progress: (UUID, VideoDownloaderProtocolEvent) -> Void
    private var standardOutputDecoder = VideoDownloaderLineDecoder()
    private var standardErrorDecoder = VideoDownloaderLineDecoder()
    private var reportedPath: String?
    private var lastProgressPublish = Date.distantPast
    private var lastPublishedProgress: VideoDownloaderProgress?
    private var progressAggregator: VideoDownloaderProgressAggregator

    init(id: UUID,
         expectsSeparateMediaTransfers: Bool = false,
         videoWeight: Double? = nil,
         progress: @escaping (UUID, VideoDownloaderProtocolEvent) -> Void) {
        self.id = id
        self.progress = progress
        progressAggregator = VideoDownloaderProgressAggregator(
            expectsSeparateMediaTransfers: expectsSeparateMediaTransfers,
            videoWeight: videoWeight)
    }

    func consume(_ data: Data, from stream: VideoDownloaderProtocolStream) {
        lock.lock()
        let lines: [String]
        switch stream {
        case .standardOutput: lines = standardOutputDecoder.append(data)
        case .standardError: lines = standardErrorDecoder.append(data)
        }
        lines.forEach(accept)
        lock.unlock()
    }

    func finish() -> String? {
        lock.lock()
        if let line = standardOutputDecoder.finish() { accept(line) }
        if let line = standardErrorDecoder.finish() { accept(line) }
        let path = reportedPath
        lock.unlock()
        return path
    }

    private func accept(_ line: String) {
        guard let parsed = VideoDownloaderProtocolParser.parse(line: line) else { return }
        let event: VideoDownloaderProtocolEvent
        switch parsed {
        case let .progress(value): event = .progress(progressAggregator.aggregate(value))
        case let .title(value): event = .title(value)
        case let .selectedVideoHeight(value): event = .selectedVideoHeight(value)
        case let .path(path):
            reportedPath = path
            if let completion = progressAggregator.complete() {
                lastProgressPublish = Date()
                lastPublishedProgress = completion
                publish(.progress(completion))
            }
            return
        }
        let now = Date()
        let shouldPublish: Bool
        if case let .progress(value) = event {
            // Filter redundant progress updates to prevent SwiftUI layout thrashing while still preserving new speed/ETA data.
            let addsInformation = lastPublishedProgress.map { previous in
                (previous.fraction == nil && value.fraction != nil)
                    || (previous.speedBytesPerSecond == nil && value.speedBytesPerSecond != nil)
                    || (previous.etaSeconds == nil && value.etaSeconds != nil)
            } ?? true
            let meaningfulAdvance: Bool
            if let previous = lastPublishedProgress?.fraction, let current = value.fraction {
                meaningfulAdvance = abs(current - previous) >= 0.005
            } else {
                meaningfulAdvance = false
            }
            shouldPublish = addsInformation
                || meaningfulAdvance
                || value.isNetworkComplete
                || now.timeIntervalSince(lastProgressPublish) >= 0.12
        } else {
            shouldPublish = true
        }
        guard shouldPublish else { return }
        if case let .progress(value) = event {
            lastProgressPublish = now
            lastPublishedProgress = value
        }
        publish(event)
    }

    private func publish(_ event: VideoDownloaderProtocolEvent) {
        DispatchQueue.main.async { [id, progress] in progress(id, event) }
    }
}

private final class VideoDownloaderPipeDrainSignal {
    private let lock = NSLock()
    private var requested = false

    var isRequested: Bool {
        lock.withLock { requested }
    }

    func requestStop() {
        lock.withLock { requested = true }
    }
}

private final class VideoDownloaderDataBox {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private var overflow = false

    init(limit: Int) { self.limit = max(0, limit) }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, limit - data.count)
        if remaining > 0 { data.append(chunk.prefix(remaining)) }
        if chunk.count > remaining { overflow = true }
    }

    func snapshot() -> (data: Data, overflow: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, overflow)
    }
}

private final class VideoDownloaderProcessOperation {
    private let condition = NSCondition()
    private var process: Process?
    private var cancelled = false
    private var didTimeOut = false
    private var didFinish = false
    private var pendingTerminations = 0

    init() {}

    var wasCancelled: Bool {
        condition.lock(); defer { condition.unlock() }
        return cancelled
    }

    func prepareForRun() {
        condition.lock()
        didTimeOut = false
        condition.unlock()
    }

    func attach(_ process: Process) {
        condition.lock()
        self.process = process
        let shouldTerminate = cancelled && beginTerminationLocked(process)
        condition.unlock()
        if shouldTerminate { terminate(process) }
    }

    func detach(_ process: Process) {
        condition.lock()
        if self.process === process { self.process = nil }
        condition.unlock()
    }

    func cancel() {
        condition.lock()
        guard !cancelled else { condition.unlock(); return }
        cancelled = true
        let process = self.process
        let shouldTerminate = process.map(beginTerminationLocked) ?? false
        condition.unlock()
        if let process, shouldTerminate { terminate(process) }
    }

    func timeoutIfRunning(_ process: Process) {
        condition.lock()
        guard self.process === process, process.isRunning, !didFinish, !cancelled else {
            condition.unlock()
            return
        }
        didTimeOut = true
        let shouldTerminate = beginTerminationLocked(process)
        condition.unlock()
        if shouldTerminate { terminate(process) }
    }

    func finish() {
        waitForPendingTerminations()
        condition.lock()
        guard !didFinish else { condition.unlock(); return }
        didFinish = true
        process = nil
        condition.broadcast()
        condition.unlock()
    }

    func waitForPendingTerminations() {
        condition.lock()
        while pendingTerminations > 0 { condition.wait() }
        condition.unlock()
    }

    func termination(for status: Int32) -> VideoDownloaderProcessTermination {
        condition.lock()
        defer { condition.unlock() }
        return didTimeOut ? .timedOut : .exited(status)
    }

    func wait() {
        condition.lock()
        while !didFinish { condition.wait() }
        condition.unlock()
    }

    private func terminate(_ process: Process) {
        let pid = process.processIdentifier
        let initiallyTracked = VideoDownloaderProcessTree.snapshot(of: pid)
        DispatchQueue.global(qos: .userInitiated).async {
            VideoDownloaderProcessTree.terminate(pid, initiallyTracked: initiallyTracked)
            self.condition.lock()
            self.pendingTerminations = max(0, self.pendingTerminations - 1)
            self.condition.broadcast()
            self.condition.unlock()
        }
    }

    private func beginTerminationLocked(_ process: Process) -> Bool {
        guard self.process === process, pendingTerminations == 0 else { return false }
        pendingTerminations += 1
        return true
    }
}
