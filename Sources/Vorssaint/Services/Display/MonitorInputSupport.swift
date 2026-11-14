// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The decisions behind switching a monitor's input over DDC, kept apart from
/// the bus so they can be tested: which inputs a monitor says it has, which one
/// a press moves to, which monitor and which service it is for, and how the
/// capability string is asked for and put back together.
enum MonitorInputSupport {
    /// The control MCCS defines for the input source.
    static let inputCode: UInt8 = 0x60
    /// Opcodes of the capabilities exchange: the request the host sends and
    /// the fragment a monitor answers with.
    private static let capabilitiesRequestOpcode: UInt8 = 0xF3
    private static let capabilitiesReplyOpcode: UInt8 = 0xE3
    /// A fragment carries up to 32 bytes of text, plus its header and checksum.
    static let capabilitiesReplyLength = 40
    /// Real strings take about six fragments. A monitor that never ends its
    /// string is given up on after this many requests.
    static let maximumCapabilityFragments = 64

    /// Get VCP Feature request for the input control.
    static var getInputPacket: [UInt8] {
        BrightnessSupport.readRequestPacket(code: inputCode)
    }

    /// Set VCP Feature packet that selects an input.
    static func setInputPacket(_ value: UInt16) -> [UInt8] {
        BrightnessSupport.writePacket(code: inputCode, value: value)
    }

    /// The names of the inputs MCCS defines, as monitors show them in their
    /// own menus. A value the standard does not define is shown as the number
    /// the monitor reports: guessing a name would send someone to the wrong
    /// port.
    static func name(of value: UInt16) -> String {
        switch value {
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
        default: return String(format: "Input 0x%02X", UInt32(value))
        }
    }

    /// The input a monitor reports. MCCS puts it in the low byte; the high
    /// byte is reserved, and a monitor that fills it would otherwise show an
    /// input no list contains and be moved to the one it is already on.
    static func inputValue(fromReply reply: UInt16) -> UInt16 {
        reply & 0x00FF
    }

    // MARK: - Capability string

    /// The input values a monitor lists for control 60 in its capability
    /// string, sorted and without repeats. Only the control that sits directly
    /// in the `vcp(...)` section counts: 60 as a value of another control, or
    /// a control nested deeper, is not the input list. Some firmware sends the
    /// string with a parenthesis missing, so a section that never closes is
    /// read to the end.
    static func supportedInputs(fromCapabilities text: String) -> [UInt16] {
        let lowered = text.lowercased()
        guard let start = vcpSectionStart(in: lowered) else { return [] }
        var values = Set<UInt16>()
        var owners: [String] = []
        var token = ""
        func flush() {
            defer { token = "" }
            guard owners == ["60"], (1...2).contains(token.count),
                  let value = UInt16(token, radix: 16) else { return }
            values.insert(value)
        }
        for character in lowered[start...] {
            switch character {
            case "(":
                owners.append(token)
                token = ""
            case ")":
                flush()
                if owners.popLast() == nil { return values.sorted() }
            case " ", "\t", "\n", "\r":
                flush()
            default:
                token.append(character)
            }
        }
        flush()
        return values.sorted()
    }

    /// The first character after `vcp(`, not taken from the middle of a longer
    /// word.
    private static func vcpSectionStart(in text: String) -> String.Index? {
        var searchFrom = text.startIndex
        while let found = text.range(of: "vcp(", range: searchFrom..<text.endIndex) {
            let standsAlone = found.lowerBound == text.startIndex
                || !text[text.index(before: found.lowerBound)].isLetter
                && !text[text.index(before: found.lowerBound)].isNumber
            if standsAlone { return found.upperBound }
            searchFrom = found.upperBound
        }
        return nil
    }

    /// The input a press moves to: the next listed value, wrapping around, so
    /// two inputs swap and more cycle. With a single input, or none, there is
    /// nowhere to go, and when the current input could not be read the press
    /// does not guess, since a guess can be the input already showing.
    static func nextInput(after current: UInt16?, among supported: [UInt16]) -> UInt16? {
        let inputs = Array(Set(supported)).sorted()
        guard inputs.count >= 2, let current else { return nil }
        if let index = inputs.firstIndex(of: current) {
            return inputs[(index + 1) % inputs.count]
        }
        return inputs.first { $0 > current } ?? inputs.first
    }

    /// What a press does with what the monitor said: move to an input, or say
    /// why it cannot. A list that could not be read and a list with a single
    /// input are told apart, because the first is worth trying again and the
    /// second is a monitor with nowhere to go.
    enum Plan: Equatable {
        case switchTo(UInt16)
        case unreadable
        case noOtherInput
    }

    static func plan(current: UInt16?, supported: [UInt16]) -> Plan {
        let inputs = Set(supported)
        guard !inputs.isEmpty else { return .unreadable }
        guard inputs.count >= 2 else { return .noOtherInput }
        guard let next = nextInput(after: current, among: supported) else { return .unreadable }
        return .switchTo(next)
    }

