// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import AVFoundation
import CoreImage
import Foundation

enum VideoOps {
    static func trim(_ url: URL, start: Double, end: Double, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        guard start.isFinite, end.isFinite, start >= 0, end > start else { throw OpenTangerineError.invalidInput("Choose a valid trim range.") }
        let format = FileFormat.detect(url) ?? .mp4
        let range = AVExporter.timeRange(start: start, end: end)
        if VideoEngine.nativeTargets.contains(format), await MediaInfo.isNativelyReadable(url) {
            try await AVExporter.export(asset: AVURLAsset(url: url), to: destination, format: format, preset: AVAssetExportPresetPassthrough, timeRange: range, progress: progress)
            return
        }
        // Stream-copy seeks to a keyframe and can include content outside the chosen range.
        let args = ["-ss", FFmpeg.timecode(start), "-i", url.path, "-t", FFmpeg.timecode(end - start)] + VideoEngine.codecArguments(for: format) + [destination.path]
        try await FFmpeg.run(args, purpose: "Trimming video", duration: end - start, progress: progress)
    }

    static func split(_ url: URL, at points: [Double], duration: Double, into folder: URL, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let sorted = ([0] + points.filter { $0 > 0 && $0 < duration }.sorted() + [duration])
        var outputs: [URL] = []
        let base = ConversionMatrix.strippedBaseName(url.lastPathComponent)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<(sorted.count - 1) {
            let start = sorted[index], end = sorted[index + 1]
            guard end - start > 0.05 else { continue }
            let output = folder.appendingPathComponent("\(base) part \(index + 1).\(url.pathExtension)")
            let count = Double(sorted.count - 1)
            try await trim(url, start: start, end: end, to: output) { p in progress((Double(index) + p) / count) }
            outputs.append(output)
        }
        return outputs
    }

    static func videoComposition(for asset: AVAsset, crop: CGRect?, outputSize: CGSize?, filter: ((CIImage, CMTime) -> CIImage)? = nil) async throws -> AVVideoComposition {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw OpenTangerineError.invalidInput("No video track found.") }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let fps = try await track.load(.nominalFrameRate)
        let oriented = CGRect(origin: .zero, size: natural).applying(transform)
        let orientedSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let cropRect = crop ?? CGRect(origin: .zero, size: orientedSize)
        let renderSize = outputSize ?? cropRect.size

        let composition = AVMutableVideoComposition(asset: asset) { request in
            var image = request.sourceImage
            let flippedCrop = CGRect(x: cropRect.minX, y: orientedSize.height - cropRect.maxY, width: cropRect.width, height: cropRect.height)
            if let filter { image = filter(image, request.compositionTime) }
            image = image.cropped(to: flippedCrop)
            image = image.transformed(by: CGAffineTransform(translationX: -flippedCrop.minX, y: -flippedCrop.minY))
            let scale = min(renderSize.width / flippedCrop.width, renderSize.height / flippedCrop.height)
            if abs(scale - 1) > 0.001 { image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
            request.finish(with: image.cropped(to: CGRect(origin: .zero, size: renderSize)), context: nil)
        }
        composition.renderSize = CGSize(width: (renderSize.width / 2).rounded(.down) * 2, height: (renderSize.height / 2).rounded(.down) * 2)
        composition.frameDuration = CMTime(value: 1, timescale: fps > 0 ? CMTimeScale(fps.rounded()) : 30)
        return composition
    }

    static func crop(_ url: URL, rect: CGRect, outputSize: CGSize?, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        let asset = AVURLAsset(url: url)
        if !FFmpeg.isAvailable, await MediaInfo.isNativelyReadable(url) {
            let composition = try await videoComposition(for: asset, crop: rect, outputSize: outputSize)
            try await AVExporter.export(asset: asset, to: destination, format: .mp4, preset: AVAssetExportPresetHighestQuality, videoComposition: composition, progress: progress)
            return
        }
        var filters = ["crop=\(Int(rect.width)):\(Int(rect.height)):\(Int(rect.minX)):\(Int(rect.minY))"]
        if let outputSize { filters.append("scale=\(Int(outputSize.width)):\(Int(outputSize.height))") }
        try await VideoEngine.ffmpegConvert(source: url, destination: destination, target: .mp4, videoFilters: filters, progress: progress)
    }

