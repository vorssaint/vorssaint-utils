// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// One input a monitor can be switched to over DDC/CI.
struct DisplayInput: Identifiable, Hashable {
    /// The value written to the input control.
    let value: UInt8
    /// LG monitors take their input through a vendor control on another
    /// host address, with values of their own (issue #885).
    let alternate: Bool

    var id: String { "\(alternate ? "alt" : "std")-\(value)" }
}

/// What a monitor's input menu offers, and the input showing this Mac when
/// the monitor reported it.
struct DisplayInputState: Equatable {
    var inputs: [DisplayInput]
    var current: DisplayInput?
    /// True when the inputs came from the monitor's capabilities string
    /// rather than the common fallback list.
    var detected: Bool
}

/// Input source switching rides the same DDC/CI channel as brightness.
/// The standard control is VCP 0x60 with MCCS values; LG monitors also take
/// VCP 0xF4 on host address 0x50, the route m1ddc and BetterDisplay call
/// "alternate" or "LG alt". Which inputs exist comes from the monitor's
/// capabilities string, `60(0F 11 12)` inside its `vcp(...)` section.
enum DisplayInputSupport {
    static let inputCode: UInt8 = 0x60
    static let alternateInputCode: UInt8 = 0xF4
    static let alternateHostAddress: UInt32 = 0x50

    /// EDID manufacturer "GSM", LG's PnP ID.
    static let lgVendorID: Int64 = 0x1E6D

    // MARK: - Names

    /// MCCS 2.2 names, plus 0x1B, which USB-C monitors widely use.
    static func name(of input: DisplayInput) -> String {
        if input.alternate {
            switch input.value {
            case 0x90: return "HDMI 1"
            case 0x91: return "HDMI 2"
            case 0x92: return "HDMI 3"
            case 0xD0: return "DisplayPort 1"
            case 0xD1: return "DisplayPort 2 / USB-C"
            case 0xD2: return "USB-C / DisplayPort 3"
            default: return unknownName(input.value)
            }
        }
        switch input.value {
        case 0x01: return "VGA 1"
        case 0x02: return "VGA 2"
        case 0x03: return "DVI 1"
        case 0x04: return "DVI 2"
        case 0x05: return "Composite 1"
        case 0x06: return "Composite 2"
        case 0x07: return "S-Video 1"
        case 0x08: return "S-Video 2"
        case 0x09: return "Tuner 1"
        case 0x0A: return "Tuner 2"
        case 0x0B: return "Tuner 3"
        case 0x0C: return "Component 1"
        case 0x0D: return "Component 2"
        case 0x0E: return "Component 3"
        case 0x0F: return "DisplayPort 1"
        case 0x10: return "DisplayPort 2"
        case 0x11: return "HDMI 1"
        case 0x12: return "HDMI 2"
        case 0x1B: return "USB-C"
        default: return unknownName(input.value)
        }
    }

    /// The name a menu or notice shows: LG's alternate route is marked, as
    /// it repeats the standard inputs' names.
    static func label(of input: DisplayInput) -> String {
        input.alternate ? "\(name(of: input)) (LG)" : name(of: input)
    }

    private static func unknownName(_ value: UInt8) -> String {
        let hex = String(value, radix: 16, uppercase: true)
        return "0x" + (hex.count < 2 ? "0" + hex : hex)
    }

    // MARK: - Choosing the list

    /// What most monitors with DDC have, offered when the capabilities string
    /// is missing or lists no inputs.
    static let commonInputs: [UInt8] = [0x0F, 0x10, 0x11, 0x12, 0x1B]
    static let lgAlternateInputs: [UInt8] = [0x90, 0x91, 0xD0, 0xD1, 0xD2]

