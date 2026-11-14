// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

/// The decisions behind switching a monitor's input over DDC, away from the
/// hardware: which inputs a monitor says it has, which one comes next, which
/// monitor a press is for and how the capability string is read back.
enum MonitorInputTests {
    /// What a Samsung monitor answered to Get Capabilities requests on a real
    /// Mac, by offset, byte for byte. The parser is checked against what
    /// hardware sends rather than against what the code expects. The last
    /// reply has no data: that is how a monitor ends its string.
    static let samsungReplies: [Int: [UInt8]] = [
        0: [0x6E, 0xA3, 0xE3, 0x00, 0x00, 0x28, 0x70, 0x72, 0x6F, 0x74, 0x28, 0x6D, 0x6F, 0x6E, 0x69, 0x74, 0x6F, 0x72, 0x29, 0x74, 0x79, 0x70, 0x65, 0x28, 0x6C, 0x63, 0x64, 0x29, 0x6D, 0x6F, 0x64, 0x65, 0x6C, 0x28, 0x53, 0x45, 0x43, 0x42],
        32: [0x6E, 0xA3, 0xE3, 0x00, 0x20, 0x29, 0x63, 0x6D, 0x64, 0x73, 0x28, 0x30, 0x31, 0x20, 0x30, 0x32, 0x20, 0x30, 0x33, 0x20, 0x30, 0x37, 0x20, 0x30, 0x43, 0x20, 0x45, 0x33, 0x20, 0x46, 0x33, 0x29, 0x76, 0x63, 0x70, 0x28, 0x30, 0x65],
        64: [0x6E, 0xA3, 0xE3, 0x00, 0x40, 0x32, 0x20, 0x30, 0x34, 0x20, 0x30, 0x35, 0x20, 0x30, 0x38, 0x20, 0x31, 0x30, 0x20, 0x31, 0x32, 0x20, 0x31, 0x34, 0x28, 0x30, 0x35, 0x20, 0x30, 0x38, 0x20, 0x30, 0x42, 0x20, 0x30, 0x43, 0x29, 0x2F],
        96: [0x6E, 0xA3, 0xE3, 0x00, 0x60, 0x20, 0x31, 0x36, 0x20, 0x31, 0x38, 0x20, 0x31, 0x41, 0x20, 0x35, 0x32, 0x20, 0x36, 0x30, 0x28, 0x31, 0x31, 0x20, 0x30, 0x46, 0x20, 0x29, 0x20, 0x36, 0x32, 0x20, 0x38, 0x37, 0x20, 0x38, 0x44, 0x61],
        128: [0x6E, 0xA3, 0xE3, 0x00, 0x80, 0x20, 0x43, 0x43, 0x20, 0x6D, 0x73, 0x77, 0x68, 0x71, 0x6C, 0x28, 0x31, 0x29, 0x6D, 0x63, 0x63, 0x73, 0x5F, 0x76, 0x65, 0x72, 0x28, 0x32, 0x2E, 0x30, 0x29, 0x61, 0x73, 0x73, 0x65, 0x74, 0x5F, 0xF0],
        160: [0x6E, 0x96, 0xE3, 0x00, 0xA0, 0x65, 0x65, 0x70, 0x28, 0x33, 0x32, 0x29, 0x6D, 0x70, 0x75, 0x5F, 0x76, 0x65, 0x72, 0x28, 0x30, 0x31, 0x29, 0x29, 0xE4],
        179: [0x6E, 0x83, 0xE3, 0x00, 0xB3, 0xED],
    ]
    /// The string those replies add up to. It has one closing parenthesis
    /// fewer than it opens, as some firmware sends it.
    static let samsungCapabilities = "(prot(monitor)type(lcd)model(SEC)cmds(01 02 03 07 0C E3 F3)"
        + "vcp(02 04 05 08 10 12 14(05 08 0B 0C) 16 18 1A 52 60(11 0F ) 62 87 8D CC mswhql(1)"
        + "mccs_ver(2.0)asset_eep(32)mpu_ver(01))"

