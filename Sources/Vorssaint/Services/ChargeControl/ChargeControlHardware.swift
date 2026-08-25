// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os

/// Narrow SMC policy for charge inhibition. The caller can only request the
/// two safe states; key names and payloads never cross the XPC boundary.
final class ChargeControlHardware {
    private let log = Logger(subsystem: ChargeControlIdentifiers.helperID, category: "hardware")
    private struct Command {
        let keys: [SMCClient.Key]
        let allow: [[UInt8]]
        let pause: [[UInt8]]
    }

    let api: ChargeControlAPI
    private let smc: SMCClient
    private let command: Command
    private let supplementalCommand: Command?
    private let dischargeKey: SMCClient.Key
    private let dischargeOn: [UInt8]
    private let dischargeOff: [UInt8]

    init?() {
        guard let smc = SMCClient() else { return nil }
        // CHTE exists on some Apple Silicon models before Tahoe, but on those
        // releases it is not the complete charge-control path. Selecting it by
        // key presence alone can leave CH0B/CH0C inhibited: discharge works,
        // while an "allow charging" command never resumes charging. Only use
        // the Tahoe path on the OS generation that owns those semantics.
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26,
           let key = smc.key(named: "CHTE"), key.dataSize == 4,
           let discharge = smc.key(named: "CHIE"), discharge.dataSize == 1 {
            self.smc = smc
            api = .tahoe
            command = Command(keys: [key],
                              allow: [[0, 0, 0, 0]],
                              pause: [[1, 0, 0, 0]])
            supplementalCommand = nil
            dischargeKey = discharge
            dischargeOn = [8]
            dischargeOff = [0]
            return
        }
        if let first = smc.key(named: "CH0B"), first.dataSize == 1,
           let second = smc.key(named: "CH0C"), second.dataSize == 1 {
            let discharge: (key: SMCClient.Key, on: [UInt8])?
            if let key = smc.key(named: "CHIE"), key.dataSize == 1 {
                // M4 machines on pre-Tahoe macOS use the legacy inhibit pair,
                // but expose the newer discharge switch.
                discharge = (key, [8])
            } else if let key = smc.key(named: "CH0I"), key.dataSize == 1 {
                discharge = (key, [1])
            } else {
                discharge = nil
            }
            guard let discharge else { return nil }
            self.smc = smc
            api = .legacy
            command = Command(keys: [first, second], allow: [[0], [0]], pause: [[2], [2]])
            if let key = smc.key(named: "CHTE"), key.dataSize == 4 {
                supplementalCommand = Command(keys: [key],
                                               allow: [[0, 0, 0, 0]],
                                               pause: [[1, 0, 0, 0]])
            } else {
                supplementalCommand = nil
            }
            dischargeKey = discharge.key
            dischargeOn = discharge.on
            dischargeOff = [0]
            return
        }
        return nil
    }

    func set(_ mode: ChargeControlMode) throws {
        let commands: [Command]
        if let supplementalCommand {
            // M4 on pre-Tahoe macOS exposes both generations. Keeping both
            // inhibit flags in sync prevents either path from retaining a
            // stale pause after a discharge or another battery utility.
            commands = [command, supplementalCommand]
        } else {
            commands = [command]
        }
        for attempt in 0..<3 {
            do {
                for item in commands {
                    let payloads = mode == .charging ? item.allow : item.pause
                    for (key, payload) in zip(item.keys, payloads) {
                        try smc.writeBytes(payload, to: key)
                    }
                }
                try smc.writeBytes(mode == .discharging ? dischargeOn : dischargeOff,
                                   to: dischargeKey)
                let commandChecks = commands.flatMap { item -> [(String, [UInt8], [UInt8]?)] in
                    let payloads = mode == .charging ? item.allow : item.pause
                    return zip(item.keys, payloads).map { ($0.0.name, $0.1, smc.readBytes($0.0)) }
                }
                let dischargeExpected = mode == .discharging ? dischargeOn : dischargeOff
                let dischargeActual = smc.readBytes(dischargeKey)
                if commandChecks.allSatisfy({ check in
                    guard let actual = check.2 else { return false }
                    if actual == check.1 { return true }
                    // M4 reports CH0B/CH0C as 3 while forced discharge is
                    // active: the requested pause bit (2) plus a controller-
                    // owned discharge status bit (1). Verify that our bit is
                    // present without rejecting the additional hardware bit.
                    return mode == .discharging
                        && (check.0 == "CH0B" || check.0 == "CH0C")
                        && check.1.count == 1 && actual.count == 1
                        && (actual[0] & check.1[0]) == check.1[0]
                })
                    && dischargeActual == dischargeExpected {
                    log.notice("applied mode=\(mode.rawValue, privacy: .public) api=\(self.api.rawValue, privacy: .public)")
                    return
                }
                let inhibitDetails = commandChecks.map { check in
                    let expected = String(describing: check.1)
                    let actual = check.2.map { String(describing: $0) } ?? "nil"
                    return "\(check.0):\(expected)->\(actual)"
                }.joined(separator: ",")
                let dischargeExpectedText = String(describing: dischargeExpected)
                let dischargeActualText = dischargeActual.map { String(describing: $0) } ?? "nil"
                log.error("verify failed mode=\(mode.rawValue, privacy: .public) attempt=\(attempt, privacy: .public) inhibit=\(inhibitDetails, privacy: .public) discharge=\(self.dischargeKey.name, privacy: .public):\(dischargeExpectedText, privacy: .public)->\(dischargeActualText, privacy: .public)")
            } catch where attempt == 2 {
                log.error("write failed mode=\(mode.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)")
                throw error
            } catch {
                log.error("write retry mode=\(mode.rawValue, privacy: .public) attempt=\(attempt, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        }
        throw ChargeControlErrorCode.controlFailed
    }
}

extension ChargeControlErrorCode: Error {}
