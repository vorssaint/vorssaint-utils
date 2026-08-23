// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum VideoDownloaderOptionalEmbedError: Error {
    case subtitle
    case artwork
}

typealias VideoDownloaderCommandRunner = (
    _ command: VideoDownloaderToolCommand,
    _ standardInput: Data?,
    _ operation: VideoDownloaderProcessOperation,
    _ timeout: TimeInterval?,
    _ stdoutLimit: Int,
    _ stderrLimit: Int,
    _ currentDirectory: URL?
) -> VideoDownloaderProcessResult

/// Encapsulates the complete post-processing pipeline for downloaded media:
/// subtitle embedding, cover artwork embedding, container format verification,
/// extension normalization, and destination publication.
struct VideoDownloaderPostProcessor {
    private let timeoutPolicy: VideoDownloaderTimeoutPolicy
    private let artworkFetcher: VideoDownloaderArtworkFetching
    private let runner: VideoDownloaderCommandRunner

    init(timeoutPolicy: VideoDownloaderTimeoutPolicy = .default,
         artworkFetcher: @escaping VideoDownloaderArtworkFetching = VideoDownloaderArtworkFetcher.fetch,
         runner: @escaping VideoDownloaderCommandRunner) {
        self.timeoutPolicy = timeoutPolicy
        self.artworkFetcher = artworkFetcher
        self.runner = runner
    }

    /// Validates whether a staged media candidate contains playable and valid streams
    /// according to the given request.
    func isValidMediaCandidate(_ mediaFile: URL,
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

    /// Inspects embedded streams, chapters, metadata, and container format via ffprobe.
    func embeddedMediaInspection(in mediaFile: URL,
                                 ffprobePath: String,
                                 operation: VideoDownloaderProcessOperation)
        throws -> VideoDownloaderEmbeddedDataInspection {
        guard FileManager.default.isExecutableFile(atPath: ffprobePath) else {
            throw VideoDownloaderFailure.missingDependencies
        }
        let result = runner(VideoDownloaderCommandBuilder.ffprobe(ffprobePath: ffprobePath, input: mediaFile),
                            nil,
                            operation,
                            15,
                            VideoDownloaderEmbeddedDataParser.maximumJSONBytes + 1,
                            128 * 1024,
                            mediaFile.deletingLastPathComponent())
        if operation.wasCancelled { throw VideoDownloaderFailure.cancelled }
        guard result.succeeded, !result.stdoutOverflow,
              let inspection = VideoDownloaderEmbeddedDataParser.parse(result.stdout) else {
            throw VideoDownloaderFailure.fileSafety
        }
        return inspection
    }

    /// Executes the full post-processing pipeline on a downloaded media file:
    /// 1. Verifies reported path in staging directory.
    /// 2. Embeds subtitles if requested.
    /// 3. Embeds cover artwork if requested.
    /// 4. Verifies container integrity and normalizes file extension via ffprobe.
    /// 5. Publishes completed file atomically to destination.
    func process(reportedPath: String,
                 staging: URL,
                 request: VideoDownloaderRequest,
                 ffmpegPath: String,
                 ffprobePath: String,
                 initialWarnings: [VideoDownloaderWarning] = [],
                 subtitleFailedDuringMediaDownload: Bool = false,
                 operation: VideoDownloaderProcessOperation) throws -> VideoDownloaderDownloadResult {
        var warnings = initialWarnings

        var mediaFile = try VideoDownloaderFileSupport.finalMedia(in: staging,
                                                                  reportedPath: reportedPath,
                                                                  mode: request.mode)

        var suppressMissingSubtitleWarning = subtitleFailedDuringMediaDownload
            && request.mode == .video

        // 1. Embed subtitle track if requested and available
        if request.mode == .video, let subtitle = request.subtitle, !subtitleFailedDuringMediaDownload {
            do {
                mediaFile = try embedSubtitle(in: mediaFile,
                                              subtitle: subtitle,
                                              staging: staging,
                                              ffmpegPath: ffmpegPath,
                                              operation: operation)
                suppressMissingSubtitleWarning = false
            } catch let failure as VideoDownloaderFailure where failure == .cancelled {
                throw failure
            } catch {
                appendWarning(.subtitle, to: &warnings)
            }
        }

        // 2. Embed cover art whenever inspection provides a thumbnail
        if let thumbnailURL = request.media.thumbnailURL {
            do {
                mediaFile = try embedArtwork(in: mediaFile,
                                              thumbnailURL: thumbnailURL,
                                              staging: staging,
                                              mode: request.mode,
                                              ffmpegPath: ffmpegPath,
                                              operation: operation)
            } catch let failure as VideoDownloaderFailure where failure == .cancelled {
                throw failure
            } catch {
                appendWarning(.artwork, to: &warnings)
            }
        }

        // 3. Inspect container integrity & normalize file extension
        let normalized = try verifyAndNormalizeMedia(in: mediaFile,
                                                     staging: staging,
                                                     request: request,
                                                     ffprobePath: ffprobePath,
                                                     operation: operation,
                                                     suppressMissingSubtitleWarning: suppressMissingSubtitleWarning)
        mediaFile = normalized.file
        normalized.warnings.forEach { appendWarning($0, to: &warnings) }

        if operation.wasCancelled { throw VideoDownloaderFailure.cancelled }

        // 4. Publish final media file into destination directory
        let published = try VideoDownloaderFileSupport.publish(mediaFile, into: request.destination)
        return VideoDownloaderDownloadResult(file: published, warnings: warnings)
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
        let result = runner(VideoDownloaderCommandBuilder.ffmpegSubtitle(
            ffmpegPath: ffmpegPath,
            input: mediaFile,
            subtitle: sidecar,
            output: temporary,
            language: subtitle.code),
            nil,
            operation,
            timeoutPolicy.postProcessing,
            64 * 1024,
            128 * 1024,
            staging)
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
        let result = runner(VideoDownloaderCommandBuilder.ffmpegArtwork(ffmpegPath: ffmpegPath,
                                                                        input: mediaFile,
                                                                        artwork: artwork,
                                                                        output: temporary,
                                                                        mode: mode),
                            nil,
                            operation,
                            timeoutPolicy.postProcessing,
                            64 * 1024,
                            128 * 1024,
                            staging)
        if operation.wasCancelled { throw VideoDownloaderFailure.cancelled }
        guard result.succeeded,
              VideoDownloaderFileSupport.isContained(temporary, in: staging),
              let outputSize = try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              outputSize > 0 else { throw VideoDownloaderOptionalEmbedError.artwork }
        _ = try fileManager.replaceItemAt(mediaFile, withItemAt: temporary,
                                          backupItemName: nil, options: [])
        return mediaFile
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

    private func appendWarning(_ warning: VideoDownloaderWarning,
                               to warnings: inout [VideoDownloaderWarning]) {
        if !warnings.contains(warning) { warnings.append(warning) }
    }
}
