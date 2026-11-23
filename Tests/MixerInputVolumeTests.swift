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
        static let micMuteFollowCallApps = "followCallApps"
        static let micMuteSavedVolumes = "savedVolumes"
        static let micMuteSavedChannelVolumes = "savedChannelVolumes"
        static let micMuteSavedControls = "savedControls"
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
            func string(forKey k: String) -> String? { values[k] as? String }
            func bool(forKey k: String) -> Bool { values[k] as? Bool ?? false }
            func double(forKey k: String) -> Double { values[k] as? Double ?? 0 }
            func dictionary(forKey k: String) -> [String: Any]? { values[k] as? [String: Any] }
            func stringArray(forKey k: String) -> [String]? { values[k] as? [String] }
            func set(_ v: Any, forKey k: String) {
                values[k] = v
                writtenKeys.append(k)
            }
            func removeObject(forKey k: String) { values[k] = nil }
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
        static func show(icon: String, message: String) { messages.append(message) }
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
        static var readOnly: Set<Key> = []
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
        static var streamReadFails = false
        static var afterWrite: (() -> Void)?
        static var afterGainRead: [Key: () -> Void] = [:]
        static var afterSwitchRead: [Key: () -> Void] = [:]
        static var afterSettableCheck: [Key: () -> Void] = [:]
        static var beforeControlWrite: ((Key, Double) -> Void)?
        static var afterUIDRead: (() -> Void)?
        /// The audio server's process list: each process, whether it is
        /// recording, and from which devices.
        static var processes: [(object: UInt32, pid: Int32, recording: Bool, devices: [UInt32])] = []
        static var processListReads = 0
        static var afterProcessListRead: (() -> Void)?
        static var current: UInt32 = 10
        static var uids: [UInt32: String] = [:]
        static var aggregates: Set<UInt32> = []
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
            readOnly = []
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
            virtual = []
            running = []
            streamChannels = [:]
            streamReadFails = false
            afterWrite = nil
            afterGainRead = [:]
            afterSwitchRead = [:]
            afterSettableCheck = [:]
            beforeControlWrite = nil
            afterUIDRead = nil
            processes = []
            processListReads = 0
            afterProcessListRead = nil
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
            v.pointee = DarwinBoolean(!readOnly.contains(key))
            afterSettableCheck.removeValue(forKey: key)?()
            return noErr
        }
        static func GetPropertyDataSize(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>, _ q: UInt32,
            _ qp: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>
        ) -> OSStatus {
            if sizeReadFails.contains(Key(d, a.pointee)) { return -1 }
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
            case kAudioDevicePropertyStreamConfiguration:
                if streamReadFails { return -1 }
                let channels = streamChannels[d] ?? [2]
                let list = p.assumingMemoryBound(to: AudioBufferList.self)
                list.pointee.mNumberBuffers = UInt32(channels.count)
                let buffers = UnsafeMutableAudioBufferListPointer(list)
                for (i, n) in channels.enumerated() {
                    buffers[i] = AudioBuffer(mNumberChannels: n, mDataByteSize: 0, mData: nil)
                }
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
            levels[k] = p.load(as: Float.self)
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
        check(MicMuteService.shared.isMuted && MicMuteService.shared.hasOutstandingClaims
                && UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive)
                && MicMuteService.shared.inputVolumeAdjustmentLifetime == nil
                && HAL.mute[10] == 1,
              "a wholly refused unmute preserves the state and claim for retry")
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
                && NotchService.shared.retractions == 0,
              "a failed background reapply stays silent instead of repeating the warning")
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
        HAL.running = [30]
        QuickToolHUD.messages = []
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        check(
            QuickToolHUD.messages == ["muted"] && MicMuteService.inputControls(10).isSilenced,
            "an aggregate with no mute or level of its own does not make the mute partial")
        HAL.reset()
        HAL.devices = [10, 40]
        HAL.levels[HAL.key(10)] = 0.5
        QuickToolHUD.messages = []
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        check(
            QuickToolHUD.messages == ["muted"] && MicMuteService.inputControls(10).isSilenced,
            "an idle microphone with no mute or level of its own does not make the mute partial")
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
        // What a version without saved channel levels leaves behind: the main
        // level and both channels at zero, with only the main level saved.
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0
        HAL.levels[HAL.key(10, 1)] = 0
        HAL.levels[HAL.key(10, 2)] = 0
        UserDefaults.standard.set(true, forKey: DefaultsKey.micMuteActive)
        UserDefaults.standard.set(["device-10": 0.5], forKey: DefaultsKey.micMuteSavedVolumes)
        UserDefaults.standard.set(["device-10"], forKey: DefaultsKey.micMuteMutedDevices)
        MicMuteService.shared = MicMuteService()
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        MicMuteService.shared.setMuted(false)
        DispatchQueue.drain()
        check(
            !MicMuteService.shared.isMuted && HAL.levels[HAL.key(10)] == 0.5
                && HAL.levels[HAL.key(10, 1)] == 0.5 && HAL.levels[HAL.key(10, 2)] == 0.5,
            "an unmute after updating brings back the channels an earlier version lowered")

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
            check(MicMuteService.shared.isMuted && MicMuteService.shared.hasOutstandingClaims
                    && (HAL.mute[10] == 1 || HAL.levels[HAL.key(10)] == 0),
                  "an ignored switch or volume restore retains the obligation despite another successful control")
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
        check(HAL.levels[HAL.key(10)] == 0.625 && !MicMuteService.shared.hasOutstandingClaims,
              "a zeroed legacy gain mute still uses its saved fallback when the main switch is off")

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
        check(MicMuteService.shared.isMuted && MicMuteService.shared.retryDeadline != nil,
              "a wholly failed manual unmute keeps the active mute's retry")
        AppFeature.micMuteAvailable = false
        MicMuteService.shared.syncWithPreferences()
        DispatchQueue.drain()
        check(!MicMuteService.shared.isMuted && MicMuteService.shared.retryDeadline == nil,
              "disabling the feature cancels mute retries even if unmute fails")
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
        HAL.ignoreWrites = true
        MicMuteService.shared.setMuted(true)
        DispatchQueue.drain()
        for _ in 0..<5 { changed(10) }
        check(MicMuteService.shared.retryDeadline == nil && HAL.writes.filter { $0 == HAL.key(10) }.count == 6,
              "an unclassified or physical microphone never enters virtual-driver backoff")
        HAL.ignoreWrites = false
        changed(10)
        check(HAL.levels[HAL.key(10)] == 0, "a slow physical microphone is silenced on its next change")

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
        check(QuickToolHUD.messages == ["unmute partial"] && service.isMuted && service.hasOutstandingClaims,
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
        runMuteListenerTests(suite)
        runMuteRecoveryTests(suite)
        runCallAppUnmuteTests(suite)
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
        suite.expect(HAL.listeners == original, "a failed device-list read preserves the active registrations")
        expectCalls("a failed device-list read does not detach the last known input")
        HAL.readFails.remove(devicesChanged)
        let inputListeners = original.filter { $0.d == 10 }
        HAL.devices = []
        notify(devicesChanged)
        suite.expect(HAL.listeners == original.subtracting(inputListeners),
                     "the system stays watched with no inputs present")
        expectCalls("removing the last input clears its registrations", removing: inputListeners)
        HAL.devices = [10]
        notify(devicesChanged)
        suite.expect(HAL.listeners == original, "the same UID and object ID can return after a real disconnect")
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
                if moment == .setter || moment == .firstReadback || moment == .topology {
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
            mute()
            HAL.devices.append(20)
            HAL.levels[secondInput] = 0.75
            notifyRegistered(devicesChanged)
            let service = MicMuteService.shared
            let observedChange: UInt64? = service.observedDeviceListChange
            HAL.writeFails = [microphone, secondInput]
            service.setMuted(false)
            DispatchQueue.drain()
            suite.expect(service.isMuted && service.hasOutstandingClaims && HAL.levels[microphone] == 0
                         && HAL.levels[secondInput] == 0 && QuickToolHUD.messages == ["unmute partial"],
                         "a wholly rejected manual restore leaves both inputs muted")
            suite.expect(observedChange != nil && service.observedDeviceListChange == observedChange,
                         "a rejected restore preserves the last device-list change of the active mute")
            HAL.writeFails = []
            HAL.writes = []
            QuickToolHUD.messages = []
            record()
            if reconnect {
                let oldGain = HAL.pendingNotification(for: microphone)
                suite.expect(oldGain != nil, "the headset still has its original listener after the rejected restore")
                HAL.dropListeners(forDevice: 10)
                HAL.devices.append(40)
                HAL.levels[microphone] = 0.8
                suite.expect(HAL.notifyIfRegistered(devicesChanged), "one device-list event announces the arrival")
                oldGain?()
                DispatchQueue.drain()
                suite.expect(service.isMuted && HAL.levels[microphone] == 0 && HAL.levels[secondInput] == 0
                             && !HAL.writes.contains(secondInput) && QuickToolHUD.messages.isEmpty,
                             "the old headset callback after a rejected restore cannot release either input")
            }
            HAL.levels[microphone] = 0.7
            notifyRegistered(microphone)
            suite.expect(!service.isMuted && HAL.levels[microphone] == 0.5 && HAL.levels[secondInput] == 0.75
                         && QuickToolHUD.messages == ["unmuted"],
                         "a call's next unmute restores both inputs after a failed manual restoration")
        }
    }
}