    /// A reply buffer as the bus hands it back: the message, then padding.
    private static func padded(_ reply: [UInt8]) -> [UInt8] {
        reply + [UInt8](repeating: 0, count: max(0, MonitorInputSupport.capabilitiesReplyLength - reply.count))
    }

    static func run(_ suite: TestSuite) {
        inputNames(suite)
        supportedInputs(suite)
        inputValue(suite)
        nextInput(suite)
        plan(suite)
        switchResult(suite)
        pickerMonitors(suite)
        targetDisplay(suite)
        serviceMatching(suite)
        capabilityReplies(suite)
        capabilityTransport(suite)
        packets(suite)
        shortcutRole(suite)
        strings(suite)
        serviceWiring(suite)
    }

    private static func inputNames(_ suite: TestSuite) {
        suite.expect(MonitorInputSupport.name(of: 0x0F) == "DisplayPort 1"
                && MonitorInputSupport.name(of: 0x10) == "DisplayPort 2"
                && MonitorInputSupport.name(of: 0x11) == "HDMI 1"
                && MonitorInputSupport.name(of: 0x12) == "HDMI 2",
               "the video inputs MCCS defines are named the way the monitor's own menu names them")
        suite.expect(MonitorInputSupport.name(of: 0x01) == "VGA 1" && MonitorInputSupport.name(of: 0x03) == "DVI 1",
               "the older connectors keep their names")
        suite.expect(MonitorInputSupport.name(of: 0x1B) == "Input 0x1B"
                && MonitorInputSupport.name(of: 0x99) == "Input 0x99",
               "a value the standard does not define is shown as the number the monitor reports, not guessed")
    }

    private static func supportedInputs(_ suite: TestSuite) {
        suite.expect(MonitorInputSupport.supportedInputs(fromCapabilities: samsungCapabilities) == [0x0F, 0x11],
               "the Samsung's own capability string lists DisplayPort 1 and HDMI 1")
        suite.expect(MonitorInputSupport.supportedInputs(
                fromCapabilities: "(vcp(02 04 60(12 0F 11 10 11) 62))") == [0x0F, 0x10, 0x11, 0x12],
               "inputs come back sorted and without repeats, whatever order the monitor lists them in")
        suite.expect(MonitorInputSupport.supportedInputs(fromCapabilities: "(vcp(60(0f 11)))") == [0x0F, 0x11],
               "hex digits are read in either case")
        suite.expect(MonitorInputSupport.supportedInputs(fromCapabilities: "(vcp(02 04 10 12))").isEmpty
                && MonitorInputSupport.supportedInputs(fromCapabilities: "(vcp(60 62))").isEmpty
                && MonitorInputSupport.supportedInputs(fromCapabilities: "(prot(monitor)type(lcd))").isEmpty
                && MonitorInputSupport.supportedInputs(fromCapabilities: "").isEmpty,
               "a monitor that does not list its inputs reports none")
        suite.expect(MonitorInputSupport.supportedInputs(fromCapabilities: "(vcp(14(60 0F) 62))").isEmpty,
               "60 as a value of another control is not the input control")
        suite.expect(MonitorInputSupport.supportedInputs(
                fromCapabilities: "(vcp(E0(01(02 03)) 60(11) 62))") == [0x11],
               "controls nested deeper are skipped without losing the input list")
        suite.expect(MonitorInputSupport.supportedInputs(fromCapabilities: "(vcp(60(zz 11 1234)))") == [0x11],
               "a value that is not one hex byte is ignored")
        suite.expect(MonitorInputSupport.supportedInputs(fromCapabilities: "(VCP(60(11 0F)))") == [0x0F, 0x11],
               "the vcp section is found in either case")
    }

    private static func inputValue(_ suite: TestSuite) {
        suite.expect(MonitorInputSupport.inputValue(fromReply: 0x000F) == 0x0F
                && MonitorInputSupport.inputValue(fromReply: 0x010F) == 0x0F
                && MonitorInputSupport.inputValue(fromReply: 0xFF11) == 0x11,
               "an input is the low byte of what the monitor reports: the high byte is reserved and some monitors fill it")
    }

