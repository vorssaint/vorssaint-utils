// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// Kept apart from FanControlSupport.swift, which the protected helper also
// compiles: resuming is the app's own business, and code the helper never
// runs must not change its binary and force every Mac to register it again.
extension FanControlConfiguration {
    private struct ConfirmedRelease: Codable {
        let releasedConfiguration: FanControlConfiguration
    }

    /// The control kept for a restart or wake. Only a valid manual speed or
    /// curve qualifies: System control has nothing to bring back.
    static func encodeResume(_ configuration: FanControlConfiguration) -> String? {
        guard configuration.mode != .system,
              FanControlPolicy.validConfiguration(configuration) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(ConfirmedRelease(releasedConfiguration: configuration)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodeResume(_ value: String) -> FanControlConfiguration? {
        guard let data = value.data(using: .utf8),
              let configuration = try? JSONDecoder().decode(ConfirmedRelease.self, from: data).releasedConfiguration,
              configuration.mode != .system,
              FanControlPolicy.validConfiguration(configuration) else { return nil }
        return configuration
    }
}

enum FanControlInterruption: Equatable {
    case stopped(FanControlStopReason?)
    case dismissed(FanControlStopReason?)
    case applyFailed
    case resumeFailed

    // Keep the manual-Apply requirement after retiring an acknowledged cause.
    static let acknowledgedStop = "dismissed"
    static let refusedApply = "applyFailed"

    init?(storedStop: String) {
        switch storedStop {
        case Self.acknowledgedStop: return nil
        case Self.refusedApply: self = .applyFailed
        default:
            // Raw reasons from older clients came from the shared helper snapshot.
            let prefix = "local."
            let reason = storedStop.hasPrefix(prefix)
                ? FanControlStopReason(rawValue: String(storedStop.dropFirst(prefix.count))) : nil
            self = .stopped(reason)
        }
    }
}

enum FanControlRequest {
    case read, apply, restore, prepareUnregister, replaceRegistration
}

enum FanControlResumePolicy {
    /// Right after a wake the SMC can refuse a curve for a moment, before the
    /// fans and temperature sensors answer again. A refused resume is tried
    /// again on this schedule, about two minutes in all, before the card
    /// reports that the fans stayed with the system.
    static let retryDelays: [TimeInterval] = [2, 3, 5, 8, 13, 20, 30, 30]

    /// The wait before the next attempt, or nil once every retry is spent.
    static func retryDelay(afterFailures failures: Int) -> TimeInterval? {
        retryDelays.indices.contains(failures) ? retryDelays[failures] : nil
    }

    /// The helper itself hands the fans back under serious thermal pressure,
    /// so a resume waits for it to ease instead of fighting that stop.
    static func defersResume(thermalState: ProcessInfo.ThermalState) -> Bool {
        thermalState == .serious || thermalState == .critical
    }
}
