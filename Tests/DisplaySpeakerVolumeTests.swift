// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreAudio
import Darwin
import Foundation

/// Production discovery, queue, transaction and mixer entry points against
/// a controlled DDC transport, default output and main queue.
enum DisplaySpeakerVolumeTests {
    typealias DispatchQueue = MixerOutputAdjustmentContract.DispatchQueue
    typealias Queue = MixerOutputAdjustmentContract.Queue
    struct BrightnessDisplay {
        typealias Audio = BrightnessSupport.MonitorSpeakerOutput
        let id: UInt32
        var name: String
        var isBuiltIn = false
        var isActive = true
        var audio: Audio?
    }
    struct AppVolumeMixer {
        static let shared = Self()
        func refreshMonitorOutput() { Service.shared.onDisplayChange?() }
        static func defaultOutputDeviceID() -> AudioObjectID? {
            Service.shared.defaultOutputReads += 1
            return Service.shared.actualDevice
        }
        static func outputDeviceUID(for device: AudioObjectID) -> String? {
            Service.shared.outputUIDReads.append(device)
            return Service.shared.outputUIDs[device]
        }
        static func isOutputDeviceAlive(_ device: AudioObjectID) -> Bool {
            Service.shared.feedbackOutputChecks.append(device)
            return !Service.shared.unavailableOutputs.contains(device)
        }
    }
    enum AppFeature {
        case brightness
        var isAvailable: Bool { true }
    }
    struct PreciseVolumeRollerService {
        typealias UserDefaults = DisplaySpeakerVolumeTests.UserDefaults
        final class Sound {
            var playbackDeviceIdentifier: String? {
                didSet {
                    if let uid = playbackDeviceIdentifier, !Service.shared.outputUIDs.values.contains(uid) {
                        playbackDeviceIdentifier = nil
                    }
                }
            }
            func stop() {}
            func play() { Service.shared.clickDeviceUIDs.append(playbackDeviceIdentifier) }
        }
        static let volumeFeedback: Sound? = Sound()
        static let shared = Self()
        func syncWithPreferences() {}
    }
    enum UserDefaults {
        static let standard = UserDefaults.self
        static func bool(forKey key: String) -> Bool {
            if key == "com.apple.sound.beep.feedback" { return Service.shared.feedbackEnabled }
            if key == DefaultsKey.brightnessControlEnabled { return Service.shared.brightnessControlsEnabled }
            return key == DefaultsKey.displayVolumeKeysEnabled && Service.shared.wantsMonitorVolumeKeys
        }
    }
    static func CGDisplayIsActive(_ id: UInt32) -> UInt32 { 1 }
    static func CGDisplayIsAsleep(_ id: UInt32) -> UInt32 { Service.shared.displayIsAsleep ? 1 : 0 }
    struct Write: Equatable {
        let code: UInt8
        let value: UInt16
        init(_ code: UInt8, _ value: UInt16) { self.code = code; self.value = value }
    }
    /// Exercise the production DDC send loop with one simulated I2C endpoint and no delays.
    final class DDCWriter {
        enum BrightnessBridge {
            static let writeI2C: ((CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32)? = {
                service, _, _, bytes, count in
                guard let writer = service as? DDCWriter else { return KERN_FAILURE }
                writer.writes += 1
                writer.lastPacket = Array(UnsafeRawBufferPointer(start: bytes, count: Int(count)))
                return writer.writeResult
            }
        }
        var writes = 0
        var lastPacket: [UInt8] = []
        var writeResult = KERN_SUCCESS
        var onPause: (() -> Void)?
        func paceDDCCommand(for id: UInt32) {}
        func recordDDCCommandEnd(for id: UInt32) {}
        func usleep(_ microseconds: UInt32) { onPause?() }
    }

    class Fixture {
        let stateLock = NSLock()
        let workQueue = Queue()
        let audioOutputQueue = Queue()
        var running = true
        var brightnessControlsEnabled = true
        var rebuildGeneration = 0
        var wantsMonitorVolume = true
        var wantsMonitorVolumeKeys = true
        var monitorVolumeKeySettings = MonitorVolumeKeySettings()
        var displayPowerIsSuspended = false
        var displayIsAsleep = false
        var displays: [BrightnessDisplay] = [] { didSet { onDisplayChange?() } }
        var onDisplayChange: (() -> Void)?
        var hiddenDisplays: [(id: UInt32, name: String)] = []
        var audioDisplayNames: [(id: UInt32, name: String)] {
            displays.filter { !$0.isBuiltIn }.map { ($0.id, $0.name) } + hiddenDisplays
        }
        var audioRoutes: [UInt32: AudioRoute] = [:]
        var pendingSpeakerUnmutes: [String: UInt64] = [:]
        var confirmedZeroUnmutes: [String: (entryID: UInt64, chip: UInt32)] = [:]
        var audioLifetime: UInt64 = 0
        var disabledSpeakerLifetime: UInt64?
        var scannedAudio = false
        var audioScanQueued: Bool?
        var speakerLevelRevisions: [String: UInt64] = [:]
        var speakerSliderIntents: [String: SpeakerSliderFeedback.Request] = [:]
        var pendingAudio: [PendingAudio] = []
        var audioWriteInFlight = false
        var audioOutputGeneration = 0
        var audioOutputListener: Bool? = true
        var selectedAudioOutput: (id: AudioObjectID, monitorName: String?, uid: String?)? = (31, "Monitor A", "monitor-a")
        var actualDevice: AudioObjectID = 31
        var monitorOutputNames: [AudioObjectID: String] = [31: "Monitor A", 32: "Monitor B"]
        var outputUIDs: [AudioObjectID: String] = [31: "monitor-a", 32: "monitor-b"]
        var defaultOutputReads = 0
        var outputUIDReads: [AudioObjectID] = []
        var unavailableOutputs: Set<AudioObjectID> = []
        var feedbackOutputChecks: [AudioObjectID] = []
        var raw: UInt16 = 40
        var maximum: UInt16 = 100
        var nativeMuted: Bool?
        var unmutedReads: UInt16 = 2
        var muteImageByte: UInt8 = 0
        var muteMaximum: UInt16 = 2
        var mccsVersion: UInt16?
        var versionReadAttempts: [Int] = []
        var rejectUnmute = false
        var rejectMute = false
        var rejectVolume = false
        var rejectVolumeRead = false
        var ignoreVolume = false
        var ignoreMute = false
        var onSend: (() -> Void)?
        var afterSend: (() -> Void)?
        var afterUnmute: (() -> Void)?
        var onRead: ((UInt8) -> Void)?
        var displayFingerprint = "fixture-identity"
        var connectedSpeakerEndpointID: UInt64 = 1
        var onEndpointLookup: (() -> Void)?
        var volumeOnUnmute: UInt16?
        var writes: [Write] = []
        var singleAttemptWrites: [Write] = []
        var writtenIDs: [UInt32] = []
        var feedbackEnabled = true
        var clickDeviceUIDs: [String?] = []
        var clicks: Int { clickDeviceUIDs.count }
        var refreshes = 0
        var silentPaths: Set<String> = []
        var chips: [UInt32] = []