    private static func nextInput(_ suite: TestSuite) {
        suite.expect(MonitorInputSupport.nextInput(after: 0x0F, among: [0x0F, 0x11]) == 0x11
                && MonitorInputSupport.nextInput(after: 0x11, among: [0x0F, 0x11]) == 0x0F,
               "with two inputs the shortcut goes to the other one, both ways")
        suite.expect(MonitorInputSupport.nextInput(after: 0x12, among: [0x0F, 0x11, 0x12]) == 0x0F
                && MonitorInputSupport.nextInput(after: 0x0F, among: [0x0F, 0x11, 0x12]) == 0x11,
               "with more inputs it cycles and wraps around")
        suite.expect(MonitorInputSupport.nextInput(after: 0x0F, among: [0x0F]) == nil
                && MonitorInputSupport.nextInput(after: 0x0F, among: []) == nil,
               "a monitor with one input, or none listed, has nowhere to go")
        suite.expect(MonitorInputSupport.nextInput(after: nil, among: [0x0F, 0x11]) == nil,
               "when the current input cannot be read the shortcut does not guess")
        suite.expect(MonitorInputSupport.nextInput(after: 0x10, among: [0x0F, 0x11]) == 0x11
                && MonitorInputSupport.nextInput(after: 0x20, among: [0x0F, 0x11]) == 0x0F,
               "an input missing from the list moves to the next listed value, or to the first")
    }

    private static func plan(_ suite: TestSuite) {
        suite.expect(MonitorInputSupport.plan(current: 0x0F, supported: [0x0F, 0x11]) == .switchTo(0x11)
                && MonitorInputSupport.plan(current: 0x10, supported: [0x0F, 0x11]) == .switchTo(0x11),
               "a press with a readable input and another one listed moves to the next input")
        suite.expect(MonitorInputSupport.plan(current: 0x0F, supported: []) == .unreadable
                && MonitorInputSupport.plan(current: nil, supported: [0x0F, 0x11]) == .unreadable
                && MonitorInputSupport.plan(current: nil, supported: []) == .unreadable,
               "a monitor that does not tell its inputs, or the one it shows, is reported as unreadable instead of guessed at")
        suite.expect(MonitorInputSupport.plan(current: 0x0F, supported: [0x0F]) == .noOtherInput
                && MonitorInputSupport.plan(current: nil, supported: [0x0F]) == .noOtherInput
                && MonitorInputSupport.plan(current: 0x0F, supported: [0x0F, 0x0F]) == .noOtherInput,
               "a monitor that lists a single input has none to move to, whatever it shows")
    }

    private static func switchResult(_ suite: TestSuite) {
        suite.expect(MonitorInputSupport.result(readings: [0x0F, 0x11], target: 0x11) == .switched
                && MonitorInputSupport.result(readings: [nil, 0x11], target: 0x11) == .switched,
               "the switch counts as done as soon as a read shows the wanted input")
        suite.expect(MonitorInputSupport.result(readings: [0x0F, 0x0F, 0x0F, 0x0F], target: 0x11) == .notSwitched
                && MonitorInputSupport.result(readings: [nil, 0x0F], target: 0x11) == .notSwitched,
               "a monitor that keeps answering with the old input did not switch")
        suite.expect(MonitorInputSupport.result(readings: [nil, nil, nil, nil], target: 0x11) == .unknown
                && MonitorInputSupport.result(readings: [], target: 0x11) == .unknown,
               "a monitor that never answers again is not reported as failed: nobody saw it refuse")
        let window = Double(MonitorInputSupport.confirmationReads) * MonitorInputSupport.confirmationInterval
        suite.expect(window >= 6 && window <= 12,
               "the wait for the confirmation outlasts the two to four seconds the Samsung took and still ends")
    }

