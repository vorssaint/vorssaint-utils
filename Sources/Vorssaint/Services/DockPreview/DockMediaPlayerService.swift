// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum DockMediaPlaybackState: String, Equatable {
    case playing
    case paused
    case stopped
}

struct DockMediaPlayer: Equatable {
    let bundleID: String
    let appName: String
    let title: String
    let artist: String?
    let album: String?
    let state: DockMediaPlaybackState
    let position: TimeInterval?
    let duration: TimeInterval?
    let artwork: NSImage?
    let appIcon: NSImage?

    var isPlaying: Bool { state == .playing }

    var progress: Double? {
        guard let position, let duration, duration > 0 else { return nil }
        return min(max(position / duration, 0), 1)
    }

    var hasTrack: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state != .stopped
    }

    static func == (lhs: DockMediaPlayer, rhs: DockMediaPlayer) -> Bool {
        lhs.bundleID == rhs.bundleID
            && lhs.appName == rhs.appName
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.state == rhs.state
            && lhs.position == rhs.position
            && lhs.duration == rhs.duration
            && lhs.artwork?.tiffRepresentation == rhs.artwork?.tiffRepresentation
    }
}

enum DockMediaCommand {
    case previous
    case playPause
    case next
}

struct DockMediaPlayerSource: Equatable {
    let bundleID: String
    let appName: String
    let appIcon: NSImage?

    init?(app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier,
              Self.supportedBundleIDs.contains(bundleID)
        else { return nil }
        self.bundleID = bundleID
        self.appName = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? bundleID
        self.appIcon = app.icon
    }

    private static let supportedBundleIDs: Set<String> = [
        "com.spotify.client",
        "com.apple.Music",
        "com.apple.iTunes",
    ]
}

final class DockMediaPlayerService {
    static let shared = DockMediaPlayerService()

    private let queue = DispatchQueue(label: "com.vorssaint.dock-media-player", qos: .userInitiated)
    private var artworkCache: [URL: NSImage] = [:]
    private var artworkCacheOrder: [URL] = []

    private init() {}

    func snapshot(for source: DockMediaPlayerSource, completion: @escaping (DockMediaPlayer?) -> Void) {
        queue.async {
            let snapshot = self.loadSnapshot(for: source)
            DispatchQueue.main.async {
                completion(snapshot)
            }
        }
    }

    func perform(_ command: DockMediaCommand, for bundleID: String) {
        queue.async {
            guard AppleScriptRunner.consentToAutomate(bundleID: bundleID) else { return }
            _ = AppleScriptRunner.run(Self.commandScript(bundleID: bundleID, command: command))
        }
    }

    private func loadSnapshot(for source: DockMediaPlayerSource) -> DockMediaPlayer? {
        guard AppleScriptRunner.consentToAutomate(bundleID: source.bundleID) else { return nil }
        let result = AppleScriptRunner.runDetailed(Self.snapshotScript(bundleID: source.bundleID))
        guard result.ok else { return nil }
        return parse(result.output, source: source)
    }

    private func parse(_ output: String, source: DockMediaPlayerSource) -> DockMediaPlayer? {
        let fields = output.components(separatedBy: Self.fieldSeparator)
        guard fields.count >= 7 else { return nil }

        let state = DockMediaPlaybackState(rawValue: fields[0].trimmingCharacters(in: .whitespacesAndNewlines))
            ?? .stopped
        let title = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = clean(fields[2])
        let album = clean(fields[3])
        let position = seconds(from: fields[4])
        let duration = normalizedDuration(from: fields[5], bundleID: source.bundleID)
        let artworkURL = clean(fields[6]).flatMap(URL.init(string:))
        let artwork = artworkURL.flatMap(loadArtwork)

        let player = DockMediaPlayer(bundleID: source.bundleID,
                                     appName: source.appName,
                                     title: title,
                                     artist: artist,
                                     album: album,
                                     state: state,
                                     position: position,
                                     duration: duration,
                                     artwork: artwork,
                                     appIcon: source.appIcon)
        return player.hasTrack ? player : nil
    }

    private func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func seconds(from value: String) -> TimeInterval? {
        guard let double = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), double >= 0 else {
            return nil
        }
        return double
    }

    private func normalizedDuration(from value: String, bundleID: String) -> TimeInterval? {
        guard let duration = seconds(from: value), duration > 0 else { return nil }
        return bundleID == "com.spotify.client" ? duration / 1_000 : duration
    }

    private func loadArtwork(from url: URL) -> NSImage? {
        if let cached = artworkCache[url] {
            return cached
        }
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        guard let image = NSImage(data: data) else { return nil }
        artworkCache[url] = image
        artworkCacheOrder.removeAll { $0 == url }
        artworkCacheOrder.append(url)
        while artworkCacheOrder.count > Self.maximumArtworkCacheCount {
            let stale = artworkCacheOrder.removeFirst()
            artworkCache.removeValue(forKey: stale)
        }
        return image
    }

    private static let fieldSeparator = String(UnicodeScalar(30)!)
    private static let maximumArtworkCacheCount = 16

    private static func snapshotScript(bundleID: String) -> String {
        switch bundleID {
        case "com.spotify.client":
            return """
            tell application id "com.spotify.client"
                if player state is stopped then return "stopped\(fieldSeparator)\(fieldSeparator)\(fieldSeparator)\(fieldSeparator)0\(fieldSeparator)0\(fieldSeparator)"
                set t to current track
                return (player state as string) & "\(fieldSeparator)" & (name of t as string) & "\(fieldSeparator)" & (artist of t as string) & "\(fieldSeparator)" & (album of t as string) & "\(fieldSeparator)" & (player position as string) & "\(fieldSeparator)" & (duration of t as string) & "\(fieldSeparator)" & (artwork url of t as string)
            end tell
            """
        default:
            return """
            tell application id "\(bundleID)"
                if player state is stopped then return "stopped\(fieldSeparator)\(fieldSeparator)\(fieldSeparator)\(fieldSeparator)0\(fieldSeparator)0\(fieldSeparator)"
                set t to current track
                return (player state as string) & "\(fieldSeparator)" & (name of t as string) & "\(fieldSeparator)" & (artist of t as string) & "\(fieldSeparator)" & (album of t as string) & "\(fieldSeparator)" & (player position as string) & "\(fieldSeparator)" & (duration of t as string) & "\(fieldSeparator)"
            end tell
            """
        }
    }

    private static func commandScript(bundleID: String, command: DockMediaCommand) -> String {
        let verb: String
        switch command {
        case .previous: verb = "previous track"
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        }
        return """
        tell application id "\(bundleID)"
            \(verb)
        end tell
        """
    }
}