        static func defaultOutputDevice() -> (id: AudioObjectID, monitorName: String?)? {
            let device = Service.shared.actualDevice
            return (device, Service.shared.monitorOutputNames[device])
        }
        static func restorationDisplayFingerprint(_ id: UInt32) -> String? { Service.shared.displayFingerprint }
        static func speakerEndpointIsConnected(_ id: UInt64?) -> Bool {
            let found = Service.shared.connectedSpeakerEndpointID == id
            Service.shared.onEndpointLookup?()
            return found
        }
        func start() { running = true }
        func tearDownDisplayControls() {
            running = false
            removeAudioOutputObserver()
            displays = []
        }
        func syncKeyTap() {}
        func syncKeyboardBrightnessHotkeys() {}
        func syncDisplayBrightnessHotkeys() {}
        func installAudioOutputObserver() { audioOutputListener = true }
        func removeAudioOutputObserver() {
            guard audioOutputListener != nil else { return }
            audioOutputListener = nil
            audioOutputGeneration += 1
            selectedAudioOutput = nil
        }
        func refresh(force: Bool) { refreshes += 1 }
        func rescanForUnclaimedVolumeKey() { refreshes += 1 }
        func rememberedPaths(_ key: String) -> Set<String> { silentPaths }
        func rememberPath(_ path: String, key: String, remembered: Bool) { silentPaths.insert(path) }
        func ddcProbe(_ code: UInt8, for id: UInt32, service: CFTypeRef, chip: UInt32,
                      attempts: Int = BrightnessSupport.ddcProbeAttempts(), whileCurrent: () -> Bool = { true }) -> DDCProbe {
            guard whileCurrent() else { return .dead }
            chips.append(chip)
            onRead?(code)
            if code == BrightnessSupport.audioVolumeCode {
                return rejectVolumeRead ? .dead : .replied(current: raw, maximum: maximum)
            }
            if code == 0xDF {
                versionReadAttempts.append(attempts)
                guard let mccsVersion else { return .dead }
                return .replied(current: mccsVersion, maximum: 0)
            }
            guard code == BrightnessSupport.audioMuteCode, let nativeMuted else { return .dead }
            let audio: UInt16 = nativeMuted ? 1 : unmutedReads
            return .replied(current: UInt16(muteImageByte) << 8 | audio, maximum: muteMaximum)
        }
        func ddcSend(to id: UInt32, service: CFTypeRef, chip: UInt32, packet: @autoclosure () -> [UInt8]?,
                     acceptPartialWrite: Bool = false, once: Bool = false, whileCurrent: () -> Bool) -> Bool {
            onSend?()
            guard whileCurrent(), let packet = packet() else { return false }
            chips.append(chip)
            let code = packet[2], value = UInt16(packet[3]) << 8 | UInt16(packet[4])
            writes.append(Write(code, value))
            if once { singleAttemptWrites.append(Write(code, value)) }
            writtenIDs.append(id)
            if code == BrightnessSupport.audioVolumeCode {
                guard !rejectVolume else { return false }
                if !ignoreVolume { raw = value }
            } else if code == BrightnessSupport.audioMuteCode, nativeMuted != nil {
                if (value == 2 && rejectUnmute) || (value == 1 && rejectMute) { return false }
                if value != 1 || !ignoreMute { nativeMuted = value == 1 }
                if value == 2 {
                    if let volumeOnUnmute { raw = volumeOnUnmute }
                    afterUnmute?()
                }
            } else { return false }
            let after = afterSend
            afterSend = nil
            after?()
            // The first DDC cycle reached the monitor. The next can lose its route.
            return whileCurrent() || acceptPartialWrite
        }
        func finish() {
            while !workQueue.jobs.isEmpty || !audioOutputQueue.jobs.isEmpty || !DispatchQueue.main.jobs.isEmpty {
                if !workQueue.jobs.isEmpty { workQueue.runOne() }
                if !audioOutputQueue.jobs.isEmpty { audioOutputQueue.runOne() }
                if !DispatchQueue.main.jobs.isEmpty { DispatchQueue.main.runOne() }
            }
        }
    }

    @discardableResult
    static func connect(_ mixer: MixerOutputAdjustmentContract.Mixer,
                        raw: UInt16 = 40, maximum: UInt16 = 100, muted: Bool? = false,
                        unmutedReads: UInt16 = 2, muteImageByte: UInt8 = 0, muteMaximum: UInt16 = 2,
                        mccsVersion: UInt16? = nil,
                        chip: UInt32 = BrightnessSupport.chipAddress,
                        registryEntryID: UInt64? = 1) -> Service {
        let service = Service()
        Service.shared = service
        service.raw = raw
        service.maximum = maximum
        service.nativeMuted = muted
        service.unmutedReads = unmutedReads
        service.muteImageByte = muteImageByte
        service.muteMaximum = muteMaximum
        service.mccsVersion = mccsVersion
        discover(service, chip: chip, registryEntryID: registryEntryID)
        service.onDisplayChange = { [weak service, weak mixer] in mixer?.monitorOutput = service?.monitorSpeakerOutput() }
        mixer.monitorOutput = service.monitorSpeakerOutput()
        return service
    }

    private static func discover(_ service: Service, chip: UInt32, registryEntryID: UInt64?, path: String = "port-a") {
        let endpoint = NSObject()
        if let probed = service.probeAudio(for: 7, service: endpoint, chip: chip, path: path,
                                          registryEntryID: registryEntryID) {
            service.audioRoutes[7] = AudioRoute(path: path, fingerprint: service.displayFingerprint,
                                                service: endpoint, registryEntryID: registryEntryID,
                                                chipAddress: chip, hasNativeMute: probed.hasNativeMute,
                                                unmutesLeavingZero: probed.unmutesLeavingZero, muteVersion: probed.muteVersion)
            service.scannedAudio = true
            service.displays = [BrightnessDisplay(id: 7, name: "Monitor A", audio: probed.state)]
        }
    }