    private static func pickerMonitors(_ suite: TestSuite) {
        suite.expect(MonitorInputSupport.pickerMonitor(id: 3, name: "Odyssey", current: 0x0F,
                                                       supported: [0x11, 0x0F, 0x11])
                == MonitorInputSupport.Monitor(id: 3, name: "Odyssey", current: 0x0F, inputs: [0x0F, 0x11]),
               "a monitor that answered is listed with its inputs sorted and without repeats")
        suite.expect(MonitorInputSupport.pickerMonitor(id: 3, name: "X", current: nil, supported: [0x0F, 0x11]) == nil
                && MonitorInputSupport.pickerMonitor(id: 3, name: "X", current: 0x0F, supported: [0x0F]) == nil
                && MonitorInputSupport.pickerMonitor(id: 3, name: "X", current: 0x0F, supported: []) == nil,
               "a monitor that did not say which input it shows, or has nothing to choose from, is not listed")
        suite.expect(MonitorInputSupport.pickerMonitor(id: 3, name: "X", current: 0x10,
                                                       supported: [0x0F, 0x11])?.inputs == [0x0F, 0x10, 0x11],
               "an input the monitor shows but did not list is still offered, so the picker can show it selected")
    }

    private static func targetDisplay(_ suite: TestSuite) {
        suite.expect(MonitorInputSupport.targetDisplay(pointerDisplay: 7, candidates: [3, 7]) == 7,
               "the monitor under the pointer is the one switched")
        suite.expect(MonitorInputSupport.targetDisplay(pointerDisplay: 1, candidates: [3]) == 3
                && MonitorInputSupport.targetDisplay(pointerDisplay: nil, candidates: [3]) == 3,
               "the only monitor that can switch is the target even with the pointer elsewhere")
        suite.expect(MonitorInputSupport.targetDisplay(pointerDisplay: 1, candidates: [3, 7]) == nil
                && MonitorInputSupport.targetDisplay(pointerDisplay: nil, candidates: [3, 7]) == nil,
               "with several monitors and the pointer on none of them nothing is switched")
        suite.expect(MonitorInputSupport.targetDisplay(pointerDisplay: 3, candidates: []) == nil,
               "no monitor, no target")
    }

    private static func serviceMatching(_ suite: TestSuite) {
        suite.expect(MonitorInputSupport.serviceOrdinal(for: 0, scores: [(0, 5, 0)], displayCount: 1,
                                                        serviceOrdinals: [5]) == 5,
               "one monitor and one DDC service can only belong to each other")
        let both = [(displayIndex: 0, serviceOrdinal: 1, score: 12), (0, 2, 0), (1, 1, 0), (1, 2, 12)]
        suite.expect(MonitorInputSupport.serviceOrdinal(for: 0, scores: both, displayCount: 2,
                                                        serviceOrdinals: [1, 2]) == 1
                && MonitorInputSupport.serviceOrdinal(for: 1, scores: both, displayCount: 2,
                                                      serviceOrdinals: [1, 2]) == 2,
               "with two monitors each gets its own service when the match is clear")
        let tie = [(displayIndex: 0, serviceOrdinal: 1, score: 2), (0, 2, 2), (1, 1, 2), (1, 2, 2)]
        suite.expect(MonitorInputSupport.serviceOrdinal(for: 0, scores: tie, displayCount: 2,
                                                        serviceOrdinals: [1, 2]) == nil,
               "two identical monitors are never told apart by guessing: the wrong one would switch")
        suite.expect(MonitorInputSupport.serviceOrdinal(for: 0, scores: [(0, 1, 1), (1, 2, 1)], displayCount: 2,
                                                        serviceOrdinals: [1, 2]) == nil,
               "a weak match between several monitors is refused")
    }

