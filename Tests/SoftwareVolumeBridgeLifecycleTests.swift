// SPDX-License-Identifier: GPL-3.0-or-later
import CoreAudio
import Foundation

/// The complete production bridge constructor/stop runs here; hardware IO and
/// the authorized PCM pump are replaced, so no physical output is touched.
enum SoftwareVolumeBridgeLifecycleTests {
    final class Storage {
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        init(rate: Double) throws {}
        deinit { pointer.deallocate() }
    }
    final class Pump {
        init(device: AudioObjectID, rate: Double, storage: Storage) throws { HAL.events.append("pump") }
        func stop() { HAL.events.append("pump-stop") }
    }
    enum Clock { static func sleep(forTimeInterval: Double) {} }
    enum HAL {
        static var events: [String] = []
        static var callback: AudioDeviceIOBlock?
        static var startStatus: OSStatus = noErr, createStatus: OSStatus = noErr
        static var isolated = true, deliverCallback = true
        static func uid(_ device: AudioObjectID) -> String? { VirtualOutputSupport.deviceUID }
        static func device(_ uid: String) -> AudioObjectID? { 42 }
        static func channels(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> [UInt32] {
            scope == kAudioObjectPropertyScopeInput ? [] : [2]
        }
        static func read<T>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) -> Bool {
            if selector == kAudioDevicePropertyNominalSampleRate { value = Double(48000) as! T }
            else if selector == kAudioDevicePropertyBufferFrameSize { value = UInt32(512) as! T }
            else if selector == kAudioDevicePropertyDeviceIsAlive { value = UInt32(1) as! T }
            else { return false }
            return true
        }
        static func write<T>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, value: T) -> OSStatus { noErr }
        static func floatFormats(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool { true }
        static func outputFormatSummary(_ device: AudioObjectID) -> String { "Float32 stereo fixture" }
        static func isolatePhysicalOutputInput(_ device: AudioObjectID, ioProc: AudioDeviceIOProcID?) -> Bool {
            events.append("isolate"); return isolated
        }
        static func create(_ proc: UnsafeMutablePointer<AudioDeviceIOProcID?>, _ device: AudioObjectID,
                           _ queue: DispatchQueue?, _ block: @escaping AudioDeviceIOBlock) -> OSStatus {
            events.append("create")
            guard createStatus == noErr else { return createStatus }
            proc.pointee = unsafeBitCast(UInt(1), to: AudioDeviceIOProcID.self)
            callback = block; return noErr
        }
        static func start(_ device: AudioObjectID, _ proc: AudioDeviceIOProcID?) -> OSStatus {
            events.append("start")
            if startStatus == noErr, deliverCallback {
                var stamp = AudioTimeStamp(), buffers = AudioBufferList()
                withUnsafePointer(to: &stamp) { time in
                    withUnsafeMutablePointer(to: &buffers) { data in callback?(time, data, time, data, time) }
                }
            }
            return startStatus
        }
        static func stop(_ device: AudioObjectID, _ proc: AudioDeviceIOProcID?) -> OSStatus { events.append("stop"); return noErr }
        static func destroy(_ device: AudioObjectID, _ proc: AudioDeviceIOProcID?) -> OSStatus {
            events.append("destroy"); callback = nil; return noErr
        }
        static func render(_ storage: UnsafeMutableRawPointer, _ output: UnsafeMutablePointer<AudioBufferList>) -> Int32 { 1 }
        static func healthy(_ storage: UnsafeMutableRawPointer) -> Int32 { 1 }
        static func reset() {
            events = []; callback = nil; startStatus = noErr; createStatus = noErr
            isolated = true; deliverCallback = true
        }
    }
    static func run(_ suite: TestSuite) {
        defer { HAL.reset() }
        HAL.reset(); HAL.startStatus = kAudioHardwareNotRunningError
        do {
            _ = try Bridge(virtual: 99, physicalUID: "hdmi")
            suite.expect(false, "a failed physical start is surfaced")
        } catch {
            suite.expect(!HAL.events.contains("stop") && HAL.events.filter { $0 == "destroy" }.count == 1,
                         "a failed start destroys its callback without stopping a device it never started")
            let message = error.localizedDescription
            suite.expect(message.contains("start") && message.contains("stop") && message.contains(String(kAudioHardwareNotRunningError)),
                         "startup diagnosis preserves the failed operation, numeric OSStatus and printable fourCC")
        }
        HAL.reset(); HAL.isolated = false
        do { _ = try Bridge(virtual: 99, physicalUID: "hdmi"); suite.expect(false, "input isolation failure aborts startup") }
        catch {
            suite.expect(!HAL.events.contains("start") && !HAL.events.contains("stop") && HAL.events.filter { $0 == "destroy" }.count == 1,
                         "privacy preflight failure destroys only the unstarted callback")
        }
        HAL.reset(); HAL.createStatus = kAudioHardwareBadDeviceError
        do { _ = try Bridge(virtual: 99, physicalUID: "hdmi"); suite.expect(false, "callback creation failure aborts startup") }
        catch {
            suite.expect(!HAL.events.contains("destroy") && !HAL.events.contains("stop"),
                         "failed creation owns no callback or running output to tear down")
            suite.expect(error.localizedDescription.contains(String(kAudioHardwareBadDeviceError)),
                         "callback creation diagnosis preserves the original OSStatus")
        }
        HAL.reset()
        do {
            let bridge = try Bridge(virtual: 99, physicalUID: "hdmi")
            bridge.stop(); bridge.stop()
            suite.expect(HAL.events.filter { $0 == "stop" }.count == 1 && HAL.events.filter { $0 == "destroy" }.count == 1,
                         "a started output stops and destroys exactly once across repeated stop calls")
        } catch { suite.expect(false, "healthy physical output starts successfully") }
        HAL.reset(); HAL.deliverCallback = false
        do { _ = try Bridge(virtual: 99, physicalUID: "hdmi"); suite.expect(false, "missing callback times out") }
        catch {
            suite.expect(HAL.events.filter { $0 == "stop" }.count == 1 && HAL.events.filter { $0 == "destroy" }.count == 1,
                         "startup timeout stops a successfully started device and destroys once")
            suite.expect(error.localizedDescription.contains("render"), "startup timeout keeps its distinct diagnostic")
        }
    }
}
