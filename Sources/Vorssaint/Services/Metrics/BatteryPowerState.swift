// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

extension BatteryPowerState {
    func apply(to reading: inout PowerReading) {
        let resolved = resolve(externalConnected: reading.externalConnected, isCharging: reading.isCharging)
        reading.externalConnected = resolved.externalConnected
        reading.isCharging = resolved.isCharging
        if reading.externalConnected || reading.isCharging {
            reading.timeRemainingSeconds = nil
        }
    }
}

/// Only a few read-only SMC flags are polled at 4 Hz, off the main thread.
/// No gate writes, full battery samples, or UI publishes occur on unchanged ticks.
final class BatteryPowerStateMonitor: ObservableObject {
    static let shared = BatteryPowerStateMonitor()
    @Published private(set) var state = BatteryPowerState()

    private let queue = DispatchQueue(label: "com.vorssaint.battery-state", qos: .userInitiated)
    private var timer: DispatchSourceTimer?

    private init() {
        guard PowerSampler.hasInternalBattery else { return }
        queue.async { [weak self] in
            guard let self, let smc = SMCClient() else { return }
            let adapterKey = smc.key(named: "AC-W").flatMap { $0.dataSize == 1 && $0.dataType == "si8 " ? $0 : nil }
            let chargingKey = smc.key(named: "CHSC").flatMap { $0.dataSize == 1 && $0.dataType == "ui8 " ? $0 : nil }
            let dischargeKey = smc.key(named: "CHIE") ?? smc.key(named: "CH0I")
            guard adapterKey != nil || chargingKey != nil else { return }
            var previous: BatteryPowerState?
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(25))
            timer.setEventHandler { [weak self] in
                let current = BatteryPowerState(
                    adapterConnected: BatteryPowerState.adapterConnected(bytes: adapterKey.flatMap(smc.readBytes)),
                    isCharging: BatteryPowerState.flag(bytes: chargingKey.flatMap(smc.readBytes)),
                    isDischarging: BatteryPowerState.flag(bytes: dischargeKey.flatMap(smc.readBytes),
                                                         enabledValue: dischargeKey?.name == "CHIE" ? 0x08 : 1))
                guard current != previous else { return }
                previous = current
                DispatchQueue.main.async { self?.state = current }
            }
            self.timer = timer
            timer.resume()
        }
    }

    deinit { timer?.cancel() }
}