    /// The menu's inputs: the monitor's own list when it reported one, the
    /// common ones otherwise, and LG's alternate route on LG monitors, whose
    /// standard control often does nothing.
    static func inputs(capabilities: [UInt8]?, vendorID: Int64?) -> (inputs: [DisplayInput], detected: Bool) {
        var seen = Set<UInt8>()
        let reported = (capabilities ?? []).filter { $0 != 0 && seen.insert($0).inserted }
        let detected = !reported.isEmpty
        var inputs = (detected ? reported : commonInputs).map { DisplayInput(value: $0, alternate: false) }
        if vendorID == lgVendorID {
            inputs += lgAlternateInputs.map { DisplayInput(value: $0, alternate: true) }
        }
        return (inputs, detected)
    }

    /// The input a Get VCP reply names. MCCS keeps the input in the low byte;
    /// some monitors set flags in the high one.
    static func currentInput(fromReply current: UInt16, among inputs: [DisplayInput]) -> DisplayInput? {
        let value = UInt8(current & 0xFF)
        guard value != 0 else { return nil }
        return inputs.first { !$0.alternate && $0.value == value } ?? DisplayInput(value: value, alternate: false)
    }

    // MARK: - Shortcut

    /// The standard value an LG alternate input reads back as, so a press can
    /// find where the monitor is even when the menu wrote the LG route.
    static func standardValue(of input: DisplayInput) -> UInt8? {
        guard input.alternate else { return input.value }
        switch input.value {
        case 0x90: return 0x11
        case 0x91: return 0x12
        case 0xD0: return 0x0F
        case 0xD1: return 0x10
        default: return nil
        }
    }

    /// The monitor the shortcut acts on: the one under the pointer, or the
    /// only one when the pointer is on another screen.
    static func shortcutDisplay(pointerDisplay: UInt32?, eligible: [UInt32]) -> UInt32? {
        if let pointerDisplay, eligible.contains(pointerDisplay) { return pointerDisplay }
        return eligible.count == 1 ? eligible[0] : nil
    }

    /// The inputs the shortcut moves through: every listed input but the ones
    /// a person unticked. An input the monitor lists later starts ticked.
    static func cycledInputs(_ inputs: [DisplayInput], excluded: Set<String>) -> [DisplayInput] {
        inputs.filter { !excluded.contains($0.id) }
    }

    /// The input after the current one, wrapping around. A monitor on an input
    /// outside the cycle, or one that did not say, starts from the first.
    static func nextInput(after current: UInt8?, in cycle: [DisplayInput]) -> DisplayInput? {
        guard !cycle.isEmpty else { return nil }
        guard let current,
              let index = cycle.firstIndex(where: { standardValue(of: $0) == current })
        else { return cycle.first }
        return cycle[(index + 1) % cycle.count]
    }

    // MARK: - Writing

    static func writePacket(for input: DisplayInput) -> (packet: [UInt8], hostAddress: UInt32) {
        if input.alternate {
            return (BrightnessSupport.writePacket(code: alternateInputCode, value: UInt16(input.value),
                                                  hostAddress: alternateHostAddress),
                    alternateHostAddress)
        }
        return (BrightnessSupport.writePacket(code: inputCode, value: UInt16(input.value)),
                BrightnessSupport.dataAddress)
    }

    // MARK: - Reading

    /// Get VCP Feature request with the host address in its checksum, as
    /// DDC/CI specifies. Monitors that check it ignore a request without it
    /// and replay their previous reply instead.
    static func readRequestPacket(code: UInt8) -> [UInt8] {
        let bytes: [UInt8] = [0x82, 0x01, code]
        let seed = UInt8(BrightnessSupport.chipAddress << 1) ^ UInt8(BrightnessSupport.dataAddress)
        return bytes + [bytes.reduce(seed) { $0 ^ $1 }]
    }

    // MARK: - Capabilities string

    static let capabilitiesRequestCode: UInt8 = 0xF3
    static let capabilitiesReplyCode: UInt8 = 0xE3
    /// Header, opcode and offset (5 bytes), up to 32 data bytes, checksum.
    static let capabilitiesReplyLength = 38
    /// Real strings run a few hundred bytes; the cap stops a monitor that
    /// never reports the end.
    static let capabilitiesMaximumLength = 1_024

