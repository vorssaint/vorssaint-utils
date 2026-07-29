// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A named group of hardware sensors surfaced in the panel. The service reports
/// the group identity, not a display string — the UI localizes it — so the
/// service/SwiftUI boundary stays intact.
enum SensorGroupID: String, CaseIterable, Hashable {
    case cpuPerformance
    case cpuEfficiency
    case graphics
    case battery
    case ssd
    case wifi
    case airflow
}

/// One temperature row: the sensor group and its current reading in °C.
struct TemperatureSensor: Identifiable, Equatable {
    let id: SensorGroupID
    let celsius: Double
}

/// One fan's actual speed. `rpm == 0` is a stopped fan (shown as "Off").
struct FanReading: Identifiable, Equatable {
    let index: Int
    let rpm: Int
    let minRPM: Int
    let maxRPM: Int
    var id: Int { index }
    /// Speed within this fan's own operating range, matching how iStats Menus
    /// reports fan %: a fan idling at its minimum reads ~0%, not (min/max). The
    /// SMC minimum for Apple-silicon fans is well above zero (~2300 RPM), so
    /// dividing by the max alone made an idle fan look ~30% busy.
    var fraction: Double {
        let span = Double(maxRPM - minRPM)
        guard span > 0 else { return 0 }
        return min(1, max(0, Double(rpm - minRPM) / span))
    }
}

/// Turns raw SMC temperature readings into a curated, labeled list.
///
/// Apple Silicon exposes well over a hundred `T*` sensors whose friendly names
/// are a per-chip, hand-maintained database. Rather than invent labels we can't
/// verify, this maps only the sensor families we can identify with confidence
/// (validated against a real M4 Pro dump, see docs/superpowers/hardware-data);
/// any key that matches no group is dropped. Each group collapses to the hottest
/// plausible reading among its keys, the value iStatMenus-style panels show.
enum SensorLabels {
    private struct Group {
        let id: SensorGroupID
        let matches: (String) -> Bool
    }

    /// Prefix rules, in display order. `Tp`/`Te` are the CPU performance/
    /// efficiency die sensors, `Tg` the GPU, `TB` the battery pack, `TH` the
    /// NAND/SSD, `TW` Wi-Fi, `Ta` the enclosure airflow sensors.
    private static let groups: [Group] = [
        Group(id: .cpuPerformance) { $0.hasPrefix("Tp") },
        Group(id: .cpuEfficiency) { $0.hasPrefix("Te") },
        Group(id: .graphics) { $0.hasPrefix("Tg") },
        Group(id: .battery) { $0.hasPrefix("TB") },
        Group(id: .ssd) { $0.hasPrefix("TH") },
        Group(id: .wifi) { $0.hasPrefix("TW") },
        Group(id: .airflow) { $0.hasPrefix("Ta") },
    ]

    /// Plausible on-die/enclosure range; filters out idle-floor placeholders and
    /// the low-voltage `Tp1*`-style keys that are not real temperatures.
    static func isPlausible(_ celsius: Double) -> Bool { celsius > 15 && celsius < 115 }

    static func list(readings: [(key: String, value: Double)]) -> [TemperatureSensor] {
        groups.compactMap { group in
            let values = readings
                .filter { group.matches($0.key) && isPlausible($0.value) }
                .map(\.value)
            guard let peak = values.max() else { return nil }
            return TemperatureSensor(id: group.id, celsius: peak)
        }
    }
}
