// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The pure logic of a monitor's speaker volume: packets, the level and mute
/// state, the volume keys, which monitor a key belongs to and when a volume
/// is offered. Nothing here talks to a monitor, so these checks show the
/// logic is right, not that a given monitor takes the commands.
enum MonitorVolumeTests {
    static func run(_ suite: TestSuite) {
        packets(suite)
        replies(suite)
        levels(suite)
        mute(suite)
        keys(suite)
        targets(suite)
        memory(suite)
        offering(suite)
    }

    private static func packets(_ suite: TestSuite) {
        suite.expect(MonitorVolumeSupport.volumeCode == 0x62 && MonitorVolumeSupport.muteCode == 0x8D
                     && MonitorVolumeSupport.volumeCode != MonitorVolumeSupport.muteCode,
                     "volume is VCP 0x62 and mute is VCP 0x8D, never the same control")
        let volume = MonitorVolumeSupport.packet(for: .volume(12))
        suite.expect(volume == BrightnessSupport.writePacket(code: 0x62, value: 12)
                     && volume[1] == 0x03 && volume[2] == 0x62 && volume[3] == 0 && volume[4] == 12,
                     "a volume write is a Set VCP Feature for 0x62 with the value big-endian")
        let mute = MonitorVolumeSupport.packet(for: .mute(MonitorVolumeSupport.muteOn))
        suite.expect(mute[2] == 0x8D && mute[4] == 1
                     && MonitorVolumeSupport.packet(for: .mute(MonitorVolumeSupport.muteOff))[4] == 2,
                     "a mute write is a Set VCP Feature for 0x8D, 1 to mute and 2 to unmute")
        let checksum = volume[0..<(volume.count - 1)].reduce(UInt8(0x37 << 1) ^ 0x51) { $0 ^ $1 }
        suite.expect(checksum == volume[volume.count - 1], "the packet carries the DDC checksum")
        suite.expect(MonitorVolumeSupport.deviceValue(0, maximum: 100) == 0
                     && MonitorVolumeSupport.deviceValue(1, maximum: 100) == 100
                     && MonitorVolumeSupport.deviceValue(0.5, maximum: 63) == 32
                     && MonitorVolumeSupport.deviceValue(2, maximum: 100) == 100
                     && MonitorVolumeSupport.deviceValue(-1, maximum: 100) == 0
                     && MonitorVolumeSupport.deviceValue(0.5, maximum: 0) == 50,
                     "a level maps onto the monitor's own range, clamped, and a monitor with no range has 0-100")
    }

    private static func replies(_ suite: TestSuite) {
        func reply(code: UInt8, maximum: UInt16, current: UInt16, result: UInt8 = 0) -> [UInt8] {
            var bytes: [UInt8] = [0x6E, 0x88, 0x02, result, code, 0x00,
                                  UInt8(maximum >> 8), UInt8(maximum & 0xFF),
                                  UInt8(current >> 8), UInt8(current & 0xFF)]
            bytes.append(bytes.reduce(UInt8(0x50)) { $0 ^ $1 })
            return bytes
        }
        let good = BrightnessSupport.parseReply(reply(code: 0x62, maximum: 100, current: 6), code: 0x62)
        suite.expect(good?.current == 6 && good?.maximum == 100, "a valid reading of 0x62 gives its current and maximum")
        suite.expect(BrightnessSupport.parseReply(reply(code: 0x10, maximum: 100, current: 6), code: 0x62) == nil,
                     "the answer to another control is not a volume reading")
        var broken = reply(code: 0x62, maximum: 100, current: 6)
        broken[8] ^= 0x01
        suite.expect(BrightnessSupport.parseReply(broken, code: 0x62) == nil, "a reply with a bad checksum is no reading")
        suite.expect(BrightnessSupport.parseReply(Array(reply(code: 0x62, maximum: 100, current: 6).dropLast(3)), code: 0x62) == nil
                     && BrightnessSupport.parseReply([UInt8](repeating: 0, count: 11), code: 0x62) == nil,
                     "a short reply and an all-zero reply, which is what a monitor that answers nothing returns, are no reading")
        suite.expect(BrightnessSupport.channelOutcome(writeAccepted: true, replyParsed: false) == .writeOnly
                     && BrightnessSupport.channelOutcome(writeAccepted: false, replyParsed: false) == .dead
                     && BrightnessSupport.channelOutcome(writeAccepted: true, replyParsed: true) == .live,
                     "a channel that takes writes but gives no reading is write-only, not unsupported")
    }

