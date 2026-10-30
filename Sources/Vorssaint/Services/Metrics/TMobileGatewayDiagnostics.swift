// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TMobileSignalQuality: String, Codable, CaseIterable {
    case unknown, poor, fair, good, excellent

    func label(_ strings: TMobileGatewayStrings) -> String {
        switch self {
        case .unknown: return strings.qualityUnavailable
        case .poor: return strings.qualityPoor
        case .fair: return strings.qualityFair
        case .good: return strings.qualityGood
        case .excellent: return strings.qualityExcellent
        }
    }
}

enum TMobileSignalMetric: String, CaseIterable {
    case rsrp, rsrq, rssi, sinr

    var label: String { rawValue.uppercased() }
    var unit: String { self == .rsrp || self == .rssi ? "dBm" : "dB" }
    func explanation(_ strings: TMobileGatewayStrings) -> String {
        switch self {
        case .rsrp: return strings.rsrpExplanation
        case .rsrq: return strings.rsrqExplanation
        case .rssi: return strings.rssiExplanation
        case .sinr: return strings.sinrExplanation
        }
    }
}

/// Placement guidance, not a carrier rating or a predicted speed. Thresholds
/// are approximate app heuristics; keep the gateway's own bars independent.
enum TMobileGatewayDiagnostics {
    static func quality(for value: Double?, metric: TMobileSignalMetric) -> TMobileSignalQuality {
        guard let value, value.isFinite else { return .unknown }
        switch metric {
        case .rsrp:
            guard (-160 ... -20).contains(value) else { return .unknown }
            if value >= -85 { return .excellent }
            if value >= -95 { return .good }
            if value >= -105 { return .fair }
            return .poor
        case .rsrq:
            guard (-50 ... 0).contains(value) else { return .unknown }
            if value >= -7 { return .excellent }
            if value >= -10 { return .good }
            if value >= -15 { return .fair }
            return .poor
        case .sinr:
            guard (-40 ... 80).contains(value) else { return .unknown }
            if value >= 20 { return .excellent }
            if value >= 13 { return .good }
            if value >= 0 { return .fair }
            return .poor
        case .rssi:
            // RSSI includes noise and depends on channel bandwidth. Do not
            // manufacture a standalone quality verdict from total power.
            return .unknown
        }
    }

    static func bandDescription(_ band: String, strings: TMobileGatewayStrings) -> String? {
        switch band.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "n41": return strings.bandN41
        case "n71": return strings.bandN71
        case "n2", "n25": return strings.bandN2
        case "b4", "b66": return strings.bandB66
        case "b5": return strings.bandB5
        case "b12": return strings.bandB12
        case "b71": return strings.bandB71
        default: return nil
        }
    }

    static func tips(for snapshot: TMobileGatewaySnapshot, strings: TMobileGatewayStrings) -> [String] {
        let primary = snapshot.fiveG?.rsrp != nil ? snapshot.fiveG : snapshot.lte ?? snapshot.fiveG
        var result: [String] = []
        if let rsrp = primary?.rsrp, quality(for: rsrp, metric: .rsrp) == .poor {
            result.append(strings.tipWeakSignal)
        }
        if let sinr = primary?.sinr, sinr < 0 {
            result.append(strings.tipInterference)
        } else if let rsrq = primary?.rsrq, rsrq < -15 {
            result.append(strings.tipLowQuality)
        }
        if snapshot.fiveG == nil, snapshot.lte != nil {
            result.append(strings.tipLTEOnly)
        }
        if snapshot.roaming == true {
            result.append(strings.tipRoaming)
        }
        if primary?.bands.contains("n41") == true {
            result.append(strings.tipN41)
        } else if primary?.bands.contains("n71") == true {
            result.append(strings.tipN71)
        }
        result.append(strings.tipEthernet)
        return result
    }

    /// Conventional 20-bit macro-eNB / 8-bit local-cell split only. Other LTE
    /// eNB formats exist: this is an estimate, never a confirmed tower identity.
    /// Do not pass a 5G NCI; its gNB split requires information we do not have.
    static func lteENodeBID(cellID: UInt64?) -> UInt32? {
        guard let cellID, cellID <= 0xFFFFFFF else { return nil }
        return UInt32(cellID >> 8)
    }

    static func lteSectorID(cellID: UInt64?) -> UInt8? {
        guard let cellID, cellID <= 0xFFFFFFF else { return nil }
        return UInt8(cellID & 0xFF)
    }
}
