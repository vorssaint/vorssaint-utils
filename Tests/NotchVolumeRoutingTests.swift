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
        func showCurrentVolume() {
            let mixer = AppVolumeMixer.shared
            if let level = mixer.systemOutputVolume {
                shownLevels.append(mixer.systemOutputMuted == true ? 0 : level)
            }
        }
    }
    struct NSEvent { let data1: Int }
    final class CGEvent {
        var flags: CGEventFlags = []
        var marker: Int64?
        var posts = 0
        func copy() -> CGEvent? { self }
        func setIntegerValueField(_ field: CGEventField, value: Int64) { marker = value }
        func post(tap: CGEventTapLocation) { posts += 1 }
    }
    class State {
        var notchKeyGate = NotchVolumeKeyGate()
        var gate = PreciseVolumeRollerGate()
        var feedbackStep = 0
        var feedback: (key: Int32, step: Int, released: Bool, applied: Bool)?
        static var forwardedReleases: [Int32] = []
        static func postForwardedRelease(_ code: Int32) { forwardedReleases.append(code) }
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
        Hardware.accepts = { _ in 0.5 }
        let ignoredKey = CGEvent()
        _ = press(.volumeDown, service: service, event: ignoredKey)
        drain()
        suite.expect(ignoredKey.posts == 0 && Service.forwardedReleases.isEmpty
                     && Hardware.writes.compactMap(\.volume).count == 1
                     && NotchService.shared.shownLevels.isEmpty,
                     "an unconfirmed successful write is neither escalated nor replayed and shows no false confirmation")
        suite.expect(AppVolumeMixer.shared.systemOutputVolume == 0.5,
                     "an ignored key leaves the last confirmed volume published")

        service = reset()
        Hardware.requiresQuantizedKeys = true
        Hardware.supportsScalarConversion = false
        let unsupportedPlan = CGEvent()
        _ = press(.volumeUp, service: service, event: unsupportedPlan)
        drain()
        suite.expect(Hardware.writes.isEmpty && unsupportedPlan.posts == 1
                     && Service.forwardedReleases == [PreciseVolumeMediaKey.volumeUp.rawValue]
                     && NotchService.shared.shownLevels.isEmpty,
                     "an output without a safe volume plan receives native handling before any hardware write")

        service = reset()
        UserDefaults.precise = true
        Hardware.requiresQuantizedKeys = true
        Hardware.supportsScalarConversion = false
        let preciseFallback = CGEvent()
        _ = press(.volumeUp, service: service, event: preciseFallback)
        drain()
        suite.expect(Hardware.writes.isEmpty && preciseFallback.posts == 1
                     && preciseFallback.flags.contains([.maskAlternate, .maskShift])
                     && Service.forwardedReleases == [PreciseVolumeMediaKey.volumeUp.rawValue]
                     && NotchService.shared.shownLevels.isEmpty,
                     "unsupported USB native fallback preserves a precise roller's fine step with one press and release")

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

        service = reset()
        Hardware.requiresQuantizedKeys = true
        let continuousConversion = CGEvent()
        _ = press(.volumeUp, service: service, event: continuousConversion)
        drain()
        suite.expect(Hardware.writes.isEmpty && continuousConversion.posts == 1
                     && Service.forwardedReleases == [PreciseVolumeMediaKey.volumeUp.rawValue]
                     && NotchService.shared.shownLevels.isEmpty,
                     "a continuous USB conversion receives native handling without treating equivalence as a hardware step")

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
    }
}
