// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Compression
import Foundation
import ImageIO

/// Firefox and the browsers built on it publish no cover to macOS Now Playing,
/// or a 60-pixel one for YouTube Music. Their saved session lists every open
/// tab with its title and address, so the tab that plays the track leads to
/// the site's own thumbnail. YouTube and YouTube Music are the sites whose
/// cover address follows from the page.
enum NotchBrowserArtworkSupport {
    /// The island draws a cover up to 320 pixels across. Anything smaller on
    /// its short side blurs once stretched, so the lookup replaces it.
    static let minimumCoverPixels = 300

    /// Whether the browser's own cover is missing or too small to show sharp.
    static func needsCover(_ artwork: Data?) -> Bool {
        guard let artwork,
              let source = CGImageSourceCreateWithData(artwork as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return true }
        return min(width, height) < minimumCoverPixels
    }

    /// A session with thousands of tabs stays well under this once decoded.
    static let maximumSessionBytes = 256 * 1_024 * 1_024
    /// YouTube's largest thumbnail is a 1280×720 JPEG of a few hundred KB.
    static let maximumArtworkBytes = 4 * 1_024 * 1_024

    /// Where each browser keeps its profiles, under Application Support.
    static let profileFolders: [String: String] = [
        "org.mozilla.firefox": "Firefox/Profiles",
        "org.mozilla.firefoxdeveloperedition": "Firefox/Profiles",
        "org.mozilla.nightly": "Firefox/Profiles",
        "app.zen-browser.zen": "zen/Profiles",
        "io.gitlab.librewolf-community": "librewolf/Profiles",
        "net.waterfox.waterfox": "Waterfox/Profiles",
        "one.ablaze.floorp": "Floorp/Profiles",
    ]

    /// The session files a profile writes, newest first by Firefox's own
    /// schedule. The recovery file updates while the browser runs.
    static let sessionFiles = ["sessionstore-backups/recovery.jsonlz4", "sessionstore.jsonlz4"]

    struct SessionTab: Equatable {
        let title: String
        let url: URL
    }

    /// Mozilla's `mozLz40` container holds an 8-byte magic, the decoded size
    /// as a little-endian UInt32, then one raw LZ4 block.
    static func decodeMozLZ4(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 12, bytes.prefix(8).elementsEqual(Array("mozLz40\0".utf8)) else { return nil }
        let size = bytes[8..<12].reversed().reduce(0) { $0 << 8 | Int($1) }
        guard size > 0, size <= maximumSessionBytes else { return nil }
        var output = [UInt8](repeating: 0, count: size)
        let written = bytes.withUnsafeBufferPointer { input in
            output.withUnsafeMutableBufferPointer { out in
                compression_decode_buffer(out.baseAddress!, size, input.baseAddress! + 12,
                                          input.count - 12, nil, COMPRESSION_LZ4_RAW)
            }
        }
        return written == size ? Data(output) : nil
    }