    /// Capabilities Request: opcode and 16-bit offset. Built here because
    /// `BrightnessSupport.packet` carries the VCP opcode in its count byte.
    static func capabilitiesRequestPacket(offset: UInt16) -> [UInt8] {
        let bytes: [UInt8] = [0x83, capabilitiesRequestCode, UInt8(offset >> 8), UInt8(offset & 0xFF)]
        let seed = UInt8(BrightnessSupport.chipAddress << 1) ^ UInt8(BrightnessSupport.dataAddress)
        return bytes + [bytes.reduce(seed) { $0 ^ $1 }]
    }

    /// Data bytes of one capabilities reply fragment, empty at the end of the
    /// string. Nil for anything malformed, or for a fragment at another
    /// offset: a monitor read too early hands back the previous reply.
    static func capabilitiesFragment(_ reply: [UInt8], offset: UInt16) -> [UInt8]? {
        guard reply.count >= 6 else { return nil }
        let length = Int(reply[1] & 0x7F)
        guard reply[1] & 0x80 != 0, length >= 3, 2 + length < reply.count,
              reply[2] == capabilitiesReplyCode,
              reply[3] == UInt8(offset >> 8), reply[4] == UInt8(offset & 0xFF) else { return nil }
        let checksum = reply[0..<(2 + length)].reduce(UInt8(0x50)) { $0 ^ $1 }
        guard checksum == reply[2 + length] else { return nil }
        return Array(reply[5..<(2 + length)])
    }

    /// The input values a capabilities string lists under VCP 0x60, or nil
    /// when it has no `vcp(...)` section or no input entry.
    static func inputValues(fromCapabilities text: String) -> [UInt8]? {
        let characters = Array(text.lowercased())
        guard let section = vcpSectionStart(characters) else { return nil }
        var index = section
        var depth = 0
        var lastCode: UInt8?
        var token = ""
        var values: [UInt8]?

        func finishToken() {
            defer { token = "" }
            guard !token.isEmpty else { return }
            if depth == 0 {
                lastCode = hexBytes(token).last
            } else if depth == 1, lastCode == inputCode {
                values = (values ?? []) + hexBytes(token)
            }
        }

        while index < characters.count {
            let character = characters[index]
            index += 1
            if character.isHexDigit {
                token.append(character)
                continue
            }
            finishToken()
            switch character {
            case "(":
                if depth == 0, lastCode == inputCode, values == nil { values = [] }
                depth += 1
            case ")":
                if depth == 0 { return values.flatMap { $0.isEmpty ? nil : $0 } }
                depth -= 1
                if depth == 0, values != nil, lastCode == inputCode { lastCode = nil }
            default:
                break
            }
        }
        finishToken()
        return values.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Index just past `vcp(`, skipping keys that merely contain it, such as
    /// a model name ending in "vcp".
    private static func vcpSectionStart(_ characters: [Character]) -> Int? {
        let key: [Character] = ["v", "c", "p"]
        var index = 0
        while index + key.count < characters.count {
            defer { index += 1 }
            guard Array(characters[index..<(index + key.count)]) == key else { continue }
            if index > 0, characters[index - 1].isLetter || characters[index - 1].isNumber { continue }
            var next = index + key.count
            while next < characters.count, characters[next] == " " { next += 1 }
            if next < characters.count, characters[next] == "(" { return next + 1 }
        }
        return nil
    }

    /// Hex digits read two at a time, so `0F 11` and `0F11` both list two
    /// values. An odd leftover digit is a value on its own.
    private static func hexBytes(_ token: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var digits = Array(token)
        if digits.count % 2 == 1 { digits.insert("0", at: 0) }
        var index = 0
        while index + 1 < digits.count {
            if let byte = UInt8(String(digits[index...index + 1]), radix: 16) { bytes.append(byte) }
            index += 2
        }
        return bytes
    }
}
