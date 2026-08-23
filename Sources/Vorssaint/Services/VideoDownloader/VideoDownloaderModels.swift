// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum VideoDownloaderOutputMode: String {
    case video
    case audio

    var allowedExtensions: Set<String> {
        self == .audio ? ["m4a"] : ["mp4", "mkv"]
    }
}

enum VideoDownloaderQuality: Hashable {
    case best
    case height(Int)

    static func highest(in heights: [Int]) -> VideoDownloaderQuality {
        guard let height = heights.max(), height > 0 else { return .best }
        return .height(height)
    }

}

struct VideoDownloaderQualityFallback: Equatable {
    let requestedHeight: Int
    let actualHeight: Int

    static func detect(requested: VideoDownloaderQuality,
                       actualHeight: Int?) -> VideoDownloaderQualityFallback? {
        guard case let .height(requestedHeight) = requested,
              let actualHeight, actualHeight > 0, actualHeight < requestedHeight else { return nil }
        return VideoDownloaderQualityFallback(requestedHeight: requestedHeight,
                                              actualHeight: actualHeight)
    }
}

enum VideoDownloaderSubtitleSource: String, Hashable {
    case manual
    case automatic
}

struct VideoDownloaderSubtitleTrack: Hashable, Identifiable {
    let code: String
    let source: VideoDownloaderSubtitleSource
    let name: String?

    var id: String { "\(source.rawValue):\(code)" }
}

/// Direct media URLs (like raw CDN streams) often lack codec tags in initial metadata probes.
/// We track .unknown separately from .unavailable so we don't preemptively block downloads
/// that yt-dlp can still successfully fetch and demux.
enum VideoDownloaderStreamAvailability: Equatable {
    case available
    case unavailable
    case unknown

    var canAttempt: Bool { self != .unavailable }
}

struct VideoDownloaderMedia: Equatable {
    let title: String
    let uploader: String?
    let duration: TimeInterval?
    let thumbnailURL: URL?
    let previewThumbnailURL: URL?
    let heights: [Int]
    let estimatedSizes: [Int: Int64]
    let estimatedAudioSize: Int64?
    let videoAvailability: VideoDownloaderStreamAvailability
    let audioAvailability: VideoDownloaderStreamAvailability
    let subtitles: [VideoDownloaderSubtitleTrack]
    let hasChapters: Bool

    init(title: String,
         uploader: String?,
         duration: TimeInterval?,
         thumbnailURL: URL?,
         previewThumbnailURL: URL? = nil,
         heights: [Int],
         estimatedSizes: [Int: Int64] = [:],
         estimatedAudioSize: Int64? = nil,
         videoAvailability: VideoDownloaderStreamAvailability,
         audioAvailability: VideoDownloaderStreamAvailability,
         subtitles: [VideoDownloaderSubtitleTrack],
         hasChapters: Bool) {
        self.title = title
        self.uploader = uploader
        self.duration = duration
        self.thumbnailURL = thumbnailURL
        self.previewThumbnailURL = previewThumbnailURL ?? thumbnailURL
        self.heights = heights
        self.estimatedSizes = estimatedSizes
        self.estimatedAudioSize = estimatedAudioSize
        self.videoAvailability = videoAvailability
        self.audioAvailability = audioAvailability
        self.subtitles = subtitles
        self.hasChapters = hasChapters
    }

    var canAttemptVideo: Bool { videoAvailability.canAttempt }
    var canAttemptAudio: Bool { audioAvailability.canAttempt }
    var subtitleOptions: [VideoDownloaderSubtitleTrack] {
        VideoDownloaderSubtitleSelection.pickerTracks(in: subtitles)
    }

