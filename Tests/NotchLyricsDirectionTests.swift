// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Verses in a right-to-left script read from the right edge of the island,
/// though every interface language the app offers runs left to right. The
/// production view (generated from NotchLyricsView.swift) runs unchanged
/// against a stand-in service; only where its ink lands is measured.
enum NotchLyricsDirectionTests {
    final class NotchLyricsService: ObservableObject {
        static let shared = NotchLyricsService()
        enum State: Equatable { case idle, consent, loading, unavailable, failed, ready }
        @Published var state: State = .ready
        @Published var lyrics: NotchLyrics?
        var offset: Double = 0
        func update(playback: NotchPlayback?, visible: Bool) {}
        func retry() {}
        func adjustOffset(by amount: Double) {}
        func resetOffset() {}
        func importLyrics() {}
    }

    // Only the empty and loading pages use these; they never render here.
    struct NotchEmptyView<Actions: View>: View {
        let symbol: String
        let message: String
        @ViewBuilder var actions: () -> Actions
        var body: some View { actions() }
    }

    struct NotchPillButton: View {
        let title: String
        var prominent = false
        let action: () -> Void
        var body: some View { EmptyView() }
    }

    struct NotchIconButton: View {
        let symbol: String
        let title: String
        let action: () -> Void
        var body: some View { EmptyView() }
    }

    private static let size = CGSize(width: 320, height: 200)

    static func run(_ suite: TestSuite) {
        let arabic = ["يا ليل يا عين", "سهرت الليل", "قلبي معاك"]
        let width = Int(size.width) * 2
        for synced in [true, false] {
            let ink = verseInk(arabic, synced: synced)
            suite.expect(ink.map { $0.maxX > width - 24 && $0.minX > width / 4 } == true,
                         "Arabic \(synced ? "timed" : "plain") lyrics hug the island's right edge (ink \(String(describing: ink)) of \(width))")
        }

        let others = [("Hebrew", ["שיר של אהבה", "כל הלילה", "אני כאן"]),
                      ("Persian", ["دلم برات تنگ شده", "بیا پیشم", "تا صبح"]),
                      ("Urdu", ["دل دیاں گلاں", "میں تیرا ہوں", "یہ رات"]),
                      // Scripts a language guess does not cover still read from the right.
                      ("Kurdish", ["خۆشم دەوێیت", "شەو درەنگە", "وەرە"]),
                      ("Yiddish", ["איך האָב דיך ליב", "אַ גוטע נאַכט", "מיין הארץ"]),
                      ("Dhivehi", ["ލޯބި ލަވަ", "ރޭގަނޑު", "ހިތް"])]
        for (name, verses) in others {
            let ink = verseInk(verses, synced: true)
            suite.expect(ink.map { $0.maxX > width - 24 && $0.minX > width / 4 } == true,
                         "\(name) lyrics hug the island's right edge (ink \(String(describing: ink)) of \(width))")
        }

        // Online lyrics carry the timed verses and a plain text separately;
        // the timed page follows the verses it shows, not a transliteration.
        let transliterated = verseInk(arabic, synced: true,
                                      plain: "Ya leil ya ein\nSahart el leil\nAlbi maak")
        suite.expect(transliterated.map { $0.maxX > width - 24 && $0.minX > width / 4 } == true,
                     "Arabic timed verses keep the right edge beside a Latin plain text (ink \(String(describing: transliterated)) of \(width))")

        // One edge per song: a verse opening with a Latin word stays with its song.
        let mixed = ["يا ليل يا عين", "Baby, baby, you're my حبيبي", "سهرت الليل", "قلبي معاك"]
        let mixedInk = verseInk(mixed, synced: true)
        suite.expect(mixedInk.map { $0.maxX > width - 24 && $0.minX > width / 4 } == true,
                     "an Arabic song keeps its right edge on a verse opening in Latin (ink \(String(describing: mixedInk)) of \(width))")

        // Left-to-right songs keep the edge they always had.
        let english = ["Hello darkness", "my old friend", "I've come to talk"]
        for synced in [true, false] {
            let ink = verseInk(english, synced: synced)
            suite.expect(ink.map { $0.minX < 24 && $0.maxX < width * 3 / 4 } == true,
                         "English \(synced ? "timed" : "plain") lyrics keep the left edge (ink \(String(describing: ink)) of \(width))")
        }
    }

    /// Horizontal ink of the verses at 2x, above the timing row a timed page
    /// adds at its bottom. Plain lyrics carry no timed lines, so the page
    /// shows the verses alone. The app's own interface stays left to right.
    private static func verseInk(_ verses: [String], synced: Bool, plain: String = "") -> (minX: Int, maxX: Int)? {
        let service = NotchLyricsService.shared
        service.lyrics = synced
            ? NotchLyrics(lines: verses.enumerated().map { NotchLyricLine(time: Double($0.offset) * 5, text: $0.element) },
                          plain: plain, instrumental: false)
            : NotchLyrics(lines: [], plain: verses.joined(separator: "\n"), instrumental: false)
        let track = RadialNowPlayingSnapshot(title: "Verses", artist: nil, album: nil,
                                            artworkData: nil, appBundleIdentifier: nil, appPID: nil)
        let playback = NotchPlayback(track: track, isPlaying: false, elapsed: 1, duration: 60,
                                     rate: 0, sampledAt: .now, canSeek: false)
        let host = NSHostingView(rootView: NotchLyricsView(playback: playback)
            .frame(width: size.width, height: size.height)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
            .environment(\.layoutDirection, .leftToRight))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        // The timed page keeps its last 40 pt for the timing row; the plain
        // page ends with its import button.
        let rows = synced ? 0..<(rep.pixelsHigh - 80) : 0..<(rep.pixelsHigh / 2)
        var minX = Int.max, maxX = -1
        for y in rows {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.brightnessComponent ?? 0) > 0.2 {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        return maxX < 0 ? nil : (minX, maxX)
    }
}
