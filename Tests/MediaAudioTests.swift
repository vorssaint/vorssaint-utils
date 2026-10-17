// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// MP3 output is judged by what macOS's own decoder plays back, not by the
/// encoder's internals: a wrong table, scale or bitstream field shows up as a
/// file that will not open, a channel that moved, or a tone buried in noise.
enum MediaAudioTests {
    static func run(_ suite: TestSuite) {
        configuration(suite)
        decisions(suite)
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                try await probe(suite)
            } catch {
                suite.expect(false, "MP3 fixture failed \(error)")
            }
            done.signal()
        }
        suite.expect(done.wait(timeout: .now() + 120) == .success,
                     "MP3 conversion checks finish within their deadline")
    }

    private static func configuration(_ suite: TestSuite) {
        for rate in [44_100, 48_000, 32_000] {
            for channels in [1, 2] {
                suite.expect((try? MediaMP3Encoder(sampleRate: rate, channelCount: channels, bitRate: 192)) != nil,
                             "MP3 encoder accepts \(rate) Hz with \(channels) channel(s)")
            }
        }
        suite.expect(MediaSupport.mp3BitRates.allSatisfy {
            (try? MediaMP3Encoder(sampleRate: 44_100, channelCount: 2, bitRate: $0)) != nil
        }, "every offered MP3 bitrate is one the encoder writes")
        suite.expect((try? MediaMP3Encoder(sampleRate: 22_050, channelCount: 2, bitRate: 192)) == nil
                     && (try? MediaMP3Encoder(sampleRate: 44_100, channelCount: 3, bitRate: 192)) == nil
                     && (try? MediaMP3Encoder(sampleRate: 44_100, channelCount: 2, bitRate: 100)) == nil,
                     "MP3 encoder refuses rates, layouts and bitrates MPEG-1 Layer III cannot carry")
    }

    private static func decisions(_ suite: TestSuite) {
        suite.expect(MediaSupport.sanitizedMP3BitRate(256) == 256
                     && MediaSupport.sanitizedMP3BitRate(100) == MediaSupport.defaultMP3BitRate
                     && MediaSupport.mp3BitRates.contains(MediaSupport.defaultMP3BitRate),
                     "a stored MP3 bitrate outside the offered set falls back to the default")
        suite.expect(MediaSupport.mp3SampleRate(forSourceRate: 48_000) == 48_000
                     && MediaSupport.mp3SampleRate(forSourceRate: 32_000) == 32_000
                     && MediaSupport.mp3SampleRate(forSourceRate: 96_000) == 44_100
                     && MediaSupport.mp3SampleRate(forSourceRate: 22_050) == 44_100
                     && MediaSupport.mp3SampleRate(forSourceRate: .nan) == 44_100,
                     "MP3 keeps a source rate MPEG-1 supports and resamples anything else to 44.1 kHz")
        suite.expect(MediaSupport.mp3ChannelCount(forSourceChannels: 1) == 1
                     && MediaSupport.mp3ChannelCount(forSourceChannels: 2) == 2
                     && MediaSupport.mp3ChannelCount(forSourceChannels: 6) == 2,
                     "MP3 keeps mono and mixes wider layouts down to stereo")
    }

    private static func probe(_ suite: TestSuite) async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-audio-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try framing(suite, folder: folder)
        try roundTrips(suite, folder: folder)
        try await conversion(suite, folder: folder)
        routing(suite, folder: folder)
    }

    // MARK: - Encoder

    private static func framing(_ suite: TestSuite, folder: URL) throws {
        for (rate, channels, bitRate) in [(44_100, 2, 192), (48_000, 2, 320), (32_000, 1, 128)] {
            let input = (0..<channels).map { tone(440 * Double($0 + 1), 0.4, rate: rate, seconds: 1.3) }
            let data = try encode(input, rate: rate, bitRate: bitRate)
            guard let frames = frames(in: data) else {
                suite.expect(false, "MP3 frames at \(rate) Hz tile the file with valid MPEG-1 Layer III headers")
                continue
            }
            suite.expect(frames.allSatisfy { $0.bitRate == bitRate && $0.sampleRate == rate
                                             && $0.channels == channels },
                         "every MP3 frame header states \(bitRate) kbps, \(rate) Hz and \(channels) channel(s)")
            let seconds = Double(frames.count * MediaMP3Encoder.samplesPerFrame) / Double(rate)
            let measured = Double(data.count * 8) / seconds / 1000
            suite.expectClose(measured, Double(bitRate), "MP3 at \(rate) Hz holds its constant bitrate",
                              tol: Double(bitRate) * 0.005)
            suite.expect(seconds >= 1.3, "MP3 frames cover every input sample at \(rate) Hz")
        }

        let empty = try MediaMP3Encoder(sampleRate: 44_100, channelCount: 2, bitRate: 192).finish()
        let emptyURL = folder.appendingPathComponent("empty.mp3")
        try empty.write(to: emptyURL)
        suite.expect((frames(in: empty)?.count ?? 0) >= 2 && (try? AVAudioFile(forReading: emptyURL)) != nil,
                     "an empty stream still ends as an MP3 a player opens")
    }

    private static func roundTrips(_ suite: TestSuite, folder: URL) throws {
        // Two different tones show whether each channel arrives where it left.
        let left = tone(440, 0.5, rate: 44_100, seconds: 1.2)
        let right = tone(1_000, 0.3, rate: 44_100, seconds: 1.2)
        let stereo = try decoded(encode([left, right], rate: 44_100, bitRate: 192, chunk: 1_000),
                                 folder: folder, name: "stereo")
        suite.expect(stereo.rate == 44_100 && stereo.channels.count == 2,
                     "stereo MP3 decodes at its source rate with both channels")
        if stereo.channels.count == 2, let lag = delay(of: left, in: stereo.channels[0]) {
            let leftMatch = match(left, stereo.channels[0], lag: lag)
            let rightMatch = match(right, stereo.channels[1], lag: lag)
            suite.expect(leftMatch.snr > 40 && rightMatch.snr > 40,
                         "both stereo channels come back clean through Apple's decoder (\(leftMatch.snr), \(rightMatch.snr) dB)")
            suite.expectClose(leftMatch.gain, 1, "MP3 keeps the source level", tol: 0.02)
            let tail = match(Array(left.suffix(2_048)), stereo.channels[0], lag: lag + left.count - 2_048, edge: 0)
            suite.expect(tail.snr > 30, "the last samples of the input are still in the MP3")
        } else {
            suite.expect(false, "stereo MP3 output aligns with its source")
        }

        for rate in [48_000, 32_000] {
            let speechLike = zip(tone(300, 0.4, rate: rate, seconds: 1), tone(2_000, 0.2, rate: rate, seconds: 1))
                .map { $0 + $1 }
            let mono = try decoded(encode([speechLike], rate: rate, bitRate: 128), folder: folder, name: "mono-\(rate)")
            if mono.channels.count == 1, mono.rate == Double(rate), let lag = delay(of: speechLike, in: mono.channels[0]) {
                let result = match(speechLike, mono.channels[0], lag: lag)
                suite.expect(result.snr > 35, "mono MP3 at \(rate) Hz comes back clean (\(result.snr) dB)")
            } else {
                suite.expect(false, "mono MP3 at \(rate) Hz decodes as one channel at its own rate")
            }
        }

        let quiet = [Float](repeating: 0, count: 30_000)
        let silent = try decoded(encode([quiet, quiet], rate: 44_100, bitRate: 128), folder: folder, name: "silence")
        suite.expect(silent.channels.count == 2 && silent.channels.allSatisfy { $0.allSatisfy { $0 == 0 } },
                     "silence encodes to exact silence")

        let leftOnly = tone(600, 0.4, rate: 44_100, seconds: 1)
        let oneSided = try decoded(encode([leftOnly, [Float](repeating: 0, count: leftOnly.count)],
                                          rate: 44_100, bitRate: 128), folder: folder, name: "left-only")
        suite.expect(oneSided.channels.count == 2 && oneSided.channels[1].allSatisfy { $0 == 0 }
                     && oneSided.channels[0].contains { abs($0) > 0.1 },
                     "a silent channel stays silent beside a busy one")
    }

    // MARK: - Converter

    private static func conversion(_ suite: TestSuite, folder: URL) async throws {
        let rate = 22_050
        let seconds = 1.5
        let wav = folder.appendingPathComponent("source.wav")
        try writeWAV([tone(440, 0.4, rate: rate, seconds: seconds), tone(1_000, 0.4, rate: rate, seconds: seconds)],
                     rate: rate, to: wav)
        let loaded = try await MediaAudioConverter.loadSource(from: AVURLAsset(url: wav))
        suite.expect(loaded.sampleRate == Double(rate) && loaded.channelCount == 2 && loaded.audioTracks.count == 1,
                     "the converter reads the source's rate, layout and track")

        let tag = MediaAudioConverter.Tag(title: "Señorita ♪ 歌", artist: "The Vorssaints", album: "Encoder Sessions",
                                          artwork: jpeg())
        let source = MediaAudioConverter.Source(asset: loaded.asset, audioTracks: loaded.audioTracks,
                                                duration: loaded.duration, sampleRate: loaded.sampleRate,
                                                channelCount: loaded.channelCount, tag: tag)
        let output = folder.appendingPathComponent("converted.mp3")
        var reports: [Double] = []
        try MediaAudioConverter.convert(source: source, bitRate: 128, destination: output,
                                        isCancelled: { false }, progress: { reports.append($0) })
        suite.expect(!reports.isEmpty && zip(reports, reports.dropFirst()).allSatisfy { $0 <= $1 }
                     && (reports.last ?? 0) > 0.9,
                     "conversion progress only moves forward and reaches the end")

        let result = try decodedFile(output)
        suite.expect(result.rate == 44_100 && result.channels.count == 2,
                     "a 22.05 kHz source becomes a 44.1 kHz stereo MP3")
        let duration = Double(result.channels.first?.count ?? 0) / result.rate
        suite.expect(duration >= seconds && duration < seconds + 0.2,
                     "the MP3 lasts as long as its source (\(duration) s)")
        if result.channels.count == 2 {
            let window = Array(result.channels[0][22_050..<44_100])
            let other = Array(result.channels[1][22_050..<44_100])
            suite.expect(power(window, 440, rate: result.rate) > 100 * power(window, 1_000, rate: result.rate)
                         && power(other, 1_000, rate: result.rate) > 100 * power(other, 440, rate: result.rate),
                         "each resampled channel keeps its own tone")
        }

        let metadata = try await AVURLAsset(url: output).load(.commonMetadata)
        func value(_ key: AVMetadataKey) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: metadata, withKey: key, keySpace: .common).first
            else { return nil }
            return try? await item.load(.stringValue)
        }
        let artwork = AVMetadataItem.metadataItems(from: metadata, withKey: AVMetadataKey.commonKeyArtwork,
                                                   keySpace: .common).first
        let artworkData = try? await artwork?.load(.dataValue)
        let title = await value(.commonKeyTitle)
        let artist = await value(.commonKeyArtist)
        let album = await value(.commonKeyAlbumName)
        suite.expect(title == tag.title && artist == tag.artist && album == tag.album,
                     "title, artist and album survive conversion, in any script")
        suite.expect(artworkData != nil && artworkData == tag.artwork, "cover art survives conversion unchanged")

        do {
            try MediaAudioConverter.convert(source: loaded, bitRate: 192,
                                            destination: folder.appendingPathComponent("cancelled.mp3"),
                                            isCancelled: { true }, progress: { _ in })
            suite.expect(false, "a cancelled conversion stops")
        } catch {
            suite.expect(error as? MediaAudioConverter.ConvertError == .cancelled, "a cancelled conversion stops")
        }

        let movie = folder.appendingPathComponent("silent.mov")
        try await writeSilentMovie(to: movie)
        do {
            _ = try await MediaAudioConverter.loadSource(from: AVURLAsset(url: movie))
            suite.expect(false, "a video without sound is reported as having no audio")
        } catch {
            suite.expect(error as? MediaAudioConverter.ConvertError == .noAudioTrack,
                         "a video without sound is reported as having no audio")
        }

        let text = folder.appendingPathComponent("not-audio.m4a")
        try Data("not audio".utf8).write(to: text)
        do {
            _ = try await MediaAudioConverter.loadSource(from: AVURLAsset(url: text))
            suite.expect(false, "a file that only looks like audio is refused")
        } catch {
            suite.expect(error as? MediaAudioConverter.ConvertError == .unsupported,
                         "a file that only looks like audio is refused")
        }
    }

    private static func routing(_ suite: TestSuite, folder: URL) {
        let audio = folder.appendingPathComponent("song.m4a")
        let video = folder.appendingPathComponent("clip.mov")
        let image = folder.appendingPathComponent("photo.png")
        for url in [audio, video, image] { try? Data([0]).write(to: url) }
        suite.expect(NotchFileToolsSupport.accepts([audio], for: .audioConverter)
                     && NotchFileToolsSupport.accepts([video], for: .audioConverter)
                     && !NotchFileToolsSupport.accepts([image], for: .audioConverter)
                     && !NotchFileToolsSupport.accepts([audio, audio], for: .audioConverter),
                     "the MP3 converter takes one audio or video file")
        suite.expect(!NotchFileToolsSupport.accepts([audio], for: .videoCompressor),
                     "audio alone is not offered to the video tools")
        suite.expect(NotchFileToolsSupport.optimizationTool(for: [audio]) == .audioConverter
                     && NotchFileToolsSupport.optimizationTool(for: [video]) == .videoCompressor,
                     "a dropped song opens the MP3 converter while a dropped video still opens compression")
    }

    // MARK: - Helpers

    private static func tone(_ frequency: Double, _ amplitude: Float, rate: Int, seconds: Double) -> [Float] {
        (0..<Int(Double(rate) * seconds)).map {
            amplitude * Float(sin(2 * .pi * frequency * Double($0) / Double(rate)))
        }
    }

    private static func encode(_ channels: [[Float]], rate: Int, bitRate: Int, chunk: Int = 4_096) throws -> Data {
        let encoder = try MediaMP3Encoder(sampleRate: rate, channelCount: channels.count, bitRate: bitRate)
        let frames = channels[0].count
        var data = Data()
        var start = 0
        while start < frames {
            let end = min(frames, start + chunk)
            var interleaved: [Float] = []
            interleaved.reserveCapacity((end - start) * channels.count)
            for frame in start..<end { for channel in channels { interleaved.append(channel[frame]) } }
            data.append(interleaved.withUnsafeBufferPointer { encoder.encode(interleaved: $0) })
            start = end
        }
        data.append(encoder.finish())
        return data
    }

    private struct Frame {
        let bitRate: Int
        let sampleRate: Int
        let channels: Int
    }

    /// Walks the stream by the standard's own frame-length formula, so a
    /// frame that is a byte too long or too short ends the walk off its end.
    private static func frames(in data: Data) -> [Frame]? {
        let bytes = [UInt8](data)
        var frames: [Frame] = []
        var offset = 0
        while offset < bytes.count {
            guard offset + 4 <= bytes.count, bytes[offset] == 0xFF, bytes[offset + 1] & 0xE0 == 0xE0,
                  bytes[offset + 1] >> 3 & 3 == 3, bytes[offset + 1] >> 1 & 3 == 1 else { return nil }
            let bitRateIndex = Int(bytes[offset + 2] >> 4)
            let rateIndex = Int(bytes[offset + 2] >> 2 & 3)
            guard (1...14).contains(bitRateIndex), rateIndex < 3 else { return nil }
            let bitRate = MediaMP3Encoder.bitRates[bitRateIndex - 1]
            let rate = MediaMP3Encoder.sampleRates[rateIndex]
            let padding = Int(bytes[offset + 2] >> 1 & 1)
            frames.append(Frame(bitRate: bitRate, sampleRate: rate, channels: bytes[offset + 3] >> 6 == 3 ? 1 : 2))
            offset += 144_000 * bitRate / rate + padding
        }
        return offset == bytes.count ? frames : nil
    }

    private static func decoded(_ data: Data, folder: URL, name: String) throws -> (rate: Double, channels: [[Float]]) {
        let url = folder.appendingPathComponent("\(name).mp3")
        try data.write(to: url)
        return try decodedFile(url)
    }

    private static func decodedFile(_ url: URL) throws -> (rate: Double, channels: [[Float]]) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            return (format.sampleRate, [])
        }
        try file.read(into: buffer)
        let channels = (0..<Int(format.channelCount)).map { channel in
            Array(UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: Int(buffer.frameLength)))
        }
        return (format.sampleRate, channels)
    }

    /// The encoder and decoder delay the signal by a fixed amount; the lag
    /// with the strongest correlation is where the source lines up.
    private static func delay(of reference: [Float], in decoded: [Float]) -> Int? {
        let window = 4_096
        let start = 4_096
        guard reference.count > start + window, decoded.count > start + window + 3_000 else { return nil }
        var best = -Float.infinity
        var lag = 0
        reference.withUnsafeBufferPointer { source in
            decoded.withUnsafeBufferPointer { output in
                for candidate in 0..<3_000 {
                    var score: Float = 0
                    vDSP_dotpr(source.baseAddress! + start, 1, output.baseAddress! + start + candidate, 1,
                               &score, vDSP_Length(window))
                    if score > best { best = score; lag = candidate }
                }
            }
        }
        return lag
    }

    private static func match(_ reference: [Float], _ decoded: [Float], lag: Int, edge: Int = 2_048)
        -> (snr: Double, gain: Double) {
        let count = min(reference.count, decoded.count - lag) - edge
        guard count > edge else { return (-.infinity, 0) }
        var signal = 0.0, noise = 0.0, cross = 0.0
        for index in edge..<count {
            let original = Double(reference[index])
            let restored = Double(decoded[index + lag])
            signal += original * original
            noise += (restored - original) * (restored - original)
            cross += original * restored
        }
        return (10 * log10(signal / max(noise, 1e-30)), signal > 0 ? cross / signal : 0)
    }

    private static func power(_ samples: [Float], _ frequency: Double, rate: Double) -> Double {
        let coefficient = 2 * cos(2 * .pi * frequency / rate)
        var previous = 0.0, older = 0.0
        for sample in samples {
            let current = Double(sample) + coefficient * previous - older
            older = previous
            previous = current
        }
        return previous * previous + older * older - coefficient * previous * older
    }

    private static func writeWAV(_ channels: [[Float]], rate: Int, to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: AVAudioChannelCount(channels.count))!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(channels[0].count))!
        buffer.frameLength = AVAudioFrameCount(channels[0].count)
        for (index, channel) in channels.enumerated() {
            channel.withUnsafeBufferPointer { buffer.floatChannelData![index].update(from: $0.baseAddress!, count: $0.count) }
        }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels.count, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        try file.write(from: buffer)
    }

    private static func jpeg() -> Data? {
        guard let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let data = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func writeSilentMovie(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var pixelBuffer: CVPixelBuffer?
            guard let pool = adapter.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
                  let pixelBuffer else { throw CocoaError(.fileWriteUnknown) }
            adapter.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
