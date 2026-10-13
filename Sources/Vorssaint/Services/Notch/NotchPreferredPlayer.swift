// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The music app the island opens when nothing is playing and a playback
/// button or the cover is clicked. Opening it never starts playback.
enum NotchPreferredPlayer {
    /// Stored when the choice is left to the island.
    static let automatic = ""
    static let known = ["com.spotify.client", "com.apple.Music"]
    /// The music app that last played in this launch of the app. Not saved:
    /// it names what the person was listening to, not a setting.
    static var lastPlayed: String?

    static func choice(in defaults: UserDefaults = .standard) -> String {
        let value = defaults.string(forKey: DefaultsKey.notchPreferredPlayer) ?? automatic
        return value.utf8.count <= 256 ? value : automatic
    }

    /// A chosen player wins while it is installed. Otherwise the music app
    /// that played last, then Spotify, then Apple Music.
    static func resolve(choice: String, lastPlayed: String?, isInstalled: (String) -> Bool) -> String? {
        if !choice.isEmpty, isInstalled(choice) { return choice }
        if let lastPlayed, isInstalled(lastPlayed) { return lastPlayed }
        return known.first(where: isInstalled)
    }

    static func current() -> String? {
        resolve(choice: choice(), lastPlayed: lastPlayed) { InstalledApps.url(for: $0) != nil }
    }

    static func remember(_ playback: NotchPlayback?, in sources: [NotchPlaybackSource]) {
        guard let playback, playback.isPlaying, let bundle = playback.track.appBundleIdentifier,
              known.contains(bundle) || sources.contains(where: { $0.bundleIdentifier == bundle && $0.isMusicApp }) else { return }
        lastPlayed = bundle
    }

    typealias Choice = (bundleID: String, name: String)

    /// The installed choices are a snapshot. A saved choice stays available
    /// before the scan finishes, or when its app is no longer installed.
    static func choices(in installed: [Choice], including chosen: String) -> [Choice] {
        guard !chosen.isEmpty, !installed.contains(where: { $0.bundleID == chosen }) else { return installed }
        return installed + [(chosen, chosen)]
    }

    /// Scan away from the view's main thread. A task that left the screen
    /// while the scan ran cannot publish its late result.
    static func loadInstalled(using load: @escaping @Sendable () -> [Choice] = { installed() }) async -> [Choice]? {
        guard !Task.isCancelled else { return nil }
        let choices = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: load())
            }
        }
        return Task.isCancelled ? nil : choices
    }

    /// The known players that are installed, and any other music app.
    static func installed() -> [Choice] {
        var ids = known.filter { InstalledApps.url(for: $0) != nil }
        for app in InstalledApps.installedApplications(includeSystemApplications: true) {
            guard let id = app.bundleID, !ids.contains(id),
                  Bundle(url: app.url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String == "public.app-category.music"
            else { continue }
            ids.append(id)
        }
        return ids.map { ($0, InstalledApps.name(for: $0)) }
    }

    /// "Open Spotify", for the tooltip and VoiceOver of what opens it.
    static func openTitle(for id: String) -> String {
        return String(format: FeatureStrings.notchMusicExtras(L10n.shared.language).openNamedPlayer, InstalledApps.name(for: id))
    }

    /// Opens the player, once; a second click while it launches is ignored by
    /// Launch Services.
    @discardableResult
    static func open() -> Bool {
        guard let id = current(), let url = InstalledApps.url(for: id), Bundle(url: url)?.bundleIdentifier == id else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
}
