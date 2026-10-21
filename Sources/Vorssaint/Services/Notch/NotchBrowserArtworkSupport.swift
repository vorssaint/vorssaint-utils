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

    /// The lookup reads the browser's saved session and goes online, so it
    /// waits for its own option in the music settings, which starts off.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchBrowserCovers)
    }

    /// Whether the browser's own cover is missing or too small to show sharp.
    static func needsCover(_ artwork: Data?) -> Bool {
        guard let artwork,
              let source = CGImageSourceCreateWithData(artwork as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return true }
        return min(width, height) < minimumCoverPixels
    }

    /// What the lookup of one track goes by, or nil when it has none to run:
    /// the option is off, the player is no Firefox-family browser, or its own
    /// cover is sharp. Two songs can share a title, so the artist keeps their
    /// covers and their cooldowns apart.
    static func lookupKey(for playback: NotchPlayback, defaults: UserDefaults = .standard) -> String? {
        guard isEnabled(in: defaults),
              let bundle = playback.track.appBundleIdentifier, profileFolders[bundle] != nil,
              let title = playback.track.title, needsCover(playback.track.artworkData) else { return nil }
        return [bundle, playback.track.artist ?? "", title].joined(separator: "\n")
    }

    /// A session with thousands of tabs stays well under this once decoded.
    static let maximumSessionBytes = 128 * 1_024 * 1_024
    /// The saved file is LZ4, a few times smaller than what it decodes to.
    static let maximumSessionFileBytes = 32 * 1_024 * 1_024
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
        guard data.count > 12, data.prefix(8).elementsEqual("mozLz40\0".utf8) else { return nil }
        let size = data.dropFirst(8).prefix(4).reversed().reduce(0) { $0 << 8 | Int($1) }
        guard size > 0, size <= maximumSessionBytes else { return nil }
        // Decoded straight into the result, so a large session is held once.
        var output = Data(count: size)
        let written = data.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { out in
                compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, size,
                                          input.bindMemory(to: UInt8.self).baseAddress! + 12,
                                          input.count - 12, nil, COMPRESSION_LZ4_RAW)
            }
        }
        return written == size ? output : nil
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

    /// The hosts whose pages can lead to a YouTube thumbnail.
    private static let youTubeHosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com",
                                                    "music.youtube.com", "youtu.be"]

    /// The tabs a cover can come from. Every other tab is dropped as soon as
    /// the session is read, so nothing else stays in memory.
    static func youTubeTabs(_ tabs: [SessionTab]) -> [SessionTab] {
        tabs.filter { youTubeHosts.contains($0.url.host?.lowercased() ?? "") }
    }

    /// Whether Apple's catalog may be asked for a song no tab names. YouTube
    /// Music keeps playing while its tab shows another page, where the
    /// session holds no video, so an open YouTube Music tab is required. A
    /// session saved before the lookup began may not list a new video's tab
    /// yet, so only a later one counts, and a plain YouTube video is found by
    /// its own tab instead of going to Apple. Waiting gives no such proof:
    /// once the user is idle for three minutes, Firefox saves only hourly.
    static func asksAppleMusic(tabs: [SessionTab], savedAt: Date, lookupStarted: Date) -> Bool {
        savedAt >= lookupStarted && tabs.contains { $0.url.host?.lowercased() == "music.youtube.com" }
    }

    /// Cover addresses for the tab that plays the track, best first. Only tabs
    /// with a known cover take part, so a search for the same song never wins.
    static func artworkURLs(forTrack title: String?, artist: String? = nil, in tabs: [SessionTab]) -> [URL] {
        guard let title else { return [] }
        let track = normalizedTabTitle(title)
        guard track.count >= 2 else { return [] }
        let credit = artist.map(normalizedTabTitle)
        // Sites wrap the track in their own name ("Title - YouTube") or an
        // unread count ("(3) Title"). Without those the tab must name the
        // track alone, or the track and its artist the way YouTube Music can,
        // so "Stay" never takes the cover of "Stay - Someone Else" and "Home"
        // never takes the cover of "Homeland".
        guard let tab = tabs.first(where: {
            !thumbnailURLs(forPage: $0.url).isEmpty && names(normalizedTabTitle($0.title), track, artist: credit)
        }) else { return [] }
        return thumbnailURLs(forPage: tab.url)
    }

    /// What YouTube and YouTube Music add after a page's own title, folded.
    private static let siteSuffixes = [" - youtube music", " | youtube music", " - youtube", " | youtube"]

    private static func names(_ tabTitle: String, _ track: String, artist: String?) -> Bool {
        let suffix = siteSuffixes.first { tabTitle.hasSuffix($0) }
        let page = String(tabTitle.dropLast(suffix?.count ?? 0))
        if page == track { return true }
        guard let artist, !artist.isEmpty else { return false }
        return page == track + " • " + artist
    }

    /// The browser saves a page's title with its runs of spaces collapsed,
    /// while Now Playing keeps the title as the page sent it.
    private static func normalizedTabTitle(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: #"^\s*\(\d+\+?\)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
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
    /// else counts as no match, so a wrong cover never shows. The art loads
    /// only from Apple's own image servers, whatever the reply names.
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
            return folded(name) == wantedTitle
                && (holdsName(wantedArtist, in: artists) || holdsName(artists, in: wantedArtist))
        }), let small = match["artworkUrl100"] as? String, small.hasSuffix("/100x100bb.jpg"),
              let cover = URL(string: String(small.dropLast("100x100bb.jpg".count)) + "600x600bb.jpg"),
              cover.scheme?.lowercased() == "https",
              cover.host?.lowercased().hasSuffix(".mzstatic.com") == true else { return nil }
        return cover
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `name` stands as whole words in `credit`, as "keshi" does in
    /// "keshi & Jay": "Mia" is not named by "Jeremias", nor "A" by "Adele".
    private static func holdsName(_ name: String, in credit: String) -> Bool {
        guard !name.isEmpty else { return false }
        let pattern = #"(?<![\p{L}\p{M}\p{N}])"# + NSRegularExpression.escapedPattern(for: name)
            + #"(?![\p{L}\p{M}\p{N}])"#
        return credit.range(of: pattern, options: .regularExpression) != nil
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
        } else if youTubeHosts.contains(host) {
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
