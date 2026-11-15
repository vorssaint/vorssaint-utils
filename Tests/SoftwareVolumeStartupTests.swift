// SPDX-License-Identifier: GPL-3.0-or-later
import CoreAudio
import Foundation
import os

/// Runs the production replacement/remembering bodies without opening audio IO.
/// The bridge boundary records the controls available at its first callback.
enum SoftwareVolumeStartupTests {
    enum Preferences { static var standard: Foundation.UserDefaults! }
    enum HAL {
        static var level = 0.8, muted: UInt32 = 0
        static var levelWriteSucceeds = true, muteWriteSucceeds = true, curveWriteSucceeds = true
        static func setPerceptualVolume(_ device: AudioObjectID, enabled: Bool) -> Bool { curveWriteSucceeds }
        static var levelReadback: Double?, muteReadback: UInt32?
        static var decibelsReadback: Double?
        static func outputDecibels(_ device: AudioObjectID) -> Double? {
            decibelsReadback ?? MixerSoftwareVolumeSupport.decibels(for: level)
        }
        static var muteReadSucceeds = true
        static func outputLevel(_ device: AudioObjectID) -> Double? { levelReadback ?? level }
        static func setOutputLevel(_ device: AudioObjectID, level: Double) -> Bool {
            guard levelWriteSucceeds else { return false }
            self.level = level; return true
        }
        static func write<T>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                             value: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> OSStatus {
            if selector == kAudioDevicePropertyMute {
                guard muteWriteSucceeds else { return kAudioHardwareIllegalOperationError }
                muted = value as! UInt32
            }
            return noErr
        }
        static func read<T>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                            into value: inout T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
            guard selector == kAudioDevicePropertyMute, muteReadSucceeds else { return false }
            value = (muteReadback ?? muted) as! T; return true
        }
        static func select(_ uid: String, selector: AudioObjectPropertySelector = kAudioHardwarePropertyDefaultOutputDevice) -> Bool { true }
    }
    final class Bridge {
        struct FirstCallback: Equatable { let uid: String; let level: Double; let muted: UInt32 }
        static var firstCallbacks: [FirstCallback] = []
        let physicalUID: String
        let progress = Progress()
        final class Progress { var cycles: Int64 = 1 }
        typealias Failure = SoftwareVolumeBridgeLifecycleTests.Bridge.Failure
        init(virtual: AudioObjectID, physicalUID: String) throws {
            self.physicalUID = physicalUID
            Self.firstCallbacks.append(.init(uid: physicalUID, level: HAL.level, muted: HAL.muted))
        }
        func stop() {}
    }
    enum Timers {
        static func makeTimerSource(queue: DispatchQueue) -> Timer { Timer() }
        final class Timer {
            func schedule(deadline: DispatchTime, repeating: Int) {}
            func setEventHandler(handler: @escaping () -> Void) {}
            func resume() {}
            func cancel() {}
        }
    }
    final class Host {
        static let log = Logger(subsystem: "com.vorssaint.tests", category: "startup")
        typealias VirtualOutputHAL = HAL
        typealias VirtualOutputBridge = Bridge
        typealias UserDefaults = Preferences
        typealias DispatchSource = Timers
        var virtual: AudioObjectID? = 99
        var virtualUID = VirtualOutputSupport.deviceUID
        var bridge: Bridge?
        var ownsVirtualOutput = true, suspended = false, isStarting = false, perceptualVolume = false, volumeCurveVerified = false
        var error: VirtualOutputSupport.Issue?
        var queue = DispatchQueue(label: "com.vorssaint.tests.startup-controls")
        var timer: Timers.Timer?
        var lastCycles: Int64 = 0, lastProgress = 0.0
        var deactivated = false
        var refreshRequests = 0
        func heartbeat() {}
        func publish(error: VirtualOutputSupport.Issue? = nil, refreshApps: Bool = true) {
            self.error = error
            if refreshApps { refreshRequests += 1 }
        }
        func deactivate() { bridge?.stop(); bridge = nil; ownsVirtualOutput = false; deactivated = true }
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.software-volume-startup"
        let preferences = Foundation.UserDefaults(suiteName: domain)!
        preferences.removePersistentDomain(forName: domain)
        Preferences.standard = preferences
        defer {
            preferences.removePersistentDomain(forName: domain)
            Preferences.standard = nil
        }
        func replace(saved: Double?, previousMuted: UInt32 = 0,
                     configure: () -> Void = {}) -> Host {
            HAL.level = 0.8; HAL.muted = previousMuted
            HAL.levelWriteSucceeds = true; HAL.muteWriteSucceeds = true; HAL.curveWriteSucceeds = true
            HAL.levelReadback = nil; HAL.muteReadback = nil; HAL.muteReadSucceeds = true
            HAL.decibelsReadback = nil
            let host = Host()
            host.bridge = try! Bridge(virtual: 99, physicalUID: "previous")
            Bridge.firstCallbacks = []
            preferences.set(saved.map { ["destination": ["decibels": MixerSoftwareVolumeSupport.decibels(for: $0)]] } ?? [:], forKey: DefaultsKey.mixerSoftwareVolumes)
            preferences.set(false, forKey: DefaultsKey.mixerPerceptualVolumeEnabled)
            configure()
            host.replaceBridge(physicalUID: "destination")
            return host
        }
        for (saved, muted, expected) in [(0.1, UInt32(0), 0.1), (0, 0, 0), (0.2, 1, 0.2)] {
            let host = replace(saved: saved, previousMuted: muted)
            suite.expect(Bridge.firstCallbacks.count == 1 && Bridge.firstCallbacks[0].uid == "destination" && abs(Bridge.firstCallbacks[0].level - expected) < 0.000001 && Bridge.firstCallbacks[0].muted == (saved == 0 ? 1 : 0),
                         "replacement first callback uses the destination's saved gain/mute, never the previous output's controls")
            suite.expect(host.bridge?.physicalUID == "destination" && host.error == nil,
                         "validated destination controls permit replacement playback")
            let levels = preferences.dictionary(forKey: DefaultsKey.mixerSoftwareVolumes)
            suite.expect((levels?["previous"] as? NSNumber)?.doubleValue == (muted == 0 ? 0.8 : 0),
                         "replacement remembers the previous output before installing destination controls")
        }
        _ = replace(saved: nil)
        suite.expect(Bridge.firstCallbacks == [.init(uid: "destination", level: MixerSoftwareVolumeSupport.savedLevel(nil), muted: 0)],
                     "a new destination's first callback starts at the safe default rather than inherited gain")
        let curveHost = replace(saved: 0.5) {
            preferences.set(true, forKey: DefaultsKey.mixerPerceptualVolumeEnabled)
        }
        suite.expect(curveHost.perceptualVolume && abs((Bridge.firstCallbacks.first?.level ?? -1) - 0.1088188204120155) < 0.00001,
                     "opt-in curve is configured before the first callback and preserves the destination's -32 dB")
        let readbackHost = replace(saved: 0.5)
        // A curve write may succeed while verification fails. Save actual dB,
        // even if the app cannot yet confirm the driver's current UI mapping.
        HAL.level = 0.1088188204120155; HAL.decibelsReadback = -32
        readbackHost.rememberLevel()
        let remembered = preferences.dictionary(forKey: DefaultsKey.mixerSoftwareVolumes)?["destination"] as? NSNumber
        suite.expect(remembered?.doubleValue == 0.5,
                     "actual dB survives an unverified curve change in the numeric format older apps understand")
        let liveHost = replace(saved: 0.5)
        let activeBridge = liveHost.bridge
        let refreshesBeforeFailure = liveHost.refreshRequests
        HAL.curveWriteSucceeds = false
        preferences.set(true, forKey: DefaultsKey.mixerPerceptualVolumeEnabled)
        liveHost.updateVolumeCurve()
        suite.expect(liveHost.bridge === activeBridge && liveHost.ownsVirtualOutput && !liveHost.suspended && !liveHost.deactivated,
                     "a failed live curve verification never releases attenuation or restores raw output")
        suite.expect(liveHost.error == .curveFailed && !liveHost.volumeCurveVerified,
                     "an unverified curve is reported and remains retryable")
        suite.expect(liveHost.refreshRequests == refreshesBeforeFailure,
                     "curve failures cannot trigger the refreshApps-to-sync retry feedback loop")
        // Flip back after a write succeeded but its readback could not be
        // verified: this must reapply even when the last confirmed mode matches.
        preferences.set(false, forKey: DefaultsKey.mixerPerceptualVolumeEnabled)
        HAL.curveWriteSucceeds = true
        liveHost.updateVolumeCurve()
        suite.expect(liveHost.volumeCurveVerified && !liveHost.perceptualVolume && liveHost.error == nil && liveHost.bridge === activeBridge,
                     "retrying the previous mode reconciles uncertain driver state without rebuilding IO")
        let failures: [() -> Void] = [
            { HAL.curveWriteSucceeds = false }, { HAL.levelWriteSucceeds = false }, { HAL.muteWriteSucceeds = false },
            { HAL.levelReadback = 0.8 }, { HAL.muteReadback = 1 },
            { HAL.muteReadSucceeds = false }
        ]
        for configure in failures {
            let host = replace(saved: 0.1, configure: configure)
            suite.expect(Bridge.firstCallbacks.isEmpty,
                         "failed or mismatching master controls never start physical playback")
            suite.expect(host.deactivated && host.suspended && host.bridge == nil && host.error != nil,
                         "master initialization failure releases ownership and reports setup failure")
        }
    }
}
