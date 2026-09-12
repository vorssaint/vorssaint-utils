// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Backs the panel's Now Playing section. The read is the same out-of-process
/// one the radial menu's card uses (`MediaRemoteNowPlayingBridge`); only the
/// paused-session question is answered differently, and the state lives here
/// rather than on `RadialNowPlayingService` so opening the panel never
/// disturbs the card the wheel is holding.
///
/// Nothing polls. The panel is a popover, so a read happens when the section
/// appears and after a transport press, and never while the panel is shut.
final class NowPlayingPanelService: ObservableObject {
    static let shared = NowPlayingPanelService()

    @Published private(set) var state = RadialNowPlayingState.nothingPlaying

    private let bridge = MediaRemoteNowPlayingBridge()
    private var generation = 0

    private init() {}

    func refresh() {
        generation += 1
        let requested = generation
        if case .playing = state {} else { state = .loading }
        bridge.fetch(includesPaused: true) { [weak self] snapshot in
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { return }
                self.state = snapshot.map(RadialNowPlayingState.playing) ?? .nothingPlaying
            }
        }
    }

    /// The glyph flips before the player answers, because the read costs a
    /// process launch and a media key that looked like it did nothing is worse
    /// than one that corrects itself. The confirming read follows, and a
    /// stale reply loses to `generation`.
    func press(_ key: RadialMenuMediaKey) {
        guard let auxKeyType = key.auxKeyType else { return }
        MediaKeyInput.post(auxKeyType: auxKeyType)
        if key == .playPause, case let .playing(snapshot) = state {
            state = .playing(snapshot.togglingPlayback)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
        }
    }
}