    // MARK: - Confirming a switch

    /// Monitors take a few seconds to move to another input, and the Samsung
    /// measured two to four. The input is read again at this spacing, this
    /// many times, so the wait outlasts the switch and still ends.
    static let confirmationReads = 4
    static let confirmationInterval: TimeInterval = 2

    enum SwitchResult: Equatable {
        case switched
        case notSwitched
        case unknown
    }

    /// What the reads taken after a switch say about it. One read of the
    /// wanted input settles it. A monitor that kept answering with something
    /// else did not switch. One that never answered again has said nothing
    /// either way, and a monitor busy changing input is not accused of failing.
    static func result(readings: [UInt16?], target: UInt16) -> SwitchResult {
        if readings.contains(where: { $0 == target }) { return .switched }
        return readings.contains(where: { $0 != nil }) ? .notSwitched : .unknown
    }

    // MARK: - Which monitor

    /// A monitor as the settings picker shows it.
    struct Monitor: Identifiable, Equatable {
        let id: UInt32
        let name: String
        var current: UInt16
        let inputs: [UInt16]
    }

    /// Only a monitor that said which input it shows and lists more than one
    /// is worth a picker. The input it shows is offered even when its own list
    /// leaves it out, so the picker can mark it.
    static func pickerMonitor(id: UInt32, name: String, current: UInt16?, supported: [UInt16]) -> Monitor? {
        guard let current, Set(supported).count >= 2 else { return nil }
        return Monitor(id: id, name: name, current: current,
                       inputs: Array(Set(supported).union([current])).sorted())
    }

    /// The monitor a press is for: the one under the pointer, or the only one
    /// that can switch. With several and the pointer on none of them nothing
    /// is switched, because there is no telling which one was meant.
    static func targetDisplay(pointerDisplay: UInt32?, candidates: [UInt32]) -> UInt32? {
        if let pointerDisplay, candidates.contains(pointerDisplay) { return pointerDisplay }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// The DDC service that belongs to the monitor at `index`. One monitor and
    /// one service can only belong to each other, even when the display data
    /// is too sparse to score. With several, only a clear match counts: the
    /// brightness scan can settle for a weaker one, but a wrong guess here
    /// switches the input of a monitor nobody pointed at.
    static func serviceOrdinal(for index: Int,
                               scores: [(displayIndex: Int, serviceOrdinal: Int, score: Int)],
                               displayCount: Int, serviceOrdinals: [Int]) -> Int? {
        if displayCount == 1, serviceOrdinals.count == 1 { return serviceOrdinals[0] }
        return BrightnessSupport.speakerService(for: index, scores: scores)
    }

    // MARK: - Capabilities exchange

    /// Get Capabilities Request for the fragment that starts at `offset`.
    static func capabilitiesRequestPacket(offset: Int) -> [UInt8] {
        var bytes: [UInt8] = [0x80 | 3, capabilitiesRequestOpcode,
                              UInt8((offset >> 8) & 0xFF), UInt8(offset & 0xFF)]
        let seed = UInt8(BrightnessSupport.chipAddress << 1) ^ UInt8(BrightnessSupport.dataAddress)
        bytes.append(bytes.reduce(seed) { $0 ^ $1 })
        return bytes
    }

    /// The text of one capabilities reply, or nil when it is not the answer to
    /// this request: checksum first (seeded with the host address the monitor
    /// answers to), then the opcode, then the offset it answers for. A reply
    /// for another offset is a stale one, and an empty fragment is how a
    /// monitor ends its string.
    static func parseCapabilitiesReply(_ reply: [UInt8], offset: Int) -> [UInt8]? {
        guard reply.count >= 6, reply[1] & 0x80 != 0 else { return nil }
        let length = Int(reply[1] & 0x7F)
        guard reply[2] == capabilitiesReplyOpcode, length >= 3, reply.count >= length + 3 else { return nil }
        let checksum = reply[0..<(length + 2)].reduce(UInt8(0x50)) { $0 ^ $1 }
        guard checksum == reply[length + 2],
              Int(reply[3]) << 8 | Int(reply[4]) == offset else { return nil }
        return Array(reply[5..<(length + 2)])
    }

    /// Puts the fragments together, asking each time from the end of what has
    /// arrived. The string is only used when it ended with the empty fragment,
    /// or when it was cut off after a complete input list, which is all that
    /// switching needs.
    static func capabilities(fetch: (Int) -> [UInt8]?) -> String? {
        var bytes: [UInt8] = []
        var ended = false
        for _ in 0..<maximumCapabilityFragments {
            guard let fragment = fetch(bytes.count) else { break }
            if fragment.isEmpty { ended = true; break }
            bytes.append(contentsOf: fragment)
        }
        guard !bytes.isEmpty else { return nil }
        let text = String(decoding: bytes, as: UTF8.self)
        return ended || !supportedInputs(fromCapabilities: text).isEmpty ? text : nil
    }
}