    private static func levels(_ suite: TestSuite) {
        var state = MonitorVolumeSupport.State(level: 0.5)
        let up = state.step(delta: MonitorVolumeSupport.keyStep, method: .volumeZero)
        suite.expect(state.level == 0.5625 && up == [.volume(56)], "a step up raises the level by a sixteenth and writes it")
        var top = MonitorVolumeSupport.State(level: 0.98)
        _ = top.step(delta: 0.5, method: .volumeZero)
        suite.expect(top.level == 1 && MonitorVolumeSupport.deviceValue(top.level, maximum: 100) == 100,
                     "the maximum volume is never exceeded")
        var bottom = MonitorVolumeSupport.State(level: 0.03)
        let down = bottom.step(delta: -0.5, method: .volumeZero)
        suite.expect(bottom.level == 0 && down == [.volume(0)] && !bottom.muted, "the minimum volume is zero and stops there")
        var out = MonitorVolumeSupport.State(level: 0.4)
        suite.expect(out.set(level: .nan, method: .volumeZero).isEmpty && out.set(level: .infinity, method: .volumeZero).isEmpty
                     && out.step(delta: .nan, method: .volumeZero).isEmpty && out.level == 0.4,
                     "a value that is not a number changes nothing and writes nothing")
        _ = out.set(level: 9, method: .volumeZero)
        suite.expect(out.level == 1, "a level above the range is held at the top")
        _ = out.set(level: -9, method: .volumeZero)
        suite.expect(out.level == 0, "a level below the range is held at zero")
        var ranged = MonitorVolumeSupport.State(level: 0.5)
        suite.expect(ranged.step(delta: 0, maximum: 63, method: .volumeZero) == [.volume(32)],
                     "writes follow the range the monitor reported")
        suite.expect(MonitorVolumeSupport.State(level: .nan).level == 0.125 && MonitorVolumeSupport.State(level: 4).level == 1,
                     "a stored level that is not valid starts from the default or is clamped")
        suite.expect(MonitorVolumeSupport.collapsed([.volume(1), .volume(2), .volume(3)]) == [.volume(3)]
                     && MonitorVolumeSupport.collapsed([.mute(2), .volume(1), .volume(2)]) == [.mute(2), .volume(2)]
                     && MonitorVolumeSupport.collapsed([.volume(1), .mute(1), .volume(2)]) == [.volume(1), .mute(1), .volume(2)]
                     && MonitorVolumeSupport.collapsed([]).isEmpty,
                     "writes waiting for the channel keep only the newest volume and every mute change in order")
    }