    static func changeSpeed(_ url: URL, factor: Double, preservePitch: Bool, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        guard factor.isFinite, factor > 0 else { throw OpenTangerineError.invalidInput("Speed must be greater than zero.") }
        let asset = AVURLAsset(url: url)
        guard !FFmpeg.isAvailable, await MediaInfo.isNativelyReadable(url) else {
            let info = try await streamInfo(url)
            let videoFilter = "setpts=\(1 / factor)*PTS"
            let audioFilter = preservePitch ? atempoChain(factor) : "asetrate=\(info.sampleRate)*\(factor),aresample=\(info.sampleRate)"
            let duration = (await FFmpeg.probeDuration(url) ?? 0) / factor
            var args = ["-i", url.path, "-vf", videoFilter]
            if info.hasAudio { args += ["-af", audioFilter] }
            args += VideoEngine.codecArguments(for: .mp4) + [destination.path]
            try await FFmpeg.run(args, purpose: "Changing speed", duration: duration, progress: progress)
            return
        }
        let composition = AVMutableComposition()
        let duration = try await asset.load(.duration)
        let fullRange = CMTimeRange(start: .zero, duration: duration)
        let scaled = CMTimeMultiplyByFloat64(duration, multiplier: 1 / factor)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audioMixParams: [AVMutableAudioMixInputParameters] = []
        for source in videoTracks {
            guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try track.insertTimeRange(fullRange, of: source, at: .zero)
            track.scaleTimeRange(fullRange, toDuration: scaled)
            track.preferredTransform = try await source.load(.preferredTransform)
        }
        for source in audioTracks {
            guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try track.insertTimeRange(fullRange, of: source, at: .zero)
            track.scaleTimeRange(fullRange, toDuration: scaled)
            let params = AVMutableAudioMixInputParameters(track: track)
            params.audioTimePitchAlgorithm = preservePitch ? .spectral : .varispeed
            audioMixParams.append(params)
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = audioMixParams
        try await AVExporter.export(asset: composition, to: destination, format: .mp4, preset: AVAssetExportPresetHighestQuality, audioMix: audioMixParams.isEmpty ? nil : mix, progress: progress)
    }

    static func atempoChain(_ factor: Double) -> String {
        guard factor.isFinite, factor > 0 else { return "anull" }
        var remaining = factor
        var parts: [String] = []
        while remaining > 2.0 { parts.append("atempo=2.0"); remaining /= 2.0 }
        while remaining < 0.5 { parts.append("atempo=0.5"); remaining /= 0.5 }
        parts.append(String(format: "atempo=%.4f", remaining))
        return parts.joined(separator: ",")
    }

    static func join(_ urls: [URL], to destination: URL, progress: @escaping (Double) -> Void) async throws {
        guard !urls.isEmpty else { throw OpenTangerineError.invalidInput("Choose at least one video to join.") }
        var allNative = true
        for url in urls {
            if !(await MediaInfo.isNativelyReadable(url)) { allNative = false }
        }
        if allNative && !FFmpeg.isAvailable {
            let composition = AVMutableComposition()
            let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            var cursor = CMTime.zero
            var canvas: CGSize?
            var instructions: [AVMutableVideoCompositionInstruction] = []
            for url in urls {
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration)
                let range = CMTimeRange(start: .zero, duration: duration)
                if let source = try await asset.loadTracks(withMediaType: .video).first, let videoTrack {
                    try videoTrack.insertTimeRange(range, of: source, at: cursor)
                    let natural = try await source.load(.naturalSize)
                    let transform = try await source.load(.preferredTransform)
                    let oriented = CGRect(origin: .zero, size: natural).applying(transform)
                    let size = CGSize(width: abs(oriented.width), height: abs(oriented.height))
                    if canvas == nil { canvas = size }
                    let target = canvas ?? size
                    let scale = min(target.width / size.width, target.height / size.height)
                    let translate = CGAffineTransform(translationX: (target.width - size.width * scale) / 2 - oriented.minX * scale, y: (target.height - size.height * scale) / 2 - oriented.minY * scale)
                    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                    layer.setTransform(transform.concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(translate), at: cursor)
                    let instruction = AVMutableVideoCompositionInstruction()
                    instruction.timeRange = CMTimeRange(start: cursor, duration: duration)
                    instruction.layerInstructions = [layer]
                    instructions.append(instruction)
                }
                if let source = try await asset.loadTracks(withMediaType: .audio).first, let audioTrack {
                    try audioTrack.insertTimeRange(range, of: source, at: cursor)
                }
                cursor = CMTimeAdd(cursor, duration)
            }
            let videoComposition = AVMutableVideoComposition()
            videoComposition.instructions = instructions
            videoComposition.renderSize = canvas ?? CGSize(width: 1920, height: 1080)
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            try await AVExporter.export(asset: composition, to: destination, format: .mp4, preset: AVAssetExportPresetHighestQuality, videoComposition: videoComposition, progress: progress)
            return
        }
        var args: [String] = []
        for url in urls { args += ["-i", url.path] }
        let first = try await streamInfo(urls[0])
        let w = max(2, first.width / 2 * 2), h = max(2, first.height / 2 * 2)
        var filter = ""
        for index in urls.indices {
            let info = try await streamInfo(urls[index])
            filter += "[\(index):v]scale=\(w):\(h):force_original_aspect_ratio=decrease,pad=\(w):\(h):(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,setpts=PTS-STARTPTS[v\(index)];"
            if info.hasAudio {
                filter += "[\(index):a]aresample=48000,aformat=channel_layouts=stereo,asetpts=PTS-STARTPTS[a\(index)];"
            } else {
                let duration = await FFmpeg.probeDuration(urls[index]) ?? 0
                guard duration > 0 else { throw OpenTangerineError.invalidInput("Could not read the video duration.") }
                filter += "anullsrc=r=48000:cl=stereo,atrim=duration=\(duration)[a\(index)];"
            }
        }
        filter += urls.indices.map { "[v\($0)][a\($0)]" }.joined() + "concat=n=\(urls.count):v=1:a=1[v][a]"
        args += ["-filter_complex", filter, "-map", "[v]", "-map", "[a]"] + VideoEngine.codecArguments(for: .mp4) + [destination.path]
        var total = 0.0
        for url in urls { total += await FFmpeg.probeDuration(url) ?? 0 }
        try await FFmpeg.run(args, purpose: "Joining videos", duration: total, progress: progress)
    }

