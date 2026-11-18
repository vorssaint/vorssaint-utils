// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// Kept apart from FanControlSupport.swift, which the protected helper also
// compiles: resuming is the app's own business, and code the helper never
// runs must not change its binary and force every Mac to register it again.
extension FanControlConfiguration {
    /// The control kept for a restart or wake. Only a valid manual speed or
    /// curve qualifies: System control has nothing to bring back.
    static func encodeResume(_ configuration: FanControlConfiguration) -> String? {
        guard configuration.mode != .system,
              FanControlPolicy.validConfiguration(configuration) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(configuration) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodeResume(_ value: String) -> FanControlConfiguration? {
        guard let data = value.data(using: .utf8),
              let configuration = try? JSONDecoder().decode(FanControlConfiguration.self, from: data),
              configuration.mode != .system,
              FanControlPolicy.validConfiguration(configuration) else { return nil }
        return configuration
    }
}

/// What the app does after the helper hands the fans back on its own. The
/// helper never restarts a session it stopped, by design, so without this a
/// single safety stop in the middle of a game left the fans with the system
/// until the next wake or app launch.
enum FanControlReapplyPolicy {
    /// Waits before each consecutive attempt. Running out leaves the fans
    /// with the system: a stop that keeps coming back is not transient.
    static let delays: [TimeInterval] = [5, 15, 30, 60, 120]
    /// Control that held this long counts as healthy, and the next stop
    /// starts again from the first wait.
    static let settledAfter: TimeInterval = 300
    /// How often a re-apply held back by thermal pressure looks again.
    static let thermalRecheck: TimeInterval = 15

    /// Stops the helper decides alone while the app still wants control. A
    /// time limit, a closed app and the cleanup after a crash are final.
    static func isTransientStop(_ reason: FanControlStopReason?) -> Bool {
        switch reason {
        case .hardwareChanged, .temperatureUnavailable, .thermalPressure, .heartbeatLost:
            return true
        case .timeLimit, .appDisconnected, .recovery, .none:
            return false
        }
    }

    static func delay(attempt: Int) -> TimeInterval? {
        delays.indices.contains(attempt) ? delays[attempt] : nil
    }

    /// The attempt count to continue from when control stops again.
    static func attempt(after previous: Int, heldFor: TimeInterval?) -> Int {
        guard let heldFor, heldFor >= settledAfter else { return previous }
        return 0
    }

    /// The helper drops control under serious thermal pressure, so asking
    /// again before it clears would only start and stop the fans.
    static func thermalStateAllows(_ state: ProcessInfo.ThermalState) -> Bool {
        state == .nominal || state == .fair
    }
}
