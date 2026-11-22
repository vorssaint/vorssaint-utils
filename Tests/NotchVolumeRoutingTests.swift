// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

private typealias ProductionNotchSupport = NotchSupport

enum NotchVolumeRoutingTests {
    typealias DispatchQueue = MixerOutputAdjustmentContract.DispatchQueue
    enum AppVolumeMixer {
        typealias OutputKeyResult = MixerOutputAdjustmentContract.Mixer.OutputKeyResult
        static var shared = MixerOutputAdjustmentContract.Mixer()
    }
    enum UserDefaults {
        static let standard = UserDefaults.self
        static var precise = false
        static func bool(forKey key: String) -> Bool {
            key == DefaultsKey.preciseVolumeRollerEnabled && precise
        }
    }
    enum AppFeature {
        case mixer
        static var mixerAvailable = true
        var isAvailable: Bool { Self.mixerAvailable }
    }
    enum NotchSupport {
        enum Module { case volume }
        static func routes(_ module: Module) -> Bool { true }
        static func volumeLevel(current: Double, direction: Int, fine: Bool) -> Double {
            ProductionNotchSupport.volumeLevel(current: current, direction: direction, fine: fine)
        }
    }
    final class NotchService {
        static let shared = NotchService()
        let acceptsSystemFeedback = true
        let showsSystemFeedback = true
        var shownLevels: [Double] = []
        @discardableResult func showCurrentVolume() -> Bool {
            let mixer = AppVolumeMixer.shared
            if let level = mixer.systemOutputVolume {
                shownLevels.append(mixer.systemOutputMuted == true ? 0 : level)
                return true
            }
            return false
        }
    }
    struct NSEvent {
        struct Subtype { let rawValue = 8 }
        let subtype = Subtype()
        let data1: Int
    }
    typealias BrightnessService = DisplaySpeakerVolumeTests.Service
    final class CGEvent {
        var flags: CGEventFlags = []
        var marker: Int64?
        var posts = 0
        func copy() -> CGEvent? { self }
        func setIntegerValueField(_ field: CGEventField, value: Int64) { marker = value }
        func post(tap: CGEventTapLocation) { posts += 1 }
    }
    class State {
        var monitorVolumeKeysHeld: [BrightnessSupport.VolumeKeyAction: BrightnessSupport.SpeakerTarget] = [:]
        static func showMonitorFeedback() { NotchService.shared.showCurrentVolume() }
        var notchKeyGate = NotchVolumeKeyGate()
        var gate = PreciseVolumeRollerGate()
        var keyOwnership = PreciseVolumeKeyOwnership()
        var nativeOutputKeysHeld: [Int32: NativeVolumeKeyPress] = [:]
        var pendingNotchKeys = 0
        var feedbackStep = 0
        var feedback: (key: Int32, step: Int, released: Bool, applied: Bool)?
        static var forwardedReleases: [Int32] = []
        static func postForwardedRelease(_ code: Int32) { forwardedReleases.append(code) }
        static var fineSteps: [Int32] = []
        static func postFineStep(_ code: Int32) { fineSteps.append(code) }
        func playFeedbackIfReady() {}
    }

