// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where a recognised song opens, and which Chrome profile YouTube opens in.
enum MusicRecognitionLinksTests {
    static func run(_ suite: TestSuite) {
        suite.expect(MusicRecognitionLinks.spotifyApp("Wakhra Swag Navv Inder")?.absoluteString
                        == "spotify:search:Wakhra%20Swag%20Navv%20Inder"
                        && MusicRecognitionLinks.youTube("Rock & Roll")?.absoluteString
                        == "https://www.youtube.com/results?search_query=Rock%20%26%20Roll"
                        && MusicRecognitionLinks.spotifyWeb("a/b")?.absoluteString == "https://open.spotify.com/search/a%2Fb",
                     "a song opens Spotify and YouTube searched by its title and artist, safely encoded")
        let state = Data("""
        {"profile":{"info_cache":{
          "Default":{"name":"Work","user_name":"work@example.com"},
          "Profile 2":{"name":"kabir","user_name":"someone@example.com"},
          "Profile 3":{"name":"Personal","user_name":"kabir@example.com"}}}}
        """.utf8)
        suite.expect(MusicRecognitionLinks.chromeProfileDirectory(matching: "KABIR@example.com", localState: state) == "Profile 3"
                        && MusicRecognitionLinks.chromeProfileDirectory(matching: "kabir", localState: state) == "Profile 2"
                        && MusicRecognitionLinks.chromeProfileDirectory(matching: "", localState: state) == nil
                        && MusicRecognitionLinks.chromeProfileDirectory(matching: "nobody", localState: state) == nil
                        && MusicRecognitionLinks.chromeProfileDirectory(matching: "kabir", localState: Data("{".utf8)) == nil,
                     "the Chrome profile is found by its account first, then its name; nothing chosen or found opens Chrome as it is")
    }
}
