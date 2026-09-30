// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Switches the Mac's system time zone and keeps a favorites list, the way
/// Quick Toggles runs its one-shot system actions: nothing polls while the
/// page is closed, and the system's own notification keeps the current zone
/// honest even when something else changes it (System Settings, a location
/// update) while the page is open.
final class TimeZoneSwitchService: ObservableObject {
    static let shared = TimeZoneSwitchService()

    enum RunState: Equatable {
        case switching, failed
    }

    @Published private(set) var currentIdentifier: String
    @Published private(set) var favorites: [String]
    @Published private(set) var state: RunState?
    /// The one favorite actually being switched to, so a row for anything
    /// else never shows the in-progress spinner while this one runs.
    @Published private(set) var switchingIdentifier: String?

    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        currentIdentifier = TimeZone.current.identifier
        favorites = (defaults.stringArray(forKey: DefaultsKey.timeZoneSwitcherFavorites) ?? [])
            .filter(TimeZoneSwitchSupport.isKnownIdentifier)
        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshCurrentIdentifier()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func refreshCurrentIdentifier() {
        NSTimeZone.resetSystemTimeZone()
        currentIdentifier = TimeZone.current.identifier
    }

    func isFavorite(_ identifier: String) -> Bool {
        favorites.contains(identifier)
    }

    func addFavorite(_ identifier: String) {
        favorites = TimeZoneSwitchSupport.addingFavorite(identifier, to: favorites)
        persistFavorites()
    }

    func removeFavorite(_ identifier: String) {
        favorites = TimeZoneSwitchSupport.removingFavorite(identifier, from: favorites)
        persistFavorites()
    }

    func moveFavorites(fromOffsets: IndexSet, toOffset: Int) {
        favorites = TimeZoneSwitchSupport.movingFavorites(favorites, fromOffsets: fromOffsets, toOffset: toOffset)
        persistFavorites()
    }

    private func persistFavorites() {
        defaults.set(favorites, forKey: DefaultsKey.timeZoneSwitcherFavorites)
    }

    /// Dismisses a failure the person has already seen (the alert's own
    /// Cancel), instead of leaving it to the automatic timeout.
    func dismissFailure() {
        guard state == .failed else { return }
        state = nil
    }

    /// Runs `systemsetup -settimezone` through the password-free sudoers rule
    /// once it exists, or creates it first (one admin prompt, ever) the first
    /// time this Mac switches a zone. A second call while one is already
    /// running is ignored, exactly like Quick Toggles guards its own one-shot
    /// actions.
    func switchTimeZone(to identifier: String, completion: ((Bool) -> Void)? = nil) {
        guard AppFeature.timeZoneSwitcher.isAvailable,
              state != .switching,
              identifier != currentIdentifier,
              TimeZoneSwitchSupport.isKnownIdentifier(identifier) else {
            completion?(false)
            return
        }
        state = .switching
        switchingIdentifier = identifier
        func finish(_ success: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion?(success)
                    return
                }
                self.switchingIdentifier = nil
                if success {
                    self.refreshCurrentIdentifier()
                    self.state = nil
                } else {
                    self.state = .failed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
                        guard let self, self.state == .failed else { return }
                        self.state = nil
                    }
                }
                completion?(success)
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            // The common case, once the rule exists, needs no probe of its
            // own: try the real switch directly. Only a failure (the rule is
            // missing or went stale) pays for a setup round trip, then one retry.
            if TimeZoneSudoers.switchTimeZone(to: identifier) {
                finish(true)
                return
            }
            TimeZoneSudoers.install { ok in
                guard ok else { finish(false); return }
                finish(TimeZoneSudoers.switchTimeZone(to: identifier))
            }
        }
    }
}