    private static func capabilityReplies(_ suite: TestSuite) {
        let first = MonitorInputSupport.parseCapabilitiesReply(padded(samsungReplies[0] ?? []), offset: 0)
        suite.expect(first.map { String(decoding: $0, as: UTF8.self) } == "(prot(monitor)type(lcd)model(SEC",
               "a real first fragment gives its 32 bytes of text")
        let last = MonitorInputSupport.parseCapabilitiesReply(padded(samsungReplies[160] ?? []), offset: 160)
        suite.expect(last.map { String(decoding: $0, as: UTF8.self) } == "eep(32)mpu_ver(01))",
               "a shorter last fragment gives only its own bytes")
        suite.expect(MonitorInputSupport.parseCapabilitiesReply(padded(samsungReplies[179] ?? []), offset: 179)?.isEmpty
                == true,
               "the reply without data, which ends the string, reads as an empty fragment")
        suite.expect(MonitorInputSupport.parseCapabilitiesReply(padded(samsungReplies[0] ?? []), offset: 32) == nil,
               "a reply for another offset is a stale answer, not this one")
        var corrupt = padded(samsungReplies[0] ?? [])
        corrupt[10] ^= 0x01
        suite.expect(MonitorInputSupport.parseCapabilitiesReply(corrupt, offset: 0) == nil,
               "a reply whose checksum does not add up is dropped")
        var wrongOpcode = padded(samsungReplies[0] ?? [])
        wrongOpcode[2] = 0x02
        suite.expect(MonitorInputSupport.parseCapabilitiesReply(wrongOpcode, offset: 0) == nil
                && MonitorInputSupport.parseCapabilitiesReply([UInt8](repeating: 0, count: 40), offset: 0) == nil
                && MonitorInputSupport.parseCapabilitiesReply([0x6E, 0x83], offset: 0) == nil,
               "anything that is not a capabilities reply reads as no reply")
    }

    private static func capabilityTransport(_ suite: TestSuite) {
        let fetch: (Int) -> [UInt8]? = { offset in
            MonitorInputSupport.parseCapabilitiesReply(padded(samsungReplies[offset] ?? []), offset: offset)
        }
        suite.expect(MonitorInputSupport.capabilities(fetch: fetch) == samsungCapabilities,
               "the fragments of a real monitor add up to its whole capability string")
        var asked: [Int] = []
        _ = MonitorInputSupport.capabilities(fetch: { offset in asked.append(offset); return fetch(offset) })
        suite.expect(asked == [0, 32, 64, 96, 128, 160, 179],
               "each request asks from the end of what was already received")
        suite.expect(MonitorInputSupport.capabilities(fetch: { _ in nil }) == nil,
               "a monitor that never answers has no capability string")
        let partial: (Int) -> [UInt8]? = { offset in
            offset == 0 ? Array("(prot(monitor)type(lcd)model(SEC".utf8) : nil
        }
        suite.expect(MonitorInputSupport.capabilities(fetch: partial) == nil,
               "a string cut off before the inputs is not used")
        let cutAfterInputs: (Int) -> [UInt8]? = { offset in
            offset == 0 ? Array("(prot(monitor)vcp(02 60(11 0F) 62".utf8) : nil
        }
        suite.expect(MonitorInputSupport.capabilities(fetch: cutAfterInputs) == "(prot(monitor)vcp(02 60(11 0F) 62",
               "a string cut off after a complete input list is still good for switching")
        var requests = 0
        let endless: (Int) -> [UInt8]? = { _ in requests += 1; return Array("(a)".utf8) }
        suite.expect(MonitorInputSupport.capabilities(fetch: endless) == nil
                && requests <= MonitorInputSupport.maximumCapabilityFragments,
               "a monitor that never ends its string is given up on after a bounded number of requests")
    }