    /// The page each open tab shows now. A tab keeps its back history in
    /// `entries`, and `index` counts from 1 to the current one.
    static func openTabs(inSession json: Data) -> [SessionTab] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let windows = root["windows"] as? [[String: Any]] else { return [] }
        return windows.flatMap { window in
            (window["tabs"] as? [[String: Any]] ?? []).compactMap { tab -> SessionTab? in
                guard let entries = tab["entries"] as? [[String: Any]], !entries.isEmpty else { return nil }
                let current = min(max((tab["index"] as? Int ?? entries.count) - 1, 0), entries.count - 1)
                guard let title = entries[current]["title"] as? String,
                      let address = entries[current]["url"] as? String,
                      let url = URL(string: address) else { return nil }
                return SessionTab(title: title, url: url)
            }
        }
    }

    /// Cover addresses for the tab that plays the track, best first. Only tabs
    /// with a known cover take part, so a search for the same song never wins.
    static func artworkURLs(forTrack title: String?, in tabs: [SessionTab]) -> [URL] {
        guard let title else { return [] }
        let track = normalizedTabTitle(title)
        guard track.count >= 2 else { return [] }
        let covered = tabs.filter { !thumbnailURLs(forPage: $0.url).isEmpty }
        let titles = covered.map { normalizedTabTitle($0.title) }
        // Sites wrap the track in their own name ("Title - YouTube") or an
        // unread count ("(3) Title"). A tab that starts with the track beats
        // one that only mentions it.
        guard let index = titles.firstIndex(where: { $0.hasPrefix(track) })
                ?? titles.firstIndex(where: { $0.contains(track) }) else { return [] }
        return thumbnailURLs(forPage: covered[index].url)
    }

    private static func normalizedTabTitle(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: #"^\s*\(\d+\+?\)\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A search of Apple's music catalog for one song, by its title and artist.
    /// Without an artist, a title alone would match covers of other songs.
    static func appleMusicSearchURL(title: String, artist: String?, country: String?) -> URL? {
        guard let artist, !artist.trimmingCharacters(in: .whitespaces).isEmpty,
              !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var url = URLComponents(string: "https://itunes.apple.com/search")!
        url.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "country", value: country.flatMap { $0.count == 2 ? $0 : nil } ?? "US"),
        ]
        return url.url
    }

    /// The 600-pixel album art of the result whose title and artist both match
    /// the track. A near miss such as a piano version or a cover by someone
    /// else counts as no match, so a wrong cover never shows.
    static func appleMusicArtworkURL(inSearch json: Data, title: String, artist: String?) -> URL? {
        guard let artist,
              let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return nil }
        let wantedTitle = folded(title)
        let wantedArtist = folded(artist)
        guard let match = results.first(where: { result in
            guard let name = result["trackName"] as? String,
                  let credit = result["artistName"] as? String else { return false }
            let artists = folded(credit)
            return folded(name) == wantedTitle && (artists.contains(wantedArtist) || wantedArtist.contains(artists))
        }), let small = match["artworkUrl100"] as? String,
              small.hasPrefix("https://"), small.hasSuffix("/100x100bb.jpg") else { return nil }
        return URL(string: String(small.dropLast("100x100bb.jpg".count)) + "600x600bb.jpg")
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The largest square centred in an image of this size, in pixels.
    static func centreSquare(width: Int, height: Int) -> CGRect {
        let side = max(0, min(width, height))
        return CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side)
    }

    /// YouTube serves every video's thumbnail from the video's ID. The full
    /// size one is missing for some older videos, so the medium one follows.
    /// Both are 16:9 without the black bands `hqdefault` adds, which a square
    /// crop would show.
    static func thumbnailURLs(forPage url: URL) -> [URL] {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased() else { return [] }
        let path = url.pathComponents.filter { $0 != "/" }
        let id: String?
        if host == "youtu.be" {
            id = path.first
        } else if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].contains(host) {
            if path.first == "watch" {
                id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "v" })?.value
            } else if path.count >= 2, ["shorts", "live", "embed"].contains(path[0]) {
                id = path[1]
            } else {
                id = nil
            }
        } else {
            id = nil
        }
        guard let id, id.count == 11,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "-" || $0 == "_" })
        else { return [] }
        return ["maxresdefault", "mqdefault"].compactMap { URL(string: "https://i.ytimg.com/vi/\(id)/\($0).jpg") }
    }
}

extension NotchPlayback {
    /// The same playback with a cover found somewhere other than Now Playing.
    func withArtwork(_ data: Data) -> NotchPlayback {
        let cover = RadialNowPlayingSnapshot(title: track.title, artist: track.artist, album: track.album,
                                             artworkData: data, appBundleIdentifier: track.appBundleIdentifier,
                                             appPID: track.appPID)
        return NotchPlayback(track: cover, isPlaying: isPlaying, elapsed: elapsed, duration: duration, rate: rate,
                             sampledAt: sampledAt, canSeek: canSeek, hasPosition: hasPosition,
                             itemIdentifier: itemIdentifier, commandContext: commandContext,
                             canSendCommandsDirectly: canSendCommandsDirectly,
                             canSkipNext: canSkipNext, canSkipPrevious: canSkipPrevious)
    }
}