    private static func streamInfo(_ url: URL) async throws -> (width: Int, height: Int, hasAudio: Bool, sampleRate: Int) {
        guard let probe = FFmpeg.probePath else { throw OpenTangerineError.ffmpegMissing("Reading media streams") }
        let result = try await ConvertShell.run(probe, ["-v", "error", "-show_streams", "-of", "json", url.path])
        guard result.succeeded, let data = result.stdout.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]],
              let video = streams.first(where: { $0["codec_type"] as? String == "video" }) else {
            throw OpenTangerineError.invalidInput("No readable video stream found.")
        }
        let audio = streams.first { $0["codec_type"] as? String == "audio" }
        return (video["width"] as? Int ?? 0, video["height"] as? Int ?? 0, audio != nil, Int(audio?["sample_rate"] as? String ?? "48000") ?? 48000)
    }

    static func snapshot(_ url: URL, at seconds: Double) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        if let result = try? await generator.image(at: time) { return result.image }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("opentangerine-frame-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temp) }
        try await FFmpeg.run(["-ss", FFmpeg.timecode(seconds), "-i", url.path, "-frames:v", "1", temp.path], purpose: "Extracting frame")
        return try ImageIOBridge.load(temp)
    }

    static func redact(_ url: URL, redactions: [Redaction], displaySize: CGSize, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        let asset = AVURLAsset(url: url)
        guard !FFmpeg.isAvailable, await MediaInfo.isNativelyReadable(url) else {
            guard displaySize.width > 0, displaySize.height > 0 else { throw OpenTangerineError.invalidInput("Invalid video preview size.") }
            let info = try await streamInfo(url)
            let sx = Double(info.width) / displaySize.width, sy = Double(info.height) / displaySize.height
            var filters: [String] = []
            for (index, r) in redactions.enumerated() {
                let x = max(0, min(info.width - 1, Int(r.rect.minX * sx)))
                let y = max(0, min(info.height - 1, Int(r.rect.minY * sy)))
                let w = min(info.width - x, max(1, Int(r.rect.width * sx)))
                let h = min(info.height - y, max(1, Int(r.rect.height * sy)))
                let enable = r.end.isFinite ? ":enable='between(t,\(r.start),\(r.end))'" : ":enable='gte(t,\(r.start))'"
                switch r.style {
                case .solid: filters.append("drawbox=x=\(x):y=\(y):w=\(w):h=\(h):color=black:t=fill\(enable)")
                case .blur, .pixelate:
                    let effect = r.style == .blur ? "boxblur=luma_radius=\(max(1, min(w, h) / 8)):luma_power=2" : "scale=\(max(1,w/12)):\(max(1,h/12)),scale=\(w):\(h):flags=neighbor"
                    filters.append("split[base\(index)][region\(index)];[region\(index)]crop=\(w):\(h):\(x):\(y),\(effect)[patch\(index)];[base\(index)][patch\(index)]overlay=\(x):\(y)\(enable)")
                }
            }
            try await VideoEngine.ffmpegConvert(source: url, destination: destination, target: .mp4, videoFilters: filters, progress: progress)
            return
        }
        let composition = try await videoComposition(for: asset, crop: nil, outputSize: nil) { image, time in
            let seconds = CMTimeGetSeconds(time)
            let active = redactions.filter { seconds >= $0.start && seconds <= $0.end }
            guard !active.isEmpty else { return image }
            let scaleX = image.extent.width / displaySize.width
            let scaleY = image.extent.height / displaySize.height
            let scaled = active.map { r -> Redaction in
                var copy = r
                copy.rect = CGRect(x: r.rect.minX * scaleX, y: r.rect.minY * scaleY, width: r.rect.width * scaleX, height: r.rect.height * scaleY)
                return copy
            }
            return ImageOps.redact(image, redactions: scaled, flipped: true)
        }
        try await AVExporter.export(asset: asset, to: destination, format: .mp4, preset: AVAssetExportPresetHighestQuality, videoComposition: composition, progress: progress)
    }

    static func compress(_ url: URL, preset: CompressionPreset, targetBytes: Int64?, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        let info = await MediaInfo.load(url)
        let target = FileFormat.detect(url) ?? .mp4
        let outputFormat: FileFormat = VideoEngine.nativeTargets.contains(target) ? target : .mp4
        if let targetBytes, info.duration > 0 {
            let totalBits = Double(targetBytes) * 8 * 0.94
            let audioBits = Double(min(preset.audioBitrate, 128_000))
            let videoBitrate = max(150_000, Int(totalBits / info.duration - audioBits))
            let scale = preset.videoScale
            var filters: [String] = []
            if scale < 1 { filters.append("scale=trunc(iw*\(scale)/2)*2:trunc(ih*\(scale)/2)*2") }
            try await VideoEngine.ffmpegConvert(source: url, destination: destination, target: outputFormat, videoFilters: filters, videoBitrate: videoBitrate, audioBitrate: Int(audioBits), progress: progress)
            return
        }
        if !FFmpeg.isAvailable, await MediaInfo.isNativelyReadable(url) {
            let longEdge = max(info.naturalSize.width, info.naturalSize.height) * preset.videoScale
            let presetName: String
            if preset == .strong || longEdge <= 1280 {
                presetName = longEdge > 1280 ? AVAssetExportPreset1280x720 : (longEdge > 960 ? AVAssetExportPreset960x540 : AVAssetExportPreset640x480)
            } else {
                presetName = longEdge > 1920 ? AVAssetExportPreset1920x1080 : AVAssetExportPreset1280x720
            }
            try await AVExporter.export(asset: AVURLAsset(url: url), to: destination, format: outputFormat, preset: presetName, progress: progress)
            return
        }
        let videoBitrate = Int(max(300_000, info.estimatedBitrate * preset.videoBitrateFactor))
        var filters: [String] = []
        if preset.videoScale < 1 { filters.append("scale=trunc(iw*\(preset.videoScale)/2)*2:trunc(ih*\(preset.videoScale)/2)*2") }
        try await VideoEngine.ffmpegConvert(source: url, destination: destination, target: outputFormat, videoFilters: filters, videoBitrate: videoBitrate, audioBitrate: preset.audioBitrate, progress: progress)
    }
}

