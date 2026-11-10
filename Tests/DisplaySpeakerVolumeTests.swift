// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// Production discovery, queue, transaction and mixer entry points against
/// a controlled DDC transport, default output and main queue.
enum DisplaySpeakerVolumeTests {
    typealias DispatchQueue = MixerOutputAdjustmentContract.DispatchQueue
    typealias Queue = MixerOutputAdjustmentContract.Queue
    struct BrightnessDisplay {
        struct Audio: Equatable {
            let target: BrightnessSupport.SpeakerTarget
            var volume: Double
            var muted: Bool?
        }
        let id: UInt32
        var name: String
        var isBuiltIn = false
        var isActive = true
        var audio: Audio?
    }
    enum AppVolumeMixer {
        static func hasSettableOutputVolume(for device: AudioObjectID) -> Bool { Service.shared.settable }
    }
    enum UserDefaults {
        static let standard = UserDefaults.self
        static func bool(forKey key: String) -> Bool {
            key == DefaultsKey.displayVolumeKeysEnabled && Service.shared.wantsMonitorVolumeKeys
        }
    }
    static func CGDisplayIsActive(_ id: UInt32) -> UInt32 { 1 }
    static func CGDisplayIsAsleep(_ id: UInt32) -> UInt32 { 0 }
    struct Write: Equatable {
        let code: UInt8
        let value: UInt16
        init(_ code: UInt8, _ value: UInt16) { self.code = code; self.value = value }
    }
    class Fixture {
        let stateLock = NSLock()
        let workQueue = Queue()
        var running = true
        var wantsMonitorVolume = true
        var wantsMonitorVolumeKeys = true
        var monitorVolumeKeySettings = MonitorVolumeKeySettings()
        var displayPowerIsSuspended = false
        var displays: [BrightnessDisplay] = [] { didSet { onDisplayChange?() } }
        var onDisplayChange: (() -> Void)?
        var hiddenDisplays: [(id: UInt32, name: String)] = []
        var audioDisplayNames: [(id: UInt32, name: String)] {
            displays.filter { !$0.isBuiltIn }.map { ($0.id, $0.name) } + hiddenDisplays
        }
        var audioRoutes: [UInt32: AudioRoute] = [:]
        var speakerRestoreLevels: [String: BrightnessSupport.SpeakerLevel] = [:]
        var audioLifetime: UInt64 = 0
        var speakerLevelRevisions: [String: UInt64] = [:]
        var pendingAudio: [PendingAudio] = []
        var audioWriteInFlight = false
        var audioOutputGeneration = 0
        var selectedAudioOutput: (id: AudioObjectID, name: String)? = (31, "Monitor A")
        var actualDevice: AudioObjectID = 31
        var settable = false
        var raw: UInt16 = 40
        var maximum: UInt16 = 100
        var nativeMuted: Bool?
        var rejectVolume = false
        var ignoreVolume = false
        var onSend: (() -> Void)?
        var afterSend: (() -> Void)?
        var onRead: (() -> Void)?
        var volumeOnUnmute: UInt16?
        var writes: [Write] = []
        var writtenIDs: [UInt32] = []
        var refreshes = 0
        var silentPaths: Set<String> = []

