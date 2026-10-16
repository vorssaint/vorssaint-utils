// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The playing app's own shuffle switch. Some players do not offer shuffle
/// to the system's Now Playing, so the music page asks the player through
/// its scripting dictionary, with the same Automation consent the playback
/// controls use. It is read only while the page is open.
final class NotchShuffleService: ObservableObject {
    static let shared = NotchShuffleService()
    @Published private(set) var availability: NotchMusicAutomation.Availability?
    /// Nil until the player answers, or while it has not been allowed to.
    @Published private(set) var enabled: Bool?
    /// False while the songs playing cannot be shuffled, as for a radio.
    @Published private(set) var allowed = true
    @Published private(set) var pending = false
    @Published private(set) var requestingAccess = false
    private let queue = DispatchQueue(label: "com.vorssaint.notch-shuffle", qos: .utility)
    private var generation = UUID()
    /// The latest switch; a later one, another player or a closed page
    /// makes an earlier reply and check stale.
    private var switchID = UUID()
    /// From the page's first refresh until it closes.
    private var open = false

    private init() {}

    /// A switch the player declares and either answers or can be allowed to.
    var isOffered: Bool {
        guard let availability else { return false }
        return availability.access == .consent || (availability.access == .granted && enabled != nil)
    }

    /// Runs when the page opens and whenever its song or player changes, since
    /// shuffle can also be switched in the player itself.
    func refresh(for playback: NotchPlayback?) {
        let target = playback.flatMap(NotchMusicAutomation.Target.init)
        let requested = UUID()
        generation = requested
        open = true
        // A new song on the same player keeps a switch on its way, so its
        // reply still ends the wait; another player drops it.
        if availability?.target != target { availability = nil; enabled = nil; pending = false; switchID = UUID() }
        guard let target else { return }
        queue.async { [weak self] in
            let available = NotchMusicAutomation.inspect(target).flatMap { $0.capabilities.shuffle == nil ? nil : $0 }
            let state = available.flatMap(NotchMusicAutomation.shuffle(of:))
            let allowed = available.map(NotchMusicAutomation.shuffleAllowed(by:)) ?? true
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { return }
                self.availability = available
                self.enabled = state
                self.allowed = allowed
            }
        }
    }

    /// The first press on a player not yet allowed asks for consent only; the
    /// next one switches shuffle.
    func toggle() {
        guard !pending, !requestingAccess, let available = availability, available.target.isCurrent else { return }
        if available.access == .consent { requestAccess(available); return }
        guard available.access == .granted, allowed, let current = enabled else { return }
        pending = true
        let id = UUID()
        switchID = id
        queue.async { [weak self] in
            let sent = NotchMusicAutomation.setShuffle(!current, availability: available)
            DispatchQueue.main.async {
                guard let self, self.switchID == id else { return }
                self.pending = false
                guard self.availability?.target == available.target else { return }
                self.enabled = sent ? !current : current
                // A switch that did not go through may mean consent was taken
                // back or the player went away, so the page looks again.
                if !sent { self.refresh(for: NotchMusicService.shared.playback) }
            }
            // Some players answer with the old state for about a second after
            // the switch, so the player's own answer is asked for a moment
            // later. It also corrects a song change's read in the meantime.
            self?.queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                let state = NotchMusicAutomation.shuffle(of: available)
                DispatchQueue.main.async {
                    guard let self, self.switchID == id, self.availability?.target == available.target,
                          let state else { return }
                    self.enabled = state
                }
            }
        }
    }

    func stop() {
        open = false
        generation = UUID()
        switchID = UUID()
        availability = nil
        enabled = nil
        allowed = true
        pending = false
    }

    private func requestAccess(_ available: NotchMusicAutomation.Availability) {
        requestingAccess = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if available.target.isCurrent { _ = AppleScriptRunner.consentToAutomate(bundleID: available.target.bundleIdentifier) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestingAccess = false
                // A new song while the dialog was up already read the old
                // answer, so only a closed page skips the look after it.
                guard self.open else { return }
                // The playback buttons share this consent, so they look again too.
                NotchMusicService.shared.refreshAutomation()
                self.refresh(for: NotchMusicService.shared.playback)
            }
        }
    }
}
