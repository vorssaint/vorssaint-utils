// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AudioToolbox
import Combine
import CoreAudio
import Foundation

/// Production input and mute services use controlled HAL data, queues and
/// preferences. No microphone, hotkey or real user preference is changed.
enum MixerInputVolumeContract {
    final class DispatchQueue {
        static let main = DispatchQueue(label: "main", qos: .default)
        static var queues: [DispatchQueue] = []
        var work: [() -> Void] = []
        var delayed: [DispatchWorkItem] = []
        var timedEnqueues = 0
        init(label: String, qos: DispatchQoS) { Self.queues.append(self) }
        func async(execute: @escaping () -> Void) { work.append(execute) }
        func asyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) {
            timedEnqueues += 1
            work.append(execute)
        }
        func asyncAfter(deadline: DispatchTime, execute: DispatchWorkItem) { delayed.append(execute) }
        func runTimers() {
            let pending = delayed
            delayed.removeAll()
            for item in pending where !item.isCancelled { item.perform() }
        }
        func sync<T>(execute: () -> T) -> T {
            while !work.isEmpty { run() }
            return execute()
        }
        func run() { if !work.isEmpty { work.removeFirst()() } }
        static func drain() {
            for _ in 0..<100 {
                if queues.allSatisfy({ $0.work.isEmpty }) { return }
                for q in queues { q.run() }
            }
            fatalError("queue did not settle")
        }
    }
    enum AppFeature {
        case mixer, audioPriority, micMute
        static var micMuteAvailable = true
        var isAvailable: Bool {
            switch self {
            case .micMute: return Self.micMuteAvailable
            default: return true
            }
        }
    }
    enum DefaultsKey {
        static let preferredInputDevice = "preferred"
        static let audioPriorityInputEnabled = "audioPriorityInputEnabled"
        static let micMuteActive = "mute"
        static let micMuteReleasePending = "releasePending"
        static let micMuteReleasedUIDs = "releasedUIDs"
        static let micMuteFollowCallApps = "followCallApps"
        static let micMuteSavedVolumes = "savedVolumes"
        static let micMuteSavedChannelVolumes = "savedChannelVolumes"
        static let micMuteSavedControls = "savedControls"
        static let micMuteProtectedChannels = "protectedChannels"
        static let micMutePendingLegacyControls = "pendingLegacyControls"
        static let micMuteMixerHandoffUID = "mixerHandoffUID"
        static let micMuteManualCheckNeeded = "manualCheckNeeded"
        static let micMuteMutedDevices = "owned"
        static let micMuteSavedVolume = "legacyVolume"
        static let micMuteShortcutEnabled = "shortcutEnabled"
        static let micMuteShortcut = "shortcut"
    }
    enum Defaults { static func sanitizedPreferredInputDeviceUID(_ s: String?) -> String? { s } }
    enum UserDefaults {
        static let standard = Store()
        final class Store {
            var values: [String: Any] = [:]
            var writtenKeys: [String] = []
            var afterChange: ((String) -> Void)?
            func object(forKey k: String) -> Any? { values[k] }
            func data(forKey k: String) -> Data? { values[k] as? Data }
            func string(forKey k: String) -> String? { values[k] as? String }
            func bool(forKey k: String) -> Bool { values[k] as? Bool ?? false }
            func double(forKey k: String) -> Double { values[k] as? Double ?? 0 }
            func dictionary(forKey k: String) -> [String: Any]? { values[k] as? [String: Any] }
            func stringArray(forKey k: String) -> [String]? { values[k] as? [String] }
            func set(_ v: Any, forKey k: String) {
                values[k] = v
                writtenKeys.append(k)
                afterChange?(k)
            }
            func removeObject(forKey k: String) {
                values[k] = nil
                afterChange?(k)
            }
        }
    }
    final class QuickToolHotkey {
        var onPress: (() -> Void)?
        init(id: Int) {}
        func sync(enabled: Bool, shortcut: GlobalShortcut, storageKey: String) -> Bool { true }
        func unregister() {}
    }
    struct GlobalShortcut {
        static let micMuteDefault = GlobalShortcut()
        static func saved(for key: String, fallback: GlobalShortcut) -> GlobalShortcut { fallback }
    }
    enum QuickToolHUD {
        static var messages: [String] = []
        static var showedFullMessage = false
        static func show(icon: String, message: String, showsFullMessage: Bool = false) {
            messages.append(message)
            showedFullMessage = showsFullMessage
        }
    }
    final class NotchService {
        static let shared = NotchService()
        var showsMicrophone = false
        var microphone: [Bool] = []
        func showMicrophone(muted: Bool) -> Bool {
            guard showsMicrophone else { return false }
            microphone.append(muted)
            return true
        }
        var retractions = 0
        func retractMicrophoneNotice() { retractions += 1 }
        var reactions: [NotchMascotReaction] = []
        func reactMascot(_ reaction: NotchMascotReaction) { reactions.append(reaction) }
    }
    enum L10n {
        static let shared = Strings()
        struct Strings {
            var s: Strings { self }
            let micMutedHUD = "muted"
            let micUnmutedHUD = "unmuted"
            let micMutePartialHUD = "mute partial"
            let micUnmutePartialHUD = "unmute partial"
            let micRestoreExhaustedHUD = "adjust microphone in mixer"
            let micManualRestore = "check original microphone"
        }
    }
    struct Key: Hashable {
        let d: UInt32
        let s: UInt32
        let e: UInt32
        let scope: AudioObjectPropertyScope
        init(_ d: UInt32, _ a: AudioObjectPropertyAddress) {
            self.d = d
            s = a.mSelector
            e = a.mElement
            scope = a.mScope
        }
    }
    enum HAL {
        static var levels: [Key: Float] = [:]
        static var minimumGain: [Key: Float] = [:]
        static var readOnly: Set<Key> = []
        static var settableReadFails: Set<Key> = []
        static var accessQueries: [Key: Int] = [:]
        static var readFails: Set<Key> = []
        static var nextReadFails: Set<Key> = []
        static var sizeReadFails: Set<Key> = []
        static var writeFails: Set<Key> = []
        static var mute: [UInt32: UInt32] = [:]
        static var muteElements: [Key: UInt32] = [:]
        static var writes: [Key] = []
        private struct ListenerIdentity: Hashable {
            let procedure: UInt
            let client: UnsafeMutableRawPointer?

            init(_ callback: @escaping AudioObjectPropertyListenerProc, _ client: UnsafeMutableRawPointer?) {
                procedure = unsafeBitCast(callback, to: UInt.self)
                self.client = client
            }
        }
        private static var notifications: [Key: [ListenerIdentity: AudioObjectPropertyListenerProc]] = [:]
        static var listeners: Set<Key> { Set(notifications.keys) }
        static var listenerAdds: [Key] = []
        static var listenerRemovals: [Key] = []
        static var afterListenerAdd: [Key: () -> Void] = [:]
        static var afterListenerRemoval: [Key: () -> Void] = [:]
        static var failedListenerKeys: Set<Key> = []
        static var failedListenerRemovals: Set<Key> = []
        static var listenerFails = false
        static var ignoreWrites = false
        static var ignoredWrites: Set<Key> = []
        static var devices: [UInt32] = [10]
        static var deviceListReads = 0
        static var inputsWithoutStreams: Set<UInt32> = []
        static var inactiveDevices: Set<UInt32> = []
        static var streamChannels: [UInt32: [UInt32]] = [:]
        static var returnedLayoutBytes: [UInt32: UInt32] = [:]
        static var streamReadFails = false
        static var afterWrite: (() -> Void)?
        static var afterGainRead: [Key: () -> Void] = [:]
        static var afterSwitchRead: [Key: () -> Void] = [:]
        static var afterSettableCheck: [Key: () -> Void] = [:]
        static var beforeControlWrite: ((Key, Double) -> Void)?
        static var afterControlWrite: ((Key) -> Void)?
        static var afterUIDRead: (() -> Void)?
        /// The audio server's process list: each process, whether it is
        /// recording, and from which devices.
        static var processes: [(object: UInt32, pid: Int32, recording: Bool, devices: [UInt32])] = []
        static var processListReads = 0
        static var afterProcessListRead: (() -> Void)?
        static var current: UInt32 = 10
        static var uids: [UInt32: String] = [:]
        static var aggregates: Set<UInt32> = []
        static var aggregateMembers: [UInt32: [UInt32]] = [:]
        static var virtual: Set<UInt32> = []
        static var running: Set<UInt32> = []
        static func key(_ d: UInt32, _ e: UInt32 = 0, _ s: UInt32 = kAudioDevicePropertyVolumeScalar,
                        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeInput)
            -> Key
        {
            Key(
                d,
                AudioObjectPropertyAddress(
                    mSelector: s, mScope: scope, mElement: e))
        }
        static func reset() {
            levels = [:]
            minimumGain = [:]
            readOnly = []
            settableReadFails = []
            accessQueries = [:]
            readFails = []
            nextReadFails = []
            sizeReadFails = []
            writeFails = []
            mute = [:]
            muteElements = [:]
            writes = []
            listenerAdds = []
            listenerRemovals = []
            afterListenerAdd = [:]
            afterListenerRemoval = [:]
            failedListenerKeys = []
            failedListenerRemovals = []
            listenerFails = false
            ignoreWrites = false
            ignoredWrites = []
            devices = [10]
            deviceListReads = 0
            inputsWithoutStreams = []
            inactiveDevices = []
            current = 10
            uids = [:]
            aggregates = []
            aggregateMembers = [:]
            virtual = []
            running = []
            streamChannels = [:]
            returnedLayoutBytes = [:]
            streamReadFails = false
            afterWrite = nil
            afterGainRead = [:]
            afterSwitchRead = [:]
            afterSettableCheck = [:]
            beforeControlWrite = nil
            afterControlWrite = nil
            afterUIDRead = nil
            processes = []
            processListReads = 0
            afterProcessListRead = nil
            UserDefaults.standard.afterChange = nil
            UserDefaults.standard.values = [:]
            AppFeature.micMuteAvailable = true
            relaunchClient()
        }
        static func relaunchClient() {
            notifications.removeAll()
            MicMuteService.shared = MicMuteService()
        }
        static func HasProperty(_ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>) -> Bool {
            let key = Key(d, a.pointee)
            switch key.s {
            case kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice,
                 kAudioHardwarePropertyServiceRestarted:
                return d == AudioObjectID(kAudioObjectSystemObject) && key.e == 0
                    && key.scope == kAudioObjectPropertyScopeGlobal
            case kAudioObjectPropertyControlList, kAudioDevicePropertyDeviceHasChanged,
                 kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioDevicePropertyDeviceIsAlive:
                return devices.contains(d) && key.e == 0 && key.scope == kAudioObjectPropertyScopeGlobal
            case kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyStreams:
                return devices.contains(d) && key.e == 0 && key.scope == kAudioDevicePropertyScopeInput
            case kAudioAggregateDevicePropertyActiveSubDeviceList:
                return aggregates.contains(d) && key.e == 0 && key.scope == kAudioObjectPropertyScopeGlobal
            case kAudioDevicePropertyMute:
                return muteElements[key] != nil
                    || (key.e == 0 && key.scope == kAudioDevicePropertyScopeInput && mute[d] != nil)
            default:
                return levels[key] != nil
            }
        }
        static func IsPropertySettable(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>,
            _ v: UnsafeMutablePointer<DarwinBoolean>
        ) -> OSStatus {
            let key = Key(d, a.pointee)
            accessQueries[key, default: 0] += 1
            if settableReadFails.contains(key) { return -1 }
            v.pointee = DarwinBoolean(!readOnly.contains(key))
            afterSettableCheck.removeValue(forKey: key)?()
            return noErr
        }
        static func GetPropertyDataSize(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>, _ q: UInt32,
            _ qp: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>
        ) -> OSStatus {
            if sizeReadFails.contains(Key(d, a.pointee)) { return -1 }
            if a.pointee.mSelector == kAudioAggregateDevicePropertyActiveSubDeviceList {
                guard let members = aggregateMembers[d] else { return -1 }
                size.pointee = UInt32(members.count * MemoryLayout<AudioObjectID>.size)
                return noErr
            }
            if a.pointee.mSelector == kAudioDevicePropertyStreams {
                size.pointee = inputsWithoutStreams.contains(d) ? 0 : UInt32(MemoryLayout<AudioStreamID>.size)
                return noErr
            }
            if a.pointee.mSelector == kAudioDevicePropertyStreamConfiguration {
                size.pointee = UInt32(
                    MemoryLayout<AudioBufferList>.size + max(0, (streamChannels[d] ?? [2]).count - 1)
                        * MemoryLayout<AudioBuffer>.stride)
                return streamReadFails ? -1 : noErr
            }
            if a.pointee.mSelector == kAudioHardwarePropertyProcessObjectList {
                size.pointee = UInt32(processes.count * 4)
                return noErr
            }
            if a.pointee.mSelector == kAudioProcessPropertyDevices {
                guard a.pointee.mScope == kAudioObjectPropertyScopeInput else { return -1 }
                size.pointee = UInt32((processes.first { $0.object == d }?.devices.count ?? 0) * 4)
                return noErr
            }
            size.pointee =
                a.pointee.mSelector == kAudioHardwarePropertyDevices ? UInt32(devices.count * 4) : 4
            return noErr
        }
        static func GetPropertyData(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>, _ q: UInt32,
            _ qp: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>, _ p: UnsafeMutableRawPointer
        ) -> OSStatus {
            let k = Key(d, a.pointee)
            if readFails.contains(k) || nextReadFails.remove(k) != nil { return -1 }
            if let v = levels[k] {
                p.storeBytes(of: v, as: Float.self)
                afterGainRead.removeValue(forKey: k)?()
                return noErr
            }
            switch a.pointee.mSelector {
            case kAudioAggregateDevicePropertyActiveSubDeviceList:
                guard let members = aggregateMembers[d] else { return -1 }
                for (i, id) in members.enumerated() {
                    p.storeBytes(of: id, toByteOffset: i * MemoryLayout<AudioObjectID>.size, as: UInt32.self)
                }
            case kAudioDevicePropertyStreamConfiguration:
                if streamReadFails { return -1 }
                let channels = streamChannels[d] ?? [2]
                let list = p.assumingMemoryBound(to: AudioBufferList.self)
                list.pointee.mNumberBuffers = UInt32(channels.count)
                let buffers = UnsafeMutableAudioBufferListPointer(list)
                for (i, n) in channels.enumerated() {
                    buffers[i] = AudioBuffer(mNumberChannels: n, mDataByteSize: 0, mData: nil)
                }
                if let bytes = returnedLayoutBytes[d] { size.pointee = bytes }
            case kAudioHardwarePropertyDevices:
                deviceListReads += 1
                for (i, v) in devices.enumerated() {
                    p.storeBytes(of: v, toByteOffset: i * 4, as: UInt32.self)
                }
            case kAudioHardwarePropertyDefaultInputDevice: p.storeBytes(of: current, as: UInt32.self)
            case kAudioHardwarePropertyProcessObjectList:
                processListReads += 1
                for (i, process) in processes.enumerated() {
                    p.storeBytes(of: process.object, toByteOffset: i * 4, as: UInt32.self)
                }
                let callback = afterProcessListRead
                afterProcessListRead = nil
                callback?()
            case kAudioProcessPropertyPID:
                guard let process = processes.first(where: { $0.object == d }) else { return -1 }
                p.storeBytes(of: process.pid, as: Int32.self)
            case kAudioProcessPropertyIsRunningInput:
                guard let process = processes.first(where: { $0.object == d }) else { return -1 }
                p.storeBytes(of: UInt32(process.recording ? 1 : 0), as: UInt32.self)
            case kAudioProcessPropertyDevices:
                guard a.pointee.mScope == kAudioObjectPropertyScopeInput,
                      let process = processes.first(where: { $0.object == d }) else { return -1 }
                for (i, device) in process.devices.enumerated() {
                    p.storeBytes(of: device, toByteOffset: i * 4, as: UInt32.self)
                }
            case kAudioDevicePropertyDeviceUID, kAudioObjectPropertyName:
                p.assumingMemoryBound(to: CFString.self).pointee = (uids[d] ?? "device-\(d)") as CFString
                let callback = afterUIDRead
                afterUIDRead = nil
                callback?()
            case kAudioDevicePropertyDeviceIsAlive:
                p.storeBytes(of: UInt32(inactiveDevices.contains(d) ? 0 : 1), as: UInt32.self)
            case kAudioDevicePropertyDeviceCanBeDefaultDevice:
                p.storeBytes(of: UInt32(1), as: UInt32.self)
            case kAudioDevicePropertyIsHidden: p.storeBytes(of: UInt32(0), as: UInt32.self)
            case kAudioDevicePropertyTransportType:
                if virtual.contains(d) {
                    p.storeBytes(of: kAudioDeviceTransportTypeVirtual, as: UInt32.self)
                } else if aggregates.contains(d) {
                    p.storeBytes(of: kAudioDeviceTransportTypeAggregate, as: UInt32.self)
                } else {
                    return -1
                }
            case kAudioDevicePropertyDeviceIsRunningSomewhere:
                p.storeBytes(of: UInt32(running.contains(d) ? 1 : 0), as: UInt32.self)
            case kAudioDevicePropertyMute:
                guard let v = muteElements[k] ?? (a.pointee.mElement == 0 ? mute[d] : nil) else { return -1 }
                p.storeBytes(of: v, as: UInt32.self)
                afterSwitchRead.removeValue(forKey: k)?()
            default: return -1
            }
            return noErr
        }
        static func SetPropertyData(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>, _ q: UInt32,
            _ qp: UnsafeRawPointer?, _ size: UInt32, _ p: UnsafeRawPointer
        ) -> OSStatus {
            let k = Key(d, a.pointee)
            writes.append(k)
            defer { afterControlWrite?(k) }
            if let beforeControlWrite {
                if k.s == kAudioDevicePropertyMute {
                    beforeControlWrite(k, Double(p.load(as: UInt32.self)))
                } else if levels[k] != nil {
                    beforeControlWrite(k, Double(p.load(as: Float.self)))
                }
            }
            if writeFails.contains(k) { return -1 }
            if ignoreWrites || ignoredWrites.contains(k) { return noErr }
            if a.pointee.mSelector == kAudioHardwarePropertyDefaultInputDevice {
                current = p.load(as: UInt32.self)
                return noErr
            }
            if a.pointee.mSelector == kAudioDevicePropertyMute {
                if muteElements[k] != nil {
                    muteElements[k] = p.load(as: UInt32.self)
                } else if a.pointee.mElement == 0, mute[d] != nil {
                    mute[d] = p.load(as: UInt32.self)
                } else {
                    return -1
                }
                return noErr
            }
            guard levels[k] != nil else { return -1 }
            levels[k] = max(p.load(as: Float.self), minimumGain[k] ?? 0)
            let callback = afterWrite
            afterWrite = nil
            callback?()
            return noErr
        }
        static func AddPropertyListener(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>,
            _ cb: @escaping AudioObjectPropertyListenerProc, _ client: UnsafeMutableRawPointer?
        ) -> OSStatus {
            let key = Key(d, a.pointee)
            listenerAdds.append(key)
            if listenerFails || failedListenerKeys.contains(key) { return -1 }
            notifications[key, default: [:]][ListenerIdentity(cb, client)] = cb
            afterListenerAdd.removeValue(forKey: key)?()
            return noErr
        }
        @discardableResult
        static func RemovePropertyListener(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>,
            _ cb: @escaping AudioObjectPropertyListenerProc, _ client: UnsafeMutableRawPointer?
        ) -> OSStatus {
            let key = Key(d, a.pointee)
            listenerRemovals.append(key)
            if failedListenerRemovals.contains(key) { return kAudioHardwareNotReadyError }
            if notifications[key] != nil {
                guard notifications[key]?.removeValue(forKey: ListenerIdentity(cb, client)) != nil
                else { return kAudioHardwareIllegalOperationError }
                if notifications[key]?.isEmpty == true { notifications.removeValue(forKey: key) }
            }
            afterListenerRemoval.removeValue(forKey: key)?()
            return noErr
        }
        static func soleListenerClient(for key: Key) -> UnsafeMutableRawPointer? {
            guard let registrations = notifications[key], registrations.count == 1 else { return nil }
            return registrations.keys.first?.client
        }
        static func pendingNotification(for key: Key, changes: [Key]? = nil) -> (() -> Void)? {
            guard let callbacks = notifications[key] else { return nil }
            let changed = changes ?? [key]
            guard !changed.isEmpty, changed.allSatisfy({ $0.d == key.d }) else { return nil }
            let addresses = changed.map { AudioObjectPropertyAddress(mSelector: $0.s, mScope: $0.scope, mElement: $0.e) }
            return {
                addresses.withUnsafeBufferPointer { buffer in
                    guard let first = buffer.baseAddress else { return }
                    for (identity, callback) in callbacks {
                        _ = callback(key.d, UInt32(buffer.count), first, identity.client)
                    }
                }
            }
        }
        @discardableResult
        static func notifyIfRegistered(_ key: Key, changes: [Key]? = nil) -> Bool {
            guard let notify = pendingNotification(for: key, changes: changes) else { return false }
            notify()
            return true
        }
        @discardableResult
        static func restartAudioService() -> Bool {
            let reset = key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyServiceRestarted,
                            scope: kAudioObjectPropertyScopeGlobal)
            let notify = pendingNotification(for: reset)
            notifications.removeAll()
            notify?()
            return notify != nil
        }
        static func dropListeners(forDevice device: UInt32) {
            notifications = notifications.filter { $0.key.d != device }
        }
    }
    static func run(_ suite: TestSuite) {
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            suite.expect(condition(), name)
        }
        func signal(_ key: Key) {
            check(HAL.notifyIfRegistered(key), "the HAL delivers the registered property notification")
        }
        func near(_ x: Double?, _ y: Double) -> Bool { x.map { abs($0 - y) < 0.0001 } ?? false }
        func manager() -> AudioInputDeviceManager {
            let m = AudioInputDeviceManager()
            m.start()
            DispatchQueue.drain()
            return m
        }
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.4
        var m = manager()
        check(near(m.inputVolume, 0.4), "initial discovery publishes gain")
        m.setInputVolume(0.7)
        DispatchQueue.drain()
        check(near(m.inputVolume, 0.7), "normal write and readback")
        HAL.ignoreWrites = true
        m.setInputVolume(0.8)
        DispatchQueue.drain()
        check(near(m.inputVolume, 0.7), "successful ignored write reads back")
        HAL.ignoreWrites = false
        HAL.writeFails.insert(HAL.key(10))
        m.setInputVolume(0.9)
        DispatchQueue.drain()
        check(near(m.inputVolume, 0.7), "failed write reads back")
        m.stop()
        DispatchQueue.drain()
        check(m.inputVolume == nil && HAL.listeners.isEmpty, "stop clears volume and observers")
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.6
        HAL.readOnly.insert(HAL.key(10))
        m = manager()
        check(m.inputVolume == nil, "read-only gain hidden")
        m.stop()
        for (label, bad) in [("positive infinity", Float.infinity),
                             ("negative infinity", -Float.infinity),
                             ("NaN", Float.nan)] {
            HAL.reset()
            HAL.levels[HAL.key(10)] = bad
            m = manager()
            check(m.inputVolume == nil, "\(label) main gain is hidden")
            m.stop()
            HAL.reset()
            HAL.levels[HAL.key(10, 1)] = 0.4
            HAL.levels[HAL.key(10, 2)] = bad
            m = manager()
            check(m.inputVolume == nil, "\(label) on one channel hides the gain")
            m.stop()
        }
        HAL.reset()
        HAL.levels[HAL.key(10)] = -0.5
        m = manager()
        check(near(m.inputVolume, 0), "negative gain clamps to 0")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 1.5
        m = manager()
        check(near(m.inputVolume, 1), "gain above 1 clamps to 1")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10, 1)] = 0.2
        HAL.levels[HAL.key(10, 2)] = 0.8
        m = manager()
        check(near(m.inputVolume, 0.5), "channel mean")
        m.setInputVolume(0.6)
        DispatchQueue.drain()
        check(HAL.levels.values.allSatisfy { abs($0 - 0.6) < 0.0001 }, "writes both channels")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10, 0, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)] = 0.5
        HAL.levels[HAL.key(10)] = 0.5
        HAL.levels[HAL.key(10, 1)] = 0.2
        HAL.levels[HAL.key(10, 2)] = 0.8
        m = manager()
        m.setInputVolume(0.6)
        DispatchQueue.drain()
        check(
            HAL.writes.count == 1
                && HAL.writes[0].s == kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            "virtual master preferred and channel balance intact")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.3
        m = manager()
        HAL.devices = [10, 20]
        HAL.current = 20
        m.refreshAndApply()
        m.setInputVolume(0.8)
        DispatchQueue.drain()
        check(
            m.effectiveInputDeviceUID == "device-20" && m.inputVolume == nil,
            "device changes during drag clear unsupported volume")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.4
        m = manager()
        m.scheduleVolumeRefresh(for: 10)
        DispatchQueue.main.run()
        m.halQueue.run()
        m.setInputVolume(0.9)
        DispatchQueue.main.run()
        check(near(m.inputVolume, 0.9), "older volume result cannot undo latest drag")
        DispatchQueue.drain()
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.4
        HAL.listenerFails = true
        HAL.ignoreWrites = true
        m = manager()
        m.setInputVolume(0.9)
        DispatchQueue.drain()
        check(near(m.inputVolume, 0.4), "listener failure still reads back ignored writes")
        m.stop()
        HAL.reset()
        HAL.streamChannels[10] = [1, 3]
        for channel: UInt32 in 1...4 { HAL.levels[HAL.key(10, channel)] = 0.5 }
        m = manager()
        m.setInputVolume(0)
        DispatchQueue.drain()
        check(
            near(m.inputVolume, 0) && HAL.levels[HAL.key(10, 3)] == 0 && HAL.levels[HAL.key(10, 4)] == 0,
            "all input channels across multiple streams follow the slider")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        check(
            MicMuteService.shared.isMuted && MicMuteService.inputControls(10).isSilenced,
            "production mute falls back to zero gain")
        m.setInputVolume(0.8)
        DispatchQueue.drain()
        check(
            MicMuteService.inputControls(10).isSilenced && MicMuteService.shared.isMuted,
            "slider preserves the active gain mute")
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(
            !MicMuteService.shared.isMuted && HAL.levels[HAL.key(10)] == 0.5,
            "explicit unmute restores the saved gain")
        m.setInputVolume(0.8)
        DispatchQueue.drain()
        check(near(m.inputVolume, 0.8), "gain remains adjustable after unmute")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        HAL.mute[10] = 0
        m = manager()
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        m.setInputVolume(0.8)
        DispatchQueue.drain()
        check(MicMuteService.inputControls(10).isSilenced, "hardware mute switch remains silent after gain gesture")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        m.stop()
        DispatchQueue.drain()
        check(
            HAL.levels[HAL.key(10)] == 0.5 && m.inputVolume == nil, "stop cancels queued volume writes")

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.2
        m = manager()
        HAL.devices = [20]
        HAL.current = 20
        HAL.uids[20] = "device-10"
        HAL.levels[HAL.key(20)] = 0.7
        m.refreshAndApply()
        m.halQueue.run()
        m.scheduleVolumeRefresh(for: 10)
        DispatchQueue.main.run()
        DispatchQueue.drain()
        check(
            m.inputDevices.first?.audioObjectID == 20 && near(m.inputVolume, 0.7),
            "same UID reconnect publishes new gain despite old notification")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.2
        m = manager()
        HAL.devices = [20]
        HAL.current = 20
        HAL.levels[HAL.key(20)] = 0.7
        m.refreshAndApply()
        m.halQueue.run()
        m.scheduleVolumeRefresh(for: 10)
        DispatchQueue.main.run()
        DispatchQueue.drain()
        check(
            near(m.inputVolume, 0.7),
            "different UID reconnect publishes new gain despite old notification")
        m.stop()
        HAL.reset()
        HAL.streamChannels[10] = [4]
        HAL.levels[HAL.key(10, 3)] = 0.7
        m = manager()
        check(near(m.inputVolume, 0.7), "gain on channel 3 is discovered")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10, 1)] = 0.5
        HAL.levels[HAL.key(10, 2)] = 0.7
        HAL.readOnly.insert(HAL.key(10, 2))
        m = manager()
        m.setInputVolume(0.4)
        DispatchQueue.drain()
        check(
            HAL.levels[HAL.key(10, 2)] == 0.7 && near(m.inputVolume, 0.4), "read-only channel left intact"
        )
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(-1)
        DispatchQueue.drain()
        check(near(m.inputVolume, 0), "negative volume clamped")
        m.setInputVolume(2)
        DispatchQueue.drain()
        check(near(m.inputVolume, 1), "volume above one clamped")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.scheduleVolumeRefresh(for: 10)
        m.stop()
        DispatchQueue.drain()
        check(m.inputVolume == nil && HAL.listeners.isEmpty, "pending read canceled by stop")
        m.start()
        DispatchQueue.drain()
        check(near(m.inputVolume, 0.5), "restart rediscovers volume")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setPreferredInputDeviceUID("missing")
        DispatchQueue.drain()
        check(
            m.preferredUnavailable && m.effectiveInputDeviceUID == "device-10"
                && near(m.inputVolume, 0.5), "missing preference uses active input")
        m.setPreferredInputDeviceUID(nil)
        DispatchQueue.drain()
        check(
            !m.preferredUnavailable && near(m.inputVolume, 0.5), "clear missing preference preserves gain"
        )
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        HAL.devices = [10, 20]
        HAL.levels[HAL.key(20)] = 0.8
        m.setPreferredInputDeviceUID("device-20")
        DispatchQueue.drain()
        check(
            HAL.current == 20 && near(m.inputVolume, 0.8), "preferred input selected with its own gain")
        m.stop()
        check(HAL.current == 10, "stop restores original input selection")

        // Audio device priority: a microphone it puts in use becomes the
        // system's own choice, so quitting leaves it there. Only a change made
        // by the saved preferred microphone is undone.
        func priorityManager() -> AudioInputDeviceManager {
            HAL.reset()
            HAL.devices = [10, 20, 30]
            HAL.levels[HAL.key(10)] = 0.5
            HAL.levels[HAL.key(20)] = 0.5
            HAL.levels[HAL.key(30)] = 0.5
            let m = manager()
            m.setInputPriorityActive(true)
            DispatchQueue.drain()
            m.setCurrentInputDeviceUID("device-20")
            DispatchQueue.drain()
            return m
        }
        m = priorityManager()
        check(HAL.current == 20, "a priority pick becomes the system input")
        m.stop()
        check(HAL.current == 20, "quitting keeps the microphone the priority list picked")
        m = priorityManager()
        m.setInputPriorityActive(false)
        DispatchQueue.drain()
        m.stop()
        check(HAL.current == 20, "turning priority off does not make quitting undo its pick")
        m = priorityManager()
        m.setInputPriorityActive(false)
        DispatchQueue.drain()
        m.setPreferredInputDeviceUID("device-30")
        DispatchQueue.drain()
        check(HAL.current == 30, "the saved preferred microphone takes over once priority is off")
        m.stop()
        check(HAL.current == 20, "quitting then goes back to the microphone the priority list picked")

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.6
        m = manager()
        for _ in 0..<20 { m.scheduleVolumeRefresh(for: 10) }
        DispatchQueue.main.run()
        check(m.halQueue.work.isEmpty, "superseded callback burst does not issue stale read")
        DispatchQueue.drain()
        check(
            near(m.inputVolume, 0.6) && m.halQueue.work.isEmpty,
            "callback burst settles without recurring work")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.6
        HAL.readFails.insert(HAL.key(10))
        m = manager()
        check(m.inputVolume == nil, "unreadable gain hidden")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10, 0, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)] = 0.6
        HAL.levels[HAL.key(10)] = 0.6
        HAL.writeFails.insert(HAL.key(10, 0, kAudioHardwareServiceDeviceProperty_VirtualMainVolume))
        m = manager()
        m.setInputVolume(0.2)
        DispatchQueue.drain()
        check(
            HAL.writes.count == 2 && HAL.levels[HAL.key(10)] == 0.2,
            "failed virtual master falls back to scalar")
        m.stop()

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        check(
            MicMuteService.shared.isMuted && HAL.levels[HAL.key(10)] == 0,
            "mute requested after a queued adjustment wins")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        MicMuteService.shared.setMuted(true)
        MicMuteService.shared.halQueue.run()
        DispatchQueue.main.run()
        MicMuteService.shared.setMuted(false)
        MicMuteService.shared.halQueue.run()
        DispatchQueue.main.run()
        DispatchQueue.drain()
        check(
            !MicMuteService.shared.isMuted && HAL.levels[HAL.key(10)] == 0.5,
            "mute and unmute invalidate a drag from before the mute")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        HAL.afterWrite = { MicMuteService.shared.setMuted(true) }
        m.setInputVolume(0.8)
        DispatchQueue.drain()
        check(
            MicMuteService.shared.isMuted && HAL.levels[HAL.key(10)] == 0,
            "mute serializes after an adjustment already writing")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        MicMuteService.shared.setMuted(true)
        MicMuteService.shared.syncWithPreferences()
        m.setInputVolume(0.8)
        DispatchQueue.drain()
        check(
            HAL.levels[HAL.key(10)] == 0 && MicMuteService.shared.isMuted,
            "preference sync cannot reopen a pending mute")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        HAL.writeFails.insert(HAL.key(10))
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        HAL.writeFails = []
        m.setInputVolume(0.8)
        DispatchQueue.drain()
        check(
            !MicMuteService.shared.isMuted && near(m.inputVolume, 0.8),
            "a failed mute does not permanently disable gain control")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        m.stop()
        m.start()
        DispatchQueue.drain()
        check(
            HAL.levels[HAL.key(10)] == 0.5 && near(m.inputVolume, 0.5),
            "stop and restart do not revive an old gain adjustment")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        HAL.current = 20
        HAL.devices = [10, 20]
        HAL.levels[HAL.key(20)] = 0.2
        DispatchQueue.drain()
        check(HAL.writes.isEmpty, "current hardware input overrides an outdated cached selection")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        HAL.uids[10] = "replacement"
        DispatchQueue.drain()
        check(HAL.writes.isEmpty, "recycled audio object cannot receive an old gain adjustment")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        m.setPreferredInputDeviceUID("missing")
        DispatchQueue.drain()
        check(
            HAL.writes.isEmpty && near(m.inputVolume, 0.5),
            "a new preference cancels earlier adjustments even if effective input stays the same")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(.nan)
        m.setInputVolume(.infinity)
        DispatchQueue.drain()
        check(
            HAL.writes.isEmpty && near(m.inputVolume, 0.5),
            "nonfinite gain requests do not write or publish")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        HAL.afterUIDRead = { m.stop() }
        DispatchQueue.drain()
        check(
            HAL.writes.isEmpty && m.inputVolume == nil,
            "stop during hardware identity validation cancels the pending gain write")
        m.stop()

        HAL.reset()
        HAL.streamChannels[10] = []
        m = manager()
        check(m.inputVolume == nil, "zero input channels expose no gain control")
        m.stop()
        HAL.reset()
        HAL.streamReadFails = true
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        DispatchQueue.drain()
        check(near(m.inputVolume, 0.8), "master gain works even if channel discovery fails")
        m.stop()
        HAL.reset()
        HAL.streamReadFails = true
        HAL.levels[HAL.key(10, 1)] = 0.5
        m = manager()
        check(m.inputVolume == nil, "channel discovery failure does not guess channel addresses")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        HAL.readOnly.insert(HAL.key(10))
        HAL.running = [10]
        NotchService.shared.showsMicrophone = true
        NotchService.shared.microphone = []
        NotchService.shared.reactions = []
        NotchService.shared.retractions = 0
        QuickToolHUD.messages = []
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        check(QuickToolHUD.messages == ["mute partial"]
                && NotchService.shared.microphone.isEmpty
                && NotchService.shared.reactions.isEmpty
                && NotchService.shared.retractions == 1,
              "a wholly refused mute warns and retracts an older island confirmation")
        check(!MicMuteService.shared.isMuted
                && !UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive)
                && !MicMuteService.shared.hasOutstandingClaims
                && MicMuteService.shared.inputVolumeAdjustmentLifetime != nil
                && HAL.levels[HAL.key(10)] == 0.5,
              "a wholly refused mute keeps its state off and the original gain unclaimed")
        HAL.reset()
        HAL.mute[10] = 0
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        HAL.writeFails.insert(HAL.key(10, 0, kAudioDevicePropertyMute))
        NotchService.shared.microphone = []
        NotchService.shared.reactions = []
        NotchService.shared.retractions = 0
        QuickToolHUD.messages = []
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(QuickToolHUD.messages == ["unmute partial"]
                && NotchService.shared.microphone.isEmpty
                && NotchService.shared.reactions.isEmpty
                && NotchService.shared.retractions == 1,
              "a wholly refused unmute warns without announcing that mute is off")
        check(!MicMuteService.shared.isMuted && !MicMuteService.shared.hasUnconfirmedInputs
                && MicMuteService.shared.hasOutstandingClaims
                && !UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive)
                && MicMuteService.shared.inputVolumeAdjustmentLifetime != nil
                && HAL.mute[10] == 1,
              "a wholly refused manual release keeps the switch owed and the mixer available")
        HAL.writeFails = []
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(!MicMuteService.shared.isMuted && !MicMuteService.shared.hasOutstandingClaims
                && HAL.mute[10] == 0,
              "retrying a refused unmute releases the device still owned by the app")
        HAL.reset()
        HAL.mute[10] = 0
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        HAL.mute[10] = 0
        HAL.running = [10]
        HAL.writeFails.insert(HAL.key(10, 0, kAudioDevicePropertyMute))
        NotchService.shared.microphone = []
        NotchService.shared.retractions = 0
        QuickToolHUD.messages = []
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        check(QuickToolHUD.messages.isEmpty && NotchService.shared.microphone.isEmpty
                && NotchService.shared.retractions == 1,
              "a failed background reapply retracts a stale confirmation without repeating the warning")
        NotchService.shared.showsMicrophone = false
        HAL.reset()
        HAL.devices = [10, 20]
        HAL.levels[HAL.key(10)] = 0.5
        HAL.levels[HAL.key(20)] = 0.5
        HAL.readOnly.insert(HAL.key(20))
        HAL.running = [20]
        QuickToolHUD.messages = []
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        check(
            QuickToolHUD.messages == ["mute partial"] && HAL.levels[HAL.key(20)] == 0.5,
            "a microphone left open is announced instead of a plain mute")
        HAL.reset()
        HAL.devices = [10, 20]
        HAL.mute[10] = 0
        HAL.mute[20] = 0
        QuickToolHUD.messages = []
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        HAL.writeFails.insert(HAL.key(20, 0, kAudioDevicePropertyMute))
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(
            QuickToolHUD.messages == ["muted", "unmute partial"] && HAL.mute[10] == 0 && HAL.mute[20] == 1,
            "a claimed microphone that stays muted is announced instead of a plain unmute")
        HAL.reset()
        HAL.devices = [10, 20]
        HAL.levels[HAL.key(10)] = 0.5
        HAL.mute[20] = 1
        QuickToolHUD.messages = []
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        check(
            QuickToolHUD.messages == ["muted"] && MicMuteService.inputControls(10).isSilenced,
            "every microphone silent, one by the user, still announces a plain mute")
        HAL.reset()
        HAL.devices = [10, 30]
        HAL.levels[HAL.key(10)] = 0.5
        HAL.aggregates = [30]
        HAL.aggregateMembers[30] = [10]
        HAL.running = [30]
        QuickToolHUD.messages = []
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        check(
            QuickToolHUD.messages == ["muted"] && !MicMuteService.shared.hasUnconfirmedInputs
                && MicMuteService.inputControls(10).isSilenced,
            "an aggregate with no mute or level of its own does not make the mute partial")
        HAL.reset()
        HAL.devices = [10, 40]
        HAL.levels[HAL.key(10)] = 0.5
        QuickToolHUD.messages = []
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        check(
            QuickToolHUD.messages == ["mute partial"] && MicMuteService.shared.hasUnconfirmedInputs
                && MicMuteService.inputControls(10).isSilenced
                && UserDefaults.standard.stringArray(forKey: DefaultsKey.micMuteMutedDevices) == ["device-10"],
            "an idle input without controls warns without being claimed for restoration")
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        NotchService.shared.showsMicrophone = true
        NotchService.shared.reactions = []
        QuickToolHUD.messages = []
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(
            QuickToolHUD.messages.isEmpty && NotchService.shared.microphone == [true, false],
            "with Dynamic Island showing it, the switch reports there instead of a floating confirmation")
        check(NotchService.shared.reactions == [.hush, .perk],
              "the companion hushes as the microphone mutes and perks up as it opens")
        HAL.reset()
        HAL.devices = [10, 20]
        HAL.levels[HAL.key(10)] = 0.5
        HAL.levels[HAL.key(20)] = 0.5
        HAL.readOnly.insert(HAL.key(20))
        HAL.running = [20]
        NotchService.shared.microphone = []
        NotchService.shared.retractions = 0
        QuickToolHUD.messages = []
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        check(
            QuickToolHUD.messages == ["mute partial"] && NotchService.shared.microphone.isEmpty,
            "a microphone left open keeps its whole warning in the floating confirmation")
        check(NotchService.shared.retractions == 1,
              "a partial result takes back the island notice of the press before it")
        NotchService.shared.showsMicrophone = false
        NotchService.shared.microphone = []
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        HAL.levels[HAL.key(10, 1)] = 1
        HAL.levels[HAL.key(10, 2)] = 0.6
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        check(
            MicMuteService.shared.isMuted && HAL.levels[HAL.key(10)] == 0
                && HAL.levels[HAL.key(10, 1)] == 0 && HAL.levels[HAL.key(10, 2)] == 0,
            "a gain mute lowers the main level and every channel")
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(
            HAL.levels[HAL.key(10)] == 0.5 && HAL.levels[HAL.key(10, 1)] == 1
                && HAL.levels[HAL.key(10, 2)] == 0.6,
            "a gain unmute puts back the main level and the balance between channels")
        HAL.reset()
        HAL.levels[HAL.key(10, 1)] = 0.8
        HAL.levels[HAL.key(10, 2)] = 0.4
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(
            HAL.levels[HAL.key(10, 1)] == 0.8 && HAL.levels[HAL.key(10, 2)] == 0.4,
            "a device with channel levels only keeps their balance through a gain mute")
        // This version kept the first readable gain but did not name its control.
        for (active, residual): (Bool, Float) in [(true, 0), (true, 0.005), (false, 0.005)] {
            HAL.reset()
            HAL.streamChannels[10] = [3]
            HAL.levels[HAL.key(10, 3)] = 0.8
            HAL.levels[HAL.key(10)] = residual
            HAL.levels[HAL.key(10, 1)] = 0
            HAL.levels[HAL.key(10, 2)] = 0
            UserDefaults.standard.set(active, forKey: DefaultsKey.micMuteActive)
            UserDefaults.standard.set(["device-10": 0.5], forKey: DefaultsKey.micMuteSavedVolumes)
            UserDefaults.standard.set(["device-10"], forKey: DefaultsKey.micMuteMutedDevices)
            MicMuteService.shared = MicMuteService()
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            if active {
                MicMuteService.shared.setMuted(false)
                DispatchQueue.drain()
            }
            check(
                !MicMuteService.shared.isMuted && MicMuteService.shared.warning == .manualRestore
                    && HAL.levels[HAL.key(10)] == residual && HAL.levels[HAL.key(10, 1)] == 0
                    && HAL.levels[HAL.key(10, 2)] == 0 && HAL.levels[HAL.key(10, 3)] == 0.8,
                "a legacy UID level cannot open a master or a silent channel during release or reapply")
        }

        HAL.reset()
        HAL.mute[10] = 1
        HAL.levels[HAL.key(10)] = 0.5
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        check(HAL.mute[10] == 1 && HAL.levels[HAL.key(10)] == 0,
              "mute also zeros gain when the user already engaged the hardware switch")
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(HAL.mute[10] == 1 && HAL.levels[HAL.key(10)] == 0.5
                && !MicMuteService.shared.hasOutstandingClaims,
              "unmute preserves the user's pre-existing hardware mute while restoring gain")

        let firstMute = HAL.key(10, 1, kAudioDevicePropertyMute)
        let secondMute = HAL.key(10, 2, kAudioDevicePropertyMute)
        HAL.reset()
        HAL.muteElements = [firstMute: 1, secondMute: 0]
        check(!MicMuteService.inputControls(10).isSilenced, "one muted channel does not silence the whole input")
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        check(HAL.muteElements[firstMute] == 1 && HAL.muteElements[secondMute] == 1
                && MicMuteService.inputControls(10).isSilenced, "channel-only mute closes every input channel")
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(HAL.muteElements[firstMute] == 1 && HAL.muteElements[secondMute] == 0,
              "channel-only unmute preserves independently muted channels")

        HAL.reset()
        HAL.streamChannels[10] = [1]
        HAL.muteElements[firstMute] = 0
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        check(MicMuteService.inputControls(10).isSilenced, "a mono input needs no nonexistent second mute switch")
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(HAL.muteElements[firstMute] == 0, "a mono channel mute restores normally")

        HAL.reset()
        HAL.devices = [10, 20]
        HAL.mute[10] = 0
        HAL.levels[HAL.key(10)] = 0.5
        HAL.readOnly.insert(HAL.key(10))
        HAL.levels[HAL.key(20)] = 0.4
        QuickToolHUD.messages = []
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        check(HAL.mute[10] == 1 && HAL.levels[HAL.key(10)] == 0.5
                && QuickToolHUD.messages == ["mute partial"]
                && UserDefaults.standard.stringArray(forKey: DefaultsKey.micMuteMutedDevices)?.contains("device-10") == true,
              "a successful switch with refused gain retains its partial change for restore")
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(HAL.mute[10] == 0 && HAL.levels[HAL.key(20)] == 0.4
                && !MicMuteService.shared.hasOutstandingClaims,
              "partial mute releases both the changed switch and the other microphone")

        for ignoredControl in [HAL.key(10, 0, kAudioDevicePropertyMute), HAL.key(10)] {
            HAL.reset()
            HAL.mute[10] = 0
            HAL.levels[HAL.key(10)] = 0.5
            MicMuteService.shared.setMuted(true)
            DispatchQueue.drain()
            HAL.ignoredWrites.insert(ignoredControl)
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
            check(!MicMuteService.shared.isMuted && MicMuteService.shared.hasOutstandingClaims
                    && !MicMuteService.shared.hasUnconfirmedInputs
                    && (HAL.mute[10] == 1 || HAL.levels[HAL.key(10)] == 0),
                  "an ignored restore keeps the obligation while mute enforcement is off")
            HAL.ignoredWrites = []
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
            check(HAL.mute[10] == 0 && HAL.levels[HAL.key(10)] == 0.5
                    && !MicMuteService.shared.hasOutstandingClaims,
                  "retry restores the original state after an ignored control write")
        }

        HAL.reset()
        HAL.muteElements = [firstMute: 0, secondMute: 0]
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        HAL.writeFails.insert(secondMute)
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(HAL.muteElements[firstMute] == 0 && HAL.muteElements[secondMute] == 1
                && MicMuteService.shared.hasOutstandingClaims,
              "a later channel failure cannot be hidden by an earlier successful unmute")
        HAL.writeFails = []
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(HAL.muteElements[secondMute] == 0 && !MicMuteService.shared.hasOutstandingClaims,
              "a later channel can be restored on retry without losing its snapshot")

        HAL.reset()
        HAL.mute[10] = 0
        HAL.levels[HAL.key(10)] = 0.5
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        HAL.readFails.insert(HAL.key(10))
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(HAL.levels[HAL.key(10)] == 0 && MicMuteService.shared.hasOutstandingClaims
                && !(UserDefaults.standard.dictionary(forKey: DefaultsKey.micMuteSavedControls) ?? [:]).isEmpty,
              "an unreadable zeroed volume retains its saved level after clearing the switch")
        HAL.readFails = []
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(HAL.levels[HAL.key(10)] == 0.5 && HAL.mute[10] == 0
                && !MicMuteService.shared.hasOutstandingClaims,
              "the original volume returns once the property can be read again")

        HAL.reset()
        HAL.mute[10] = 0
        HAL.levels[HAL.key(10)] = 0.5
        HAL.levels[HAL.key(10, 1)] = 0
        HAL.levels[HAL.key(10, 2)] = 0.6
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        HAL.relaunchClient()
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(HAL.levels[HAL.key(10)] == 0.5 && HAL.levels[HAL.key(10, 1)] == 0
                && HAL.levels[HAL.key(10, 2)] == 0.6 && HAL.mute[10] == 0,
              "the exact zero channel and other levels survive a relaunch while muted")

        HAL.reset()
        HAL.streamChannels[10] = [4]
        for channel in 1...4 { HAL.levels[HAL.key(10, UInt32(channel))] = Float(channel) / 10 }
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        let raisedChannel = HAL.key(10, 3)
        check(HAL.listeners.contains(raisedChannel), "mute watches channels beyond the stereo pair")
        HAL.levels[raisedChannel] = 0.9
        signal(raisedChannel)
        DispatchQueue.drain()
        check(HAL.levels[raisedChannel] == 0 && MicMuteService.inputControls(10).isSilenced,
              "a listener reasserts mute when a later channel rises while the first stays at zero")
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check((1...4).allSatisfy { HAL.levels[HAL.key(10, UInt32($0))] == Float($0) / 10 },
              "reapplying an external gain change preserves every original channel level")

        HAL.reset()
        let virtualMain = HAL.key(10, 0, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        HAL.levels[virtualMain] = 0.5
        HAL.levels[HAL.key(10, 1)] = 0
        HAL.levels[HAL.key(10, 2)] = 0.5
        HAL.afterWrite = {
            HAL.levels[HAL.key(10, 1)] = 0
            HAL.levels[HAL.key(10, 2)] = 0
        }
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(HAL.levels[virtualMain] == 0.5 && HAL.levels[HAL.key(10, 1)] == 0
                && HAL.levels[HAL.key(10, 2)] == 0.5,
              "channel snapshots precede the virtual master write that also changes their levels")

        HAL.reset()
        HAL.mute[10] = 0
        HAL.levels[HAL.key(10)] = 0.5
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        HAL.devices = []
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(!MicMuteService.shared.isMuted && MicMuteService.shared.hasOutstandingClaims,
              "an unplugged microphone keeps its control snapshot after mute is switched off")
        HAL.devices = [20]
        HAL.uids[20] = "device-10"
        HAL.mute[20] = 1
        HAL.levels[HAL.key(20)] = 0
        MicMuteService.shared.reapplyIfNeeded()
        DispatchQueue.drain()
        check(HAL.mute[20] == 0 && HAL.levels[HAL.key(20)] == 0.5
                && !MicMuteService.shared.hasOutstandingClaims,
              "a returning device restores by stable uid even after its audio object id changes")

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        HAL.devices = []
        AppFeature.micMuteAvailable = false
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        let system = AudioObjectID(kAudioObjectSystemObject)
        let devicesChanged = HAL.key(system, 0, kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal)
        check(HAL.listeners.contains(devicesChanged),
              "disabling mic mute keeps device discovery until an unplugged microphone is restored")
        HAL.devices = [10]
        signal(devicesChanged)
        DispatchQueue.drain()
        check(HAL.levels[HAL.key(10)] == 0.5 && !MicMuteService.shared.hasOutstandingClaims && HAL.listeners.isEmpty,
              "a claimed microphone regains its volume on reconnection with the feature disabled")

        HAL.reset()
        HAL.mute[10] = 1
        HAL.levels[HAL.key(10)] = 0.5
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        AppFeature.micMuteAvailable = false
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        check(!MicMuteService.shared.isMuted && !MicMuteService.shared.hasOutstandingClaims
                && HAL.mute[10] == 1 && HAL.levels[HAL.key(10)] == 0.5 && HAL.listeners.isEmpty,
              "disabling the feature restores only its own changes and removes all listeners")

        // The pre-3.2 active flag is still needed when disabling schedules
        // the first restore of this launch on the audio queue.
        for savedGain: Double? in [nil, 0.625] {
            HAL.reset()
            HAL.devices = [10, 20]
            HAL.levels = [HAL.key(10): savedGain == nil ? 0.3 : 0.005, HAL.key(20): 0]
            if savedGain == nil { HAL.mute[10] = 1 }
            HAL.mute[20] = 1
            if let savedGain { UserDefaults.standard.set(savedGain, forKey: DefaultsKey.micMuteSavedVolume) }
            UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteActive)
            HAL.relaunchClient()
            AppFeature.micMuteAvailable = false
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            check(HAL.levels[HAL.key(10)] == (savedGain == nil ? 0.3 : 0.005) && (savedGain != nil || HAL.mute[10] == 1)
                    && HAL.mute[20] == 1 && HAL.levels[HAL.key(20)] == 0 && HAL.writes.isEmpty
                    && UserDefaults.standard.data(forKey: DefaultsKey.micMutePendingLegacyControls) == nil
                    && UserDefaults.standard.bool(forKey: DefaultsKey.micMuteManualCheckNeeded)
                    && !UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive),
                  "disabling on migration preserves the unidentified hardware for manual recovery")
        }

        HAL.reset()
        HAL.mute[10] = 0
        HAL.levels[HAL.key(10)] = 0.5
        MicMuteService.shared.setMuted(true)
        MicMuteService.shared.unmuteForTeardown()
        DispatchQueue.drain()
        check(HAL.mute[10] == 0 && HAL.levels[HAL.key(10)] == 0.5
                && !MicMuteService.shared.hasOutstandingClaims && HAL.listeners.isEmpty,
              "teardown drains an in-flight combined mute and restores its exact controls")

        for mainMute in [UInt32(0), 1] {
            HAL.reset()
            HAL.mute[10] = mainMute
            HAL.levels[HAL.key(10, 1)] = 0
            HAL.levels[HAL.key(10, 2)] = 0.5
            HAL.muteElements[firstMute] = 1
            UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteActive)
            UserDefaults.standard.set(["device-10"], forKey: DefaultsKey.micMuteMutedDevices)
            MicMuteService.shared = MicMuteService()
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
            check(HAL.mute[10] == 0 && HAL.levels[HAL.key(10, 2)] == 0.5
                    && HAL.levels[HAL.key(10, 1)] == 0 && HAL.muteElements[firstMute] == 1
                    && !MicMuteService.shared.hasOutstandingClaims,
                  "a legacy switch mute preserves the channel mix even if another client already released the switch")
        }

        HAL.reset()
        HAL.mute[10] = 0
        HAL.levels[HAL.key(10)] = 0
        UserDefaults.standard.set(0.625, forKey: DefaultsKey.micMuteSavedVolume)
        UserDefaults.standard.set(["device-10"], forKey: DefaultsKey.micMuteMutedDevices)
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        check(HAL.levels[HAL.key(10)] == 0 && !MicMuteService.shared.hasOutstandingClaims,
              "an already released v3.4.3 native switch leaves the user's zero level untouched")

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0
        UserDefaults.standard.set(["device-10", "device-20"], forKey: DefaultsKey.micMuteMutedDevices)
        UserDefaults.standard.set(["device-10": ["\(HAL.key(10).s):0": 0.4]], forKey: DefaultsKey.micMuteSavedControls)
        UserDefaults.standard.set(0.625, forKey: DefaultsKey.micMuteSavedVolume)
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        HAL.devices = [10, 20]
        HAL.current = 20
        HAL.levels[HAL.key(20)] = 0.005
        HAL.mute[20] = 1
        HAL.relaunchClient()
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        check(HAL.levels[HAL.key(10)] == 0.4 && HAL.mute[20] == 0 && HAL.levels[HAL.key(20)] == 0.005
                && !MicMuteService.shared.hasOutstandingClaims,
              "a returning native mic cannot inherit an unused global gain when it becomes the default")

        for masterMovesChannels in [false, true] {
            HAL.reset()
            let master = HAL.key(10)
            let left = HAL.key(10, 1)
            HAL.levels = [master: 0, left: 0]
            HAL.readFails = [master]
            let levels = ["\(master.s):0": 0.625, "\(left.s):1": 0.25]
            UserDefaults.standard.set(["device-10": levels], forKey: DefaultsKey.micMuteSavedControls)
            UserDefaults.standard.set(["device-10"], forKey: DefaultsKey.micMuteMutedDevices)
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
            check(HAL.levels[left] == 0.25 && MicMuteService.shared.hasOutstandingClaims,
                  "a readable channel restores while the recorded master is unreadable")
            HAL.levels[left] = 0.375 // The user adjusts the released channel.
            HAL.readFails = []
            HAL.writes = []
            HAL.beforeControlWrite = { key, target in
                if masterMovesChannels && key == master { HAL.levels[left] = Float(target) }
            }
            HAL.relaunchClient()
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
            check(HAL.levels[master] == 0.625 && HAL.levels[left] == 0.375 && !MicMuteService.shared.hasOutstandingClaims
                    && HAL.writes == (masterMovesChannels ? [master, left] : [master]),
                  "restoring a returning master preserves a later channel edit, including driver-linked gains")
        }

        for relaunch in [false, true] {
            HAL.reset()
            let oldMaster = HAL.key(10)
            let oldChannel = HAL.key(10, 1)
            let returnedMaster = HAL.key(30)
            let returnedChannel = HAL.key(30, 1)
            HAL.uids[10] = "old-headset"
            HAL.levels = [oldMaster: 0, oldChannel: 0.375]
            UserDefaults.standard.set(["old-headset": ["\(oldMaster.s):0": 0.625]], forKey: DefaultsKey.micMuteSavedControls)
            UserDefaults.standard.set(["old-headset"], forKey: DefaultsKey.micMuteMutedDevices)
            HAL.afterWrite = {
                // The old master's write moved its channel just before unplugging.
                HAL.levels[returnedMaster] = 0.625
                HAL.levels[returnedChannel] = 0.625
                HAL.uids[10] = "new-headset"
                HAL.levels[oldMaster] = 0.875
                HAL.levels[oldChannel] = 0.5
            }
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
            HAL.devices.append(30)
            HAL.uids[30] = "old-headset"
            HAL.writes = []
            if relaunch {
                HAL.levels[returnedChannel] = 0.25 // The user adjusted the channel after the interrupted Set.
                HAL.relaunchClient()
                MicMuteService.shared.syncWithPreferences()
            } else { signal(devicesChanged) }
            DispatchQueue.drain()
            check(HAL.levels[returnedChannel] == (relaunch ? 0.25 : 0.375) && HAL.levels[oldChannel] == 0.5 && HAL.levels[oldMaster] == 0.875
                    && HAL.writes == (relaunch ? [] : [returnedChannel]) && !MicMuteService.shared.hasOutstandingClaims
                    && MicMuteService.shared.warning == (relaunch ? .manualRestore : nil),
                  "the old headset compensates its moved channel live and preserves an edit after relaunch (restarted: \(relaunch))")
        }

        HAL.reset()
        HAL.mute[10] = 1
        HAL.levels[HAL.key(10)] = 0
        HAL.muteElements[firstMute] = 1
        UserDefaults.standard.set(["device-10"], forKey: DefaultsKey.micMuteMutedDevices)
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        check(HAL.mute[10] == 0 && HAL.levels[HAL.key(10)] == 0 && HAL.muteElements[firstMute] == 1
                && !MicMuteService.shared.hasOutstandingClaims,
              "a pending legacy unmute restores only the claimed main switch when the microphone returns")

        HAL.reset()
        var now: TimeInterval = 10
        MicMuteService.shared = MicMuteService(uptime: { now })
        let retryService = MicMuteService.shared
        HAL.uids[10] = "MSLoopbackDriverDevice_UID"
        HAL.devices = [10, 20]
        HAL.levels[HAL.key(10)] = 0.5
        HAL.levels[HAL.key(20)] = 0.75
        HAL.ignoredWrites.insert(HAL.key(10))
        retryService.setMuted(true)
        DispatchQueue.drain()
        func changed(_ device: UInt32) {
            signal(HAL.key(device))
            DispatchQueue.drain()
        }
        for _ in 0..<10 { changed(10) }
        let refusingWrites = HAL.writes.filter { $0 == HAL.key(10) }.count
        check(refusingWrites == 3 && HAL.listeners.contains(HAL.key(10)),
              "a refusing driver stops receiving writes from its callbacks but remains watched")
        let backoffGeneration = retryService.applyGeneration
        UserDefaults.standard.writtenKeys = []
        for _ in 0..<8 {
            signal(HAL.key(10))
        }
        DispatchQueue.drain()
        check(retryService.applyGeneration == backoffGeneration + 1 && UserDefaults.standard.writtenKeys.isEmpty
                && HAL.writes.filter { $0 == HAL.key(10) }.count == refusingWrites
                && retryService.retryDeadline == now + 0.25,
              "a callback burst during driver backoff preserves the retry deadline without writing hardware or defaults")
        HAL.levels[HAL.key(20)] = 0.8
        changed(20)
        check(HAL.levels[HAL.key(20)] == 0 && HAL.writes.filter { $0 == HAL.key(10) }.count == refusingWrites,
              "another input is silenced immediately without retrying the refusing device")
        now += 0.25
        retryService.halQueue.runTimers()
        DispatchQueue.drain()
        check(HAL.writes.filter { $0 == HAL.key(10) }.count == refusingWrites + 1
                && retryService.retryDeadline == now + 0.5,
              "a refusing device retries without a notification and doubles its backoff")
        HAL.ignoredWrites.removeAll()
        HAL.levels[HAL.key(10)] = 0
        changed(10)
        HAL.levels[HAL.key(10)] = 0.5
        changed(10)
        check(HAL.levels[HAL.key(10)] == 0 && retryService.retryDeadline == nil,
              "delayed silence restores immediate enforcement on the next gain change")
        retryService.setMuted(false)
        DispatchQueue.drain()
        retryService.halQueue.runTimers()
        DispatchQueue.drain()
        check(HAL.levels[HAL.key(10)] == 0.5 && HAL.levels[HAL.key(20)] == 0.75,
              "a canceled retry cannot remute inputs after an explicit unmute")

        HAL.reset()
        now = 20
        MicMuteService.shared = MicMuteService(uptime: { now })
        HAL.virtual = [10]
        HAL.levels[HAL.key(10)] = 1
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        for _ in 0..<10 {
            HAL.levels[HAL.key(10)] = 1
            changed(10)
        }
        check(HAL.writes.filter { $0 == HAL.key(10) }.count == 3,
              "a virtual driver that resets after successful readback cannot loop on its own notifications")
        now += 0.25
        MicMuteService.shared.halQueue.runTimers()
        DispatchQueue.drain()
        check(HAL.levels[HAL.key(10)] == 0, "a virtual driver that recovers without notifying is silenced")
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        now += 1
        MicMuteService.shared.halQueue.runTimers()
        DispatchQueue.drain()
        check(HAL.levels[HAL.key(10)] == 1, "an explicit unmute cancels a pending virtual driver retry")

        HAL.reset()
        now = 30
        MicMuteService.shared = MicMuteService(uptime: { now })
        HAL.virtual = [10]
        HAL.levels[HAL.key(10)] = 1
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        for _ in 0..<3 {
            HAL.levels[HAL.key(10)] = 1
            changed(10)
        }
        let runningKey = HAL.key(10, 0, kAudioDevicePropertyDeviceIsRunningSomewhere,
                                 scope: kAudioObjectPropertyScopeGlobal)
        check(HAL.listeners.contains(runningKey) && MicMuteService.shared.retryDeadline != nil,
              "a virtual driver in backoff keeps its recording-start listener")
        HAL.listenerAdds = []
        HAL.listenerRemovals = []
        HAL.running = [10]
        signal(runningKey)
        DispatchQueue.drain()
        for _ in 0..<5 {
            HAL.levels[HAL.key(10)] = 1
            changed(10)
            check(HAL.levels[HAL.key(10)] == 0, "a recording virtual input is immediately silenced")
        }
        check(MicMuteService.shared.retryDeadline == nil,
              "starting capture bypasses a previously idle virtual input's backoff")
        check(HAL.listenerAdds.isEmpty && HAL.listenerRemovals == [runningKey],
              "leaving idle-only backoff removes only the recording-start listener")

        HAL.reset()
        now = 40
        MicMuteService.shared = MicMuteService(uptime: { now })
        HAL.uids = [10: "first input"]
        HAL.virtual = [10]
        HAL.levels[HAL.key(10)] = 0.5
        HAL.ignoredWrites = [HAL.key(10)]
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        changed(10)
        changed(10)
        let hotPlugged = MicMuteService.shared
        HAL.ignoredWrites = []
        HAL.uids = [10: "replacement input"]
        HAL.levels[HAL.key(10)] = 0.35
        changed(10)
        check(HAL.levels[HAL.key(10)] == 0 && hotPlugged.retryDeadline == nil,
              "a new UID reusing an old audio object ID is not subject to the old cooldown")
        hotPlugged.setMuted(false)
        DispatchQueue.drain()
        now += 1
        hotPlugged.halQueue.runTimers()
        DispatchQueue.drain()
        check(HAL.levels[HAL.key(10)] == 0.35 && hotPlugged.hasOutstandingClaims,
              "the new input restores its own gain and retains the disconnected input's separate claim")

        HAL.reset()
        now = 50
        MicMuteService.shared = MicMuteService(uptime: { now })
        HAL.virtual = [10]
        HAL.levels[HAL.key(10)] = 0.5
        HAL.ignoredWrites = [HAL.key(10)]
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        changed(10)
        changed(10)
        HAL.levels[HAL.key(10)] = 0.2
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(!MicMuteService.shared.isMuted && MicMuteService.shared.retries.isEmpty
                && MicMuteService.shared.retryDeadline != nil && MicMuteService.shared.hasOutstandingClaims,
              "a wholly failed manual release cancels mute retries and schedules recovery of the saved gain")
        AppFeature.micMuteAvailable = false
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        check(!MicMuteService.shared.isMuted && MicMuteService.shared.retries.isEmpty && MicMuteService.shared.retryDeadline != nil
                && !UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive),
              "disabling the feature retains only the pending release's retry")
        MicMuteService.shared.unmuteForTeardown()
        HAL.ignoredWrites = []
        now += 1
        MicMuteService.shared.halQueue.runTimers()
        DispatchQueue.drain()
        check(!MicMuteService.shared.isMuted && MicMuteService.shared.retryDeadline == nil
                && HAL.levels[HAL.key(10)] == 0.2,
              "teardown cancels retries even when the audio driver refuses restoration")

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        HAL.levels[HAL.key(10)] = 0.5
        HAL.afterWrite = { HAL.levels[HAL.key(10)] = 0.5 }
        signal(HAL.key(10))
        DispatchQueue.drain()
        check(HAL.listeners.contains(HAL.key(10)),
              "a gain raised again right after the re-mute keeps the microphone watched")

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        let gain = HAL.key(10)
        let sweepsBefore = MicMuteService.shared.applyGeneration
        UserDefaults.standard.writtenKeys = []
        for _ in 0..<5 {
            signal(gain)
        }
        DispatchQueue.drain()
        check(MicMuteService.shared.applyGeneration == sweepsBefore + 1,
              "a burst of device changes is answered by one sweep")
        check(UserDefaults.standard.writtenKeys.isEmpty,
              "a re-assert that finds everything muted writes no preferences")
        let service = MicMuteService.shared
        let timersBefore = DispatchQueue.main.timedEnqueues
        HAL.levels[HAL.key(10)] = 0.5
        signal(gain)
        DispatchQueue.main.run()
        check(DispatchQueue.main.timedEnqueues == timersBefore && service.halQueue.work.count == 1,
              "the first callback queues an audio sweep immediately, without a mute delay")
        let firstSweep = service.applyGeneration
        // Let main handle each arrival separately while the audio queue is busy.
        for _ in 0..<8 {
            signal(gain)
            DispatchQueue.main.run()
        }
        check(service.applyGeneration == firstSweep && service.halQueue.work.count == 1,
              "a busy audio queue never accumulates additional listener sweeps")
        service.halQueue.run()
        HAL.levels[HAL.key(10)] = 0.75
        DispatchQueue.drain()
        check(service.applyGeneration == firstSweep + 1 && HAL.levels[HAL.key(10)] == 0,
              "one trailing sweep covers changes the busy sweep missed")

        HAL.writeFails.insert(HAL.key(10))
        QuickToolHUD.messages = []
        signal(gain)
        service.setMuted(false)
        DispatchQueue.main.run()
        service.syncWithPreferences()
        DispatchQueue.drain()
        check(QuickToolHUD.messages == ["unmute partial"] && !service.isMuted && service.hasOutstandingClaims,
              "an older device notification or preference sync cannot hide a failed manual unmute")
        HAL.writeFails = []
        service.setMuted(false)
        DispatchQueue.drain()
        check(!service.isMuted && HAL.levels[HAL.key(10)] == 0.5,
              "a later manual retry restores the original input gain")

        HAL.reset()
        let stopped = MicMuteService.shared
        HAL.levels[HAL.key(10)] = 0.65
        HAL.mute[20] = 1
        HAL.devices = [10, 20]
        stopped.toggle()
        stopped.toggle()
        check(!stopped.wantsMute, "a second toggle cancels a mute that is still on the audio queue")
        QuickToolHUD.messages = []
        signal(devicesChanged)
        stopped.unmuteForTeardown()
        check(stopped.halQueue.work.isEmpty && HAL.levels[HAL.key(10)] == 0.65 && HAL.mute[20] == 1,
              "teardown drains a queued mute and unmute without opening a user-muted input")
        DispatchQueue.drain()
        check(HAL.listeners.isEmpty && !stopped.isMuted && QuickToolHUD.messages.isEmpty,
              "old callbacks cannot publish, remute or reinstall listeners after teardown")

        HAL.reset()
        let removed = MicMuteService.shared
        HAL.levels[HAL.key(10)] = 0.6
        removed.setMuted(true)
        DispatchQueue.drain()
        let lateDeviceChange = HAL.pendingNotification(for: devicesChanged)
        check(lateDeviceChange != nil, "the HAL retained the device-list delivery before teardown")
        HAL.devices = []
        removed.unmuteForTeardown()
        lateDeviceChange?()
        DispatchQueue.drain()
        check(removed.hasOutstandingClaims && HAL.listeners.isEmpty,
              "a late HAL callback for an absent claim cannot reinstall listeners after teardown")

        // Deliver a topology callback before the manual sweep, and change the
        // device list after that sweep but before it can publish on main.
        for mute in [true, false] {
            HAL.reset()
            HAL.levels[HAL.key(10)] = 0.5
            HAL.levels[HAL.key(20)] = 0.75
            let pending = MicMuteService.shared
            if !mute {
                HAL.devices = [10, 20]
                pending.setMuted(true)
                DispatchQueue.drain()
                HAL.devices = [10]
            }
            pending.setMuted(mute)
            signal(devicesChanged)
            DispatchQueue.main.run()
            check(UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive) != mute
                    && pending.halQueue.work.count == 1,
                  "a device change during a manual request cannot queue the stale persisted state")
            pending.halQueue.run()
            HAL.devices = [10, 20]
            DispatchQueue.drain()
            check(pending.isMuted == mute
                    && UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive) == mute
                    && HAL.levels[HAL.key(10)] == (mute ? 0 : 0.5)
                    && HAL.levels[HAL.key(20)] == (mute ? 0 : 0.75),
                  "the requested mute or unmute reaches a device that arrives before publication")
        }

        runCoalescedReconnectTests(suite)
        runInitialMuteRegistrationTests(suite)
        runMuteListenerTests(suite)
        runPendingRestoreDeviceChangeTests(suite)
        runPendingControlListTests(suite)
        runRestoreControlListEchoTests(suite)
        runRestoreRetryLimitTests(suite)
        runMuteRecoveryTests(suite)
        runLowGainMuteTests(suite)
        runProtectedChannelRestoreTests(suite)
        runManualRestoreAcknowledgementTests(suite)
        runObservedChannelRestoreTests(suite)
        runLegacyStereoAccessTests(suite)
        runHistorical344ChannelCaptureTests(suite)
        runAggregateAndRestoreTests(suite)
        runLegacyMasterRestoreTests(suite)
        runReleaseIntentTests(suite)
        runControlRetryTests(suite)
        runCallAppUnmuteTests(suite)
    }

    private static func runReleaseIntentTests(_ suite: TestSuite) {
        let master = HAL.key(10)
        let channel = HAL.key(10, 1)
        let list = HAL.key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyDevices,
                           scope: kAudioObjectPropertyScopeGlobal)
        for action in ["button", "disable", "teardown", "call"] {
            HAL.reset()
            UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteFollowCallApps)
            HAL.levels = [master: 0.625, channel: 0.25]
            let service = MicMuteService.shared
            service.setMuted(true)
            DispatchQueue.drain()
            let oldChannel = HAL.pendingNotification(for: channel)
            HAL.readFails = [master]
            HAL.writes = []
            switch action {
            case "call":
                let ownPID = ProcessInfo.processInfo.processIdentifier
                HAL.processes = [(object: 100, pid: ownPID == 4242 ? 4243 : 4242, recording: true, devices: [10])]
                HAL.levels[channel] = 0.875
                suite.expect(HAL.notifyIfRegistered(channel), "the recording input reports a verified call opening")
            case "disable": AppFeature.micMuteAvailable = false; service.syncWithPreferences()
            case "teardown": service.unmuteForTeardown()
            default: service.setMuted(false)
            }
            DispatchQueue.drain()
            suite.expect(!service.isMuted && !service.wantsMute && service.hasOutstandingClaims && HAL.levels[channel] == 0.25,
                         "a \(action) release restores the single input's available channel while its master waits")
            HAL.levels[channel] = 0.375
            HAL.writes = []
            AppFeature.micMuteAvailable = true
            service.syncWithPreferences()
            oldChannel?()
            DispatchQueue.drain()
            suite.expect(HAL.writes.isEmpty && HAL.levels[channel] == 0.375,
                         "a sync and a queued old callback keep the \(action) release and the user's channel edit")
            HAL.relaunchClient()
            let restarted = MicMuteService.shared
            restarted.syncWithPreferences()
            DispatchQueue.drain()
            suite.expect(!restarted.isMuted && !restarted.wantsMute && restarted.inputVolumeAdjustmentLifetime != nil
                         && restarted.controlSymbol == "exclamationmark.triangle" && HAL.writes.isEmpty && restarted.hasOutstandingClaims,
                         "relaunch continues a \(action) release with the one outstanding master and the mixer available")
            HAL.readFails = []
            suite.expect(HAL.notifyIfRegistered(list), "the pending master receives its recovery event")
            DispatchQueue.drain()
            suite.expect(HAL.writes == [master] && HAL.levels == [master: 0.625, channel: 0.375]
                         && !restarted.hasOutstandingClaims && !restarted.isMuted,
                         "the returning master completes the \(action) release without touching the edited channel")
        }

        for call in [false, true] {
            HAL.reset()
            UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteFollowCallApps)
            HAL.levels = [master: 0.625, channel: 0.25]
            let service = MicMuteService.shared
            service.setMuted(true)
            DispatchQueue.drain()
            HAL.readFails = [master]
            if call {
                let ownPID = ProcessInfo.processInfo.processIdentifier
                HAL.processes = [(object: 100, pid: ownPID == 4242 ? 4243 : 4242, recording: true, devices: [10])]
                // The call itself restored this channel to its exact saved gain.
                HAL.levels[channel] = 0.25
                _ = HAL.notifyIfRegistered(channel)
                DispatchQueue.main.run()
            } else {
                service.setMuted(false)
            }
            service.halQueue.sync {}
            suite.expect(service.isMuted && service.inputVolumeAdjustmentLifetime != nil,
                         "the verified release allows mixer edits while the old mute is still published")
            DispatchQueue.main.work.removeAll()
            HAL.levels[channel] = 0.5
            HAL.writes = []
            HAL.relaunchClient()
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            suite.expect(HAL.writes.isEmpty && HAL.levels[channel] == 0.5 && !MicMuteService.shared.wantsMute
                         && MicMuteService.shared.hasOutstandingClaims,
                         "the release direction is durable before publication (call: \(call))")
            MicMuteService.shared.toggle()
            DispatchQueue.drain()
            suite.expect(MicMuteService.shared.wantsMute && HAL.levels[channel] == 0,
                         "an explicit new mute can supersede the persisted release")
        }

        for moment in ["sync", "queued callback", "registration", "publication"] {
            HAL.reset()
            HAL.levels = [master: 0.625, channel: 0.25]
            let service = MicMuteService.shared
            // Reproduce the durable state after a channel was released while
            // an older request or its completion still lives in memory.
            func recordPendingRelease() {
                UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteReleasePending)
                UserDefaults.standard.set(["device-10": ["\(master.s):0": 0.625]], forKey: DefaultsKey.micMuteSavedControls)
                HAL.readFails = [master]
                HAL.levels[channel] = 0.375
                HAL.writes = []
            }
            if moment == "registration" { HAL.afterListenerAdd[channel] = recordPendingRelease }
            service.setMuted(true)
            if moment == "publication" {
                service.halQueue.sync {}
                recordPendingRelease()
            }
            DispatchQueue.drain()
            if moment == "sync" {
                recordPendingRelease()
                service.syncWithPreferences()
            } else if moment == "queued callback" {
                _ = HAL.notifyIfRegistered(channel)
                DispatchQueue.main.run()
                recordPendingRelease()
            }
            DispatchQueue.drain()
            suite.expect(!service.wantsMute && !service.isMuted && HAL.writes.isEmpty && HAL.levels[channel] == 0.375,
                         "a persisted release prevails over stale mute state at \(moment)")
        }

        HAL.reset()
        let other = HAL.key(20)
        HAL.devices = [10, 20]
        HAL.levels = [master: 0.625, channel: 0.25, other: 0.75]
        UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteFollowCallApps)
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        HAL.processes = [(object: 100, pid: ownPID == 4242 ? 4243 : 4242, recording: true, devices: [10])]
        HAL.readFails = [master]
        var restarted = false
        var reclosed = false
        HAL.beforeControlWrite = { key, value in
            if key == other && value == 0.75 && !restarted {
                HAL.levels[channel] = 0.375
                restarted = HAL.restartAudioService()
            } else if restarted && value == 0 { reclosed = true }
        }
        HAL.levels[channel] = 0.875
        _ = HAL.notifyIfRegistered(channel)
        DispatchQueue.drain()
        suite.expect(restarted && !reclosed && !MicMuteService.shared.wantsMute && HAL.levels[channel] == 0.375
                     && MicMuteService.shared.hasOutstandingClaims,
                     "a reset on the next input preserves a call release already verified on the first input")
    }

    private static func runLegacyMasterRestoreTests(_ suite: TestSuite) {
        let master = HAL.key(10)
        let left = HAL.key(10, 1)
        let right = HAL.key(10, 2)
        let virtual = HAL.key(10, 0, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        let defaults = UserDefaults.standard
        let uid = "device-10"
        func release() {
            HAL.relaunchClient()
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
        }
        HAL.reset()
        defaults.set([uid], forKey: DefaultsKey.micMuteMutedDevices)
        defaults.set([uid: 0.625], forKey: DefaultsKey.micMuteSavedVolumes)
        HAL.levels[master] = 0.005
        HAL.mute[10] = 1
        var retired = false
        defaults.afterChange = { key in
            if key == DefaultsKey.micMuteSavedVolumes {
                retired = defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices)?.isEmpty == true
                    && defaults.bool(forKey: DefaultsKey.micMuteManualCheckNeeded)
            }
        }
        release()
        defaults.afterChange = nil
        suite.expect(retired && HAL.writes.isEmpty && HAL.mute[10] == 1 && HAL.levels[master] == 0.005,
                     "clearing the unaddressed gain never leaves the UID as a switch-only mute")
        for reapply in [false, true] {
            HAL.reset()
            defaults.set([uid], forKey: DefaultsKey.micMuteMutedDevices)
            defaults.set([uid: 0.625], forKey: DefaultsKey.micMuteSavedVolumes)
            defaults.set([uid: ["\(master.s):0": 0.625, "1": 0.25, "2": 0.625]], forKey: DefaultsKey.micMuteSavedControls)
            HAL.levels = [left: reapply ? 0.005 : 0]
            if reapply {
                defaults.set(true, forKey: DefaultsKey.micMuteActive)
                HAL.relaunchClient()
                MicMuteService.shared.syncWithPreferences()
                DispatchQueue.drain()
                suite.expect(HAL.levels[left] == 0 && HAL.writes == [left],
                             "reapplying a legacy mute corrects the visible channel's residual gain")
                HAL.writes = []
            }
            release()
            suite.expect(HAL.levels == [left: 0.25] && HAL.writes == [left] && MicMuteService.shared.hasOutstandingClaims,
                         "the first visible channel restores from a legacy master and stereo record")
            HAL.levels = [right: 0, virtual: 0]
            HAL.writes = []
            release()
            suite.expect(HAL.levels == [right: 0.625, virtual: 0] && HAL.writes == [right]
                         && MicMuteService.shared.hasOutstandingClaims,
                         "matching the second channel's level does not verify the missing legacy scalar master")
            HAL.levels = [master: 0, left: 0.375, right: 0.875]
            HAL.ignoredWrites = [master]
            HAL.writes = []
            release()
            suite.expect(HAL.levels == [master: 0, left: 0.375, right: 0.875] && HAL.writes == [master]
                         && MicMuteService.shared.hasOutstandingClaims,
                         "an ignored restore keeps the returning master's own obligation")
            HAL.ignoredWrites = []
            HAL.writes = []
            release()
            suite.expect(HAL.levels == [master: 0.625, left: 0.375, right: 0.875] && HAL.writes == [master]
                         && !MicMuteService.shared.hasOutstandingClaims,
                         "the returning legacy master restores once and leaves the released channel's new level intact")
        }

        // A channel-only device also saved its first readable channel as the UID's level.
        for currentMaster: Float? in [nil, 0.875, 0, 0.005] {
            HAL.reset()
            defaults.set([uid], forKey: DefaultsKey.micMuteMutedDevices)
            defaults.set([uid: 0.25], forKey: DefaultsKey.micMuteSavedVolumes)
            defaults.set([uid: ["1": 0.25, "2": 0.75]], forKey: DefaultsKey.micMuteSavedChannelVolumes)
            HAL.levels = [left: 0, right: 0]
            HAL.levels[master] = currentMaster
            release()
            suite.expect(HAL.levels[left] == 0.25 && HAL.levels[right] == 0.75 && HAL.levels[master] == currentMaster
                         && !HAL.writes.contains(master) && !MicMuteService.shared.hasOutstandingClaims
                         && MicMuteService.shared.warning == .manualRestore,
                         "an unaddressed UID level requests a manual check regardless of the current master")
            if currentMaster == nil {
                HAL.levels[master] = 0
                HAL.writes = []
                HAL.relaunchClient()
                MicMuteService.shared.syncWithPreferences()
                DispatchQueue.drain()
                suite.expect(HAL.writes.isEmpty && HAL.levels[master] == 0 && MicMuteService.shared.warning == .manualRestore
                             && !MicMuteService.shared.hasOutstandingClaims && MicMuteService.shared.inputVolumeAdjustmentLifetime != nil,
                             "an ambiguous master that returns at zero stays available for the user's manual adjustment")
            }
        }

        // Per-control snapshots distinguish a virtual master even when its level matches a channel.
        HAL.reset()
        defaults.set([uid], forKey: DefaultsKey.micMuteMutedDevices)
        defaults.set([uid: ["\(virtual.s):0": 0.25, "\(left.s):1": 0.25, "\(right.s):2": 0]],
                     forKey: DefaultsKey.micMuteSavedControls)
        HAL.levels = [master: 0, left: 0, right: 0.5]
        release()
        suite.expect(HAL.levels == [master: 0, left: 0.25, right: 0] && MicMuteService.shared.hasOutstandingClaims,
                     "only the saved channels can be released while their recorded virtual master is absent")
        HAL.levels = [master: 0, virtual: 0, left: 0.375, right: 0]
        HAL.writes = []
        release()
        suite.expect(HAL.levels == [master: 0, virtual: 0.25, left: 0.375, right: 0] && HAL.writes == [virtual]
                     && !MicMuteService.shared.hasOutstandingClaims,
                     "the recorded virtual master restores without applying its value to a scalar master")

        // A missing master's exact address and live channel edits survive retries.
        HAL.reset()
        let third = HAL.key(10, 3)
        defaults.set([uid], forKey: DefaultsKey.micMuteMutedDevices)
        defaults.set([uid: ["\(master.s):0": 0.625]], forKey: DefaultsKey.micMuteSavedControls)
        HAL.streamChannels[10] = [3]
        HAL.levels = [master: 0, left: 0.005, third: 0.375]
        HAL.readFails = [left]
        release()
        suite.expect(HAL.writes.isEmpty && MicMuteService.shared.hasOutstandingClaims,
                     "a known master waits while a writable sibling is unreadable")
        HAL.levels[left] = nil
        HAL.readFails = []
        release()
        suite.expect(HAL.writes.isEmpty && MicMuteService.shared.hasOutstandingClaims,
                     "hiding the unreadable sibling does not authorize a master write")
        HAL.levels[left] = 0.5
        HAL.beforeControlWrite = { key, target in
            if key == master {
                HAL.levels[left] = Float(target)
                HAL.levels[third] = Float(target)
            }
        }
        release()
        suite.expect(HAL.levels == [master: 0.625, left: 0.5, third: 0.375] && !MicMuteService.shared.hasOutstandingClaims,
                     "the recorded master restores while protecting both current channel edits")
    }

    private static func runControlRetryTests(_ suite: TestSuite) {
        let left = HAL.key(10, 1)
        let right = HAL.key(10, 2)
        let other = HAL.key(20)
        var now: TimeInterval = 10
        func start() -> MicMuteService {
            let service = MicMuteService(uptime: { now })
            MicMuteService.shared = service
            service.setMuted(true)
            DispatchQueue.drain()
            return service
        }
        func notify(_ key: Key) {
            suite.expect(HAL.notifyIfRegistered(key), "the current control can report its gain")
            DispatchQueue.drain()
        }
        func writes(_ key: Key) -> Int { HAL.writes.filter { $0 == key }.count }

        // Only an idle virtual input can bounce back at a normal gain after
        // accepting zero. A persistent refusal can affect any input.
        let behaviors: [(name: String, virtual: Bool, running: Bool, accepts: [Bool], expectedWrites: Int)] = [
            ("idle virtual, accepts then refuses", true, false, [true, false], 3),
            ("idle virtual, refuses then accepts", true, false, [false, true], 3),
            ("idle virtual, always accepts", true, false, [true], 3),
            ("active virtual, always accepts", true, true, [true], 11),
            ("physical, always accepts", false, false, [true], 11),
            ("active virtual, always refuses", true, true, [false], 3),
            ("physical, always refuses", false, false, [false], 3)
        ]
        let running = HAL.key(10, 0, kAudioDevicePropertyDeviceIsRunningSomewhere, scope: kAudioObjectPropertyScopeGlobal)
        for behavior in behaviors {
            HAL.reset()
            HAL.levels = [left: 0.5, right: 0.25]
            HAL.virtual = behavior.virtual ? [10] : []
            HAL.running = behavior.running ? [10] : []
            HAL.beforeControlWrite = { key, target in
                guard key == left && target == 0 else { return }
                if behavior.accepts[(writes(left) - 1) % behavior.accepts.count] {
                    HAL.ignoredWrites.remove(left)
                } else {
                    HAL.ignoredWrites.insert(left)
                }
            }
            let retrying = start()
            // No second observation at zero between the initial set and this burst.
            if behavior.accepts.count > 1 { now += 1 }
            for _ in 0..<10 {
                HAL.levels[left] = 0.5
                notify(left)
            }
            suite.expect(writes(left) == behavior.expectedWrites, "the write burst is bounded as expected: \(behavior.name)")
            HAL.levels[right] = 0.75
            notify(right)
            suite.expect(HAL.levels[right] == 0 && writes(left) == behavior.expectedWrites,
                         "another channel remains independent: \(behavior.name)")
            guard behavior.accepts.count > 1 else { continue }

            // Retry once when due, then keep the longer deadline even when
            // the next setter produces the opposite result.
            let burst = writes(left)
            now += 0.25
            retrying.halQueue.runTimers()
            DispatchQueue.drain()
            HAL.levels[left] = 0.5
            notify(left)
            suite.expect(writes(left) == burst + 1 && retrying.retryDeadline == now + 0.5,
                         "the timer preserves the count through an alternating result: \(behavior.name)")
            var ticks = 0
            while let deadline = retrying.retryDeadline, ticks < 20 {
                now = deadline
                HAL.levels[left] = 0.5 // Rebound without a notification.
                retrying.halQueue.runTimers()
                DispatchQueue.drain()
                ticks += 1
            }
            suite.expect((1..<20).contains(ticks) && writes(left) == 10 && retrying.retryDeadline == nil,
                         "alternating results exhaust the same timed recovery budget: \(behavior.name)")
            HAL.beforeControlWrite = nil
            HAL.ignoredWrites = []
            HAL.running = [10]
            notify(running)
            suite.expect(HAL.levels[left] == 0 && !retrying.hasUnconfirmedInputs && retrying.retryDeadline == nil,
                         "starting capture immediately retries the idle input: \(behavior.name)")
        }

        for reportsTransientZero in [false, true] {
            HAL.reset()
            HAL.devices = [10, 20]
            HAL.levels = [left: 0.005, right: 0.4, other: 0.7]
            UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteFollowCallApps)
            HAL.beforeControlWrite = { key, target in
                guard key == left && target == 0 else { return }
                if writes(left).isMultiple(of: 2) {
                    HAL.ignoredWrites.remove(left)
                } else {
                    HAL.ignoredWrites.insert(left)
                }
            }
            let alternating = start()
            for _ in 0..<10 {
                if reportsTransientZero {
                    HAL.levels[left] = 0
                    notify(left)
                }
                HAL.levels[left] = 0.005
                notify(left)
            }
            let burst = writes(left)
            suite.expect(burst == 3 && alternating.hasUnconfirmedInputs && alternating.retryDeadline != nil,
                         "ten quick residuals share one burst when zero writes alternate between refusal and success")
            HAL.levels[right] = 0.8
            notify(right)
            suite.expect(HAL.levels[right] == 0 && writes(left) == burst,
                         "the alternating control's cooldown leaves the adjacent gain immediately writable")

            // A single late reading at zero is still only one observation.
            // An immediate rebound gets the next attempt at the existing cadence.
            now += 2
            HAL.levels[left] = 0
            notify(left)
            for _ in 0..<4 {
                HAL.levels[left] = 0.005
                notify(left)
            }
            suite.expect(writes(left) == burst + 1, "a single quiet sample after a long delay does not start a new burst")
            HAL.beforeControlWrite = nil
            HAL.ignoredWrites = []
            HAL.levels[left] = 0
            notify(left)
            now += 0.25
            alternating.halQueue.runTimers()
            DispatchQueue.drain()
            suite.expect(alternating.retryDeadline == nil && !alternating.hasUnconfirmedInputs,
                         "quiet observations a quarter second apart clear the alternating gain's retry")
            HAL.levels[left] = 0.005
            notify(left)
            suite.expect(writes(left) == burst + 2 && HAL.levels[left] == 0,
                         "a fresh low opening after stable zero is corrected immediately")
            let ownPID = ProcessInfo.processInfo.processIdentifier
            HAL.processes = [(object: 100, pid: ownPID == 4242 ? 4243 : 4242, recording: true, devices: [10])]
            HAL.levels[left] = 0.6
            notify(left)
            suite.expect(!alternating.isMuted && HAL.levels[left] == 0.005 && HAL.levels[other] == 0.7,
                         "a real call opening after verified zero restores the original levels")
        }

        for reportsZeroFirst in [false, true] {
            for virtual in [false, true] {
                HAL.reset()
                HAL.devices = [10, 20]
                HAL.levels = [left: 0.6, right: 0.3, other: 0.8]
                HAL.running = [10]
                if virtual { HAL.virtual = [10] }
                HAL.beforeControlWrite = { key, target in
                    guard key == left && target == 0 else { return }
                    if reportsZeroFirst {
                        // The setter's own read returns zero, but the level has
                        // already rebounded by the final verification pass.
                        HAL.afterGainRead[left] = { HAL.levels[left] = 0.4 }
                    } else {
                        HAL.minimumGain[left] = 0.4
                    }
                }
                let service = start()
                suite.expect(service.hasUnconfirmedInputs && service.retryDeadline != nil,
                             "the first unconfirmed setter schedules recovery without needing a callback")
                for index in 0..<10 {
                    HAL.levels[left] = index.isMultiple(of: 2) ? 0.2 : 0.7
                    notify(left)
                }
                let leftCount = writes(left)
                suite.expect(leftCount <= 3 && service.retryDeadline != nil && service.hasUnconfirmedInputs,
                             "alternating live readings on one refused control cannot restart its burst")
                HAL.levels[right] = 0.6
                HAL.levels[other] = 0.8
                notify(right)
                suite.expect(writes(left) == leftCount && HAL.levels[right] == 0 && HAL.levels[other] == 0,
                             "the other channel and input are silenced immediately during the refused setter's cooldown")
                HAL.beforeControlWrite = nil
                HAL.minimumGain = [:]
                now += 1
                service.halQueue.runTimers()
                DispatchQueue.drain()
                suite.expect(writes(left) == leftCount + 1 && HAL.levels[left] == 0 && !service.hasUnconfirmedInputs,
                             "the timer retries the original control and verifies recovery")
            }
        }

        HAL.reset()
        HAL.levels = [left: 0.5, right: 0]
        HAL.ignoredWrites = [left]
        let service = start()
        notify(left)
        notify(left)
        let leftDeadline = service.retryDeadline
        now += 0.1
        HAL.levels[right] = 0.5
        HAL.ignoredWrites.insert(right)
        for _ in 0..<3 { notify(right) }
        let leftCount = writes(left)
        let rightCount = writes(right)
        suite.expect(service.retryDeadline == leftDeadline,
                     "one channel starting its own cooldown preserves the earlier deadline on the other")
        now += 0.15
        service.halQueue.runTimers()
        DispatchQueue.drain()
        suite.expect(writes(left) == leftCount + 1 && writes(right) == rightCount,
                     "the earliest timer services only the control whose cooldown expired")

        HAL.reset()
        HAL.levels = [left: 0.005, right: 0]
        HAL.minimumGain[left] = 0.005
        let recovering = start()
        HAL.minimumGain = [:]
        now += 1
        recovering.halQueue.runTimers()
        DispatchQueue.drain()
        suite.expect(HAL.levels[left] == 0 && !recovering.hasUnconfirmedInputs,
                     "a physical mic that refuses only its first write recovers without a notification")

        for becomesUnreadable in [false, true] {
            HAL.reset()
            HAL.levels = [left: 0.5, right: 0]
            HAL.ignoredWrites = [left]
            let stuck = start()
            if becomesUnreadable { HAL.readFails = [left] }
            var ticks = 0
            while let deadline = stuck.retryDeadline, ticks < 20 {
                now = deadline
                stuck.halQueue.runTimers()
                DispatchQueue.drain()
                ticks += 1
            }
            suite.expect((2...10).contains(ticks) && stuck.retryDeadline == nil && stuck.hasUnconfirmedInputs,
                         "persistent failure exhausts timed recovery, including unreadable controls")
            let priorWrites = writes(left)
            HAL.readFails = []
            HAL.levels[left] = 0.3
            notify(left)
            suite.expect(writes(left) == priorWrites && stuck.retryDeadline == nil,
                         "another positive reading cannot restart the exhausted retry burst")
            now += 60
            HAL.ignoredWrites = []
            notify(left)
            suite.expect(writes(left) == priorWrites + 1 && HAL.levels[left] == 0 && !stuck.hasUnconfirmedInputs,
                         "a new hardware notice after cooldown recovers an input that exhausted its timers")
        }

        HAL.reset()
        HAL.devices = [10, 20]
        HAL.uids[10] = "old input"
        HAL.levels = [left: 0.005, right: 0, other: 0.8]
        HAL.ignoredWrites = [left]
        UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteFollowCallApps)
        let replacing = start()
        notify(left)
        notify(left)
        let stale = HAL.pendingNotification(for: left)
        HAL.uids[10] = "new input"
        HAL.ignoredWrites = []
        notify(HAL.key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyDevices,
                       scope: kAudioObjectPropertyScopeGlobal))
        suite.expect(stale != nil && HAL.levels[left] == 0 && !replacing.hasUnconfirmedInputs,
                     "the same control address and residual on a replacement UID get a fresh zero attempt")
        let ownPID = ProcessInfo.processInfo.processIdentifier
        HAL.processes = [(object: 100, pid: ownPID == 4242 ? 4243 : 4242, recording: true, devices: [10])]
        HAL.levels[left] = 0.7
        stale?()
        DispatchQueue.drain()
        suite.expect(replacing.isMuted && HAL.levels[left] == 0 && HAL.levels[other] == 0,
                     "the retired registration can reassert mute but cannot release another mic")
        HAL.levels[left] = 0.7
        notify(left)
        suite.expect(!replacing.isMuted && HAL.levels[left] == 0.005 && HAL.levels[other] == 0.8,
                     "the new registration follows a real call opening and restores the replacement's gain")
    }

    private static func runAggregateAndRestoreTests(_ suite: TestSuite) {
        runUIDOnlySwitchRestoreTests(suite)
        let gain = HAL.key(10)
        let members = HAL.key(30, 0, kAudioAggregateDevicePropertyActiveSubDeviceList, scope: kAudioObjectPropertyScopeGlobal)
        for missing in ["none", "member", "membership", "layout", "truncated layout", "no members"] {
            HAL.reset()
            HAL.devices = [30, 10, 20]
            HAL.aggregates = [30]
            HAL.inputsWithoutStreams = [20] // An active output-only member does not capture.
            HAL.uids = [101: "device-10", 102: "device-20"] // The HAL supplies sub-device objects.
            HAL.aggregateMembers[30] = missing == "no members" ? [] : [101, 102]
            if missing == "member" { HAL.aggregateMembers[30]?.append(199) }
            if missing == "membership" { HAL.readFails = [members] }
            if missing == "truncated layout" {
                // Two buffers fit the allocation; the returned byte count describes only the first.
                HAL.streamChannels[30] = [1, 1]
                HAL.returnedLayoutBytes[30] = UInt32(MemoryLayout<AudioBufferList>.size)
            }
            if missing == "layout" { HAL.sizeReadFails = [HAL.key(30, 0, kAudioDevicePropertyStreamConfiguration)] }
            HAL.levels[gain] = 0.6
            QuickToolHUD.messages = []
            let service = MicMuteService.shared
            service.setMuted(true)
            DispatchQueue.drain()
            suite.expect(service.isMuted && service.hasUnconfirmedInputs == (missing != "none")
                         && HAL.levels[gain] == 0 && QuickToolHUD.messages == [missing == "none" ? "muted" : "mute partial"],
                         "aggregate confirmation requires known active input members and layout (\(missing))")
            if missing == "none" {
                HAL.aggregateMembers[30] = [199]
                suite.expect(HAL.notifyIfRegistered(members), "the aggregate reports a change of its active members")
                DispatchQueue.drain()
                suite.expect(service.hasUnconfirmedInputs && HAL.levels[gain] == 0,
                             "a membership change invalidates coverage without releasing the unrelated mic")
            }
        }

        HAL.reset()
        HAL.devices = [10, 30]
        HAL.aggregates = [30]
        HAL.aggregateMembers[30] = [10]
        HAL.levels[gain] = 0.6
        HAL.afterListenerAdd[members] = { HAL.aggregateMembers[30] = [199] }
        QuickToolHUD.messages = []
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        suite.expect(MicMuteService.shared.hasUnconfirmedInputs && QuickToolHUD.messages == ["mute partial"],
                     "a member hidden during listener installation cannot inherit the old aggregate confirmation")

        let readbacks: [(Float, Float, Bool)] = [(0.5, Float(0.5).nextUp, true), (0.5, Float(0.5).nextDown, true),
                                                 (0.5, 0.51, false), (0.00005, 0.00009, false), (0.00005, 0, false)]
        for (original, readback, restored) in readbacks {
            HAL.reset()
            HAL.levels[gain] = original
            let service = MicMuteService.shared
            service.setMuted(true)
            DispatchQueue.drain()
            var requested: Double?
            HAL.beforeControlWrite = { key, value in if key == gain { requested = value } }
            HAL.afterWrite = { HAL.levels[gain] = readback }
            QuickToolHUD.messages = []
            service.setMuted(false)
            DispatchQueue.drain()
            suite.expect(requested == Double(original) && service.hasOutstandingClaims == !restored && !service.isMuted
                         && QuickToolHUD.messages == [restored ? "unmuted" : "unmute partial"],
                         "restore writes the exact gain and verifies a positive driver readback (\(readback))")
        }

        for active in [false, true] {
            HAL.reset()
            let liveChannel = HAL.key(10, 1)
            HAL.levels = [gain: 0, liveChannel: 0.25]
            UserDefaults.standard.set(["device-10"], forKey: DefaultsKey.micMuteMutedDevices)
            UserDefaults.standard.set(0.625, forKey: DefaultsKey.micMuteSavedVolume)
            UserDefaults.standard.set(active, forKey: DefaultsKey.micMuteActive)
            HAL.relaunchClient()
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            if active {
                MicMuteService.shared.setMuted(false)
                DispatchQueue.drain()
            }
            suite.expect(HAL.levels == [gain: 0, liveChannel: 0.25] && !HAL.writes.contains(gain),
                         "a recorded UID without a switch or saved level never raises the user's zero master")

            for originalSwitch: UInt32? in [nil, 0, 1] {
                HAL.reset()
                HAL.levels[gain] = 0.005
                HAL.mute[10] = originalSwitch
                UserDefaults.standard.set(0.625, forKey: DefaultsKey.micMuteSavedVolume)
                UserDefaults.standard.set(["device-10"], forKey: DefaultsKey.micMuteMutedDevices)
                UserDefaults.standard.set(active, forKey: DefaultsKey.micMuteActive)
                HAL.relaunchClient()
                let service = MicMuteService.shared
                service.syncWithPreferences()
                DispatchQueue.drain()
                if active {
                    service.setMuted(false)
                    DispatchQueue.drain()
                }
                // v3.4.3 stored only the UID when its native master switch worked.
                suite.expect(HAL.levels[gain] == 0.005
                             && !service.hasOutstandingClaims && !service.isMuted && (originalSwitch == nil || HAL.mute[10] == 0),
                             "a UID with a native switch preserves its gain beside a stale global (active: \(active), switch: \(String(describing: originalSwitch)))")
            }
        }

        // A pre-3.2 record refers to the default input. A fresh manual
        // request may still find an old saved global level on the same Mac.
        for inherited in [false, true] {
            HAL.reset()
            HAL.devices = [10, 20]
            HAL.levels = [gain: 0.005, HAL.key(20): 0.008]
            UserDefaults.standard.set(0.625, forKey: DefaultsKey.micMuteSavedVolume)
            UserDefaults.standard.set(inherited, forKey: DefaultsKey.micMuteActive)
            HAL.relaunchClient()
            let service = MicMuteService.shared
            if inherited { service.syncWithPreferences() } else { service.setMuted(true) }
            DispatchQueue.drain()
            service.setMuted(false)
            DispatchQueue.drain()
            suite.expect(HAL.levels[gain] == 0.005 && HAL.levels[HAL.key(20)] == 0.008,
                         "a current mute restores both microphones to their measured gains beside an unbound global")
        }

        let otherGain = HAL.key(20)
        let otherChannelMute = HAL.key(20, 1, kAudioDevicePropertyMute)
        let channelMute = HAL.key(10, 1, kAudioDevicePropertyMute)
        for reapply in [false, true] {
            HAL.reset()
            HAL.devices = [10, 20]
            HAL.levels = [gain: 0.005, otherGain: 0.005]
            HAL.mute[20] = 1
            HAL.muteElements[otherChannelMute] = 1
            UserDefaults.standard.set(0.625, forKey: DefaultsKey.micMuteSavedVolume)
            UserDefaults.standard.set(["device-10", "device-20"], forKey: DefaultsKey.micMuteMutedDevices)
            UserDefaults.standard.set(reapply, forKey: DefaultsKey.micMuteActive)
            HAL.relaunchClient()
            let service = MicMuteService.shared
            service.syncWithPreferences()
            DispatchQueue.drain()
            if reapply {
                service.setMuted(false)
                DispatchQueue.drain()
            }
            suite.expect(HAL.levels[gain] == 0.005 && HAL.levels[otherGain] == 0.005 && HAL.mute[20] == 0
                         && HAL.muteElements[otherChannelMute] == 1 && !service.hasOutstandingClaims,
                         "a claimed native mic keeps its own gain and channel mute beside the legacy default")

            HAL.reset()
            HAL.devices = [10, 20]
            HAL.mute = [10: 1, 20: 1]
            HAL.muteElements[channelMute] = 1
            UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteActive)
            HAL.relaunchClient()
            if reapply {
                MicMuteService.shared.syncWithPreferences()
                DispatchQueue.drain()
            }
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
            suite.expect(HAL.mute[10] == 1 && HAL.mute[20] == 1 && HAL.muteElements[channelMute] == 1 && HAL.writes.isEmpty,
                         "a pre-3.2 flag without a UID preserves existing switches on every microphone")

            HAL.reset()
            HAL.levels = [gain: 0.005, HAL.key(10, 1): 0, HAL.key(10, 2): 0.35]
            HAL.mute[10] = 1
            HAL.muteElements[channelMute] = 1
            UserDefaults.standard.set(0.625, forKey: DefaultsKey.micMuteSavedVolume)
            UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteActive)
            HAL.relaunchClient()
            if reapply {
                MicMuteService.shared.syncWithPreferences()
                DispatchQueue.drain()
            }
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
            suite.expect(HAL.levels == [gain: 0.005, HAL.key(10, 1): 0, HAL.key(10, 2): 0.35]
                         && HAL.mute[10] == 1 && HAL.muteElements[channelMute] == 1,
                         "a pre-3.2 flag and global gain cannot claim a switch or gain on the current default")

            HAL.reset()
            let third = HAL.key(10, 3)
            let virtual = HAL.key(10, 0, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            HAL.streamChannels[10] = [3]
            HAL.levels = [gain: 0.005, HAL.key(10, 1): 0, HAL.key(10, 2): 0, third: 0, virtual: 0]
            HAL.mute[10] = 1
            HAL.muteElements[channelMute] = 1
            UserDefaults.standard.set(["device-10": 0.7], forKey: DefaultsKey.micMuteSavedVolumes)
            // Only positive channels were included in the old stereo snapshot.
            UserDefaults.standard.set(["device-10": ["2": 0.4]], forKey: DefaultsKey.micMuteSavedChannelVolumes)
            UserDefaults.standard.set(["device-10"], forKey: DefaultsKey.micMuteMutedDevices)
            UserDefaults.standard.set(reapply, forKey: DefaultsKey.micMuteActive)
            HAL.relaunchClient()
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            if reapply {
                MicMuteService.shared.setMuted(false)
                DispatchQueue.drain()
            }
            suite.expect(HAL.levels == [gain: 0.005, HAL.key(10, 1): 0, HAL.key(10, 2): 0.4, third: 0, virtual: 0]
                         && HAL.mute[10] == 1 && HAL.muteElements[channelMute] == 1
                         && MicMuteService.shared.warning == .manualRestore,
                         "a per-UID stereo record restores only its named channel and retains existing mutes")

            HAL.reset()
            let virtualMain = HAL.key(10, 0, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            let thirdChannel = HAL.key(10, 3)
            HAL.streamChannels[10] = [3]
            HAL.levels = [gain: 0.005, HAL.key(10, 1): 0, HAL.key(10, 2): 0.45, thirdChannel: 0, virtualMain: 0]
            HAL.muteElements[channelMute] = 1
            UserDefaults.standard.set(0.625, forKey: DefaultsKey.micMuteSavedVolume)
            UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteActive)
            HAL.relaunchClient()
            if reapply {
                MicMuteService.shared.syncWithPreferences()
                DispatchQueue.drain()
            }
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
            suite.expect(HAL.levels == [gain: 0.005, HAL.key(10, 1): 0, HAL.key(10, 2): 0.45,
                                        thirdChannel: 0, virtualMain: 0] && HAL.muteElements[channelMute] == 1,
                         "a pre-3.2 flag without a UID preserves every scalar's own level")
        }

        for (stored, current): (Double, Float) in [(0.005, 0.005), (0.01, 0.005), (1.1, 0.005), (0.625, 0.45)] {
            HAL.reset()
            HAL.levels = [gain: current, HAL.key(10, 1): 0]
            UserDefaults.standard.set(stored, forKey: DefaultsKey.micMuteSavedVolume)
            UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteActive)
            HAL.relaunchClient()
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
            suite.expect(HAL.levels == [gain: current, HAL.key(10, 1): 0] && HAL.writes.isEmpty,
                         "an invalid legacy gain or a live master cannot claim the user's zero channel")
        }

        HAL.reset()
        HAL.devices = [10, 20]
        HAL.levels = [gain: 0.005, otherGain: 0.005]
        HAL.ignoredWrites = [gain]
        UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteActive)
        bindLegacyDefault(gain: 0.625, scalars: [0])
        HAL.relaunchClient()
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        suite.expect(UserDefaults.standard.stringArray(forKey: DefaultsKey.micMuteMutedDevices) == ["device-10"],
                     "a refused first legacy restore persists the original default UID")
        HAL.current = 20
        HAL.ignoredWrites = []
        HAL.relaunchClient()
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        suite.expect(HAL.levels[gain] == 0.625 && HAL.levels[otherGain] == 0.005 && !MicMuteService.shared.hasOutstandingClaims,
                     "retrying after the default changes restores the original input and keeps the new gain")

        runLegacyReadFailureTests(suite)
    }

    private static func runUIDOnlySwitchRestoreTests(_ suite: TestSuite) {
        let defaults = UserDefaults.standard
        let uid = "returning microphone"
        let gain = HAL.key(30)
        let native = HAL.key(30, 0, kAudioDevicePropertyMute)
        let list = HAL.key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal)
        let other = HAL.key(20)
        func prepare(active: Bool) {
            HAL.reset()
            HAL.devices = [20]
            HAL.current = 20
            HAL.levels[other] = 0.375
            defaults.set([uid], forKey: DefaultsKey.micMuteMutedDevices)
            defaults.set(active, forKey: DefaultsKey.micMuteActive)
            // The old native path left both per-UID level dictionaries empty.
            defaults.set([String: Double](), forKey: DefaultsKey.micMuteSavedVolumes)
            defaults.set([String: [String: Double]](), forKey: DefaultsKey.micMuteSavedChannelVolumes)
            defaults.set(0.625, forKey: DefaultsKey.micMuteSavedVolume)
            HAL.relaunchClient()
        }
        func release() {
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
        }
        for missing in ["absent", "unreadable", "read-only"] {
            prepare(active: false)
            release()
            suite.expect(MicMuteService.shared.hasOutstandingClaims && !defaults.bool(forKey: DefaultsKey.micMuteManualCheckNeeded),
                         "an offline recorded UID still waits for its actual control")
            HAL.devices.append(30)
            HAL.uids[30] = uid
            HAL.levels[gain] = 0
            if missing != "absent" { HAL.mute[30] = 1 }
            if missing == "unreadable" { HAL.readFails = [native] }
            if missing == "read-only" { HAL.readOnly = [native] }
            _ = HAL.notifyIfRegistered(list)
            DispatchQueue.drain()
            suite.expect(MicMuteService.shared.warning == .manualRestore && !MicMuteService.shared.hasOutstandingClaims
                         && MicMuteService.shared.inputVolumeAdjustmentLifetime != nil && HAL.writes.isEmpty
                         && QuickToolHUD.messages.last == L10n.shared.s.micManualRestore,
                         "a zero gain cannot verify the returning UID's \(missing) master switch")
            if missing == "read-only" {
                MicMuteService.shared.acknowledgeManualRestore()
                DispatchQueue.drain()
            }
            HAL.mute[30] = 1
            HAL.readFails = []
            HAL.readOnly = []
            HAL.relaunchClient()
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            release()
            suite.expect(HAL.mute[30] == 1 && HAL.levels[gain] == 0 && HAL.levels[other] == 0.375
                         && HAL.writes.isEmpty && MicMuteService.shared.warning == (missing == "read-only" ? nil : .manualRestore),
                         "a switch that returns after manual handoff stays at the user's setting")
        }

        for residual: Float in [0, 0.005] {
            prepare(active: true)
            HAL.devices.append(30)
            HAL.uids[30] = uid
            HAL.levels[gain] = residual
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            suite.expect(MicMuteService.shared.isMuted && HAL.levels[gain] == 0 && HAL.levels[other] == 0
                         && defaults.bool(forKey: DefaultsKey.micMuteManualCheckNeeded),
                         "reapplying mute separates the unidentified old control from the gains closed now")
            HAL.mute[30] = 1
            HAL.relaunchClient()
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            release()
            suite.expect(HAL.levels[gain] == residual && HAL.mute[30] == 1 && !HAL.writes.contains(native)
                         && HAL.levels[other] == 0.375 && !MicMuteService.shared.hasOutstandingClaims
                         && MicMuteService.shared.warning == .manualRestore,
                         "a reapply restores only the newly measured gains and preserves the late native switch")
        }
    }

    private static func runUnidentifiedLegacyDefaultTests(_ suite: TestSuite) {
        let defaults = UserDefaults.standard
        let system = AudioObjectID(kAudioObjectSystemObject)
        let route = HAL.key(system, 0, kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
        let uid = HAL.key(10, 0, kAudioDevicePropertyDeviceUID, scope: kAudioObjectPropertyScopeGlobal)
        let original = HAL.key(10)
        let other = HAL.key(20)
        let returned = HAL.key(30)
        func prepare() {
            HAL.reset()
            HAL.devices = [10, 20]
            HAL.uids[10] = "old microphone"
            HAL.levels = [original: 0.005, other: 0.42]
            defaults.set(true, forKey: DefaultsKey.micMuteActive)
            defaults.set(0.625, forKey: DefaultsKey.micMuteSavedVolume)
        }
        func release() {
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
        }
        func pendingRecord() -> [String: Any]? {
            guard let data = defaults.data(forKey: DefaultsKey.micMutePendingLegacyControls) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }

        func hasOnlyReminder() -> Bool {
            defaults.bool(forKey: DefaultsKey.micMuteManualCheckNeeded)
                && defaults.data(forKey: DefaultsKey.micMutePendingLegacyControls) == nil
                && defaults.object(forKey: DefaultsKey.micMuteSavedVolume) == nil
        }

        // The headset was replaced before upgrading. Its UID is readable
        // on the new version's very first sweep, at the old default's ID.
        for usedNativeSwitch in [false, true] {
            prepare()
            if usedNativeSwitch { defaults.removeObject(forKey: DefaultsKey.micMuteSavedVolume) }
            HAL.uids[10] = "headset connected before upgrade"
            HAL.mute[10] = usedNativeSwitch ? 1 : nil
            HAL.relaunchClient()
            release()
            suite.expect(HAL.writes.isEmpty && HAL.levels[original] == 0.005
                         && HAL.mute[10] == (usedNativeSwitch ? 1 : nil) && hasOnlyReminder()
                         && !MicMuteService.shared.hasOutstandingClaims && !MicMuteService.shared.isMuted
                         && MicMuteService.shared.inputVolumeAdjustmentLifetime != nil,
                         "a readable replacement before upgrade keeps its gain and switch after an anonymous release")
        }

        // The ID can also be recycled after an incomplete first sweep.
        for missing in [nil, route, uid] {
            prepare()
            if let missing { HAL.readFails = [missing] }
            HAL.relaunchClient()
            release()
            suite.expect(HAL.writes.isEmpty && hasOnlyReminder(),
                         "an unidentified legacy input leaves only a manual reminder and no restorable target")
            HAL.uids[10] = "replacement on the same ID"
            HAL.readFails = []
            HAL.relaunchClient()
            release()
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            suite.expect(HAL.writes.isEmpty && HAL.levels == [original: 0.005, other: 0.42]
                         && hasOnlyReminder(),
                         "a directly recycled ID never acquires the legacy global gain")
        }

        // Old pending data could contain an object ID and exclusions. Neither
        // identifies the device originally muted by the pre-UID release.
        prepare()
        let oldRecord: [String: Any] = [
            "observedDefaultID": 10, "excludedUIDs": ["device-20"], "gain": 0.625,
            "checkSwitch": false, "unreadScalars": [], "residualScalars": []
        ]
        defaults.set(try! JSONSerialization.data(withJSONObject: oldRecord), forKey: DefaultsKey.micMutePendingLegacyControls)
        defaults.set(false, forKey: DefaultsKey.micMuteActive)
        defaults.set([String](), forKey: DefaultsKey.micMuteMutedDevices)
        HAL.uids[10] = "new device"
        HAL.relaunchClient()
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        suite.expect(HAL.writes.isEmpty && HAL.levels[original] == 0.005 && hasOnlyReminder()
                     && !MicMuteService.shared.hasOutstandingClaims && HAL.listeners.isEmpty,
                     "launching with an older ID-only record consumes it once and leaves only the reminder")

        // A pending old default never prevents a current mute or restore on
        // the known microphone. The already-muted third input stays untouched.
        for lostUID in [true, false] {
            prepare()
            HAL.devices.append(40)
            HAL.levels[HAL.key(40)] = 0
            HAL.mute[40] = 1
            if lostUID { HAL.readFails = [uid] } else { HAL.levels[original] = nil }
            HAL.relaunchClient()
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            suite.expect(HAL.levels[other] == 0 && HAL.writes == [other] && hasOnlyReminder(),
                         "a mute with missing default identity or controls still snapshots and silences the other known mic")
            HAL.relaunchClient()
            release()
            suite.expect(HAL.levels[other] == 0.42 && HAL.mute[40] == 1 && HAL.writes == [other, other]
                         && hasOnlyReminder(),
                         "a release restores other owned inputs and keeps only a reminder for the unidentified one")
            HAL.uids[10] = "replacement on the same ID"
            HAL.readFails = []
            HAL.levels[original] = 0.005
            release()
            suite.expect(HAL.levels[original] == 0.005 && HAL.writes == [other, other],
                         "a replacement at the incomplete default's ID keeps its own level")
            HAL.devices = [10, 20, 30, 40]
            HAL.uids[30] = "old microphone"
            HAL.levels[returned] = 0.005
            HAL.relaunchClient()
            release()
            suite.expect(HAL.levels[returned] == 0.005 && hasOnlyReminder() && HAL.levels[other] == 0.42,
                         "even a familiar UID cannot be given a gain whose original owner was never recorded")
        }

        // A previous migration that already recorded a UID and scalar
        // remains recoverable while the original input only exposes topology.
        prepare()
        bindLegacyDefault(uid: "old microphone", gain: 0.625, scalars: [0])
        HAL.levels[original] = nil
        HAL.relaunchClient()
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        suite.expect(HAL.writes == [other] && HAL.levels[other] == 0 && pendingRecord()?["uid"] as? String == "old microphone",
                     "an unavailable bound scalar does not block a mute on another known microphone")
        HAL.uids[10] = "replacement on the same ID"
        HAL.levels[original] = 0.005
        HAL.relaunchClient()
        release()
        suite.expect(HAL.levels == [original: 0.005, other: 0.42] && HAL.writes == [other, other]
                     && pendingRecord()?["uid"] as? String == "old microphone",
                     "releasing a different microphone keeps an absent UID's bound scalar owed")
        HAL.current = 20
        HAL.devices.append(30)
        HAL.uids[30] = "old microphone"
        HAL.levels[returned] = 0
        HAL.relaunchClient()
        release()
        suite.expect(HAL.levels == [original: 0.005, other: 0.42, returned: 0.625] && pendingRecord() == nil,
                     "a returning recorded UID recovers its own scalar on a different HAL object")
    }

    /// On-disk format of a previous migration that had already recorded
    /// the original default's UID and its still-unread controls.
    private static func bindLegacyDefault(uid: String = "device-10", gain: Double?, scalars: [UInt32], checkSwitch: Bool = false) {
        var record: [String: Any] = ["uid": uid, "checkSwitch": checkSwitch, "unreadScalars": scalars,
                                     "residualScalars": []]
        if let first = scalars.first { record["firstScalar"] = first }
        if let gain { record["gain"] = gain }
        UserDefaults.standard.set(try! JSONSerialization.data(withJSONObject: record), forKey: DefaultsKey.micMutePendingLegacyControls)
        UserDefaults.standard.set([uid], forKey: DefaultsKey.micMuteMutedDevices)
    }

    private static func runLegacyReadFailureTests(_ suite: TestSuite) {
        runUnidentifiedLegacyDefaultTests(suite)
        let master = HAL.key(10)
        let left = HAL.key(10, 1)
        let right = HAL.key(10, 2)
        let other = HAL.key(20)
        HAL.reset()
        HAL.levels = [master: 0, left: 0]
        HAL.readFails = [master]
        bindLegacyDefault(gain: 0.625, scalars: [0, 1])
        UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteActive)
        HAL.relaunchClient()
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        HAL.levels = [master: 0, right: 0]
        HAL.readFails = []
        HAL.relaunchClient()
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        suite.expect(MicMuteService.shared.hasOutstandingClaims && HAL.levels[master] == 0.625 && HAL.levels[right] == 0,
                     "the master restores when it recovers even if the original channel is now absent")
        HAL.levels[master] = nil
        HAL.levels[left] = 0
        HAL.relaunchClient()
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        suite.expect(HAL.levels == [left: 0.625, right: 0] && !MicMuteService.shared.hasOutstandingClaims,
                     "only the controls seen on the legacy default inherit its gain")

        HAL.reset()
        let native = HAL.key(10, 0, kAudioDevicePropertyMute)
        HAL.mute[10] = 1
        HAL.levels = [left: 0, right: 0]
        HAL.readFails = [native, right]
        UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteActive)
        bindLegacyDefault(gain: 0.625, scalars: [1, 2], checkSwitch: true)
        HAL.relaunchClient()
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        HAL.readOnly = [native]
        HAL.readFails = [right]
        HAL.relaunchClient()
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        suite.expect(HAL.levels[left] == 0.625 && HAL.mute[10] == 1 && MicMuteService.shared.hasOutstandingClaims,
                     "a read-only native control leaves a proven gain restorable while its sibling remains unreadable")
        HAL.levels[left] = 0.25
        HAL.readFails = []
        HAL.relaunchClient()
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        suite.expect(HAL.levels == [left: 0.25, right: 0.625] && HAL.mute[10] == 1 && !MicMuteService.shared.hasOutstandingClaims,
                     "the pending gain restores independently after native switch and stereo read failures")

        for reapply in [false, true] {
            // An unresolved bound scalar keeps both its UID and its target
            // across a failed read, a relaunch, and a change of default.
            for (stored, recovered, expected): (Double?, Float, Float) in [
                (0.625, 0.005, 0.625), (0.625, 0.375, 0.375), (nil, 0, 0.75), (nil, 0.005, 0.005)
            ] {
                HAL.reset()
                HAL.devices = [10, 20]
                HAL.levels = [master: recovered, other: 0.005]
                HAL.readFails = [master]
                bindLegacyDefault(gain: stored, scalars: [0])
                UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteActive)
                HAL.relaunchClient()
                if reapply { MicMuteService.shared.syncWithPreferences() } else { MicMuteService.shared.setMuted(false) }
                DispatchQueue.drain()
                let claims = UserDefaults.standard.stringArray(forKey: DefaultsKey.micMuteMutedDevices) ?? []
                suite.expect(claims.contains("device-10") && !HAL.writes.contains(master),
                             "the old default's unreadable scalar remains pending across its first sweep")
                HAL.current = 20
                HAL.readFails = []
                HAL.relaunchClient()
                MicMuteService.shared.setMuted(false)
                DispatchQueue.drain()
                suite.expect(HAL.levels[master] == expected && HAL.levels[other] == 0.005
                             && !MicMuteService.shared.hasOutstandingClaims,
                             "the returning default resolves a residual, fallback zero or live gain by its original UID")
            }

            HAL.reset()
            HAL.levels = [left: 0]
            UserDefaults.standard.set(["device-10"], forKey: DefaultsKey.micMuteMutedDevices)
            UserDefaults.standard.set(["device-10": ["1": 0.4, "2": 0.8]], forKey: DefaultsKey.micMuteSavedChannelVolumes)
            UserDefaults.standard.set(reapply, forKey: DefaultsKey.micMuteActive)
            HAL.relaunchClient()
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            if reapply {
                MicMuteService.shared.setMuted(false)
                DispatchQueue.drain()
            }
            suite.expect(HAL.levels[left] == 0.4 && MicMuteService.shared.hasOutstandingClaims,
                         "the available stereo channel restores while its absent sibling stays owed")
            HAL.levels = [left: 0.35, right: 0]
            HAL.relaunchClient()
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
            suite.expect(HAL.levels == [left: 0.35, right: 0.8] && !MicMuteService.shared.hasOutstandingClaims,
                         "the returning stereo channel restores without undoing a new level on its released sibling")
        }
    }

    private static func runHistorical344ChannelCaptureTests(_ suite: TestSuite) {
        // Recorded from v3.4.4 (d9c7f4a7) with its own HAL fixture and an isolated
        // Foundation.UserDefaults suite. setMuted(true) closed device-20's switch.
        // Connecting device-10 with only scalar channel 1 at 0.625 and reapplying
        // recorded the key and persisted value after each write to that suite.
        // On first use the same three gain records preceded the UID list.
        let path = "Tests/Fixtures/MicMute344ChannelOne.plist"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let fixture = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let before = fixture["beforeConnection"] as? [String: Any],
              let fresh = fixture["firstUseBeforeListing"] as? [String: Any], fresh.count == 3,
              let writes = fixture["writes"] as? [[String: Any]], writes.count == 5 else {
            suite.expect(false, "load the v3.4.4 channel capture at \(path)")
            return
        }
        let keys = ["micMuteActive": DefaultsKey.micMuteActive,
                    "micMuteSavedVolumes": DefaultsKey.micMuteSavedVolumes,
                    "micMuteSavedChannelVolumes": DefaultsKey.micMuteSavedChannelVolumes,
                    "micMuteSavedControls": DefaultsKey.micMuteSavedControls,
                    "micMuteMutedDevices": DefaultsKey.micMuteMutedDevices]
        let master = HAL.key(30)
        let channel = HAL.key(30, 1)
        let otherSwitch = HAL.key(20, 0, kAudioDevicePropertyMute)
        for firstUse in [false, true] {
            var disk = firstUse ? [:] : before
            for (index, write) in writes.enumerated() {
                guard let key = write["key"] as? String, keys[key] != nil, let value = write["value"] else {
                    suite.expect(false, "read historical preference write \(index + 1)")
                    return
                }
                if firstUse && index >= fresh.count { break }
                disk[key] = firstUse ? fresh[key] : value
                HAL.reset()
                for (name, local) in keys { UserDefaults.standard.values[local] = disk[name] }
                HAL.devices = firstUse ? [30] : [20, 30]
                HAL.uids[30] = "device-10"
                if !firstUse { HAL.mute[20] = 1 }
                HAL.levels = [master: 0]
                HAL.relaunchClient()
                if firstUse { MicMuteService.shared.syncWithPreferences() }
                else { MicMuteService.shared.toggle() }
                DispatchQueue.drain()
                let recordedChannel = index >= 1
                let context = firstUse ? "first use" : "active mute"
                suite.expect(HAL.writes == (firstUse ? [] : [otherSwitch]) && HAL.levels[master] == 0
                             && MicMuteService.shared.hasOutstandingClaims == recordedChannel,
                             "v3.4.4 \(context) after \(key) never puts channel 1's gain on a new master")
                if !recordedChannel {
                    suite.expect(MicMuteService.shared.warning == .manualRestore
                                 && MicMuteService.shared.inputVolumeAdjustmentLifetime != nil,
                                 "v3.4.4 \(context) with just the UID gain leaves the mixer available for a manual check")
                }
                HAL.writes = []
                HAL.levels[channel] = 0
                HAL.relaunchClient()
                MicMuteService.shared.syncWithPreferences()
                DispatchQueue.drain()
                suite.expect(HAL.writes == (recordedChannel ? [channel] : []) && HAL.levels[master] == 0
                             && HAL.levels[channel] == (recordedChannel ? 0.625 : 0)
                             && !MicMuteService.shared.hasOutstandingClaims,
                             "v3.4.4 \(context) after \(key) restores only a recorded channel when that element returns")
            }
        }
    }

    private static func runLegacyStereoAccessTests(_ suite: TestSuite) {
        let defaults = UserDefaults.standard
        let uid = "device-10"
        let master = HAL.key(10)
        let left = HAL.key(10, 1)
        let right = HAL.key(10, 2)
        func seed(_ level: Double?, _ channels: [String: Double]) {
            defaults.set([uid], forKey: DefaultsKey.micMuteMutedDevices)
            if let level { defaults.set([uid: level], forKey: DefaultsKey.micMuteSavedVolumes) }
            defaults.set([uid: channels], forKey: DefaultsKey.micMuteSavedChannelVolumes)
        }
        func release() {
            HAL.relaunchClient()
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
        }
        func finished() -> Bool {
            !MicMuteService.shared.hasOutstandingClaims && MicMuteService.shared.warning == nil
        }

        HAL.reset()
        seed(0.625, ["1": 0.25, "2": 0.75])
        defaults.set([uid: ["\(master.s):0": 0.625, "1": 0.25, "2": 0.75]], forKey: DefaultsKey.micMuteSavedControls)
        HAL.levels = [master: 0, left: 0.005, right: 0]
        HAL.readOnly = [left]
        release()
        suite.expect(HAL.writes == [master, right] && HAL.levels == [master: 0.625, left: 0.005, right: 0.75]
                     && finished(), "a legacy stereo meter has no restore target alongside its writable master and channel")

        HAL.reset()
        seed(nil, ["1": 0.25])
        HAL.levels = [left: 0.005]
        HAL.readOnly = [left]
        release()
        suite.expect(HAL.writes.isEmpty && HAL.levels[left] == 0.005 && finished(),
                     "a stereo record with only a read-only meter leaves no automatic restore outstanding")

        HAL.reset()
        seed(nil, ["1": 0.25])
        HAL.levels = [left: 0.375]
        HAL.settableReadFails = [left]
        release()
        suite.expect(HAL.writes.isEmpty && HAL.levels[left] == 0.375 && !MicMuteService.shared.hasOutstandingClaims
                     && MicMuteService.shared.warning == .manualRestore,
                     "a legacy reading with unknown write access leaves the original input available for a manual check")
        HAL.settableReadFails = []
        release()
        suite.expect(HAL.writes.isEmpty && HAL.levels[left] == 0.375 && MicMuteService.shared.warning == .manualRestore,
                     "a later access query cannot turn an ambiguous meter reading into a restore obligation")

        for readOnly in [false, true] {
            HAL.reset()
            seed(nil, ["1": 0.25, "2": 0.75])
            HAL.levels = [left: 0]
            release()
            suite.expect(HAL.writes == [left] && HAL.levels[left] == 0.25 && MicMuteService.shared.hasOutstandingClaims,
                         "a missing legacy stereo element stays pending while the known channel restores")
            HAL.levels = [left: 0.375, right: 0.005]
            if readOnly { HAL.readOnly = [right] }
            HAL.writes = []
            release()
            suite.expect(HAL.writes == (readOnly ? [] : [right]) && HAL.levels[left] == 0.375
                         && HAL.levels[right] == (readOnly ? 0.005 : 0.75) && finished(),
                         "the returning legacy element is classified before becoming a writable restore target")
        }

        HAL.reset()
        seed(0.625, ["1": 0.25, "2": 0.75])
        defaults.set([uid: ["\(master.s):0": 0.625, "1": 0.25, "2": 0.75]], forKey: DefaultsKey.micMuteSavedControls)
        HAL.levels = [left: 0, right: 0.005]
        HAL.readOnly = [right]
        release()
        suite.expect(HAL.writes == [left] && HAL.levels[left] == 0.25 && MicMuteService.shared.hasOutstandingClaims,
                     "an absent legacy master retains its identity while its writable channel is released")
        HAL.levels = [master: 0]
        HAL.writes = []
        release()
        suite.expect(HAL.writes.isEmpty && HAL.levels[master] == 0 && MicMuteService.shared.hasOutstandingClaims,
                     "a previously released writable channel must be readable before a coupled master moves")
        HAL.levels[left] = 0.375
        HAL.beforeControlWrite = { key, target in
            if key == master { HAL.levels[left] = Float(target) }
        }
        release()
        suite.expect(HAL.writes == [master, left] && HAL.levels == [master: 0.625, left: 0.375] && finished(),
                     "a returning writable sibling keeps its live level while the absent meter is never owed")

        HAL.reset()
        seed(0.25, ["1": 0.25])
        defaults.set([uid: ["\(left.s):1": 0.25]], forKey: DefaultsKey.micMuteSavedControls)
        HAL.levels = [left: 0]
        HAL.readOnly = [left]
        release()
        suite.expect(HAL.writes.isEmpty && MicMuteService.shared.hasOutstandingClaims
                     && MicMuteService.shared.warning == .restoreUnconfirmed,
                     "a temporarily read-only control with a modern snapshot remains owed")
        HAL.readOnly = []
        release()
        suite.expect(HAL.writes == [left] && HAL.levels[left] == 0.25 && finished(),
                     "the modern control restores its own verified target when write access returns")

        HAL.reset()
        seed(0.625, ["1": 0.25, "2": 0.875])
        defaults.set([uid: ["\(master.s):0": 0.625, "1": 0.25, "2": 0.875]], forKey: DefaultsKey.micMuteSavedControls)
        HAL.devices = [20]
        let call = HAL.key(20)
        HAL.levels = [call: 0.5, master: 0, left: 0.125, right: 0]
        HAL.readOnly = [left]
        defaults.set(true, forKey: DefaultsKey.micMuteActive)
        defaults.set(true, forKey: DefaultsKey.micMuteFollowCallApps)
        HAL.relaunchClient()
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        let pid = ProcessInfo.processInfo.processIdentifier
        HAL.processes = [(100, pid == 4242 ? 4243 : 4242, true, [20])]
        HAL.afterProcessListRead = { HAL.devices = [10, 20] }
        HAL.levels[call] = 0.75
        HAL.writes = []
        _ = HAL.notifyIfRegistered(call)
        DispatchQueue.drain()
        suite.expect(!MicMuteService.shared.isMuted && finished() && HAL.afterProcessListRead == nil
                     && HAL.levels[master] == 0.625 && HAL.levels[left] == 0.125 && HAL.levels[right] == 0.875
                     && !HAL.writes.contains(left),
                     "a stereo input that returns during a call's release restores its verified channel balance")
    }

    private static func runObservedChannelRestoreTests(_ suite: TestSuite) {
        let master = HAL.key(10)
        let third = HAL.key(10, 3)
        let other = HAL.key(20)
        for (readOnly, accessUnknown) in [(true, false), (true, true), (false, false)] {
            HAL.reset()
            HAL.devices = [10, 20]
            HAL.streamChannels[10] = [3]
            HAL.levels = [master: 0.625, third: 0.25, other: 0.875]
            if readOnly { HAL.readOnly = [third] }
            HAL.beforeControlWrite = { key, target in
                if key == master && HAL.levels[third] != nil { HAL.levels[third] = Float(target) }
            }
            MicMuteService.shared.setMuted(true)
            DispatchQueue.drain()
            let saved = UserDefaults.standard.dictionary(forKey: DefaultsKey.micMuteSavedControls) as? [String: [String: Double]]
            suite.expect(HAL.levels[third] == 0 && saved?["device-10"]?["\(third.s):3"] == (readOnly ? nil : 0.25),
                         "the master can silence a meter without claiming it as a writable channel")
            HAL.levels[master] = nil
            if accessUnknown { HAL.settableReadFails = [third] }
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
            suite.expect(HAL.levels[third] == (readOnly ? 0 : 0.25) && HAL.levels[other] == 0.875
                         && MicMuteService.shared.hasOutstandingClaims,
                         "the missing master remains owed after independent controls are released")
            HAL.streamChannels[10] = [2]
            HAL.levels[third] = nil
            HAL.settableReadFails = []
            HAL.levels[master] = 0
            HAL.relaunchClient()
            HAL.writes = []
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            suite.expect(HAL.writes == (readOnly ? [master] : []) && HAL.levels[master] == (readOnly ? 0.625 : 0)
                         && MicMuteService.shared.hasOutstandingClaims == !readOnly,
                         "a missing read-only meter permits master restore while a released writable channel defers it")
            if !readOnly {
                HAL.levels[third] = 0.375
                MicMuteService.shared.syncWithPreferences()
                DispatchQueue.drain()
                suite.expect(HAL.writes == [master, third] && HAL.levels[master] == 0.625 && HAL.levels[third] == 0.375
                             && !MicMuteService.shared.hasOutstandingClaims,
                             "the returning writable channel keeps its live gain across the driver's coupled master restore")
            }
        }
    }

    private static func runManualRestoreAcknowledgementTests(_ suite: TestSuite) {
        let defaults = UserDefaults.standard
        let gain = HAL.key(10)
        for absentClaim in [false, true] {
            HAL.reset()
            HAL.levels[gain] = 0.005
            // An unbound migration and a separate, known headset that may
            // still be unplugged when the user checks the original microphone.
            let oldRecord: [String: Any] = ["gain": 0.625, "checkSwitch": false,
                                            "unreadScalars": [], "residualScalars": []]
            defaults.set(try! JSONSerialization.data(withJSONObject: oldRecord), forKey: DefaultsKey.micMutePendingLegacyControls)
            defaults.set(absentClaim ? ["device-20"] : [], forKey: DefaultsKey.micMuteMutedDevices)
            if absentClaim {
                defaults.set(["device-20": ["\(gain.s):0": 0.875]], forKey: DefaultsKey.micMuteSavedControls)
            }
            HAL.relaunchClient()
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
            suite.expect(MicMuteService.shared.warning == .manualRestore && !MicMuteService.shared.isMuted
                         && QuickToolHUD.messages.last == "check original microphone" && QuickToolHUD.showedFullMessage
                         && defaults.data(forKey: DefaultsKey.micMutePendingLegacyControls) == nil
                         && defaults.bool(forKey: DefaultsKey.micMuteManualCheckNeeded)
                         && MicMuteService.shared.inputVolumeAdjustmentLifetime != nil && HAL.writes.isEmpty,
                         "manual recovery names the uncertainty and leaves the user's input controls available")
            HAL.relaunchClient()
            suite.expect(MicMuteService.shared.warning == .manualRestore,
                         "manual recovery is visible after relaunch without a device notification")
            MicMuteService.shared.acknowledgeManualRestore()
            DispatchQueue.drain()
            suite.expect(!defaults.bool(forKey: DefaultsKey.micMuteManualCheckNeeded)
                         && MicMuteService.shared.warning == (absentClaim ? .restoreUnconfirmed : nil)
                         && HAL.writes.isEmpty && HAL.levels[gain] == 0.005,
                         "acknowledging the old input clears only its warning without adjusting any hardware")
            HAL.devices.append(20)
            let other = HAL.key(20)
            HAL.levels[other] = 0
            HAL.relaunchClient()
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            suite.expect(HAL.levels == [gain: 0.005, other: absentClaim ? 0.875 : 0]
                         && HAL.writes == (absentClaim ? [other] : []) && MicMuteService.shared.warning == nil,
                         "only the independently recorded UID restores after the manual check")
        }

        HAL.reset()
        defaults.set(true, forKey: DefaultsKey.micMuteActive)
        HAL.mute[10] = 1
        QuickToolHUD.messages = []
        HAL.relaunchClient()
        MicMuteService.shared.unmuteForTeardown()
        DispatchQueue.drain()
        suite.expect(MicMuteService.shared.warning == .manualRestore && QuickToolHUD.messages == ["check original microphone"]
                     && QuickToolHUD.showedFullMessage && MicMuteService.shared.inputVolumeAdjustmentLifetime != nil
                     && HAL.mute[10] == 1 && HAL.writes.isEmpty && HAL.listeners.isEmpty,
                     "teardown releases the mixer and reports the unidentified input without opening its switch")
    }

    private static func runProtectedChannelRestoreTests(_ suite: TestSuite) {
        let channel = HAL.key(10, 3)
        let sibling = HAL.key(10, 1)
        let other = HAL.key(20)
        let defaults = UserDefaults.standard
        func release() {
            HAL.relaunchClient()
            HAL.writes = []
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
        }
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioHardwareServiceDeviceProperty_VirtualMainVolume] {
            let master = HAL.key(10, 0, selector)
            for hidden in [false, true] {
                HAL.reset()
                HAL.devices = [10, 20]
                HAL.streamChannels[10] = [3]
                HAL.levels = [channel: 0, other: 0]
                defaults.set(["device-10", "device-20"], forKey: DefaultsKey.micMuteMutedDevices)
                defaults.set(["device-10": ["\(master.s):0": 0.625, "\(channel.s):3": 0.25, "\(sibling.s):1": 0.75],
                              "device-20": ["\(other.s):0": 0.875]], forKey: DefaultsKey.micMuteSavedControls)
                release()
                suite.expect(HAL.levels[channel] == 0.25 && HAL.levels[other] == 0.875
                             && MicMuteService.shared.hasOutstandingClaims,
                             "release an available channel and the other input while the master is missing")

                var live: Float = 0.375 // The user adjusts the released channel.
                HAL.levels[master] = 0
                HAL.levels[sibling] = 0
                HAL.levels[channel] = hidden ? nil : live
                HAL.streamChannels[10] = [2]
                HAL.readFails = hidden ? [] : [channel]
                HAL.beforeControlWrite = { key, target in
                    if key == master {
                        live = Float(target)
                        if HAL.levels[channel] != nil { HAL.levels[channel] = live }
                    }
                }
                release()
                suite.expect(live == 0.375 && HAL.writes == [sibling] && MicMuteService.shared.hasOutstandingClaims,
                             "an unreadable or missing released channel defers only its potentially coupled master")
                HAL.levels[channel] = live
                HAL.readFails = [sibling] // The other channel now hides its own user edit.
                HAL.levels[sibling] = 0.5
                release()
                suite.expect(live == 0.375 && HAL.writes.isEmpty && MicMuteService.shared.hasOutstandingClaims,
                             "alternating readable channels cannot authorize a master using stale values")
                HAL.readFails = []
                release()
                suite.expect(HAL.levels[channel] == 0.375 && HAL.levels[sibling] == 0.5 && HAL.levels[master] == 0.625
                             && HAL.writes == [master, channel] && !MicMuteService.shared.hasOutstandingClaims,
                             "all current channel edits survive the master restore after a relaunch and layout change")
            }
        }

        // This channel was never owed. A master-only record must protect it
        // even if the master itself becomes readable between two HAL reads.
        let master = HAL.key(10)
        HAL.reset()
        HAL.levels = [master: 0, sibling: 0.375]
        HAL.nextReadFails = [master]
        defaults.set(["device-10"], forKey: DefaultsKey.micMuteMutedDevices)
        defaults.set(["device-10": ["\(master.s):0": 0.625]], forKey: DefaultsKey.micMuteSavedControls)
        HAL.beforeControlWrite = { key, target in if key == master { HAL.levels[sibling] = Float(target) } }
        release()
        release()
        suite.expect(HAL.levels == [master: 0.625, sibling: 0.375] && !MicMuteService.shared.hasOutstandingClaims,
                     "a transient master read failure cannot bypass the live channel snapshot")

        HAL.reset()
        HAL.levels = [master: 0, sibling: 0.375]
        HAL.readFails = [sibling]
        defaults.set(["device-10"], forKey: DefaultsKey.micMuteMutedDevices)
        defaults.set(["device-10": ["\(master.s):0": 0.625]], forKey: DefaultsKey.micMuteSavedControls)
        release()
        HAL.levels[sibling] = nil
        HAL.readFails = []
        release()
        suite.expect(HAL.levels[master] == 0 && HAL.writes.isEmpty && MicMuteService.shared.hasOutstandingClaims,
                     "an unreadable writable channel stays protected when its property subsequently disappears")
        HAL.levels[master] = 0.625
        release()
        suite.expect(HAL.writes.isEmpty && !MicMuteService.shared.hasOutstandingClaims,
                     "a matching master needs only its own readback even while a protected channel remains hidden")
    }

    private static func runLowGainMuteTests(_ suite: TestSuite) {
        func setMuted(_ muted: Bool) {
            MicMuteService.shared.setMuted(muted)
            DispatchQueue.drain()
        }
        let gain = HAL.key(10)
        let other = HAL.key(20)
        let low: Float = 0.005
        // Include a positive value inside the old setter's comparison tolerance.
        for initial: Float in [low, 0.00005] {
            HAL.reset()
            HAL.levels[gain] = initial
            QuickToolHUD.messages = []
            setMuted(true)
            suite.expect(HAL.writes == [gain] && HAL.levels[gain] == 0 && MicMuteService.shared.isMuted
                         && !MicMuteService.shared.hasUnconfirmedInputs && QuickToolHUD.messages == ["muted"],
                         "muting a gain-only mic at \(initial) writes and confirms zero")
            HAL.relaunchClient()
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            HAL.ignoredWrites = [gain]
            setMuted(false)
            suite.expect(MicMuteService.shared.hasOutstandingClaims && HAL.levels[gain] == 0
                         && QuickToolHUD.messages.last == "unmute partial",
                         "a driver that ignores a low gain restore keeps the obligation and reports the failure")
            HAL.ignoredWrites = []
            HAL.writes = []
            setMuted(false)
            suite.expect(HAL.writes == [gain] && HAL.levels[gain] == initial
                         && !MicMuteService.shared.hasOutstandingClaims,
                         "the saved gain \(initial) survives a relaunch and is restored exactly")
        }

        for ignores in [false, true] {
            HAL.reset()
            var now: TimeInterval = 10
            let service = MicMuteService(uptime: { now })
            MicMuteService.shared = service
            HAL.devices = [10, 20]
            HAL.levels[gain] = ignores ? low : 0.4
            HAL.levels[other] = 0.7
            if ignores { HAL.ignoredWrites = [gain] } else { HAL.minimumGain[gain] = low }
            QuickToolHUD.messages = []
            setMuted(true)
            suite.expect(service.isMuted && service.hasUnconfirmedInputs && HAL.levels[gain] == low && HAL.levels[other] == 0
                         && HAL.writes.contains(gain) && QuickToolHUD.messages == ["mute partial"],
                         "an accepted zero write that leaves a positive readback warns the user")
            for _ in 0..<10 {
                suite.expect(HAL.notifyIfRegistered(gain), "the refusing gain remains observed")
                DispatchQueue.drain()
            }
            suite.expect(HAL.writes.filter { $0 == gain }.count == 3 && service.retryDeadline != nil
                         && QuickToolHUD.messages == ["mute partial"],
                         "repeated notices from a refusing physical mic back off without repeating its warning")
            let writesBeforeTopology = HAL.writes
            let topology = HAL.key(10, 0, kAudioDevicePropertyDeviceHasChanged, scope: kAudioObjectPropertyScopeGlobal)
            for _ in 0..<3 {
                suite.expect(HAL.notifyIfRegistered(topology), "the driver can also echo its device-change listener")
                DispatchQueue.drain()
            }
            suite.expect(HAL.writes == writesBeforeTopology && service.hasUnconfirmedInputs,
                         "structural notices for the same residual do not restart its writes")
            HAL.ignoredWrites = []
            HAL.minimumGain = [:]
            now += 1
            service.halQueue.runTimers()
            DispatchQueue.drain()
            suite.expect(service.isMuted && !service.hasUnconfirmedInputs && HAL.levels[gain] == 0,
                         "a scheduled retry confirms zero when the mic recovers")
            let settledWrites = HAL.writes
            now += 60
            service.halQueue.runTimers()
            DispatchQueue.drain()
            suite.expect(service.retryDeadline == nil && HAL.writes == settledWrites,
                         "a sustained zero clears the cooldown without another write")
            setMuted(false)
            suite.expect(HAL.levels[gain] == (ignores ? low : 0.4) && HAL.levels[other] == 0.7,
                         "recovery restores the gain saved before the first attempt")
        }

        HAL.reset()
        HAL.streamChannels[10] = [2]
        let left = HAL.key(10, 1)
        let right = HAL.key(10, 2)
        HAL.levels = [left: 0, right: low]
        HAL.mute[10] = 1
        HAL.minimumGain[right] = low
        QuickToolHUD.messages = []
        setMuted(true)
        suite.expect(HAL.writes.contains(right) && !HAL.writes.contains(left)
                     && HAL.levels[right] == low && HAL.mute[10] == 1 && QuickToolHUD.messages == ["mute partial"],
                     "one positive channel gets a zero attempt and a warning even with the native switch engaged")
        setMuted(false)
        suite.expect(HAL.levels[left] == 0 && HAL.levels[right] == low && HAL.mute[10] == 1
                     && !HAL.writes.contains(HAL.key(10, 0, kAudioDevicePropertyMute)),
                     "unmute preserves the user's original channel mix and their engaged mute switch")

        let rightSwitch = HAL.key(10, 2, kAudioDevicePropertyMute)
        for originalSwitch: UInt32? in [nil, 2, 0] {
            let usableSwitch = originalSwitch == 0
            HAL.reset()
            HAL.streamChannels[10] = [2]
            HAL.levels[left] = low
            HAL.muteElements[rightSwitch] = originalSwitch
            QuickToolHUD.messages = []
            let service = MicMuteService.shared
            setMuted(true)
            suite.expect(HAL.levels[left] == 0 && service.isMuted && service.hasUnconfirmedInputs == !usableSwitch
                         && (usableSwitch ? HAL.muteElements[rightSwitch] == 1 : !HAL.writes.contains(rightSwitch))
                         && QuickToolHUD.messages == [usableSwitch ? "muted" : "mute partial"],
                         "a zero on the left channel needs a confirmed control on the right")
            setMuted(false)
            suite.expect(HAL.levels[left] == low && HAL.muteElements[rightSwitch] == originalSwitch
                         && !service.hasOutstandingClaims,
                         "both types of channel control return to their saved values")
        }
    }

    private static func runInitialMuteRegistrationTests(_ suite: TestSuite) {
        let first = HAL.key(10)
        let second = HAL.key(20)
        let devicesChanged = HAL.key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyDevices,
                                     scope: kAudioObjectPropertyScopeGlobal)
        for follow in [false, true] {
            for (reopens, refusesCorrection) in [(false, false), (true, false), (true, true)] {
                HAL.reset()
                HAL.devices = [10, 20]
                HAL.levels = [first: 0.5, second: 0.75]
                UserDefaults.standard.set(follow, forKey: DefaultsKey.micMuteFollowCallApps)
                var missedNotice = false
                HAL.beforeControlWrite = { key, target in
                    guard reopens, key == second && target == 0 else { return }
                    HAL.levels[first] = 0.005
                    missedNotice = !HAL.notifyIfRegistered(first)
                    if refusesCorrection { HAL.ignoredWrites = [first] }
                }
                QuickToolHUD.messages = []
                let service = MicMuteService.shared
                service.setMuted(true)
                service.halQueue.run()
                // Observe the first publication before a background reapply can repair it.
                while QuickToolHUD.messages.isEmpty && !DispatchQueue.main.work.isEmpty { DispatchQueue.main.run() }
                suite.expect(missedNotice == reopens && HAL.listeners.contains(first) && service.isMuted && HAL.levels[second] == 0,
                             "the initial read can miss an opening before the gain listener is installed")
                suite.expect(HAL.levels[first] == (refusesCorrection ? 0.005 : 0)
                             && service.hasUnconfirmedInputs == refusesCorrection
                             && QuickToolHUD.messages == [refusesCorrection ? "mute partial" : "muted"],
                             "the first announcement reflects the mute rechecked after listener registration")
                HAL.ignoredWrites = []
                if follow {
                    // The second input has a confirmed mute even if the first refused.
                    let ownPID = ProcessInfo.processInfo.processIdentifier
                    HAL.processes = [(100, ownPID == 4242 ? 4243 : 4242, true, [20])]
                    HAL.levels[second] = 0.8
                    suite.expect(HAL.notifyIfRegistered(second), "the call opens the confirmed second input")
                } else {
                    service.setMuted(false)
                }
                DispatchQueue.drain()
                suite.expect(!service.isMuted && QuickToolHUD.messages.last == "unmuted"
                             && HAL.levels[first] == 0.5 && HAL.levels[second] == 0.75 && !service.hasOutstandingClaims,
                             "the post-registration check preserves the gains from before the first write")
            }
        }
        for follow in [false, true] {
            for notify in [false, true] {
                HAL.reset()
                HAL.devices = [10, 20]
                HAL.levels = [first: 0.5, second: 0.75]
                let defaults = UserDefaults.standard
                defaults.set(follow, forKey: DefaultsKey.micMuteFollowCallApps)
                let service = MicMuteService.shared
                var replacedAt: Int?
                var staleSetter = false
                HAL.afterListenerAdd[first] = {
                    // The original headset reopens before its first post-registration check.
                    HAL.levels[first] = 0.005
                    HAL.afterSettableCheck[first] = {
                        HAL.afterSettableCheck[first] = {
                            HAL.uids[10] = "replacement"
                            HAL.levels[first] = 0.875
                            replacedAt = HAL.deviceListReads
                            if notify { _ = HAL.notifyIfRegistered(devicesChanged) }
                        }
                    }
                }
                HAL.beforeControlWrite = { key, _ in
                    if key == first && replacedAt == HAL.deviceListReads { staleSetter = true }
                }
                service.setMuted(true)
                DispatchQueue.drain()
                let claims = Set(defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices) ?? [])
                suite.expect(replacedAt != nil && !staleSetter && service.isMuted && !service.hasUnconfirmedInputs
                             && HAL.levels[first] == 0 && claims == ["device-10", "device-20", "replacement"],
                             "post-registration correction snapshots the replacement before silencing it and retains the original claim")
                service.setMuted(false)
                DispatchQueue.drain()
                suite.expect(HAL.levels[first] == 0.875 && HAL.levels[second] == 0.75
                             && defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices) == ["device-10"],
                             "the replacement regains its own gain while the disconnected headset remains owed its original level")
                HAL.uids[10] = "device-10"
                HAL.levels[first] = 0.005
                _ = HAL.notifyIfRegistered(devicesChanged)
                DispatchQueue.drain()
                suite.expect(HAL.levels[first] == 0.5 && !service.hasOutstandingClaims,
                             "the returning original headset receives only its own pre-mute gain")
            }
        }
        for legacy in [false, true] {
            HAL.reset()
            HAL.levels = [first: 0.5]
            let service = MicMuteService.shared
            service.setMuted(true)
            DispatchQueue.drain()
            if legacy {
                bindLegacyDefault(gain: 0.5, scalars: [0])
                UserDefaults.standard.removeObject(forKey: DefaultsKey.micMuteSavedControls)
            }
            HAL.afterSettableCheck[first] = {
                HAL.uids[10] = "replacement"
                HAL.levels[first] = 0.875
                _ = HAL.notifyIfRegistered(devicesChanged)
            }
            HAL.writes = []
            service.setMuted(false)
            DispatchQueue.drain()
            suite.expect(HAL.writes.isEmpty && HAL.levels[first] == 0.875 && !service.isMuted && service.hasOutstandingClaims,
                         "a headset appearing during a manual restore never receives the departing input's gain")
            HAL.uids[10] = "device-10"
            HAL.levels[first] = 0
            _ = HAL.notifyIfRegistered(devicesChanged)
            DispatchQueue.drain()
            suite.expect(HAL.levels[first] == 0.5 && !service.hasOutstandingClaims,
                         "a restore interrupted by ID reuse keeps the exact gain until the original input returns")
        }
        enum Change { case replacement, sameUID, restart, manualUnmute }
        for change in [Change.replacement, .sameUID, .restart, .manualUnmute] {
            HAL.reset()
            let channel = HAL.key(10, 1)
            HAL.levels = [first: 0.5, channel: 0.25]
            let service = MicMuteService.shared
            var staleSetter = false
            var changedAt: Int?
            HAL.afterWrite = {
                // The master has changed. The channel is still owed at its original level.
                HAL.afterSettableCheck[channel] = {
                    changedAt = HAL.deviceListReads
                    switch change {
                    case .replacement:
                        HAL.uids[10] = "replacement"
                        HAL.levels = [first: 0.875, channel: 0.375]
                    case .sameUID: _ = HAL.notifyIfRegistered(devicesChanged)
                    case .restart: _ = HAL.restartAudioService()
                    case .manualUnmute: service.setMuted(false)
                    }
                }
            }
            HAL.beforeControlWrite = { key, value in
                if key == channel && value == 0 && changedAt == HAL.deviceListReads { staleSetter = true }
            }
            service.setMuted(true)
            DispatchQueue.drain()
            suite.expect(changedAt != nil && !staleSetter && service.isMuted == (change != .manualUnmute),
                         "a manual mute checks the current UID, topology, server and request at each setter (\(change))")
            if change != .manualUnmute { service.setMuted(false) }
            DispatchQueue.drain()
            suite.expect(HAL.levels[first] == (change == .replacement ? 0.875 : 0.5)
                         && HAL.levels[channel] == (change == .replacement ? 0.375 : 0.25)
                         && service.hasOutstandingClaims == (change == .replacement),
                         "an interrupted sweep keeps the pre-write levels of every input it changed (\(change))")
            if change == .replacement {
                HAL.uids[10] = "device-10"
                HAL.levels = [first: 0, channel: 0.25]
                _ = HAL.notifyIfRegistered(devicesChanged)
                DispatchQueue.drain()
                suite.expect(HAL.levels[first] == 0.5 && HAL.levels[channel] == 0.25 && !service.hasOutstandingClaims,
                             "the partly silenced original device regains its pre-write snapshot on reconnection")
            }
        }
    }

    private static func runCoalescedReconnectTests(_ suite: TestSuite) {
        let devicesChanged = HAL.key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyDevices,
                                     scope: kAudioObjectPropertyScopeGlobal)
        let gain = HAL.key(10)
        for separateDisconnectNotice in [false, true] {
            HAL.reset()
            UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteFollowCallApps)
            HAL.levels[gain] = 0.625
            let service = MicMuteService.shared
            service.setMuted(true)
            DispatchQueue.drain()
            let original = HAL.listeners
            let inputListeners = original.filter { $0.d == 10 }
            HAL.listenerAdds = []
            HAL.listenerRemovals = []

            HAL.devices = []
            HAL.dropListeners(forDevice: 10)
            if separateDisconnectNotice { _ = HAL.notifyIfRegistered(devicesChanged) }
            HAL.devices = [10]
            HAL.levels[gain] = 0.8
            let ownPID = ProcessInfo.processInfo.processIdentifier
            HAL.processes = [(100, ownPID == 4242 ? 4243 : 4242, true, [10])]
            _ = HAL.notifyIfRegistered(devicesChanged)
            DispatchQueue.drain()
            suite.expect(service.isMuted && HAL.levels[gain] == 0 && HAL.listeners == original,
                         "a same-ID reconnect between inventory reads is silenced even while captured")
            suite.expect(Set(HAL.listenerAdds) == inputListeners && HAL.listenerAdds.count == inputListeners.count
                         && Set(HAL.listenerRemovals) == inputListeners && HAL.listenerRemovals.count == inputListeners.count,
                         "an ambiguous device list renews each input listener once and keeps the system listeners")

            HAL.processes = []
            HAL.levels[gain] = 0.8
            _ = HAL.notifyIfRegistered(gain)
            DispatchQueue.drain()
            suite.expect(HAL.levels[gain] == 0 && HAL.listenerAdds.count == inputListeners.count
                         && HAL.listenerRemovals.count == inputListeners.count,
                         "the first gain change after reconnect is caught without replacing listeners again")
            service.setMuted(false)
            DispatchQueue.drain()
            suite.expect(!service.isMuted && HAL.levels[gain] == 0.625 && HAL.listeners.isEmpty,
                         "explicit unmute restores the level from before the headset disconnected")
        }
    }

    private static func runPendingRestoreDeviceChangeTests(_ suite: TestSuite) {
        HAL.reset()
        let master = HAL.key(10)
        let left = HAL.key(10, 1)
        let other = HAL.key(20)
        let changed = HAL.key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyDevices,
                              scope: kAudioObjectPropertyScopeGlobal)
        HAL.devices = [10, 20]
        HAL.levels = [master: 0.625, left: 0.25, other: 0.75]
        let service = MicMuteService.shared
        service.setMuted(true)
        DispatchQueue.drain()
        HAL.levels[master] = nil
        service.setMuted(false)
        DispatchQueue.drain()
        suite.expect(!service.isMuted && service.hasOutstandingClaims && HAL.levels[left] == 0.25 && HAL.levels[other] == 0.75,
                     "unmute releases the independent input and channel while the missing master remains owed")
        HAL.levels[left] = 0.375
        HAL.levels[master] = 0
        HAL.beforeControlWrite = { key, target in
            if key == master { HAL.levels[left] = Float(target) }
        }
        HAL.writes = []
        HAL.readFails = [left]
        suite.expect(HAL.notifyIfRegistered(changed), "a pending restore still observes system device changes")
        DispatchQueue.drain()
        suite.expect(HAL.writes.isEmpty && service.hasOutstandingClaims,
                     "the returning master waits while the released channel cannot be read")
        HAL.readFails = []
        _ = HAL.notifyIfRegistered(changed)
        DispatchQueue.drain()
        suite.expect(HAL.writes == [master, left] && HAL.levels[master] == 0.625 && HAL.levels[left] == 0.375
                     && HAL.levels[other] == 0.75 && !service.hasOutstandingClaims && HAL.listeners.isEmpty,
                     "the system change restores the returning master without losing the user's latest channel mix")
    }

    private static func runRestoreRetryLimitTests(_ suite: TestSuite) {
        runMixerRestoreAdjustmentTests(suite)
        runInterruptedIntentTests(suite)
        runInterruptedReleaseTests(suite)
        runInterruptedFirstMuteTests(suite)
        runInterruptedMixerHandoffTests(suite)
        runRestoreReadRecoveryTests(suite)
        runLegacyMixerRestoreEditTests(suite)
        let master = HAL.key(10)
        let channel = HAL.key(10, 1)
        let other = HAL.key(20)
        let local = HAL.key(10, 0, kAudioObjectPropertyControlList, scope: kAudioObjectPropertyScopeGlobal)
        let system = HAL.key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyDevices,
                             scope: kAudioObjectPropertyScopeGlobal)
        let cases: [(permanent: Bool, events: [Key])] = [
            (false, []), (false, [local, system]),
            (true, []), (true, [local]), (true, [system]), (true, [local, system]),
        ]
        for (permanent, events) in cases {
            HAL.reset()
            var now: TimeInterval = 10
            let service = MicMuteService(uptime: { now })
            MicMuteService.shared = service
            HAL.devices = [10, 20]
            HAL.levels = [master: 0.625, other: 0.875]
            let paired = permanent && events.isEmpty
            if paired { HAL.levels[channel] = 0.25 }
            service.toggle()
            DispatchQueue.drain()
            var attempts = 0
            var delivered: Set<Key> = []
            HAL.writes = []
            HAL.beforeControlWrite = { key, target in
                if key == channel { HAL.ignoredWrites.insert(channel) }
                guard key == master, target == 0.625 else { return }
                attempts += 1
                if permanent || attempts == 1 { HAL.ignoredWrites.insert(master) }
                else { HAL.ignoredWrites.remove(master) }
                // A broken driver can echo every Set. Bound only the fake's
                // deliveries so a write loop on the old build fails by assertion.
                if attempts <= 4 {
                    for event in events where HAL.notifyIfRegistered(event) { delivered.insert(event) }
                }
            }
            func tick() {
                now += 2
                service.halQueue.runTimers()
                DispatchQueue.main.runTimers()
                DispatchQueue.drain()
            }
            service.toggle()
            DispatchQueue.drain()
            let context = "\(permanent ? "permanent" : "transient") refusal, events \(events.map { $0 == local ? "local" : "global" })"
            suite.expect(attempts == 1 && HAL.levels[master] == 0 && delivered == Set(events)
                         && !service.isMuted && !service.wantsMute && service.hasOutstandingClaims && service.warning == .restoreUnconfirmed,
                         "a refused restore waits for its retry without reentering from the driver: \(context)")
            for _ in 0..<4 { tick() }
            suite.expect(attempts == (permanent ? 3 : 2) && HAL.levels[master] == (permanent ? 0 : 0.625)
                         && (!paired || (HAL.writes.filter { $0 == channel }.count == 3 && HAL.levels[channel] == 0))
                         && HAL.levels[other] == 0.875 && HAL.writes.filter { $0 == other }.count == 1
                         && service.hasOutstandingClaims == permanent
                         && service.warning?.message == (permanent ? L10n.shared.s.micRestoreExhaustedHUD : nil),
                         "the clock restores a transient failure and bounds a permanent one per input: \(context)")
            let settled = HAL.writes
            for event in events { _ = HAL.notifyIfRegistered(event) }
            DispatchQueue.drain()
            for _ in 0..<4 { tick() }
            suite.expect(HAL.writes == settled && service.retryDeadline == nil,
                         "additional echoes and timer ticks leave the settled restore alone: \(context)")
            guard permanent else { continue }
            HAL.beforeControlWrite = nil
            HAL.ignoredWrites = []
            if events.count == 2 {
                suite.expect(HAL.restartAudioService(), "the pending input receives a real HAL restart")
                DispatchQueue.drain()
                suite.expect(HAL.levels == [master: 0.625, other: 0.875] && !service.hasOutstandingClaims
                             && service.warning == nil, "a real HAL restart can recover the previously exhausted input")
            } else {
                let mixer = AudioInputDeviceManager()
                mixer.start()
                DispatchQueue.drain()
                let manualGain = events == [system] ? 0.625 : 0.375
                mixer.setInputVolume(manualGain)
                DispatchQueue.drain()
                suite.expect(!service.hasOutstandingClaims && service.warning == .manualRestore,
                             "the accepted mixer edit hands the whole input to the user, even at its original target: \(context)")
                for event in events { _ = HAL.notifyIfRegistered(event) }
                DispatchQueue.drain()
                tick()
                suite.expect(service.inputVolumeAdjustmentLifetime != nil && mixer.inputVolume == manualGain
                             && HAL.levels[master] == Float(manualGain) && HAL.writes == settled + [master],
                             "the mixer permits manual gain adjustment after automatic recovery stops: \(context)")
                mixer.stop()
                HAL.relaunchClient()
                let restarted = MicMuteService.shared
                restarted.syncWithPreferences()
                DispatchQueue.drain()
                suite.expect(HAL.levels[master] == Float(manualGain) && !restarted.hasOutstandingClaims
                             && restarted.warning == .manualRestore && (!paired || HAL.levels[channel] == 0),
                             "relaunch preserves every channel on the manually adjusted input: \(context)")
                restarted.toggle()
                DispatchQueue.drain()
                restarted.toggle()
                DispatchQueue.drain()
                suite.expect(!restarted.isMuted && restarted.warning == .manualRestore && HAL.levels[master] == Float(manualGain),
                             "the next mute cycle restores the user's adjustment: \(context)")
            }
        }
    }

    private static func runRestoreReadRecoveryTests(_ suite: TestSuite) {
        enum Query { case gain, access, protectedChannelGain }
        let master = HAL.key(10)
        let channel = HAL.key(10, 1)
        let local = HAL.key(10, 0, kAudioObjectPropertyControlList, scope: kAudioObjectPropertyScopeGlobal)
        let system = HAL.key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyDevices,
                             scope: kAudioObjectPropertyScopeGlobal)
        var now: TimeInterval = 10
        func muted(_ levels: [Key: Float]) -> MicMuteService {
            HAL.reset()
            let service = MicMuteService(uptime: { now })
            MicMuteService.shared = service
            HAL.levels = levels
            service.toggle()
            DispatchQueue.drain()
            HAL.writes = []
            return service
        }
        func tick(_ service: MicMuteService) {
            now += 30
            service.halQueue.runTimers()
            DispatchQueue.main.runTimers()
            DispatchQueue.drain()
        }

        for (targets, protectsChannel) in [([master], false), ([channel], false), ([channel], true), ([master, channel], true)] {
            let channelIsOwed = targets == [channel] && !protectsChannel
            let service = muted(channelIsOwed ? [master: 0.625, channel: 0.25] : [master: 0.625])
            if channelIsOwed { HAL.levels[master] = nil }
            if protectsChannel { HAL.levels[channel] = 0.375 }
            HAL.settableReadFails = Set(targets)
            HAL.accessQueries = [:]
            service.toggle()
            DispatchQueue.drain()
            for attempt in 1...3 {
                suite.expect(targets.allSatisfy { HAL.accessQueries[$0] == attempt },
                             "each restore opportunity queries unknown access once per control")
                if let deadline = service.retryDeadline { now = deadline.nextDown }
                for event in [local, system, local] {
                    _ = HAL.notifyIfRegistered(event)
                    DispatchQueue.drain()
                }
                suite.expect(targets.allSatisfy { HAL.accessQueries[$0] == attempt } && HAL.writes.isEmpty,
                             "local and global echoes cannot spend another access query")
                tick(service)
            }
            suite.expect(targets.allSatisfy { HAL.accessQueries[$0] == 3 } && service.retryDeadline == nil && service.warning == .restoreExhausted,
                         "an exhausted access check has no further polling")
        }

        let laterChannel = HAL.key(10, 2)
        let waitingMaster = muted([master: 0.625])
        HAL.settableReadFails = [master, channel]
        HAL.accessQueries = [:]
        waitingMaster.toggle()
        DispatchQueue.drain()
        HAL.levels[channel] = 0.25
        HAL.levels[laterChannel] = 0.375
        for event in [local, system, local] {
            _ = HAL.notifyIfRegistered(event)
            DispatchQueue.drain()
        }
        suite.expect(HAL.accessQueries[master] == 1 && HAL.accessQueries[channel] == 1 && HAL.writes.isEmpty,
                     "a channel discovered during a master's access cooldown waits after its first failed check")
        HAL.levels[laterChannel] = nil
        HAL.settableReadFails = []
        tick(waitingMaster)
        suite.expect(HAL.writes.isEmpty && waitingMaster.hasOutstandingClaims,
                     "the master also waits for a writable channel discovered during another access cooldown")
        HAL.levels[laterChannel] = 0.375
        _ = HAL.notifyIfRegistered(local)
        DispatchQueue.drain()
        suite.expect(HAL.writes == [master] && HAL.levels[channel] == 0.25 && HAL.levels[laterChannel] == 0.375
                     && !waitingMaster.hasOutstandingClaims && waitingMaster.retryDeadline == nil,
                     "the master restores when it can protect both channels")

        for (query, recovers) in [(Query.gain, true), (.gain, false), (.access, true), (.access, false)] {
            let service = muted([master: 0.625])
            if query == .access { HAL.settableReadFails = [master] } else { HAL.readFails = [master] }
            service.toggle()
            DispatchQueue.drain()
            let firstDeadline = service.retryDeadline
            suite.expect(HAL.writes.isEmpty && firstDeadline != nil && service.hasOutstandingClaims && !service.isMuted,
                         "a failed initial \(query) query schedules a check without writing to the mic")
            if recovers {
                HAL.readFails = []
                HAL.settableReadFails = []
            } else {
                for _ in 0..<4 {
                    _ = HAL.notifyIfRegistered(local)
                    _ = HAL.notifyIfRegistered(system)
                    DispatchQueue.drain()
                }
                suite.expect(service.retryDeadline == firstDeadline && service.warning == .restoreUnconfirmed && HAL.writes.isEmpty,
                             "early echoes leave the first \(query) retry intact")
            }
            for _ in 0..<4 { tick(service) }
            suite.expect(HAL.writes == (recovers ? [master] : []) && HAL.levels[master] == (recovers ? 0.625 : 0)
                         && service.retryDeadline == nil && service.hasOutstandingClaims == !recovers
                         && service.warning == (recovers ? nil : .restoreExhausted) && service.inputVolumeAdjustmentLifetime != nil,
                         "recovery from the initial \(query) failure restores the saved gain or finishes with manual guidance")
            if !recovers {
                HAL.readFails = []
                HAL.settableReadFails = []
                _ = HAL.notifyIfRegistered(system)
                DispatchQueue.drain()
                suite.expect(HAL.writes.isEmpty && service.warning == .restoreExhausted && service.retryDeadline == nil,
                             "a global echo leaves a spent \(query) budget and the user's gain alone")
            }
        }

        for (absent, unknownAccess) in [(true, false), (false, false), (false, true)] {
            let service = muted([master: 0.625])
            if absent {
                HAL.levels[master] = nil
            } else {
                HAL.readOnly = [master]
                HAL.readFails = [master]
                if unknownAccess { HAL.settableReadFails = [master] }
            }
            service.toggle()
            DispatchQueue.drain()
            if unknownAccess {
                suite.expect(service.retryDeadline != nil && HAL.writes.isEmpty, "unknown access schedules only a check")
                HAL.settableReadFails = []
            }
            tick(service)
            suite.expect(HAL.writes.isEmpty && service.retryDeadline == nil && service.hasOutstandingClaims
                         && service.warning == .restoreUnconfirmed,
                         "a missing or read-only property waits for topology without a timed restore")
            HAL.levels[master] = 0
            HAL.readOnly = []
            HAL.readFails = []
            _ = HAL.notifyIfRegistered(local)
            DispatchQueue.drain()
            suite.expect(HAL.writes == [master] && HAL.levels[master] == 0.625 && !service.hasOutstandingClaims,
                         "the pending control restores when it becomes available and writable")
        }

        for (query, persistent) in [(Query.gain, false), (.gain, true), (.protectedChannelGain, false), (.access, false)] {
            let protectChannel = query == .protectedChannelGain
            let service = muted(protectChannel ? [master: 0.625, channel: 0.875] : [master: 0.625])
            HAL.ignoredWrites = [master]
            service.toggle()
            DispatchQueue.drain()
            let initialWrites = protectChannel ? [master, channel] : [master]
            suite.expect(HAL.writes == initialWrites && service.retryDeadline != nil && !service.isMuted,
                         "the first refused restore schedules a second opportunity")
            HAL.ignoredWrites = []
            if protectChannel {
                // The first release restored this channel. A later master Set moves it.
                HAL.levels[channel] = 0.375
                HAL.beforeControlWrite = { key, target in if key == master { HAL.levels[channel] = Float(target) } }
            }
            if query == .access { HAL.settableReadFails = [master] }
            else if persistent { HAL.readFails = [master] }
            else { HAL.nextReadFails = [protectChannel ? channel : master] }
            tick(service)
            suite.expect(HAL.nextReadFails.isEmpty && HAL.writes == initialWrites && service.hasOutstandingClaims
                         && service.retryDeadline != nil,
                         "a failed gain or access query gets another timed check without a blind Set")
            HAL.settableReadFails = []
            for _ in 0..<5 { tick(service) }
            if persistent {
                suite.expect(HAL.levels[master] == 0 && HAL.writes == [master] && service.hasOutstandingClaims
                             && service.retryDeadline == nil && service.warning == .restoreExhausted
                             && service.inputVolumeAdjustmentLifetime != nil,
                             "a permanently unreadable retry stops with a manual warning and the mixer available")
                _ = HAL.notifyIfRegistered(local)
                _ = HAL.notifyIfRegistered(system)
                DispatchQueue.drain()
                tick(service)
                suite.expect(HAL.writes == [master] && service.retryDeadline == nil && service.warning == .restoreExhausted,
                             "echoes do not restart the clock for an exhausted unreadable control")
            } else {
                suite.expect(HAL.levels[master] == 0.625 && HAL.writes == initialWrites + initialWrites
                             && HAL.levels[channel] == (protectChannel ? 0.375 : nil) && service.retryDeadline == nil
                             && !service.hasOutstandingClaims && service.warning == nil,
                             "the next clock check restores a transient read failure without a hardware event")
            }
        }

        for acceptCompensation in [true, false] {
            let service = muted([master: 0.625, channel: 0.25])
            HAL.levels[master] = nil
            HAL.ignoredWrites = [channel]
            service.toggle()
            DispatchQueue.drain()
            for _ in 0..<4 { tick(service) }
            suite.expect(HAL.writes == [channel, channel, channel] && service.warning == .restoreExhausted
                         && service.retryDeadline == nil, "the channel is already exhausted while its master is absent")

            HAL.readFails = [channel]
            HAL.levels[master] = 0
            HAL.writes = []
            HAL.beforeControlWrite = { key, target in
                guard key == master else { return }
                // The pending channel cannot be read until the master Set moves it.
                HAL.levels[channel] = Float(target)
                HAL.readFails.remove(channel)
                if acceptCompensation { HAL.ignoredWrites.remove(channel) }
            }
            _ = HAL.notifyIfRegistered(local)
            DispatchQueue.drain()
            suite.expect(HAL.writes == [master, channel] && HAL.levels[master] == 0.625
                         && HAL.levels[channel] == (acceptCompensation ? 0.25 : 0.625),
                         "the submitted master can compensate a previously unreadable exhausted channel")
            for _ in 0..<6 {
                _ = HAL.notifyIfRegistered(local)
                _ = HAL.notifyIfRegistered(system)
                DispatchQueue.drain()
                tick(service)
            }
            let settled = HAL.writes
            _ = HAL.notifyIfRegistered(local)
            _ = HAL.notifyIfRegistered(system)
            DispatchQueue.drain()
            tick(service)
            suite.expect(HAL.writes == settled && settled.filter { $0 == master }.count == 1
                         && (1...3).contains(settled.filter { $0 == channel }.count)
                         && service.retryDeadline == nil && service.hasOutstandingClaims == !acceptCompensation
                         && service.warning == (acceptCompensation ? nil : .restoreExhausted),
                         "echoes of the master and channel do not renew the compensation budget")
        }
    }

    private static func runLegacyMixerRestoreEditTests(_ suite: TestSuite) {
        let master = HAL.key(10)
        let channel = HAL.key(10, 1)
        let virtual = HAL.key(10, 0, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        let uid = "device-10"
        for bareElement in [false, true] {
            HAL.reset()
            let slider = bareElement ? virtual : master
            HAL.levels = [slider: 0, channel: 0.25]
            UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteActive)
            UserDefaults.standard.set([uid], forKey: DefaultsKey.micMuteMutedDevices)
            UserDefaults.standard.set([uid: 0.625], forKey: DefaultsKey.micMuteSavedVolumes)
            if bareElement {
                UserDefaults.standard.set([uid: ["0": 0.625]], forKey: DefaultsKey.micMuteSavedControls)
            } else {
                HAL.readFails = [channel]
            }
            HAL.relaunchClient()
            MicMuteService.shared.toggle()
            DispatchQueue.drain()
            let mixer = AudioInputDeviceManager()
            mixer.start()
            DispatchQueue.drain()
            mixer.setInputVolume(0.375)
            DispatchQueue.drain()
            suite.expect(HAL.writes == [slider] && HAL.levels[slider] == 0.375,
                         "the available master accepts a manual edit after the unidentified gain is retired")
            mixer.stop()
            HAL.writes = []
            HAL.readFails = []
            if bareElement {
                // The scalar master returns as an alias of the virtual master.
                HAL.levels[master] = HAL.levels[virtual]
                HAL.beforeControlWrite = { key, target in if key == master { HAL.levels[virtual] = Float(target) } }
            }
            HAL.relaunchClient()
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            suite.expect(HAL.writes.isEmpty && HAL.levels[slider] == 0.375 && HAL.levels[channel] == 0.25
                         && !MicMuteService.shared.hasOutstandingClaims && MicMuteService.shared.warning == .manualRestore,
                         "a later legacy \(bareElement ? "element 0" : "UID gain") cannot undo the accepted mixer edit")
        }
    }

    private struct Checkpoint {
        let name: String
        let preferences = UserDefaults.standard.values
        let devices = HAL.devices
        let streamChannels = HAL.streamChannels
        let levels = HAL.levels
        let minimumGain = HAL.minimumGain
        let switches = HAL.mute

        func reopen(with gains: [Key: Float] = [:], switches changedSwitches: [UInt32: UInt32] = [:]) {
            HAL.reset()
            UserDefaults.standard.values = preferences
            HAL.devices = devices
            HAL.streamChannels = streamChannels
            HAL.levels = levels.merging(gains) { _, edited in edited }
            HAL.minimumGain = minimumGain
            HAL.mute = switches.merging(changedSwitches) { _, edited in edited }
            HAL.relaunchClient()
        }
    }

    private static func hasPendingControlWrite(_ uid: String, in preferences: [String: Any]) -> Bool {
        let controls = preferences[DefaultsKey.micMuteSavedControls] as? [String: Any]
        return controls?[uid] as? String == "changing" || preferences[DefaultsKey.micMuteMixerHandoffUID] as? String == uid
    }

    private static func runInterruptedIntentTests(_ suite: TestSuite) {
        let master = HAL.key(10), muteSwitch = HAL.key(10, 0, kAudioDevicePropertyMute), peer = HAL.key(20)
        let original: [Key: Float] = [master: 0.625, peer: 0.875]
        let edited: [Key: Float] = [master: 0.375, peer: 0.875]
        let silent: [Key: Float] = [master: 0, peer: 0]
        let defaults = UserDefaults.standard
        enum Reversal { case betweenControls, preference, call, callConfirmation, callPublication }
        for (lastMute, trigger) in [(true, Reversal.betweenControls), (false, .betweenControls),
                                    (true, .preference), (false, .preference), (true, .call),
                                    (true, .callConfirmation), (true, .callPublication)] {
            HAL.reset()
            HAL.devices = [10, 20]
            HAL.levels = original
            HAL.mute[10] = 0
            let call = trigger == .call || trigger == .callConfirmation || trigger == .callPublication
            if call { defaults.set(true, forKey: DefaultsKey.micMuteFollowCallApps) }
            let userRemuted = lastMute && trigger != .preference
            let releasedLevels = lastMute && trigger == .preference ? original : edited
            let service = MicMuteService.shared
            service.toggle()
            DispatchQueue.drain()
            if !lastMute {
                // B still owes its original gain when a fresh mute starts on A.
                HAL.writeFails = [peer]
                service.toggle()
                DispatchQueue.drain()
                HAL.writeFails = []
                HAL.levels[master] = edited[master]
            }
            var reversed = false
            var cuts: [Checkpoint] = []
            func capture(_ name: String) {
                if reversed { cuts.append(Checkpoint(name: name)) }
            }
            func reverse() {
                reversed = true
                service.toggle()
                capture("new command returned")
            }
            func reverseBeforeB() {
                guard HAL.mute[10] == 0 && HAL.levels[master] == original[master] else {
                    HAL.afterSettableCheck[peer] = reverseBeforeB
                    return
                }
                // A was released. The user changed it before B's setter was submitted.
                HAL.levels[master] = edited[master]
                HAL.mute[10] = 1
                reverse()
            }
            if userRemuted && (trigger == .betweenControls || trigger == .call) { HAL.afterSettableCheck[peer] = reverseBeforeB }
            let publication = service.$isMuted.dropFirst().sink { muted in
                if trigger == .callPublication && !muted && !reversed {
                    HAL.levels[master] = edited[master]
                    HAL.mute[10] = 1
                    reverse()
                }
            }
            defaults.afterChange = { key in
                let observesCommand = trigger == .preference && key == DefaultsKey.micMuteReleasePending
                if !reversed && (observesCommand || trigger == .callConfirmation) {
                    // A synchronous observer may issue a newer command before the superseded one queues its HAL sweep.
                    if service.inputVolumeLock.try() {
                        service.inputVolumeLock.unlock()
                        if observesCommand { reverse() }
                        else if service.isMuted && service.inputVolumeAdjustmentLifetime != nil {
                            HAL.levels[master] = edited[master]
                            HAL.mute[10] = 1
                            reverse()
                        }
                    }
                }
                capture("preference \(key)")
            }
            HAL.beforeControlWrite = { key, value in
                if trigger == .betweenControls && !reversed && !lastMute && key == master && value == 0 { reverse() }
                capture("entry to Set \(key.d)/\(key.s)")
            }
            HAL.afterControlWrite = { key in capture("return from Set \(key.d)/\(key.s)") }
            if call {
                let caller: Int32 = ProcessInfo.processInfo.processIdentifier == 4242 ? 4243 : 4242
                HAL.processes = [(100, caller, true, [10])]
                HAL.mute[10] = 0
                HAL.levels[master] = 0.5
                suite.expect(HAL.notifyIfRegistered(master), "the recording app reports its opening before the new shortcut")
            } else { service.toggle() }
            DispatchQueue.drain()
            publication.cancel()
            defaults.afterChange = nil
            HAL.beforeControlWrite = nil
            HAL.afterControlWrite = nil
            suite.expect(reversed && !cuts.isEmpty && service.isMuted == lastMute && HAL.levels == (lastMute ? silent : releasedLevels)
                         && HAL.mute[10] == (lastMute ? 1 : 0),
                         "the most recent explicit command completes without interruption (mute: \(lastMute), \(trigger))")
            for point in cuts {
                // A release that stopped inside a setter must leave that UID for the user to check.
                let uncertainA = !lastMute && hasPendingControlWrite("device-10", in: point.preferences)
                let uncertainB = !lastMute && hasPendingControlWrite("device-20", in: point.preferences)
                var expected = releasedLevels
                if uncertainA { expected[master] = point.levels[master] }
                if uncertainB { expected[peer] = point.levels[peer] }
                let finalSwitch: UInt32? = uncertainA ? point.switches[10] : (userRemuted ? 1 : 0)
                point.reopen()
                var oppositeWrite = false
                HAL.beforeControlWrite = { key, value in
                    let closes = key == muteSwitch ? value == 1 : value == 0
                    if closes != lastMute { oppositeWrite = true }
                }
                let resumed = MicMuteService.shared
                resumed.syncWithPreferences()
                DispatchQueue.drain()
                let touchedUncertain = HAL.writes.contains { ($0.d == 10 && uncertainA) || ($0.d == 20 && uncertainB) }
                suite.expect(!oppositeWrite && !touchedUncertain && resumed.isMuted == lastMute
                             && HAL.levels == (lastMute ? silent : expected) && HAL.mute[10] == (lastMute ? 1 : finalSwitch)
                             && (!(uncertainA || uncertainB) || resumed.warning == .manualRestore),
                             "reopening at \(point.name) honors the newest command and every proven gain (mute: \(lastMute), \(trigger))")
                HAL.beforeControlWrite = nil
                resumed.toggle()
                DispatchQueue.drain()
                if !lastMute {
                    resumed.toggle()
                    DispatchQueue.drain()
                }
                suite.expect(!resumed.isMuted && !resumed.hasOutstandingClaims && HAL.levels == expected && HAL.mute[10] == finalSwitch,
                             "the next explicit cycle preserves the recovered mix after \(point.name) (mute: \(lastMute), \(trigger))")
            }
        }

        HAL.reset()
        HAL.devices = [10, 20]
        HAL.levels = original
        HAL.mute[10] = 0
        let service = MicMuteService.shared
        service.toggle()
        DispatchQueue.drain()
        HAL.writeFails = [master]
        var cuts: [(point: Checkpoint, pastA: Bool, setter: Key?)] = []
        var atPeer = false
        func capture(_ name: String, setter: Key? = nil) { cuts.append((Checkpoint(name: name), atPeer, setter)) }
        func beforePeerAccess() {
            guard HAL.mute[10] == 0 else {
                HAL.afterSettableCheck[peer] = beforePeerAccess
                return
            }
            atPeer = true
            capture("B's access check after A's switch was released")
        }
        HAL.afterSettableCheck[peer] = beforePeerAccess
        defaults.afterChange = { capture("partial release preference \($0)") }
        HAL.beforeControlWrite = { key, _ in
            capture("entry to partial release Set \(key.d)/\(key.s)", setter: key)
        }
        HAL.afterControlWrite = { key in capture("return from partial release Set \(key.d)/\(key.s)", setter: key) }
        service.toggle()
        DispatchQueue.drain()
        defaults.afterChange = nil
        HAL.beforeControlWrite = nil
        HAL.afterControlWrite = nil
        suite.expect(atPeer && cuts.contains { $0.setter == peer } && HAL.levels == [master: 0, peer: 0.875] && HAL.mute[10] == 0
                     && service.hasOutstandingClaims && service.warning == .restoreUnconfirmed,
                     "uninterrupted release opens A's switch and restores B while A's refused master remains owed")
        for (point, pastA, setter) in cuts {
            let inPeerSet = setter == peer || hasPendingControlWrite("device-20", in: point.preferences)
            let inASet = !pastA && (setter?.d == 10 || hasPendingControlWrite("device-10", in: point.preferences))
            let remuted = point.switches[10] == 0
            // The same persisted record covers both sides of a HAL call. During B's call the user chose zero on B.
            point.reopen(with: inPeerSet ? [peer: 0] : [:], switches: remuted ? [10: 1] : [:])
            let resumed = MicMuteService.shared
            resumed.syncWithPreferences()
            DispatchQueue.drain()
            let manual = resumed.warning == .manualRestore
            let preservesSwitch = remuted ? HAL.mute[10] == 1 && !HAL.writes.contains(muteSwitch) : HAL.mute[10] == 0 || (inASet && manual)
            let recoversPeer = inPeerSet ? HAL.levels[peer] == 0 && !HAL.writes.contains(peer) && manual : HAL.levels[peer] == 0.875
            suite.expect(preservesSwitch && recoversPeer && (HAL.levels[master] == 0.625 || (inASet && manual))
                         && !resumed.isMuted && !resumed.hasOutstandingClaims,
                         "partial release preserves the user's switch and restores the other proven controls after \(point.name)")
            if remuted && !inPeerSet && (inASet || pastA) {
                // An edit on uncertain A supplies a new gain; after A was verified its refused master still owes 0.625.
                point.reopen(with: inASet ? [master: 0.375] : [:], switches: [10: 1])
                let newMute = MicMuteService.shared
                newMute.setMuted(true)
                DispatchQueue.drain()
                suite.expect(newMute.isMuted && HAL.mute[10] == 1 && HAL.levels == silent,
                             "a new mute closes the partially released inputs after \(point.name)")
                newMute.toggle()
                DispatchQueue.drain()
                suite.expect(!newMute.isMuted && !newMute.hasOutstandingClaims && HAL.mute[10] == 1
                             && HAL.levels == (inASet ? edited : original),
                             "the new mute preserves the physical switch and every known level after \(point.name)")
            }
        }
        runUnverifiedReleaseCheckpointTests(suite)
        runAcceptedIntentEquivalenceTests(suite)
    }

    private static func runAcceptedIntentEquivalenceTests(_ suite: TestSuite) {
        enum Action { case refusedMute, retryAtRefusal, acceptCall, muteAfterCall }
        struct Result: Equatable {
            let muted: Bool, mixerEditable: Bool, hasClaims: Bool
            let gains: [Key: Float]
        }
        let a = HAL.key(10), b = HAL.key(20)
        let devicesChanged = HAL.key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyDevices,
                                     scope: kAudioObjectPropertyScopeGlobal)
        for action in [Action.refusedMute, .retryAtRefusal, .acceptCall, .muteAfterCall] {
            let call = action == .acceptCall || action == .muteAfterCall
            let lastMute = action == .retryAtRefusal || action == .muteAfterCall
            var uninterrupted: Result?
            for relaunch in [false, true] {
                HAL.reset()
                HAL.devices = [10, 20]
                HAL.levels = [a: 0.625, b: 0.875]
                UserDefaults.standard.set(call, forKey: DefaultsKey.micMuteFollowCallApps)
                var service = MicMuteService.shared
                service.toggle()
                DispatchQueue.drain()
                HAL.devices = [10] // B will return after the decision, still owing 0.875.
                if call {
                    let caller: Int32 = ProcessInfo.processInfo.processIdentifier == 4242 ? 4243 : 4242
                    HAL.processes = [(100, caller, true, [10])]
                    HAL.levels[a] = 0.5
                    suite.expect(HAL.notifyIfRegistered(a), "the recording app opens the registered input")
                    DispatchQueue.main.run()
                    service.halQueue.sync {}
                    suite.expect(service.isMuted && HAL.levels[a] == 0.625,
                                 "the HAL accepted the call opening while the preceding mute is still published")
                    if action == .muteAfterCall { service.toggle() }
                } else {
                    service.toggle()
                    DispatchQueue.drain()
                    HAL.writeFails = [a]
                    HAL.writes = []
                    var retried = false
                    UserDefaults.standard.afterChange = { _ in
                        guard action == .retryAtRefusal && !retried && HAL.writes.contains(a),
                              service.inputVolumeLock.try() else { return }
                        service.inputVolumeLock.unlock()
                        guard service.inputVolumeAdjustmentLifetime != nil else { return }
                        retried = true
                        HAL.writeFails = []
                        service.toggle()
                    }
                    service.toggle()
                    DispatchQueue.drain()
                    UserDefaults.standard.afterChange = nil
                    suite.expect(HAL.writes.contains(a) && retried == lastMute && service.isMuted == lastMute,
                                 "a wholly refused mute returns to release until the user presses the button again")
                    HAL.writeFails = []
                }
                if relaunch {
                    // An interrupted process cannot publish its old completion in the new process.
                    service.halQueue.work.removeAll()
                    DispatchQueue.main.work.removeAll()
                    Checkpoint(name: "last accepted action").reopen()
                    service = MicMuteService.shared
                    service.syncWithPreferences()
                }
                DispatchQueue.drain()
                let mixer = AudioInputDeviceManager()
                mixer.start()
                DispatchQueue.drain()
                HAL.writes = []
                mixer.setInputVolume(0.375)
                DispatchQueue.drain()
                suite.expect(HAL.writes == (lastMute ? [] : [a]) && HAL.levels[a] == (lastMute ? 0 : 0.375),
                             "A accepts a mixer adjustment only in the accepted release (\(action), relaunch: \(relaunch))")
                mixer.stop()
                HAL.devices = [10, 20]
                suite.expect(HAL.notifyIfRegistered(devicesChanged), "the service observes B's return")
                DispatchQueue.drain()
                let result = Result(muted: service.isMuted, mixerEditable: service.inputVolumeAdjustmentLifetime != nil,
                                    hasClaims: service.hasOutstandingClaims, gains: HAL.levels)
                let expected = Result(muted: lastMute, mixerEditable: !lastMute, hasClaims: lastMute,
                                      gains: lastMute ? [a: 0, b: 0] : [a: 0.375, b: 0.875])
                suite.expect(result == expected && (uninterrupted == nil || result == uninterrupted),
                             "continuous and relaunched inputs honor the same accepted action (\(action), relaunch: \(relaunch))")
                uninterrupted = result
            }
        }
    }

    private static func runUnverifiedReleaseCheckpointTests(_ suite: TestSuite) {
        let gain = HAL.key(10), native = HAL.key(10, 0, kAudioDevicePropertyMute), peer = HAL.key(20)
        let devicesChanged = HAL.key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyDevices,
                                     scope: kAudioObjectPropertyScopeGlobal)
        let defaults = UserDefaults.standard
        for (control, replacesUID) in [(native, false), (gain, false), (native, true)] {
            HAL.reset()
            HAL.devices = [10, 20]
            HAL.levels = [peer: 0.875]
            let independentMaster = control == native && !replacesUID
            if control == gain || independentMaster { HAL.levels[gain] = 0.625 }
            if control == native { HAL.mute[10] = 0 }
            var now: TimeInterval = 10
            let service = MicMuteService(uptime: { now })
            MicMuteService.shared = service
            service.toggle()
            DispatchQueue.drain()
            if control == gain { HAL.ignoredWrites = [gain] }
            if independentMaster { HAL.writeFails = [gain] }
            var cuts: [(point: Checkpoint, afterVerification: Bool)] = []
            HAL.afterControlWrite = { key in
                guard key == control else { return }
                if replacesUID { HAL.uids[10] = "replacement" } else { HAL.readFails.insert(key) }
                cuts.append((Checkpoint(name: "A's Set before readback"), false))
            }
            defaults.afterChange = { key in
                if !cuts.isEmpty && key == DefaultsKey.micMuteSavedControls
                    && !hasPendingControlWrite("device-20", in: defaults.values) {
                    cuts.append((Checkpoint(name: HAL.levels[peer] == 0 ? "A's record before B" : "record after B's release"), true))
                }
            }
            service.toggle()
            DispatchQueue.drain()
            defaults.afterChange = nil
            HAL.afterControlWrite = nil
            suite.expect(!cuts.isEmpty && service.hasOutstandingClaims, "A's submitted release could not be verified")
            cuts.append((Checkpoint(name: "completed release sweep"), true))

            HAL.readFails = []
            HAL.ignoredWrites = []
            HAL.writeFails = []
            HAL.uids[10] = nil
            HAL.writes = []
            now += 30
            _ = HAL.notifyIfRegistered(devicesChanged)
            service.halQueue.runTimers()
            DispatchQueue.drain()
            suite.expect(!service.hasOutstandingClaims && service.warning == nil && HAL.levels[peer] == 0.875
                         && (replacesUID ? HAL.writes.isEmpty : HAL.writes == [gain] && HAL.levels[gain] == 0.625)
                         && (control != native || HAL.mute[10] == 0),
                         "the running process verifies the returning control or retries the ignored gain")

            for (cut, afterVerification) in cuts {
                cut.reopen(with: control == gain ? [gain: 0] : [:], switches: control == native ? [10: 1] : [:])
                let resumed = MicMuteService.shared
                resumed.syncWithPreferences()
                DispatchQueue.drain()
                var expectedWrites: [Key] = []
                if independentMaster && HAL.levels[gain] == 0.625 { expectedWrites.append(gain) }
                if cut.levels[peer] == 0 { expectedWrites.append(peer) }
                suite.expect(HAL.writes == expectedWrites && HAL.levels[peer] == 0.875
                             && (!independentMaster || HAL.levels[gain] == 0.625 || (!afterVerification && HAL.levels[gain] == 0))
                             && (control == gain ? HAL.levels[gain] == 0 : HAL.mute[10] == 1)
                             && resumed.warning == .manualRestore && !resumed.hasOutstandingClaims,
                             "relaunch preserves A's manual mute and restores B at \(cut.name) (\(control.s), UID replaced: \(replacesUID))")
            }
        }
    }

    private static func runInterruptedReleaseTests(_ suite: TestSuite) {
        let master = HAL.key(10), channel = HAL.key(10, 1), peer = HAL.key(20)
        let muteSwitch = HAL.key(10, 0, kAudioDevicePropertyMute)
        let devicesChanged = HAL.key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyDevices,
                                     scope: kAudioObjectPropertyScopeGlobal)
        enum Release { case bothPresent, alreadyRestored, peerAbsent, switchOnly, followCall, masterOnly, channelOnly }
        let mixed: Set<Key> = [master, channel, muteSwitch]
        let modes: [(Release, Set<Key>)] = [(.bothPresent, mixed), (.alreadyRestored, mixed), (.peerAbsent, mixed),
                                            (.switchOnly, [muteSwitch]), (.followCall, [muteSwitch]),
                                            (.masterOnly, [master]), (.channelOnly, [channel])]
        let gains: [Key: Float] = [master: 0.625, channel: 0.25, peer: 0.875]
        for (mode, controls) in modes {
            HAL.reset()
            let original = gains.filter { $0.key == peer || controls.contains($0.key) }
            let silenced = original.filter { $0.key.d == 10 }.mapValues { _ in Float(0) }
            let remuted: [UInt32: UInt32] = controls.contains(muteSwitch) ? [10: 1] : [:]
            if mode == .followCall { UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteFollowCallApps) }
            HAL.devices = [10, 20]
            HAL.levels = original
            if mode == .channelOnly { HAL.streamChannels[10] = [1] }
            HAL.mute = remuted.mapValues { _ in 0 }
            let service = MicMuteService.shared
            service.toggle()
            DispatchQueue.drain()
            if mode == .peerAbsent { HAL.devices = [10] }
            if mode == .alreadyRestored {
                HAL.levels[master] = original[master]
                HAL.levels[channel] = original[channel]
                HAL.mute[10] = 0
            }
            var verified: Set<Key> = []
            func watchRead(_ key: Key) {
                let didRead = {
                    if key == muteSwitch ? HAL.mute[10] == 0 : HAL.levels[key] == original[key] {
                        verified.insert(key)
                    } else { watchRead(key) }
                }
                if key == muteSwitch { HAL.afterSwitchRead[key] = didRead }
                else { HAL.afterGainRead[key] = didRead }
            }
            for key in controls { watchRead(key) }
            var cuts: [(point: Checkpoint, insidePeerSet: Bool)] = []
            var releaseIntent: Checkpoint?
            var sawVerifiedCall = false
            if mode == .followCall {
                func beforeB() {
                    guard verified == controls else {
                        HAL.afterSettableCheck[peer] = beforeB
                        return
                    }
                    sawVerifiedCall = true
                    cuts.append((Checkpoint(name: "A was verified before B's Set or any main publication"), false))
                }
                HAL.afterSettableCheck[peer] = beforeB
            }
            UserDefaults.standard.afterChange = { key in
                guard verified == controls else {
                    if key == DefaultsKey.micMuteReleasePending && releaseIntent == nil {
                        releaseIntent = Checkpoint(name: "release requested before verification")
                    }
                    return
                }
                cuts.append((Checkpoint(name: "release preference \(key)"), false))
                if mode != .followCall {
                    // A recursive lock attempt would hang the test before the observer could report it.
                    let available = service.inputVolumeLock.try()
                    if available { service.inputVolumeLock.unlock() }
                    suite.expect(available && service.inputVolumeAdjustmentLifetime != nil,
                                 "a synchronous preference observer can query the editable mixer at \(key)")
                }
            }
            HAL.beforeControlWrite = { key, _ in
                if key == peer {
                    suite.expect(verified == controls, "A's restored controls have been read before the release reaches B")
                    cuts.append((Checkpoint(name: "entry to B's setter"), true))
                }
            }
            HAL.afterControlWrite = { key in
                if key == peer { cuts.append((Checkpoint(name: "return from B's setter"), true)) }
            }
            HAL.writes = []
            if mode == .followCall {
                let caller: Int32 = ProcessInfo.processInfo.processIdentifier == 4242 ? 4243 : 4242
                HAL.processes = [(100, caller, true, [20])]
                HAL.levels[peer] = 0.375
                suite.expect(HAL.notifyIfRegistered(peer), "a recording app opens B through its registered gain listener")
            } else { service.toggle() }
            DispatchQueue.drain()
            UserDefaults.standard.afterChange = nil
            HAL.beforeControlWrite = nil
            HAL.afterControlWrite = nil
            let writesToA = HAL.writes.filter { $0.d == 10 }
            let expectedControls = mode == .alreadyRestored ? Set<Key>() : controls
            suite.expect(verified == controls && !cuts.isEmpty && (mode == .followCall ? sawVerifiedCall : releaseIntent != nil)
                         && Set(writesToA) == expectedControls
                         && writesToA.count == expectedControls.count
                         && HAL.levels[master] == original[master] && HAL.levels[channel] == original[channel]
                         && HAL.mute[10] == (controls.contains(muteSwitch) ? 0 : nil)
                         && HAL.levels[peer] == (mode == .peerAbsent ? 0 : original[peer]) && !service.isMuted
                         && UserDefaults.standard.object(forKey: DefaultsKey.micMuteReleasedUIDs) == nil
                         && service.hasOutstandingClaims == (mode == .peerAbsent) && (mode == .peerAbsent || service.warning == nil),
                         "normal release verifies every control and only the missing peer stays owed (\(mode))")
            if let releaseIntent {
                let writes = HAL.writes, levels = HAL.levels, switches = HAL.mute
                releaseIntent.reopen()
                let resumed = MicMuteService.shared
                resumed.syncWithPreferences()
                DispatchQueue.drain()
                suite.expect(HAL.writes == writes && HAL.levels == levels && HAL.mute == switches
                             && !resumed.isMuted && resumed.hasOutstandingClaims == (mode == .peerAbsent),
                             "relaunch at the release intent completes the inputs that were still owed (\(mode))")
            }
            for (point, insidePeerSet) in cuts {
                // After release the user silences A again, before the next launch.
                let inPeerSet = insidePeerSet || hasPendingControlWrite("device-20", in: point.preferences)
                var edited = silenced
                if inPeerSet { edited[peer] = 0 }
                point.reopen(with: edited, switches: remuted)
                let relaunched = MicMuteService.shared
                relaunched.syncWithPreferences()
                DispatchQueue.drain()
                if mode == .peerAbsent {
                    suite.expect(HAL.writes.isEmpty && relaunched.hasOutstandingClaims,
                                 "only the disconnected peer waits following interruption at \(point.name)")
                    HAL.devices = [10, 20]
                    _ = HAL.notifyIfRegistered(devicesChanged)
                    DispatchQueue.drain()
                }
                let expectedWrites: [Key] = inPeerSet || point.levels[peer] == original[peer] ? [] : [peer]
                var expected = silenced
                expected[peer] = inPeerSet ? 0 : original[peer]
                suite.expect(HAL.writes == expectedWrites && HAL.levels == expected
                             && UserDefaults.standard.object(forKey: DefaultsKey.micMuteReleasedUIDs) == nil
                             && HAL.mute == remuted && !relaunched.isMuted && !relaunched.hasOutstandingClaims
                             && relaunched.warning == (inPeerSet ? .manualRestore : nil),
                             "relaunch preserves the user's re-mute and completes B following interruption at \(point.name) (\(mode))")
            }
        }
    }

    private static func runInterruptedFirstMuteTests(_ suite: TestSuite) {
        let defaults = UserDefaults.standard
        let gain = HAL.key(10), peer = HAL.key(20)
        let original: Float = 0.625, edited: Float = 0.375
        let gainUID = "device-10", peerUID = "device-20"
        let peerSwitch = HAL.key(20, 0, kAudioDevicePropertyMute)
        for floor: Float in [0, 0.005] {
            HAL.reset()
            HAL.devices = [10, 20]
            HAL.levels = [gain: original, peer: 0.875]
            HAL.minimumGain[gain] = floor
            HAL.mute[20] = 0
            var returned: Set<String> = []
            var cuts: [(point: Checkpoint, returned: Set<String>, editAfterCommit: Bool)] = []
            func capture(_ name: String, editAfterCommit: Bool = false) {
                cuts.append((Checkpoint(name: name), returned, editAfterCommit))
            }
            capture("before first mute")
            defaults.afterChange = { capture("first mute preference \($0)") }
            HAL.beforeControlWrite = { key, _ in
                let uid = "device-\(key.d)"
                if !returned.contains(uid) {
                    let snapshot = defaults.dictionary(forKey: DefaultsKey.micMuteSavedControls)?[uid] as? [String: Double]
                    suite.expect(snapshot?["\(key.s):\(key.e)"] != nil,
                                 "the first HAL setter already has its original control in the prepared snapshot")
                }
                capture("before Set \(key.d)/\(key.s):\(key.e)", editAfterCommit: key == peerSwitch)
            }
            HAL.afterControlWrite = { key in
                // At this checkpoint the driver changed the hardware but hasn't returned a status.
                capture("before Set returns \(key.d)/\(key.s):\(key.e)")
                returned.insert("device-\(key.d)")
            }
            MicMuteService.shared.toggle()
            DispatchQueue.drain()
            defaults.afterChange = nil
            HAL.beforeControlWrite = nil
            HAL.afterControlWrite = nil
            suite.expect(returned == [gainUID, peerUID] && HAL.levels[gain] == floor && HAL.levels[peer] == 0
                         && HAL.mute[20] == 1 && MicMuteService.shared.isMuted,
                         "the first mute writes both inputs before its completed checkpoint")
            capture("after first mute completed", editAfterCommit: true)
            for (point, returned, editAfterCommit) in cuts {
                let snapshots = point.preferences[DefaultsKey.micMuteSavedControls] as? [String: [String: Double]] ?? [:]
                let owners = point.preferences[DefaultsKey.micMuteMutedDevices] as? [String] ?? []
                let committed = returned.intersection(owners)
                let uncertain = Set(snapshots.keys).subtracting(committed)
                let edits: [Float?]
                if uncertain.contains(gainUID) { edits = [nil, 0, 0.005, edited] }
                else if editAfterCommit || !returned.contains(gainUID) { edits = [nil, edited] }
                else { edits = [nil] }
                for edit in edits {
                    let changes = edit.map { [gain: $0] } ?? [:]
                    var expected = point.levels.merging(changes) { _, new in new }
                    if committed.contains(gainUID) { expected[gain] = original }
                    if committed.contains(peerUID) { expected[peer] = 0.875 }
                    let expectedSwitch = committed.contains(peerUID) ? 0 : point.switches[20]
                    for syncFirst in [false, true] {
                        point.reopen(with: changes)
                        var openedStaleControl = false
                        HAL.beforeControlWrite = { key, target in
                            if key == gain && expected[gain] != original && target == Double(original) { openedStaleControl = true }
                            if key == peerSwitch && expectedSwitch == 1 && target == 0 { openedStaleControl = true }
                        }
                        let service = MicMuteService.shared
                        if syncFirst {
                            service.syncWithPreferences()
                            DispatchQueue.drain()
                            if !service.isMuted {
                                suite.expect(HAL.levels == expected && HAL.mute[20] == expectedSwitch
                                             && service.warning == (uncertain.isEmpty ? nil : .manualRestore),
                                             "launch preserves uncommitted controls and reports their uncertainty after \(point.name)")
                            }
                        }
                        // The shortcut can finish a persisted request or start a fresh mute.
                        service.toggle()
                        DispatchQueue.drain()
                        if service.isMuted {
                            service.toggle()
                            DispatchQueue.drain()
                        }
                        suite.expect(!openedStaleControl && HAL.levels == expected && HAL.mute[20] == expectedSwitch
                                     && !service.isMuted && !service.hasOutstandingClaims
                                     && service.warning == (uncertain.isEmpty ? nil : .manualRestore),
                                     "first mute recovers at \(point.name), floor \(floor), edit \(String(describing: edit)), sync first \(syncFirst)")
                    }
                }
            }
        }
    }

    private static func runInterruptedMixerHandoffTests(_ suite: TestSuite) {
        let defaults = UserDefaults.standard
        let uid = "device-10", peer = "device-20"
        let master = HAL.key(10), channel = HAL.key(10, 1), other = HAL.key(20)
        for allFail in [false, true] {
            HAL.reset()
            HAL.devices = [10, 20]
            let original: [Key: Float] = [master: 0.625, channel: 0.75, other: 0.875]
            HAL.levels = original
            HAL.mute[10] = 0
            let service = MicMuteService.shared
            service.toggle()
            DispatchQueue.drain()
            HAL.ignoredWrites = [master, other]
            service.toggle()
            DispatchQueue.drain()
            let mixer = AudioInputDeviceManager()
            mixer.start()
            DispatchQueue.drain()

            HAL.ignoredWrites = []
            HAL.writeFails = allFail ? [master, channel] : []
            var checkpoints: [Checkpoint] = []
            var unedited = allFail ? [Checkpoint(name: "before the mixer edit")] : []
            var accepted = false
            var markerWasSet = false
            HAL.beforeControlWrite = { key, _ in
                suite.expect(hasPendingControlWrite(uid, in: defaults.values),
                             "each attempted mixer setter on an owed input records its UID before entering the HAL")
                checkpoints.append(Checkpoint(name: "before mixer Set on element \(key.e)"))
            }
            HAL.afterControlWrite = { key in
                accepted = !allFail
                checkpoints.append(Checkpoint(name: "inside mixer Set on element \(key.e)"))
            }
            defaults.afterChange = { key in
                let pending = hasPendingControlWrite(uid, in: defaults.values)
                let cleared = markerWasSet && !pending
                markerWasSet = pending
                if accepted && cleared {
                    let maps = [DefaultsKey.micMuteSavedControls, DefaultsKey.micMuteSavedVolumes,
                                DefaultsKey.micMuteSavedChannelVolumes, DefaultsKey.micMuteProtectedChannels]
                    suite.expect(maps.allSatisfy { defaults.dictionary(forKey: $0)?[uid] == nil }
                                 && defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices) == [peer]
                                 && defaults.bool(forKey: DefaultsKey.micMuteManualCheckNeeded),
                                 "the accepted edit retires its marker after the full UID handoff and reminder")
                }
                if accepted || pending {
                    checkpoints.append(Checkpoint(name: "mixer preference \(key)"))
                } else if cleared && allFail {
                    unedited.append(Checkpoint(name: "marker removed after rejected mixer Set"))
                }
            }
            mixer.setInputVolume(0.375)
            DispatchQueue.drain()
            defaults.afterChange = nil
            HAL.beforeControlWrite = nil
            HAL.afterControlWrite = nil
            mixer.stop()
            let completed = Checkpoint(name: "completed mixer edit")
            suite.expect(!checkpoints.isEmpty && !hasPendingControlWrite(uid, in: defaults.values)
                         && defaults.bool(forKey: DefaultsKey.micMuteManualCheckNeeded) == !allFail,
                         "the completed mixer call removes its marker and warns only after an accepted setter")

            if allFail { unedited.append(completed) }
            for point in unedited {
                point.reopen()
                MicMuteService.shared.syncWithPreferences()
                DispatchQueue.drain()
                suite.expect(HAL.levels == original && HAL.mute[10] == 0 && MicMuteService.shared.warning == nil,
                             "both inputs keep their genuine targets at \(point.name)")
            }
            for point in checkpoints {
                var expected = point.levels
                expected[other] = original[other]
                for syncFirst in [true, false] {
                    point.reopen()
                    let restored = MicMuteService.shared
                    if syncFirst {
                        restored.syncWithPreferences()
                        DispatchQueue.drain()
                        suite.expect(HAL.writes == [other] && HAL.levels == expected && HAL.mute == point.switches
                                     && restored.warning == .manualRestore && !restored.hasOutstandingClaims,
                                     "only the peer restores after interruption at \(point.name)")
                    }
                    restored.toggle()
                    DispatchQueue.drain()
                    restored.toggle()
                    DispatchQueue.drain()
                    suite.expect(HAL.levels == expected && HAL.mute == point.switches && restored.warning == .manualRestore
                                 && !restored.hasOutstandingClaims,
                                 "a fresh mute cycle preserves the manual mix after \(point.name), sync first: \(syncFirst)")
                }
            }
        }

        // B arrives after A was muted. C was already quiet when it appeared.
        let left = HAL.key(20, 1), right = HAL.key(20, 2), quiet = HAL.key(30)
        let devicesChanged = HAL.key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyDevices,
                                     scope: kAudioObjectPropertyScopeGlobal)
        enum CaptureDriver { case roundsUp, rejects, ignores }
        for driver in [CaptureDriver.roundsUp, .rejects, .ignores] {
            HAL.reset()
            HAL.levels[master] = 0.875
            MicMuteService.shared.toggle()
            DispatchQueue.drain()
            var arrivingMix: [Key: Float] = [master: 0.875, other: 0.625, quiet: 0]
            if driver == .roundsUp {
                arrivingMix[left] = 0.005
                arrivingMix[right] = 0
            }
            HAL.devices = [10, 20, 30]
            HAL.levels = arrivingMix
            HAL.levels[master] = 0
            let originalSwitch: UInt32 = driver == .roundsUp ? 0 : 1
            HAL.mute[20] = originalSwitch
            switch driver {
            case .roundsUp: HAL.minimumGain[other] = 0.005
            case .rejects: HAL.writeFails.insert(other)
            case .ignores: HAL.ignoredWrites.insert(other)
            }
            HAL.writes = []
            var captures = [Checkpoint(name: "before capturing the new input")]
            defaults.afterChange = { captures.append(Checkpoint(name: "capture preference \($0)")) }
            HAL.beforeControlWrite = { key, _ in captures.append(Checkpoint(name: "before capture Set \(key.s):\(key.e)")) }
            HAL.afterControlWrite = { key in captures.append(Checkpoint(name: "after capture Set \(key.s):\(key.e)")) }
            suite.expect(HAL.notifyIfRegistered(devicesChanged), "the real device-list listener sees the arriving microphones")
            DispatchQueue.drain()
            defaults.afterChange = nil
            HAL.beforeControlWrite = nil
            HAL.afterControlWrite = nil
            let owners = Set(defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices) ?? [])
            if driver == .roundsUp {
                suite.expect(HAL.levels[other] == 0.005 && HAL.levels[left] == 0 && HAL.mute[20] == 1 && owners == [uid, peer],
                             "a capture owns the input whose master rounds zero up, leaving a user-silenced input alone")
            } else {
                suite.expect(HAL.writes.contains(other) && (driver != .rejects || owners == [uid]) && captures.contains {
                    ($0.preferences[DefaultsKey.micMuteMutedDevices] as? [String])?.contains(peer) == true
                }, "the new input is provisionally recorded and a definitive setter error retires its claim")
            }
            for point in captures {
                for syncFirst in (driver == .roundsUp ? [false, true] : [false]) {
                    point.reopen()
                    let restored = MicMuteService.shared
                    if syncFirst {
                        restored.syncWithPreferences()
                        DispatchQueue.drain()
                    }
                    restored.toggle()
                    DispatchQueue.drain()
                    suite.expect(HAL.levels == arrivingMix && HAL.mute[20] == originalSwitch && !HAL.writes.contains(quiet)
                                 && !restored.hasOutstandingClaims && restored.warning == nil,
                                 "unmute preserves every original gain and switch after \(point.name), driver: \(driver), sync first: \(syncFirst)")
                }
            }
        }

        HAL.reset()
        HAL.levels[master] = 0.875
        MicMuteService.shared.toggle()
        DispatchQueue.drain()
        HAL.devices = [10, 20]
        HAL.levels[other] = 0.625
        var replaced = false
        defaults.afterChange = { key in
            guard !replaced, key == DefaultsKey.micMuteMutedDevices,
                  defaults.stringArray(forKey: key)?.contains(peer) == true else { return }
            HAL.uids[20] = "quiet-replacement"
            HAL.levels[other] = 0
            replaced = HAL.notifyIfRegistered(devicesChanged)
        }
        HAL.writes = []
        _ = HAL.notifyIfRegistered(devicesChanged)
        DispatchQueue.drain()
        defaults.afterChange = nil
        suite.expect(replaced && HAL.writes.isEmpty && defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices) == [uid],
                     "reusing the ID during capture leaves the quiet replacement untouched and retires the unsubmitted claim")
        HAL.uids[20] = peer
        MicMuteService.shared.toggle()
        DispatchQueue.drain()
        suite.expect(HAL.writes == [master] && HAL.levels == [master: 0.875, other: 0],
                     "a pre-Set capture cannot reopen an input that returned already quiet")

        // Older captures saved the new UID's scalar before its other maps and before adding it to the list.
        enum PartialInput { case master, unrecordedChannel, third, readOnlyThird }
        for (residual, reapply, input) in [(Float(0), false, PartialInput.master), (0.005, false, .master),
                                           (0.005, true, .master), (0.005, false, .unrecordedChannel),
                                           (0.005, true, .unrecordedChannel), (0, false, .third), (0, false, .readOnlyThird)] {
            HAL.reset()
            HAL.levels[master] = 0.875
            MicMuteService.shared.toggle()
            DispatchQueue.drain()
            HAL.devices = [10, 20]
            let third = HAL.key(20, 3)
            if input == .third || input == .readOnlyThird {
                HAL.streamChannels[20] = [3]
                HAL.levels[third] = residual
                defaults.set([peer: ["3": 0.625]], forKey: DefaultsKey.micMuteSavedChannelVolumes)
                if input == .readOnlyThird {
                    HAL.levels[left] = 0
                    HAL.readOnly.insert(third)
                }
            } else {
                HAL.levels[other] = residual
                HAL.minimumGain[other] = residual
                if input == .unrecordedChannel { HAL.levels[left] = 0 }
            }
            defaults.set([uid: 0.875, peer: 0.625], forKey: DefaultsKey.micMuteSavedVolumes)
            HAL.relaunchClient()
            let service = MicMuteService.shared
            var openedChannel = false
            HAL.beforeControlWrite = { key, value in
                if key == left && value > 0 { openedChannel = true }
            }
            if reapply {
                service.syncWithPreferences()
                DispatchQueue.drain()
            }
            service.toggle()
            DispatchQueue.drain()
            if input == .third || input == .readOnlyThird {
                suite.expect(HAL.levels[third] == (input == .third ? 0.625 : 0) && !openedChannel
                             && HAL.writes.contains(third) == (input == .third) && !service.hasOutstandingClaims
                             && service.warning == .manualRestore,
                             "a partial capture restores its named third channel only when it is writable")
            } else if input == .unrecordedChannel {
                suite.expect(!openedChannel && HAL.levels[left] == 0,
                             "a partial scalar capture cannot open an independent channel with no saved level")
                suite.expect(HAL.levels[master] == 0.875 && (HAL.levels[other] == 0.625 || service.warning == .manualRestore),
                             "the peer restores even if the partial input needs a manual check")
            } else {
                suite.expect(HAL.levels == [master: 0.875, other: residual] && !service.hasOutstandingClaims
                             && service.warning == .manualRestore,
                             "an unaddressed pre-marker level cannot be assigned to the master that appears today")
            }
        }

        for hasList in [false, true] {
            HAL.reset()
            HAL.levels[master] = 0.375
            defaults.set(true, forKey: DefaultsKey.micMuteActive)
            defaults.set(0.625, forKey: DefaultsKey.micMuteSavedVolume)
            if hasList { defaults.set([String](), forKey: DefaultsKey.micMuteMutedDevices) }
            HAL.relaunchClient()
            MicMuteService.shared.toggle()
            DispatchQueue.drain()
            suite.expect(HAL.writes.isEmpty && HAL.levels[master] == 0.375
                         && MicMuteService.shared.warning == (hasList ? nil : .manualRestore),
                         "only a missing historical list leaves the old global gain unidentified")
        }

        for hasList in [false, true] {
            HAL.reset()
            HAL.devices = [10, 20]
            HAL.levels = [master: 0.375, other: 0]
            bindLegacyDefault(uid: peer, gain: 0.875, scalars: [0])
            if hasList { defaults.set([String](), forKey: DefaultsKey.micMuteMutedDevices) }
            else { defaults.removeObject(forKey: DefaultsKey.micMuteMutedDevices) }
            HAL.relaunchClient()
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
            suite.expect(HAL.writes == (hasList ? [] : [other]) && HAL.levels == [master: 0.375, other: hasList ? 0 : 0.875]
                         && !MicMuteService.shared.hasOutstandingClaims,
                         "the same bound legacy record is valid with a missing list and retired by an explicit empty list")
        }
    }

    private static func runMixerRestoreAdjustmentTests(_ suite: TestSuite) {
        let master = HAL.key(10)
        let linked = HAL.key(10, 1)
        let independent = HAL.key(10, 2)
        func recoveringMixer(_ levels: [Key: Float], ticks: Int = 2) -> AudioInputDeviceManager {
            HAL.reset()
            var now: TimeInterval = 10
            let service = MicMuteService(uptime: { now })
            MicMuteService.shared = service
            HAL.devices = Set(levels.keys.map(\.d)).sorted()
            HAL.levels = levels
            service.toggle()
            DispatchQueue.drain()
            HAL.ignoredWrites = Set(levels.keys)
            service.toggle()
            DispatchQueue.drain()
            for _ in 0..<ticks {
                now += 2
                service.halQueue.runTimers()
                DispatchQueue.drain()
            }
            suite.expect(service.warning == (ticks == 2 ? .restoreExhausted : .restoreUnconfirmed),
                         "the mixer edit starts at the expected recovery attempt")
            let mixer = AudioInputDeviceManager()
            mixer.start()
            DispatchQueue.drain()
            HAL.writes = []
            return mixer
        }
        func relaunch(_ mixer: AudioInputDeviceManager) {
            mixer.stop()
            HAL.afterWrite = nil
            HAL.beforeControlWrite = nil
            HAL.minimumGain = [:]
            HAL.ignoredWrites = []
            HAL.writeFails = []
            HAL.writes = []
            HAL.relaunchClient()
            MicMuteService.shared.syncWithPreferences()
            DispatchQueue.drain()
        }

        let other = HAL.key(20)
        let serviceList = HAL.key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyDevices,
                                  scope: kAudioObjectPropertyScopeGlobal)
        let rounded: Float = 0.4
        let mixer = recoveringMixer([master: 0.625, linked: 0.25, independent: 0.875, other: 0.5])
        HAL.ignoredWrites.remove(master)
        HAL.minimumGain[master] = rounded
        mixer.setInputVolume(0.375)
        DispatchQueue.drain()
        let defaults = UserDefaults.standard
        suite.expect(HAL.writes == [master] && mixer.inputVolume == Double(rounded)
                     && defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices) == ["device-20"]
                     && MicMuteService.shared.warning == .manualRestore,
                     "an accepted rounded master edit releases the full UID while another input remains owed")
        // The driver publishes a linked channel later; the other channel never moved.
        HAL.levels[linked] = 0.3125
        _ = HAL.notifyIfRegistered(master)
        _ = HAL.notifyIfRegistered(serviceList)
        DispatchQueue.drain()
        suite.expect(HAL.writes == [master] && HAL.levels[linked] == 0.3125 && HAL.levels[independent] == 0
                     && MicMuteService.shared.warning == .manualRestore,
                     "late publication leaves both linked and independent channels under manual control")
        HAL.writes = []
        suite.expect(HAL.restartAudioService(), "the still-pending input receives a real audio service reset")
        DispatchQueue.drain()
        suite.expect(HAL.writes == [other] && HAL.levels[linked] == 0.3125 && HAL.levels[independent] == 0,
                     "a new HAL generation retries only the UID that the user did not hand off")
        relaunch(mixer)
        let manualMix: [Key: Float] = [master: rounded, linked: 0.3125, independent: 0, other: 0.5]
        suite.expect(HAL.writes == [other] && HAL.levels == manualMix && !MicMuteService.shared.hasOutstandingClaims
                     && MicMuteService.shared.warning == .manualRestore,
                     "on relaunch only the other UID restores, and the manual reminder survives")
        MicMuteService.shared.toggle()
        DispatchQueue.drain()
        suite.expect(MicMuteService.shared.isMuted && HAL.levels.values.allSatisfy { $0 == 0 },
                     "a new mute can close the input after its old recovery was handed off")
        MicMuteService.shared.toggle()
        DispatchQueue.drain()
        suite.expect(HAL.levels == manualMix && MicMuteService.shared.warning == .manualRestore,
                     "the new mute cycle restores its own snapshot without resurrecting the old mix")
        HAL.writes = []
        MicMuteService.shared.acknowledgeManualRestore()
        DispatchQueue.drain()
        suite.expect(MicMuteService.shared.warning == nil && HAL.writes.isEmpty,
                     "only acknowledging the manual check dismisses its reminder")

        for ignoredSample in [0.375, 0.75] {
            let drag = recoveringMixer([master: 0.625, independent: 0.875])
            HAL.beforeControlWrite = { key, target in
                if target == ignoredSample { HAL.ignoredWrites.insert(key) } else { HAL.ignoredWrites.remove(key) }
            }
            drag.setInputVolume(0.375)
            drag.setInputVolume(0.75)
            drag.halQueue.run()
            suite.expect(HAL.writes == [master] && !MicMuteService.shared.hasOutstandingClaims,
                         "the first noErr in a drag hands off every channel even when the setter was ignored")
            while !DispatchQueue.main.work.isEmpty { DispatchQueue.main.run() }
            MicMuteService.shared.halQueue.run()
            DispatchQueue.drain()
            let expected = ignoredSample == 0.375 ? 0.75 : 0.375
            suite.expect(HAL.writes == [master, master] && drag.inputVolume == expected && HAL.levels[independent] == 0
                         && MicMuteService.shared.warning == .manualRestore,
                         "the final drag sample is delivered and the manual reminder survives either readback")
            drag.stop()
        }

        let channels = recoveringMixer([linked: 0.25, independent: 0.875])
        HAL.ignoredWrites.remove(linked)
        HAL.writeFails = [independent]
        HAL.afterWrite = { HAL.levels[independent] = 0.125 }
        var releasedBeforeSecondSet = false
        HAL.beforeControlWrite = { key, _ in
            if key == independent {
                releasedBeforeSecondSet = !MicMuteService.shared.hasOutstandingClaims
                    && defaults.bool(forKey: DefaultsKey.micMuteManualCheckNeeded)
            }
        }
        channels.setInputVolume(0.375)
        DispatchQueue.drain()
        suite.expect(releasedBeforeSecondSet && HAL.writes == [linked, independent] && HAL.levels[independent] == 0.125,
                     "the first accepted channel releases the UID before the next channel setter can fail")
        relaunch(channels)
        suite.expect(HAL.writes.isEmpty && HAL.levels == [linked: 0.375, independent: 0.125]
                     && MicMuteService.shared.warning == .manualRestore,
                     "the failed second setter cannot recreate any of the input's former restore targets")

        for ticks in [0, 2] {
            let failed = recoveringMixer([master: 0.625, linked: 0.25], ticks: ticks)
            let deadline = MicMuteService.shared.retryDeadline
            HAL.writeFails = [master, linked]
            HAL.beforeControlWrite = { key, _ in if key == master { HAL.levels[master] = rounded } }
            failed.setInputVolume(0.375)
            DispatchQueue.drain()
            _ = HAL.notifyIfRegistered(serviceList)
            DispatchQueue.drain()
            suite.expect(HAL.writes == [master, linked] && failed.inputVolume == Double(rounded)
                         && MicMuteService.shared.hasOutstandingClaims && MicMuteService.shared.retryDeadline == deadline
                         && MicMuteService.shared.warning == (ticks == 2 ? .restoreExhausted : .restoreUnconfirmed),
                         "with no accepted mixer setter, a changed reading preserves the existing claims, deadline and retry budget")
            relaunch(failed)
            suite.expect(HAL.writes == [master, linked] && HAL.levels == [master: 0.625, linked: 0.25]
                         && !MicMuteService.shared.hasOutstandingClaims && MicMuteService.shared.warning == nil,
                         "a real reconnect can recover the original gains when the entire mixer edit failed")
        }

        for beforeSet in [true, false] {
            let replaced = recoveringMixer([linked: 0.25, independent: 0.875])
            HAL.ignoredWrites = []
            func replaceInput() {
                HAL.uids[10] = "replacement"
                HAL.levels = [linked: 0.25, independent: 0.125]
            }
            if beforeSet {
                defaults.afterChange = { _ in
                    if hasPendingControlWrite("device-10", in: defaults.values) { replaceInput() }
                }
            } else { HAL.afterWrite = replaceInput }
            replaced.setInputVolume(0.375)
            DispatchQueue.drain()
            defaults.afterChange = nil
            let service = MicMuteService.shared
            suite.expect(HAL.uids[10] == "replacement" && HAL.writes == (beforeSet ? [] : [linked])
                         && HAL.levels[independent] == 0.125 && service.hasOutstandingClaims == beforeSet
                         && !hasPendingControlWrite("device-10", in: defaults.values)
                         && service.warning == (beforeSet ? .restoreExhausted : .manualRestore),
                         "reusing the ID before or after the first setter releases the UID only for an accepted edit")
            HAL.uids[10] = "device-10"
            relaunch(replaced)
            suite.expect(HAL.writes == (beforeSet ? [independent] : []) && HAL.levels[linked] == 0.25
                         && HAL.levels[independent] == (beforeSet ? 0.875 : 0.125)
                         && MicMuteService.shared.warning == (beforeSet ? nil : .manualRestore),
                         "on return the original input still owes its old gain only when the mixer never wrote")
        }

        let unclaimed = recoveringMixer([master: 0, other: 0.5])
        HAL.ignoredWrites.remove(master)
        unclaimed.setInputVolume(0.375)
        DispatchQueue.drain()
        suite.expect(HAL.writes == [master] && HAL.levels[master] == 0.375
                     && defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices) == ["device-20"]
                     && MicMuteService.shared.warning == .restoreExhausted,
                     "editing a healthy input adds no manual warning while another input owes a restore")
        relaunch(unclaimed)
        suite.expect(HAL.writes == [other] && HAL.levels == [master: 0.375, other: 0.5] && MicMuteService.shared.warning == nil,
                     "a healthy input's ordinary mixer edit leaves no reminder after the other input recovers")
        let ordinary = AudioInputDeviceManager()
        ordinary.start()
        DispatchQueue.drain()
        ordinary.setInputVolume(0.75)
        DispatchQueue.drain()
        suite.expect(ordinary.inputVolume == 0.75 && MicMuteService.shared.warning == nil,
                     "the mixer remains an ordinary gain control outside recovery")
        ordinary.stop()
    }

    private static func runRestoreControlListEchoTests(_ suite: TestSuite) {
        let master = HAL.key(10)
        let channel = HAL.key(10, 1)
        let controlList = HAL.key(10, 0, kAudioObjectPropertyControlList, scope: kAudioObjectPropertyScopeGlobal)
        for delayed in [false, true] {
            HAL.reset()
            let service = MicMuteService.shared
            HAL.levels = [master: 0.625, channel: 0.875]
            service.setMuted(true)
            DispatchQueue.drain()
            HAL.levels = [:]
            service.setMuted(false)
            DispatchQueue.drain()
            func signalList() {
                suite.expect(HAL.notifyIfRegistered(controlList), "the pending input delivers its control-list change")
                DispatchQueue.drain()
            }

            HAL.levels[master] = 0
            if delayed { HAL.writeFails = [master] } else { HAL.ignoredWrites = [master] }
            HAL.writes = []
            var echoes = 0
            var queued: [() -> Void] = []
            HAL.beforeControlWrite = { key, _ in
                // Cap deliveries so a regression fails without exhausting the test queue.
                guard key == master, echoes < 3, let notify = HAL.pendingNotification(for: controlList) else { return }
                echoes += 1
                if delayed { queued.append(notify) } else { notify() }
            }
            signalList()
            while !queued.isEmpty {
                queued.removeFirst()()
                DispatchQueue.drain()
            }
            HAL.beforeControlWrite = nil
            suite.expect(echoes == 1 && HAL.writes == [master] && HAL.levels[master] == 0
                         && service.hasOutstandingClaims && service.warning == .restoreUnconfirmed,
                         "a refused master stays pending after its own \(delayed ? "late" : "synchronous") control-list echo")

            HAL.levels[channel] = 0
            HAL.writes = []
            signalList()
            suite.expect(HAL.writes == [channel] && HAL.levels[channel] == 0.875 && service.hasOutstandingClaims,
                         "a newly available channel restores without retrying its unchanged refused master")
            HAL.levels[channel] = 0.375
            HAL.levels[master] = nil
            HAL.writes = []
            signalList()
            suite.expect(HAL.writes.isEmpty && service.hasOutstandingClaims, "an unavailable master retains its claim")
            HAL.levels[master] = 0
            signalList()
            suite.expect(HAL.writes == [master] && HAL.levels[channel] == 0.375 && service.hasOutstandingClaims,
                         "the same master gets a fresh restore attempt after disappearing and returning")

            HAL.ignoredWrites = []
            HAL.writeFails = []
            HAL.writes = []
            if delayed {
                HAL.levels[master] = 0.625
                signalList()
            } else {
                service.setMuted(false)
                DispatchQueue.drain()
            }
            suite.expect(HAL.writes == (delayed ? [] : [master]) && HAL.levels[master] == 0.625
                         && HAL.levels[channel] == 0.375 && !service.hasOutstandingClaims
                         && service.warning == nil && HAL.listeners.isEmpty,
                         "a verified readback or an explicit unmute can finish the refused restore")
        }

        HAL.reset()
        let service = MicMuteService.shared
        HAL.levels = [master: 0.625, channel: 0.875]
        service.setMuted(true)
        DispatchQueue.drain()
        HAL.levels[master] = nil
        HAL.ignoredWrites = [channel]
        HAL.writes = []
        service.setMuted(false)
        DispatchQueue.drain()
        suite.expect(HAL.writes == [channel] && HAL.levels[channel] == 0 && service.hasOutstandingClaims,
                     "a refused channel keeps its own target while the linked master is absent")
        HAL.beforeControlWrite = { key, target in
            if key == master {
                HAL.levels[channel] = Float(target)
                HAL.ignoredWrites.remove(channel)
            }
        }
        HAL.levels[master] = 0
        HAL.writes = []
        suite.expect(HAL.notifyIfRegistered(controlList), "the device reports the return of the coupled master")
        DispatchQueue.drain()
        suite.expect(HAL.writes == [master, channel] && HAL.levels == [master: 0.625, channel: 0.875]
                     && !service.hasOutstandingClaims && HAL.listeners.isEmpty,
                     "the returning master permits compensation of a previously refused channel in the same restore")
    }

    private static func runPendingControlListTests(_ suite: TestSuite) {
        runPendingUIDGainListenerTests(suite)
        let global = kAudioObjectPropertyScopeGlobal
        let local = HAL.key(10, 0, kAudioObjectPropertyControlList, scope: global)
        let system = AudioObjectID(kAudioObjectSystemObject)
        let changed = HAL.key(system, 0, kAudioHardwarePropertyDevices, scope: global)
        let master = HAL.key(10)
        let channel = HAL.key(10, 1)
        let other = HAL.key(20)
        func releaseWithMissingMaster() {
            HAL.reset()
            HAL.devices = [10, 20]
            HAL.levels = [master: 0.625, channel: 0.25, other: 0.75]
            MicMuteService.shared.setMuted(true)
            DispatchQueue.drain()
            HAL.levels[master] = nil
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
            HAL.levels[channel] = 0.375
            HAL.writes = []
        }
        for relaunch in [false, true] {
            releaseWithMissingMaster()
            if relaunch {
                HAL.relaunchClient()
                MicMuteService.shared.syncWithPreferences()
                DispatchQueue.drain()
            }
            let service = MicMuteService.shared
            let delayed = HAL.pendingNotification(for: local)
            suite.expect(HAL.listeners.filter { $0.d != system } == [local] && delayed != nil && service.hasOutstandingClaims,
                         "only the incomplete input's control list stays registered during release")
            HAL.listenerAdds = []
            HAL.listenerRemovals = []
            service.syncWithPreferences()
            DispatchQueue.drain()
            suite.expect(HAL.listenerAdds.isEmpty && HAL.listenerRemovals.isEmpty && HAL.writes.isEmpty,
                         "a pending control list keeps its registration while the master stays absent")
            HAL.levels[master] = 0
            HAL.beforeControlWrite = { key, target in if key == master { HAL.levels[channel] = Float(target) } }
            suite.expect(HAL.notifyIfRegistered(local), "the reappearing master can be announced solely by its device")
            DispatchQueue.drain()
            suite.expect(HAL.levels == [master: 0.625, channel: 0.375, other: 0.75] && HAL.writes == [master, channel]
                         && !service.isMuted && !service.hasOutstandingClaims && HAL.listeners.isEmpty,
                         "the local event restores the linked master, preserves 0.375 and releases all listeners")
            let generation = service.applyGeneration
            delayed?()
            DispatchQueue.drain()
            suite.expect(service.applyGeneration == generation && HAL.listeners.isEmpty,
                         "a late control-list delivery cannot resume a completed restore")
        }

        releaseWithMissingMaster()
        let stale = HAL.pendingNotification(for: local)
        HAL.uids[10] = "replacement"
        HAL.levels[master] = 0.875
        stale?()
        DispatchQueue.drain()
        suite.expect(stale != nil && HAL.levels[master] == 0.875 && HAL.writes.isEmpty && !HAL.listeners.contains(local),
                     "a replacement reusing the object ID cannot inherit the listener or the saved gain")
        HAL.devices.append(30)
        HAL.uids[30] = "device-10"
        let returned = HAL.key(30, 0, kAudioObjectPropertyControlList, scope: global)
        let returnedChannel = HAL.key(30, 1)
        HAL.levels[returnedChannel] = 0.375
        _ = HAL.notifyIfRegistered(changed)
        DispatchQueue.drain()
        suite.expect(HAL.listeners.filter { $0.d != system } == [returned], "the local observer follows the owed UID onto its new object")
        let afterStop = HAL.pendingNotification(for: returned)
        MicMuteService.shared.unmuteForTeardown()
        HAL.levels[HAL.key(30)] = 0
        afterStop?()
        DispatchQueue.drain()
        suite.expect(afterStop != nil && HAL.writes.isEmpty && HAL.listeners.isEmpty && MicMuteService.shared.hasOutstandingClaims,
                     "teardown cancels the pending device listener even when the hardware still owes a restore")

        releaseWithMissingMaster()
        HAL.relaunchClient()
        HAL.beforeControlWrite = { key, target in if key == master { HAL.levels[channel] = Float(target) } }
        HAL.afterListenerAdd[local] = { HAL.levels[master] = 0 }
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        suite.expect(HAL.writes == [master, channel] && HAL.levels[channel] == 0.375
                     && HAL.listeners.isEmpty && !MicMuteService.shared.hasOutstandingClaims,
                     "one post-registration read catches a master that returned before its control-list listener was installed")

        releaseWithMissingMaster()
        HAL.relaunchClient()
        HAL.levels[master] = 0
        HAL.ignoredWrites = [master]
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        suite.expect(HAL.writes == [master] && MicMuteService.shared.hasOutstandingClaims && HAL.listeners.contains(local),
                     "registering a pending input on launch makes one attempt when its present master refuses restoration")
        HAL.levels[master] = nil
        HAL.ignoredWrites = []
        HAL.dropListeners(forDevice: 10)
        _ = HAL.notifyIfRegistered(changed)
        DispatchQueue.drain()
        suite.expect(HAL.listeners.contains(local), "a coalesced same-UID reconnect reacquires its lost control-list listener")
        HAL.levels[master] = 0
        _ = HAL.notifyIfRegistered(local)
        DispatchQueue.drain()
        suite.expect(HAL.levels[master] == 0.625 && HAL.listeners.isEmpty,
                     "the renewed local registration finishes the restore on the reconnected input")
    }

    private static func runPendingUIDGainListenerTests(_ suite: TestSuite) {
        let defaults = UserDefaults.standard
        let local = HAL.key(10, 0, kAudioObjectPropertyControlList, scope: kAudioObjectPropertyScopeGlobal)
        let system = AudioObjectID(kAudioObjectSystemObject)
        let master = HAL.key(10)
        let other = HAL.key(20)
        HAL.reset()
        HAL.devices = [10, 20]
        HAL.levels = [other: 0.375]
        // This legacy input recorded its scalar channel by element.
        defaults.set(["device-10"], forKey: DefaultsKey.micMuteMutedDevices)
        let channel = HAL.key(10, 1)
        defaults.set(["device-10": ["1": 0.625]], forKey: DefaultsKey.micMuteSavedChannelVolumes)
        HAL.relaunchClient()
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        let late = HAL.pendingNotification(for: local)
        suite.expect(HAL.listeners.filter { $0.d != system } == [local] && late != nil && HAL.writes.isEmpty
                     && MicMuteService.shared.hasOutstandingClaims,
                     "a named legacy channel watches for its own missing control")
        HAL.levels[channel] = 0
        suite.expect(HAL.notifyIfRegistered(local), "the input's control list alone reports the returning scalar")
        DispatchQueue.drain()
        suite.expect(HAL.writes == [channel] && HAL.levels == [channel: 0.625, other: 0.375] && HAL.listeners.isEmpty
                     && !MicMuteService.shared.hasOutstandingClaims && MicMuteService.shared.warning == nil,
                     "the local event restores the recorded channel gain once and retires all listeners")
        HAL.levels[channel] = 0.25
        late?()
        DispatchQueue.drain()
        suite.expect(HAL.writes == [channel] && HAL.levels[channel] == 0.25 && HAL.listeners.isEmpty,
                     "a late scalar-list callback preserves the user's subsequent gain")

        HAL.reset()
        HAL.levels[master] = 0
        defaults.set(["device-10"], forKey: DefaultsKey.micMuteMutedDevices)
        defaults.set(0.625, forKey: DefaultsKey.micMuteSavedVolume)
        HAL.relaunchClient()
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        HAL.mute[10] = 1
        suite.expect(!HAL.listenerAdds.contains(local) && !HAL.notifyIfRegistered(local)
                     && MicMuteService.shared.warning == .manualRestore && !MicMuteService.shared.hasOutstandingClaims
                     && HAL.writes.isEmpty && HAL.listeners.isEmpty,
                     "a UID without a saved level or identifiable switch leaves only the manual reminder")
    }

    private static func runMuteListenerTests(_ suite: TestSuite) {
        func notify(_ key: Key) {
            suite.expect(HAL.notifyIfRegistered(key), "the HAL delivers this change to a registered listener")
            DispatchQueue.drain()
        }
        func expectCalls(_ message: String, adding: Set<Key> = [], removing: Set<Key> = []) {
            suite.expect(Set(HAL.listenerAdds) == adding && HAL.listenerAdds.count == adding.count
                         && Set(HAL.listenerRemovals) == removing && HAL.listenerRemovals.count == removing.count,
                         message)
            HAL.listenerAdds = []
            HAL.listenerRemovals = []
        }

        HAL.reset()
        let system = AudioObjectID(kAudioObjectSystemObject)
        let global = kAudioObjectPropertyScopeGlobal
        let devicesChanged = HAL.key(system, 0, kAudioHardwarePropertyDevices, scope: global)
        let restarted = HAL.key(system, 0, kAudioHardwarePropertyServiceRestarted, scope: global)
        let defaultInput = HAL.key(system, 0, kAudioHardwarePropertyDefaultInputDevice, scope: global)
        let controlsChanged = HAL.key(10, 0, kAudioObjectPropertyControlList, scope: global)
        let gain = HAL.key(10)
        let channelSwitch = HAL.key(10, 1, kAudioDevicePropertyMute)
        let thirdChannel = HAL.key(10, 3)
        let headset = HAL.key(20)
        HAL.levels[gain] = 0.5
        HAL.muteElements[channelSwitch] = 0
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        let original = HAL.listeners
        let expected: Set<Key> = [devicesChanged, restarted, defaultInput,
                                  controlsChanged, HAL.key(10, 0, kAudioDevicePropertyStreamConfiguration),
                                  HAL.key(10, 0, kAudioDevicePropertyStreams),
                                  HAL.key(10, 0, kAudioDevicePropertyDeviceIsAlive, scope: global),
                                  HAL.key(10, 0, kAudioDevicePropertyDeviceHasChanged, scope: global),
                                  gain, channelSwitch]
        suite.expect(original == expected, "mute watches topology and only the controls present on the physical input")
        expectCalls("the first mute installs each listener once", adding: original)

        HAL.levels[gain] = 0.8
        notify(gain)
        suite.expect(HAL.levels[gain] == 0, "the next gain notification still silences a physical microphone")
        expectCalls("re-muting gain keeps existing listeners")

        HAL.muteElements[channelSwitch] = nil
        HAL.failedListenerRemovals = [channelSwitch]
        notify(gain)
        suite.expect(HAL.listeners == original && HAL.listenerAdds.isEmpty
                     && Set(HAL.listenerRemovals) == [channelSwitch],
                     "a temporary removal error leaves other registrations intact")
        HAL.listenerRemovals = []
        HAL.failedListenerRemovals = []
        notify(gain)
        suite.expect(HAL.listeners == original.subtracting([channelSwitch]),
                     "an unavailable switch is no longer watched")
        expectCalls("a failed removal is retried on the next reconciliation", removing: [channelSwitch])
        HAL.muteElements[channelSwitch] = 1
        notify(gain)
        suite.expect(HAL.listeners == original, "a switch that returns on the same channel is watched again")
        expectCalls("a gain callback registers only the returning switch", adding: [channelSwitch])

        HAL.readFails.insert(devicesChanged)
        notify(devicesChanged)
        suite.expect(HAL.listeners == original && MicMuteService.shared.isMuted && MicMuteService.shared.hasUnconfirmedInputs,
                     "a failed device-list read preserves the active registrations and marks coverage unconfirmed")
        expectCalls("a failed device-list read does not detach the last known input")
        HAL.readFails.remove(devicesChanged)
        let inputListeners = original.filter { $0.d == 10 }
        HAL.devices = []
        notify(devicesChanged)
        suite.expect(HAL.listeners == original.subtracting(inputListeners) && MicMuteService.shared.hasUnconfirmedInputs,
                     "the system stays watched with coverage unconfirmed while no inputs are present")
        expectCalls("removing the last input clears its registrations", removing: inputListeners)
        HAL.devices = [10]
        notify(devicesChanged)
        suite.expect(HAL.listeners == original && !MicMuteService.shared.hasUnconfirmedInputs,
                     "the returning UID and object ID regain confirmation after a new check")
        expectCalls("the returning input regains each of its registrations", adding: inputListeners)

        HAL.devices = [10, 20]
        HAL.streamChannels[10] = [3]
        HAL.levels[thirdChannel] = 0.5
        HAL.levels[headset] = 0.75
        notify(devicesChanged)
        let expanded = HAL.listeners
        suite.expect(original.isSubset(of: expanded) && expanded.contains(thirdChannel) && expanded.contains(headset),
                     "an arriving headset and an additional input channel are watched")
        let expandedInputListeners = expanded.filter { $0.d != system }
        expectCalls("a device arrival renews existing input listeners once and registers the new controls",
                    adding: expandedInputListeners, removing: inputListeners)

        notify(controlsChanged)
        let microphoneListeners = expanded.filter { $0.d == 10 }
        expectCalls("a control-list notification renews each listener on the affected input exactly once",
                    adding: microphoneListeners, removing: microphoneListeners)
        let sweepsAfterRenewal = MicMuteService.shared.applyGeneration
        for _ in 0..<5 { notify(headset) }
        suite.expect(MicMuteService.shared.applyGeneration == sweepsAfterRenewal + 5 && HAL.listeners == expanded,
                     "each gain notification after renewal settles in one sweep")
        expectCalls("repeated gain notifications between device-list changes keep the renewed listeners")

        let uid = HAL.key(10, 0, kAudioDevicePropertyDeviceUID, scope: global)
        let streams = HAL.key(10, 0, kAudioDevicePropertyStreams)
        let layout = HAL.key(10, 0, kAudioDevicePropertyStreamConfiguration)
        let unreadable: [(label: String, data: Set<Key>, size: Set<Key>)] = [
            ("device UID", [uid], []), ("input streams", [], [streams]),
            ("channel layout size", [], [layout]), ("channel layout", [layout], []),
        ]
        for failure in unreadable {
            HAL.readFails = failure.data
            HAL.sizeReadFails = failure.size
            HAL.levels[headset] = 0.8
            notify(headset)
            suite.expect(HAL.listeners == expanded && HAL.levels[headset] == 0,
                         "unreadable \(failure.label) preserves the high channel and enforces mute on the other input")
            expectCalls("unreadable \(failure.label) keeps the last known registrations")
            HAL.readFails = []
            HAL.sizeReadFails = []
            HAL.levels[thirdChannel] = 0.8
            if HAL.listeners.contains(thirdChannel) { notify(thirdChannel) }
            suite.expect(HAL.levels[thirdChannel] == 0,
                         "the third channel is silenced on its next gain change after \(failure.label) recovers")
            expectCalls("recovered \(failure.label) needs no new registrations")
        }

        HAL.devices = [10]
        HAL.streamChannels[10] = [2]
        HAL.levels[thirdChannel] = nil
        notify(devicesChanged)
        suite.expect(HAL.listeners == original, "departed inputs and channels lose their listeners")
        expectCalls("a device departure removes old input listeners and registers the remaining controls once",
                    adding: inputListeners, removing: expandedInputListeners)

        HAL.uids[10] = "replacement input"
        HAL.levels[gain] = 0.625
        HAL.failedListenerRemovals = [gain]
        notify(devicesChanged)
        suite.expect(HAL.listeners == original && HAL.listenerRemovals.contains(gain)
                     && !HAL.listenerAdds.contains(gain),
                     "a replacement waits for the old registration at the same address to be removed")
        HAL.listenerRemovals.removeAll { $0 == gain }
        let renewed = inputListeners.subtracting([gain])
        expectCalls("a reused audio object ID renews the other registrations on that input",
                    adding: renewed, removing: renewed)
        HAL.failedListenerRemovals = []
        HAL.failedListenerKeys = [gain]
        notify(defaultInput)
        suite.expect(HAL.listenerAdds.contains(gain) && HAL.listeners == original.subtracting([gain]),
                     "a failed registration on a replacement input is kept available for retry")
        HAL.listenerAdds.removeAll { $0 == gain }
        expectCalls("the replacement removes the old registration as soon as the HAL is ready", removing: [gain])
        HAL.failedListenerKeys = []
        notify(defaultInput)
        suite.expect(HAL.listeners == original, "the replacement regains its previously unavailable listener")
        expectCalls("only the failed registration is retried", adding: [gain])

        suite.expect(HAL.restartAudioService(), "the reset reaches a registered system listener")
        DispatchQueue.drain()
        suite.expect(HAL.listeners == original && Set(HAL.listenerAdds) == original
                     && HAL.listenerAdds.count == original.count,
                     "a restarted audio service regains every listener even with unchanged IDs and UIDs")
        HAL.listenerAdds = []
        HAL.listenerRemovals = []
        HAL.levels[gain] = 0.8
        notify(gain)
        suite.expect(HAL.levels[gain] == 0, "gain is silenced on the first callback after an audio reset")
        expectCalls("a gain callback after restart keeps the rebuilt registrations")

        MicMuteService.shared.unmuteForTeardown()
        DispatchQueue.drain()
        suite.expect(HAL.listeners.isEmpty && HAL.levels[gain] == 0.625,
                     "teardown restores the replacement's own gain and clears all listeners")
        expectCalls("teardown removes each remaining listener once", removing: original)
    }

    private static func runMuteRecoveryTests(_ suite: TestSuite) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let global = kAudioObjectPropertyScopeGlobal
        let reset = HAL.key(system, 0, kAudioHardwarePropertyServiceRestarted, scope: global)
        let devicesChanged = HAL.key(system, 0, kAudioHardwarePropertyDevices, scope: global)
        let gain = HAL.key(10)
        let uid = HAL.key(10, 0, kAudioDevicePropertyDeviceUID, scope: global)
        let streams = HAL.key(10, 0, kAudioDevicePropertyStreams)
        let alive = HAL.key(10, 0, kAudioDevicePropertyDeviceIsAlive, scope: global)
        func notify(_ key: Key) {
            suite.expect(HAL.notifyIfRegistered(key), "recovery is triggered by a registered property listener")
            DispatchQueue.drain()
        }
        func startMute() -> MicMuteService {
            HAL.reset()
            HAL.levels[gain] = 0.625
            let service = MicMuteService.shared
            service.setMuted(true)
            return service
        }

        for publishFirst in [false, true] {
            let service = startMute()
            service.halQueue.sync {}
            if publishFirst { DispatchQueue.drain() }
            suite.expect(HAL.levels[gain] == 0 && service.isMuted == publishFirst && service.hasOutstandingClaims,
                         "the first mute has saved the input's level before the service resets")
            HAL.devices = []
            suite.expect(HAL.restartAudioService(), "a successful first mute is already subscribed to service resets")
            DispatchQueue.drain()
            suite.expect(service.wantsMute && service.isMuted && service.hasOutstandingClaims
                         && UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive),
                         "an empty post-reset inventory preserves a successful mute and its original claim")
            HAL.devices = [10]
            HAL.levels[gain] = 0.8
            notify(devicesChanged)
            suite.expect(service.isMuted && HAL.levels[gain] == 0, "the returning device is silenced after reset")
            service.setMuted(false)
            DispatchQueue.drain()
            suite.expect(!service.isMuted && HAL.levels[gain] == 0.625 && !service.hasOutstandingClaims,
                         "only an explicit unmute restores the level saved before the reset")
        }

        HAL.reset()
        HAL.failedListenerKeys = [reset]
        HAL.levels[gain] = 0.625
        let initial = MicMuteService.shared
        initial.setMuted(true)
        initial.halQueue.sync {}
        suite.expect(!HAL.restartAudioService(), "the HAL cannot deliver a reset when its first registration fails")
        HAL.failedListenerKeys = []
        DispatchQueue.drain()
        HAL.levels[gain] = 0.8
        notify(gain)
        suite.expect(initial.isMuted && HAL.levels[gain] == 0 && HAL.listeners.contains(reset),
                     "a missed reset during the first mute cannot leave a cached but dead gain listener")

        for changed in [streams, alive] {
            let service = startMute()
            DispatchQueue.drain()
            if changed == streams { HAL.inputsWithoutStreams = [10] } else { HAL.inactiveDevices = [10] }
            notify(changed)
            HAL.inputsWithoutStreams = []
            HAL.inactiveDevices = []
            HAL.levels[gain] = 0.8
            notify(changed)
            suite.expect(service.isMuted && HAL.levels[gain] == 0 && HAL.listeners.contains(gain),
                         "a listed device that regains streams or becomes alive reopens no microphone")
        }

        let service = startMute()
        DispatchQueue.drain()
        let inputListeners = HAL.listeners.filter { $0.d == 10 }
        HAL.devices.append(20)
        HAL.levels[HAL.key(20)] = 0.75
        HAL.readFails = [uid]
        HAL.failedListenerKeys = inputListeners
        HAL.listenerRemovals = []
        notify(devicesChanged)
        suite.expect(inputListeners.isSubset(of: HAL.listeners) && inputListeners.isDisjoint(with: HAL.listenerRemovals),
                     "partial discovery preserves live listeners on an input that cannot accept new registrations")
        HAL.readFails = []
        HAL.failedListenerKeys = []
        HAL.listenerAdds = []
        HAL.levels[gain] = 0.8
        notify(gain)
        suite.expect(service.isMuted && HAL.levels[gain] == 0 && inputListeners.isSubset(of: HAL.listeners)
                     && Set(HAL.listenerRemovals) == inputListeners && Set(HAL.listenerAdds) == inputListeners,
                     "the preserved gain listener triggers mute and deferred renewal once the input is readable")

        let failures: [(label: String, data: Set<Key>, size: Set<Key>)] = [
            ("UID", [uid], []), ("input streams", [], [streams]), ("device list", [devicesChanged], []),
        ]
        for failure in failures {
            HAL.reset()
            var now: TimeInterval = 10
            let service = MicMuteService(uptime: { now })
            MicMuteService.shared = service
            HAL.levels[gain] = 0.625
            service.setMuted(true)
            DispatchQueue.drain()
            func hasTimer() -> Bool { service.halQueue.delayed.contains { !$0.isCancelled } }
            func tick() {
                now += 1
                service.halQueue.runTimers()
                DispatchQueue.drain()
            }
            HAL.readFails = failure.data
            HAL.sizeReadFails = failure.size
            HAL.levels[gain] = 0.8
            suite.expect(HAL.restartAudioService(), "reset reaches the HAL client before delayed discovery")
            DispatchQueue.drain()
            suite.expect(service.isMuted && hasTimer(), "an unreadable post-reset \(failure.label) schedules recovery")
            tick()
            HAL.readFails = []
            HAL.sizeReadFails = []
            for _ in 0..<5 where hasTimer() { tick() }
            suite.expect(HAL.levels[gain] == 0 && HAL.listeners.contains(gain) && !hasTimer(),
                         "the timer alone recovers the \(failure.label), enforces mute and stops")

            HAL.readFails = failure.data
            HAL.sizeReadFails = failure.size
            suite.expect(HAL.restartAudioService(), "the recovered system listener receives a later reset")
            DispatchQueue.drain()
            var attempts = 0
            for _ in 0..<8 where hasTimer() {
                attempts += 1
                tick()
            }
            suite.expect((1...5).contains(attempts) && !hasTimer() && service.wantsMute,
                         "persistently unreadable \(failure.label) cannot poll forever or cancel the mute")
        }
    }

    private static func runCallAppUnmuteTests(_ suite: TestSuite) {
        let microphone = HAL.key(10)
        let secondInput = HAL.key(20)
        let devicesChanged = HAL.key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyDevices,
                                     scope: kAudioObjectPropertyScopeGlobal)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let callPID: Int32 = ownPID == 4242 ? 4243 : 4242
        func prepare(_ followCalls: Bool? = true) {
            HAL.reset()
            if let followCalls {
                UserDefaults.standard.set(followCalls, forKey: DefaultsKey.micMuteFollowCallApps)
            }
            HAL.levels[microphone] = 0.5
        }
        func mute() {
            MicMuteService.shared.setMuted(true)
            DispatchQueue.drain()
            QuickToolHUD.messages = []
        }
        func record(_ device: UInt32 = 10) {
            HAL.processes = [(object: 100, pid: callPID, recording: true, devices: [device])]
        }
        func signal(_ device: UInt32, selector: AudioObjectPropertySelector) {
            suite.expect(HAL.notifyIfRegistered(HAL.key(device, 0, selector)),
                         "the HAL delivers the change to the registered input listener")
        }
        func notify(_ device: UInt32 = 10, selector: AudioObjectPropertySelector = kAudioDevicePropertyVolumeScalar) {
            signal(device, selector: selector)
            DispatchQueue.drain()
        }
        func topologyChanged() {
            suite.expect(HAL.notifyIfRegistered(devicesChanged), "the HAL delivers the device-list notification")
            DispatchQueue.drain()
        }
        func resetAudioService() {
            suite.expect(HAL.restartAudioService(), "the in-flight reset reaches the registered callback")
        }

        prepare()
        HAL.devices = [10, 20]
        HAL.levels[secondInput] = 0.75
        mute()
        record()
        HAL.writes = []
        HAL.levels[microphone] = 0.005
        notify()
        suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0 && HAL.writes == [microphone]
                     && HAL.levels[secondInput] == 0 && QuickToolHUD.messages.isEmpty,
                     "a small gain echo after verified zero is corrected without releasing the other microphone")
        HAL.levels[microphone] = 0.7
        notify()
        suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                     && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                     "the next call opening after the corrected echo restores both microphones")

        for virtual in [false, true] {
            prepare()
            let service = MicMuteService(uptime: { 100 })
            MicMuteService.shared = service
            HAL.devices = [10, 20]
            HAL.virtual = virtual ? [10] : []
            HAL.running = [10]
            let channel = HAL.key(10, 1)
            HAL.levels[channel] = 0.25
            HAL.levels[secondInput] = 0.75
            mute()
            record()
            HAL.writes = []
            for _ in 0..<10 {
                HAL.levels[microphone] = 0.005
                notify()
            }
            suite.expect((1..<10).contains(HAL.writes.filter { $0 == microphone }.count)
                         && service.isMuted && service.hasUnconfirmedInputs && HAL.levels[microphone] == 0.005
                         && HAL.levels[secondInput] == 0 && QuickToolHUD.messages.isEmpty,
                         "repeated residual callbacks during capture limit writes and display unconfirmed coverage")
            HAL.writes = []
            HAL.levels[channel] = 0.4
            suite.expect(HAL.notifyIfRegistered(channel), "a different channel reports its real gain change")
            DispatchQueue.drain()
            suite.expect(service.isMuted && HAL.levels[channel] == 0 && HAL.writes == [channel],
                         "a residual cooldown still corrects another channel immediately")
            if virtual {
                service.setMuted(false)
                DispatchQueue.drain()
            } else {
                record(20)
                HAL.levels[secondInput] = 0.8
                notify(20)
            }
            suite.expect(!service.isMuted && !service.hasUnconfirmedInputs && HAL.levels[microphone] == 0.5
                         && HAL.levels[channel] == 0.25 && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                         "a residual cooldown permits manual unmute or a call opening on the other confirmed input")
        }

        for preference: Bool? in [nil, false] {
            prepare(preference)
            HAL.devices = [10, 20]
            HAL.levels[secondInput] = 0.75
            mute()
            record()
            HAL.levels[microphone] = 0.7
            notify()
            suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0
                            && HAL.levels[secondInput] == 0 && HAL.processListReads == 0
                            && QuickToolHUD.messages.isEmpty,
                         "the default and disabled settings hold the global mute during another app's capture")
        }

        for handleResetOnMainFirst in [false, true] {
            prepare()
            HAL.devices = [10, 20]
            HAL.levels[secondInput] = 0.75
            mute()
            let service = MicMuteService.shared
            signal(10, selector: kAudioDevicePropertyVolumeScalar)
            DispatchQueue.main.run()
            suite.expect(service.applyInFlight && !service.halQueue.work.isEmpty,
                         "the call-following sweep is on the audio queue before the service reset")

            // The restarted service reuses the same IDs and UIDs. The old
            // sweep must not treat these new values as a call app unmuting.
            HAL.levels[microphone] = 0.7
            record()
            HAL.writes = []
            resetAudioService()
            if handleResetOnMainFirst { DispatchQueue.main.run() }
            service.halQueue.run()
            DispatchQueue.drain()
            suite.expect(service.isMuted && HAL.levels[microphone] == 0 && HAL.levels[secondInput] == 0
                         && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                         "a queued pre-reset sweep cannot release either microphone across an audio restart")
            HAL.levels[microphone] = 0.7
            notify()
            suite.expect(!service.isMuted && HAL.levels[microphone] == 0.5 && HAL.levels[secondInput] == 0.75,
                         "a fresh unmute by the recording app still restores both inputs after reset")
        }

        prepare()
        mute()
        record()
        HAL.levels[microphone] = 0.7
        signal(10, selector: kAudioDevicePropertyVolumeScalar)
        DispatchQueue.main.run()
        MicMuteService.shared.halQueue.run()
        suite.expect(HAL.levels[microphone] == 0.5 && !MicMuteService.shared.hasOutstandingClaims,
                     "the call's unmute restores the saved gain before publication")
        resetAudioService()
        DispatchQueue.drain()
        suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5,
                     "a reset after the call's committed unmute keeps the microphone open")

        prepare(false)
        mute()
        record()
        HAL.levels[microphone] = 0.7
        UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteFollowCallApps)
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0 && QuickToolHUD.messages.isEmpty,
                     "enabling call following during mute establishes the quiet input before accepting changes")
        HAL.levels[microphone] = 0.7
        notify()
        suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                        && QuickToolHUD.messages == ["unmuted"],
                     "the next click is followed after changing the preference during an active mute")

        for switchOnly in [false, true] {
            prepare()
            HAL.mute[10] = 0
            let priorLifetime = MicMuteService.shared.inputVolumeAdjustmentLifetime
            mute()
            record()
            notify()
            suite.expect(HAL.processListReads == 0 && HAL.mute[10] == 1 && HAL.levels[microphone] == 0,
                         "a microphone that is still quiet does not need a process-list lookup")
            if switchOnly {
                HAL.mute[10] = 0
                notify(selector: kAudioDevicePropertyMute)
            } else {
                HAL.levels[microphone] = 0.7
                notify()
            }
            suite.expect(!MicMuteService.shared.isMuted && !MicMuteService.shared.applyInFlight
                            && !UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive)
                            && HAL.levels[microphone] == 0.5 && HAL.mute[10] == 0
                            && QuickToolHUD.messages == ["unmuted"],
                         "with call following enabled, a gain change or switch release restores the saved controls")
            var staleGainApplied = false
            var currentGainApplied = false
            if let priorLifetime {
                MicMuteService.shared.withUnmutedInput(lifetime: priorLifetime) { staleGainApplied = true }
            }
            if let restoredLifetime = MicMuteService.shared.inputVolumeAdjustmentLifetime {
                MicMuteService.shared.withUnmutedInput(lifetime: restoredLifetime) { currentGainApplied = true }
            }
            suite.expect(priorLifetime != nil && !staleGainApplied && currentGainApplied,
                         "following a call releases gain adjustment with a new lifetime")
            mute()
            suite.expect(MicMuteService.shared.isMuted && HAL.mute[10] == 1 && HAL.levels[microphone] == 0,
                         "the shortcut can mute again after following a call app")
        }

        let otherProcesses: [(String, [(UInt32, Int32, Bool, [UInt32])])] = [
            ("nobody", []),
            ("this app", [(100, ownPID, true, [10])]),
            ("an idle app", [(100, callPID, false, [10])]),
            ("a different input", [(100, callPID, true, [20])]),
        ]
        for (label, processes) in otherProcesses {
            prepare()
            mute()
            HAL.processes = processes
            HAL.levels[microphone] = 0.7
            notify()
            suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0
                            && QuickToolHUD.messages.isEmpty,
                         "an external gain change leaves mute active with \(label)")
        }

        prepare()
        HAL.devices = [10, 20]
        HAL.levels[secondInput] = 0.75
        mute()
        record()
        HAL.levels[microphone] = 0.7
        HAL.writes = []
        HAL.afterProcessListRead = { HAL.levels[microphone] = 0 }
        notify()
        suite.expect(HAL.processListReads > 0 && MicMuteService.shared.isMuted && HAL.levels[microphone] == 0
                        && HAL.levels[secondInput] == 0 && HAL.writes.isEmpty && QuickToolHUD.messages.isEmpty,
                     "a call that silences the microphone again during the process query stays muted")

        prepare()
        HAL.uids[10] = "old input"
        mute()
        record()
        HAL.levels[microphone] = 0.7
        HAL.afterProcessListRead = {
            HAL.uids[10] = "replacement input"
            HAL.levels[microphone] = 0.8
        }
        notify()
        suite.expect(HAL.processListReads > 0 && MicMuteService.shared.isMuted && HAL.levels[microphone] == 0
                        && QuickToolHUD.messages.isEmpty,
                     "reusing the opened device ID during the process lookup mutes the replacement as a new input")
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.8
                        && UserDefaults.standard.stringArray(forKey: DefaultsKey.micMuteMutedDevices) == ["old input"],
                     "the replacement gets its own level back and the detached microphone keeps its restore claim")

        prepare()
        HAL.devices = [10, 20]
        HAL.levels[secondInput] = 0.75
        mute()
        record()
        HAL.levels[microphone] = 0.7
        HAL.writes = []
        HAL.afterProcessListRead = { MicMuteService.shared.setMuted(true) }
        notify()
        suite.expect(HAL.processListReads > 0 && MicMuteService.shared.isMuted && HAL.levels[microphone] == 0
                        && HAL.levels[secondInput] == 0 && !HAL.writes.contains(secondInput)
                        && QuickToolHUD.messages == ["muted"],
                     "a new mute requested during detection prevents even a temporary restore on the other input")

        prepare()
        mute()
        record()
        HAL.levels[microphone] = 0.7
        signal(10, selector: kAudioDevicePropertyVolumeScalar)
        DispatchQueue.main.run()
        MicMuteService.shared.halQueue.run()
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0
                        && QuickToolHUD.messages == ["muted"],
                     "a newer manual mute wins before the call's unmute can be announced")

        prepare()
        HAL.devices = [10, 20]
        HAL.levels[secondInput] = 0.75
        HAL.mute[10] = 0
        mute()
        record()
        HAL.readFails.insert(microphone)
        notify()
        suite.expect(MicMuteService.shared.isMuted && HAL.mute[10] == 1 && HAL.levels[secondInput] == 0
                        && QuickToolHUD.messages.isEmpty,
                     "an unreadable gain cannot release another muted input while the first is recording")

        for disconnectWasDelivered in [true, false] {
            prepare()
            HAL.uids[10] = "USB headset"
            mute()
            if disconnectWasDelivered {
                HAL.devices = []
                topologyChanged()
            }
            HAL.devices = [20]
            HAL.uids[20] = "USB headset"
            HAL.levels[secondInput] = 0.8
            record(20)
            topologyChanged()
            suite.expect(MicMuteService.shared.isMuted && HAL.levels[secondInput] == 0 && QuickToolHUD.messages.isEmpty,
                         "a returning UID on a new audio object starts muted even when a call is recording from it")
            HAL.levels[secondInput] = 0.7
            notify(20)
            suite.expect(!MicMuteService.shared.isMuted && HAL.levels[secondInput] == 0.5,
                         "a fresh unmute on the returning headset restores the original saved level")
        }

        let otherStreams = HAL.key(30, 0, kAudioDevicePropertyStreams)
        enum Reconnect: CaseIterable {
            case headsetOnly, withNewDevice, oldGainAfterList, oldGainDuringRemoval, oldGainDuringRegistration
        }
        func checkReconnect(_ reconnect: Reconnect, followCalls: Bool, partialInventory: Bool) {
            prepare(followCalls)
            HAL.devices = [10, 20, 30]
            // Exercise both a partial first inventory and an input that
            // becomes unreadable only when the headset reconnects.
            if partialInventory && !followCalls { HAL.sizeReadFails = [otherStreams] }
            HAL.levels[secondInput] = 0.75
            mute()
            record()

            guard let oldGain = HAL.pendingNotification(for: microphone) else {
                suite.expect(false, "the headset has a gain listener before disconnecting")
                return
            }
            HAL.dropListeners(forDevice: 10)
            if reconnect != .headsetOnly { HAL.devices.append(40) }
            if partialInventory { HAL.sizeReadFails = [otherStreams] }
            HAL.levels[microphone] = 0.8
            HAL.writes = []
            var reopenedDuringRenewal = false
            let reopen = {
                reopenedDuringRenewal = HAL.levels[microphone] == 0
                HAL.levels[microphone] = 0.9
                if reconnect != .withNewDevice { oldGain() }
            }
            switch reconnect {
            case .withNewDevice, .oldGainDuringRemoval: HAL.afterListenerRemoval[microphone] = reopen
            case .oldGainDuringRegistration: HAL.afterListenerAdd[microphone] = reopen
            case .headsetOnly, .oldGainAfterList: break
            }
            suite.expect(HAL.notifyIfRegistered(devicesChanged), "the HAL announces the headset reconnection")
            if reconnect == .oldGainAfterList { oldGain() }
            DispatchQueue.drain()
            if reconnect != .headsetOnly && reconnect != .oldGainAfterList {
                suite.expect(reopenedDuringRenewal, "the headset reopened after being silenced during listener renewal")
            }
            suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0
                            && HAL.levels[secondInput] == 0 && !HAL.writes.contains(secondInput)
                            && QuickToolHUD.messages.isEmpty,
                         "\(reconnect) keeps both inputs muted (partial inventory: \(partialInventory), follow calls: \(followCalls))")

            HAL.levels[microphone] = 0.7
            suite.expect(HAL.notifyIfRegistered(microphone), "the reconnected headset delivers its next gain change")
            DispatchQueue.drain()
            if followCalls {
                suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                                && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                             "a fresh unmute from the call restores both saved gains after reconnect")
            } else {
                suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0
                                && HAL.levels[secondInput] == 0 && QuickToolHUD.messages.isEmpty,
                             "with call following off, the next gain change still leaves both inputs muted")
            }
        }

        for partialInventory in [false, true] {
            for followCalls in [false, true] {
                for reconnect in Reconnect.allCases {
                    checkReconnect(reconnect, followCalls: followCalls, partialInventory: partialInventory)
                }
            }
        }

        func notifyRegistered(_ property: Key) {
            suite.expect(HAL.notifyIfRegistered(property), "the HAL delivers the change to a registered listener")
            DispatchQueue.drain()
        }
        let defaultInput = HAL.key(AudioObjectID(kAudioObjectSystemObject), 0, kAudioHardwarePropertyDefaultInputDevice,
                                   scope: kAudioObjectPropertyScopeGlobal)
        let channelGain = HAL.key(10, 3)
        enum GainDelivery: CaseIterable { case afterConfirmation, oldAtAdd, newAtAdd, pendingAtRemoval, noNotification }
        for delivery in GainDelivery.allCases {
            prepare()
            HAL.devices = [10, 20]
            HAL.streamChannels[10] = [3]
            HAL.levels[channelGain] = 0.625
            HAL.levels[secondInput] = 0.75
            mute()
            record()
            guard let oldGain = HAL.pendingNotification(for: channelGain) else {
                suite.expect(false, "the original channel has a gain listener")
                continue
            }
            HAL.writes = []
            if delivery == .pendingAtRemoval {
                // The sweep already read the quiet channel under its original registration.
                HAL.afterGainRead[secondInput] = {
                    oldGain()
                    HAL.levels[channelGain] = nil
                }
            } else {
                HAL.levels[channelGain] = nil
            }
            // A normal sweep discovers the disappearing property without a device-list or layout callback.
            suite.expect(HAL.notifyIfRegistered(defaultInput), "the HAL requests an inventory check")
            DispatchQueue.main.run()
            MicMuteService.shared.halQueue.run()
            suite.expect(!HAL.listeners.contains(channelGain) && HAL.afterGainRead[secondInput] == nil,
                         "the obsolete registration is removed even when its delivery is already queued")
            if delivery != .pendingAtRemoval { DispatchQueue.drain() }

            HAL.levels[channelGain] = 0
            if delivery != .afterConfirmation {
                HAL.afterListenerAdd[channelGain] = {
                    HAL.levels[channelGain] = 0.8
                    if delivery == .oldAtAdd { oldGain() }
                    if delivery == .newAtAdd {
                        suite.expect(HAL.notifyIfRegistered(channelGain), "the replacement reports gain during its installation")
                    }
                }
            }
            if delivery == .pendingAtRemoval {
                // Preference sync reconciles listeners while the first sweep is still awaiting publication.
                MicMuteService.shared.syncWithPreferences()
                MicMuteService.shared.halQueue.run()
                suite.expect(HAL.listeners.contains(channelGain), "the replacement is installed before the queued notice is processed")
            }
            notifyRegistered(defaultInput)
            suite.expect(HAL.listeners.contains(channelGain) && HAL.afterListenerAdd[channelGain] == nil,
                         "the same channel address is registered again on the same input")
            if delivery == .afterConfirmation {
                suite.expect(HAL.levels[channelGain] == 0 && MicMuteService.shared.isMuted,
                             "the replacement channel has settled at zero before the old callback arrives")
                HAL.levels[channelGain] = 0.8
                oldGain()
                DispatchQueue.drain()
            }
            suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0 && HAL.levels[channelGain] == 0
                         && HAL.levels[secondInput] == 0 && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                         "a replaced channel cannot release mute from an unconfirmed opening or an old delivery (\(delivery))")
            HAL.levels[channelGain] = 0.7
            notifyRegistered(channelGain)
            suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5 && HAL.levels[channelGain] == 0.625
                         && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                         "a new delivery from the confirmed replacement restores the saved gains")
        }

        prepare()
        mute()
        let retiredGain = HAL.pendingNotification(for: microphone)
        let oldClient = HAL.soleListenerClient(for: microphone)
        suite.expect(AudioListenerClients.owner(of: oldClient) === MicMuteService.shared,
                     "the original gain listener has a registered service owner")
        HAL.failedListenerRemovals = [microphone]
        MicMuteService.shared.unmuteForTeardown()
        DispatchQueue.drain()
        suite.expect(oldClient != nil && HAL.soleListenerClient(for: microphone) == oldClient
                     && AudioListenerClients.owner(of: oldClient) == nil,
                     "the refused HAL removal retains the opaque client but releases its owner registration")
        suite.expect(retiredGain != nil && HAL.notifyIfRegistered(microphone) && DispatchQueue.main.work.isEmpty
                     && !MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5,
                     "a refused removal can still deliver after teardown without waking the main queue")
        HAL.failedListenerRemovals = []
        HAL.listenerAdds = []
        HAL.listenerRemovals = []
        mute()
        let newClient = HAL.soleListenerClient(for: microphone)
        suite.expect(newClient != oldClient && AudioListenerClients.owner(of: newClient) === MicMuteService.shared,
                     "reactivation registers a distinct opaque client owned by the service")
        record()
        HAL.levels[microphone] = 0.8
        retiredGain?()
        DispatchQueue.drain()
        suite.expect(HAL.listenerRemovals.contains(microphone) && HAL.listenerAdds.contains(microphone)
                     && MicMuteService.shared.isMuted && HAL.levels[microphone] == 0 && QuickToolHUD.messages.isEmpty,
                     "reactivation replaces the retired listener and rejects its old delivery as an unmute")
        HAL.levels[microphone] = 0.7
        notifyRegistered(microphone)
        suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5 && QuickToolHUD.messages == ["unmuted"],
                     "the replacement gain listener follows the next real click after reactivation")
        suite.expect(newClient != nil && !HAL.listeners.contains(microphone) && AudioListenerClients.owner(of: newClient) == nil,
                     "unmute releases the replacement's HAL registration and registry entry")

        prepare()
        HAL.devices = [10, 20]
        HAL.streamChannels[10] = [3]
        let firstChannel = HAL.key(10, 1)
        HAL.levels[firstChannel] = 0.25
        HAL.levels[channelGain] = 0.625
        HAL.levels[secondInput] = 0.75
        mute()
        record()
        HAL.writes = []
        HAL.levels[channelGain] = 0.8
        suite.expect(HAL.notifyIfRegistered(firstChannel, changes: [firstChannel, channelGain]),
                     "the first channel's registration delivers a mixed address array")
        DispatchQueue.drain()
        suite.expect(MicMuteService.shared.isMuted && HAL.levels[firstChannel] == 0 && HAL.levels[channelGain] == 0
                     && HAL.levels[secondInput] == 0 && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                     "an extra address in another channel's delivery cannot authorize the open channel")
        HAL.levels[channelGain] = 0.7
        suite.expect(HAL.notifyIfRegistered(channelGain, changes: [firstChannel, channelGain]),
                     "the third channel's own registration reports its changed gain in a mixed delivery")
        DispatchQueue.drain()
        suite.expect(!MicMuteService.shared.isMuted && HAL.levels[firstChannel] == 0.25 && HAL.levels[channelGain] == 0.625
                     && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                     "the registration's own address remains valid within a mixed callback")

        for topology in [HAL.key(10, 0, kAudioDevicePropertyStreams),
                         HAL.key(10, 0, kAudioObjectPropertyControlList, scope: kAudioObjectPropertyScopeGlobal)] {
            prepare()
            HAL.devices = [10, 20]
            HAL.streamChannels[10] = [3]
            HAL.levels[channelGain] = 0.625
            HAL.levels[secondInput] = 0.75
            mute()
            record()
            let delayedTopology = HAL.pendingNotification(for: topology)
            HAL.levels[channelGain] = 0.8
            HAL.writes = []
            suite.expect(HAL.notifyIfRegistered(channelGain, changes: [channelGain, topology]),
                         "the gain listener reports the opening and a structural change in one delivery")
            DispatchQueue.drain()
            suite.expect(delayedTopology != nil && MicMuteService.shared.isMuted && HAL.levels[microphone] == 0
                         && HAL.levels[channelGain] == 0 && HAL.levels[secondInput] == 0
                         && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                         "the mixed delivery keeps both inputs muted before the dedicated topology callback arrives")
            delayedTopology?()
            DispatchQueue.drain()
            suite.expect(MicMuteService.shared.isMuted && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                         "the delayed topology delivery cannot release the other input")
            HAL.levels[channelGain] = 0.7
            notifyRegistered(channelGain)
            suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5 && HAL.levels[channelGain] == 0.625
                         && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                         "the next confirmed gain click restores both inputs after a mixed structural delivery")
        }

        for clickInInventory in [false, true] {
            prepare()
            HAL.devices = [10, 20]
            HAL.levels[secondInput] = 0.75
            mute()
            record()
            HAL.writes = []
            var deliveries = 0
            var deliveriesBeforeSilence: Int?
            func changeGainDuringRead() {
                deliveries += 1
                HAL.levels[microphone] = deliveries.isMultiple(of: 2) ? 0.7 : 0.9
                suite.expect(HAL.notifyIfRegistered(microphone), "the active gain listener reports the changing level")
                if deliveries < 48 { HAL.afterGainRead[microphone] = changeGainDuringRead }
            }
            HAL.afterGainRead[microphone] = changeGainDuringRead
            var silentReads = 0
            var quietCallbacks = 0
            var clickedDuringInventory = false
            var overwroteClick = false
            func observeSilence() {
                guard HAL.levels[microphone] == 0 else { return }
                silentReads += 1
                if !clickInInventory && HAL.notifyIfRegistered(microphone) { quietCallbacks += 1 }
                if silentReads < 8 { HAL.afterGainRead[microphone] = observeSilence }
            }
            HAL.beforeControlWrite = { key, value in
                if clickedDuringInventory && key == microphone && value == 0 { overwroteClick = true }
            }
            HAL.afterWrite = {
                if HAL.levels[microphone] == 0 { deliveriesBeforeSilence = deliveries }
                HAL.afterGainRead[microphone] = observeSilence
                if clickInInventory {
                    HAL.afterUIDRead = {
                        guard silentReads >= 2 else { return }
                        HAL.afterGainRead[microphone] = nil
                        HAL.levels[microphone] = 0.8
                        clickedDuringInventory = HAL.notifyIfRegistered(microphone)
                    }
                }
            }
            HAL.levels[microphone] = 0.7
            notifyRegistered(microphone)
            suite.expect((1...16).contains(deliveriesBeforeSilence ?? 0),
                         "a continuously changing gain is silenced after bounded work while callbacks are still arriving")
            if clickInInventory {
                suite.expect(clickedDuringInventory && !overwroteClick, "a click after the storm's confirmed mute survives reconciliation")
            } else {
                suite.expect(quietCallbacks >= 2 && MicMuteService.shared.isMuted && HAL.levels[microphone] == 0
                             && HAL.levels[secondInput] == 0 && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                             "more gain callbacks without an opening cannot release either input after the forced mute")
                HAL.levels[microphone] = 0.7
                notifyRegistered(microphone)
            }
            suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                         && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                         "the first stable click after the gain callback storm restores both inputs")
        }

        enum DuringScan: CaseIterable {
            case beforeHeadsetRead, afterHeadsetRead, defaultInputOnly, rereadQuietChannel, processLookup, quietNoticeBeforeLookup
        }
        for moment in DuringScan.allCases {
            prepare()
            HAL.devices = moment == .beforeHeadsetRead || moment == .defaultInputOnly ? [20, 10] : [10, 20]
            HAL.streamChannels[10] = [3]
            HAL.levels[firstChannel] = 0.25
            HAL.levels[channelGain] = 0.625
            HAL.levels[secondInput] = 0.75
            mute()
            record()
            var delivered = false
            func clickThirdChannel() {
                HAL.levels[channelGain] = 0.8
                delivered = HAL.notifyIfRegistered(channelGain)
            }
            switch moment {
            case .beforeHeadsetRead, .afterHeadsetRead, .defaultInputOnly:
                HAL.afterGainRead[secondInput] = clickThirdChannel
                notifyRegistered(moment == .defaultInputOnly ? defaultInput : secondInput)
            case .rereadQuietChannel:
                HAL.afterGainRead[secondInput] = {
                    suite.expect(HAL.notifyIfRegistered(firstChannel), "the quiet first channel notifies after its initial read")
                    HAL.afterGainRead[firstChannel] = clickThirdChannel
                }
                notifyRegistered(defaultInput)
            case .processLookup, .quietNoticeBeforeLookup:
                HAL.levels[firstChannel] = 0.7
                HAL.writes = []
                if moment == .quietNoticeBeforeLookup {
                    suite.expect(HAL.levels[channelGain] == 0 && HAL.notifyIfRegistered(channelGain),
                                 "the third channel reports zero in the same batch as the first channel's opening")
                }
                HAL.afterProcessListRead = {
                    HAL.levels[firstChannel] = 0
                    if moment == .processLookup {
                        clickThirdChannel()
                    } else {
                        HAL.levels[channelGain] = 0.8
                    }
                }
                notifyRegistered(firstChannel)
                if moment == .quietNoticeBeforeLookup {
                    suite.expect(HAL.afterProcessListRead == nil && MicMuteService.shared.isMuted && HAL.levels[microphone] == 0
                                 && HAL.levels[firstChannel] == 0 && HAL.levels[channelGain] == 0 && HAL.levels[secondInput] == 0
                                 && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                                 "a third-channel opening without a new callback cannot reuse its earlier quiet notification")
                    clickThirdChannel()
                    DispatchQueue.drain()
                }
            }
            suite.expect(delivered && !MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                         && HAL.levels[firstChannel] == 0.25 && HAL.levels[channelGain] == 0.625
                         && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                         "the new third-channel click during \(moment) restores all saved gains without a second click")
        }

        enum AfterMuteWrite: CaseIterable {
            case setter, firstReadback, verifying, residualReadback, readingChannel, failedFirstReadback, inventory, installingOtherListener, topology
        }
        let headsetSwitch = HAL.key(10, 0, kAudioDevicePropertyMute)
        for control in [microphone, headsetSwitch] {
            let isSwitch = control == headsetSwitch
            let moments: [AfterMuteWrite] = isSwitch ? [.verifying, .inventory] : AfterMuteWrite.allCases
            for moment in moments {
                prepare()
                HAL.devices = [10, 20]
                HAL.levels[secondInput] = 0.75
                if isSwitch {
                    HAL.levels[microphone] = nil
                    HAL.mute[10] = 0
                }
                if moment == .readingChannel || moment == .failedFirstReadback { HAL.levels[firstChannel] = 0.25 }
                mute()
                record()
                let client = HAL.soleListenerClient(for: control)
                let newControl = HAL.key(20, 1)
                if moment == .installingOtherListener { HAL.levels[newControl] = 0 }
                if isSwitch { HAL.mute[10] = 0 } else { HAL.levels[microphone] = 0.9 } // Unreported drift.
                HAL.writes = []
                var started = false
                var delivered = false
                var closedAfterClick = false
                var silentReads = 0
                let quietGain: Float = moment == .residualReadback ? 0.005 : 0
                func click() {
                    HAL.afterGainRead[control] = nil
                    HAL.afterSwitchRead[control] = nil
                    if moment == .topology {
                        suite.expect(HAL.notifyIfRegistered(devicesChanged), "the list changes after the verified write")
                    }
                    if isSwitch { HAL.mute[10] = 0 } else { HAL.levels[microphone] = 0.8 }
                    delivered = HAL.soleListenerClient(for: control) == client && HAL.notifyIfRegistered(control)
                }
                func observeNextRead() {
                    if isSwitch { HAL.afterSwitchRead[control] = sawRead } else { HAL.afterGainRead[control] = sawRead }
                }
                func sawRead() {
                    guard isSwitch ? HAL.mute[10] == 1 : HAL.levels[control] == quietGain else { return }
                    silentReads += 1
                    if moment == .firstReadback || ((moment == .verifying || moment == .residualReadback) && silentReads == 2) {
                        click()
                    } else if moment == .readingChannel || moment == .failedFirstReadback {
                        HAL.afterGainRead[firstChannel] = click
                    } else {
                        observeNextRead()
                    }
                }
                HAL.beforeControlWrite = { key, value in
                    guard key == control, value == (isSwitch ? 1 : 0) else { return }
                    if delivered { closedAfterClick = true }
                    guard !started else { return }
                    started = true
                    observeNextRead()
                    switch moment {
                    case .setter: HAL.afterWrite = click
                    case .residualReadback: HAL.afterWrite = { HAL.levels[control] = quietGain }
                    case .failedFirstReadback: HAL.nextReadFails.insert(control)
                    case .inventory, .topology: HAL.afterUIDRead = click
                    case .installingOtherListener: HAL.afterListenerAdd[newControl] = click
                    default: break
                    }
                }
                notifyRegistered(secondInput)
                suite.expect(client != nil && delivered, "the original registration delivers the click during \(moment)")
                if moment == .inventory {
                    suite.expect(silentReads >= 2, "both post-write silence reads precede the inventory callback")
                }
                if moment == .setter || moment == .firstReadback || moment == .residualReadback || moment == .topology {
                    suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0 && HAL.levels[secondInput] == 0
                                 && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                                 "an unverified opening during \(moment) keeps the other mic silent")
                    HAL.levels[microphone] = 0.8
                    notifyRegistered(microphone)
                } else {
                    suite.expect(!closedAfterClick, "a click on the confirmed control during \(moment) is never overwritten")
                }
                suite.expect(!MicMuteService.shared.isMuted && (isSwitch ? HAL.mute[10] == 0 : HAL.levels[microphone] == 0.5)
                             && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                             "the first confirmed click during or after \(moment) restores both inputs and announces once")
            }
        }

        for readOnlyChannel in [false, true] {
            prepare()
            HAL.devices = [10, 20]
            HAL.streamChannels[10] = [3]
            HAL.levels[secondInput] = 0.75
            HAL.levels[firstChannel] = readOnlyChannel ? 0 : 0.25
            HAL.levels[channelGain] = 0.625
            if readOnlyChannel { HAL.readOnly = [firstChannel] }
            mute()
            record()
            HAL.levels[microphone] = 0.9
            HAL.levels[firstChannel] = 0.7
            var receivedClick = false
            var overwroteClick = false
            HAL.afterWrite = {
                guard HAL.writes.last == microphone, HAL.levels[microphone] == 0 else { return }
                HAL.levels[firstChannel] = 0 // The master setter also silences this channel.
                HAL.afterGainRead[firstChannel] = {
                    guard HAL.levels[firstChannel] == 0 else { return }
                    HAL.afterGainRead[channelGain] = {
                        HAL.levels[firstChannel] = 0.8
                        receivedClick = HAL.notifyIfRegistered(firstChannel)
                    }
                }
            }
            HAL.beforeControlWrite = { key, value in
                if receivedClick && key == firstChannel && value == 0 { overwroteClick = true }
            }
            notifyRegistered(secondInput)
            suite.expect(receivedClick && !overwroteClick && !MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                         && HAL.levels[firstChannel] == (readOnlyChannel ? 0.8 : 0.25) && HAL.levels[channelGain] == 0.625
                         && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                         "the first click after reading an indirectly silenced channel restores both inputs (read-only: \(readOnlyChannel))")
        }

        enum DuringMuteWrite: CaseIterable {
            case preparingGains, preparingSwitch, finalSettableCheck, betweenChannels, quietReadAfterWrite, betweenInputs, followingDisabled
        }
        for moment in DuringMuteWrite.allCases {
            let follows = moment != .followingDisabled
            let headsetSwitch = HAL.key(10, 0, kAudioDevicePropertyMute)
            let otherChannel = HAL.key(20, 3)
            prepare(follows)
            HAL.devices = [10, 20]
            HAL.streamChannels = [10: [3], 20: [3]]
            HAL.levels[firstChannel] = 0.25
            HAL.levels[channelGain] = 0.625
            HAL.levels[secondInput] = 0.75
            HAL.levels[otherChannel] = 0.375
            if moment == .preparingSwitch { HAL.mute[10] = 0 }
            mute()
            record()
            if moment == .betweenInputs { HAL.processes[0].devices = [10, 20] }

            var delivered = false
            var closedAfterClick: [Key] = []
            HAL.beforeControlWrite = { key, value in
                if delivered && value == (key.s == kAudioDevicePropertyMute ? 1 : 0) { closedAfterClick.append(key) }
            }
            func click(_ control: Key) {
                if control == headsetSwitch {
                    HAL.mute[10] = 0
                } else {
                    HAL.levels[control] = 0.8
                }
                delivered = HAL.notifyIfRegistered(control)
            }
            HAL.levels[microphone] = 0.9 // Unreported drift; only the still-quiet first channel starts the sweep.
            switch moment {
            case .preparingGains, .preparingSwitch, .followingDisabled:
                HAL.afterGainRead[microphone] = {
                    HAL.afterGainRead[microphone] = { click(moment == .preparingSwitch ? headsetSwitch : channelGain) }
                }
            case .finalSettableCheck:
                // The snapshot asks whether this control is writable. The next
                // check on the same address is the driver's last query before Set.
                HAL.afterSettableCheck[microphone] = {
                    HAL.afterSettableCheck[microphone] = { click(channelGain) }
                }
            case .betweenChannels:
                HAL.afterWrite = { click(channelGain) }
            case .quietReadAfterWrite:
                // The channel read returned zero, so this control needs no Set.
                // The app opens it before the service can finish verifying silence.
                HAL.afterWrite = { HAL.afterGainRead[channelGain] = { click(channelGain) } }
            case .betweenInputs:
                HAL.levels[secondInput] = 0.9
                HAL.afterWrite = {
                    // Whichever drifting main gain was silenced first, open a
                    // confirmed, quiet channel on the other recording input.
                    click(HAL.writes.last?.d == microphone.d ? otherChannel : channelGain)
                }
            }
            notifyRegistered(firstChannel)
            suite.expect(delivered, "the recording app delivers its registered control callback during \(moment)")
            if follows {
                suite.expect(closedAfterClick.isEmpty,
                             "no control even transiently receives a mute write after the valid click during \(moment)")
                suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                             && HAL.levels[firstChannel] == 0.25 && HAL.levels[channelGain] == 0.625
                             && HAL.levels[secondInput] == 0.75 && HAL.levels[otherChannel] == 0.375
                             && (moment != .preparingSwitch || HAL.mute[10] == 0) && QuickToolHUD.messages == ["unmuted"],
                             "a single click during \(moment) restores both inputs and announces the release once")
            } else {
                suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0 && HAL.levels[channelGain] == 0
                             && HAL.levels[secondInput] == 0 && HAL.levels[otherChannel] == 0
                             && HAL.processListReads == 0 && QuickToolHUD.messages.isEmpty,
                             "with following disabled the same late click is silenced without a release")
            }
        }

        prepare()
        HAL.devices = [10, 20]
        HAL.streamChannels[10] = [3]
        HAL.levels[firstChannel] = 0.25
        HAL.levels[channelGain] = 0.625
        HAL.levels[secondInput] = 0.75
        mute()
        record()
        HAL.levels[microphone] = 0.9
        HAL.writeFails = [microphone]
        HAL.writes = []
        var quietDeliveries = 0
        var deliveriesAtAttempt: Int?
        func reportQuietChannel() {
            if HAL.notifyIfRegistered(firstChannel) { quietDeliveries += 1 }
            if quietDeliveries < 48 { HAL.afterSettableCheck[microphone] = reportQuietChannel }
        }
        HAL.afterSettableCheck[microphone] = reportQuietChannel
        HAL.beforeControlWrite = { key, value in
            if key == microphone && value == 0 && deliveriesAtAttempt == nil {
                deliveriesAtAttempt = quietDeliveries
                HAL.afterSettableCheck[microphone] = nil
            }
        }
        notifyRegistered(firstChannel)
        suite.expect((1...16).contains(deliveriesAtAttempt ?? 0) && (1...8).contains(HAL.writes.count)
                     && MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.9 && HAL.levels[secondInput] == 0
                     && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                     "notifications during write preparation cannot postpone a refused mute indefinitely or release the other mic")
        HAL.writeFails = []
        notifyRegistered(firstChannel)
        suite.expect(HAL.levels[microphone] == 0 && MicMuteService.shared.isMuted && QuickToolHUD.messages.isEmpty,
                     "the drift is silenced once the driver accepts the mute write")
        HAL.levels[channelGain] = 0.8
        notifyRegistered(channelGain)
        suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5 && HAL.levels[channelGain] == 0.625
                     && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                     "a new stable click after the refusal restores both inputs")

        let newMain = HAL.key(30)
        let newChannel = HAL.key(30, 1)
        for unreadableAfterError in [false, true] {
            prepare()
            HAL.devices = [10, 20]
            HAL.streamChannels[10] = [3]
            HAL.levels[channelGain] = 0.625
            HAL.levels[secondInput] = 0.75
            mute()
            record()
            // The sweep discovers a third mic before any device-list callback.
            HAL.devices.insert(30, at: 0)
            HAL.levels[newMain] = 0.375
            HAL.levels[newChannel] = 0.875
            HAL.writes = []
            var clickedAfterNewWrite = false
            var closedAgain = false
            var refusedRestores: Set<UInt32> = []
            func clickAfterChangingNewInput(_ changed: Key) {
                guard changed.d == 30, HAL.levels[changed] == 0 else { return }
                HAL.writeFails = Set(HAL.levels.keys)
                HAL.beforeControlWrite = { key, value in
                    if value == 0 { closedAgain = true } else { refusedRestores.insert(key.d) }
                }
                HAL.levels[channelGain] = 0.8
                clickedAfterNewWrite = HAL.notifyIfRegistered(channelGain)
            }
            if unreadableAfterError {
                HAL.beforeControlWrite = { key, value in
                    guard key.d == 30, value == 0 else { return }
                    // The setter changes the hardware before reporting an error.
                    // Its immediate readback also fails, then the control is readable again.
                    HAL.levels[key] = Float(value)
                    HAL.nextReadFails.insert(key)
                    clickAfterChangingNewInput(key)
                }
            } else {
                HAL.afterWrite = {
                    if let changed = HAL.writes.last { clickAfterChangingNewInput(changed) }
                }
            }
            suite.expect(HAL.notifyIfRegistered(secondInput), "the quiet second mic initiates discovery of the third mic")
            DispatchQueue.main.run()
            MicMuteService.shared.halQueue.run()
            // Inspect before a queued reassert can discover and snapshot the half-muted mic again.
            let saved = UserDefaults.standard.dictionary(forKey: DefaultsKey.micMuteSavedControls) as? [String: [String: Double]]
            let claims = UserDefaults.standard.stringArray(forKey: DefaultsKey.micMuteMutedDevices) ?? []
            let newSnapshot = ["\(newMain.s):\(newMain.e)": 0.375, "\(newChannel.s):\(newChannel.e)": 0.875]
            suite.expect(clickedAfterNewWrite && HAL.nextReadFails.isEmpty && !closedAgain
                         && refusedRestores == [10, 20, 30] && HAL.levels[secondInput] == 0,
                         "the third mic's first real gain write is followed only by attempted restores of all three inputs")
            suite.expect(saved?["device-30"] == newSnapshot && Set(claims) == ["device-10", "device-20", "device-30"],
                         "a wholly refused automatic restore retains the third mic's full pre-write snapshot and every claim")
            HAL.beforeControlWrite = nil
            DispatchQueue.drain()
            suite.expect(MicMuteService.shared.isMuted && !QuickToolHUD.messages.contains("unmuted"),
                         "a wholly refused release keeps the active mute")
            HAL.writeFails = []
            MicMuteService.shared.setMuted(false)
            DispatchQueue.drain()
            suite.expect(!MicMuteService.shared.isMuted && !MicMuteService.shared.hasOutstandingClaims
                         && HAL.levels[newMain] == 0.375 && HAL.levels[newChannel] == 0.875 && HAL.levels[microphone] == 0.5
                         && HAL.levels[channelGain] == 0.625 && HAL.levels[secondInput] == 0.75,
                         "a later manual unmute restores every original gain, including the interrupted third mic")
        }

        for trigger in [secondInput, devicesChanged] {
            for duringUIDRead in [false, true] {
                prepare()
                HAL.devices = [10, 20]
                HAL.levels[secondInput] = 0.75
                mute()
                HAL.devices.insert(30, at: 0)
                HAL.uids[30] = "input-X"
                HAL.levels[newMain] = 0.375
                var replacedAtListRead: Int?
                var topologyDelivered = false
                var wroteWithOldInventory = false
                func replaceInput() {
                    HAL.uids[30] = "input-Y"
                    HAL.levels[newMain] = 0.875
                    replacedAtListRead = HAL.deviceListReads
                    topologyDelivered = HAL.notifyIfRegistered(devicesChanged)
                }
                if duringUIDRead {
                    // X is first in the inventory; the HAL has copied its UID but has yet to return it.
                    HAL.afterUIDRead = replaceInput
                } else {
                    HAL.afterSettableCheck[newMain] = { HAL.afterSettableCheck[newMain] = replaceInput }
                }
                HAL.beforeControlWrite = { key, value in
                    if key == newMain && value == 0 && replacedAtListRead == HAL.deviceListReads { wroteWithOldInventory = true }
                }
                notifyRegistered(trigger)
                suite.expect(topologyDelivered && !wroteWithOldInventory && MicMuteService.shared.isMuted
                             && HAL.levels[newMain] == 0 && HAL.levels[secondInput] == 0 && QuickToolHUD.messages.isEmpty,
                             "the list callback invalidates the prepared setter before it can zero the replacement UID")
                MicMuteService.shared.setMuted(false)
                DispatchQueue.drain()
                suite.expect(!MicMuteService.shared.isMuted && HAL.levels[newMain] == 0.875 && HAL.levels[microphone] == 0.5
                             && HAL.levels[secondInput] == 0.75 && !MicMuteService.shared.hasOutstandingClaims,
                             "manual unmute restores the replacement's own gain and leaves no claim on the unwritten UID")
            }
        }

        enum DriverEcho: CaseIterable {
            case master, openChannel, channelOpensBeforeSet, masterAfterQuietChannel, quietAlias, unchangedResidual
        }
        for echo in DriverEcho.allCases {
            let driverNotice: Key
            switch echo {
            case .master, .masterAfterQuietChannel: driverNotice = microphone
            case .quietAlias, .unchangedResidual: driverNotice = firstChannel
            case .openChannel, .channelOpensBeforeSet: driverNotice = channelGain
            }
            prepare()
            HAL.devices = [10, 20]
            HAL.streamChannels[10] = [3]
            HAL.levels[channelGain] = 0.625
            if echo == .masterAfterQuietChannel || driverNotice == firstChannel { HAL.levels[firstChannel] = 0.25 }
            HAL.levels[secondInput] = 0.75
            mute()
            record()
            let unchangedMaster: Float = echo == .unchangedResidual ? 0.005 : 0.9
            HAL.levels[microphone] = unchangedMaster
            if echo == .openChannel || echo == .unchangedResidual {
                HAL.levels[channelGain] = 0.8
            }
            if echo == .channelOpensBeforeSet || echo == .unchangedResidual {
                HAL.afterSettableCheck[microphone] = {
                    HAL.afterSettableCheck[microphone] = { HAL.levels[driverNotice] = 0.8 }
                }
            }
            HAL.ignoredWrites = echo == .unchangedResidual ? [microphone] : [microphone, driverNotice]
            HAL.writes = []
            var reportedIgnoredWrite = false
            HAL.beforeControlWrite = { key, value in
                guard key == microphone, value == 0 else { return }
                HAL.beforeControlWrite = nil
                // Both levels are unchanged when the setter reports success.
                // The driver's callback arrives during the readback.
                func echoUnchangedValue() {
                    guard HAL.levels[microphone] == unchangedMaster,
                          echo != .unchangedResidual || HAL.levels[firstChannel] == 0.8 else { return }
                    reportedIgnoredWrite = HAL.notifyIfRegistered(driverNotice)
                }
                HAL.afterGainRead[microphone] = {
                    if echo == .masterAfterQuietChannel || echo == .quietAlias {
                        HAL.afterGainRead[firstChannel] = {
                            guard HAL.levels[firstChannel] == 0 else { return }
                            HAL.afterGainRead[channelGain] = {
                                if echo == .quietAlias { HAL.levels[firstChannel] = 0.8 }
                                echoUnchangedValue()
                            }
                        }
                    } else {
                        echoUnchangedValue()
                    }
                }
            }
            notifyRegistered(secondInput)
            suite.expect(reportedIgnoredWrite && MicMuteService.shared.isMuted && HAL.levels[microphone] == unchangedMaster
                         && (echo != .quietAlias || HAL.levels[firstChannel] == 0.8)
                         && (echo != .unchangedResidual || HAL.levels[firstChannel] == 0)
                         && HAL.levels[channelGain] == (driverNotice == channelGain ? 0.8 : 0)
                         && HAL.levels[secondInput] == 0 && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                         "a driver echo from \(echo) after an ignored Set cannot release the other mic")
        }

        for refusesSwitch in [false, true] {
            for duringInventory in [false, true] {
                prepare()
                HAL.devices = [10, 20]
                HAL.mute[10] = 0
                HAL.levels[secondInput] = 0.75
                mute()
                record()
                HAL.mute[10] = 0
                HAL.levels[microphone] = 0.9
                if refusesSwitch { HAL.ignoredWrites = [headsetSwitch] }
                HAL.writes = []
                var correctedGain = false
                var notified = false
                func reportOpening() {
                    guard correctedGain, HAL.writes.contains(headsetSwitch), HAL.levels[microphone] == 0,
                          HAL.mute[10] == (refusesSwitch ? 0 : 1) else { return }
                    HAL.levels[microphone] = 0.8
                    notified = HAL.notifyIfRegistered(microphone)
                }
                HAL.afterWrite = {
                    correctedGain = HAL.writes.last == microphone
                    if duringInventory { HAL.afterUIDRead = reportOpening }
                }
                notifyRegistered(secondInput)
                if !duringInventory {
                    notifyRegistered(secondInput) // Allow another full reconciliation with the current switch state.
                    reportOpening()
                    DispatchQueue.drain()
                }
                suite.expect(notified, "the gain listener reports an opening after the corrective switch and gain writes")
                if refusesSwitch {
                    suite.expect(MicMuteService.shared.isMuted && HAL.mute[10] == 0 && HAL.levels[microphone] == 0
                                 && HAL.levels[secondInput] == 0 && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                                 "a verified gain cannot authorize an echo while the ignored switch remains open (inventory: \(duringInventory))")
                    HAL.ignoredWrites = []
                    if duringInventory {
                        HAL.mute[10] = 1 // The driver finally engages the switch; both controls are already quiet.
                        notifyRegistered(secondInput)
                        suite.expect(HAL.mute[10] == 1 && HAL.levels[microphone] == 0 && HAL.levels[secondInput] == 0,
                                     "both the recovered mute switch and the gain reach their quiet states")
                        HAL.levels[microphone] = 0.8
                        notifyRegistered(microphone)
                    } else {
                        HAL.levels[microphone] = 0.9
                        HAL.levels[secondInput] = 0.6
                        let originalClient = HAL.soleListenerClient(for: microphone)
                        var sawQuietGain = false
                        var sawEngagedSwitch = false
                        var clickedDuringRecovery = false
                        HAL.afterWrite = {
                            guard HAL.writes.last == microphone else { return }
                            HAL.afterGainRead[microphone] = { sawQuietGain = HAL.levels[microphone] == 0 }
                            HAL.afterSwitchRead[headsetSwitch] = { sawEngagedSwitch = HAL.mute[10] == 1 }
                        }
                        HAL.afterSettableCheck[secondInput] = {
                            guard sawQuietGain, sawEngagedSwitch, originalClient != nil,
                                  HAL.soleListenerClient(for: microphone) == originalClient else { return }
                            HAL.levels[microphone] = 0.8
                            clickedDuringRecovery = HAL.notifyIfRegistered(microphone)
                        }
                        notifyRegistered(defaultInput)
                        suite.expect(clickedDuringRecovery, "the recovered headset reports its next click while the other input prepares a write")
                    }
                }
                suite.expect(!MicMuteService.shared.isMuted && HAL.mute[10] == 0 && HAL.levels[microphone] == 0.5
                             && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                             "one click with both controls confirmed restores the saved switch and both gains")
            }
        }

        let channelSwitch = HAL.key(10, 1, kAudioDevicePropertyMute)
        for refusedAtStart in [headsetSwitch, channelSwitch] {
            prepare()
            HAL.devices = [10, 20]
            HAL.levels[secondInput] = 0.75
            HAL.mute[10] = 0
            if refusedAtStart == channelSwitch { HAL.muteElements[channelSwitch] = 0 }
            HAL.ignoredWrites = [refusedAtStart]
            mute()
            record()
            HAL.writes = []
            HAL.levels[microphone] = 0.8
            notifyRegistered(microphone)
            suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0 && HAL.levels[secondInput] == 0
                         && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                         "a switch ignored since the first mute prevents the headset's gain echo from releasing another input")
            if refusedAtStart == headsetSwitch {
                record(20)
                HAL.levels[secondInput] = 0.8
                notifyRegistered(secondInput)
            } else {
                suite.expect(HAL.mute[10] == 1 && HAL.muteElements[channelSwitch] == 0,
                             "the engaged main switch hides the still-open channel from the aggregate switch reading")
                HAL.muteElements[channelSwitch] = 1
                var confirmedChannel = false
                HAL.afterSwitchRead[channelSwitch] = { confirmedChannel = HAL.muteElements[channelSwitch] == 1 }
                HAL.writes = []
                notifyRegistered(secondInput)
                suite.expect(confirmedChannel && !HAL.writes.contains(channelSwitch) && MicMuteService.shared.isMuted,
                             "reconciliation reads the recovered channel switch at its own address while the main switch stays engaged")
                HAL.ignoredWrites = []
                HAL.levels[microphone] = 0.8
                notifyRegistered(microphone)
            }
            suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5 && HAL.levels[secondInput] == 0.75
                         && HAL.mute[10] == 0 && (refusedAtStart != channelSwitch || HAL.muteElements[channelSwitch] == 0)
                         && QuickToolHUD.messages == ["unmuted"],
                         "one click on the independently confirmed or recovered input restores both gains")
        }

        prepare()
        HAL.devices = [10, 20]
        HAL.mute[10] = 0
        HAL.ignoredWrites = [headsetSwitch]
        HAL.levels[secondInput] = 0.75
        mute()
        record()
        let survivingGain = HAL.soleListenerClient(for: microphone)
        HAL.mute[10] = nil
        notifyRegistered(defaultInput) // Remove only the absent switch listener.
        notifyRegistered(defaultInput) // Check the gain again with the surviving registration.
        suite.expect(!HAL.listeners.contains(headsetSwitch) && survivingGain != nil && HAL.soleListenerClient(for: microphone) == survivingGain,
                     "dropping the refused switch property leaves its input's gain registration intact")
        HAL.writes = []
        HAL.levels[microphone] = 0.8
        notifyRegistered(microphone)
        suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0 && HAL.levels[secondInput] == 0
                     && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                     "removing only the refused switch cannot turn a gain echo into a global release")

        let headsetListeners = HAL.listeners.filter { $0.d == 10 }
        HAL.listenerRemovals = []
        HAL.listenerAdds = []
        var readAfterReplacement = false
        HAL.afterListenerAdd[microphone] = {
            HAL.afterGainRead[microphone] = { readAfterReplacement = HAL.levels[microphone] == 0 }
        }
        notifyRegistered(HAL.key(10, 0, kAudioDevicePropertyStreams))
        suite.expect(headsetListeners.isSubset(of: Set(HAL.listenerRemovals)) && headsetListeners.isSubset(of: Set(HAL.listenerAdds))
                     && HAL.soleListenerClient(for: microphone) != survivingGain && readAfterReplacement,
                     "the same headset renews its listeners and confirms zero with the replacement gain registration")
        HAL.levels[microphone] = 0.8
        notifyRegistered(microphone)
        suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5 && HAL.levels[secondInput] == 0.75
                     && QuickToolHUD.messages == ["unmute partial"],
                     "the new gain click restores both levels and reports the unavailable saved switch")

        let deviceChanges = [
            HAL.key(10, 0, kAudioDevicePropertyDeviceIsAlive, scope: kAudioObjectPropertyScopeGlobal),
            HAL.key(10, 0, kAudioDevicePropertyDeviceHasChanged, scope: kAudioObjectPropertyScopeGlobal),
            HAL.key(10, 0, kAudioObjectPropertyControlList, scope: kAudioObjectPropertyScopeGlobal),
            HAL.key(10, 0, kAudioDevicePropertyStreams),
            HAL.key(10, 0, kAudioDevicePropertyStreamConfiguration),
        ]
        for captured in [microphone, secondInput] {
            prepare()
            HAL.devices = [10, 20]
            HAL.levels[secondInput] = 0.75
            mute()
            record(captured.d)
            if captured == microphone {
                notifyRegistered(microphone) // Consume a gain notification while the headset is still quiet.
                HAL.levels[microphone] = 0.8
                HAL.writes = []
                notifyRegistered(secondInput)
                suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0 && HAL.levels[secondInput] == 0
                             && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                             "a gain notification from the other input cannot release the captured headset")
            } else {
                // The headset's layout changes in the same batch as the call's gain adjustment on input 20.
                HAL.streamChannels[10] = [1]
                let layout = HAL.key(10, 0, kAudioDevicePropertyStreamConfiguration)
                suite.expect(HAL.notifyIfRegistered(layout), "the headset reports its independent layout change")
            }
            HAL.levels[captured] = 0.7
            notifyRegistered(captured)
            suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                         && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                         "a gain callback on the confirmed input used by the call restores both gains")
        }

        prepare()
        HAL.devices = [10, 20]
        HAL.levels[secondInput] = 0.75
        mute()
        record()
        HAL.afterUIDRead = {
            HAL.levels[microphone] = 0.7
            suite.expect(HAL.notifyIfRegistered(microphone), "the call's gain callback arrives during the UID read")
        }
        notifyRegistered(defaultInput)
        suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                     && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                     "a default-input sweep on a confirmed connection preserves a concurrent click by the call")

        prepare()
        HAL.devices = [10, 20]
        let thirdChannel = HAL.key(10, 3)
        let headsetLayout = HAL.key(10, 0, kAudioDevicePropertyStreamConfiguration)
        HAL.streamChannels[10] = [3]
        HAL.levels[thirdChannel] = 0.8
        HAL.readOnly = [thirdChannel]
        HAL.levels[secondInput] = 0.75
        mute()
        record()
        let pendingThirdChannel = HAL.pendingNotification(for: thirdChannel)
        HAL.sizeReadFails = [headsetLayout]
        HAL.writes = []
        notifyRegistered(secondInput)
        suite.expect(pendingThirdChannel != nil && HAL.levels[microphone] == 0 && HAL.levels[thirdChannel] == 0.8
                     && HAL.levels[secondInput] == 0, "the unreadable layout hides an always-open third channel")
        HAL.sizeReadFails = []
        pendingThirdChannel?()
        DispatchQueue.drain()
        suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0 && HAL.levels[thirdChannel] == 0.8
                     && HAL.levels[secondInput] == 0 && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                     "a delayed callback for an unread channel cannot turn its unchanged gain into a call unmute")
        HAL.levels[thirdChannel] = 0 // The device finally reports silence on its read-only channel.
        notifyRegistered(thirdChannel)
        suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0 && HAL.levels[secondInput] == 0
                     && QuickToolHUD.messages.isEmpty, "the complete silent reading keeps both inputs muted")
        HAL.levels[microphone] = 0.7
        notifyRegistered(microphone)
        suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                     && HAL.levels[secondInput] == 0.75 && HAL.levels[thirdChannel] == 0 && !HAL.writes.contains(thirdChannel)
                     && QuickToolHUD.messages == ["unmuted"],
                     "a real click on the master gain observed at zero restores both saved input levels")

        prepare()
        HAL.devices = [10, 20]
        let quietChannel = HAL.key(20, 1)
        let inputSwitch = HAL.key(20, 0, kAudioDevicePropertyMute)
        HAL.levels[secondInput] = 0.75
        HAL.levels[quietChannel] = 0
        HAL.mute[20] = 0
        HAL.failedListenerKeys = [microphone]
        mute()
        record(20)
        suite.expect(HAL.listenerAdds.contains(microphone) && !HAL.listeners.contains(microphone),
                     "the HAL refuses the headset's individual gain registration")
        HAL.levels[secondInput] = 0.8
        notifyRegistered(quietChannel)
        suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0 && HAL.levels[secondInput] == 0
                     && HAL.mute[20] == 1 && QuickToolHUD.messages.isEmpty,
                     "a quiet channel's notification cannot authorize the same input's open master gain")
        HAL.mute[20] = 0
        notifyRegistered(inputSwitch)
        suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                     && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                     "a confirmed input's switch can release mute while the other gain registration is refused")

        prepare()
        HAL.devices = [10, 20]
        HAL.levels[secondInput] = 0.75
        let alive = HAL.key(10, 0, kAudioDevicePropertyDeviceIsAlive, scope: kAudioObjectPropertyScopeGlobal)
        HAL.failedListenerKeys = [alive]
        mute()
        record()
        let gainBeforeDisconnect = HAL.pendingNotification(for: microphone)
        suite.expect(gainBeforeDisconnect != nil && !HAL.listeners.contains(alive),
                     "the headset gain is observed while its alive listener is refused")
        HAL.dropListeners(forDevice: 10)
        HAL.levels[microphone] = 0.8
        HAL.writes = []
        HAL.failedListenerKeys = []
        HAL.afterListenerAdd[alive] = { HAL.failedListenerKeys = [alive] }
        HAL.afterListenerAdd[microphone] = {
            HAL.levels[microphone] = 0.9
            gainBeforeDisconnect?()
        }
        notifyRegistered(secondInput)
        suite.expect(HAL.listeners.contains(alive) && HAL.afterListenerAdd[microphone] == nil
                     && MicMuteService.shared.isMuted && HAL.levels[microphone] == 0 && HAL.levels[secondInput] == 0
                     && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                     "repairing the alive listener renews gain lost in the unobserved reconnect and confirms silence")
        HAL.levels[microphone] = 0.7
        notifyRegistered(microphone)
        suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                     && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                     "the renewed headset gain listener follows the next real click")

        for change in deviceChanges {
            prepare()
            HAL.devices = [10, 20]
            HAL.levels[secondInput] = 0.75
            mute()
            record()
            let oldGain = HAL.pendingNotification(for: microphone)
            HAL.inactiveDevices = [10]
            HAL.inputsWithoutStreams = [10]
            HAL.streamChannels[10] = []
            suite.expect(HAL.notifyIfRegistered(change), "the headset reports losing its input path")
            HAL.inactiveDevices = []
            HAL.inputsWithoutStreams = []
            HAL.streamChannels[10] = [2]
            suite.expect(HAL.notifyIfRegistered(change), "the same headset returns before the next inventory read")
            HAL.dropListeners(forDevice: 10)
            HAL.levels[microphone] = 0.8
            HAL.writes = []
            HAL.afterListenerAdd[microphone] = {
                HAL.levels[microphone] = 0.9
                oldGain?()
            }
            DispatchQueue.drain()
            suite.expect(oldGain != nil && HAL.afterListenerAdd[microphone] == nil && MicMuteService.shared.isMuted
                         && HAL.levels[microphone] == 0 && HAL.levels[secondInput] == 0
                         && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                         "coalesced changes to property \(change.s) renew the gain listener and silence the returning headset")
            HAL.levels[microphone] = 0.7
            notifyRegistered(microphone)
            suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                         && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                         "the next gain change follows the call after the headset's input path stabilizes")
        }
        enum RegistrationRecovery: CaseIterable { case automatic, manualRestore, persistentFailure }
        for recovery in RegistrationRecovery.allCases {
            prepare()
            var now: TimeInterval = 10
            let service = MicMuteService(uptime: { now })
            MicMuteService.shared = service
            HAL.devices = [10, 20]
            HAL.levels[secondInput] = 0.75
            let loopback = HAL.key(30)
            if recovery == .manualRestore {
                HAL.devices.append(30)
                HAL.uids[30] = "MSLoopbackDriverDevice_UID"
                HAL.levels[loopback] = 0.625
                HAL.ignoredWrites = [loopback]
            }
            HAL.failedListenerKeys = [devicesChanged]
            mute()
            if recovery == .manualRestore {
                notifyRegistered(loopback)
                notifyRegistered(loopback)
                suite.expect(service.retryDeadline != nil, "the refusing loopback has its own gain retry")
            }
            record()
            let oldGain = HAL.pendingNotification(for: microphone)
            suite.expect(oldGain != nil && !HAL.notifyIfRegistered(devicesChanged),
                         "the headset was observed but the HAL cannot announce its reconnection")
            HAL.dropListeners(forDevice: 10)
            HAL.writes = []
            func expectMuted(_ message: String) {
                suite.expect(service.isMuted && HAL.levels[microphone] == 0 && HAL.levels[secondInput] == 0
                             && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty, message)
            }
            func tick() {
                now += 60
                DispatchQueue.main.runTimers()
                service.halQueue.runTimers()
                DispatchQueue.drain()
            }
            for property in [secondInput, defaultInput] {
                HAL.levels[microphone] = 0.8
                notifyRegistered(property)
                expectMuted("an unrelated callback enforces mute while the device-list listener is unavailable")
            }
            if recovery == .persistentFailure {
                let firstSweep = service.applyGeneration
                var attempts = 0
                while attempts < 12 {
                    let active = DispatchQueue.main.delayed.filter { !$0.isCancelled }
                    if active.isEmpty { break }
                    suite.expect(active.count == 1, "only one registration retry is waiting")
                    attempts += 1
                    tick()
                }
                let finalSweep = service.applyGeneration
                let finalAdds = HAL.listenerAdds.count
                tick()
                suite.expect((1..<12).contains(attempts) && finalSweep > firstSweep && service.applyGeneration == finalSweep
                             && HAL.listenerAdds.count == finalAdds && !HAL.listeners.contains(devicesChanged),
                             "persistent refusal exhausts the timed retries without polling or registering again")
                expectMuted("exhausting the timer leaves the active mute and both gains intact")

                suite.expect(HAL.restartAudioService(), "the registered listener delivers a new audio service generation")
                DispatchQueue.drain()
                tick()
                suite.expect(!HAL.listeners.contains(devicesChanged) && DispatchQueue.main.delayed.contains { !$0.isCancelled },
                             "the new generation keeps retrying even when its first timed registration fails")
            }
            if recovery == .manualRestore {
                HAL.levels[microphone] = 0.9
                tick()
                expectMuted("a timer also enforces mute while reconnections cannot be observed")
                let pending = DispatchQueue.main.delayed.filter { !$0.isCancelled }
                HAL.ignoredWrites = []
                service.setMuted(false)
                DispatchQueue.drain()
                HAL.failedListenerKeys = []
                HAL.writes = []
                let finalSweep = service.applyGeneration
                let finalAdds = HAL.listenerAdds.count
                tick()
                suite.expect(!service.isMuted && HAL.levels[microphone] == 0.5 && HAL.levels[secondInput] == 0.75
                             && pending.count == 1 && pending.allSatisfy(\.isCancelled)
                             && service.applyGeneration == finalSweep && HAL.listenerAdds.count == finalAdds
                             && HAL.listeners.isEmpty && HAL.writes.isEmpty,
                             "manual unmute restores both inputs and cancels recovery from the listener failure")
            } else {
                // The missing system registration becomes available without a HAL callback.
                HAL.failedListenerKeys = []
                HAL.afterListenerAdd[microphone] = {
                    HAL.levels[microphone] = 0.9
                    oldGain?()
                }
                tick()
                suite.expect(HAL.listeners.contains(devicesChanged) && HAL.listeners.contains(microphone)
                             && HAL.afterListenerAdd[microphone] == nil,
                             "a retry alone recovers the device list and renews the returning headset's gain listener")
                expectMuted("recovery confirms both microphones silent after renewing the headset listener")
                HAL.levels[microphone] = 0.7
                notifyRegistered(microphone)
                suite.expect(!service.isMuted && HAL.levels[microphone] == 0.5 && HAL.levels[secondInput] == 0.75
                             && QuickToolHUD.messages == ["unmuted"],
                             "only a fresh click after recovery releases both saved gains")
            }
        }
        for removalFails in [false, true] {
            prepare()
            HAL.devices = [10, 20]
            HAL.levels[secondInput] = 0.75
            mute()
            record()
            if removalFails { HAL.failedListenerRemovals = [microphone] } else { HAL.failedListenerKeys = [microphone] }
            HAL.devices.append(40)
            notifyRegistered(devicesChanged)
            suite.expect(HAL.listeners.contains(microphone) == removalFails && HAL.listenerRemovals.contains(microphone),
                         "failed removal leaves the old gain listener, while failed registration leaves none")

            HAL.writes = []
            HAL.levels[microphone] = 0.8
            notifyRegistered(secondInput)
            suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0 && HAL.levels[secondInput] == 0
                         && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                         "a notification from the other input cannot release mute while renewal is still failing")

            HAL.failedListenerRemovals = []
            HAL.failedListenerKeys = []
            HAL.afterListenerAdd[microphone] = { HAL.levels[microphone] = 0.9 }
            notifyRegistered(secondInput)
            suite.expect(HAL.afterListenerAdd[microphone] == nil && MicMuteService.shared.isMuted
                         && HAL.levels[microphone] == 0 && HAL.levels[secondInput] == 0
                         && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                         "the newly registered gain listener gets a quiet baseline after a failed renewal")
            HAL.levels[microphone] = 0.7
            notifyRegistered(microphone)
            suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                         && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["unmuted"],
                         "the next gain change on the recovered headset follows the call and restores both inputs")
        }

        let arrivingInput = HAL.key(40)
        for captured in [microphone, arrivingInput] {
            prepare()
            HAL.devices = [10, 20]
            HAL.levels[secondInput] = 0.75
            mute()
            let pendingGain = HAL.pendingNotification(for: microphone)
            suite.expect(pendingGain != nil, "the old headset has a pending gain notification")
            HAL.dropListeners(forDevice: 10)
            HAL.devices.append(40)
            HAL.levels[microphone] = 0.8
            HAL.levels[arrivingInput] = 0.625
            record(captured.d)
            HAL.writes = []
            // The mute sweep sees all three inputs. Only its listener reconciliation fails to read the list.
            HAL.afterWrite = { HAL.readFails = [devicesChanged] }
            suite.expect(HAL.notifyIfRegistered(devicesChanged), "the HAL announces the device change")
            DispatchQueue.main.run()
            MicMuteService.shared.halQueue.run()
            suite.expect(HAL.readFails.contains(devicesChanged) && HAL.levels[microphone] == 0
                         && HAL.levels[secondInput] == 0 && HAL.levels[arrivingInput] == 0
                         && !HAL.listeners.contains(microphone) && !HAL.listeners.contains(arrivingInput),
                         "the first sweep silences all inputs before the unreadable list prevents registration")
            HAL.readFails = []
            HAL.afterListenerAdd[captured] = {
                HAL.levels[captured] = 0.9
                pendingGain?()
            }
            DispatchQueue.drain()
            suite.expect(HAL.afterListenerAdd[captured] == nil && MicMuteService.shared.isMuted
                         && HAL.levels[microphone] == 0 && HAL.levels[secondInput] == 0 && HAL.levels[arrivingInput] == 0
                         && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                         "an old headset callback cannot release any input while device \(captured.d) gains a listener")
            HAL.levels[captured] = 0.7
            notifyRegistered(captured)
            suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                         && HAL.levels[secondInput] == 0.75 && HAL.levels[arrivingInput] == 0.625
                         && QuickToolHUD.messages == ["unmuted"],
                         "the next gain change on device \(captured.d) restores all three saved gains")
        }

        prepare()
        HAL.mute[10] = 0
        mute()
        HAL.ignoredWrites = [HAL.key(10, 0, kAudioDevicePropertyMute)]
        HAL.mute[10] = 0
        notify(selector: kAudioDevicePropertyMute)
        record()
        notify()
        suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0 && QuickToolHUD.messages.isEmpty,
                     "a switch cleared before capture cannot release mute when recording starts later")

        prepare()
        var now: TimeInterval = 0
        MicMuteService.shared = MicMuteService(uptime: { now })
        HAL.devices = [10, 20]
        HAL.uids[20] = "MSLoopbackDriverDevice_UID"
        HAL.levels[secondInput] = 0.75
        HAL.ignoredWrites = [secondInput]
        mute()
        notify(20)
        notify(20)
        suite.expect(MicMuteService.shared.retryDeadline != nil, "the loopback has a retry waiting")
        record()
        HAL.levels[microphone] = 0.7
        now += 0.25
        MicMuteService.shared.halQueue.runTimers()
        notify()
        suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                        && QuickToolHUD.messages == ["unmuted"],
                     "a loopback retry ahead of the microphone listener still follows the call's unmute")

        // The second input's write runs after the first input has been verified silent.
        prepare()
        HAL.devices = [10, 20]
        HAL.levels[secondInput] = 0.75
        record()
        HAL.afterWrite = { HAL.afterWrite = { HAL.levels[microphone] = 0.7 } }
        QuickToolHUD.messages = []
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        suite.expect(MicMuteService.shared.isMuted && HAL.levels[microphone] == 0
                     && HAL.levels[secondInput] == 0 && QuickToolHUD.messages == ["muted"],
                     "an opening before the first listeners are installed must be silenced before following the call")
        HAL.levels[microphone] = 0.7
        notifyRegistered(microphone)
        suite.expect(!MicMuteService.shared.isMuted && HAL.levels[microphone] == 0.5
                        && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages == ["muted", "unmuted"],
                     "the next gain callback after the first confirmed mute follows the call")

        for reconnect in [false, true] {
            prepare()
            var releaseTime: TimeInterval = 0
            MicMuteService.shared = MicMuteService(uptime: { releaseTime })
            mute()
            HAL.devices.append(20)
            HAL.levels[secondInput] = 0.75
            notifyRegistered(devicesChanged)
            let service = MicMuteService.shared
            let oldGain = HAL.pendingNotification(for: microphone)
            HAL.writeFails = [microphone, secondInput]
            service.setMuted(false)
            DispatchQueue.drain()
            suite.expect(!service.isMuted && service.hasOutstandingClaims && HAL.levels[microphone] == 0
                         && HAL.levels[secondInput] == 0 && QuickToolHUD.messages == ["unmute partial"],
                         "a wholly rejected manual restore leaves both physical inputs muted with release pending")
            suite.expect(oldGain != nil && service.observedDeviceListChange == nil,
                         "an explicit release retires the active mute's call-following baseline")
            HAL.writes = []
            QuickToolHUD.messages = []
            record()
            HAL.levels[microphone] = 0.8
            if reconnect {
                HAL.dropListeners(forDevice: 10)
                HAL.devices.append(40)
                suite.expect(HAL.notifyIfRegistered(devicesChanged), "one device-list event announces the arrival")
            }
            oldGain?()
            DispatchQueue.drain()
            suite.expect(!service.wantsMute && HAL.levels[microphone] == 0.8 && HAL.levels[secondInput] == 0
                         && QuickToolHUD.messages.isEmpty,
                         "a delayed headset event during a call cannot reassert mute after a refused manual release")
            HAL.writeFails = []
            notifyRegistered(devicesChanged)
            releaseTime += 2
            service.halQueue.runTimers()
            DispatchQueue.drain()
            suite.expect(!service.isMuted && !service.hasOutstandingClaims && HAL.levels[microphone] == 0.5
                         && HAL.levels[secondInput] == 0.75 && QuickToolHUD.messages.isEmpty,
                         "recovery retries the manual release of both original gains while the call records")
        }
    }
}
