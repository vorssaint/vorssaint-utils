// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ChargeControlIdentifiers {
    static let teamID = "3D485NHW29"
#if VORSSAINT_DEVELOPMENT
    static let appBundleID = "com.vorssaint.utils.dev"
#else
    static let appBundleID = "com.vorssaint.utils"
#endif
    static let helperID = "\(appBundleID).charge-control"
    static let plistName = "\(helperID).plist"
#if VORSSAINT_DEVELOPMENT
    // Local developer builds may use the repository's self-signed identity or
    // ad-hoc signing. The bundle identifiers still isolate the dev pair from
    // production; production keeps the strict Team ID requirement below.
    static let helperCodeRequirement = "identifier \"\(helperID)\""
    static let appCodeRequirement = "identifier \"\(appBundleID)\""
#else
    static let helperCodeRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(helperID)\""
    static let appCodeRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(appBundleID)\""
#endif
}

enum ChargeControlAPI: String, Codable {
    case tahoe, legacy, unavailable
}

enum ChargeControlMode: String, Codable {
    case charging, paused, discharging
}

enum ChargeControlSessionAction: String, Equatable {
    case normal, dischargeToLimit, topUp
}

enum ChargeControlErrorCode: String, Codable {
    case unsupportedHardware, helperUnavailable, controlFailed
}

struct ChargeControlResponse: Codable, Equatable {
    let succeeded: Bool
    let api: ChargeControlAPI
    let mode: ChargeControlMode
    let error: ChargeControlErrorCode?

    static func success(api: ChargeControlAPI, mode: ChargeControlMode) -> Self {
        Self(succeeded: true, api: api, mode: mode, error: nil)
    }

    static func failure(_ error: ChargeControlErrorCode,
                        api: ChargeControlAPI = .unavailable,
                        mode: ChargeControlMode = .charging) -> Self {
        Self(succeeded: false, api: api, mode: mode, error: error)
    }
}

@objc protocol ChargeControlXPCProtocol {
    func status(withReply reply: @escaping (Data) -> Void)
    func allowCharging(withReply reply: @escaping (Data) -> Void)
    func pauseCharging(withReply reply: @escaping (Data) -> Void)
    func startDischarging(withReply reply: @escaping (Data) -> Void)
    func heartbeat(withReply reply: @escaping (Data) -> Void)
    func restoreSystemDefault(withReply reply: @escaping (Data) -> Void)
}

enum ChargeControlIPC {
    static func encode(_ response: ChargeControlResponse) -> Data {
        (try? JSONEncoder().encode(response))
            ?? Data(#"{"succeeded":false,"api":"unavailable","mode":"charging","error":"controlFailed"}"#.utf8)
    }

    static func decode(_ data: Data) -> ChargeControlResponse? {
        try? JSONDecoder().decode(ChargeControlResponse.self, from: data)
    }
}

enum ChargeLimitPolicy {
    static let range = 20...100
    static let defaultLimit = 80
    static let hysteresis = 2

    static func sanitizedLimit(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    static func desiredMode(percent: Int, limit: Int, pluggedIn: Bool,
                            previous: ChargeControlMode) -> ChargeControlMode {
        let limit = sanitizedLimit(limit)
        guard pluggedIn, limit < 100 else { return .charging }
        // Normal enforcement never force-discharges. While paused, wait for
        // the full band before allowing charging again to avoid micro-cycles.
        if previous == .paused, percent > limit - hysteresis { return .paused }
        if percent >= limit { return .paused }
        return .charging
    }

    static func shouldEndDischarge(percent: Int, limit: Int, pluggedIn: Bool,
                                   builtInDisplayOnline: Bool) -> Bool {
        !pluggedIn || !builtInDisplayOnline || percent <= sanitizedLimit(limit)
    }

    static func shouldEndTopUp(percent: Int, pluggedIn: Bool) -> Bool {
        !pluggedIn || percent >= 100
    }

    static func shouldReportSystemConflict(wantsCharging: Bool, isCharging: Bool,
                                           secondsSinceAllow: TimeInterval?) -> Bool {
        guard wantsCharging, !isCharging, let secondsSinceAllow else { return false }
        return secondsSinceAllow >= 20
    }
}
