// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit.ps

/// The battery and charger as the power sounds read them.
struct PowerSoundReading: Equatable {
    var chargePercent: Int?
    var externalConnected: Bool
}

enum PowerSoundSupport {
    /// The mark the island's own low battery notice uses.
    static let lowBatteryPercent = 20

    static let sounds: [AppSound] = [.batteryLow, .chargerConnected, .chargerDisconnected]

    /// The moments between two readings. The first reading is the state at
    /// launch, so it plays nothing.
    static func moments(from before: PowerSoundReading?, to after: PowerSoundReading) -> [AppSound] {
        guard let before else { return [] }
        var moments: [AppSound] = []
        if !before.externalConnected && after.externalConnected { moments.append(.chargerConnected) }
        if before.externalConnected && !after.externalConnected { moments.append(.chargerDisconnected) }
        if !after.externalConnected, let now = after.chargePercent, now <= lowBatteryPercent,
           (before.chargePercent ?? 0) > lowBatteryPercent {
            moments.append(.batteryLow)
        }
        return moments
    }

    /// Whether the watcher needs to listen: one of its sounds is on.
    static func isWanted(hasBattery: Bool, isOn: (AppSound) -> Bool) -> Bool {
        hasBattery && sounds.contains(where: isOn)
    }

    /// A desktop has no battery to run low or charger to plug in.
    static let hasInternalBattery = internalBattery(in: sourceDescriptions()) != nil

    static func reading() -> PowerSoundReading? {
        internalBattery(in: sourceDescriptions()).map(reading(from:))
    }

    static func reading(from description: [String: Any]) -> PowerSoundReading {
        let current = description[kIOPSCurrentCapacityKey] as? Int
        let max = description[kIOPSMaxCapacityKey] as? Int
        let percent = current.flatMap { current in
            max.flatMap { $0 > 0 ? Int((Double(current) / Double($0) * 100).rounded()) : nil }
        }
        return PowerSoundReading(chargePercent: percent,
                                 externalConnected: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
    }

    static func internalBattery(in descriptions: [[String: Any]]) -> [String: Any]? {
        descriptions.first { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }
    }

    private static func sourceDescriptions() -> [[String: Any]] {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        return list.compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
    }
}

/// Plays the battery and charger sounds. It listens to the power sources
/// on its own, so the sounds play with the Dynamic Island off, and only
/// while one of them is switched on.
final class PowerSoundWatcher {
    static let shared = PowerSoundWatcher()

    private var source: CFRunLoopSource?
    private var last: PowerSoundReading?
    private var defaultsObserver: NSObjectProtocol?

    private init() {}

    func start() {
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                  object: nil, queue: .main) { [weak self] _ in
            self?.sync()
        }
        sync()
    }

    private func sync() {
        let wanted = PowerSoundSupport.isWanted(hasBattery: PowerSoundSupport.hasInternalBattery) {
            AppSoundSupport.isOn($0)
        }
        if wanted, source == nil { listen() } else if !wanted, source != nil { stopListening() }
    }

    private func listen() {
        last = PowerSoundSupport.reading()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<PowerSoundWatcher>.fromOpaque(context).takeUnretainedValue().powerChanged()
        }
        guard let created = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?
            .takeRetainedValue() else { return }
        source = created
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
    }

    private func stopListening() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        source = nil
        last = nil
    }

    /// Called on the main run loop.
    private func powerChanged() {
        guard let next = PowerSoundSupport.reading() else { return }
        let moments = PowerSoundSupport.moments(from: last, to: next)
        last = next
        for sound in moments { AppSoundService.shared.play(sound) }
    }
}