        static func defaultOutputDevice() -> (id: AudioObjectID, name: String, transport: UInt32)? {
            (Service.shared.actualDevice, Service.shared.selectedAudioOutput?.name ?? "", kAudioDeviceTransportTypeHDMI)
        }
        static func restorationDisplayFingerprint(_ id: UInt32) -> String? { "fixture-identity" }
        func refresh(force: Bool) { refreshes += 1 }
        func rescanForUnclaimedVolumeKey() { refreshes += 1 }
        func rememberedPaths(_ key: String) -> Set<String> { silentPaths }
        func rememberPath(_ path: String, key: String, remembered: Bool) { silentPaths.insert(path) }
        func ddcProbe(_ code: UInt8, for id: UInt32, service: CFTypeRef) -> DDCProbe {
            onRead?()
            if code == BrightnessSupport.audioVolumeCode { return .replied(current: raw, maximum: maximum) }
            guard code == BrightnessSupport.audioMuteCode, let nativeMuted else { return .dead }
            return .replied(current: nativeMuted ? 1 : 2, maximum: 2)
        }
        func ddcSend(to id: UInt32, service: CFTypeRef, packet: [UInt8], whileCurrent: () -> Bool) -> Bool {
            onSend?()
            guard whileCurrent() else { return false }
            let code = packet[2], value = UInt16(packet[3]) << 8 | UInt16(packet[4])
            writes.append(Write(code, value))
            writtenIDs.append(id)
            if code == BrightnessSupport.audioVolumeCode {
                guard !rejectVolume else { return false }
                if !ignoreVolume { raw = value }
            } else if code == BrightnessSupport.audioMuteCode, nativeMuted != nil {
                nativeMuted = value == 1
                if value == 2, let volumeOnUnmute { raw = volumeOnUnmute }
            } else { return false }
            let after = afterSend
            afterSend = nil
            after?()
            return true
        }
        func finish() {
            while !workQueue.jobs.isEmpty || !DispatchQueue.main.jobs.isEmpty {
                if !workQueue.jobs.isEmpty { workQueue.runOne() }
                if !DispatchQueue.main.jobs.isEmpty { DispatchQueue.main.runOne() }
            }
        }
    }

    @discardableResult
    static func connect(_ mixer: MixerOutputAdjustmentContract.Mixer,
                        raw: UInt16 = 40, maximum: UInt16 = 100, muted: Bool? = false) -> Service {
        let service = Service()
        Service.shared = service
        service.raw = raw
        service.maximum = maximum
        service.nativeMuted = muted
        let endpoint = NSObject()
        if let probed = service.probeAudio(for: 7, service: endpoint, path: "port-a") {
            service.audioRoutes[7] = AudioRoute(path: "port-a", fingerprint: "fixture-identity",
                                                service: endpoint, hasNativeMute: probed.hasNativeMute)
            service.displays = [BrightnessDisplay(id: 7, name: "Monitor A", audio: probed.state)]
        }
        service.onDisplayChange = { [weak service, weak mixer] in mixer?.monitorOutput = service?.monitorSpeakerOutput() }
        mixer.monitorOutput = service.monitorSpeakerOutput()
        return service
    }

