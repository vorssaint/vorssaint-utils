// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

private typealias ProductionNotchSupport = NotchSupport

enum NotchVolumeRoutingTests {
    typealias DispatchQueue = MixerOutputAdjustmentContract.DispatchQueue
    enum AppVolumeMixer { static var shared = MixerOutputAdjustmentContract.Mixer() }
    enum UserDefaults {
        static let standard = UserDefaults.self
        static func bool(forKey key: String) -> Bool { false }
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
        func showCurrentVolume() {}
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
            Hardware.device = 1
            Hardware.volume = 0.5
            Hardware.muted = false
            Hardware.writes = []
            Hardware.succeeds = true
            Hardware.afterVolumeWrite = nil
            AppVolumeMixer.shared = MixerOutputAdjustmentContract.Mixer()
            AppVolumeMixer.shared.selectOutput(1, volume: 0.5, muted: false)
            Service.forwardedReleases = []
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
        service = reset()
        AppVolumeMixer.shared.systemOutputMuted = nil
        let unsupportedMute = CGEvent()
        suite.expect(!press(.mute, service: service, event: unsupportedMute)
                     && DispatchQueue.main.jobs.isEmpty && Hardware.writes.isEmpty && unsupportedMute.posts == 0,
                     "initially unsupported mute passes through without scheduling or reposting")
    }
}
