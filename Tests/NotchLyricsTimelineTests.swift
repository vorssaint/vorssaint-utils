// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum NotchLyricsTimelineTests {
    // Native scheduling, with visibility supplied without ordering a window
    // onscreen. The production schedule and highlighting logic run unchanged.
    private final class Window: NSWindow {
        override var isVisible: Bool { true }
        override var occlusionState: NSWindow.OcclusionState { [.visible] }
    }

    private final class Observations {
        var active: Int?
        var count = 0
        func record(_ active: Int?) { self.active = active; count += 1 }
    }

    private struct Content: View {
        let lyrics: NotchLyrics
        let playback: NotchPlayback
        let offset: Double
        let observations: Observations

        var body: some View {
            TimelineView(.explicit(lyrics.changeDates(for: playback, offset: offset, from: .now))) { context in
                let _ = observations.record(lyrics.activeIndex(at: playback.position(at: context.date), offset: offset))
                Color.clear.frame(width: 40, height: 20)
            }
        }
    }

    static func run(expect: (Bool, String) -> Void) {
        let track = RadialNowPlayingSnapshot(title: "Timed verses", artist: nil, album: nil,
                                            artworkData: nil, appBundleIdentifier: nil, appPID: nil)
        func check(_ times: [Double], duration: Double = 10, offset: Double = 0,
                   blankLast: Bool = false, expected: Int, message: String) {
            let lyrics = NotchLyrics(lines: times.enumerated().map { index, time in
                NotchLyricLine(time: time, text: blankLast && index == times.count - 1 ? "" : "Verse")
            }, plain: "", instrumental: false)
            let playback = NotchPlayback(track: track, isPlaying: true, elapsed: 0, duration: duration,
                                         rate: 1, sampledAt: .now, canSeek: false)
            let observations = Observations()
            let window = Window(contentRect: CGRect(x: 0, y: 0, width: 40, height: 20),
                                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: Content(lyrics: lyrics, playback: playback,
                                                      offset: offset, observations: observations))
            window.contentView = host
            defer { window.contentView = nil }
            let deadline = Date().addingTimeInterval(2)
            while observations.active != expected && Date() < deadline {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            expect(observations.active == expected, message)
            let count = observations.count
            let settled = Date().addingTimeInterval(0.12)
            while Date() < settled { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            expect(observations.count == count, "lyrics stop updating after the last reachable verse")
        }

        check([0, 0.08, 0.16], expected: 2,
              message: "the native timeline highlights the final verse without another player update")
        check([0.08], expected: 0,
              message: "a single future verse is highlighted when its time arrives")
        check([0, 0.08], blankLast: true, expected: 1,
              message: "a final instrumental gap clears the preceding verse")
        check([0, 0.08, 0.16], duration: 0.2, offset: 0.05, expected: 1,
              message: "timing adjustment delivers the last reachable verse when later verses exceed the duration")

        seekPositions(expect: expect)
    }

    /// Clicking a verse asks the player to move to its start, with the user's
    /// timing adjustment applied and the recording's bounds kept.
    private static func seekPositions(expect: (Bool, String) -> Void) {
        let track = RadialNowPlayingSnapshot(title: "Timed verses", artist: nil, album: nil,
                                             artworkData: nil, appBundleIdentifier: nil, appPID: nil)
        let lyrics = NotchLyrics(lines: [NotchLyricLine(time: 0, text: "One"),
                                         NotchLyricLine(time: 30, text: "Two"),
                                         NotchLyricLine(time: 120, text: "Three")],
                                 plain: "", instrumental: false)
        func playback(duration: Double = 180, canSeek: Bool = true) -> NotchPlayback {
            NotchPlayback(track: track, isPlaying: true, elapsed: 0, duration: duration,
                          rate: 1, sampledAt: .now, canSeek: canSeek)
        }
        expect(lyrics.seekPosition(for: 1, offset: 0, into: playback(), allowed: true) == 30,
               "clicking a verse moves the player to its start")
        expect(lyrics.seekPosition(for: 1, offset: 0.5, into: playback(), allowed: true) == 30.5,
               "a timing adjustment moves the clicked target with the verses")
        expect(lyrics.seekPosition(for: 0, offset: -10, into: playback(), allowed: true) == 0,
               "clicking the first verse never asks to play before the recording")
        expect(lyrics.seekPosition(for: 1, offset: 0, into: playback(duration: 20), allowed: true) == 20,
               "a verse past the end asks for the end rather than an impossible position")
        expect(lyrics.seekPosition(for: 1, offset: 0, into: playback(canSeek: false), allowed: true) == 30,
               "a player driven through automation moves to the clicked verse")
        expect(lyrics.seekPosition(for: 1, offset: 0, into: playback(), allowed: false) == nil,
               "a player that cannot seek gets no target")
        expect(lyrics.seekPosition(for: 3, offset: 0, into: playback(), allowed: true) == nil,
               "a verse that does not exist gets no target")
    }
}