    static func run(_ suite: TestSuite) {
        typealias Hardware = MixerOutputAdjustmentContract.Hardware
        func reset() -> Service {
            DispatchQueue.main = MixerOutputAdjustmentContract.Queue()
            Hardware.reset()
            UserDefaults.precise = false
            Hardware.volume = 0.5
            AppVolumeMixer.shared = MixerOutputAdjustmentContract.Mixer()
            AppVolumeMixer.shared.selectOutput(1, volume: 0.5, muted: false)
            Service.forwardedReleases = []
            Service.fineSteps = []
            NotchService.shared.shownLevels = []
            return Service()
        }
        func drain() {
            let mixer = AppVolumeMixer.shared
            while !DispatchQueue.main.jobs.isEmpty || !mixer.halQueue.jobs.isEmpty {
                if !DispatchQueue.main.jobs.isEmpty { DispatchQueue.main.runOne() }
                if !mixer.halQueue.jobs.isEmpty { mixer.halQueue.runOne() }
            }
        }
        func press(_ key: PreciseVolumeMediaKey, service: Service, event: CGEvent) -> Bool {
            service.routeNotchVolume(NSEvent(data1: Int(key.rawValue) << 16 | 0x0a00), event: event)
        }

        var service = reset()
        let tap = [0x0a00, 0x0b00]
        let fullPress = [0x0a00, 0x0a01, 0x0b00]
        let fineFlags: CGEventFlags = [.maskAlternate, .maskShift]
        func route(_ key: PreciseVolumeMediaKey, states: [Int], flags: CGEventFlags = [])
            -> (consumed: [Bool], events: [CGEvent]) {
            var events = [CGEvent]()
            let consumed = states.map { state in
                let event = CGEvent()
                event.flags = flags
                events.append(event)
                return service.routeVolumeKey(NSEvent(data1: Int(key.rawValue) << 16 | state), event: event)
            }
            return (consumed, events)
        }
        func checkLearnedNativeKeys() {
            let priorWrites = Hardware.writes
            let priorReleases = Service.forwardedReleases
            let priorQueries = Hardware.queries
            UserDefaults.precise = true
            service.gate.minimumSpacing = -1
            service.gate.reversalWindow = 0
            let down = route(.volumeUp, states: [0x0a00])
            UserDefaults.precise = false
            let held = route(.volumeUp, states: [0x0a01, 0x0b00])
            UserDefaults.precise = true
            let mute = route(.mute, states: tap)
            drain()
            suite.expect(down.consumed == [false] && held.consumed == [false, false]
                         && (down.events + held.events).allSatisfy { $0.flags == fineFlags && $0.posts == 0 && $0.marker == nil },
                         "known native volume keeps fine modifiers through release even when the roller is turned off")
            suite.expect(mute.consumed == [false, false]
                         && mute.events.allSatisfy { $0.flags.isEmpty && $0.posts == 0 && $0.marker == nil },
                         "known native mute keeps its original down and up without fine modifiers")
            suite.expect(Hardware.writes == priorWrites && Hardware.queries == priorQueries
                         && Service.forwardedReleases == priorReleases && Service.fineSteps.isEmpty
                         && NotchService.shared.shownLevels.isEmpty,
                         "later native keys neither repeat the failed plan nor enqueue synthetic feedback")
        }

        Hardware.requiresQuantizedKeys = true
        Hardware.supportsScalarConversion = false
        let mixer = AppVolumeMixer.shared
        mixer.selectOutput(1, volume: nil, muted: false)
        suite.expect(!mixer.prefersNativeOutputKey(.volumeUp),
                     "a mute-only device is not classified as having adjustable virtual volume")
        mixer.selectOutput(1, volume: 0.5, muted: false)
        let nativeUp = route(.volumeUp, states: fullPress)
        suite.expect(nativeUp.consumed == [false, false, false],
                     "virtual-only USB leaves the first physical down, repeat and release to macOS")
        drain()
        suite.expect(nativeUp.events.allSatisfy { $0.posts == 0 && $0.flags.isEmpty && $0.marker == nil }
                     && Service.forwardedReleases.isEmpty && Service.fineSteps.isEmpty
                     && Hardware.writes.isEmpty && Hardware.queries.isEmpty
                     && mixer.systemOutputVolume == 0.5 && NotchService.shared.shownLevels.isEmpty,
                     "native keys do not synthesize a pair, plan a write or announce an unobserved level")
        Hardware.volume = 0.5625
        mixer.readSnapshot(volume: 0.5625, muted: false)
        suite.expect(mixer.systemOutputVolume == 0.5625,
                     "the late native level reaches the mixer after the physical key")

        UserDefaults.precise = true
        let physicalFine = route(.volumeDown, states: fullPress, flags: fineFlags)
        suite.expect(physicalFine.consumed == [false, false, false]
                     && physicalFine.events.allSatisfy { $0.flags == fineFlags && $0.posts == 0 },
                     "an Option-Shift physical press stays native with the precise roller enabled")
        service.gate.minimumSpacing = -1
        service.gate.reversalWindow = 0
        let roller = route(.volumeUp, states: fullPress)
        drain()
        suite.expect(roller.consumed == [false, false, false]
                     && roller.events.allSatisfy { $0.flags == fineFlags && $0.posts == 0 }
                     && Service.fineSteps.isEmpty && Service.forwardedReleases.isEmpty
                     && Hardware.writes.isEmpty && NotchService.shared.shownLevels.isEmpty,
                     "the roller applies fine modifiers to each original native event without a synthetic pair")

        service.gate.minimumSpacing = .infinity
        let suppressed = route(.volumeUp, states: fullPress)
        suite.expect(suppressed.consumed == [true, true, true] && Service.fineSteps.isEmpty,
                     "a roller down rejected for spacing also consumes its repeats and release")

        UserDefaults.precise = false
        suite.expect(route(.mute, states: tap).consumed == [true, true],
                     "a separate USB mute control remains available to the island")
        drain()
        suite.expect(Hardware.muted == true && NotchService.shared.shownLevels == [0],
                     "mute confirms independently of volume-step support")
        mixer.requestOutputAdjustment(volume: 0.375)
        drain()
        suite.expect(Hardware.volume == 0.375 && Hardware.scalarWrites == 0 && mixer.systemOutputVolume == 0.375,
                     "the slider still sets the virtual main volume directly")

        suite.expect(route(.volumeDown, states: [0x0a00]).consumed == [false],
                     "the virtual-only output starts a native hold before the device switches")
        Hardware.device = 2
        Hardware.requiresQuantizedKeys = false
        Hardware.volume = 0.5
        Hardware.muted = false
        mixer.selectOutput(2, volume: 0.5, muted: false)
        suite.expect(route(.volumeDown, states: [0x0a01, 0x0b00]).consumed == [false, false],
                     "a new output leaves the native hold's repeat and release with macOS")
        suite.expect(route(.volumeUp, states: tap).consumed == [true, true],
                     "selecting an ordinary output restores island key ownership")
        drain()
        suite.expect(Hardware.volume == 0.5625 && NotchService.shared.shownLevels.last == 0.5625,
                     "the replacement output applies and announces its first ordinary step")

        service = reset()
        let pendingPress = route(.volumeDown, states: tap)
        suite.expect(pendingPress.consumed == [true, true],
                     "the island claims the press on the initial output")
        Hardware.device = 2
        AppVolumeMixer.shared.selectOutput(2, volume: 0.5, muted: false)
        drain()
        suite.expect(Hardware.writes.isEmpty && pendingPress.events.allSatisfy { $0.posts == 0 }
                     && NotchService.shared.shownLevels.isEmpty,
                     "a device switch before dispatch cannot apply or replay the old press on the new output")

        service = reset()
        let lostMute = CGEvent()
        suite.expect(press(.mute, service: service, event: lostMute), "supported mute is accepted before dispatch")
        AppVolumeMixer.shared.systemOutputMuted = nil
        Hardware.muted = nil
        drain()
        suite.expect(Hardware.writes.isEmpty && AppVolumeMixer.shared.systemOutputVolume == 0.5,
                     "mute capability lost before dispatch must not lower or write volume (writes: \(Hardware.writes))")
        suite.expect(lostMute.posts == 1 && lostMute.marker == PreciseVolumeKeyEvents.postedMarker
                     && Service.forwardedReleases == [7],
                     "mute capability lost before dispatch forwards the native press and release")

        service = reset()
        let ordinaryMute = CGEvent()
        _ = press(.mute, service: service, event: ordinaryMute)
        drain()
        suite.expect(Hardware.writes == [.init(device: 1, volume: nil, muted: true)]
                     && AppVolumeMixer.shared.systemOutputVolume == 0.5 && ordinaryMute.posts == 0,
                     "ordinary mute preserves the stored volume")

        for key in [PreciseVolumeMediaKey.volumeUp, .volumeDown] {
            service = reset()
            let event = CGEvent()
            _ = press(key, service: service, event: event)
            drain()
            let expected: Double = key == .volumeUp ? 0.5625 : 0.4375
            suite.expect(AppVolumeMixer.shared.systemOutputVolume == expected && event.posts == 0
                         && Hardware.writes.contains { $0.volume == Float(expected) },
                         "\(key) still applies its ordinary volume step")
        }
        for initiallyMuted in [false, true] {
            service = reset()
            Hardware.muted = initiallyMuted
            Hardware.accepts = { ($0 * 100).rounded() / 100 }
            AppVolumeMixer.shared.selectOutput(1, volume: 0.5, muted: initiallyMuted)
            let roundedKey = CGEvent()
            _ = press(.volumeUp, service: service, event: roundedKey)
            drain()
            let expectedPercent = initiallyMuted ? 6.0 : 56.0
            suite.expect(Hardware.muted == false && roundedKey.posts == 0
                         && Hardware.writes.compactMap(\.volume).count == 1
                         && NotchService.shared.shownLevels.map { ($0 * 100).rounded() } == [expectedPercent],
                         "a regular output reporting whole percentages confirms its accepted level, including unmuting")
        }
        service = reset()
        Hardware.volume = 0.3
        Hardware.requiresQuantizedKeys = true
        let coarse: (Float32) -> Float32 = { value in
            let levels: [Float32] = [0, 0.05, 0.1, 0.2, 0.3, 0.45, 0.65, 1]
            return levels.min { abs($0 - value) < abs($1 - value) }!
        }
        Hardware.accepts = coarse
        Hardware.quantizes = { coarse($0) }
        AppVolumeMixer.shared.selectOutput(1, volume: 0.3, muted: false)
        Hardware.afterVolumeWrite = {
            suite.expect(abs((AppVolumeMixer.shared.systemOutputVolume ?? -1) - 0.3) < 0.0001
                         && NotchService.shared.shownLevels.isEmpty,
                         "a volume key keeps the confirmed level until its write is read back")
        }
        let coarseKey = CGEvent()
        _ = press(.volumeUp, service: service, event: coarseKey)
        drain()
        suite.expect(Hardware.volume == 0.45 && coarseKey.posts == 0
                     && Hardware.writes.compactMap(\.volume).count == 1,
                     "one intercepted key advances coarse USB volume with one write and no native replay")
        suite.expect(NotchService.shared.shownLevels.map { ($0 * 100).rounded() } == [45],
                     "the notch announces the device's accepted volume instead of the rounded-away request")

        service = reset()
        Hardware.requiresQuantizedKeys = true
        Hardware.volume = 0.3
        Hardware.muted = true
        Hardware.accepts = coarse
        Hardware.quantizes = { coarse($0) }
        AppVolumeMixer.shared.selectOutput(1, volume: 0.3, muted: true)
        let fineUnmute = CGEvent()
        fineUnmute.flags = [.maskAlternate, .maskShift]
        _ = press(.volumeUp, service: service, event: fineUnmute)
        drain()
        suite.expect(Hardware.volume == 0.05 && Hardware.muted == false && fineUnmute.posts == 0
                     && Hardware.writes.compactMap(\.volume).count == 1
                     && NotchService.shared.shownLevels.map { ($0 * 100).rounded() } == [5],
                     "one fine USB key leaves muted stored volume at the first audible step and announces it")

        service = reset()
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { ($0 * 8).rounded() / 8 }
        Hardware.accepts = { _ in 0.5 }
        AppVolumeMixer.shared.selectOutput(1, volume: 0.5, muted: false)
        let ignoredKey = route(.volumeDown, states: tap)
        drain()
        suite.expect(ignoredKey.consumed == [true, true] && ignoredKey.events.allSatisfy { $0.posts == 0 }
                     && Service.forwardedReleases.isEmpty
                     && Hardware.writes.compactMap(\.volume).count == 1
                     && NotchService.shared.shownLevels.isEmpty,
                     "an unconfirmed successful write is neither escalated nor replayed and shows no false confirmation")
        suite.expect(AppVolumeMixer.shared.systemOutputVolume == 0.5,
                     "an ignored key leaves the last confirmed volume published")
        checkLearnedNativeKeys()
        Hardware.volume = 0.375
        AppVolumeMixer.shared.readSnapshot(volume: 0.375, muted: false)
        suite.expect(AppVolumeMixer.shared.systemOutputVolume == 0.375 && Hardware.writes.count == 1,
                     "a late USB acknowledgement is published without reapplying the unconfirmed key")

        service = reset()
        Hardware.requiresQuantizedKeys = true
        AppVolumeMixer.shared.selectOutput(1, volume: 0.5, muted: false)
        Hardware.supportsScalarConversion = false
        let unsupportedPlan = CGEvent()
        _ = press(.volumeUp, service: service, event: unsupportedPlan)
        drain()
        suite.expect(Hardware.writes.isEmpty && unsupportedPlan.posts == 1
                     && Service.forwardedReleases == [PreciseVolumeMediaKey.volumeUp.rawValue]
                     && NotchService.shared.shownLevels.isEmpty,
                     "a volume control lost after the snapshot receives native handling before any hardware write")

        service = reset()
        UserDefaults.precise = true
        Hardware.requiresQuantizedKeys = true
        AppVolumeMixer.shared.selectOutput(1, volume: 0.5, muted: false)
        Hardware.supportsScalarConversion = false
        let preciseFallback = CGEvent()
        _ = press(.volumeUp, service: service, event: preciseFallback)
        drain()
        suite.expect(Hardware.writes.isEmpty && preciseFallback.posts == 1
                     && preciseFallback.flags.contains([.maskAlternate, .maskShift])
                     && Service.forwardedReleases == [PreciseVolumeMediaKey.volumeUp.rawValue]
                     && NotchService.shared.shownLevels.isEmpty,
                     "a USB control lost after the snapshot forwards the precise step with one press and release")

        service = reset()
        UserDefaults.precise = true
        let muteFallback = CGEvent()
        _ = press(.mute, service: service, event: muteFallback)
        Hardware.muted = nil
        drain()
        suite.expect(Hardware.writes.isEmpty && muteFallback.posts == 1
                     && muteFallback.flags.isDisjoint(with: [.maskAlternate, .maskShift])
                     && Service.forwardedReleases == [PreciseVolumeMediaKey.mute.rawValue],
                     "precise roller mode adds no fine-step modifiers to a native mute fallback")

        for missingConversion in [false, true] {
            service = reset()
            Hardware.requiresQuantizedKeys = true
            if missingConversion { Hardware.quantizes = { _ in nil } }
            let selected = AppVolumeMixer.shared
            selected.selectOutput(1, volume: 0.5, muted: false)
            let firstDown = route(.volumeUp, states: [0x0a00])
            drain()
            let firstUp = route(.volumeUp, states: [0x0b00])
            suite.expect(firstDown.consumed == [true] && firstDown.events[0].posts == 1
                         && firstUp.consumed == [true] && firstUp.events[0].posts == 0
                         && Service.forwardedReleases == [PreciseVolumeMediaKey.volumeUp.rawValue]
                         && Hardware.writes.isEmpty && NotchService.shared.shownLevels.isEmpty,
                         "a missing or continuous conversion forwards the first intercepted press once and owns its release")
            var sliderConfirmed = false
            selected.requestOutputAdjustment(volume: 0.375) { sliderConfirmed = $0 }
            let queued = route(.volumeDown, states: tap)
            suite.expect(queued.consumed == [true, true] && queued.events[0].posts == 0 && !sliderConfirmed,
                         "a known native key waits behind a slider write in the same output lifetime")
            drain()
            suite.expect(sliderConfirmed && Hardware.volume == 0.375 && queued.events[0].posts == 1
                         && Service.forwardedReleases == [PreciseVolumeMediaKey.volumeUp.rawValue,
                                                         PreciseVolumeMediaKey.volumeDown.rawValue],
                         "the queued fallback is forwarded once after the slider finishes")
            checkLearnedNativeKeys()

            UserDefaults.precise = false
            Hardware.requiresQuantizedKeys = false
            Hardware.volume = 0.5
            selected.selectOutput(1, volume: 0.5, muted: false)
            let renewed = route(.volumeDown, states: tap)
            drain()
            suite.expect(renewed.consumed == [true, true] && Hardware.volume == 0.4375
                         && NotchService.shared.shownLevels == [0.4375],
                         "a new lifetime revalidates a reused device ID before intercepting a fresh press")
        }

        service = reset()
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { _ in
            Hardware.device = 2
            Hardware.volume = 0.2
            return nil
        }
        let replacedDuringPlanning = CGEvent()
        _ = press(.volumeUp, service: service, event: replacedDuringPlanning)
        drain()
        suite.expect(Hardware.writes.isEmpty && Hardware.volume == 0.2
                     && replacedDuringPlanning.posts == 0 && Service.forwardedReleases.isEmpty
                     && NotchService.shared.shownLevels.isEmpty,
                     "a default change that invalidates conversion consumes the old key instead of falling back on the new output")

        service = reset()
        Hardware.afterVolumeWrite = {
            Hardware.device = 2
            Hardware.volume = 0.2
        }
        let replacedOutput = CGEvent()
        _ = press(.volumeUp, service: service, event: replacedOutput)
        drain()
        suite.expect(Hardware.writes.count == 1 && Hardware.writes[0].device == 1
                     && Hardware.volume == 0.2 && replacedOutput.posts == 0
                     && Service.forwardedReleases.isEmpty && NotchService.shared.shownLevels.isEmpty,
                     "a default change during a write consumes the old key without replay, stale mute or feedback")

        service = reset()
        AppVolumeMixer.shared.systemOutputMuted = nil
        let unsupportedMute = CGEvent()
        suite.expect(!press(.mute, service: service, event: unsupportedMute)
                     && DispatchQueue.main.jobs.isEmpty && Hardware.writes.isEmpty && unsupportedMute.posts == 0,
                     "initially unsupported mute passes through without scheduling or reposting")

        service = reset()
        AppVolumeMixer.shared.monitorOutput = BrightnessSupport.MonitorSpeakerOutput(target: .init(displayID: 7, path: "port-a"), volume: 0.4, muted: nil)
        let monitorUp = CGEvent()
        suite.expect(!press(.volumeUp, service: service, event: monitorUp)
                     && monitorUp.posts == 0 && DispatchQueue.main.jobs.isEmpty && Hardware.writes.isEmpty,
                     "monitor speakers with keys off pass volume keys through to macOS")
        service = reset()
        AppVolumeMixer.shared.monitorOutput = BrightnessSupport.MonitorSpeakerOutput(target: .init(displayID: 7, path: "port-a"), volume: 0.4, muted: false)
        let monitorMute = CGEvent()
        suite.expect(!press(.mute, service: service, event: monitorMute)
                     && monitorMute.posts == 0 && DispatchQueue.main.jobs.isEmpty,
                     "monitor speakers with keys off pass mute through to macOS")

        service = reset()
        let speakers = DisplaySpeakerVolumeTests.connect(AppVolumeMixer.shared, raw: 2)
        func monitorPress(_ data: Int, flags: CGEventFlags = []) -> Bool {
            service.routeMonitorVolume(NSEvent(data1: data), flags: flags)
        }
        let fine: CGEventFlags = [.maskAlternate, .maskShift]
        suite.expect(monitorPress(0x0a00, flags: fine), "the matched display claims the fine volume key")
        speakers.finish()
        suite.expect(speakers.raw == 3 && NotchService.shared.shownLevels == [0.03],
                     "monitor feedback uses the confirmed fine level")
        speakers.selectedAudioOutput = (32, "Monitor B")
        speakers.actualDevice = 32
        speakers.audioRoutes[8] = .init(path: "port-b", fingerprint: "fixture-identity",
                                        service: NSObject(), chipAddress: BrightnessSupport.chipAddress,
                                        hasNativeMute: true, unmutesLeavingZero: false)
        speakers.displays.append(.init(id: 8, name: "Monitor B", audio: .init(target: .init(displayID: 8, path: "port-b"), volume: 0.4, muted: false)))
        suite.expect(monitorPress(0x0a01) && monitorPress(0x0b00), "the old hold owns its repeats and release")
        speakers.finish()
        suite.expect(speakers.writes.count == 1 && NotchService.shared.shownLevels.count == 1,
                     "a held key does not transfer writes or feedback to the new monitor")
        suite.expect(monitorPress(0x0a00, flags: fine) && monitorPress(0x0b00),
                     "a fresh press can start on the newly selected monitor")
        speakers.finish()
        suite.expect(speakers.writtenIDs == [7, 8] && NotchService.shared.shownLevels.last == 0.04,
                     "the new press and its feedback use the new selection")
        speakers.displays[0].name = "Monitor B"
        suite.expect(!monitorPress(0x0a00) && !monitorPress(0x0a01) && !monitorPress(0x0b00),
                     "identical names pass a whole press through even if only one endpoint can write")
        speakers.finish()
        speakers.displays[0].name = "Monitor A"
        speakers.selectedAudioOutput = (31, "Monitor A")
        speakers.actualDevice = 31
        AppVolumeMixer.shared.monitorOutput = speakers.monitorSpeakerOutput()
        speakers.rejectVolume = true
        suite.expect(monitorPress(0x0a00, flags: fine), "the current target can claim a new press")
        speakers.finish()
        suite.expect(NotchService.shared.shownLevels.count == 2 && Hardware.writes.isEmpty,
                     "a rejected DDC transaction never announces a new level or writes HAL")

    }
}
