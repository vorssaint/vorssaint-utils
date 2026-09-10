// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ChargeControlFamily: String, Codable, Equatable, Sendable {
    case appleSiliconCH0
    case appleSiliconCHT
    case intelBCLM
    case nativePowerUI
}

enum ChargeControlGate: String, Codable, Equatable, Sendable {
    case allowCharging
    case inhibitCharging
    case forceDischarge
}

enum ChargeCalibrationPhase: String, Codable, Equatable, Sendable {
    case chargingToFull
    case dischargingToFloor
    case chargingToFullAgain
    case holdingAtFull
    case restoringLimit
}

struct ChargeCalibrationState: Codable, Equatable, Sendable {
    var phase: ChargeCalibrationPhase
    var holdStartedAt: Date?
    var savedLimit: Int
}

enum ChargeControlMode: Equatable, Sendable {
    case limit
    case dischargeToLimit
    case topUp
    case calibration(ChargeCalibrationState)
}

struct ChargeControlHardwareProfile: Codable, Equatable, Sendable {
    var family: ChargeControlFamily
    var supportsInhibit: Bool
    var supportsDischarge: Bool

    static let empty = ChargeControlHardwareProfile(family: .appleSiliconCH0,
                                                    supportsInhibit: false,
                                                    supportsDischarge: false)
}

struct ChargeControlSnapshot: Codable, Equatable, Sendable {
    var gate: ChargeControlGate
    var profile: ChargeControlHardwareProfile?
    var isDischarging: Bool

    static let idle = ChargeControlSnapshot(gate: .allowCharging,
                                            profile: nil,
                                            isDischarging: false)
}

enum ChargeControlErrorCode: String, Codable, Equatable, Error, Sendable {
    case noBattery
    case unsupportedHardware
    case authorizationRequired
    case helperUnavailable
    case controlFailed
}

struct ChargeControlRequest: Codable, Equatable, Sendable {
    var gate: ChargeControlGate
    var limitPercent: Int
}

struct ChargeControlResponse: Codable, Equatable, Sendable {
    let succeeded: Bool
    let snapshot: ChargeControlSnapshot
    let error: ChargeControlErrorCode?

    static func success(_ snapshot: ChargeControlSnapshot) -> ChargeControlResponse {
        ChargeControlResponse(succeeded: true, snapshot: snapshot, error: nil)
    }

    static func failure(_ error: ChargeControlErrorCode,
                        snapshot: ChargeControlSnapshot = .idle) -> ChargeControlResponse {
        ChargeControlResponse(succeeded: false, snapshot: snapshot, error: error)
    }
}

enum ChargeLimitBarSupport {
    static let segmentCount = 20

    static func clampedPercent(_ percent: Int) -> Int {
        min(100, max(0, percent))
    }

    static func filledSegmentCount(for percent: Int) -> Int {
        let percent = clampedPercent(percent)
        return percent == 0 ? 0 : (percent + 4) / 5
    }

    static func targetFraction(for percent: Int) -> Double {
        Double(clampedPercent(percent)) / 100
    }

    static func isAboveLimit(segment index: Int, limit: Int) -> Bool {
        (index + 1) * 5 > clampedPercent(limit)
    }
}

struct ChargeControlEvaluationCoalescer {
    private var pending = false

    mutating func deferIfBusy(_ isBusy: Bool) -> Bool {
        guard isBusy else { return false }
        pending = true
        return true
    }

    mutating func consumePending() -> Bool {
        defer { pending = false }
        return pending
    }
}

enum ChargeControlPolicy {
    static let minimumLimit = 20
    static let maximumLimit = 100
    static let defaultLimit = 80
    static let minimumSailingBoundary = 10
    static let minimumSailingRange = 1
    static let defaultSailingRange = 5
    static let hysteresis = 2
    static let calibrationFloor = 10
    static let calibrationFull = 100
    static let calibrationHold: TimeInterval = 60 * 60
    static let pollInterval: TimeInterval = 2
    static let postGateRefreshDelays: [TimeInterval] = [0.25, 0.75, 1.5]
    static let heartbeatLimit: TimeInterval = 7
    static let intelDischargeBCLM = 10

    static func sanitizedLimit(_ percent: Int) -> Int {
        (minimumLimit...maximumLimit).contains(percent) ? percent : defaultLimit
    }

    static func maximumSailingRange(limit: Int) -> Int {
        let cap = sanitizedLimit(limit)
        return max(minimumSailingRange, cap - minimumSailingBoundary)
    }

    static func sanitizedSailingRange(_ percent: Int, limit: Int) -> Int {
        min(max(percent, minimumSailingRange), maximumSailingRange(limit: limit))
    }

