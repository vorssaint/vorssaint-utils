// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Whether the song Apple Music plays is a favorite, and a way to change it,
/// through the same Automation consent the playback buttons use. Read only
/// while the music page is open.
final class NotchAppleMusicLikeService: ObservableObject {
    static let shared = NotchAppleMusicLikeService()
    /// Nil until Music answers, or while it has not been allowed to.
    @Published private(set) var liked: Bool?
    @Published private(set) var busy = false
    @Published private(set) var failed = false
    @Published private(set) var requestingAccess = false
    private let queue = DispatchQueue(label: "com.vorssaint.notch-applemusic-like", qos: .utility)
    private var generation = UUID()

    private init() {}

    func offers(_ playback: NotchPlayback?) -> Bool {
        playback?.track.appBundleIdentifier == NotchAppleMusicLikeSupport.bundleIdentifier
    }

    /// Runs when the page opens and whenever its song or player changes, since
    /// a song can also be favorited in Music itself.
    func refresh(for playback: NotchPlayback?) {
        let requested = UUID()
        generation = requested
        busy = false
        failed = false
        guard offers(playback) else { liked = nil; return }
        queue.async { [weak self] in
            let reply = AppleScriptRunner.runDetailed(NotchAppleMusicLikeSupport.readScript)
            let state = reply.ok ? NotchAppleMusicLikeSupport.state(in: reply.output) : nil
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { return }
                self.liked = state
            }
        }
    }

    /// The first press while Music has not been allowed asks for consent only.
    func toggle(for playback: NotchPlayback?) {
        guard offers(playback), !busy, !requestingAccess else { return }
        guard let current = liked else { requestAccess(for: playback); return }
        busy = true
        failed = false
        let requested = generation
        queue.async { [weak self] in
            let reply = AppleScriptRunner.runDetailed(NotchAppleMusicLikeSupport.writeScript(!current))
            let state = reply.ok ? NotchAppleMusicLikeSupport.state(in: reply.output) : nil
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { return }
                self.busy = false
                if let state { self.liked = state } else { self.failed = true }
            }
        }
    }

    func stop() {
        generation = UUID()
        liked = nil
        busy = false
        failed = false
    }

    private func requestAccess(for playback: NotchPlayback?) {
        requestingAccess = true
        failed = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let allowed = AppleScriptRunner.consentToAutomate(bundleID: NotchAppleMusicLikeSupport.bundleIdentifier)
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestingAccess = false
                if allowed { self.refresh(for: NotchMusicService.shared.playback) } else { self.failed = true }
            }
        }
    }
}
