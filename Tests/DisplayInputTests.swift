// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Input source packets, capabilities parsing and the menu's list. No monitor
/// is read or written.
enum DisplayInputTests {
    static func run(_ suite: TestSuite) {
        packets(suite)
        capabilities(suite)
        fragments(suite)
        lists(suite)
        shortcut(suite)
    }

    private static func packets(_ suite: TestSuite) {
        // m1ddc's `set input 15`: 0x84 0x03 0x60 0x00 0x0F, checksum seeded 0x6E ^ 0x51.
        let standard = DisplayInputSupport.writePacket(for: DisplayInput(value: 0x0F, alternate: false))
        suite.expect(standard.hostAddress == 0x51, "standard input writes through the usual host address")
        suite.expect(standard.packet == [0x84, 0x03, 0x60, 0x00, 0x0F, 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x60 ^ 0x0F],
                     "standard input packet matches m1ddc")
        // m1ddc's `set input-alt 208`: VCP 0xF4 on host address 0x50.
        let lg = DisplayInputSupport.writePacket(for: DisplayInput(value: 0xD0, alternate: true))
        suite.expect(lg.hostAddress == 0x50, "LG input writes through the alternate host address")
        suite.expect(lg.packet == [0x84, 0x03, 0xF4, 0x00, 0xD0, 0x6E ^ 0x50 ^ 0x84 ^ 0x03 ^ 0xF4 ^ 0xD0],
                     "LG input packet's checksum covers the alternate host address")
        suite.expect(BrightnessSupport.writePacket(code: 0x10, value: 50)
                        == BrightnessSupport.packet(payload: [0x10, 0, 50]),
                     "luminance packets keep the usual host address")
        // m1ddc's `get input`; a Samsung Odyssey G5 ignored the request without 0x51.
        suite.expect(DisplayInputSupport.readRequestPacket(code: 0x60)
                        == [0x82, 0x01, 0x60, 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x60],
                     "input read request's checksum covers the host address")
        suite.expect(DisplayInputSupport.capabilitiesRequestPacket(offset: 0x20)
                        == [0x83, 0xF3, 0x00, 0x20, 0x6E ^ 0x51 ^ 0x83 ^ 0xF3 ^ 0x20],
                     "capabilities request carries its offset")
    }

    private static func capabilities(_ suite: TestSuite) {
        let dell = "(prot(monitor)type(LCD)model(U2720Q)cmds(01 02 03 07 0C E3 F3)vcp(02 04 05 08 10 12 "
            + "14(01 04 05 06 08 09 0B 0C) 16 18 1A 52 60(1B 0F 11 ) AA(01 02 04) AC AE B2 B6 C6 C8 C9 "
            + "D6(01 04 05) DC(00 03 05) DF E0 E1 E2(00 1D 01 02 04 0E 12 14 23 24 27) F0(0C) F1 F2 FD)"
            + "mswhql(1)asset_eep(40)mccs_ver(2.1))"
        suite.expect(DisplayInputSupport.inputValues(fromCapabilities: dell) == [0x1B, 0x0F, 0x11],
                     "inputs read from the vcp section, in the monitor's order")
        suite.expect(DisplayInputSupport.inputValues(fromCapabilities: "vcp(10 12 60(0F11 12))") == [0x0F, 0x11, 0x12],
                     "packed hex values split into pairs")
        suite.expect(DisplayInputSupport.inputValues(fromCapabilities: "model(vcp60)VCP(10 60 (0F 10))") == [0x0F, 0x10],
                     "a model name containing vcp is not the section; case and spacing vary")
        suite.expect(DisplayInputSupport.inputValues(fromCapabilities: "vcp(10 12 60)") == nil,
                     "an input control without values lists no inputs")
        suite.expect(DisplayInputSupport.inputValues(fromCapabilities: "vcp(10 14(60 61) 12)") == nil,
                     "a value 0x60 under another control is not the input control")
        suite.expect(DisplayInputSupport.inputValues(fromCapabilities: "prot(monitor)") == nil,
                     "no vcp section lists no inputs")
        suite.expect(DisplayInputSupport.inputValues(fromCapabilities: "vcp(60(0F 11") == [0x0F, 0x11],
                     "a truncated string keeps what it listed")
    }

