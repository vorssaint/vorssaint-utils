// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// The fingerprint is a port of SongRec's (https://github.com/marin-m/SongRec,
// GPL-3.0, by marin-m), itself based on Shazam's published research: peaks
// found in a spectrogram of 16 kHz mono sound, packed in Shazam's signature
// format. Only this fingerprint is ever sent, never the sound itself.

import Accelerate
import Foundation
import zlib

/// One peak of the spectrogram: when, how loud, and where in frequency.
struct ShazamPeak: Equatable {
    let pass: UInt32
    let magnitude: UInt16
    let bin: UInt16
}

/// A fingerprint of a few seconds of 16 kHz mono sound.
struct ShazamSignature: Equatable {
    static let sampleRate = 16_000
    /// Peaks in four frequency bands: 250–520 Hz, 520–1450 Hz, 1450–3500 Hz, 3500–5500 Hz.
    var bands: [[ShazamPeak]] = [[], [], [], []]
    var sampleCount: Int = 0

    var peakCount: Int { bands.reduce(0) { $0 + $1.count } }
    var milliseconds: Int { sampleCount * 1000 / Self.sampleRate }

    /// Shazam's binary signature: a 48-byte header, then each band's peaks.
    func encoded() -> Data {
        var data = Data()
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        u32(0xcafe_2580)          // magic
        u32(0)                     // CRC-32, written below
        u32(0)                     // size after the header, written below
        u32(0x9411_9c00)          // magic
        u32(0); u32(0); u32(0)
        u32(3 << 27)               // 16 kHz
        u32(0); u32(0)
        u32(UInt32(sampleCount) + UInt32(Double(Self.sampleRate) * 0.24))
        u32((15 << 19) + 0x40000)
        u32(0x4000_0000)
        u32(0)                     // size after the header, again, written below
        for (index, peaks) in bands.enumerated() where !peaks.isEmpty {
            var body = Data()
            var pass: UInt32 = 0
            for peak in peaks {
                if peak.pass - pass >= 255 {
                    body.append(0xff)
                    withUnsafeBytes(of: peak.pass.littleEndian) { body.append(contentsOf: $0) }
                    pass = peak.pass
                }
                body.append(UInt8(peak.pass - pass))
                withUnsafeBytes(of: peak.magnitude.littleEndian) { body.append(contentsOf: $0) }
                withUnsafeBytes(of: peak.bin.littleEndian) { body.append(contentsOf: $0) }
                pass = peak.pass
            }
            u32(0x6003_0040 + UInt32(index))
            u32(UInt32(body.count))
            data.append(body)
            data.append(contentsOf: [UInt8](repeating: 0, count: (4 - body.count % 4) % 4))
        }
        let after = UInt32(data.count - 48)
        data.replaceSubrange(8..<12, with: withUnsafeBytes(of: after.littleEndian) { Data($0) })
        data.replaceSubrange(52..<56, with: withUnsafeBytes(of: after.littleEndian) { Data($0) })
        let crc = data.dropFirst(8).withUnsafeBytes { raw -> UInt32 in
            UInt32(zlib.crc32(0, raw.bindMemory(to: Bytef.self).baseAddress, uInt(raw.count)))
        }
        data.replaceSubrange(4..<8, with: withUnsafeBytes(of: crc.littleEndian) { Data($0) })
        return data
    }

    var uri: String { "data:audio/vnd.shazam.sig;base64," + encoded().base64EncodedString() }
}

/// Turns 16 kHz mono samples into a signature, as SongRec does: a 2048-point
/// FFT every 128 samples, peaks spread across time and frequency, then each
/// peak that stands out from its neighbours kept.
final class ShazamSignatureGenerator {
    /// Worked out in double precision: in single, 1 − cos loses the tiny values at both ends.
    static let window: [Float] = (0..<2048).map { Float(0.5 * (1 - cos(2 * Double.pi * Double($0 + 1) / 2049))) }