    private static func checkInterruptedDDCWrites(_ suite: TestSuite) {
        let writer = DDCWriter()
        let chip = BrightnessSupport.chipAddress
        let unmute = BrightnessSupport.writePacket(code: BrightnessSupport.audioMuteCode,
                                                   value: BrightnessSupport.audioUnmutedValue)
        let luminance = BrightnessSupport.writePacket(code: BrightnessSupport.luminanceCode, value: 5)
        let currentUntilFirstSend = { writer.writes == 0 }
        let released = writer.ddcSend(to: 7, service: writer, chip: chip, packet: unmute,
                                      acceptPartialWrite: true, whileCurrent: currentUntilFirstSend)
        suite.expect(released && writer.writes == 1,
                     "an accepted unmute survives cancellation before its repeat without sending again")
        writer.writes = 0
        let brightened = writer.ddcSend(to: 7, service: writer, chip: chip, packet: luminance,
                                        whileCurrent: currentUntilFirstSend)
        suite.expect(!brightened && writer.writes == 1,
                     "a luminance write stays cancelled when its second cycle loses the route")
        writer.writes = 0
        writer.writeResult = KERN_FAILURE
        let rejected = writer.ddcSend(to: 7, service: writer, chip: chip, packet: unmute,
                                      acceptPartialWrite: true, whileCurrent: currentUntilFirstSend)
        suite.expect(!rejected && writer.writes == 1,
                     "a rejected unmute never counts as an accepted write when its repeat is cancelled")
        for result in [KERN_SUCCESS, KERN_FAILURE] {
            writer.writeResult = result
            writer.writes = 0
            var ceiling: UInt16 = 5
            writer.onPause = { ceiling = 3 }
            let accepted = writer.ddcSend(to: 7, service: writer, chip: chip,
                packet: BrightnessSupport.writePacket(code: BrightnessSupport.audioVolumeCode, value: ceiling), once: true)
            suite.expect(accepted == (result == KERN_SUCCESS) && writer.writes == 1
                         && writer.lastPacket == [0x84, 0x03, 0x62, 0, 3, 0xd9],
                         "the single physical write uses the final ceiling and its checksum after the write pause")
        }
    }

    private static func checkSliderFeedback(_ suite: TestSuite) {
        let mixer = MixerOutputAdjustmentContract.Mixer()
        let target = BrightnessSupport.SpeakerTarget(displayID: 7, path: "port-a")
        let feedback = SpeakerSliderFeedback { Service.shared.sliderFeedbackOutput }
        var service = connect(mixer)
        func set(_ volume: Double, completion: @escaping (Bool) -> Void = { _ in }) {
            service.requestSpeakers(.set(volume: volume, muted: nil), target: target,
                                    sliderFeedback: feedback.request(), completion: completion)
        }
        for releaseFirst in [false, true] {
            for (muted, unmutedReads): (Bool?, UInt16) in [(true, 2), (nil, 2), (false, 0)] {
                service = connect(mixer, raw: 0, muted: muted, unmutedReads: unmutedReads)
                service.wantsMonitorVolumeKeys = releaseFirst
                service.monitorVolumeKeySettings = .init(maximumPercent: 5)
                feedback.editingChanged(true)
                set(0.6)
                if releaseFirst { feedback.editingChanged(false) } else { service.finish() }
                suite.expect(service.clicks == 0, "the speaker slider waits for both release and confirmation")
                // Only the selected output changed. This row still controls the same monitor.
                service.removeAudioOutputObserver()
                service.actualDevice = 32
                if releaseFirst { service.finish() } else { feedback.editingChanged(false) }
                feedback.editingChanged(false)
                service.finish()
                suite.expect(service.raw == 60 && service.writtenIDs.allSatisfy { $0 == 7 }
                             && service.clickDeviceUIDs == ["monitor-a"] && service.feedbackOutputChecks == [31],
                             "a manual adjustment stays on its monitor and clicks once on the original output")
            }
        }

        for (level, raw): (Double, UInt16) in [(0, 0), (1, 10), (0.41, 4)] {
            service = connect(mixer, raw: raw, maximum: 10, muted: nil)
            feedback.editingChanged(true)
            set(level)
            feedback.editingChanged(false)
            service.finish()
            suite.expect(service.writes.isEmpty && service.clicks == 0,
                         "an endpoint or a rounded value already on the monitor makes no sound")
        }
        service = connect(mixer)
        feedback.editingChanged(true)
        feedback.editingChanged(false)
        suite.expect(service.clicks == 0, "releasing without setting any volume stays silent")
        set(0.7)
        service.finish()
        suite.expect(service.raw == 70 && service.clicks == 1,
                     "a keyboard or accessibility adjustment without drag callbacks clicks after confirmation")
        service.feedbackEnabled = false
        set(0.8)
        service.finish()
        suite.expect(service.raw == 80 && service.clicks == 1, "disabling the system sound leaves a confirmed change silent")

        service = connect(mixer)
        feedback.editingChanged(true)
        var replaced: [Bool] = []
        set(0.5)
        set(0.6) { replaced.append($0) }
        set(0.7)
        suite.expect(replaced == [false] && service.clicks == 0, "a coalesced setter completes synchronously")
        feedback.editingChanged(false)
        service.finish()
        suite.expect(service.writes == [Write(BrightnessSupport.audioVolumeCode, 70)] && service.clicks == 1,
                     "the newest setter survives the superseded callback without writing again on release")
        feedback.editingChanged(true)
        set(0.8)
        service.finish()
        set(0.801)
        feedback.editingChanged(false)
        service.finish()
        suite.expect(service.clicks == 2 && service.writes.count == 2,
                     "a final setter on the same hardware step preserves the drag's single confirmed change")

        for (beforeReadback, rejectFinalRead) in [(false, false), (true, false), (false, true)] {
            service = connect(mixer)
            feedback.editingChanged(true)
            if beforeReadback { service.afterSend = { set(0.801) } }
            set(0.8)
            service.workQueue.runOne()
            if !beforeReadback { set(0.801) }
            service.rejectVolumeRead = rejectFinalRead
            feedback.editingChanged(false)
            service.finish()
            suite.expect(service.clicks == (rejectFinalRead ? 0 : 1) && service.raw == 80
                         && service.writes == [Write(BrightnessSupport.audioVolumeCode, 80)],
                         "an in-flight change requires the last setter's readback (before readback: \(beforeReadback), read fails: \(rejectFinalRead))")
        }

        service = connect(mixer)
        feedback.editingChanged(true)
        set(0.7)
        service.finish()
        service.requestSpeakers(.set(volume: 0.8, muted: nil), target: target)
        service.finish()
        set(0.801)
        feedback.editingChanged(false)
        service.finish()
        suite.expect(service.clicks == 0 && service.writes.map(\.value) == [70, 80],
                     "a final no-op cannot borrow an earlier drag change superseded by another control")

        service = connect(mixer)
        feedback.editingChanged(true)
        set(0.5)
        service.finish()
        service.wantsMonitorVolume = false
        var refused: Bool?
        set(0.7) { refused = $0 }
        service.wantsMonitorVolume = true
        feedback.editingChanged(false)
        suite.expect(refused == false && service.clicks == 0 && service.writes.count == 1,
                     "a synchronously refused final setter revokes the earlier success before release")

        for invalidate: (Service) -> Void in [
            { $0.displays = [] }, { $0.invalidateSpeakerRoutes() }, { _ in feedback.cancel() },
            { $0.displayFingerprint = "another-monitor" }, { $0.displayIsAsleep = true },
            { $0.requestSpeakers(.set(volume: nil, muted: true), target: target) }
        ] {
            service = connect(mixer)
            feedback.editingChanged(true)
            set(0.7)
            service.finish()
            invalidate(service)
            feedback.editingChanged(false)
            service.finish()
            suite.expect(service.clicks == 0, "a removed target, cancelled edit or newer intent revokes a waiting click")
        }
        service = connect(mixer)
        feedback.editingChanged(true)
        set(0.7)
        feedback.editingChanged(false)
        feedback.editingChanged(true)
        service.finish()
        feedback.editingChanged(false)
        suite.expect(service.clicks == 0, "starting another drag invalidates a released edit awaiting its readback")
        for interrupt: (Service) -> Void in [
            { $0.rejectVolume = true }, { $0.ignoreVolume = true }, { $0.maximum = 0 },
            { $0.wantsMonitorVolume = false }, { $0.invalidateSpeakerRoutes() }, { _ in feedback.cancel() }
        ] {
            service = connect(mixer)
            feedback.editingChanged(true)
            set(0.5)
            service.finish()
            set(0.7)
            feedback.editingChanged(false)
            interrupt(service)
            service.finish()
            suite.expect(service.clicks == 0,
                         "a failed or cancelled final level stays silent even after an earlier level succeeded")
        }
        service = connect(mixer, raw: 0, muted: false, unmutedReads: 0)
        service.rejectUnmute = true
        feedback.editingChanged(true)
        set(0.5)
        feedback.editingChanged(false)
        service.finish()
        suite.expect(service.raw == 50 && service.clicks == 0,
                     "accepting the new volume but failing to release the zero latch cannot sound a click")
    }