    /// Extractors frequently break their JSON metadata parsers before actual downloading breaks.
    /// Returning a fallback shell lets the user attempt the download directly rather than
    /// being blocked by a failed inspection pass.
    static func fallback(for source: ValidatedVideoURL) -> VideoDownloaderMedia {
        let title: String
        if let host = source.value.host, !host.isEmpty {
            title = host
        } else {
            title = source.string
        }
        return VideoDownloaderMedia(title: title,
                                    uploader: nil,
                                    duration: nil,
                                    thumbnailURL: nil,
                                    heights: [],
                                    estimatedSizes: [:],
                                    estimatedAudioSize: nil,
                                    videoAvailability: .unknown,
                                    audioAvailability: .unknown,
                                    subtitles: [],
                                    hasChapters: false)
    }
}

struct VideoDownloaderRequest {
    let source: ValidatedVideoURL
    let mode: VideoDownloaderOutputMode
    let quality: VideoDownloaderQuality
    let subtitle: VideoDownloaderSubtitleTrack?
    let destination: URL
    let media: VideoDownloaderMedia

    func withQuality(_ value: VideoDownloaderQuality) -> VideoDownloaderRequest {
        VideoDownloaderRequest(source: source,
                               mode: mode,
                               quality: value,
                               subtitle: subtitle,
                               destination: destination,
                               media: media)
    }

    var videoWeight: Double? {
        guard mode == .video else { return nil }
        let combinedBytes: Int64?
        switch quality {
        case let .height(h): combinedBytes = media.estimatedSizes[h]
        case .best: combinedBytes = media.heights.first.flatMap { media.estimatedSizes[$0] }
        }
        guard let combinedBytes, let audioBytes = media.estimatedAudioSize,
              combinedBytes > audioBytes, audioBytes > 0 else { return nil }
        let (videoOnlyBytes, underflow) = combinedBytes.subtractingReportingOverflow(audioBytes)
        guard !underflow else { return nil }
        let total = Double(combinedBytes)
        guard total > 0 else { return nil }
        return Double(videoOnlyBytes) / total
    }
}

struct VideoDownloaderProgress: Equatable {
    let fraction: Double?
    let speedBytesPerSecond: Double?
    let etaSeconds: TimeInterval?

    var isNetworkComplete: Bool { (fraction ?? 0) >= 1 }
}

/// Low-level yt-dlp telemetry stays decoupled inside the parser so rapid raw stream events
/// don't trigger unnecessary SwiftUI layout passes.
struct VideoDownloaderRawProgress: Equatable {
    let fraction: Double?
    let speedBytesPerSecond: Double?
    let etaSeconds: TimeInterval?
    let isAuxiliary: Bool
    let isCombinedMedia: Bool
}

struct VideoDownloaderProgressAggregator {
    private let transferCount: Int
    private let videoWeight: Double
    private var completedTransfers = 0
    private var currentTransferCompleted = false
    private var lastRawFraction: Double?
    private var lastOverallFraction: Double?

    init(expectsSeparateMediaTransfers: Bool, videoWeight: Double? = nil) {
        transferCount = expectsSeparateMediaTransfers ? 2 : 1
        if let videoWeight, videoWeight >= 0.5, videoWeight <= 0.98 {
            self.videoWeight = videoWeight
        } else {
            self.videoWeight = expectsSeparateMediaTransfers ? 0.85 : 1.0
        }
    }