    private var ring = [Int16](repeating: 0, count: 2048)
    private var ringIndex = 0
    private var ffts = [[Float]](repeating: [Float](repeating: 0, count: 1025), count: 256)
    private var fftIndex: UInt8 = 0
    private var spread = [[Float]](repeating: [Float](repeating: 0, count: 1025), count: 256)
    private var spreadIndex: UInt8 = 0
    private var spreadsDone: UInt32 = 0
    private var signature = ShazamSignature()
    private let setup = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2))!

    deinit { vDSP_destroy_fftsetup(setup) }

    static func signature(of samples: [Float]) -> ShazamSignature {
        let generator = ShazamSignatureGenerator()
        generator.signature.sampleCount = samples.count
        let whole = samples.count / 128 * 128
        var chunk = [Int16](repeating: 0, count: 128)
        var start = 0
        while start < whole {
            for i in 0..<128 {
                chunk[i] = Int16(max(-32768, min(32767, (samples[start + i] * 32768).rounded())))
            }
            generator.fft(chunk)
            generator.spreadPeaks()
            generator.spreadsDone += 1
            if generator.spreadsDone >= 46 { generator.recognisePeaks() }
            start += 128
        }
        return generator.signature
    }

    private func fft(_ chunk: [Int16]) {
        for i in 0..<128 { ring[ringIndex + i] = chunk[i] }
        ringIndex = (ringIndex + 128) & 2047
        var input = [Float](repeating: 0, count: 2048)
        for i in 0..<2048 { input[i] = Float(ring[(i + ringIndex) & 2047]) * Self.window[i] }
        // A real FFT of 2048 points, through vDSP's split-complex packing.
        var real = [Float](repeating: 0, count: 1024)
        var imaginary = [Float](repeating: 0, count: 1024)
        var output = [Float](repeating: 0, count: 1025)
        real.withUnsafeMutableBufferPointer { re in
            imaginary.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                input.withUnsafeBufferPointer { samples in
                    samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: 1024) {
                        vDSP_ctoz($0, 2, &split, 1, 1024)
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, 11, FFTDirection(FFT_FORWARD))
                // vDSP scales a real FFT by two; DC and Nyquist share the first slot.
                let scale = Float(1 << 17)
                let dc = split.realp[0] / 2, nyquist = split.imagp[0] / 2
                output[0] = max(dc * dc / scale, 1e-10)
                output[1024] = max(nyquist * nyquist / scale, 1e-10)
                for k in 1..<1024 {
                    let r = split.realp[k] / 2, i = split.imagp[k] / 2
                    output[k] = max((r * r + i * i) / scale, 1e-10)
                }
            }
        }
        ffts[Int(fftIndex)] = output
        fftIndex &+= 1
    }

    private func spreadPeaks() {
        var results = ffts[Int(fftIndex &- 1)]
        for position in 0...1022 {
            results[position] = max(results[position], results[position + 1], results[position + 2])
        }
        spread[Int(spreadIndex)] = results
        for position in 0...1024 {
            for former in [UInt8(1), 3, 6] {
                let index = Int(spreadIndex &- former)
                spread[index][position] = max(spread[index][position], results[position])
            }
        }
        spreadIndex &+= 1
    }

    private func recognisePeaks() {
        let current = ffts[Int(fftIndex &- 46)]
        let before = spread[Int(spreadIndex &- 49)]
        for bin in 10...1014 {
            guard current[bin] >= 1.0 / 64.0, current[bin] >= before[bin - 1] else { continue }
            var neighbours: Float = 0
            for offset in [-10, -7, -4, -3, 1, 2, 5, 8] { neighbours = max(neighbours, before[bin + offset]) }
            guard current[bin] > neighbours else { continue }
            var around = neighbours
            for offset in [-53, -45, 165, 172, 179, 186, 193, 200, 214, 221, 228, 235, 242, 249] {
                around = max(around, spread[(Int(spreadIndex) + offset) & 255][bin - 1])
            }
            guard current[bin] > around else { continue }
            func magnitude(_ value: Float) -> Float { max(log(value), 1.0 / 64.0) * 1477.3 + 6144 }
            let peak = magnitude(current[bin]), lower = magnitude(current[bin - 1]), upper = magnitude(current[bin + 1])
            let variation1 = peak * 2 - lower - upper
            guard variation1 > 0 else { continue }
            let variation2 = (upper - lower) * 32 / variation1
            let corrected = UInt16(truncatingIfNeeded: bin * 64 + Int(variation2))
            let hertz = Float(corrected) * (16000 / 2 / 1024 / 64)
            let band: Int
            switch Int(hertz) {
            case 250...519: band = 0
            case 520...1449: band = 1
            case 1450...3499: band = 2
            case 3500...5500: band = 3
            default: continue
            }
            signature.bands[band].append(ShazamPeak(pass: spreadsDone - 46, magnitude: UInt16(peak), bin: corrected))
        }
    }
}

/// What Shazam answered: the song, and how cleanly the sound lined up with it.
struct ShazamMatch: Equatable {
    let key: String
    let title: String
    let artist: String
    let artworkURL: URL?
    /// How far the heard sound's speed and pitch were from the recording; near zero is a clean match.
    let skew: Double

    /// Shazam's JSON reply. Nil when it found nothing.
    static func parse(_ data: Data) -> ShazamMatch? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let track = object["track"] as? [String: Any],
              let title = track["title"] as? String, !title.isEmpty else { return nil }
        let images = track["images"] as? [String: Any]
        let cover = (images?["coverarthq"] as? String) ?? (images?["coverart"] as? String)
        let matches = object["matches"] as? [[String: Any]] ?? []
        let skew = matches.compactMap { match -> Double? in
            let time = (match["timeskew"] as? NSNumber)?.doubleValue ?? 0
            let frequency = (match["frequencyskew"] as? NSNumber)?.doubleValue ?? 0
            return abs(time) + abs(frequency)
        }.min() ?? 0.01
        return ShazamMatch(key: (track["key"] as? String) ?? title.lowercased(), title: title,
                           artist: (track["subtitle"] as? String) ?? "", artworkURL: cover.flatMap(URL.init(string:)),
                           skew: skew)
    }

    /// The request body for a signature, as Shazam's apps send it.
    static func requestBody(_ signature: ShazamSignature, at date: Date = Date()) -> Data? {
        let milliseconds = UInt64(date.timeIntervalSince1970 * 1000)
        let body: [String: Any] = [
            "geolocation": ["altitude": 300, "latitude": 45, "longitude": 2],
            "signature": ["samplems": signature.milliseconds, "timestamp": milliseconds, "uri": signature.uri],
            "timestamp": milliseconds,
            "timezone": TimeZone.current.identifier,
        ]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    static func requestURL() -> URL? {
        let first = UUID().uuidString.uppercased(), second = UUID().uuidString.lowercased()
        return URL(string: "https://amp.shazam.com/discovery/v5/en/US/android/-/tag/\(first)/\(second)"
                   + "?sync=true&webv3=true&sampling=true&connected=&shazamapiversion=v3&sharehub=true&video=v3")
    }
}