    private static func checkSliderFeedbackOutput(_ suite: TestSuite) {
        enum Change: CaseIterable {
            case defaultOnly, removed, reusedID, inactive, publicationPending, emptyUIDAtStart
            case cancelAfterCheck, dragAfterCheck, writeAfterCheck, disableAfterCheck, removedAfterCheck
        }
        let mixer = MixerOutputAdjustmentContract.Mixer()
        let target = BrightnessSupport.SpeakerTarget(displayID: 7, path: "port-a")
        for change in Change.allCases {
            let service = connect(mixer)
            let feedback = SpeakerSliderFeedback { service.sliderFeedbackOutput }
            func set(_ level: Double) {
                service.requestSpeakers(.set(volume: level, muted: nil), target: target, sliderFeedback: feedback.request())
            }
            // The monitor row is A. The Mac is playing through headphones when the drag starts.
            service.actualDevice = 32
            service.monitorOutputNames[32] = nil
            service.outputUIDs[32] = change == .emptyUIDAtStart ? "" : "headphones"
            service.readSelectedAudioOutput()
            if change != .publicationPending { service.finish() }
            feedback.editingChanged(true)
            service.actualDevice = 31
            service.readSelectedAudioOutput()
            service.finish()
            set(0.5)
            service.finish()
            suite.expect(service.raw == 50 && service.feedbackOutputChecks.isEmpty && service.clicks == 0,
                         "an intermediate confirmation waits for release without checking audio hardware (\(change))")
            set(0.7)
            feedback.editingChanged(false)
            service.actualDevice = 33
            service.outputUIDs[33] = "speakers"
            service.selectedAudioOutput = (33, nil, "speakers")
            switch change {
            case .removed: service.outputUIDs[32] = nil
            case .reusedID: service.outputUIDs[32] = "replacement"
            case .inactive: service.unavailableOutputs.insert(32)
            default: break
            }
            suite.expect(service.audioOutputQueue.jobs.isEmpty && service.feedbackOutputChecks.isEmpty && service.clicks == 0,
                         "release performs no audio lookup and waits for the final write (\(change))")
            service.workQueue.runOne()
            DispatchQueue.main.runOne()
            let checks: [AudioObjectID] = change == .emptyUIDAtStart ? [] : [32]
            suite.expect(service.writtenIDs == [7, 7] && service.raw == 70 && service.clicks == 0
                         && service.audioOutputQueue.jobs.count == checks.count && service.feedbackOutputChecks.isEmpty,
                         "both writes reach A and only the initial playback device can be checked asynchronously (\(change))")
            if !service.audioOutputQueue.jobs.isEmpty { service.audioOutputQueue.runOne() }
            suite.expect(service.feedbackOutputChecks == checks && service.clicks == 0,
                         "the audio queue verifies the captured device once and leaves playback on main (\(change))")

            // Change the default again after the HAL reply, before the main queue can play.
            service.actualDevice = 31
            service.selectedAudioOutput = (31, "Monitor A", "monitor-a")
            switch change {
            case .cancelAfterCheck: feedback.cancel()
            case .removedAfterCheck: service.outputUIDs[32] = nil
            case .dragAfterCheck: feedback.editingChanged(true)
            case .writeAfterCheck: service.requestSpeakers(.set(volume: 0.8, muted: nil), target: target)
            case .disableAfterCheck: service.feedbackEnabled = false
            default: break
            }
            service.finish()
            let expected: [String?] = [.defaultOnly, .publicationPending].contains(change) ? ["headphones"] : []
            suite.expect(service.clickDeviceUIDs == expected && service.feedbackOutputChecks == checks
                         && service.writtenIDs == (change == .writeAfterCheck ? [7, 7, 7] : [7, 7]),
                         "only the live original headphones can play the final unsuperseded click (\(change))")
            if change == .dragAfterCheck {
                set(0.8)
                feedback.editingChanged(false)
                service.finish()
                suite.expect(service.clickDeviceUIDs == ["monitor-a"] && service.feedbackOutputChecks == [32, 31]
                             && service.writtenIDs == [7, 7, 7],
                             "the next drag captures its own output and plays once after its own write")
            }
        }
    }

