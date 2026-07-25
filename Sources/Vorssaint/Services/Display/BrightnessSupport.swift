// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure DDC/CI helpers for the display brightness feature: packet building,
/// reply parsing, value scaling and the display-to-service match score. No
/// IOKit here so the unit tests cover every byte.
enum BrightnessSupport {
    /// VCP code for luminance in the DDC/CI standard.
    static let luminanceCode: UInt8 = 0x10
    /// 7-bit I2C address DDC displays listen on.
    static let chipAddress: UInt32 = 0x37
    /// Sub-address DDC hosts write through.
    static let dataAddress: UInt32 = 0x51

    // Field-proven pacing: displays lose I2C transactions that arrive back to
    // back, so every write waits first, reads settle longer, and failures
    // retry after a pause instead of hammering the bus.
    static let writePauseMicroseconds: UInt32 = 10_000
    static let readPauseMicroseconds: UInt32 = 50_000
    static let retryPauseMicroseconds: UInt32 = 20_000
    static let writeCycles = 2
    static let retryAttempts = 4
    static let replyLength = 11

    /// The DDC/CI standard also spaces whole commands apart: a host waits at
    /// least 50ms after one command before starting the next. The pauses
    /// above pace the steps inside a command; without this one, a slider
    /// drag or a held brightness key chains commands at the write pause,
    /// five times faster than monitors are promised, and some react to the
    /// stream by dropping their signal until they are power cycled
    /// (issue #301).
    static let commandIntervalMicroseconds: UInt64 = 50_000

    /// How long the next command must still wait, given when the previous
    /// one to the same display finished. A first command, or a clock that
    /// moved backwards, waits nothing.
    static func ddcCommandDelay(nowMicroseconds: UInt64,
                                lastCommandEndMicroseconds: UInt64?) -> UInt32 {
        guard let last = lastCommandEndMicroseconds, last <= nowMicroseconds else { return 0 }
        let elapsed = nowMicroseconds - last
        guard elapsed < commandIntervalMicroseconds else { return 0 }
        return UInt32(commandIntervalMicroseconds - elapsed)
    }

    /// Wraps a DDC payload: length-tagged header, payload, XOR checksum. The
    /// checksum seed covers the destination address, and the sub-address only
    /// participates for multi-byte payloads (single-byte requests omit it).
    static func packet(payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [UInt8(0x80 | (payload.count + 1)), UInt8(payload.count)]
        bytes.append(contentsOf: payload)
        let seed = UInt8(chipAddress << 1) ^ (payload.count == 1 ? 0 : UInt8(dataAddress))
        bytes.append(bytes.reduce(seed) { $0 ^ $1 })
        return bytes
    }