    mutating func aggregate(_ progress: VideoDownloaderRawProgress) -> VideoDownloaderProgress {
        // yt-dlp reuses its main progress hook for sidecar downloads (subtitles/thumbnails).
        // We freeze the percentage during sidecars so the progress bar doesn't jump backward
        // right before completing.
        guard !progress.isAuxiliary else {
            return VideoDownloaderProgress(fraction: lastOverallFraction,
                                           speedBytesPerSecond: nil,
                                           etaSeconds: nil)
        }
        guard let rawFraction = progress.fraction else {
            return VideoDownloaderProgress(fraction: lastOverallFraction,
                                           speedBytesPerSecond: progress.speedBytesPerSecond,
                                           etaSeconds: progress.etaSeconds)
        }
        let fraction = min(max(rawFraction, 0), 1)
        // When a site provides a single muxed stream instead of split audio/video,
        // treating it as a two-stage download would freeze the progress bar at the weight boundary.
        if progress.isCombinedMedia || transferCount == 1 {
            let overall = max(lastOverallFraction ?? 0, fraction)
            lastRawFraction = fraction
            lastOverallFraction = overall
            currentTransferCompleted = fraction >= 1
            return VideoDownloaderProgress(fraction: overall,
                                           speedBytesPerSecond: progress.speedBytesPerSecond,
                                           etaSeconds: progress.etaSeconds)
        }
        // Because stdout buffering and `--progress-delta` throttling can skip the final 100% update
        // of the first stream, a sudden drop near 0% signals that the second transfer has started.
        if let previous = lastRawFraction,
           fraction < previous,
           (previous >= 0.99 || previous - fraction >= 0.5 || fraction < 0.05) {
            if !currentTransferCompleted {
                completedTransfers = min(completedTransfers + 1, transferCount)
            }
            currentTransferCompleted = false
        }
        if fraction >= 1, !currentTransferCompleted {
            completedTransfers = min(completedTransfers + 1, transferCount)
            currentTransferCompleted = true
        }
        let activeFraction = currentTransferCompleted ? 0 : fraction
        let candidate: Double
        let eta: TimeInterval?
        if completedTransfers == 0 {
            candidate = min(activeFraction * videoWeight, videoWeight)
            if let rawETA = progress.etaSeconds, rawETA > 0, activeFraction < 0.999 {
                let remainingOverall = 1.0 - candidate
                let remainingStreamPortion = (1.0 - activeFraction) * videoWeight
                eta = rawETA * (remainingOverall / max(remainingStreamPortion, 0.001))
            } else {
                eta = progress.etaSeconds
            }
        } else {
            candidate = min(videoWeight + activeFraction * (1.0 - videoWeight), 1.0)
            eta = progress.etaSeconds
        }
        let overall = max(lastOverallFraction ?? 0, candidate)
        lastRawFraction = fraction
        lastOverallFraction = overall
        return VideoDownloaderProgress(fraction: overall,
                                       speedBytesPerSecond: progress.speedBytesPerSecond,
                                       etaSeconds: eta)
    }

    mutating func complete() -> VideoDownloaderProgress? {
        guard lastOverallFraction != 1 else { return nil }
        lastOverallFraction = 1
        completedTransfers = transferCount
        currentTransferCompleted = true
        return VideoDownloaderProgress(fraction: 1, speedBytesPerSecond: nil, etaSeconds: nil)
    }
}

/// Protect against infinite, negative, or corrupt extractor duration values
/// that could overflow Foundation's DateComponentsFormatter or crash the UI.
enum VideoDownloaderNumericPolicy {
    static let maximumTimeInterval: TimeInterval = 10 * 365.25 * 24 * 60 * 60

    static func timeInterval(_ value: Double?) -> TimeInterval? {
        guard let value, value.isFinite, value > 0,
              value <= maximumTimeInterval else { return nil }
        return value
    }

    static func wholeSeconds(_ value: TimeInterval) -> Int? {
        guard let value = timeInterval(value) else { return nil }
        return Int(value.rounded())
    }
}

/// Formats file sizes in bytes into localized human-readable representations (e.g. "~145 MB").
enum VideoDownloaderByteCountFormatter {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static func formattedApproximateSize(_ bytes: Int64?) -> String? {
        guard let bytes, bytes > 0 else { return nil }
        return "~\(formatter.string(fromByteCount: bytes))"
    }
}

/// Prevent race conditions where rapid URL changes or slow network replies
/// allow an older asynchronous task to overwrite newer state.
enum VideoDownloaderCallbackGate {
    static func accepts(_ callbackID: UUID, currentID: UUID?) -> Bool {
        callbackID == currentID
    }
}

