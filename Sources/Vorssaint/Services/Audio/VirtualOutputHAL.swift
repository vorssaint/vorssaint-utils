// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint Audio contributors
import CoreAudio
import AudioToolbox
import Foundation

enum VirtualOutputHAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        var property = address(selector, scope: scope), size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0) == noErr
        }
    }
    @discardableResult static func write<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, value: T,
                                           scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> OSStatus {
        var property = address(selector, scope: scope), value = value
        return withUnsafePointer(to: &value) {
            AudioObjectSetPropertyData(object, &property, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        }
    }
    static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var property = address(selector, scope: scope), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size) == noErr, size > 0 else { return [] }
        var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &result) == noErr else { return [] }
        return result
    }
    static func device(_ uid: String) -> AudioObjectID? {
        var property = address(kAudioHardwarePropertyTranslateUIDToDevice), qualifier = uid as CFString
        var result = AudioObjectID(0), size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &qualifier) {
            AudioObjectGetPropertyData(system, &property, UInt32(MemoryLayout<CFString>.size), $0, &size, &result)
        }
        return status == noErr && result != 0 ? result : nil
    }
    static func uid(_ device: AudioObjectID) -> String? {
        var value: CFString = "" as CFString
        return read(device, kAudioDevicePropertyDeviceUID, into: &value) ? value as String : nil
    }
    static func defaultUID(_ selector: AudioObjectPropertySelector = kAudioHardwarePropertyDefaultOutputDevice) -> String? {
        var value = AudioObjectID(0)
        return read(system, selector, into: &value) ? uid(value) : nil
    }
    @discardableResult static func select(_ uid: String, selector: AudioObjectPropertySelector = kAudioHardwarePropertyDefaultOutputDevice) -> Bool {
        guard let device = device(uid) else { return false }
        return write(system, selector, value: device) == noErr
    }
    static func outputLevel(_ device: AudioObjectID) -> Double? {
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar] {
            var value: Float32 = 0
            if read(device, selector, into: &value, scope: kAudioObjectPropertyScopeOutput), value.isFinite {
                return Double(min(1, max(0, value)))
            }
        }
        return nil
    }
    static func setOutputLevel(_ device: AudioObjectID, level: Double) -> Bool {
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar] {
            if write(device, selector, value: Float32(level), scope: kAudioObjectPropertyScopeOutput) == noErr { return true }
        }
        return false
    }
    static func hasHardwareVolume(_ uid: String) -> Bool {
        guard let device = device(uid) else { return false }
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar] {
            for element in [AudioObjectPropertyElement(0), 1, 2] {
                var property = address(selector, scope: kAudioObjectPropertyScopeOutput)
                property.mElement = element
                var settable = DarwinBoolean(false)
                if AudioObjectHasProperty(device, &property),
                   AudioObjectIsPropertySettable(device, &property, &settable) == noErr,
                   settable.boolValue { return true }
            }
        }
        return false
    }
    static var requiredComponentBuild: Int {
        VirtualOutputSupport.requiredComponentBuild(bundledBuild: Bundle.main.object(forInfoDictionaryKey: "VorssaintAudioDriverBuild") as? Int)
    }
    private static func installedComponents() -> [(uid: String, info: [String: Any])] {
        [("VorssaintAudio", "com.vorssaint.utils.software-volume.driver", VirtualOutputSupport.deviceUID),
         ("VorssaintAudioFork", "com.vorssaint.audiofork.driver", VirtualOutputSupport.legacyDeviceUID)].compactMap { name, identifier, uid in
            let plist = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/\(name).driver/Contents/Info.plist")
            guard let data = try? Data(contentsOf: plist),
                  let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == identifier else { return nil }
            return (uid, info)
        }
    }
    static var installedComponentBuild: Int? {
        installedComponents().compactMap { ($0.info["CFBundleVersion"] as? String).flatMap(Int.init) }.max()
    }
    static func componentDevice() -> AudioObjectID? {
        for component in installedComponents() {
            guard let version = component.info["CFBundleVersion"] as? String,
                  (Int(version) ?? 0) >= requiredComponentBuild,
                  let device = device(component.uid) else { continue }
            // A newly copied plist must not make an old, still-loaded duplex
            // driver appear ready while Core Audio is restarting.
            let selectors: [AudioObjectPropertySelector] = [VirtualOutputSupport.ownerSelector, 0x766b6579, 0x7670636d]
            if selectors.allSatisfy({ selector in
                var property = address(selector)
                return AudioObjectHasProperty(device, &property)
            }) { return device }
        }
        return nil
    }
    static func installedComponentExists() -> Bool { !installedComponents().isEmpty }
    static func restorableOutputs(systemSounds: Bool) -> [String] {
        objects(system, kAudioHardwarePropertyDevices).compactMap { device in
            var alive: UInt32 = 0, hidden: UInt32 = 0, eligible: UInt32 = 0
            let selector = systemSounds ? kAudioDevicePropertyDeviceCanBeDefaultSystemDevice : kAudioDevicePropertyDeviceCanBeDefaultDevice
            guard read(device, kAudioDevicePropertyDeviceIsAlive, into: &alive), alive != 0,
                  read(device, selector, into: &eligible, scope: kAudioObjectPropertyScopeOutput), eligible != 0,
                  let uid = uid(device), !VirtualOutputSupport.isSoftwareOutput(uid) else { return nil }
            _ = read(device, kAudioDevicePropertyIsHidden, into: &hidden)
            return hidden == 0 ? uid : nil
        }
    }
    static func physicalDevices() -> [(uid: String, id: AudioObjectID)] {
        objects(system, kAudioHardwarePropertyDevices).compactMap { device in
            var alive: UInt32 = 0, hidden: UInt32 = 0, transport: UInt32 = 0
            guard read(device, kAudioDevicePropertyDeviceIsAlive, into: &alive), alive != 0,
                  read(device, kAudioDevicePropertyTransportType, into: &transport),
                  transport != kAudioDeviceTransportTypeVirtual,
                  transport != kAudioDeviceTransportTypeAggregate,
                  let uid = uid(device), channels(device, scope: kAudioObjectPropertyScopeOutput).reduce(0, +) >= 2 else { return nil }
            _ = read(device, kAudioDevicePropertyIsHidden, into: &hidden)
            return hidden == 0 ? (uid, device) : nil
        }
    }
    static func channels(_ object: AudioObjectID, scope: AudioObjectPropertyScope) -> [UInt32] {
        var property = address(kAudioDevicePropertyStreamConfiguration, scope: scope), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return [] }
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bytes.deallocate() }
        guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, bytes) == noErr else { return [] }
        return UnsafeMutableAudioBufferListPointer(bytes.assumingMemoryBound(to: AudioBufferList.self)).map(\.mNumberChannels)
    }
    /// The HAL guarantees a NULL callback buffer for each disabled stream.
    /// Configure and read back BEFORE AudioDeviceStart; failure means no IO.
    static func setStreamUsage(_ device: AudioObjectID, ioProc: AudioDeviceIOProcID?,
                               scope: AudioObjectPropertyScope, enabled: [UInt32]) -> Bool {
        guard let ioProc, !enabled.isEmpty,
              objects(device, kAudioDevicePropertyStreams, scope: scope).count == enabled.count,
              let offset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn) else { return false }
        let size = offset + enabled.count * MemoryLayout<UInt32>.size
        let raw = UnsafeMutableRawPointer.allocate(byteCount: max(size, MemoryLayout<AudioHardwareIOProcStreamUsage>.size),
                                                   alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment)
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        let usage = raw.assumingMemoryBound(to: AudioHardwareIOProcStreamUsage.self)
        usage.pointee.mIOProc = unsafeBitCast(ioProc, to: UnsafeMutableRawPointer.self)
        usage.pointee.mNumberStreams = UInt32(enabled.count)
        let flags = raw.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
        for index in enabled.indices { flags[index] = enabled[index] }
        var property = address(kAudioDevicePropertyIOProcStreamUsage, scope: scope)
        guard AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(size), raw) == noErr else { return false }
        var returnedSize = UInt32(size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &returnedSize, raw) == noErr,
              returnedSize == UInt32(size), usage.pointee.mNumberStreams == UInt32(enabled.count) else { return false }
        return enabled.indices.allSatisfy { flags[$0] == enabled[$0] }
    }
    static func inputStreamCount(_ device: AudioObjectID) -> Int? {
        var property = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr,
              size % UInt32(MemoryLayout<AudioObjectID>.size) == 0 else { return nil }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard objects(device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput).count == count else { return nil }
        return count
    }
    static func isolatePhysicalOutputInput(_ device: AudioObjectID, ioProc: AudioDeviceIOProcID?) -> Bool {
        guard let count = inputStreamCount(device) else { return false }
        guard let mask = VirtualOutputSupport.inputMask(streamCount: count, source: .physicalOutput(streams: count)) else { return false }
        if mask.isEmpty { return true }
        return setStreamUsage(device, ioProc: ioProc, scope: kAudioObjectPropertyScopeInput, enabled: mask)
    }
    static func isolateProcessTapInput(_ device: AudioObjectID, ioProc: AudioDeviceIOProcID?, physicalUID: String) -> Bool {
        guard let physical = self.device(physicalUID), let count = inputStreamCount(physical) else { return false }
        return isolateInput(device, ioProc: ioProc, source: .processTap(physicalStreams: count))
    }
    static func isolateInput(_ device: AudioObjectID, ioProc: AudioDeviceIOProcID?,
                             source: VirtualOutputSupport.InputSource) -> Bool {
        let count = objects(device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput).count
        guard let mask = VirtualOutputSupport.inputMask(streamCount: count, source: source) else { return false }
        return setStreamUsage(device, ioProc: ioProc, scope: kAudioObjectPropertyScopeInput, enabled: mask)
    }
    static func floatFormats(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        let streams = objects(device, kAudioDevicePropertyStreams, scope: scope)
        guard !streams.isEmpty else { return false }
        return streams.allSatisfy { stream in
            var format = AudioStreamBasicDescription()
            return read(stream, kAudioStreamPropertyVirtualFormat, into: &format)
                && format.mFormatID == kAudioFormatLinearPCM && format.mBitsPerChannel == 32
                && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
                && format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0
        }
    }
}