    private static func packets(_ suite: TestSuite) {
        suite.expect(MonitorInputSupport.capabilitiesRequestPacket(offset: 0) == [0x83, 0xF3, 0x00, 0x00, 0x4F]
                && MonitorInputSupport.capabilitiesRequestPacket(offset: 32) == [0x83, 0xF3, 0x00, 0x20, 0x6F]
                && MonitorInputSupport.capabilitiesRequestPacket(offset: 0x0120) == [0x83, 0xF3, 0x01, 0x20, 0x6E],
               "the capabilities request carries its offset big-endian and the standard checksum")
        suite.expect(MonitorInputSupport.setInputPacket(0x11) == [0x84, 0x03, 0x60, 0x00, 0x11, 0xC9]
                && MonitorInputSupport.setInputPacket(0x0F) == BrightnessSupport.writePacket(code: 0x60, value: 0x0F),
               "setting the input is the ordinary Set VCP Feature packet for control 0x60")
        suite.expect(MonitorInputSupport.getInputPacket == BrightnessSupport.readRequestPacket(code: 0x60),
               "reading the input is the ordinary Get VCP Feature request for control 0x60")
    }

    private static func shortcutRole(_ suite: TestSuite) {
        let role = GlobalShortcutRole.monitorInput
        suite.expect(role.feature == .brightness && role.group == .energyDisplay,
               "the shortcut appears with the display controls")
        suite.expect(role.requiredEnableKeys
                == [DefaultsKey.brightnessControlEnabled, DefaultsKey.monitorInputShortcutEnabled],
               "the shortcut needs the brightness control and its own switch")
        suite.expect(role.defaultShortcut == GlobalShortcut(keyCode: Int64(kVK_ANSI_X),
                                                            modifiers: [.control, .option, .command]),
               "the shortcut ships on control-option-command-X")
        suite.expect((Defaults.registeredDefaults[DefaultsKey.monitorInputShortcutEnabled] as? Bool) == false,
               "the shortcut ships off")
        suite.expect((Defaults.registeredDefaults[role.storageKey] as? String) == role.defaultShortcut.storageValue,
               "the shortcut's default is registered under its own key")
        suite.expect(GlobalShortcutRole.conflict(for: role.defaultShortcut, excluding: role, isOn: { _ in true },
                                                 isAvailable: { _ in true }, includeInactive: true) == nil,
               "no other shortcut ships on the same keys")
        suite.expect(GlobalShortcutRole.activeRoles(isOn: { _ in true }).contains(role),
               "with both switches on the shortcut is active")
        suite.expect(!GlobalShortcutRole.activeRoles(isOn: { $0 != DefaultsKey.monitorInputShortcutEnabled })
                        .contains(role)
                && !GlobalShortcutRole.activeRoles(isOn: { $0 != DefaultsKey.brightnessControlEnabled })
                        .contains(role),
               "turning either switch off releases the keys")
        suite.expect(!GlobalShortcutRole.activeRoles(isOn: { _ in true }, isAvailable: { $0 != .brightness })
                        .contains(role),
               "the shortcut follows the availability of the brightness feature")
    }