    /// Set VCP Feature packet (opcode 0x03 carried in the length header).
    static func writePacket(code: UInt8, value: UInt16) -> [UInt8] {
        packet(payload: [code, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// Get VCP Feature request packet.
    static func readRequestPacket(code: UInt8) -> [UInt8] {
        packet(payload: [code])
    }

    /// Parses a Get VCP Feature reply: checksum first (seeded with the host
    /// address the display answers to), then the big-endian maximum and
    /// current values. Anything malformed reads as no reply.
    static func parseReply(_ reply: [UInt8]) -> (current: UInt16, maximum: UInt16)? {
        guard reply.count >= replyLength else { return nil }
        let checksum = reply[0..<(reply.count - 1)].reduce(UInt8(0x50)) { $0 ^ $1 }
        guard checksum == reply[reply.count - 1] else { return nil }
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return (current, maximum)
    }

    /// A display that reports no range still accepts writes; treat it as the
    /// conventional 0-100 scale.
    static func sanitizedMaximum(_ maximum: UInt16) -> UInt16 {
        maximum > 0 ? maximum : 100
    }

    /// What probing a monitor's DDC channel concluded. Signal converters in
    /// the path (USB-C to HDMI adapters, and the low end Macs whose HDMI port
    /// is such a converter internally) reject every I2C write outright, which
    /// tells a dead channel apart from a monitor that just answers poorly:
    /// field hardware showed reads "succeeding" with cached EDID bytes there,
    /// so only the write result is trustworthy.
    enum DDCChannelOutcome: Equatable {
        /// The monitor answered a luminance read.
        case live
        /// Writes are accepted but replies never come; the slider still
        /// works, it just cannot show the monitor's own value.
        case writeOnly
        /// Every write was rejected: no DDC reaches this display.
        case dead
    }

    static func channelOutcome(writeAccepted: Bool, replyParsed: Bool) -> DDCChannelOutcome {
        if replyParsed { return .live }
        return writeAccepted ? .writeOnly : .dead
    }

    // MARK: - Display switching

    /// Turning off the final drawable display would leave no UI path to turn
    /// it back on. The target must be active and another active display must
    /// remain after the transaction.
    static func canDisableDisplay(activeDisplayIDs: Set<UInt32>, target: UInt32) -> Bool {
        activeDisplayIDs.contains(target) && activeDisplayIDs.count > 1
    }

    // MARK: - Software dimming (gamma curve)

    /// Displays with no DDC channel are dimmed in the video pipeline instead:
    /// the display's gamma curve is scaled down, which darkens the picture
    /// exactly like lowering the backlight would, per display and fully
    /// reversible. The scale is linear all the way down and zero really is
    /// black (owner's call): the slider and the brightness keys can always
    /// bring it back.
    static func softwareDimFactor(for value: Double) -> Float {
        Float(min(max(value, 0), 1))
    }

    /// A gamma table scaled toward black. Factor one returns the input
    /// untouched so restoring is bit-exact.
    static func scaledGammaTable(_ table: [Float], factor: Float) -> [Float] {
        guard factor < 1 else { return table }
        return table.map { $0 * factor }
    }

    /// The dim level put back on a display that just returned from a
    /// connection gap. The saved level is honoured, but never so dark that
    /// the screen reads as dead: replugging the cable is the one gesture
    /// left to someone facing a black picture, and it has to land on
    /// something visible (issue #301). Live control is untouched and still
    /// reaches true black.
    static let reconnectionDimFloor = 0.25

    static func reconnectedDimLevel(_ saved: Double) -> Double {
        max(min(saved, 1), reconnectionDimFloor)
    }

    // MARK: - Brightness keys

    /// The keyboard brightness keys arrive as system-defined events, not key
    /// downs: subtype 8 (auxiliary control buttons) with the key code and
    /// press state packed into data1. Codes 2 and 3 are brightness up and
    /// down; sixteen steps span the whole range, matching the system's own
    /// increments.
    static let brightnessKeyStep = 1.0 / 16.0

    struct BrightnessKeyEvent: Equatable {
        let delta: Double
        let isKeyDown: Bool
        let isRepeat: Bool
    }

    static func brightnessKeyEvent(subtype: Int, data1: Int) -> BrightnessKeyEvent? {
        guard subtype == 8 else { return nil }
        let raw = UInt32(truncatingIfNeeded: data1)
        let state = Int((raw >> 8) & 0xFF)
        guard state == 10 || state == 11 else { return nil }
        let delta: Double
        switch (raw >> 16) & 0xFFFF {
        case 2: delta = brightnessKeyStep
        case 3: delta = -brightnessKeyStep
        default: return nil
        }
        return BrightnessKeyEvent(delta: delta, isKeyDown: state == 10, isRepeat: (raw & 0x1) != 0)
    }

    /// Keyboards other than the built-in one do not send brightness as a
    /// media key at all. They send an ordinary key press: either one of the
    /// two dedicated brightness codes, or F14 and F15, which the system
    /// offers as brightness keys in its own keyboard shortcuts whenever an
    /// external keyboard is attached. Measured against the display server:
    /// all four move brightness by the same sixteenth of the range as the
    /// built-in keys (issue #287).
    enum BrightnessKeyCode {
        static let increase = 144
        static let decrease = 145
        static let functionIncrease = 113
        static let functionDecrease = 107
    }

    /// Cheap enough for the hot path: every keystroke in the session passes
    /// through the tap, and only these four may cost anything more.
    static func isBrightnessKeyCode(_ keyCode: Int) -> Bool {
        keyCode == BrightnessKeyCode.increase || keyCode == BrightnessKeyCode.decrease
            || keyCode == BrightnessKeyCode.functionIncrease
            || keyCode == BrightnessKeyCode.functionDecrease
    }

    static func brightnessFunctionKeyEvent(keyCode: Int,
                                           isKeyDown: Bool,
                                           isRepeat: Bool,
                                           hasModifiers: Bool,
                                           functionKeysAdjustBrightness: Bool) -> BrightnessKeyEvent? {
        // A modified press means something else: the system opens its own
        // display settings, and finer steps are its business too.
        guard !hasModifiers else { return nil }
        let delta: Double
        switch keyCode {
        case BrightnessKeyCode.increase: delta = brightnessKeyStep
        case BrightnessKeyCode.decrease: delta = -brightnessKeyStep
        case BrightnessKeyCode.functionIncrease where functionKeysAdjustBrightness:
            delta = brightnessKeyStep
        case BrightnessKeyCode.functionDecrease where functionKeysAdjustBrightness:
            delta = -brightnessKeyStep
        default: return nil
        }
        return BrightnessKeyEvent(delta: delta, isKeyDown: isKeyDown, isRepeat: isRepeat)
    }

    /// Whether F14 and F15 still mean brightness. The system ships them
    /// switched on, so an absent entry means yes; a user who turned them off
    /// in the system's keyboard shortcuts gets them left alone.
    static func functionKeysAdjustBrightness(symbolicHotKeys: [String: Any]?) -> Bool {
        guard let symbolicHotKeys else { return true }
        for identifier in ["53", "54"] {
            guard let entry = symbolicHotKeys[identifier] as? [String: Any] else { continue }
            if let enabled = entry["enabled"] as? Bool, !enabled { return false }
            if let enabled = entry["enabled"] as? NSNumber, !enabled.boolValue { return false }
        }
        return true
    }

    static func steppedBrightness(_ current: Double, delta: Double) -> Double {
        min(max(current + delta, 0), 1)
    }

    /// Whether a brightness key press aimed at a system-routed display is
    /// stepped by the app instead of left to the system (issue #268). The
    /// system's own key handling only ever moves its native target, so a
    /// press the pointer routes to any other display (an Apple pipeline
    /// external monitor, or any display in clamshell mode) has to be stepped
    /// here or it lands on the wrong screen. The built-in panel keeps the
    /// native handling and its animation unless the overlay replaces it.
    static func stepsSystemRoutedDisplay(followsPointer: Bool,
                                         displayIsBuiltIn: Bool,
                                         overlayReplacesNative: Bool) -> Bool {
        if followsPointer, !displayIsBuiltIn { return true }
        return overlayReplacesNative
    }

    /// Sixteen segments match the system brightness steps. A non-zero value
    /// keeps at least one segment visible while exact zero stays empty.
    static func filledBrightnessSegments(_ brightness: Double) -> Int {
        let clamped = min(max(brightness, 0), 1)
        guard clamped > 0 else { return 0 }
        return min(Int((clamped * 16).rounded(.up)), 16)
    }

    /// Whole percentage used by the brightness overlay.
    static func wholePercent(_ brightness: Double) -> Int {
        guard brightness.isFinite else { return 0 }
        return Int((min(max(brightness, 0), 1) * 100).rounded())
    }

    /// DDC value to the 0...1 slider scale.
    static func normalized(current: UInt16, maximum: UInt16) -> Double {
        let ceiling = sanitizedMaximum(maximum)
        return min(max(Double(current) / Double(ceiling), 0), 1)
    }

    /// Slider value to the display's own scale, rounded to the nearest step.
    static func deviceValue(for normalized: Double, maximum: UInt16) -> UInt16 {
        let ceiling = sanitizedMaximum(maximum)
        let clamped = min(max(normalized, 0), 1)
        return UInt16((clamped * Double(ceiling)).rounded())
    }

    // MARK: - Display to service matching

    /// What CoreGraphics knows about a display, for scoring against an
    /// IORegistry service candidate.
    struct DisplayIdentity {
        var vendorID: Int64?
        var productID: Int64?
        var weekOfManufacture: Int64?
        var yearOfManufacture: Int64?
        var horizontalImageSize: Int64?
        var verticalImageSize: Int64?
        var ioDisplayLocation: String?
        var productName: String?
        var serialNumber: Int64?
    }

    /// What the IORegistry walk collected for one external service.
    struct ServiceIdentity {
        var edidUUID = ""
        var ioDisplayLocation = ""
        var productName = ""
        var serialNumber: Int64 = 0
        var ordinal = 0
    }

    /// The EDID UUID embeds identity fields at fixed positions; each one that
    /// matches the display scores a point, and the IORegistry path match is
    /// decisive on its own. Zero means the pair is unrelated.
    static func matchScore(service: ServiceIdentity, display: DisplayIdentity) -> Int {
        var score = 0
        func uuidChunk(at location: Int) -> String {
            String(service.edidUUID.prefix(location + 4).suffix(4))
        }
        if let vendor = display.vendorID, vendor > 0 {
            let key = String(format: "%04X", UInt16(clamping: vendor))
            if key != "0000", key == uuidChunk(at: 0) { score += 1 }
        }
        if let product = display.productID, product > 0 {
            let value = UInt16(clamping: product)
            let key = String(format: "%02X%02X", UInt8(value & 0xFF), UInt8(value >> 8))
            if key != "0000", key == uuidChunk(at: 4) { score += 1 }
        }
        if let week = display.weekOfManufacture, let year = display.yearOfManufacture, year >= 1990 {
            let key = String(format: "%02X%02X",
                             UInt8(clamping: week),
                             UInt8(clamping: year - 1990))
            if key != "0000", key == uuidChunk(at: 19) { score += 1 }
        }
        if let horizontal = display.horizontalImageSize, let vertical = display.verticalImageSize {
            let key = String(format: "%02X%02X",
                             UInt8(clamping: horizontal / 10),
                             UInt8(clamping: vertical / 10))
            if key != "0000", key == uuidChunk(at: 30) { score += 1 }
        }
        if !service.ioDisplayLocation.isEmpty, service.ioDisplayLocation == display.ioDisplayLocation {
            score += 10
        }
        if !service.productName.isEmpty,
           service.productName.lowercased() == display.productName?.lowercased() {
            score += 1
        }
        if service.serialNumber != 0, service.serialNumber == display.serialNumber {
            score += 1
        }
        return score
    }

    /// Greedy assignment, best scores first: each display and each service is
    /// used at most once, and zero-score pairs never match. Returns display
    /// index to service ordinal.
    static func assignServices(scores: [(displayIndex: Int, serviceOrdinal: Int, score: Int)])
        -> [Int: Int] {
        var assignment: [Int: Int] = [:]
        var takenServices = Set<Int>()
        for entry in scores.sorted(by: { $0.score > $1.score }) where entry.score > 0 {
            guard assignment[entry.displayIndex] == nil,
                  !takenServices.contains(entry.serviceOrdinal) else { continue }
            assignment[entry.displayIndex] = entry.serviceOrdinal
            takenServices.insert(entry.serviceOrdinal)
        }
        return assignment
    }
}