    private static func fragments(_ suite: TestSuite) {
        func reply(offset: UInt16, data: [UInt8]) -> [UInt8] {
            var bytes: [UInt8] = [0x6E, 0x80 | UInt8(3 + data.count), 0xE3, UInt8(offset >> 8), UInt8(offset & 0xFF)]
            bytes += data
            bytes.append(bytes.reduce(UInt8(0x50)) { $0 ^ $1 })
            return bytes + [UInt8](repeating: 0, count: max(0, 38 - bytes.count))
        }
        let data = Array("vcp(60(0F".utf8)
        suite.expect(DisplayInputSupport.capabilitiesFragment(reply(offset: 32, data: data), offset: 32) == data,
                     "a fragment's data bytes")
        suite.expect(DisplayInputSupport.capabilitiesFragment(reply(offset: 64, data: []), offset: 64) == [],
                     "an empty fragment ends the string")
        suite.expect(DisplayInputSupport.capabilitiesFragment(reply(offset: 0, data: data), offset: 32) == nil,
                     "a fragment for another offset is a stale reply")
        var corrupted = reply(offset: 0, data: data)
        corrupted[6] ^= 0x01
        suite.expect(DisplayInputSupport.capabilitiesFragment(corrupted, offset: 0) == nil,
                     "a bad checksum reads as no reply")
        var vcpReply = reply(offset: 0, data: data)
        vcpReply[2] = 0x02
        suite.expect(DisplayInputSupport.capabilitiesFragment(vcpReply, offset: 0) == nil,
                     "a Get VCP reply is not a capabilities fragment")
    }

    private static func lists(_ suite: TestSuite) {
        let reported = DisplayInputSupport.inputs(capabilities: [0x11, 0x0F, 0x11, 0x00], vendorID: 0x10AC)
        suite.expect(reported.detected, "a reported list is detected")
        suite.expect(reported.inputs.map(\.value) == [0x11, 0x0F], "reported inputs keep order, without repeats or zero")
        let fallback = DisplayInputSupport.inputs(capabilities: nil, vendorID: nil)
        suite.expect(!fallback.detected && fallback.inputs.map(\.value) == DisplayInputSupport.commonInputs,
                     "no capabilities offers the common inputs")
        let lg = DisplayInputSupport.inputs(capabilities: [0x0F, 0x11], vendorID: DisplayInputSupport.lgVendorID)
        suite.expect(lg.inputs.filter(\.alternate).map(\.value) == DisplayInputSupport.lgAlternateInputs,
                     "LG monitors add the alternate route")
        suite.expect(DisplayInputSupport.currentInput(fromReply: 0x0111, among: lg.inputs)
                        == DisplayInput(value: 0x11, alternate: false),
                     "the current input is the reply's low byte")
        suite.expect(DisplayInputSupport.currentInput(fromReply: 0, among: lg.inputs) == nil,
                     "zero names no input")
        suite.expect(DisplayInputSupport.name(of: DisplayInput(value: 0x1B, alternate: false)) == "USB-C"
                        && DisplayInputSupport.name(of: DisplayInput(value: 0x2A, alternate: false)) == "0x2A"
                        && DisplayInputSupport.name(of: DisplayInput(value: 0x0A, alternate: true)) == "0x0A",
                     "known and unknown input names")
        suite.expect(DisplayInputSupport.label(of: DisplayInput(value: 0xD0, alternate: true)) == "DisplayPort 1 (LG)"
                        && DisplayInputSupport.label(of: DisplayInput(value: 0x11, alternate: false)) == "HDMI 1",
                     "LG's alternate inputs are marked")
    }

    private static func shortcut(_ suite: TestSuite) {
        let dp = DisplayInput(value: 0x0F, alternate: false)
        let hdmi = DisplayInput(value: 0x11, alternate: false)
        let usbc = DisplayInput(value: 0x1B, alternate: false)
        let all = [dp, hdmi, usbc]
        let cycle = DisplayInputSupport.cycledInputs(all, excluded: [usbc.id])
        suite.expect(cycle == [dp, hdmi], "unticked inputs leave the cycle")
        suite.expect(DisplayInputSupport.nextInput(after: 0x0F, in: cycle) == hdmi
                        && DisplayInputSupport.nextInput(after: 0x11, in: cycle) == dp,
                     "two ticked inputs toggle")
        suite.expect(DisplayInputSupport.nextInput(after: 0x1B, in: all) == dp, "the last input wraps to the first")
        suite.expect(DisplayInputSupport.nextInput(after: 0x1B, in: cycle) == dp
                        && DisplayInputSupport.nextInput(after: nil, in: cycle) == dp,
                     "an input outside the cycle, or none read, starts from the first")
        suite.expect(DisplayInputSupport.nextInput(after: 0x0F, in: []) == nil, "an empty cycle switches nothing")
        let lgDP = DisplayInput(value: 0xD0, alternate: true)
        let lgHDMI = DisplayInput(value: 0x90, alternate: true)
        suite.expect(DisplayInputSupport.nextInput(after: 0x0F, in: [lgDP, lgHDMI]) == lgHDMI,
                     "an LG input is found by the standard value it reads back as")
        suite.expect(DisplayInputSupport.shortcutDisplay(pointerDisplay: 3, eligible: [2, 3]) == 3,
                     "the monitor under the pointer")
        suite.expect(DisplayInputSupport.shortcutDisplay(pointerDisplay: 1, eligible: [2]) == 2,
                     "the only monitor when the pointer is on the built-in screen")
        suite.expect(DisplayInputSupport.shortcutDisplay(pointerDisplay: 1, eligible: [2, 3]) == nil,
                     "no guess between several monitors")
    }
}
