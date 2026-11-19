// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Real TextKit rendering with paused playback, so captures are deterministic
/// and never need a web engine, a display capture grant or a visible window.
enum NotchKaraokeRenderingTests {
    private final class Window: NSWindow {
        override var isVisible: Bool { true }
        override var occlusionState: NSWindow.OcclusionState { [.visible] }
    }
    static func run(_ suite: TestSuite) {
        let line = NotchLyricLine(time: 1, text: "Starlight across the sky", end: 8, syllables: [
            .init(range: NSRange(location: 0, length: 4), begin: 1, end: 2),
            .init(range: NSRange(location: 4, length: 5), begin: 2, end: 3),
            .init(range: NSRange(location: 10, length: 6), begin: 3, end: 5),
            .init(range: NSRange(location: 17, length: 3), begin: 5, end: 6),
            .init(range: NSRange(location: 21, length: 3), begin: 6, end: 8)
        ])
        let track = RadialNowPlayingSnapshot(title: "Native karaoke test", artist: nil, album: nil,
                                             artworkData: nil, appBundleIdentifier: nil, appPID: nil)
        func capture(_ elapsed: Double, width: Double = 230, sample: NotchLyricLine? = nil, active: Bool = true) -> (brightness: Double, height: Double, center: Double)? {
            let playback = NotchPlayback(track: track, isPlaying: false, elapsed: elapsed, duration: 10,
                                         rate: 1, sampledAt: .now, canSeek: false)
            let host = NSHostingView(rootView: NotchKaraokeLine(line: sample ?? line, playback: playback, offset: 0, active: active)
                .frame(width: width).background(.black))
            let window = Window(contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
                                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil }
            let deadline = Date().addingTimeInterval(0.12)
            while Date() < deadline { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            let height = host.fittingSize.height
            host.frame = NSRect(x: 0, y: 0, width: width, height: max(30, height))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let directory = ProcessInfo.processInfo.environment["VORSSAINT_KARAOKE_SNAPSHOT_DIR"],
               let png = bitmap.representation(using: .png, properties: [:]) {
                let folder = URL(fileURLWithPath: directory, isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? png.write(to: folder.appendingPathComponent("karaoke-\(elapsed)-\(Int(width)).png"), options: .atomic)
            }
            var brightness = 0.0
            var weightedX = 0.0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                        let value = Double(color.redComponent + color.greenComponent + color.blueComponent)
                        brightness += value
                        weightedX += Double(x) * value
                    }
                }
            }
            return (brightness, height, weightedX / max(1, brightness))
        }
        guard let before = capture(0), let dimBefore = capture(0, active: false), let part = capture(2.5), let after = capture(8), let settled = capture(9, active: false), let wrapped = capture(2.5, width: 85) else {
            suite.expect(false, "native karaoke renders through SwiftUI and TextKit"); return
        }
        suite.expect(before.brightness > 0 && part.brightness > before.brightness && after.brightness > part.brightness,
                     "native glyph masks progressively fill individual syllables as playback advances")
        suite.expect(before.height == part.height && part.height == after.height,
                     "syllable highlighting does not resize or rewrap the lyric line")
        suite.expect(wrapped.height > part.height, "native text wraps to the available island width")
        suite.expect(abs(dimBefore.brightness - settled.brightness) < dimBefore.brightness * 0.01
            && settled.brightness < after.brightness,
                     "the completed verse settles to the dim state after its animation tail")
        let leading = NotchLyricLine(time: 1, text: "Answer", end: 4,
            syllables: [.init(range: NSRange(location: 0, length: 6), begin: 1, end: 4)])
        var trailing = leading; trailing.side = .trailing
        if let left = capture(3, sample: leading), let right = capture(3, sample: trailing) {
            suite.expect(right.center > left.center + 80, "TextKit places the duet singer on the opposite edge")
        } else { suite.expect(false, "duet alignment renders natively") }
        handoffLayout(suite)
    }

    private static func handoffLayout(_ suite: TestSuite) {
        let lyrics = NotchLyrics(lines: [
            .init(time: 12, text: "The first verse enters", end: 15),
            .init(time: 15, text: ""),
            .init(time: 28, text: "The next verse stays in place", end: 31)
        ], plain: "", instrumental: false, writers: ["Demo Writer"])
        let track = RadialNowPlayingSnapshot(title: "Handoff", artist: nil, album: nil, artworkData: nil,
                                             appBundleIdentifier: nil, appPID: nil)
        func view(_ time: Double) -> some View {
            let playback = NotchPlayback(track: track, isPlaying: false, elapsed: time, duration: 40, rate: 1, sampledAt: .now, canSeek: false)
            return NotchSyncedLyricsView(lyrics: lyrics, playback: playback, offset: 0,
                                         waiting: "Waiting", instrumental: "Instrumental")
                .frame(width: 260, height: 160)
        }
        let host = NSHostingView(rootView: view(11.5))
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 260, height: 160),
                            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil }
        func scroll(in view: NSView) -> NSScrollView? {
            if let result = view as? NSScrollView { return result }
            for child in view.subviews { if let result = scroll(in: child) { return result } }
            return nil
        }
        func settle(_ duration: Double = 0.12) {
            let until = Date().addingTimeInterval(duration)
            while Date() < until { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        }
        settle()
        guard let scroller = scroll(in: host), let document = scroller.documentView else {
            suite.expect(false, "native lyric viewport contains a scroll document"); return
        }
        let before = document.frame.height
        var offsets: [Double] = []
        var heights: [Double] = []
        for index in 0..<66 {
            host.rootView = view(11.6 + Double(index) / 60)
            settle(1 / 60)
            offsets.append(scroller.contentView.bounds.minY)
            heights.append(document.frame.height)
        }
        let moves = zip(offsets, offsets.dropFirst()).map { abs($1 - $0) }
        suite.expect(offsets.last! > offsets.first! + 1 && moves.filter { $0 > 0.05 }.count > 6,
                     "the animated native handoff moves over multiple frames rather than jumping to its final offset")
        suite.expect(moves.max() ?? 0 < 12, "native handoff frame increments stay bounded without sudden grid jumps")
        suite.expect(abs(before - document.frame.height - 42) < 1,
                     "the completed waiting slot releases its height and spacing instead of leaving a phantom gap")
        host.rootView = view(20)
        settle(0.25)
        suite.expect(document.frame.height > heights.last! + 30,
                     "a real middle-song instrumental interval has a visible indicator slot")
        host.rootView = view(28.6)
        settle(0.6)
        suite.expect(abs(document.frame.height - heights.last!) < 1,
                     "the middle-song slot disappears completely after its transition")

        // Also advance a real playback clock without replacing the root view:
        // explicit TimelineView events must wake the collapsing gap on their own.
        let live = NotchPlayback(track: track, isPlaying: true, elapsed: 11.5, duration: 40,
                                 rate: 1, sampledAt: .now, canSeek: false)
        let liveHost = NSHostingView(rootView: NotchSyncedLyricsView(lyrics: lyrics, playback: live, offset: 0,
            waiting: "Waiting", instrumental: "Instrumental").frame(width: 260, height: 160))
        window.contentView = liveHost
        let deadline = Date().addingTimeInterval(1.7)
        var liveHeights: [Double] = []
        while Date() < deadline {
            liveHost.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(1 / 60))
            if let liveDocument = scroll(in: liveHost)?.documentView { liveHeights.append(liveDocument.frame.height) }
        }
        suite.expect(liveHeights.count > 20 && abs((liveHeights.first ?? 0) - (liveHeights.last ?? 0) - 42) < 1,
                     "live playback automatically wakes and completes the gap collapse without a refreshed root view")
        if ProcessInfo.processInfo.environment["VORSSAINT_KARAOKE_TRACE"] != nil {
            print("LIVE GAP HEIGHTS", liveHeights)
        }
        suite.expect(zip(liveHeights, liveHeights.dropFirst()).filter { abs($0 - $1) > 0.1 }.count > 8,
                     "the live playback layout collapses across multiple actual display frames")

        // Ordinary verse changes preserve all anchor rectangles, unlike an
        // inserted/collapsing gap. They still must start auto-scroll.
        let ordinary = NotchLyrics(lines: (0..<12).map {
            .init(time: Double($0) * 2, text: "Verse \($0) with enough words to wrap onto another line", end: Double($0) * 2 + 1.8)
        }, plain: "", instrumental: false)
        let ordinaryPlayback = NotchPlayback(track: track, isPlaying: true, elapsed: 0.8, duration: 30,
            rate: 1, sampledAt: .now, canSeek: false)
        let ordinaryHost = NSHostingView(rootView: NotchSyncedLyricsView(lyrics: ordinary, playback: ordinaryPlayback,
            offset: 0, waiting: "Waiting", instrumental: "Instrumental")
            .frame(width: 260, height: 160).background(Color.blue))
        window.contentView = ordinaryHost
        let ordinaryDeadline = Date().addingTimeInterval(3.0)
        var ordinaryOffsets: [Double] = []
        while Date() < ordinaryDeadline {
            ordinaryHost.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(1 / 60))
            if let viewport = scroll(in: ordinaryHost) { ordinaryOffsets.append(viewport.contentView.bounds.minY) }
        }
        suite.expect((ordinaryOffsets.last ?? 0) > (ordinaryOffsets.first ?? 0) + 20,
                     "ordinary verse changes auto-scroll even when the layout anchors do not change")
        suite.expect(zip(ordinaryOffsets, ordinaryOffsets.dropFirst()).filter { abs($1 - $0) > 0.05 }.count > 6,
                     "ordinary verse auto-scroll also advances across multiple frames")
        if let bitmap = ordinaryHost.bitmapImageRepForCachingDisplay(in: ordinaryHost.bounds) {
            ordinaryHost.cacheDisplay(in: ordinaryHost.bounds, to: bitmap)
            let color = bitmap.colorAt(x: bitmap.pixelsWide - 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB)
            if ProcessInfo.processInfo.environment["VORSSAINT_KARAOKE_TRACE"] != nil {
                print("TRANSPARENT VIEWPORT", color as Any, "host", ordinaryHost.frame, "opaque", ordinaryHost.isOpaque,
                      "scroll", scroll(in: ordinaryHost)?.isOpaque as Any, "clip", scroll(in: ordinaryHost)?.contentView.isOpaque as Any)
                if let png = bitmap.representation(using: .png, properties: [:]),
                   let directory = ProcessInfo.processInfo.environment["VORSSAINT_KARAOKE_SNAPSHOT_DIR"] {
                    try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("transparent-viewport.png"))
                }
            }
            // macOS resolves Color.blue using its current appearance/color space;
            // compare channel dominance instead of assuming a pure RGB primary.
            suite.expect((color?.blueComponent ?? 0) > 0.8
                && (color?.blueComponent ?? 0) > (color?.redComponent ?? 1) + 0.3
                && (color?.blueComponent ?? 0) > (color?.greenComponent ?? 1) + 0.15,
                         "the lyric viewport preserves its surrounding background instead of drawing a black rectangle")
        } else { suite.expect(false, "transparent native lyric viewport capture is available") }
    }
}
