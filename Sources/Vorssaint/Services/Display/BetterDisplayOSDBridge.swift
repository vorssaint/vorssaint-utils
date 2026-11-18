// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Shows brightness that BetterDisplay adjusts in the island, or in the
/// brightness overlay when that is on, so one surface reports every change.
/// It only listens: nothing is sent back to BetterDisplay, and a broadcast
/// is dropped when neither surface would show it.
final class BetterDisplayOSDBridge: NSObject {
    static let shared = BetterDisplayOSDBridge()

    private var observing = false

    func start() {
        guard !observing else { return }
        observing = true
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(receive(_:)), name: BetterDisplayOSD.notificationName, object: nil)
    }

    @objc private func receive(_ notification: Notification) {
        guard let json = notification.object as? String,
              let reading = BetterDisplayOSD.brightness(fromJSON: json) else { return }
        DispatchQueue.main.async {
            if UserDefaults.standard.bool(forKey: DefaultsKey.brightnessOSDEnabled) {
                // Tries the island first, then the overlay on that display.
                BrightnessOSD.show(displayID: reading.displayID ?? CGMainDisplayID(), level: reading.level)
            } else {
                _ = NotchService.shared.showBrightness(reading.level)
            }
        }
    }
}
