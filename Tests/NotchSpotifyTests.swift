// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchSpotifyTests {
    static func run(_ suite: TestSuite) {
        support(suite)
        listener(suite)
        settings(suite)
    }


    private static func support(_ suite: TestSuite) {
        typealias Spotify = NotchSpotifySupport
        let id = "4uLU6hMCjMI75M1A2tKUQC"
        suite.expect(Spotify.validClientID("0123456789abcdef0123456789abcdef") && !Spotify.validClientID("0123456789ABCDEF0123456789abcdef")
                     && !Spotify.validClientID("short") && !Spotify.validClientID(""), "only a well-formed client ID can start sign-in")
        // RFC 7636 appendix B.
        suite.expect(Spotify.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
                     "the PKCE challenge is the URL-safe SHA-256 of the verifier")
        let verifier = Spotify.randomToken()
        suite.expect(verifier.count >= 43 && verifier.count <= 128 && verifier != Spotify.randomToken()
                     && verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }, "a verifier is fresh, long enough and URL-safe")
        let url = Spotify.authorizationURL(clientID: "0123456789abcdef0123456789abcdef", verifier: verifier, state: "s1")
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }
        suite.expect(url?.host == "accounts.spotify.com" && item("redirect_uri") == "http://127.0.0.1:43827/callback"
                     && item("code_challenge_method") == "S256" && item("code_challenge") == Spotify.challenge(for: verifier)
                     && item("state") == "s1" && item("scope")?.contains("user-library-modify") == true,
                     "sign-in asks for the library scopes over PKCE with the loopback redirect")
        suite.expect(Spotify.callback(fromRequest: "GET /callback?code=abc&state=s1 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n", expectedState: "s1") == .code("abc"),
                     "the browser's callback hands over its code")
        suite.expect(Spotify.callback(fromRequest: "GET /callback?code=abc&state=other HTTP/1.1\r\n", expectedState: "s1") == .invalid
                     && Spotify.callback(fromRequest: "GET /favicon.ico HTTP/1.1\r\n", expectedState: "s1") == .invalid
                     && Spotify.callback(fromRequest: "POST /callback?code=abc&state=s1 HTTP/1.1\r\n", expectedState: "s1") == .invalid,
                     "a callback with another state, path or method is ignored")
        suite.expect(Spotify.callback(fromRequest: "GET /callback?error=access_denied&state=s1 HTTP/1.1\r\n", expectedState: "s1") == .denied,
                     "declining in the browser ends the sign-in")
        let now = Date(timeIntervalSince1970: 1_000)
        let first = Spotify.tokens(from: Data(#"{"access_token":"a","refresh_token":"r","expires_in":3600}"#.utf8), now: now)
        let renewed = Spotify.tokens(from: Data(#"{"access_token":"b","expires_in":3600}"#.utf8), previousRefreshToken: "r", now: now)
        suite.expect(first == .init(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(3600))
                     && renewed?.refreshToken == "r" && renewed?.accessToken == "b"
                     && Spotify.tokens(from: Data(#"{"access_token":"b"}"#.utf8)) == nil,
                     "a refresh without a new refresh token keeps the old one")
        suite.expect(first?.isFresh(at: now) == true && first?.isFresh(at: now.addingTimeInterval(3590)) == false,
                     "a token is renewed shortly before it expires")
        suite.expect(Spotify.currentItem(from: Data(#"{"item":{"uri":"spotify:track:\#(id)","name":"Song"}}"#.utf8)) == .init(uri: "spotify:track:\(id)", name: "Song")
                     && Spotify.currentItem(from: Data(#"{"item":{"uri":"spotify:local:a:b:c:1","name":"Local"}}"#.utf8)) == nil
                     && Spotify.currentItem(from: Data(#"{"item":null}"#.utf8)) == nil,
                     "only a catalog track or episode can be liked")
        suite.expect(Spotify.saved(from: Data("[true]".utf8)) == true && Spotify.saved(from: Data("[false]".utf8)) == false
                     && Spotify.saved(from: Data("[1]".utf8)) == nil && Spotify.saved(from: Data("[true,false]".utf8)) == nil,
                     "the saved answer is one Boolean for the one song asked about")
        suite.expect(Spotify.sameSong("Café  del Mar", "cafe del mar") && !Spotify.sameSong("Song", "Song (Live)")
                     && !Spotify.sameSong(nil, "Song") && !Spotify.sameSong("", ""),
                     "the heart only follows the song the island shows")
        suite.expect(Spotify.libraryURL("me/library/contains", uri: "spotify:track:\(id)")?.absoluteString
                     == "https://api.spotify.com/v1/me/library/contains?uris=spotify:track:\(id)",
                     "library calls name the song by its URI")
    }

    private static func listener(_ suite: TestSuite) {
        typealias Spotify = NotchSpotifySupport
        let page = String(decoding: Spotify.callbackResponse(page: "Signed in <now> & done"), as: UTF8.self)
        let body = page.components(separatedBy: "\r\n\r\n").last ?? ""
        suite.expect(page.hasPrefix("HTTP/1.1 200 OK\r\n") && page.contains("Content-Length: \(body.utf8.count)\r\n")
                     && body.contains("Signed in &lt;now> &amp; done"),
                     "the browser is told sign-in finished, with the text escaped and the length exact")
        suite.expect(String(decoding: Spotify.callbackResponse(page: nil), as: UTF8.self).hasPrefix("HTTP/1.1 404"),
                     "a stray request such as the favicon gets nothing")
        suite.expect(Spotify.refreshRevoked(status: 400) && !Spotify.refreshRevoked(status: 500) && !Spotify.refreshRevoked(status: 429),
                     "only a refused refresh signs out; a server error keeps the account")
    }

    private static func settings(_ suite: TestSuite) {
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchSpotifyClientID)
                     && SettingsBackupSupport.exportKeys().contains(AppFeature.notchSpotify.availabilityKey),
                     "the Client ID and the feature choice are accounted for by settings backup")
        suite.expect(!AppFeature.notchSpotify.installedByDefault && AppFeature.notchSpotify.permissions.isEmpty,
                     "Spotify likes are opt-in and ask for no system permission")
        for language in AppLanguage.allCases {
            let strings = Mirror(reflecting: FeatureStrings.notchSpotify(language)).children.compactMap { $0.value as? String }
            suite.expect(strings.count == 22 && strings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                         "Spotify strings are complete in \(language.rawValue)")
        }
    }
}