    private static func mute(_ suite: TestSuite) {
        var state = MonitorVolumeSupport.State(level: 0.4)
        suite.expect(state.toggleMute(method: .volumeZero) == [.volume(0)] && state.muted && state.shown == 0 && state.level == 0.4,
                     "muting by volume writes zero and keeps the level it had")
        suite.expect(state.toggleMute(method: .volumeZero) == [.volume(40)] && !state.muted && state.shown == 0.4,
                     "unmuting brings the last level back")
        _ = state.toggleMute(method: .muteCode)
        suite.expect(state.muted, "muting by the mute code marks it muted")
        suite.expect(state.toggleMute(method: .muteCode) == [.mute(2), .volume(40)] && !state.muted,
                     "unmuting by the mute code sends 2 and then the level, so it is not left unpredictable")
        var silent = MonitorVolumeSupport.State(level: 0)
        _ = silent.toggleMute(method: .volumeZero)
        let restored = silent.toggleMute(method: .volumeZero)
        suite.expect(silent.level == MonitorVolumeSupport.unmuteFloor && restored == [.volume(6)],
                     "unmuting from a level of zero comes back at the floor, so it is heard")
        var held = MonitorVolumeSupport.State(level: 0.5)
        _ = held.toggleMute(method: .volumeZero)
        let moved = held.step(delta: MonitorVolumeSupport.keyStep, method: .volumeZero)
        suite.expect(!held.muted && held.level == 0.5625 && moved == [.volume(56)],
                     "a volume key while muted unmutes at the stepped level")
        var coded = MonitorVolumeSupport.State(level: 0.5)
        _ = coded.toggleMute(method: .muteCode)
        let slid = coded.set(level: 0.7, method: .muteCode)
        suite.expect(!coded.muted && slid == [.mute(2), .volume(70)], "moving the slider while muted by code unmutes first")
        var manual = MonitorVolumeSupport.State(level: 0.5)
        _ = manual.toggleMute(method: .volumeZero)
        _ = manual.set(level: 0.2, method: .volumeZero)
        suite.expect(manual.level == 0.2 && !manual.muted,
                     "a level set while muted replaces the remembered one, so the last level is never written over by an older one")
    }

    private static func keys(_ suite: TestSuite) {
        func data1(_ key: Int, state: Int, repeating: Bool = false) -> Int { key << 16 | state << 8 | (repeating ? 1 : 0) }
        suite.expect(MonitorVolumeSupport.keyPress(subtype: 8, data1: data1(0, state: 0x0A)) == .init(key: .up, isDown: true, isRepeat: false)
                     && MonitorVolumeSupport.keyPress(subtype: 8, data1: data1(1, state: 0x0A))?.key == .down
                     && MonitorVolumeSupport.keyPress(subtype: 8, data1: data1(7, state: 0x0A))?.key == .mute
                     && MonitorVolumeSupport.keyPress(subtype: 8, data1: data1(0, state: 0x0B))?.isDown == false
                     && MonitorVolumeSupport.keyPress(subtype: 8, data1: data1(1, state: 0x0A, repeating: true))?.isRepeat == true,
                     "volume up, down and mute are read from the media key event, down or up, repeating or not")
        suite.expect(MonitorVolumeSupport.keyPress(subtype: 8, data1: data1(2, state: 0x0A)) == nil
                     && MonitorVolumeSupport.keyPress(subtype: 8, data1: data1(3, state: 0x0A)) == nil
                     && MonitorVolumeSupport.keyPress(subtype: 7, data1: data1(0, state: 0x0A)) == nil
                     && MonitorVolumeSupport.keyPress(subtype: 8, data1: data1(0, state: 0x05)) == nil,
                     "brightness keys, other event kinds and other key states are not volume keys")
        suite.expect(BrightnessSupport.brightnessKeyEvent(subtype: 8, data1: data1(0, state: 0x0A)) == nil
                     && BrightnessSupport.brightnessKeyEvent(subtype: 8, data1: data1(1, state: 0x0A)) == nil,
                     "a volume key is never taken for a brightness key")
    }

