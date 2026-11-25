// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ControllerChargeState: Equatable {
    case charging, discharging, full, unknown
}

struct ControllerBatterySample: Equatable {
    let time: TimeInterval
    /// 0...1, as the controller reports it.
    let level: Double
}

/// What a controller's battery has done since it last changed direction.
///
/// Controllers report their charge in coarse steps, so the history keeps only
/// the moments the level changed. The first step has no known start (the
/// level may have sat there for a while before we looked), so a rate needs two
/// later steps: the span between them is measured from step to step.
struct ControllerChargeHistory: Equatable {
    static let minimumTransitions = 2
    static let capacity = 24
    /// Longer than this and the number says more about a stalled charge than
    /// about the battery.
    static let longestEstimate: TimeInterval = 48 * 3600

    private(set) var state: ControllerChargeState = .unknown
    private(set) var steps: [ControllerBatterySample] = []

    mutating func record(level: Double, state newState: ControllerChargeState, at time: TimeInterval) {
        guard level.isFinite else { return }
        if newState != state {
            state = newState
            steps = []
        }
        guard steps.last?.level != level else { return }
        steps.append(ControllerBatterySample(time: time, level: level))
        if steps.count > Self.capacity { steps.removeFirst(steps.count - Self.capacity) }
    }

    mutating func reset() {
        state = .unknown
        steps = []
    }

    /// Seconds until full while charging, or until empty while discharging.
    /// Nil until the history can support one.
    var estimate: TimeInterval? {
        guard state == .charging || state == .discharging else { return nil }
        guard steps.count >= Self.minimumTransitions + 1,
              let first = steps.dropFirst().first, let last = steps.last else { return nil }
        let elapsed = last.time - first.time
        let change = last.level - first.level
        guard elapsed > 0 else { return nil }
        let perSecond = change / elapsed
        let remainingLevel: Double
        switch state {
        case .charging:
            guard perSecond > 0 else { return nil }
            remainingLevel = 1 - last.level
        case .discharging:
            guard perSecond < 0 else { return nil }
            remainingLevel = last.level
        case .full, .unknown:
            return nil
        }
        let seconds = remainingLevel / abs(perSecond)
        guard seconds.isFinite, seconds >= 0, seconds <= Self.longestEstimate else { return nil }
        return seconds
    }
}

struct DualSenseFirmware: Equatable {
    let version: UInt32
    let hardware: UInt32
    /// The date and time the firmware was built, as the controller prints them.
    let built: String?
}

enum GameControllerSupport {
    static let sonyVendorID = 0x054C
    /// DualSense and DualSense Edge.
    static let dualSenseProductIDs: Set<Int> = [0x0CE6, 0x0DF2]
    static let dualSenseFirmwareReportID: UInt8 = 0x20
    static let dualSenseFirmwareReportSize = 64

    static func isDualSense(vendorID: Int?, productID: Int?) -> Bool {
        guard vendorID == sonyVendorID, let productID else { return false }
        return dualSenseProductIDs.contains(productID)
    }

    /// A whole percent, or nil when the controller does not report a usable level.
    static func percent(_ level: Double?) -> Int? {
        guard let level, level.isFinite, (0...1).contains(level) else { return nil }
        return Int((level * 100).rounded())
    }

    /// Reads the DualSense firmware information report (id 0x20): a build date
    /// and time as text, then the hardware and firmware versions as
    /// little-endian words. Anything that does not look like that report is
    /// rejected rather than shown as a version.
    static func parseDualSenseFirmware(_ report: [UInt8]) -> DualSenseFirmware? {
        guard report.count >= 32, report[0] == dualSenseFirmwareReportID else { return nil }
        func word(at offset: Int) -> UInt32 {
            (0..<4).reduce(UInt32(0)) { $0 | UInt32(report[offset + $1]) << (8 * UInt32($1)) }
        }
        let version = word(at: 28)
        guard version != 0, version != UInt32.max else { return nil }
        return DualSenseFirmware(version: version, hardware: word(at: 24),
                                 built: buildStamp(report))
    }

    /// "Sep 12 2023 12:22:08": the date fills bytes 1...11 and the time bytes
    /// 12...19, with nothing between them.
    private static func buildStamp(_ report: [UInt8]) -> String? {
        func field(_ range: Range<Int>) -> String? {
            let bytes = report[range].prefix { $0 != 0 }
            guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }),
                  let text = String(bytes: bytes, encoding: .ascii) else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let date = field(1..<12), let time = field(12..<20), time.contains(":") else { return nil }
        return "\(date) \(time)"
    }

    static func firmwareText(_ firmware: DualSenseFirmware) -> String {
        let version = String(format: "0x%08X", firmware.version)
        guard let built = firmware.built else { return version }
        return "\(version) · \(built)"
    }

    /// "2h 5m", "45m". Never below a minute, never more than two units.
    static func duration(_ seconds: TimeInterval, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: max(60, seconds.rounded())) ?? ""
    }
}