enum VideoDownloaderFailure: Error, Equatable {
    case inspectionTimedOut
    case inspectionFailed
    case inspectionTooLarge
    case malformedInspection
    case playlist
    case live
    case drm
    case restricted
    case missingDependencies
    case downloadFailed
    case rateLimited
    /// Modern extractors need external JavaScript solvers (EJS) from GitHub. Catching this
    /// specifically lets us tell the user their network is blocking GitHub rather than blaming the video.
    case ejsComponentFailure
    case setupBusy
    case setupFailed
    case terminalPermission
    case cookiesPermission
    case mp4Remux
    case fileSafety
    case cancelled
    /// Extractor errors can dump massive Python tracebacks. We truncate them so they stay readable
    /// in popover alerts without freezing UI layout rendering.
    case extractorError(String)
}

enum VideoDownloaderWarning: Equatable, Hashable {
    case subtitle
    case subtitleRateLimited
    case artwork
    case metadata
    case chapters
}

struct VideoDownloaderDownloadResult: Equatable {
    let file: URL
    let warnings: [VideoDownloaderWarning]
}

/// Subprocesses can hang indefinitely on dead TCP sockets or stalled post-processors.
/// Hard timeouts ensure we clean up resources and stay responsive to cancellation.
struct VideoDownloaderTimeoutPolicy: Equatable {
    let inspection: TimeInterval
    let download: TimeInterval
    let postProcessing: TimeInterval
    let homebrewSetup: TimeInterval

    static let `default` = VideoDownloaderTimeoutPolicy(
        inspection: 20,
        download: 2 * 60 * 60,
        postProcessing: 10 * 60,
        homebrewSetup: 30 * 60
    )
}

enum VideoURLValidationError: Error, Equatable {
    case empty
    case tooLong
    case controlCharacter
    case unsupportedScheme
    case missingHost
    case credentials
    case malformed
}

struct ValidatedVideoURL: Equatable {
    let value: URL
    let string: String
}

struct VideoDownloaderToolCommand: Equatable {
    let executable: String
    let arguments: [String]
    let executableSearchDirectories: [String]

    init(executable: String,
         arguments: [String],
         executableSearchDirectories: [String] = []) {
        self.executable = executable
        self.arguments = arguments
        self.executableSearchDirectories = executableSearchDirectories
    }
}

struct VideoDownloaderEmbeddedDataInspection: Equatable {
    let hasVideo: Bool
    let hasAudio: Bool
    let hasSubtitle: Bool
    let hasArtwork: Bool
    let hasChapters: Bool
    let hasMetadata: Bool
    let container: VideoDownloaderMediaContainer?
}

enum VideoDownloaderMediaContainer: String, Equatable {
    case mp4
    case mkv
    case m4a

    var pathExtension: String { rawValue }
}

enum VideoDownloaderProtocolEvent: Equatable {
    case progress(VideoDownloaderProgress)
    case title(String)
    case selectedVideoHeight(Int?)
}

enum VideoDownloaderParsedEvent: Equatable {
    case progress(VideoDownloaderRawProgress)
    case title(String)
    case selectedVideoHeight(Int?)
    case path(String)
}

enum VideoDownloaderTool: String, CaseIterable, Hashable {
    case ytDlp
    case ffmpeg
    case ffprobe
    case deno

    var executableName: String {
        switch self {
        case .ytDlp: return "yt-dlp"
        case .ffmpeg: return "ffmpeg"
        case .ffprobe: return "ffprobe"
        case .deno: return "deno"
        }
    }

    /// Homebrew packages ffprobe inside the ffmpeg formula; mapping it prevents failed searches for a standalone formula.
    var formula: String {
        switch self {
        case .ffprobe: return "ffmpeg"
        default: return executableName
        }
    }

    static func formulae(for tools: Set<VideoDownloaderTool>) -> [String] {
        var seen = Set<String>()
        return allCases
            .filter { tools.contains($0) }
            .compactMap { tool in
                seen.insert(tool.formula).inserted ? tool.formula : nil
            }
    }
}

struct VideoDownloaderDependencies: Equatable {
    var paths: [VideoDownloaderTool: String]

    var missing: Set<VideoDownloaderTool> {
        Set(VideoDownloaderTool.allCases.filter { paths[$0] == nil })
    }

    var isReady: Bool { missing.isEmpty }
}