    private static func checkSliderOutputBeforeObserverUpdate(_ suite: TestSuite) {
        enum Observer: CaseIterable { case delayed, unavailable, awaitingPublication }
        let mixer = MixerOutputAdjustmentContract.Mixer()
        let target = BrightnessSupport.SpeakerTarget(displayID: 7, path: "port-a")
        for observer in Observer.allCases {
            for drag in [false, true] {
                for readableUID in [true, false] {
                    let service = connect(mixer)
                    service.actualDevice = 32  // Both A and B are connected, but B is already playing.
                    if !readableUID { service.outputUIDs[32] = nil }
                    switch observer {
                    case .delayed: break  // A is still published.
                    case .unavailable: service.removeAudioOutputObserver()
                    case .awaitingPublication:
                        service.readSelectedAudioOutput()
                        service.audioOutputQueue.runOne()  // The reply about B is waiting on main.
                    }
                    let reads = service.defaultOutputReads
                    let uidReads = service.outputUIDReads.count
                    let feedback = SpeakerSliderFeedback { service.sliderFeedbackOutput }
                    func set(_ level: Double) {
                        service.requestSpeakers(.set(volume: level, muted: nil), target: target, sliderFeedback: feedback.request())
                    }
                    if drag {
                        feedback.editingChanged(true)
                        set(0.5)
                        service.finish()
                        suite.expect(service.clicks == 0, "a held drag stays silent after its intermediate write")
                        service.actualDevice = 31
                    }
                    set(0.7)
                    if drag { feedback.editingChanged(false) }
                    suite.expect(service.defaultOutputReads - reads == 1
                                 && service.outputUIDReads.dropFirst(uidReads).elementsEqual([32]),
                                 "the panel samples the default ID and UID once before the final write can complete")
                    service.finish()
                    let expectedClicks: [String?] = readableUID ? ["monitor-b"] : []
                    suite.expect(service.defaultOutputReads - reads == 1 && service.raw == 70
                                 && service.writtenIDs == (drag ? [7, 7] : [7])
                                 && service.clickDeviceUIDs == expectedClicks,
                                 "one initial default read routes feedback for an explicit write to A (\(observer), drag: \(drag), readable B: \(readableUID))")
                }
            }
        }
    }

    private static func checkSliderEndpointChanges(_ suite: TestSuite) {
        enum Rescan { case beforeFinalRequest, beforeFinalRead, beforeRelease }
        let mixer = MixerOutputAdjustmentContract.Mixer()
        let target = BrightnessSupport.SpeakerTarget(displayID: 7, path: "port-a")
        let volume = BrightnessSupport.audioVolumeCode
        let chip = BrightnessSupport.chipAddress
        let routes: [(firstID: UInt64?, scannedID: UInt64?, address: UInt32)] = [
            (1, 2, chip), (1, 1, chip), (nil, nil, chip), (1, 1, BrightnessSupport.hdmiConverterChipAddress)
        ]
        func rescan(_ service: Service, id: UInt64?, address: UInt32) {
            // A fresh AV service wrapper can describe the same endpoint or its
            // replacement. Both monitors report 80 on this port and display ID.
            service.connectedSpeakerEndpointID = id ?? 0
            service.audioRoutes[target.displayID] = AudioRoute(path: target.path, fingerprint: service.displayFingerprint,
                service: NSObject(), registryEntryID: id, chipAddress: address,
                hasNativeMute: true, unmutesLeavingZero: false)
            service.raw = 80
        }
        for timing in [Rescan.beforeFinalRequest, .beforeFinalRead, .beforeRelease] {
            for (firstID, scannedID, address) in routes {
                let service = connect(mixer, registryEntryID: firstID)
                let feedback = SpeakerSliderFeedback { service.sliderFeedbackOutput }
                func set(_ value: Double) {
                    service.requestSpeakers(.set(volume: value, muted: nil), target: target,
                                            sliderFeedback: feedback.request())
                }
                feedback.editingChanged(true)
                set(0.8)
                service.finish()
                if timing == .beforeFinalRequest { rescan(service, id: scannedID, address: address) }
                set(0.801)
                if timing == .beforeFinalRead { rescan(service, id: scannedID, address: address) }
                service.finish()
                if timing == .beforeRelease { rescan(service, id: scannedID, address: address) }
                feedback.editingChanged(false)
                service.finish()
                let sameEndpoint = firstID != nil && firstID == scannedID && address == chip
                suite.expect(service.writes == [Write(volume, 80)] && service.clicks == (sameEndpoint ? 1 : 0),
                             "a rounded final read can confirm only its original endpoint (\(firstID as Any) → \(scannedID as Any), address \(address), \(timing))")
                if timing == .beforeFinalRequest, scannedID == 2 {
                    let priorClicks = service.clicks
                    feedback.editingChanged(true)
                    set(0.65)
                    feedback.editingChanged(false)
                    service.finish()
                    suite.expect(service.writes == [Write(volume, 80), Write(volume, 65)] && service.clicks == priorClicks + 1,
                                 "the replacement monitor can confirm and sound its own slider write")
                }
            }
        }
        let feedback = SpeakerSliderFeedback { Service.shared.sliderFeedbackOutput }
        for (roundedFinalValue, freshWrapper) in [(false, false), (true, false), (false, true)] {
            let service = connect(mixer, registryEntryID: nil)
            feedback.editingChanged(true)
            service.requestSpeakers(.set(volume: 0.8, muted: nil), target: target, sliderFeedback: feedback.request())
            service.finish()
            if roundedFinalValue {
                service.requestSpeakers(.set(volume: 0.801, muted: nil), target: target, sliderFeedback: feedback.request())
                service.finish()
            }
            if freshWrapper { rescan(service, id: nil, address: chip) }
            feedback.editingChanged(false)
            service.finish()
            suite.expect(service.writes == [Write(volume, 80)] && service.clicks == 1,
                         "a confirmed write still clicks without a registry entry ID (rounded final: \(roundedFinalValue), fresh wrapper: \(freshWrapper))")
        }

        let unplugged = connect(mixer)
        feedback.editingChanged(true)
        unplugged.requestSpeakers(.set(volume: 0.8, muted: nil), target: target, sliderFeedback: feedback.request())
        unplugged.finish()
        unplugged.connectedSpeakerEndpointID = 2
        feedback.editingChanged(false)
        unplugged.finish()
        suite.expect(unplugged.writes == [Write(volume, 80)] && unplugged.clicks == 0,
                     "unplugging the confirmed endpoint before the route refresh revokes the release click")

        let releaseRoutes: [(first: UInt64?, current: UInt64?, lookup: UInt64?, matches: Bool)] = [
            (nil, nil, nil, true), (nil, 2, 2, true), (1, nil, 1, true), (1, 0, 1, true),
            (1, 1, 1, true), (1, 2, nil, false)
        ]
        for (first, current, lookup, matches) in releaseRoutes {
            for connected in [false, true] {
                let service = connect(mixer, registryEntryID: first)
                feedback.editingChanged(true)
                service.requestSpeakers(.set(volume: 0.8, muted: nil), target: target, sliderFeedback: feedback.request())
                service.finish()
                rescan(service, id: current, address: chip)
                service.connectedSpeakerEndpointID = connected ? (lookup ?? current ?? 1) : 0
                let commands = service.chips.count
                var lookups = 0
                service.onEndpointLookup = { lookups += 1 }
                feedback.editingChanged(false)
                service.finish()
                let plays = matches && (lookup == nil || connected)
                suite.expect(lookups == (lookup == nil ? 0 : 1) && service.clicks == (plays ? 1 : 0)
                             && service.writes == [Write(volume, 80)] && service.chips.count == commands,
                             "release validates the available registry ID without DDC (\(first as Any) → \(current as Any), connected: \(connected))")
            }
        }
    }

