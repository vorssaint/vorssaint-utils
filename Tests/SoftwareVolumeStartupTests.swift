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
        static var playback = "physical", effects = "physical"
        static var effectsOnPlaybackSelection: String?
        static func defaultUID(_ selector: AudioObjectPropertySelector = kAudioHardwarePropertyDefaultOutputDevice) -> String? {
            selector == kAudioHardwarePropertyDefaultSystemOutputDevice ? effects : playback
        }
        static func select(_ uid: String, selector: AudioObjectPropertySelector = kAudioHardwarePropertyDefaultOutputDevice) -> Bool {
            if selector == kAudioHardwarePropertyDefaultSystemOutputDevice {
                effects = uid
            } else {
                playback = uid
                if let effectsOnPlaybackSelection { effects = effectsOnPlaybackSelection }
            }
            return true
        }
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
            HAL.playback = "physical"; HAL.effects = "physical"; HAL.effectsOnPlaybackSelection = nil
            let host = Host()
            host.bridge = try! Bridge(virtual: 99, physicalUID: "previous")
            Bridge.firstCallbacks = []
            preferences.set(saved.map { ["destination": ["decibels": MixerSoftwareVolumeSupport.decibels(for: $0)]] } ?? [:], forKey: DefaultsKey.mixerSoftwareVolumes)
            preferences.removeObject(forKey: DefaultsKey.mixerSoftwareMutedDecibels)
            preferences.set(false, forKey: DefaultsKey.mixerPerceptualVolumeEnabled)
            configure()
            host.replaceBridge(physicalUID: "destination")
            return host
        }
        _ = replace(saved: nil)
        suite.expect(HAL.playback == VirtualOutputSupport.deviceUID && HAL.effects == HAL.playback,
                     "effects following physical playback enter the virtual master with it")
        let split = replace(saved: nil) { HAL.effects = "alerts" }
        suite.expect(HAL.playback == VirtualOutputSupport.deviceUID && HAL.effects == "alerts",
                     "activating the virtual master leaves an independent effects destination alone")
        HAL.effects = "manual-alerts"
        split.replaceBridge(physicalUID: "destination")
        suite.expect(HAL.effects == "manual-alerts",
                     "rebuilding the bridge preserves a manual effects selection made during fallback")
        _ = replace(saved: nil) { HAL.effectsOnPlaybackSelection = "new-alerts" }
        suite.expect(HAL.effects == "new-alerts",
                     "an effects change during the playback handoff supersedes the captured follow preference")
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
        func savedValue(_ key: String, _ uid: String) -> Double? {
            preferences.dictionary(forKey: key)?[uid] as? Double
        }
        for perceptual in [false, true] {
            let host = replace(saved: 0.7, previousMuted: 1) {
                HAL.decibelsReadback = -24
                preferences.set(perceptual, forKey: DefaultsKey.mixerPerceptualVolumeEnabled)
            }
            suite.expect(savedValue(DefaultsKey.mixerSoftwareVolumes, "previous") == 0
                         && savedValue(DefaultsKey.mixerSoftwareMutedDecibels, "previous") == -24,
                         "muting stores zero for older builds while retaining the actual gain")
            HAL.decibelsReadback = nil
            Bridge.firstCallbacks = []
            host.replaceBridge(physicalUID: "previous")
            let expected = MixerSoftwareVolumeSupport.level(forDecibels: -24, perceptual: perceptual)
            suite.expect(Bridge.firstCallbacks == [.init(uid: "previous", level: expected, muted: 1)],
                         "returning to the muted output starts silent with its own gain in either curve")
            _ = HAL.write(99, kAudioDevicePropertyMute, value: UInt32(0), scope: kAudioObjectPropertyScopeOutput)
            suite.expect(HAL.muted == 0 && abs(MixerSoftwareVolumeSupport.decibels(for: HAL.level, perceptual: perceptual) + 24) < 0.00001,
                         "unmuting after a rebuild recovers the level without moving the volume slider")
            HAL.decibelsReadback = -24
            host.rememberLevel()
            suite.expect(savedValue(DefaultsKey.mixerSoftwareMutedDecibels, "previous") == nil
                         && savedValue(DefaultsKey.mixerSoftwareVolumes, "previous") == 0.625,
                         "unmuting restores the numeric gain used by older builds")
        }

        let failedReadHost = replace(saved: 0.4)
        HAL.muted = 1; HAL.decibelsReadback = -20
        failedReadHost.rememberLevel()
        HAL.muteReadSucceeds = false; HAL.decibelsReadback = -10
        failedReadHost.rememberLevel()
        suite.expect(savedValue(DefaultsKey.mixerSoftwareVolumes, "destination") == 0
                     && savedValue(DefaultsKey.mixerSoftwareMutedDecibels, "destination") == -20,
                     "an unreadable mute control preserves both saved values")
        HAL.muteReadSucceeds = true; HAL.decibelsReadback = nil
        Bridge.firstCallbacks = []
        Host().replaceBridge(physicalUID: "destination")
        suite.expect(Bridge.firstCallbacks == [.init(uid: "destination", level: 0.6875, muted: 1)],
                     "restarting after a failed mute read keeps the first callback silenced at the previous gain")
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
