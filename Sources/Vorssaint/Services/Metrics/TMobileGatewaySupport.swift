// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreFoundation
import Foundation

enum TMobileGatewayFailure: Error, Equatable {
    case invalidAddress, authenticationRequired, unavailable, invalidResponse
}

enum TMobileGatewayPhase: Equatable {
    case idle, loading, ready
    case failed(TMobileGatewayFailure)
}

struct TMobileRadioSignal: Equatable {
    let bars: Int?
    let bands: [String]
    let rsrp: Double?
    let rsrq: Double?
    let rssi: Double?
    let sinr: Double?
    let cellID: UInt64?
    let antenna: String?
    let bandwidthMHz: Double?
    let channel: Int?
    let physicalCellID: Int?
    let trackingAreaCode: UInt32?
    let cqi: Int?
    let gNodeBID: UInt32?
    let eNodeBID: UInt32?
    let ecgi: String?
    let supportedBands: [String]?

    init(bars: Int?, bands: [String], rsrp: Double?, rsrq: Double?, rssi: Double?, sinr: Double?,
         cellID: UInt64? = nil, antenna: String? = nil, bandwidthMHz: Double? = nil,
         channel: Int? = nil, physicalCellID: Int? = nil, trackingAreaCode: UInt32? = nil,
         cqi: Int? = nil, gNodeBID: UInt32? = nil, eNodeBID: UInt32? = nil,
         ecgi: String? = nil, supportedBands: [String]? = nil) {
        self.bars = bars; self.bands = bands; self.rsrp = rsrp; self.rsrq = rsrq
        self.rssi = rssi; self.sinr = sinr; self.cellID = cellID; self.antenna = antenna
        self.bandwidthMHz = bandwidthMHz; self.channel = channel; self.physicalCellID = physicalCellID
        self.trackingAreaCode = trackingAreaCode; self.cqi = cqi; self.gNodeBID = gNodeBID
        self.eNodeBID = eNodeBID; self.ecgi = ecgi; self.supportedBands = supportedBands
    }
}

struct TMobileGatewaySnapshot: Equatable {
    let model: String?
    let firmware: String?
    let uptime: TimeInterval?
    let registration: String?
    let roaming: Bool?
    let lte: TMobileRadioSignal?
    let fiveG: TMobileRadioSignal?
    let apn: String?

    init(model: String?, firmware: String?, uptime: TimeInterval?, registration: String?, roaming: Bool?,
         lte: TMobileRadioSignal?, fiveG: TMobileRadioSignal?, apn: String? = nil) {
        self.model = model; self.firmware = firmware; self.uptime = uptime
        self.registration = registration; self.roaming = roaming
        self.lte = lte; self.fiveG = fiveG; self.apn = apn
    }

    var primaryRadioLabel: String? {
        if fiveG?.rsrp != nil { return "5G" }
        if lte != nil { return "LTE" }
        return fiveG == nil ? nil : "5G"
    }
}

/// Only allowlisted radio/status fields cross this boundary. Optional cell
/// details are retained only when returned by the same public status request;
/// their absence never triggers an authenticated telemetry request.
/// Credentials, client identifiers, SIM information and GPS are never retained.
enum TMobileGatewaySupport {
    static func privateLANBaseURL(_ input: String) -> URL? {
        let scheme: String
        if input.hasPrefix("http://") { scheme = "http" }
        else if input.hasPrefix("https://") { scheme = "https" }
        else { return nil }

        var authority = String(input.dropFirst(scheme.count + 3))
        if authority.hasSuffix("/") { authority.removeLast() }
        let parts = authority.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let host = String(parts[0])
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return nil }
        var numbers: [Int] = []
        for octet in octets {
            guard !octet.isEmpty, octet.utf8.allSatisfy({ (48...57).contains($0) }),
                  octet.count == 1 || octet.first != "0",
                  let value = Int(octet), (0...255).contains(value) else { return nil }
            numbers.append(value)
        }
        let isPrivate = numbers[0] == 10
            || (numbers[0] == 172 && (16...31).contains(numbers[1]))
            || (numbers[0] == 192 && numbers[1] == 168)
        guard isPrivate else { return nil }

