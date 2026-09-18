// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The deadline survives preference changes and suspension, so a completed
/// alarm cannot be restarted by a redraw, device change or return from sleep.
final class NotchTimerAlert {
    static let maximumDuration: Duration = .seconds(5 * 60)
    private var task: Task<Void, Never>?
    private var deadline: ContinuousClock.Instant?
    private let interval: Duration
    private let now: () -> ContinuousClock.Instant
    private let sound: () -> Void
    private let stopSound: () -> Void

    convenience init() {
        let tone = NSSound(contentsOfFile: "/System/Library/Sounds/Glass.aiff", byReference: false)
        self.init(sound: {
            if let tone { tone.stop(); tone.play() }
            else { NSSound.beep() }
        }, stopSound: { tone?.stop() })
    }

    init(interval: Duration = .seconds(2), now: @escaping () -> ContinuousClock.Instant = { .now },
         sound: @escaping () -> Void, stopSound: @escaping () -> Void) {
        self.interval = interval
        self.now = now
        self.sound = sound
        self.stopSound = stopSound
    }

    func start(enabled: Bool) {
        let current = now()
        let deadline = self.deadline ?? current.advanced(by: Self.maximumDuration)
        self.deadline = deadline
        guard enabled, current < deadline else { suspend(); return }
        guard task == nil else { return }
        sound()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.delay(until: deadline) else { return }
                do { try await Task.sleep(for: delay, clock: .continuous) }
                catch { return }
                guard !Task.isCancelled, let self else { return }
                guard self.now() < deadline else { self.suspend(); return }
                self.sound()
            }
        }
    }

    func suspend() {
        task?.cancel(); task = nil
        stopSound()
    }

    func stop() {
        suspend()
        deadline = nil
    }

    private func delay(until deadline: ContinuousClock.Instant) -> Duration {
        max(.zero, min(interval, now().duration(to: deadline)))
    }

    deinit { task?.cancel(); stopSound() }
}