    private static func targets(_ suite: TestSuite) {
        let one = [MonitorVolumeSupport.Candidate(id: 3, name: "Odyssey G73SH")]
        suite.expect(MonitorVolumeSupport.target(outputIsDisplayAudio: true, outputName: "Odyssey G73SH",
                                                 candidates: one, pointerDisplay: 1) == 3,
                     "the monitor the Mac plays through gets the keys wherever the pointer is")
        suite.expect(MonitorVolumeSupport.target(outputIsDisplayAudio: false, outputName: "Odyssey G73SH",
                                                 candidates: one, pointerDisplay: 3) == nil,
                     "a sound output that is not a display's, such as the Mac's speakers, keeps the system's keys")
        suite.expect(MonitorVolumeSupport.target(outputIsDisplayAudio: true, outputName: "Other TV",
                                                 candidates: one, pointerDisplay: 3) == nil
                     && MonitorVolumeSupport.target(outputIsDisplayAudio: true, outputName: nil,
                                                    candidates: one, pointerDisplay: 3) == nil
                     && MonitorVolumeSupport.target(outputIsDisplayAudio: true, outputName: "Odyssey G73SH",
                                                    candidates: [], pointerDisplay: 3) == nil,
                     "a display output that names no monitor offered, or no monitor offered at all, is left to the system")
        suite.expect(MonitorVolumeSupport.target(outputIsDisplayAudio: true, outputName: " odyssey g73sh ",
                                                 candidates: one, pointerDisplay: nil) == 3,
                     "the output and the monitor match by name regardless of case and spacing")
        let two = [MonitorVolumeSupport.Candidate(id: 3, name: "DELL U2723QE"),
                   MonitorVolumeSupport.Candidate(id: 5, name: "DELL U2723QE")]
        suite.expect(MonitorVolumeSupport.target(outputIsDisplayAudio: true, outputName: "DELL U2723QE",
                                                 candidates: two, pointerDisplay: 5) == 5
                     && MonitorVolumeSupport.target(outputIsDisplayAudio: true, outputName: "DELL U2723QE",
                                                    candidates: two, pointerDisplay: 1) == 3,
                     "two monitors with one name are told apart by the pointer, and the first takes it when the pointer is elsewhere")
        let mixed = [MonitorVolumeSupport.Candidate(id: 3, name: "Odyssey G73SH"),
                     MonitorVolumeSupport.Candidate(id: 5, name: "DELL U2723QE")]
        suite.expect(MonitorVolumeSupport.target(outputIsDisplayAudio: true, outputName: "DELL U2723QE",
                                                 candidates: mixed, pointerDisplay: 3) == 5,
                     "with several monitors the one whose speakers play gets the keys, not the one under the pointer")
    }

    private static func memory(_ suite: TestSuite) {
        let a = MonitorVolumeSupport.State(level: 0.2)
        var stored = MonitorVolumeSupport.updatedStates([:], fingerprint: "a", state: a)
        stored = MonitorVolumeSupport.updatedStates(stored, fingerprint: "b", state: .init(level: 0.6, muted: true))
        suite.expect(stored["a"] == a && stored["b"]?.muted == true, "each monitor keeps its own level and mute")
        suite.expect(MonitorVolumeSupport.updatedStates(stored, fingerprint: "", state: a) == stored,
                     "a monitor with no identity is not remembered")
        var many: [String: MonitorVolumeSupport.State] = [:]
        for index in 0..<40 { many = MonitorVolumeSupport.updatedStates(many, fingerprint: "m\(index)", state: a, limit: 16) }
        suite.expect(many.count == 16, "what is remembered stays bounded")
        let data = try? JSONEncoder().encode(stored)
        suite.expect(data.flatMap { try? JSONDecoder().decode([String: MonitorVolumeSupport.State].self, from: $0) } == stored,
                     "the remembered levels survive being saved and read back")
    }

    private static func offering(_ suite: TestSuite) {
        suite.expect(MonitorVolumeSupport.isOffered(volumeReplied: true, chosenByPerson: false, hasDDCRoute: true),
                     "a monitor that answered a reading of 0x62 is offered")
        suite.expect(!MonitorVolumeSupport.isOffered(volumeReplied: false, chosenByPerson: false, hasDDCRoute: true),
                     "a monitor that gave no reading, which proves nothing either way, is not offered until a person turns it on")
        suite.expect(MonitorVolumeSupport.isOffered(volumeReplied: false, chosenByPerson: true, hasDDCRoute: true),
                     "a monitor a person turned the volume on for is offered")
        suite.expect(!MonitorVolumeSupport.isOffered(volumeReplied: true, chosenByPerson: true, hasDDCRoute: false),
                     "a display without a DDC channel, one that was unplugged or runs on the system pipeline, is never offered")
    }
}
