// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import CoreMedia
import Foundation

/// Saves the soundtrack of an audio or video file as MP3.
///
/// AVFoundation decodes whatever it can open and mixes every enabled audio
/// track into one, so a recording with separate system audio and microphone
/// tracks keeps both voices. It also resamples to a rate MP3 carries, which
/// leaves the encoder only ever seeing the formats it supports.
enum MediaAudioConverter {
    struct Tag: Equatable {
        var title: String?
        var artist: String?
        var album: String?
        var artwork: Data?
    }

    struct Source {
        let asset: AVAsset
        let audioTracks: [AVAssetTrack]
        let duration: Double
        let sampleRate: Double
        let channelCount: Int
        let tag: Tag
    }

    enum ConvertError: Error, Equatable {
        case noAudioTrack
        case unsupported
        case cancelled
        case failed(String)
    }

    static func loadSource(from asset: AVAsset) async throws -> Source {
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio) else {
            throw ConvertError.unsupported
        }
        guard !tracks.isEmpty else { throw ConvertError.noAudioTrack }
        // A disabled track is usually another language of the same movie;
        // mixing it in would talk over the one the person hears.
        var enabled: [AVAssetTrack] = []
        for track in tracks where (try? await track.load(.isEnabled)) ?? true {
            enabled.append(track)
        }
        let chosen = enabled.isEmpty ? tracks : enabled
        var sampleRate = 0.0
        var channelCount = 0
        for track in chosen {
            for description in (try? await track.load(.formatDescriptions)) ?? [] {
                guard let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
                    continue
                }
                sampleRate = max(sampleRate, format.mSampleRate)
                channelCount = max(channelCount, Int(format.mChannelsPerFrame))
            }
        }
        let duration = (try? await asset.load(.duration))?.seconds ?? 0
        return Source(asset: asset,
                      audioTracks: chosen,
                      duration: duration.isFinite ? max(0, duration) : 0,
                      sampleRate: sampleRate,
                      channelCount: channelCount,
                      tag: await loadTag(from: asset))
    }

    static func convert(source: Source,
                        bitRate: Int,
                        destination: URL,
                        isCancelled: () -> Bool,
                        progress: (Double) -> Void) throws {
        let sampleRate = MediaSupport.mp3SampleRate(forSourceRate: source.sampleRate)
        let channelCount = MediaSupport.mp3ChannelCount(forSourceChannels: source.channelCount)
        guard let encoder = try? MediaMP3Encoder(sampleRate: sampleRate,
                                                 channelCount: channelCount,
                                                 bitRate: MediaSupport.sanitizedMP3BitRate(bitRate)),
              let reader = try? AVAssetReader(asset: source.asset)
        else { throw ConvertError.unsupported }

        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channelCount == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
        let output = AVAssetReaderAudioMixOutput(audioTracks: source.audioTracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ConvertError.unsupported }
        reader.add(output)

        try? FileManager.default.removeItem(at: destination)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: destination)
        else { throw ConvertError.failed("The MP3 file could not be created.") }
        defer { try? handle.close() }
        guard reader.startReading() else {
            throw ConvertError.failed(reader.error?.localizedDescription ?? "Audio could not be read.")
        }

        if let tag = id3Tag(source.tag) { try handle.write(contentsOf: tag) }
        while let buffer = output.copyNextSampleBuffer() {
            if isCancelled() {
                reader.cancelReading()
                throw ConvertError.cancelled
            }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            var copied = false
            let samples = [Float](unsafeUninitializedCapacity: count) { storage, initialized in
                copied = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                                    destination: storage.baseAddress!) == kCMBlockBufferNoErr
                initialized = copied ? count : 0
            }
            guard copied else { throw ConvertError.failed("Audio could not be read.") }
            try handle.write(contentsOf: samples.withUnsafeBufferPointer { encoder.encode(interleaved: $0) })
            let end = CMSampleBufferGetPresentationTimeStamp(buffer) + CMSampleBufferGetDuration(buffer)
            if source.duration > 0, end.seconds.isFinite {
                progress(min(0.99, max(0, end.seconds / source.duration)))
            }
        }
        if isCancelled() { throw ConvertError.cancelled }
        guard reader.status == .completed else {
            throw ConvertError.failed(reader.error?.localizedDescription ?? "Audio could not be read.")
        }
        try handle.write(contentsOf: encoder.finish())
    }

    /// Title, artist, album and cover carried over as an ID3v2.3 tag, the
    /// version every player reads, so a converted song keeps its name.
    static func id3Tag(_ tag: Tag) -> Data? {
        var frames = Data()
        func append(_ id: String, _ body: Data) {
            frames.append(contentsOf: Array(id.utf8))
            frames.append(contentsOf: bigEndianBytes(UInt32(body.count)))
            frames.append(contentsOf: [0, 0])
            frames.append(body)
        }
        func appendText(_ id: String, _ value: String?) {
            guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                  let encoded = text.data(using: .utf16LittleEndian) else { return }
            // Encoding 1 is UTF-16 with a byte order mark, so any script survives.
            append(id, Data([1, 0xFF, 0xFE]) + encoded)
        }
        appendText("TIT2", tag.title)
        appendText("TPE1", tag.artist)
        appendText("TALB", tag.album)
        if let artwork = tag.artwork, let mime = imageMIMEType(artwork) {
            // Latin-1 description, MIME type, front cover, empty description.
            append("APIC", Data([0]) + Data(mime.utf8) + Data([0, 3, 0]) + artwork)
        }
        guard !frames.isEmpty, frames.count < 1 << 28 else { return nil }
        // The tag size is synchsafe: seven bits per byte, so it can never
        // read as an MP3 frame sync.
        let size = frames.count
        let header = Data("ID3".utf8) + Data([3, 0, 0,
                                              UInt8(size >> 21 & 0x7F), UInt8(size >> 14 & 0x7F),
                                              UInt8(size >> 7 & 0x7F), UInt8(size & 0x7F)])
        return header + frames
    }

    private static func loadTag(from asset: AVAsset) async -> Tag {
        guard let items = try? await asset.load(.commonMetadata) else { return Tag() }
        func first(_ key: AVMetadataKey) -> AVMetadataItem? {
            AVMetadataItem.metadataItems(from: items, withKey: key, keySpace: .common).first
        }
        var tag = Tag()
        if let item = first(.commonKeyTitle) { tag.title = try? await item.load(.stringValue) }
        if let item = first(.commonKeyArtist) { tag.artist = try? await item.load(.stringValue) }
        if let item = first(.commonKeyAlbumName) { tag.album = try? await item.load(.stringValue) }
        if let item = first(.commonKeyArtwork) { tag.artwork = try? await item.load(.dataValue) }
        return tag
    }

    private static func imageMIMEType(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        return nil
    }

    private static func bigEndianBytes(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }
}