    static func desiredGate(chargePercent: Int,
                            limit: Int,
                            sailingRange: Int? = nil,
                            wasInhibited: Bool,
                            mode: ChargeControlMode,
                            family: ChargeControlFamily?,
                            externalConnected: Bool = true) -> ChargeControlGate {
        guard externalConnected else { return .allowCharging }
        let cap = sanitizedLimit(limit)
        switch mode {
        case .calibration(let state):
            return calibrationGate(chargePercent: chargePercent, state: state)
        case .dischargeToLimit:
            // Manual battery-power override; the legacy case name is retained
            // for compatibility. Only Stop (not the saved cap) ends this mode.
            return .forceDischarge
        case .topUp:
            return .allowCharging
        case .limit:
            break
        }

        guard cap < maximumLimit else { return .allowCharging }

        if family == .intelBCLM, sailingRange == nil {
            return .inhibitCharging
        }

        if chargePercent >= cap { return .inhibitCharging }
        if let sailingRange {
            let resumeBelow = cap - sanitizedSailingRange(sailingRange, limit: cap)
            if wasInhibited && chargePercent > resumeBelow { return .inhibitCharging }
        } else if wasInhibited && chargePercent > cap - hysteresis {
            return .inhibitCharging
        }
        return .allowCharging
    }

    static func startCalibration(chargePercent: Int, savedLimit: Int) -> ChargeCalibrationState {
        let cap = sanitizedLimit(savedLimit)
        if chargePercent >= calibrationFull {
            return ChargeCalibrationState(phase: .dischargingToFloor,
                                          holdStartedAt: nil,
                                          savedLimit: cap)
        }
        return ChargeCalibrationState(phase: .chargingToFull,
                                      holdStartedAt: nil,
                                      savedLimit: cap)
    }

    static func advanceCalibration(_ state: ChargeCalibrationState,
                                   chargePercent: Int,
                                   now: Date,
                                   holdDuration: TimeInterval = calibrationHold) -> ChargeCalibrationState? {
        switch state.phase {
        case .chargingToFull:
            guard chargePercent >= calibrationFull else { return state }
            return ChargeCalibrationState(phase: .dischargingToFloor,
                                          holdStartedAt: nil,
                                          savedLimit: state.savedLimit)
        case .dischargingToFloor:
            guard chargePercent <= calibrationFloor else { return state }
            return ChargeCalibrationState(phase: .chargingToFullAgain,
                                          holdStartedAt: nil,
                                          savedLimit: state.savedLimit)
        case .chargingToFullAgain:
            guard chargePercent >= calibrationFull else { return state }
            return ChargeCalibrationState(phase: .holdingAtFull,
                                          holdStartedAt: now,
                                          savedLimit: state.savedLimit)
        case .holdingAtFull:
            let started = state.holdStartedAt ?? now
            if state.holdStartedAt == nil {
                return ChargeCalibrationState(phase: .holdingAtFull,
                                              holdStartedAt: now,
                                              savedLimit: state.savedLimit)
            }
            guard now.timeIntervalSince(started) >= holdDuration else {
                return ChargeCalibrationState(phase: .holdingAtFull,
                                              holdStartedAt: started,
                                              savedLimit: state.savedLimit)
            }
            return ChargeCalibrationState(phase: .restoringLimit,
                                          holdStartedAt: nil,
                                          savedLimit: state.savedLimit)
        case .restoringLimit:
            return chargePercent <= state.savedLimit ? nil : state
        }
    }

    static func holdRemaining(state: ChargeCalibrationState,
                              now: Date,
                              holdDuration: TimeInterval = calibrationHold) -> TimeInterval? {
        guard state.phase == .holdingAtFull, let started = state.holdStartedAt else { return nil }
        return max(0, holdDuration - now.timeIntervalSince(started))
    }

    static func restoreReason(hasActiveGate: Bool,
                              heartbeatAge: TimeInterval) -> Bool {
        hasActiveGate && heartbeatAge > heartbeatLimit
    }

    /// Fit a write to the key's reported size. M-series firmware uses 1-byte
    /// CH0C or 4-byte CHTE for the same inhibit bit.
    static func paddedSMCBytes(_ bytes: [UInt8], to size: UInt32) -> [UInt8] {
        let count = Int(size)
        guard count > 0 else { return [] }
        if bytes.count == count { return bytes }
        if bytes.count > count { return Array(bytes.prefix(count)) }
        return bytes + Array(repeating: 0, count: count - bytes.count)
    }

    private static func calibrationGate(chargePercent: Int,
                                        state: ChargeCalibrationState) -> ChargeControlGate {
        switch state.phase {
        case .chargingToFull, .chargingToFullAgain, .holdingAtFull:
            return .allowCharging
        case .dischargingToFloor:
            return .forceDischarge
        case .restoringLimit:
            return chargePercent > state.savedLimit ? .forceDischarge : .inhibitCharging
        }
    }
}
