// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import zlib

/// SongRec's fingerprint as ported, Shazam's reply, and how answers are scored.
enum MusicRecognitionEngineTests {
    static func run(_ suite: TestSuite) {
        signature(suite)
        scoring(suite)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        guard data.count >= offset + 4 else { return 0 }
        return data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    }

    private static func signature(_ suite: TestSuite) {
        let window = ShazamSignatureGenerator.window
        suite.expect(abs(window[0] - 0.0000023508) < 1e-9 && abs(window[2047] - 0.0000023508) < 1e-9
                        && abs(window[1023] - 1) < 1e-5,
                     "the Hanning window matches SongRec's table at both ends and the middle")

        // Ten notes of 0.3 s, each a different pitch from 600 to 1410 Hz, all within the 520–1450 Hz band.
        // A peak must stand out from the same pitch a second or two either side, so no note repeats.
        let notes = (0..<10).map { 600.0 + Double($0) * 90 }
        let tone = (0..<48_000).map { index -> Float in
            let note = notes[min(9, index / 4_800)]
            let inNote = index % 4_800
            return inNote < 4_000 ? Float(0.5 * sin(2 * Double.pi * note * Double(index) / 16_000)) : 0
        }
        let signature = ShazamSignatureGenerator.signature(of: tone)
        suite.expect(signature.bands[1].count > 0 && signature.bands[1].count * 2 > signature.peakCount,
                     "notes in the 520–1450 Hz band put most of their peaks in that band (\(signature.bands.map(\.count)))")
        let hertz = signature.bands[1].map { Double($0.bin) * 16_000 / 2 / 1024 / 64 }
        suite.expect(hertz.filter { peak in notes.contains { abs($0 - peak) < 20 } }.count * 2 > hertz.count,
                     "most of those peaks sit at the notes' own pitches (\(hertz.prefix(4)))")
        suite.expect(ShazamSignatureGenerator.signature(of: [Float](repeating: 0, count: 48_000)).peakCount == 0,
                     "silence gives no peaks")

        let encoded = signature.encoded()
        let crc = encoded.dropFirst(8).withUnsafeBytes { raw in
            UInt32(zlib.crc32(0, raw.bindMemory(to: Bytef.self).baseAddress, uInt(raw.count)))
        }
        suite.expect(u32(encoded, 0) == 0xcafe_2580 && u32(encoded, 12) == 0x9411_9c00 && u32(encoded, 28) == 3 << 27
                        && u32(encoded, 8) == UInt32(encoded.count - 48) && u32(encoded, 52) == UInt32(encoded.count - 48)
                        && u32(encoded, 4) == crc && encoded.count % 4 == 0,
                     "the signature carries Shazam's header, its sizes, a valid CRC, and padding to four bytes")
        let firstBand = signature.bands.firstIndex { !$0.isEmpty } ?? 0
        suite.expect(u32(encoded, 56) == 0x6003_0040 + UInt32(firstBand)
                        && signature.uri.hasPrefix("data:audio/vnd.shazam.sig;base64,"),
                     "each band is tagged by its number, and the signature travels as a data URI")
        suite.expect(signature.milliseconds == 3000, "three seconds of sound are three thousand milliseconds")

        let reply = Data("""
        {"matches":[{"offset":42.1,"timeskew":0.0003,"frequencyskew":-0.0002}],
         "track":{"key":"512","title":"Blinding Lights","subtitle":"The Weeknd",
                  "images":{"coverart":"https://example.com/a.jpg","coverarthq":"https://example.com/hq.jpg"}}}
        """.utf8)
        let match = ShazamMatch.parse(reply)
        suite.expect(match?.title == "Blinding Lights" && match?.artist == "The Weeknd" && match?.key == "512"
                        && match?.artworkURL?.absoluteString == "https://example.com/hq.jpg"
                        && abs((match?.skew ?? 1) - 0.0005) < 1e-9,
                     "Shazam's reply gives the song, its sharpest cover and how cleanly it lined up")
        suite.expect(ShazamMatch.parse(Data(#"{"matches":[],"retryms":3000}"#.utf8)) == nil,
                     "a reply with no track is no match")
        let body = ShazamMatch.requestBody(signature, at: Date(timeIntervalSince1970: 1_731_400_000))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        suite.expect((body?["timestamp"] as? NSNumber)?.uint64Value == 1_731_400_000_000
                        && ((body?["signature"] as? [String: Any])?["samplems"] as? NSNumber)?.intValue == 3000,
                     "the request carries the time in milliseconds and the signature's length")
    }

    private static func scoring(_ suite: TestSuite) {
        let original = RecognisedSong(title: "Blinding Lights", artist: "The Weeknd", artworkURL: nil)
        let remix = RecognisedSong(title: "Blinding Lights (Remix)", artist: "The Weeknd & ROSALÍA", artworkURL: nil)
        var scoring = MusicRecognitionScoring()
        scoring.add(original, engine: "songrec-mac", skew: 0.0003)
        suite.expect(scoring.best?.percent == 74, "one clean answer scores 74%")
        scoring.add(remix, engine: "songrec-mac", skew: 0.0002)
        scoring.add(original, engine: "songrec-mac", skew: 0.0001)
        scoring.add(original, engine: "shazamkit-room", skew: nil)
        suite.expect(scoring.best?.song == original && scoring.best?.percent == 99
                        && scoring.others(than: original.id).map(\.song) == [remix],
                     "agreeing windows and a second engine raise the song's score; the remix stays a nearby match")
        suite.expect(MusicRecognitionScoring.key(title: "Song (feat. A)", artist: "B") == MusicRecognitionScoring.key(title: "Song", artist: "B")
                        && MusicRecognitionScoring.key(title: "Song - Remastered 2011", artist: "B")
                            == MusicRecognitionScoring.key(title: "Song", artist: "B"),
                     "a featured artist or a remaster is the same song heard")
        suite.expect(!MusicRecognitionScoring.isAudible([Float](repeating: 0.0001, count: 1000))
                        && MusicRecognitionScoring.isAudible([Float](repeating: 0.2, count: 1000)),
                     "near-silence is not worth fingerprinting")
        let wav = MusicRecognitionScoring.wav([0, 0.5, -0.5])
        suite.expect(wav.count == 44 + 6 && String(data: wav.prefix(4), encoding: .ascii) == "RIFF"
                        && u32(wav, 24) == 16_000 && u32(wav, 40) == 6,
                     "a clip for AudD is a 16 kHz, 16-bit mono WAV")
        let search = Data("""
        {"results":[{"trackName":"Blinding Lights","artistName":"The Weeknd","artworkUrl100":"https://x/100x100bb.jpg"},
                    {"trackName":"Blinding Lights (Acoustic)","artistName":"Someone","artworkUrl100":"https://x/100x100bb.jpg"},
                    {"trackName":"Blinding Lights (Acoustic)","artistName":"Someone"}]}
        """.utf8)
        let versions = MusicRecognitionScoring.versions(from: search, excluding: original)
        suite.expect(versions.count == 1 && versions.first?.artist == "Someone"
                        && versions.first?.artworkURL?.absoluteString == "https://x/300x300bb.jpg",
                     "other versions leave out the song itself and repeats, with a sharper cover")
        suite.expect(MusicRecognitionScoring.searchTerms(for: remix) == ["Blinding Lights The Weeknd", "Blinding Lights"]
                        && MusicRecognitionScoring.searchTerms(for: RecognisedSong(title: "Song - Remastered", artist: "A feat. B",
                                                                                   artworkURL: nil)) == ["Song A", "Song"],
                     "other versions are searched by the bare title with the main artist, then the title alone")
    }
}
