// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import AVFoundation
import Foundation

struct VideoEngine: ConversionEngine {
    static let nativeTargets: Set<FileFormat> = [.mp4, .mov]

    func supports(from: FileFormat, to: FileFormat) -> Bool {
        guard from.category == .video else { return false }
        return to.category == .video || to == .mp3
    }

    func convert(_ request: ConversionRequest) async throws {
        let o = request.options
        // The native exporter takes no settings, so a changed option goes to ffmpeg when it is there.
        let customised = o.maxHeight != nil || o.videoCRF != nil || o.removeAudio || o.audioBitrate != nil
        if Self.nativeTargets.contains(request.target), request.sourceFormat != .gif, !(customised && FFmpeg.isAvailable),
           await MediaInfo.isNativelyReadable(request.source) {
            do {
                let asset = AVURLAsset(url: request.source)
                try await AVExporter.export(asset: asset, to: request.destination, format: request.target, preset: AVAssetExportPresetHighestQuality, progress: request.progress)
                return
            } catch {
                try Task.checkCancellation()
                guard FFmpeg.isAvailable else { throw error }
            }
        }
        if request.target == .mp3 {
            try await AudioEngine.ffmpegConvert(source: request.source, destination: request.destination, target: .mp3,
                                            bitrate: request.options.audioBitrate, progress: request.progress)
            return
        }
        try await Self.ffmpegConvert(source: request.source, destination: request.destination, target: request.target,
                                     options: request.options, progress: request.progress)
    }

    static func codecArguments(for target: FileFormat, videoBitrate: Int? = nil, audioBitrate: Int? = nil) -> [String] {
        var args: [String] = []
        switch target {
        case .mp4:
            args += ["-c:v", "libx264", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart", "-f", "mp4"]
        case .mov:
            args += ["-c:v", "libx264", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-f", "mov"]
        case .mkv:
            args += ["-c:v", "libx264", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-f", "matroska"]
        case .webm:
            args += ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", "-row-mt", "1", "-c:a", "libopus", "-f", "webm"]
        case .avi:
            args += ["-c:v", "mpeg4", "-vtag", "xvid", "-q:v", "4", "-c:a", "libmp3lame", "-f", "avi"]
        case .wmv:
            args += ["-c:v", "wmv2", "-q:v", "4", "-c:a", "wmav2", "-f", "asf"]
        default:
            break
        }
        if let videoBitrate, target != .webm, target != .avi, target != .wmv {
            args += ["-b:v", "\(videoBitrate)", "-maxrate", "\(Int(Double(videoBitrate) * 1.4))", "-bufsize", "\(videoBitrate * 2)"]
        } else if target == .mp4 || target == .mov || target == .mkv {
            args += ["-crf", "20"]
        }
        if let audioBitrate, target != .avi, target != .wmv { args += ["-b:a", "\(audioBitrate)"] }
        return args
    }

    static func ffmpegConvert(source: URL, destination: URL, target: FileFormat, videoFilters: [String] = [], videoBitrate: Int? = nil, audioBitrate: Int? = nil, options: ConvertOptions = ConvertOptions(), progress: @escaping (Double) -> Void) async throws {
        let duration = await FFmpeg.probeDuration(source)
        if target == .gif {
            let filters = videoFilters + ["fps=\(max(1, options.gifFPS))", "scale='min(\(max(16, options.gifWidth)),iw)':-2:flags=lanczos", "split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5"]
            let args = ["-i", source.path, "-vf", filters.joined(separator: ","), "-loop", "0", "-f", "gif", destination.path]
            try await FFmpeg.run(args, purpose: "Creating GIF", duration: duration, progress: progress)
            return
        }
        var args = ["-i", source.path, "-map_metadata", "0"]
        var filters = videoFilters
        if let height = options.maxHeight { filters.append("scale=-2:'min(\(height),ih)'") }
        if options.removeAudio { args.append("-an") }
        if target == .mp4 || target == .mov || target == .mkv || target == .webm {
            filters.append("scale=trunc(iw/2)*2:trunc(ih/2)*2")
        }
        if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }
        args += codecArguments(for: target, videoBitrate: videoBitrate, audioBitrate: options.audioBitrate ?? audioBitrate)
        if let crf = options.videoCRF, videoBitrate == nil, [.mp4, .mov, .mkv, .webm].contains(target) {
            // Later options win in ffmpeg, so this replaces the codec's default factor.
            args += ["-crf", "\(crf)"]
        }
        args.append(destination.path)
        try await FFmpeg.run(args, purpose: "Converting to \(target.displayName)", duration: duration, progress: progress)
    }
}

