// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import Security
import SwiftUI

/// Where a print job stands, as the printer reports it in `gcode_state`.
enum PrinterJobState: String, Equatable {
    case idle = "IDLE"
    case preparing = "PREPARE"
    case printing = "RUNNING"
    case paused = "PAUSE"
    case finished = "FINISH"
    case failed = "FAILED"
    case unknown

    init(report: String) {
        self = PrinterJobState(rawValue: report.uppercased()) ?? .unknown
    }

    /// A job is on the printer and worth a live activity.
    var isActive: Bool { self == .preparing || self == .printing || self == .paused }

    var symbol: String {
        switch self {
        case .preparing: return "flame"
        case .printing: return "printer.fill"
        case .paused: return "pause.circle.fill"
        case .finished: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle, .unknown: return "printer"
        }
    }
}

/// The parts of a Bambu Lab `print` report the island shows. The A1 and P1
/// series send only what changed after the first full report, so each
/// report is merged into the last one instead of replacing it.
struct PrinterStatus: Equatable {
    var state: PrinterJobState = .unknown
    var percent: Int?
    var remainingMinutes: Int?
    var layer: Int?
    var totalLayers: Int?
    var nozzle: Double?
    var nozzleTarget: Double?
    var bed: Double?
    var bedTarget: Double?
    var jobName: String?
    var errorCode: Int = 0

    mutating func merge(_ print: [String: Any]) {
        if let value = print["gcode_state"] as? String { state = PrinterJobState(report: value) }
        if let value = Self.int(print["mc_percent"]) { percent = max(0, min(100, value)) }
        if let value = Self.int(print["mc_remaining_time"]) { remainingMinutes = max(0, value) }
        if let value = Self.int(print["layer_num"]) { layer = value }
        if let value = Self.int(print["total_layer_num"]) { totalLayers = value }
        if let value = Self.double(print["nozzle_temper"]) { nozzle = value }
        if let value = Self.double(print["nozzle_target_temper"]) { nozzleTarget = value }
        if let value = Self.double(print["bed_temper"]) { bed = value }
        if let value = Self.double(print["bed_target_temper"]) { bedTarget = value }
        if let value = Self.int(print["print_error"]) { errorCode = value }
        if let value = print["subtask_name"] as? String {
            jobName = NotchPrinterSupport.jobName(value)
        }
    }

    /// Reports carry numbers as numbers or, on some firmware, as text.
    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) ?? Double(text).map { Int($0) } }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
}

enum NotchPrinterSupport {
    static let tint = Color(nsColor: .systemGreen)
    static let pausedTint = Color(nsColor: .systemOrange)
    static let failedTint = Color(nsColor: .systemRed)
    /// How long to wait before trying the printer again after it drops.
    static let reconnectDelay: TimeInterval = 10
    /// A connection with no report for this long is treated as lost.
    static let staleAfter: TimeInterval = 90

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchPrinter.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchPrinterEnabled)
            && NotchSupport.modules(in: defaults).contains(.printer)
    }

    static func serial(in defaults: UserDefaults = .standard) -> String {
        (defaults.string(forKey: DefaultsKey.notchPrinterSerial) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func reportTopic(serial: String) -> String { "device/\(serial)/report" }
    static func requestTopic(serial: String) -> String { "device/\(serial)/request" }

    /// Asks for a full report; later reports only carry what changed.
    static func pushAllRequest(sequence: Int) -> Data {
        let body: [String: Any] = ["pushing": ["sequence_id": String(sequence), "command": "pushall"]]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    /// The `print` part of a report, or nil for other messages.
    static func printReport(_ payload: Data) -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        return object["print"] as? [String: Any]
    }

    /// A sliced file's name without the extensions the slicer adds.
    static func jobName(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [".gcode.3mf", ".3mf", ".gcode"] where name.lowercased().hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        return name.isEmpty ? nil : name
    }

    /// "1 h 05 m", "12 m" or "<1 m".
    static func remainingText(minutes: Int?, language: AppLanguage) -> String? {
        guard let minutes else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        var calendar = Calendar.current
        calendar.locale = language.formattingLocale()
        formatter.calendar = calendar
        return formatter.string(from: TimeInterval(max(1, minutes) * 60))
    }

    /// What the closed island shows beside the camera.
    static func stripReading(_ status: PrinterStatus) -> String {
        switch status.state {
        case .preparing: return status.nozzle.map { temperature($0) } ?? "…"
        case .printing, .paused: return status.percent.map { "\($0)%" } ?? "…"
        default: return ""
        }
    }

    static func temperature(_ value: Double) -> String { "\(Int(value.rounded()))°" }

    static func temperaturePair(_ current: Double?, _ target: Double?) -> String {
        let now = current.map { temperature($0) } ?? "–"
        guard let target, target > 0 else { return now }
        return now + " / " + temperature(target)
    }

    static func tint(for state: PrinterJobState) -> Color {
        switch state {
        case .paused: return pausedTint
        case .failed: return failedTint
        default: return tint
        }
    }

    static let stripWingRange: ClosedRange<CGFloat> = 40...96
}

/// The Bambu Cloud sign-in lives in the keychain, not in preferences, so it
/// never reaches a settings backup: the token and the account it belongs to.
/// The account password itself is never stored.
enum PrinterKeychain {
    enum Item: String {
        case cloudToken = "cloud-token"
        case cloudUsername = "cloud-username"
        case cloudEmail = "cloud-email"
    }

    private static let service = "com.vorssaint.utils.bambu-printer"

    static func read(_ item: Item) -> String {
        var query = query(item)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ value: String, for item: Item) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(query(item) as CFDictionary)
        guard !trimmed.isEmpty else { return }
        var entry = query(item)
        entry[kSecValueData as String] = Data(trimmed.utf8)
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(entry as CFDictionary, nil)
    }

    static func signOut() {
        for item in [Item.cloudToken, .cloudUsername, .cloudEmail] { save("", for: item) }
    }

    private static func query(_ item: Item) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: item.rawValue]
    }
}
