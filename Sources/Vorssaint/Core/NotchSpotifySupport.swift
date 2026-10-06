// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

/// The pieces of Spotify's Web API the heart button needs, kept free of
/// networking so they can be tested. Each person registers their own Spotify
/// app: a development-mode app is limited to a handful of users, so a shared
/// client ID would stop working for everyone else.
enum NotchSpotifySupport {
    static let bundleIdentifier = "com.spotify.client"
    static let callbackPort: UInt16 = 43827
    static let redirectURI = "http://127.0.0.1:\(callbackPort)/callback"
    static let scopes = "user-read-currently-playing user-read-playback-state user-library-read user-library-modify"
    static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    static let apiBase = URL(string: "https://api.spotify.com/v1")!

    /// A client ID is 32 lowercase hexadecimal characters.
    static func validClientID(_ value: String) -> Bool {
        value.utf8.count == 32 && value.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }

    /// Random URL-safe text for the PKCE verifier and the state check.
    static func randomToken(bytes: Int = 48) -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<bytes).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func authorizationURL(clientID: String, verifier: String, state: String) -> URL? {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scopes),
        ]
        return components?.url
    }

    enum Callback: Equatable { case code(String), denied, invalid }

    /// Reads the first line of the browser's request to the loopback
    /// listener. Only a callback carrying the expected state is accepted.
    static func callback(fromRequest request: String, expectedState: String) -> Callback {
        guard let line = request.components(separatedBy: .newlines).first else { return .invalid }
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[2].hasPrefix("HTTP/"),
              let components = URLComponents(string: String(parts[1])), components.path == "/callback" else { return .invalid }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
        guard value("state") == expectedState else { return .invalid }
        if let code = value("code"), !code.isEmpty, code.utf8.count <= 2048 { return .code(code) }
        return value("error") == nil ? .invalid : .denied
    }

    /// The loopback listener's whole reply. A request that is not the
    /// callback, such as the browser's favicon, gets an empty 404.
    static func callbackResponse(page: String?) -> Data {
        guard let page else {
            return Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        }
        let escaped = page.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        let body = "<!doctype html><meta charset=utf-8><title>\(AppInfo.name)</title>"
            + "<p style=\"font:16px -apple-system,sans-serif;margin:3em\">\(escaped)</p>"
        return Data(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\n"
                     + "Connection: close\r\n\r\n" + body).utf8)
    }

    /// Spotify answers a refresh token it no longer honors with 400
    /// (invalid_grant). Anything else, a server error or a dropped
    /// connection, is worth trying again later.
    static func refreshRevoked(status: Int) -> Bool { status == 400 || status == 401 }

    static func formBody(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(fields.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&").utf8)
    }

    struct Tokens: Codable, Equatable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date

        func isFresh(at date: Date = Date()) -> Bool { expiresAt.timeIntervalSince(date) > 60 }
    }

    /// A refresh reply may leave out the refresh token; the old one then stays.
    static func tokens(from data: Data, previousRefreshToken: String? = nil, now: Date = Date()) -> Tokens? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["access_token"] as? String, !access.isEmpty,
              let refresh = (object["refresh_token"] as? String) ?? previousRefreshToken, !refresh.isEmpty else { return nil }
        let lifetime = (object["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return Tokens(accessToken: access, refreshToken: refresh, expiresAt: now.addingTimeInterval(max(60, min(lifetime, 86_400))))
    }

    struct Item: Equatable {
        let uri: String
        let name: String
    }

    /// The track or episode the account is playing, on any device.
    static func currentItem(from data: Data) -> Item? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = object["item"] as? [String: Any],
              let uri = item["uri"] as? String, validItemURI(uri),
              let name = item["name"] as? String else { return nil }
        return Item(uri: uri, name: name)
    }

    /// Only catalog tracks and episodes can be saved; a local file cannot.
    static func validItemURI(_ uri: String) -> Bool {
        let parts = uri.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0] == "spotify" && ["track", "episode"].contains(parts[1])
            && parts[2].utf8.count == 22 && parts[2].unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
    }

    static func saved(from data: Data) -> Bool? {
        guard let values = try? JSONSerialization.jsonObject(with: data) as? [Any], values.count == 1,
              let number = values[0] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// The island's title and Spotify's name for the same song can differ in
    /// case, accents or spacing; anything more is a different song.
    static func sameSong(_ island: String?, _ spotify: String) -> Bool {
        guard let island else { return false }
        func normal(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let left = normal(island), right = normal(spotify)
        return !left.isEmpty && left == right
    }

    static func libraryURL(_ path: String, uri: String) -> URL? {
        var components = URLComponents(url: apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "uris", value: uri)]
        return components?.url
    }
}