    private static func checkMuteDiscovery(_ suite: TestSuite) {
        let mixer = MixerOutputAdjustmentContract.Mixer()
        let volume = BrightnessSupport.audioVolumeCode
        let mute = BrightnessSupport.audioMuteCode
        let chip = BrightnessSupport.chipAddress
        let readOnly = connect(mixer, raw: 40, muted: true, registryEntryID: nil)
        var muteRequest: Bool?
        var raiseRequest: Bool?
        mixer.requestOutputAdjustment(muted: false) { muteRequest = $0 }
        mixer.requestOutputAdjustment(volume: 0.5) { raiseRequest = $0 }
        readOnly.finish()
        let reported = readOnly.displays.first?.audio
        suite.expect(muteRequest == false && raiseRequest == false && readOnly.writes.isEmpty && readOnly.refreshes == 0
                     && reported?.muted == true && reported?.canToggleMute == false
                     && mixer.systemOutputMuted == true && mixer.systemOutputVolume == 0.4 && !mixer.canToggleOutputMute,
                     "a physically muted monitor keeps its confirmed state and stored level when an unmute is unavailable")
        var capabilities: [Bool] = []
        let subscription = mixer.$canToggleOutputMute.dropFirst().sink { capabilities.append($0) }
        discover(readOnly, chip: chip, registryEntryID: 1)
        discover(readOnly, chip: chip, registryEntryID: nil)
        subscription.cancel()
        suite.expect(capabilities == [true, false] && mixer.systemOutputMuted == true && mixer.systemOutputVolume == 0.4,
                     "regaining and losing endpoint identity publishes control availability without changing the physical mute")

        for (version, maximum): (UInt16, UInt16) in [
            (0x0200, 65535), (0x0201, 100), (0x0201, 65535), (0x0201, 0), (0x0300, 65535)
        ] {
            let scalar = connect(mixer, muted: true, muteMaximum: maximum, mccsVersion: version)
            suite.expect(mixer.systemOutputMuted == true && scalar.versionReadAttempts == [1],
                         "one version read identifies a scalar mute regardless of its reported maximum")
            mixer.requestOutputMuteToggle()
            scalar.finish()
            suite.expect(mixer.systemOutputMuted == false && scalar.writes == [Write(mute, 2)] && scalar.raw == 40,
                         "the unmute command confirms scalar state two at the original volume")
            mixer.requestOutputMuteToggle()
            scalar.finish()
            suite.expect(scalar.writes == [Write(mute, 2), Write(mute, 1)] && scalar.versionReadAttempts == [1]
                         && mixer.systemOutputMuted == true && scalar.raw == 40,
                         "both mute commands use scalar readback without querying the version on each key")
        }
        for (version, maximum): (UInt16?, UInt16) in [
            (nil, 100), (nil, 65535), (0x0202, 0), (0x0202, 100), (0x0202, 65535), (0x0202, 0x0200),
            (0x0203, 65535), (0x0301, 65535), (0x0400, 65535)
        ] {
            let speakers = connect(mixer, muted: true, muteMaximum: maximum, mccsVersion: version)
            mixer.requestOutputMuteToggle()
            mixer.requestOutputAdjustment(volume: 0.55)
            speakers.finish()
            suite.expect(speakers.writes == [Write(volume, 55)] && mixer.systemOutputMuted == nil
                         && speakers.versionReadAttempts == [1],
                         "an ambiguous reply requires a recognized scalar version and leaves ordinary volume available")
        }

        for version: UInt16 in [0x0200, 0x0201, 0x0300] {
            let endpoint = connect(mixer, muted: false, muteMaximum: 65535, mccsVersion: version)
            discover(endpoint, chip: chip, registryEntryID: 1)
            suite.expect(endpoint.versionReadAttempts == [1] && mixer.systemOutputMuted == false,
                         "a new wrapper for the same registry endpoint reuses its reported MCCS version")
            endpoint.connectedSpeakerEndpointID = 2
            mixer.requestOutputMuteToggle()
            endpoint.finish()
            suite.expect(endpoint.writes.isEmpty, "a removed endpoint's version cannot authorize native mute")
            endpoint.mccsVersion = 0x0202
            discover(endpoint, chip: chip, registryEntryID: 2)
            suite.expect(endpoint.versionReadAttempts == [1, 1] && mixer.systemOutputMuted == nil,
                         "a replacement at the same port must supply its own version")
        }

        let unplugged = connect(mixer)
        unplugged.muteMaximum = 65535
        unplugged.mccsVersion = 0x0201
        unplugged.onRead = { [weak unplugged] code in
            if code == 0xDF { unplugged?.connectedSpeakerEndpointID = 2 }
        }
        let missing = unplugged.probeAudio(for: 7, service: NSObject(), chip: chip, path: "port-a", registryEntryID: 1)
        suite.expect(missing == nil, "unplugging during the optional version read cannot publish a stale mute route")

        for (version, image, readback, maximum): (UInt16, UInt8, UInt16, UInt16) in [
            (0x0201, 1, 2, 0x0202), (0x0201, 0, 0, 65535),
            (0x0200, 0, 0, 2), (0x0201, 0, 0, 2), (0x0300, 0, 0, 2)
        ] {
            let scalar = connect(mixer, muted: true, muteMaximum: 65535, mccsVersion: version)
            scalar.afterUnmute = { [weak scalar] in
                scalar?.muteImageByte = image
                scalar?.unmutedReads = readback
                scalar?.muteMaximum = maximum
            }
            var accepted: Bool?
            mixer.requestOutputAdjustment(muted: false) { accepted = $0 }
            scalar.finish()
            suite.expect(accepted == false && scalar.writes == [Write(mute, 2), Write(mute, 1)]
                         && scalar.versionReadAttempts == [1],
                         "a scalar transaction rejects reserved or combined unmute readback and attempts to re-mute")
        }
        let compound = connect(mixer, muted: true, muteMaximum: 65535, mccsVersion: 0x0202)
        compound.muteImageByte = 1
        compound.muteMaximum = 0x0202
        discover(compound, chip: chip, registryEntryID: 1)
        compound.afterUnmute = { [weak compound] in
            compound?.muteImageByte = 0
            compound?.muteMaximum = 100
        }
        var accepted: Bool?
        mixer.requestOutputAdjustment(muted: false) { accepted = $0 }
        compound.finish()
        suite.expect(accepted == false && compound.writes == [Write(mute, 2), Write(mute, 1)]
                     && compound.versionReadAttempts == [1],
                     "a combined control requires audio support at readback and never falls back to guessing a scalar")

        for version: UInt16 in [0x0200, 0x0201, 0x0202, 0x0300] {
            let speakers = connect(mixer, raw: 0, muteMaximum: 65535, mccsVersion: version)
            speakers.unmutedReads = 0
            speakers.muteMaximum = 2
            discover(speakers, chip: chip, registryEntryID: 1)
            mixer.requestOutputAdjustment(volume: 0.05)
            speakers.finish()
            let release = version == 0x0202 ? [Write(mute, 2)] : []
            suite.expect(speakers.writes == [Write(volume, 5)] + release && mixer.systemOutputVolume == 0.05
                         && mixer.systemOutputMuted == nil && speakers.versionReadAttempts == [1],
                         "a zero reply preserves the 2.2 latch release and leaves scalar volume independent of mute")
        }

        // A monitor first encountered muted may report zero after a verified
        // native unmute. Only that endpoint can interpret a subsequent zero.
        for (id, address, path): (UInt64?, UInt32, String) in [
            (1, chip, "port-a"), (2, chip, "port-a"), (nil, chip, "port-a"),
            (1, BrightnessSupport.hdmiConverterChipAddress, "port-a"), (1, chip, "port-b")
        ] {
            let speakers = connect(mixer, muted: true, unmutedReads: 0)
            mixer.requestOutputMuteToggle()
            speakers.finish()
            suite.expect(speakers.writes == [Write(mute, 2)] && mixer.systemOutputMuted == false,
                         "an accepted native unmute verifies the monitor's scalar zero encoding")
            speakers.invalidateSpeakerRoutes()
            speakers.connectedSpeakerEndpointID = id ?? 0
            discover(speakers, chip: address, registryEntryID: id, path: path)
            let same = id == 1 && address == chip && path == "port-a"
            suite.expect(mixer.systemOutputMuted == (same ? false : nil),
                         "rediscovery binds the proven zero encoding to the physical endpoint")
            mixer.requestOutputMuteToggle()
            speakers.finish()
            suite.expect(speakers.writes == (same ? [Write(mute, 2), Write(mute, 1)] : [Write(mute, 2)])
                         && mixer.systemOutputMuted == (same ? true : nil),
                         "only the original endpoint retains native mute after the rescan")
            if id == 2 {
                speakers.connectedSpeakerEndpointID = 1
                discover(speakers, chip: chip, registryEntryID: 1)
                suite.expect(mixer.systemOutputMuted == nil,
                             "a replacement on the same path invalidates the previous endpoint's proof")
            }
        }

        let stale = connect(mixer, muted: true, unmutedReads: 0)
        mixer.requestOutputMuteToggle()
        stale.finish()
        stale.connectedSpeakerEndpointID = 2
        let reads = stale.chips.count
        mixer.requestOutputMuteToggle()
        stale.finish()
        suite.expect(stale.writes == [Write(mute, 2)] && stale.chips.count == reads,
                     "an unplugged endpoint's proven zero cannot authorize I/O before the next scan")

        let unverified = connect(mixer, muted: true, unmutedReads: 0)
        unverified.volumeOnUnmute = 90
        mixer.requestOutputAdjustment(volume: 0.45)
        unverified.finish()
        unverified.nativeMuted = false
        discover(unverified, chip: chip, registryEntryID: 1)
        suite.expect(unverified.writes == [Write(volume, 45), Write(mute, 2), Write(mute, 1)]
                     && mixer.systemOutputMuted == nil,
                     "a zero read during a failed unmute cannot establish native mute at the next scan")
    }

