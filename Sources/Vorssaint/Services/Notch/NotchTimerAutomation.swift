// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

@MainActor
final class NotchTimerAutomation {
    static let shared = NotchTimerAutomation()
    private var isReady = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    // Shortcuts can launch the app in the background before its timer is ready.
    func waitForStartup() async {
        guard !isReady else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finishLaunching() {
        isReady = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