    /// The service is not part of this test binary, so what keeps a press from
    /// reaching the wrong monitor, or the bus from the wrong thread, is pinned
    /// at its source.
    private static func serviceWiring(_ suite: TestSuite) {
        let path = "Sources/Vorssaint/Services/Display/BrightnessService.swift"
        let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        /// A method of the service, from its signature to the closing brace at
        /// the method's own indentation.
        func method(_ signature: String) -> String {
            guard let start = source.range(of: signature),
                  let end = source.range(of: "\n    }\n", range: start.upperBound..<source.endIndex)
            else { return "" }
            return String(source[start.lowerBound..<end.upperBound])
        }
        let press = method("private func switchMonitorInput()")
        suite.expect(!press.isEmpty && ["running", "AppFeature.brightness.isAvailable", "SessionActivity.shared.isActive",
                                        "DefaultsKey.monitorInputShortcutEnabled", "!monitorInputBusy"]
                        .allSatisfy { press.contains($0) },
               "a press does nothing unless brightness is on and running, the session is active, the shortcut is on and no change is in flight")

        suite.expect(method("func syncWithPreferences()").contains("syncMonitorInputHotkey()")
                && method("func stop()").contains("monitorInputHotkey.unregister()"),
               "the shortcut is registered with the other brightness shortcuts and released when brightness stops")

        var idOwners = 0
        let sources = FileManager.default.enumerator(atPath: "Sources/Vorssaint")?
            .compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") } ?? []
        for file in sources {
            let text = (try? String(contentsOfFile: "Sources/Vorssaint/" + file, encoding: .utf8)) ?? ""
            idOwners += text.components(separatedBy: "QuickToolHotkey(id: 64)").count - 1
        }
        suite.expect(idOwners == 1 && source.contains("monitorInputHotkey = QuickToolHotkey(id: 64)"),
               "hotkey 64 belongs to the monitor input alone, so no other shortcut is taken over by it")

        let targets = method("private func monitorInputTargets()")
        suite.expect(!targets.isEmpty && targets.contains("requireIdentity: true")
                && targets.contains("MonitorInputSupport.serviceOrdinal(")
                && !targets.contains("assignServices("),
               "a monitor is given a service only on a clear match: the brightness scan's looser assignment is not used")

        let write = method("private func writeMonitorInput(")
        suite.expect(write.contains("ddcSend(to: target.id") && write.contains("MonitorInputSupport.setInputPacket(value)"),
               "the input is written through the paced DDC write, not a side channel")
        let queueHalf = source.components(separatedBy: "// MARK: - Rebuild (work queue)").last ?? ""
        suite.expect(["private func moveToNextInput(", "private func writeMonitorInput(",
                      "private func monitorInputState(", "private func ddcCapabilitiesFragment(",
                      "private func monitorInputTargets("].allSatisfy { queueHalf.contains($0) },
               "everything that talks to the monitor sits in the half of the service that runs on the work queue")
        suite.expect(method("private func carryOutMonitorInputChange(").contains("workQueue.async"),
               "a press or a pick reaches the bus from the work queue, never from the main thread")

        let outcome = method("private func showMonitorInputOutcome(")
        if let name = outcome.range(of: "QuickToolHUD.show(icon: \"display\", message: MonitorInputSupport.name(of: value))"),
           let confirm = outcome.range(of: "confirmMonitorInput(") {
            suite.expect(name.lowerBound < confirm.lowerBound,
                   "the new input is named on the monitor before the wait for the confirmation starts")
        } else {
            suite.expect(false, "the outcome shows the new input and then confirms it")
        }
        suite.expect(method("private func confirmMonitorInput(").contains("generation == self.monitorInputGeneration"),
               "a confirmation that a newer press overtook ends without a word")

        suite.expect(method("private func monitorInputState(").contains("MonitorInputSupport.inputValue(fromReply: reported)")
                && method("private func confirmMonitorInput(").contains("MonitorInputSupport.inputValue(fromReply: reported)"),
               "both reads of the input, the one before a switch and the one that confirms it, use its low byte")
        let state = method("private func monitorInputState(")
        if let read = state.range(of: "ddcProbe("), let ask = state.range(of: "MonitorInputSupport.capabilities(") {
            suite.expect(read.lowerBound < ask.lowerBound && state.contains("let cached = monitorInputCapabilities[key]")
                    && state.contains("monitorInputCapabilities[key] = inputs"),
                   "the input is read before the list is asked for, and the list is asked for once per connection")
        } else {
            suite.expect(false, "the state reads the input and then the capability list")
        }
    }

    private static func strings(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let text = FeatureStrings.brightness(language)
            let all = [text.monitorInputShortcut, text.monitorInputShortcutCaption, text.monitorInputNoMonitor,
                       text.monitorInputUnreadable, text.monitorInputNoOther, text.monitorInputNotSwitched,
                       text.monitorInputPickerEmpty, text.monitorInputPointAtMonitor]
            suite.expect(all.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                   "\(language.rawValue) words every message of the monitor input switch")
        }
        suite.expect(GlobalShortcutRole.monitorInput.title(L10n.shared.s)
                == FeatureStrings.brightness(L10n.shared.language).monitorInputShortcut,
               "the shortcut list names the shortcut with the same words as its settings row")
    }
}
