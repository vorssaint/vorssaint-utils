// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchYouTubeMusicTests {
    typealias Entry = NotchYouTubeMusicSupport.Entry

    private static func queueRow(_ title: String, artist: String, ref: Int) -> [Entry] {
        let scope = "ytmusic-player-queue-item"
        return [
            Entry(role: "AXImage", url: URL(string: "https://i.ytimg.com/vi/\(ref)/sddefault.jpg"), ref: ref),
            Entry(role: "AXButton", text: "Play \(title)", ref: ref + 1),
            Entry(role: "AXGroup", classes: ["song-title", "style-scope", scope], text: title, ref: ref + 2),
            Entry(role: "AXGroup", classes: ["byline", "style-scope", scope], text: artist, ref: ref + 3),
            Entry(role: "AXGroup", classes: ["duration", "style-scope", scope], text: "3:05", ref: ref + 4),
            Entry(role: "AXButton", text: "Action menu", ref: ref + 5),
        ]
    }

    static func run(_ suite: TestSuite) {
        var queue = NotchYouTubeMusicSupport.QueueParser()
        let page = [Entry(role: "AXImage", url: URL(string: "https://i.ytimg.com/vi/home/a.jpg"), ref: 0)]
            + queueRow("First", artist: "A", ref: 10) + queueRow("Café Song", artist: "B", ref: 20)
            + queueRow("Third", artist: "C", ref: 30)
        page.forEach { queue.feed($0) }
        let upcoming = queue.upcoming(after: "cafe  song")
        suite.expect(upcoming?.map(\.title) == ["Third"] && upcoming?.first?.subtitle == "C"
                     && upcoming?.first?.duration == 185 && upcoming?.first?.action == 31,
                     "the YouTube Music queue lists the songs after the playing one and presses their play button")
        suite.expect(queue.upcoming(after: "Unknown") == nil,
                     "a page that does not play the song shows no YouTube Music queue")

        var again = NotchYouTubeMusicSupport.ListenAgainParser()
        let card = "ytmusic-two-row-item-renderer"
        let shelf: [Entry] = [
            Entry(role: "AXGroup", classes: ["strapline", "ytmusic-carousel-shelf-basic-header-renderer"], text: "Name", ref: 0),
            Entry(role: "AXHeading", text: "Listen again", ref: 1),
            Entry(role: "AXImage", url: URL(string: "https://lh3.googleusercontent.com/x"), ref: 2),
            Entry(role: "AXButton", text: "Play Album One", ref: 3),
            Entry(role: "AXLink", text: "Album One", ref: 4),
            Entry(role: "AXGroup", classes: ["title", card], text: "Album One", ref: 5),
            Entry(role: "AXGroup", classes: ["subtitle", card], text: "Album • Artist", ref: 6),
            Entry(role: "AXButton", text: "Action menu", ref: 7),
            Entry(role: "AXLink", text: "Mix", ref: 8),
            Entry(role: "AXGroup", classes: ["title", card], text: "Mix", ref: 9),
            Entry(role: "AXHeading", text: "Quick picks", ref: 10),
            Entry(role: "AXGroup", classes: ["title", card], text: "Not shown", ref: 11),
        ]
        var stopped = false
        for entry in shelf where !stopped { stopped = again.feed(entry) }
        suite.expect(again.playable.map(\.title) == ["Album One", "Mix"] && again.playable.map(\.action) == [3, 8]
                     && again.playable.first?.subtitle == "Album • Artist" && stopped,
                     "Listen again reads its own shelf, plays from the cover's button or the title's link, and stops at the next shelf")
        suite.expect(NotchYouTubeMusicSupport.isCandidate(bundleIdentifier: "com.apple.Safari.WebApp.B46DBF3F")
                     && NotchYouTubeMusicSupport.duration("1:02:03") == 3723 && !NotchYouTubeMusicSupport.isCoverURL(URL(string: "http://i.ytimg.com/a")),
                     "web apps from Safari are read, and only HTTPS covers from YouTube's hosts load")
    }
}
