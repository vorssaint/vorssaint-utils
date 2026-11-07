// SPDX-License-Identifier: GPL-3.0-or-later
import CoreAudio
import Foundation
import SoftwareVolumePCM

/// The complete production bridge constructor/stop runs here; hardware IO and
/// the authorized PCM pump are replaced, so no physical output is touched.
enum SoftwareVolumeBridgeLifecycleTests {
    final class Storage {
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        init(rate: Double, channels: UInt32, channelMap: [UInt32]) throws {}
        deinit { pointer.deallocate() }
    }
    final class Pump {
        init(device: AudioObjectID, rate: Double, channels: UInt32, storage: Storage) throws { HAL.events.append("pump") }
        func stop() { HAL.events.append("pump-stop") }
    }
    enum Clock { static func sleep(forTimeInterval: Double) {} }
    enum HAL {
        static var events: [String] = []
        static var callback: AudioDeviceIOBlock?
        static var startStatus: OSStatus = noErr, createStatus: OSStatus = noErr
        static var isolated = true, deliverCallback = true
        static var capacity: UInt32 = 2, semanticChannels: UInt32 = 2, virtualChannels: UInt32 = 2
        static var rate: Double = 48000, layoutLabel: UInt32 = kAudioChannelLabel_Left
        static var configurationSucceeds = true
        static func uid(_ device: AudioObjectID) -> String? { VirtualOutputSupport.deviceUID }
        static func device(_ uid: String) -> AudioObjectID? { 42 }
        static func channels(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> [UInt32] {
            scope == kAudioObjectPropertyScopeInput ? [] : [device == 99 ? virtualChannels : capacity]
        }
        static func outputConfiguration(_ device: AudioObjectID) -> Data? {
            var format = vs_format_default(semanticChannels)
            format.descriptions.0.mChannelLabel = layoutLabel
            return withUnsafeBytes(of: &format) { Data($0) }
        }
        static func configureOutput(_ device: AudioObjectID, configuration: Data) -> Bool {
            events.append("configure")
            if configurationSucceeds { virtualChannels = semanticChannels }
            return configurationSucceeds
        }
        static func outputChannelMap(_ device: AudioObjectID, configuration: Data) -> [UInt32]? { Array(0..<semanticChannels) }
        static func read<T>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) -> Bool {
            if selector == kAudioDevicePropertyNominalSampleRate { value = rate as! T }
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
            capacity = 2; semanticChannels = 2; virtualChannels = 2
            rate = 48000; layoutLabel = kAudioChannelLabel_Left; configurationSucceeds = true
        }
    }
    static func run(_ suite: TestSuite) {
        defer { HAL.reset() }
        for channels: UInt32 in [2, 6, 8] {
            for rate: Double in [48000, 96000, 192000] {
                HAL.reset(); HAL.capacity = channels; HAL.semanticChannels = channels; HAL.rate = rate
                do {
                    let bridge = try Bridge(virtual: 99, physicalUID: "hdmi")
                    suite.expect(bridge.configurationIsCurrent() && HAL.virtualChannels == channels,
                                 "channel-aware output starts at \(channels) channels and \(rate) Hz")
                    suite.expect(HAL.events.first == "configure" && HAL.events.contains("isolate"),
                                 "output layout settles before pump/IO and physical input isolation remains required")
                    HAL.layoutLabel = kAudioChannelLabel_Center
                    suite.expect(!bridge.configurationIsCurrent(), "a channel-label change rebuilds the bridge even at the same channel count")
                    HAL.layoutLabel = kAudioChannelLabel_Left; HAL.rate *= 2
                    suite.expect(!bridge.configurationIsCurrent(), "a sample-rate change invalidates the previous PCM session")
                    bridge.stop()
                } catch { suite.expect(false, "supported multichannel output starts") }
            }
        }
        HAL.reset(); HAL.capacity = 6
        do {
            let bridge = try Bridge(virtual: 99, physicalUID: "stereo-in-wide-stream")
            suite.expect(HAL.virtualChannels == 2 && bridge.configurationIsCurrent(),
                         "a stereo layout on a six-channel HDMI stream stays stereo")
            bridge.stop()
        } catch { suite.expect(false, "stereo topology in a wider stream is preserved") }
        HAL.reset(); HAL.configurationSucceeds = false
        do { _ = try Bridge(virtual: 99, physicalUID: "hdmi"); suite.expect(false, "failed layout negotiation aborts startup") }
        catch { suite.expect(!HAL.events.contains("create"), "an unverified channel layout never starts output IO") }
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
