// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads the battery temperature sensors for the Keep Awake thermal guard.
///
/// SystemMonitor samples the same keys only while something asks it to — an
/// open panel, a menu bar item or an alert — and never while the Monitor is
/// switched off in the hub. The guard has to keep reading in exactly those
/// conditions, so it holds its own SMC connection.
final class BatteryTemperatureSampler {
    /// Probed once: enumerating SMC keys walks the whole key table, far too
    /// slow for a watchdog tick or a Settings redraw.
    static let isSupported: Bool = BatteryTemperatureSampler().read() != nil

    private let smc: SMCClient?
    private let keys: [SMCClient.Key]

    init() {
        let client = SMCClient()
        smc = client
        keys = client?.keys(where: TemperatureSensorSelector.isBatteryTemperatureKey) ?? []
    }

    /// Hottest battery reading in °C, or nil when no sensor answers.
    func read() -> Double? {
        guard let smc, !keys.isEmpty else { return nil }
        return TemperatureSensorSelector.hottestPlausibleReading(keys.map { smc.readValue($0) })
    }
}
