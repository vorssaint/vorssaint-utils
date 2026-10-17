// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import UserNotifications

enum NotificationPostResult: Equatable {
    case accepted
    case authorizationPending
    case authorizationUnavailable
    case deliveryFailed

    static func authorizationResult(for status: UNAuthorizationStatus) -> Self {
        switch status {
        case .authorized, .provisional:
            return .accepted
        case .notDetermined:
            return .authorizationPending
        case .denied, .ephemeral:
            return .authorizationUnavailable
        @unknown default:
            return .authorizationUnavailable
        }
    }
}

/// Decides when a reading over its limit deserves a notification.
///
/// A single sample proves nothing: a short burst can push the hottest core
/// sensor or the CPU load past the limit and be gone again before the panel
/// is even open. The alert waits for the reading to hold across separate
/// samples, one gate per metric.
struct SustainedAlertGate {
    /// How long the reading has to hold.
    static let sustainedSeconds: TimeInterval = 12

    private var heldSince: TimeInterval?
    private var lastReadingAt: TimeInterval?

    /// `readAt` is when the metric was actually read. The monitor keeps
    /// serving the last reading in between reads, and counting those repeats
    /// would let one burst age into an alert on its own. It comes from the
    /// system uptime clock, which stops while the Mac sleeps, so a sleep in
    /// the middle cannot pass for a long sustained stretch either.
    mutating func shouldAlert(reading: Double?,
                              threshold: Double,
                              readAt: TimeInterval?) -> Bool {
        guard let reading, let readAt, reading >= threshold else {
            reset()
            return false
        }
        guard readAt != lastReadingAt else { return false }
        lastReadingAt = readAt
        guard let since = heldSince else {
            heldSince = readAt
            return false
        }
        return readAt - since >= Self.sustainedSeconds
    }

    mutating func reset() {
        heldSince = nil
        lastReadingAt = nil
    }
}

/// One reminder per known external-power session. Missing battery readings
/// preserve state: they cannot impersonate an unplug or a five-point drop.
struct HighChargeReminderGate {
    private(set) var armed = true
    private(set) var sessionID = UUID()

    mutating func evaluate(enabled: Bool,
                           charge: Int?,
                           hasBattery: Bool,
                           externalConnected: Bool,
                           threshold: Int) -> Int? {
        guard enabled else {
            reset()
            return nil
        }
        guard hasBattery, let charge else { return nil }
        guard externalConnected else {
            reset()
            return nil
        }
        if armed, charge >= threshold {
            armed = false
            return charge
        }
        if !armed, charge <= threshold - 5 {
            reset()
        }
        return nil
    }

    mutating func reset() {
        armed = true
        sessionID = UUID()
    }

    mutating func rearmCurrentSession() {
        armed = true
    }
}

struct HighChargeReminderDeliveryState {
    struct Attempt {
        fileprivate let id = UUID()
        fileprivate let sessionID: UUID
        fileprivate let grantGeneration: UInt64
        let charge: Int
    }

    private(set) var gate = HighChargeReminderGate()
    private var activeAttemptID: UUID?
    private var blockedSessionID: UUID?
    private var observedPermissionGranted: Bool?
    private var grantGeneration: UInt64 = 0

    mutating func begin(enabled: Bool,
                        charge: Int?,
                        hasBattery: Bool,
                        externalConnected: Bool,
                        threshold: Int) -> Attempt? {
        let previousSessionID = gate.sessionID
        let alertCharge = gate.evaluate(enabled: enabled,
                                        charge: charge,
                                        hasBattery: hasBattery,
                                        externalConnected: externalConnected,
                                        threshold: threshold)
        if gate.sessionID != previousSessionID {
            activeAttemptID = nil
            blockedSessionID = nil
        }
        guard blockedSessionID != gate.sessionID else { return nil }
        guard let alertCharge else { return nil }
        let attempt = Attempt(sessionID: gate.sessionID,
                              grantGeneration: grantGeneration,
                              charge: alertCharge)
        activeAttemptID = attempt.id
        return attempt
    }

    /// A result may change only the exact session and attempt it consumed.
    @discardableResult
    mutating func complete(_ attempt: Attempt, result: NotificationPostResult) -> Bool {
        guard activeAttemptID == attempt.id, gate.sessionID == attempt.sessionID else { return false }
        activeAttemptID = nil
        switch result {
        case .accepted:
            blockedSessionID = nil
        case .authorizationPending, .deliveryFailed:
            gate.rearmCurrentSession()
        case .authorizationUnavailable:
            if grantGeneration > attempt.grantGeneration {
                blockedSessionID = nil
                gate.rearmCurrentSession()
            } else {
                blockedSessionID = gate.sessionID
            }
        }
        return true
    }

    /// Only a newly observed grant reopens a session blocked by denial. The
    /// first cached value establishes a baseline, and repeated `.granted`
    /// refreshes do not create retry generations of their own.
    mutating func observePermission(granted: Bool) {
        guard let previous = observedPermissionGranted else {
            observedPermissionGranted = granted
            return
        }
        observedPermissionGranted = granted
        guard granted, !previous else { return }
        grantGeneration &+= 1
        if blockedSessionID == gate.sessionID {
            blockedSessionID = nil
            gate.rearmCurrentSession()
        }
    }

    mutating func reset() {
        activeAttemptID = nil
        blockedSessionID = nil
        gate.reset()
    }
}

/// Owns the production gate → poster → completion operation. Tests inject a
/// controllable poster so completion interleavings exercise this same path.
final class HighChargeReminderDeliveryController {
    private var state = HighChargeReminderDeliveryState()

    var armed: Bool { state.gate.armed }

    func evaluate(enabled: Bool,
                  charge: Int?,
                  hasBattery: Bool,
                  externalConnected: Bool,
                  threshold: Int,
                  post: (Int, @escaping (NotificationPostResult) -> Void) -> Void) {
        guard let attempt = state.begin(enabled: enabled,
                                        charge: charge,
                                        hasBattery: hasBattery,
                                        externalConnected: externalConnected,
                                        threshold: threshold) else { return }
        post(attempt.charge) { [weak self] result in
            self?.state.complete(attempt, result: result)
        }
    }

    func observePermission(granted: Bool) {
        state.observePermission(granted: granted)
    }

    func reset() {
        state.reset()
    }
}

enum HighChargeReminderContent {
    static func real(strings: MonitorAlertFeatureStrings,
                     charge: Int) -> (title: String, body: String) {
        (strings.highChargeTitle, String(format: strings.highChargeBodyFormat, charge))
    }

    static func test(strings: MonitorAlertFeatureStrings) -> (title: String, body: String) {
        (strings.sendTest, strings.highChargeTitle)
    }
}