    static func run(_ suite: TestSuite) {
        suite.expect(BrightnessSupport.audioReply(current: 50, maximum: 100) == 0.5
                     && BrightnessSupport.audioReply(current: 100, maximum: 100) == 1,
                     "a volume reply is read against its own maximum")
        suite.expect(BrightnessSupport.audioReply(current: 5, maximum: 0) == nil
                     && BrightnessSupport.audioReply(current: 255, maximum: 100) == nil,
                     "an empty or impossible range never becomes a usable volume")

        let service = Service()
        let endpoint = NSObject()
        service.raw = 255
        suite.expect(service.probeAudio(for: 7, service: endpoint, path: "a") == nil && service.silentPaths.isEmpty,
                     "an impossible reading does not permanently classify a connection as silent")
        service.raw = 3
        service.onRead = { [weak service] in service?.wantsMonitorVolume = false }
        suite.expect(service.probeAudio(for: 7, service: endpoint, path: "a") == nil,
                     "turning off speakers during discovery cannot publish a writable route")
        service.onRead = nil
        service.wantsMonitorVolume = true
        suite.expect(service.probeAudio(for: 7, service: endpoint, path: "a")?.state.volume == 0.03,
                     "reenabling on a readable channel discovers its real low volume")
        var rejected: [UInt8] = [0x6e, 0x88, 0x02, 0x01, 0x62, 0, 0, 100, 0, 80]
        rejected.append(rejected.reduce(UInt8(0x50)) { $0 ^ $1 })
        suite.expect(BrightnessSupport.parseReply(rejected, code: 0x62) == nil,
                     "an unsupported VCP reply cannot confirm a level even with a correct checksum")

        suite.expect(BrightnessSupport.muteReply(current: 1, maximum: 2) == true
                     && BrightnessSupport.muteReply(current: 2, maximum: 2) == false,
                     "only the two MCCS mute values read as muted or unmuted")
        suite.expect(BrightnessSupport.muteReply(current: 0, maximum: 2) == nil
                     && BrightnessSupport.muteReply(current: 3, maximum: 100) == nil
                     && BrightnessSupport.muteReply(current: 1, maximum: 1) == nil,
                     "any other mute value is not a mute control")
        suite.expect(BrightnessSupport.muteDeviceValue(true) == BrightnessSupport.audioMutedValue
                     && BrightnessSupport.muteDeviceValue(false) == BrightnessSupport.audioUnmutedValue,
                     "mute writes use the MCCS values")

        suite.expect(BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeHDMI)
                     && BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeDisplayPort)
                     && !BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeBuiltIn)
                     && !BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeBluetooth),
                     "only HDMI and DisplayPort outputs can belong to a monitor")
        suite.expect(BrightnessSupport.displayOwnsOutputVolume(
                        transport: kAudioDeviceTransportTypeHDMI, outputHasSettableVolume: false)
                     && !BrightnessSupport.displayOwnsOutputVolume(
                        transport: kAudioDeviceTransportTypeHDMI, outputHasSettableVolume: true)
                     && !BrightnessSupport.displayOwnsOutputVolume(
                        transport: kAudioDeviceTransportTypeBuiltIn, outputHasSettableVolume: false),
                     "keys reach a monitor only when its output cannot take macOS volume")
        typealias Mute = BrightnessSupport
        suite.expect(Mute.monitorMuteChange(from: 0.0625, muted: false, to: 0, raises: false) == true
                     && Mute.monitorMuteChange(from: 0, muted: true, to: 0, raises: false) == nil,
                     "reaching zero mutes a monitor once, as macOS does for its own outputs")
        suite.expect(Mute.monitorMuteChange(from: 0, muted: false, to: 0.0625, raises: true) == false,
                     "leaving zero unmutes even when the last reading said unmuted, for monitors that mute themselves")
        suite.expect(Mute.monitorMuteChange(from: 0.4, muted: true, to: 0.5, raises: true) == false
                     && Mute.monitorMuteChange(from: 0.4, muted: true, to: 0.3, raises: false) == nil
                     && Mute.monitorMuteChange(from: 0.4, muted: false, to: 0.5, raises: true) == nil,
                     "a raise lifts a chosen mute, a lower leaves it, and an audible step writes no mute")
        suite.expect(Mute.monitorMuteChange(from: 0.0625, muted: nil, to: 0, raises: false) == nil
                     && Mute.monitorMuteChange(from: 0, muted: nil, to: 0.0625, raises: true) == nil,
                     "a monitor without an MCCS mute control never gets a mute write")
        let monitors: [(id: UInt32, name: String)] = [(2, "LG HDR 4K"), (3, "DELL U2720Q")]
        suite.expect(BrightnessSupport.displayForAudioOutput(deviceName: "DELL U2720Q",
                        candidates: monitors) == 3
                     && BrightnessSupport.displayForAudioOutput(deviceName: "dell u2720q",
                        candidates: monitors) == 3,
                     "the sound device is matched to its display by name, ignoring case")
        suite.expect(BrightnessSupport.displayForAudioOutput(deviceName: "LG HDR 4K Audio",
                        candidates: monitors) == 2,
                     "a device name that extends the display name still matches it")
        suite.expect(BrightnessSupport.displayForAudioOutput(deviceName: "MacBook Pro Speakers",
                        candidates: monitors) == nil
                     && BrightnessSupport.displayForAudioOutput(deviceName: "",
                        candidates: monitors) == nil,
                     "sound from another device or with no name never routes keys to a display")
        let identical: [(id: UInt32, name: String)] = [(2, "LG HDR"), (3, "LG HDR")]
        suite.expect(BrightnessSupport.displayForAudioOutput(deviceName: "LG HDR", candidates: identical) == nil
                     && BrightnessSupport.displayForAudioOutput(deviceName: "LG HDR Audio", candidates: identical) == nil
                     && BrightnessSupport.displayForAudioOutput(deviceName: "Receiver", candidates: [(2, "LG HDR")]) == nil,
                     "neither duplicate names nor an unrelated single monitor identify the selected output")
        suite.expect(BrightnessSupport.speakerService(for: 1, scores: [(1, 7, 2), (2, 7, 2)]) == nil
                     && BrightnessSupport.speakerService(for: 1, scores: [(1, 7, 2), (1, 8, 2)]) == nil
                     && BrightnessSupport.speakerService(for: 1, scores: [(1, 7, 10), (2, 7, 2)]) == 7,
                     "a speaker service needs a unique display and endpoint, while a matched connection is usable")
        var screen = BrightnessSupport.DisplayIdentity()
        screen.ioDisplayLocation = "port-a"
        screen.serialNumber = 5
        var endpointIdentity = BrightnessSupport.ServiceIdentity()
        endpointIdentity.ioDisplayLocation = "port-a"
        endpointIdentity.serialNumber = 6
        suite.expect(BrightnessSupport.matchScore(service: endpointIdentity, display: screen, requireIdentity: true) == 0
                     && BrightnessSupport.matchScore(service: endpointIdentity, display: screen) > 0,
                     "a conflicting serial on a reused port rules out audio without changing brightness assignment")

        func keyData(_ code: Int, state: Int, repeatBit: Int = 0) -> Int {
            (code << 16) | (state << 8) | repeatBit
        }
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(0, state: 10))
                        == BrightnessSupport.VolumeKeyEvent(action: .step(direction: 1),
                                                            isKeyDown: true, isRepeat: false),
                     "the volume-up key press parses as one step up")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(1, state: 11))
                        == BrightnessSupport.VolumeKeyEvent(action: .step(direction: -1),
                                                            isKeyDown: false, isRepeat: false),
                     "the volume-down key release parses as one step down")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(7, state: 10))
                        == BrightnessSupport.VolumeKeyEvent(action: .toggleMute,
                                                            isKeyDown: true, isRepeat: false),
                     "the mute key press parses as a mute toggle")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8,
                        data1: keyData(0, state: 10, repeatBit: 1))?.isRepeat == true,
                     "a held volume key is marked as a repeat")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(2, state: 10)) == nil
                     && BrightnessSupport.volumeKeyEvent(subtype: 7, data1: keyData(0, state: 10)) == nil
                     && BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(0, state: 7)) == nil,
                     "brightness keys, other subtypes and other states are never volume keys")

        let settings = MonitorVolumeKeySettings()
        suite.expect(settings.requestedLevel(from: 0, direction: 1, fine: false) == 1.0 / 16.0
                     && settings.requestedLevel(from: 0, direction: -1, fine: true) == -1.0 / 100.0,
                     "default monitor keys move one sixteenth, or one percent with Option and Shift")
        suite.expect(BrightnessSupport.volumeKeyFineness(option: true, shift: true,
                        commandOrControl: false) == true
                     && BrightnessSupport.volumeKeyFineness(option: false, shift: false,
                        commandOrControl: false) == false
                     && BrightnessSupport.volumeKeyFineness(option: true, shift: false,
                        commandOrControl: false) == nil
                     && BrightnessSupport.volumeKeyFineness(option: true, shift: true,
                        commandOrControl: true) == nil,
                     "Option+Shift is the fine step, Option alone and Command or Control stay with macOS")
        suite.expect(BrightnessSupport.steppedLevel(0.95, delta: 0.1) == 1
                     && BrightnessSupport.steppedLevel(0.05, delta: -0.1) == 0
                     && BrightnessSupport.steppedLevel(0.5, delta: 0.25) == 0.75,
                     "a volume step stays between silent and full")

        suite.expect(BrightnessSupport.updatedRememberedPaths(["a", "b"], path: "c",
                        remembered: true, limit: 2) == ["b", "c"]
                     && BrightnessSupport.updatedRememberedPaths(["a", "b"], path: "a",
                        remembered: false) == ["b"],
                     "a silent-speaker path is remembered newest and forgotten when it changes")
        suite.expect(!BrightnessSupport.shouldProbe(pathKey: "a", rememberedPaths: ["a"])
                     && BrightnessSupport.shouldProbe(pathKey: "b", rememberedPaths: ["a"])
                     && BrightnessSupport.shouldProbe(pathKey: nil, rememberedPaths: ["a"]),
                     "a remembered silent path is not probed again, and an unknown path always is")
        suite.expect(BrightnessSupport.shouldProbeLuminance(pathKey: "a", writeOnlyPaths: ["a"],
                        probesAudio: true, recheckedPaths: [])
                     && !BrightnessSupport.shouldProbeLuminance(pathKey: "a", writeOnlyPaths: ["a"],
                        probesAudio: true, recheckedPaths: ["a"])
                     && !BrightnessSupport.shouldProbeLuminance(pathKey: "a", writeOnlyPaths: ["a"],
                        probesAudio: false, recheckedPaths: [])
                     && BrightnessSupport.shouldProbeLuminance(pathKey: "b", writeOnlyPaths: ["a"],
                        probesAudio: false, recheckedPaths: [])
                     && BrightnessSupport.shouldProbeLuminance(pathKey: nil, writeOnlyPaths: ["a"],
                        probesAudio: false, recheckedPaths: []),
                     "a remembered write-only path is read again once while speakers are wanted, then trusted")
        suite.expect(BrightnessSupport.ddcRetryDelay(attempt: 1, probesAudio: true, repliedThisSession: true) == 2
                     && BrightnessSupport.ddcRetryDelay(attempt: 2, probesAudio: true, repliedThisSession: true) == 5
                     && BrightnessSupport.ddcRetryDelay(attempt: 3, probesAudio: true, repliedThisSession: true) == 15,
                     "a monitor that answered before is read again after about 2, 5 and 15 seconds")
        suite.expect(BrightnessSupport.ddcRetryDelay(attempt: 4, probesAudio: true, repliedThisSession: true) == nil,
                     "the write-only answer stands once the third retry fails")
        suite.expect(BrightnessSupport.ddcRetryDelay(attempt: 1, probesAudio: false, repliedThisSession: true) == nil
                     && BrightnessSupport.ddcRetryDelay(attempt: 1, probesAudio: true, repliedThisSession: false) == nil,
                     "a failed read is retried only while speakers are wanted and the monitor answered this session")
        suite.expect(BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: true,
                        now: 100, lastRescan: nil)
                     && !BrightnessSupport.rescansForVolumeKey(hasTarget: true, displayOwnsOutput: true,
                        now: 100, lastRescan: nil)
                     && !BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: false,
                        now: 100, lastRescan: nil),
                     "an unclaimed volume key rescans only while a monitor output has no target")
        suite.expect(!BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: true,
                        now: 109, lastRescan: 100)
                     && BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: true,
                        now: 110, lastRescan: 100),
                     "volume keys rescan at most once every 10 seconds")
        suite.expect(BrightnessSupport.needsAudioScan(wanted: true, scanned: false, queued: nil)
                     && !BrightnessSupport.needsAudioScan(wanted: true, scanned: false, queued: true)
                     && !BrightnessSupport.needsAudioScan(wanted: true, scanned: true, queued: nil)
                     && BrightnessSupport.needsAudioScan(wanted: false, scanned: true, queued: true)
                     && BrightnessSupport.needsAudioScan(wanted: false, scanned: false, queued: true)
                     && !BrightnessSupport.needsAudioScan(wanted: false, scanned: true, queued: false),
                     "a speaker scan is forced once per setting change, not again while one is queued")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.displayVolumeEnabled] as? Bool == false
                     && Defaults.registeredDefaults[DefaultsKey.displayVolumeKeysEnabled] as? Bool == false,
                     "speaker volume and its volume keys are off until enabled")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.displayVolumeEnabled)
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.displayVolumeKeysEnabled),
                     "the speaker volume switches travel in a settings backup")
        suite.expect(SettingsBackupSupport.machineStateKeys.contains(DefaultsKey.displayAudioSilentPaths)
                     && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.displayAudioSilentPaths),
                     "a monitor's silent-speaker memory stays on this Mac")
    }
}
