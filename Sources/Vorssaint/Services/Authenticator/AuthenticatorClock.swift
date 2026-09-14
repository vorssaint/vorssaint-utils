// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The second hand every view showing a code reads, kept apart from
/// `AuthenticatorService` on purpose. A page that observes the service
/// would rebuild whole every second, list, toggles and row menus included,
/// which is what made the settings list feel heavy; observing this instead
/// redraws the codes and nothing else. One clock also means every visible
/// code turns over in the same frame.
final class AuthenticatorClock: ObservableObject {
    static let shared = AuthenticatorClock()

    @Published private(set) var now = Date()

    private var timer: Timer?
    private var subscribers = 0
    private var paused = false

    private init() {}

    /// Views call this in pairs from `onAppear` and `onDisappear`; the
    /// timer only runs while at least one is on screen.
    func begin() {
        subscribers += 1
        // A drag that ended with the page going away leaves the flag set,
        // and a paused clock never starts again. Arriving is always a fresh
        // start.
        paused = false
        now = Date()
        start()
    }

    func end() {
        subscribers = max(subscribers - 1, 0)
        if subscribers == 0 { stop() }
    }

    /// Holds the tick while a drag is in flight. A reorder animation and a
    /// redraw of every row in the same frame is what makes rows stutter,
    /// and a code that is one second stale during a drag is nobody's
    /// problem.
    func pause() {
        guard !paused else { return }
        paused = true
        stop()
    }

    func resume() {
        guard paused else { return }
        paused = false
        now = Date()
        start()
    }

    private func start() {
        guard timer == nil, subscribers > 0, !paused else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }
}
