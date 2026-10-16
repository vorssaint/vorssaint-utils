// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// The complete production watch is extracted on every test build. Only its
/// queues and HAL transport are replaced, so no audio device is touched.
enum MixerLevelCompensationContract {
    final class DispatchQueue {
        private var jobs: [() -> Void] = []
        init(label: String, qos: DispatchQoS) {}
        func async(execute work: @escaping () -> Void) { jobs.append(work) }
        func run() {
            while !jobs.isEmpty { jobs.removeFirst()() }
        }
    }

    final class OperationQueue {
        private var jobs: [() -> Void] = []
        func addOperation(_ work: @escaping () -> Void) { jobs.append(work) }
        func run() {
            while !jobs.isEmpty { jobs.removeFirst()() }
        }
    }

    enum TapGainEngine { static let teardownQueue = OperationQueue() }

    enum HAL {
        struct Registration {
            let object: AudioObjectID
            let address: AudioObjectPropertyAddress
            let callback: AudioObjectPropertyListenerProc
            let client: UnsafeMutableRawPointer?
        }

        static var processes: [AudioObjectID] = []
        static var registrations: [Registration] = []
        static var removalStatus: OSStatus = noErr
        static var removalAttempts: [AudioObjectID] = []

        static func AddPropertyListener(_ object: AudioObjectID,
                                        _ address: UnsafePointer<AudioObjectPropertyAddress>,
                                        _ callback: @escaping AudioObjectPropertyListenerProc,
                                        _ client: UnsafeMutableRawPointer?) -> OSStatus {
            registrations.append(Registration(object: object, address: address.pointee,
                                              callback: callback, client: client))
            return noErr
        }

        static func RemovePropertyListener(_ object: AudioObjectID,
                                           _ address: UnsafePointer<AudioObjectPropertyAddress>,
                                           _ callback: AudioObjectPropertyListenerProc,
                                           _ client: UnsafeMutableRawPointer?) -> OSStatus {
            removalAttempts.append(object)
            let status = object == AudioObjectID(kAudioObjectSystemObject) ? noErr : removalStatus
            if status == noErr || status == kAudioHardwareBadObjectError {
                registrations.removeAll { $0.object == object && $0.client == client }
            }
            return status
        }

        static func announce(_ object: AudioObjectID) {
            for registration in registrations.filter({ $0.object == object }) {
                var address = registration.address
                _ = registration.callback(object, 1, &address, registration.client)
            }
        }
    }

    enum AppVolumeMixer {
        static func audioProcessObjects() -> [AudioObjectID] { HAL.processes }
        static func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope) -> [AudioObjectID] { [] }
        static func defaultOutputDeviceID() -> AudioObjectID? { nil }
        static func subDeviceUIDs(of device: AudioObjectID) -> [String] { [] }
        static func deviceID(forUID uid: String) -> AudioObjectID? { nil }
        static func outputStreamChannels(of device: AudioObjectID) -> [Int] { [] }
        static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                            _ value: inout T, scope: AudioObjectPropertyScope) -> Bool { false }
    }

    static func run(_ suite: TestSuite) {
        guard #available(macOS 14.4, *) else { return }
        removalContract(suite, initial: noErr, final: noErr, name: "successful removal")
        removalContract(suite, initial: kAudioHardwareBadObjectError, final: kAudioHardwareBadObjectError,
                        name: "vanished process")
        removalContract(suite, initial: kAudioHardwareUnspecifiedError, final: noErr,
                        name: "removal that succeeds during stop")
        removalContract(suite, initial: kAudioHardwareUnspecifiedError, final: kAudioHardwareUnspecifiedError,
                        name: "removal still refused during stop")
    }

    private static func removalContract(_ suite: TestSuite, initial: OSStatus, final: OSStatus, name: String) {
        let process: AudioObjectID = 41
        HAL.processes = [process]
        HAL.registrations = []
        HAL.removalAttempts = []
        HAL.removalStatus = initial
        var watch: LevelCompensationWatch? = LevelCompensationWatch.started(everyProcessExcept: [99]) { _ in }
        watch?.queue.run()
        weak var weakWatch: LevelCompensationWatch?
        weakWatch = watch
        let client = HAL.registrations.first { $0.object == process }?.client

        // An unreadable process list also appears empty; it does not prove
        // that the previous process objects and their listeners are gone.
        HAL.processes = []
        HAL.announce(AudioObjectID(kAudioObjectSystemObject))
        watch?.queue.run()
        let removalFailed = initial != noErr && initial != kAudioHardwareBadObjectError
        suite.expect(watch?.listenedObjects.contains(process) == removalFailed,
                     "\(name) tracks an incremental removal until success or a vanished object")
        suite.expect(HAL.registrations.contains { $0.object == process } == removalFailed,
                     "\(name) keeps bookkeeping consistent with the installed callbacks")

        HAL.removalStatus = final
        watch?.stop()
        TapGainEngine.teardownQueue.run()
        watch?.queue.run()
        watch = nil
        let remainsInstalled = removalFailed && final != noErr && final != kAudioHardwareBadObjectError
        suite.expect((weakWatch != nil) == remainsInstalled,
                     "\(name) retains the watch exactly while a callback can still use its client")
        suite.expect(HAL.removalAttempts.filter { $0 == process }.count == (removalFailed ? 2 : 1),
                     "\(name) retries a refused incremental removal during stop")
        if remainsInstalled {
            // Do not invoke a pointer if a regression has released it.
            if let surviving = weakWatch {
                HAL.announce(process)
                surviving.queue.run()
                suite.expect(weakWatch != nil,
                             "a late callback after refused teardown still has a live watch")
            }
            // Dispose only the fixture's intentionally retained failure case
            // after removing every fake registration that could call it.
            HAL.registrations = []
            if weakWatch != nil, let client {
                Unmanaged<LevelCompensationWatch>.fromOpaque(client).release()
            }
        }
        suite.expect(weakWatch == nil && HAL.registrations.isEmpty,
                     "\(name) leaves the fixture without callbacks or retained watches")
    }
}