        if parts.count == 2 {
            let port = parts[1]
            guard !port.isEmpty, port.utf8.allSatisfy({ (48...57).contains($0) }),
                  port.first != "0", let number = Int(port), (1...65535).contains(number)
            else { return nil }
        }
        // Rebuilding from validated ASCII components prevents URL parser repair,
        // percent escaping, userinfo and alternate IPv4 spellings from slipping in.
        return URL(string: "\(scheme)://\(authority)")
    }

    static func parse(_ data: Data) throws -> TMobileGatewaySnapshot {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              ["device", "time", "signal"].contains(where: { root[$0] is [String: Any] })
        else { throw TMobileGatewayFailure.invalidResponse }
        let device = root["device"] as? [String: Any] ?? [:]
        let time = root["time"] as? [String: Any] ?? [:]
        let signal = root["signal"] as? [String: Any] ?? [:]
        let generic = signal["generic"] as? [String: Any] ?? [:]
        let uptime = number(time["upTime"])
        return TMobileGatewaySnapshot(
            model: text(device["model"]) ?? text(device["friendlyName"]),
            firmware: text(device["softwareVersion"]),
            uptime: uptime.flatMap { $0 >= 0 ? $0 : nil },
            registration: text(generic["registration"]),
            roaming: boolean(generic["roaming"]),
            lte: radio(signal["4g"], isFiveG: false), fiveG: radio(signal["5g"], isFiveG: true),
            apn: text(generic["apn"]))
    }

    static func pollingDelay(errorStreak: Int) -> TimeInterval {
        errorStreak <= 0 ? 15 : min(15 * pow(2, Double(min(errorStreak, 3))), 120)
    }

    private static func radio(_ value: Any?, isFiveG: Bool) -> TMobileRadioSignal? {
        guard let object = value as? [String: Any] else { return nil }
        let sector = object["sector"] as? [String: Any] ?? [:]
        let barValue = number(object["bars"])
        let bars = barValue.flatMap { (0...5).contains($0) ? Int($0.rounded()) : nil }
        let rawBands = (object["bands"] as? [Any]) ?? object["bands"].map { [$0] } ?? []
        var bands: [String] = []
        for value in rawBands.prefix(32) {
            guard let candidate = band(value, isFiveG: isFiveG), !bands.contains(candidate) else { continue }
            bands.append(candidate)
        }
        // Deliberately broad LTE/NR sanity limits reject sentinels such as
        // zero RSRP and 99 SINR without treating a weak but real link as absent.
        let rsrp = measurement(object["rsrp"], range: -160 ... -20)
        let rsrq = measurement(object["rsrq"], range: -50 ... 0)
        let rssi = measurement(object["rssi"], range: -160 ... 0)
        let sinr = measurement(object["sinr"], range: -40 ... 80)
        let cellID = integer(object["cid"] ?? sector["cid"], maximum: isFiveG ? 0xFFFFFFFFF : 0xFFFFFFF)
        let antenna: String?
        switch text(object["antennaUsed"])?.lowercased() {
        case "internal": antenna = "Internal"
        case "external": antenna = "External"
        default: antenna = nil
        }
        let bandwidth = bandwidth(object["bandwidth"])
        let channel = integer(object["earfcn"] ?? object["arfcn"] ?? object["nrarfcn"],
                              maximum: isFiveG ? 3_279_165 : 262_143).map(Int.init)
        let pci = integer(object["pci"], maximum: isFiveG ? 1007 : 503).map(Int.init)
        let tac = integer(object["tac"], maximum: isFiveG ? 0xFFFFFF : 0xFFFF).map(UInt32.init)
        let cqi = integer(object["cqi"], maximum: 30).map(Int.init)
        let gNodeBID: UInt32? = isFiveG
            ? integer(object["gNBID"] ?? sector["gNBID"], maximum: UInt64(UInt32.max)).map { UInt32($0) } : nil
        let eNodeBValue: Any? = object["eNBID"] ?? object["eNodeBID"] ?? sector["eNBID"]
        let eNodeBID: UInt32? = !isFiveG
            ? integer(eNodeBValue, maximum: 0xFFFFFFF).map { UInt32($0) } : nil
        let ecgi = cellGlobalIdentity(object["ecgi"] ?? object["ECGI"])
        var supportedBands: [String] = []
        for value in ((object["supportedBands"] as? [Any]) ?? []).prefix(32) {
            if let band = band(value, isFiveG: isFiveG), !supportedBands.contains(band) { supportedBands.append(band) }
        }
        guard bars != nil || !bands.isEmpty || rsrp != nil || rsrq != nil || rssi != nil || sinr != nil
            || cellID != nil || antenna != nil || bandwidth != nil || channel != nil || pci != nil
            || tac != nil || cqi != nil || gNodeBID != nil || eNodeBID != nil || ecgi != nil || !supportedBands.isEmpty
        else { return nil }
        return TMobileRadioSignal(bars: bars, bands: bands, rsrp: rsrp, rsrq: rsrq, rssi: rssi, sinr: sinr,
                                  cellID: cellID, antenna: antenna, bandwidthMHz: bandwidth, channel: channel,
                                  physicalCellID: pci, trackingAreaCode: tac, cqi: cqi, gNodeBID: gNodeBID,
                                  eNodeBID: eNodeBID, ecgi: ecgi, supportedBands: supportedBands.isEmpty ? nil : supportedBands)
    }

    /// Preserve a returned identity for display/exact local reference matching.
    /// No bit masking, PLMN split or geographic inference is applied.
    private static func cellGlobalIdentity(_ value: Any?) -> String? {
        let candidate: String?
        if value is String { candidate = text(value) }
        else { candidate = integer(value, maximum: UInt64.max).map(String.init) }
        guard let candidate, !candidate.isEmpty, candidate.utf8.count <= 64,
              candidate.utf8.contains(where: { (48...57).contains($0) }) else { return nil }
        let digits = candidate.lowercased().hasPrefix("0x") ? candidate.dropFirst(2) : candidate[...]
        let components = digits.split(whereSeparator: { $0 == "-" || $0 == ":" })
        guard !digits.isEmpty, digits.first != "-", digits.first != ":", digits.last != "-", digits.last != ":",
              !digits.contains("--"), !digits.contains("::"), !digits.contains("-:"), !digits.contains(":-"),
              components.contains(where: { $0.contains(where: { $0 != "0" }) }),
              digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0)
                  || (97...102).contains($0) || $0 == 45 || $0 == 58 }) else { return nil }
        return candidate
    }

    private static func band(_ value: Any?, isFiveG: Bool) -> String? {
        guard let candidate = text(value)?.lowercased(), candidate.first == (isFiveG ? "n" : "b") else { return nil }
        let digits = candidate.dropFirst()
        guard (1...3).contains(digits.count), digits.first != "0",
              digits.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(digits), (1...512).contains(number) else { return nil }
        return candidate
    }

    /// Parse identifiers as integers, never via Double or a rounded measurement.
    private static func integer(_ value: Any?, maximum: UInt64) -> UInt64? {
        let digits: String
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            digits = number.stringValue
        } else if let string = value as? String {
            digits = string.trimmingCharacters(in: .whitespacesAndNewlines)
        } else { return nil }
        guard !digits.isEmpty, digits.count <= 20, digits.utf8.allSatisfy({ (48...57).contains($0) }),
              let integer = UInt64(digits), integer <= maximum else { return nil }
        return integer
    }

    private static func measurement(_ value: Any?, range: ClosedRange<Double>) -> Double? {
        number(value).flatMap { range.contains($0) ? $0 : nil }
    }

    private static func bandwidth(_ value: Any?) -> Double? {
        let raw: Any?
        if let string = value as? String, string.lowercased().hasSuffix("mhz") {
            raw = String(string.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else { raw = value }
        return number(raw).flatMap { $0 > 0 && $0 <= 400 ? $0 : nil }
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128,
              trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return trimmed
    }

    private static func number(_ value: Any?) -> Double? {
        let result: Double?
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            result = number.doubleValue
        } else if let string = value as? String {
            result = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        } else { result = nil }
        return result.flatMap { $0.isFinite ? $0 : nil }
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
            if number == 0 { return false }
            if number == 1 { return true }
        }
        if let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if ["true", "1"].contains(text) { return true }
            if ["false", "0"].contains(text) { return false }
        }
        return nil
    }
}
