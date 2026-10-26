// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Main-thread lifecycle and UI state; potentially blocking sensor reads run
/// serially off main. Disabled features own neither timers nor sensor clients.
final class AmbientLightService: ObservableObject {
    static let shared = AmbientLightService()

    enum Status { case disabled, waiting, monitoring, unavailable, appearanceUnavailable, paused }
    @Published private(set) var status: Status = .disabled
    @Published private(set) var lux: Double?

    private let queue = DispatchQueue(label: "com.vorssaint.utils.ambient-light", qos: .utility)
    private let sensor = AmbientLightSensor()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var gate = AmbientLightGate()
    private var threshold = AmbientLightSupport.defaultThreshold
    private var defaultAppearance = AmbientLightAppearance.dark
    private var generation = 0
    private var reading = false
    private var sleeping = false

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        guard AppFeature.ambientLight.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.ambientLightEnabled) else {
            stop()
            return
        }
        let next = AmbientLightSupport.sanitizedThreshold(
            UserDefaults.standard.double(forKey: DefaultsKey.ambientLightThreshold))
        let nextAppearance = AmbientLightAppearance.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.ambientLightDefaultAppearance))
        if next != threshold || nextAppearance != defaultAppearance {
            threshold = next
            defaultAppearance = nextAppearance
            gate = AmbientLightGate()
            // A read begun with the old configuration must never trigger an action.
            generation += 1
            reading = false
        }
        if observers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            observers = [
                center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                    self?.sleeping = true
                    self?.pause()
                },
                center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                    self?.sleeping = false
                    self?.syncWithPreferences()
                },
            ]
        }
        guard !sleeping, SessionActivity.shared.isActive else {
            pause()
            return
        }
        guard timer == nil else { return }
        status = .waiting
        let timer = Timer(timeInterval: AmbientLightSupport.sampleInterval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        timer.tolerance = 0.4
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        sample()
    }

    private func pause() {
        timer?.invalidate()
        timer = nil
        generation += 1
        reading = false
        gate = AmbientLightGate()
        lux = nil
        status = .paused
        queue.async { [sensor] in sensor.close() }
    }

    func stop() {
        pause()
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers = []
        sleeping = false
        status = .disabled
    }

    private func sample() {
        guard !reading, timer != nil else { return }
        reading = true
        let token = generation
        queue.async { [weak self, sensor] in
            let value = sensor.readLux()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token, self.timer != nil else { return }
                self.reading = false
                // Recheck persisted settings too: a backup import can disable
                // the feature while a sensor read is in flight.
                guard AppFeature.ambientLight.isAvailable,
                      UserDefaults.standard.bool(forKey: DefaultsKey.ambientLightEnabled),
                      SessionActivity.shared.isActive else {
                    self.syncWithPreferences()
                    return
                }
                let currentThreshold = AmbientLightSupport.sanitizedThreshold(
                    UserDefaults.standard.double(forKey: DefaultsKey.ambientLightThreshold))
                let currentAppearance = AmbientLightAppearance.sanitized(
                    UserDefaults.standard.string(forKey: DefaultsKey.ambientLightDefaultAppearance))
                guard currentThreshold == self.threshold, currentAppearance == self.defaultAppearance else {
                    self.syncWithPreferences()
                    return
                }
                self.lux = value
                let target = self.gate.observe(lux: value, threshold: self.threshold,
                                               defaultAppearance: self.defaultAppearance,
                                               now: ProcessInfo.processInfo.systemUptime)
                guard value != nil else {
                    self.status = .unavailable
                    self.timer?.fireDate = Date(timeIntervalSinceNow: 30)
                    return
                }
                guard SystemAppearance.isDark != nil else { self.status = .appearanceUnavailable; return }
                if let target {
                    self.status = SystemAppearance.setDark(target == .dark) ? .monitoring : .appearanceUnavailable
                } else if self.status != .appearanceUnavailable {
                    self.status = .monitoring
                }
            }
        }
    }
}