    static func run(_ suite: TestSuite) {
        checkMuteDiscovery(suite)
        checkInterruptedDDCWrites(suite)
        checkSliderFeedback(suite)
        checkSliderFeedbackOutput(suite)
        checkSliderOutputBeforeObserverUpdate(suite)
        checkSliderEndpointChanges(suite)
        let mixer = MixerOutputAdjustmentContract.Mixer()
        let mute = BrightnessSupport.audioMuteCode
        for startsMuted in [false, true] {
            let speakers = connect(mixer, muted: startsMuted, muteImageByte: startsMuted ? 0xff : 1,
                                   muteMaximum: startsMuted ? 0xff02 : 0x0202)
            suite.expect(mixer.monitorOutput?.muted == startsMuted && speakers.versionReadAttempts.isEmpty,
                         "discovery reads the audio state from a combined mute and blanking reply")
            speakers.afterSend = { [weak speakers] in speakers?.muteImageByte = 2 }
            mixer.requestOutputMuteToggle()
            speakers.finish()
            suite.expect(speakers.writes == [Write(mute, startsMuted ? 2 : 1)]
                         && speakers.displays.first?.audio?.muted == !startsMuted
                         && mixer.systemOutputMuted == !startsMuted && speakers.raw == 40,
                         "the mute button changes only audio and confirms it independently of the picture")
        }
        for (audio, image, maximum): (UInt16, UInt8, UInt16) in [(2, 1, 0x0200), (1, 1, 0x0201),
                                                                 (2, 1, 0x0203), (3, 1, 0x0202), (2, 0, 0xff),
                                                                 (1, 1, 100), (2, 0, 0x0264), (0, 0, 100)] {
            let speakers = connect(mixer, unmutedReads: audio, muteImageByte: image, muteMaximum: maximum)
            mixer.requestOutputAdjustment(muted: true)
            speakers.finish()
            suite.expect(speakers.displays.first?.audio?.volume == 0.4 && mixer.systemOutputMuted == nil
                         && speakers.writes.isEmpty,
                         "an unsupported or reserved audio reply cannot authorize mute")
        }
        for (image, maximum): (UInt8, UInt16) in [(1, 2), (0, 0x0200), (0, 0xffff)] {
            let speakers = connect(mixer, raw: 0, unmutedReads: 0, muteImageByte: image, muteMaximum: maximum)
            mixer.requestOutputAdjustment(volume: 0.02)
            speakers.finish()
            suite.expect(speakers.writes == [Write(BrightnessSupport.audioVolumeCode, 2)]
                         && mixer.systemOutputVolume == 0.02 && mixer.systemOutputMuted == nil && speakers.versionReadAttempts.isEmpty,
                         "an unrelated zero reply cannot opt a monitor into unmute when leaving zero")
        }
        suite.expect(BrightnessSupport.audioReply(current: 50, maximum: 100) == 0.5
                     && BrightnessSupport.audioReply(current: 100, maximum: 100) == 1,
                     "a volume reply is read against its own maximum")
        suite.expect(BrightnessSupport.audioReply(current: 5, maximum: 0) == nil
                     && BrightnessSupport.audioReply(current: 255, maximum: 100) == nil,
                     "an empty or impossible range never becomes a usable volume")

        let service = Service()
        let endpoint = NSObject()
        service.raw = 255
        suite.expect(service.probeAudio(for: 7, service: endpoint, chip: BrightnessSupport.chipAddress, path: "a") == nil && service.silentPaths.isEmpty,
                     "an impossible reading does not permanently classify a connection as silent")
        service.raw = 3
        service.onRead = { [weak service] _ in service?.wantsMonitorVolume = false }
        suite.expect(service.probeAudio(for: 7, service: endpoint, chip: BrightnessSupport.chipAddress, path: "a") == nil,
                     "turning off speakers during discovery cannot publish a writable route")
        service.onRead = nil
        service.wantsMonitorVolume = true
        suite.expect(service.probeAudio(for: 7, service: endpoint, chip: BrightnessSupport.chipAddress, path: "a")?.state.volume == 0.03,
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
        var discovery = BrightnessSupport.ServiceDiscoveryRetries()
        suite.expect(discovery.missing(7, now: 0) == 2 && discovery.missing(8, now: 0) == 2,
                     "identical monitors at separate display IDs get separate retry deadlines")
        discovery.found(7)
        for tick in [0.0, 0.25, 0.5, 1.5] {
            suite.expect(discovery.missing(8, now: tick) == 2 - tick,
                         "early panel refreshes retain the first scheduled deadline")
            discovery.found(7)
        }
        suite.expect(discovery.missing(8, now: 2) == 5 && discovery.missing(8, now: 7) == 15
                     && discovery.missing(8, now: 22) == nil && discovery.missing(8, now: 500) == nil,
                     "a healthy twin cannot replenish a missing monitor's three timed scans")
        discovery.found(8)
        suite.expect(discovery.missing(8, now: 501) == 2, "a recovered connection can start a new retry sequence")

        var native = BrightnessSupport.DisplayIdentity()
        native.productName = "Native panel"
        var hdmi = BrightnessSupport.DisplayIdentity()
        hdmi.productName = "HDMI panel"
        var nativeEndpoint = BrightnessSupport.ServiceIdentity()
        nativeEndpoint.productName = "Native panel"
        nativeEndpoint.ordinal = 3
        let desk = [(index: 0, identity: native), (index: 1, identity: hdmi)]
        suite.expect(BrightnessSupport.brightnessServices(displays: desk, candidates: [1], services: [nativeEndpoint]).isEmpty,
                     "the DDC service of a native display cannot prematurely end HDMI discovery")
        var hdmiEndpoint = BrightnessSupport.ServiceIdentity()
        hdmiEndpoint.productName = "HDMI panel"
        hdmiEndpoint.ordinal = 4
        suite.expect(BrightnessSupport.brightnessServices(displays: desk, candidates: [1],
                        services: [nativeEndpoint, hdmiEndpoint]) == [1: 4]
                     && BrightnessSupport.brightnessServices(displays: [(1, hdmi)], candidates: [1],
                        services: [.init()]) == [1: 0],
                     "the recovered HDMI reaches its own service and a genuinely lone sparse endpoint still works")
        var firstTwin = hdmi, secondTwin = hdmi
        firstTwin.ioDisplayLocation = "port-a"
        secondTwin.ioDisplayLocation = "port-b"
        hdmiEndpoint.ioDisplayLocation = "port-a"
        let twins = [(index: 0, identity: firstTwin), (index: 1, identity: secondTwin)]
        suite.expect(BrightnessSupport.brightnessServices(displays: twins,
                        candidates: [0, 1], services: [hdmiEndpoint]) == [0: 4],
                     "one service behind identical EDIDs belongs only to the matching physical connection")
        let modelOnly = BrightnessSupport.ServiceIdentity(productName: "HDMI panel", ordinal: 5)
        for displays in [twins, Array(twins.reversed())] {
            for services in [[hdmiEndpoint, modelOnly], [modelOnly, hdmiEndpoint]] {
                suite.expect(BrightnessSupport.brightnessServices(displays: displays, candidates: [0, 1],
                                services: services) == [0: 4, 1: 5],
                             "the port match leaves the other twin its model-matched service in either order")
            }
        }
        suite.expect(BrightnessSupport.brightnessServices(displays: twins, candidates: [1],
                        services: [hdmiEndpoint, modelOnly]) == [1: 5],
                     "a twin outside the brightness candidates still reserves its port-matched service")
        let otherModelOnly = BrightnessSupport.ServiceIdentity(productName: "HDMI panel", ordinal: 6)
        suite.expect(BrightnessSupport.brightnessServices(displays: twins, candidates: [0, 1],
                        services: [modelOnly, otherModelOnly]).isEmpty,
                     "identical models without a port or serial match leave both services ambiguous")
        suite.expect(BrightnessSupport.brightnessServices(displays: twins, candidates: [0, 1],
                        services: [hdmiEndpoint, modelOnly, otherModelOnly]) == [0: 4],
                     "two equally good services for the remaining twin keep only the port match")
        suite.expect(BrightnessSupport.brightnessServices(displays: twins, candidates: [0, 1],
                        services: [hdmiEndpoint, .init(ordinal: 5)]) == [0: 4],
                     "a leftover service without identity evidence cannot acquire the other twin")
        suite.expect(BrightnessSupport.keepsSoftwareDimOnDiscovery(previouslySoftware: true,
                        dimmed: true, pending: nil)
                     && BrightnessSupport.keepsSoftwareDimOnDiscovery(previouslySoftware: true,
                        dimmed: false, pending: 0.25)
                     && !BrightnessSupport.keepsSoftwareDimOnDiscovery(previouslySoftware: true,
                        dimmed: false, pending: nil),
                     "a recovered service preserves both applied and queued dimming while an untouched panel moves to DDC")
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
