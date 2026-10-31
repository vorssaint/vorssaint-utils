// SPDX-License-Identifier: GPL-3.0-or-later
import CoreAudio
import Foundation

/// Runs the production replacement/remembering bodies without opening audio IO.
/// The bridge boundary records the controls available at its first callback.
enum SoftwareVolumeStartupTests {
    enum Preferences { static var standard: Foundation.UserDefaults! }
    enum HAL {
        static var level = 0.8, muted: UInt32 = 0
        static var levelWriteSucceeds = true, muteWriteSucceeds = true
        static var levelReadback: Double?, muteReadback: UInt32?
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
        struct Failure: Error {
            let issue: VirtualOutputSupport.Issue
            init(_ message: String, issue: VirtualOutputSupport.Issue = .setupFailed) { self.issue = issue }
        }
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
        typealias VirtualOutputHAL = HAL
        typealias VirtualOutputBridge = Bridge
        typealias UserDefaults = Preferences
        typealias DispatchSource = Timers
        var virtual: AudioObjectID? = 99
        var virtualUID = VirtualOutputSupport.deviceUID
        var bridge: Bridge?
        var ownsVirtualOutput = true, suspended = false, isStarting = false
        var error: VirtualOutputSupport.Issue?
        var queue = DispatchQueue(label: "com.vorssaint.tests.startup-controls")
        var timer: Timers.Timer?
        var lastCycles: Int64 = 0, lastProgress = 0.0
        var deactivated = false
        func heartbeat() {}
        func publish(error: VirtualOutputSupport.Issue? = nil) { self.error = error }
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
            HAL.levelWriteSucceeds = true; HAL.muteWriteSucceeds = true
            HAL.levelReadback = nil; HAL.muteReadback = nil; HAL.muteReadSucceeds = true
            let host = Host()
            host.bridge = try! Bridge(virtual: 99, physicalUID: "previous")
            Bridge.firstCallbacks = []
            preferences.set(saved.map { ["destination": $0] } ?? [:], forKey: DefaultsKey.mixerSoftwareVolumes)
            configure()
            host.replaceBridge(physicalUID: "destination")
            return host
        }
        for (saved, muted, expected) in [(0.1, UInt32(0), 0.1), (0, 0, 0), (0.2, 1, 0.2)] {
            let host = replace(saved: saved, previousMuted: muted)
            suite.expect(Bridge.firstCallbacks == [.init(uid: "destination", level: expected, muted: saved == 0 ? 1 : 0)],
                         "replacement first callback uses the destination's saved gain/mute, never the previous output's controls")
            suite.expect(host.bridge?.physicalUID == "destination" && host.error == nil,
                         "validated destination controls permit replacement playback")
            let levels = preferences.dictionary(forKey: DefaultsKey.mixerSoftwareVolumes)
            suite.expect((levels?["previous"] as? NSNumber)?.doubleValue == (muted == 0 ? 0.8 : 0),
                         "replacement remembers the previous output before installing destination controls")
        }
        _ = replace(saved: nil)
        suite.expect(Bridge.firstCallbacks == [.init(uid: "destination", level: 0.5, muted: 0)],
                     "a new destination's first callback starts at the safe default rather than inherited gain")
        let failures: [() -> Void] = [
            { HAL.levelWriteSucceeds = false }, { HAL.muteWriteSucceeds = false },
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
