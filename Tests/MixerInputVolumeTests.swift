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
        init(label: String, qos: DispatchQoS) { Self.queues.append(self) }
        func async(execute: @escaping () -> Void) { work.append(execute) }
        func asyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) { work.append(execute) }
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
        case mixer, micMute
        var isAvailable: Bool { true }
    }
    enum DefaultsKey {
        static let preferredInputDevice = "preferred"
        static let micMuteActive = "mute"
        static let micMuteSavedVolumes = "savedVolumes"
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
            func string(forKey k: String) -> String? { values[k] as? String }
            func bool(forKey k: String) -> Bool { values[k] as? Bool ?? false }
            func double(forKey k: String) -> Double { values[k] as? Double ?? 0 }
            func dictionary(forKey k: String) -> [String: Any]? { values[k] as? [String: Any] }
            func stringArray(forKey k: String) -> [String]? { values[k] as? [String] }
            func set(_ v: Any, forKey k: String) { values[k] = v }
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
    enum QuickToolHUD { static func show(icon: String, message: String) {} }
    enum L10n {
        static let shared = Strings()
        struct Strings {
            var s: Strings { self }
            let micMutedHUD = "muted"
            let micUnmutedHUD = "unmuted"
        }
    }
    struct Key: Hashable {
        let d: UInt32
        let s: UInt32
        let e: UInt32
        init(_ d: UInt32, _ a: AudioObjectPropertyAddress) {
            self.d = d
            s = a.mSelector
            e = a.mElement
        }
    }
    enum HAL {
        static var levels: [Key: Float] = [:]
        static var readOnly: Set<Key> = []
        static var readFails: Set<Key> = []
        static var writeFails: Set<Key> = []
        static var mute: [UInt32: UInt32] = [:]
        static var writes: [Key] = []
        static var listeners: Set<Key> = []
        static var listenerFails = false
        static var ignoreWrites = false
        static var devices: [UInt32] = [10]
        static var streamChannels: [UInt32: [UInt32]] = [:]
        static var streamReadFails = false
        static var afterWrite: (() -> Void)?
        static var afterUIDRead: (() -> Void)?
        static var current: UInt32 = 10
        static var uids: [UInt32: String] = [:]
        static func key(_ d: UInt32, _ e: UInt32 = 0, _ s: UInt32 = kAudioDevicePropertyVolumeScalar)
            -> Key
        {
            Key(
                d,
                AudioObjectPropertyAddress(
                    mSelector: s, mScope: kAudioDevicePropertyScopeInput, mElement: e))
        }
        static func reset() {
            levels = [:]
            readOnly = []
            readFails = []
            writeFails = []
            mute = [:]
            writes = []
            listeners = []
            listenerFails = false
            ignoreWrites = false
            devices = [10]
            current = 10
            uids = [:]
            streamChannels = [:]
            streamReadFails = false
            afterWrite = nil
            afterUIDRead = nil
            UserDefaults.standard.values = [:]
            MicMuteService.shared = MicMuteService()
        }
        static func HasProperty(_ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>) -> Bool {
            let k = Key(d, a.pointee)
            return levels[k] != nil || (a.pointee.mSelector == kAudioDevicePropertyMute && mute[d] != nil)
        }
        static func IsPropertySettable(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>,
            _ v: UnsafeMutablePointer<DarwinBoolean>
        ) -> OSStatus {
            v.pointee = DarwinBoolean(!readOnly.contains(Key(d, a.pointee)))
            return noErr
        }
        static func GetPropertyDataSize(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>, _ q: UInt32,
            _ qp: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>
        ) -> OSStatus {
            if a.pointee.mSelector == kAudioDevicePropertyStreamConfiguration {
                size.pointee = UInt32(
                    MemoryLayout<AudioBufferList>.size + max(0, (streamChannels[d] ?? [2]).count - 1)
                        * MemoryLayout<AudioBuffer>.stride)
                return streamReadFails ? -1 : noErr
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
            if readFails.contains(k) { return -1 }
            if let v = levels[k] {
                p.storeBytes(of: v, as: Float.self)
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
                for (i, v) in devices.enumerated() {
                    p.storeBytes(of: v, toByteOffset: i * 4, as: UInt32.self)
                }
            case kAudioHardwarePropertyDefaultInputDevice: p.storeBytes(of: current, as: UInt32.self)
            case kAudioDevicePropertyDeviceUID, kAudioObjectPropertyName:
                p.assumingMemoryBound(to: CFString.self).pointee = (uids[d] ?? "device-\(d)") as CFString
                let callback = afterUIDRead
                afterUIDRead = nil
                callback?()
            case kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyDeviceCanBeDefaultDevice:
                p.storeBytes(of: UInt32(1), as: UInt32.self)
            case kAudioDevicePropertyIsHidden: p.storeBytes(of: UInt32(0), as: UInt32.self)
            case kAudioDevicePropertyMute:
                guard let v = mute[d] else { return -1 }
                p.storeBytes(of: v, as: UInt32.self)
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
            if writeFails.contains(k) { return -1 }
            if ignoreWrites { return noErr }
            if a.pointee.mSelector == kAudioHardwarePropertyDefaultInputDevice {
                current = p.load(as: UInt32.self)
                return noErr
            }
            if a.pointee.mSelector == kAudioDevicePropertyMute {
                mute[d] = p.load(as: UInt32.self)
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
            _ cb: AudioObjectPropertyListenerProc, _ client: UnsafeMutableRawPointer?
        ) -> OSStatus {
            if listenerFails { return -1 }
            listeners.insert(Key(d, a.pointee))
            return noErr
        }
        @discardableResult
        static func RemovePropertyListener(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>,
            _ cb: AudioObjectPropertyListenerProc, _ client: UnsafeMutableRawPointer?
        ) -> OSStatus {
            listeners.remove(Key(d, a.pointee))
            return noErr
        }
    }
    static func run(_ suite: TestSuite) {
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            suite.expect(condition(), name)
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
            MicMuteService.shared.isMuted && MicMuteService.isSilenced(10),
            "production mute falls back to zero gain")
        m.setInputVolume(0.8)
        DispatchQueue.drain()
        check(
            MicMuteService.isSilenced(10) && MicMuteService.shared.isMuted,
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
        check(MicMuteService.isSilenced(10), "hardware mute switch remains silent after gain gesture")
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
    }
}
