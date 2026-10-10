// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreAudio
import Foundation

/// Observes output activity, not audio samples. Some players publish no Now
/// Playing metadata; Core Audio can still identify the app opening an output.
/// All HAL work and listener ownership stay on one queue. No tap or timer.
final class NotchAudioSourceReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.vorssaint.notch-audio-sources", qos: .utility)
    /// Main-thread generation rejects a read finishing after stop/restart.
    private var generation = UUID()
    /// Queue-only state.
    private var active = false
    private var globalListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var pending: DispatchWorkItem?
    private var publish: (([NotchPlaybackSource]) -> Void)?

    func start(onChange: @escaping ([NotchPlaybackSource]) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard #available(macOS 14.4, *) else { onChange([]); return }
        generation = UUID()
        let requested = generation
        queue.async { [weak self] in
            guard let self else { return }
            self.removeListeners()
            self.active = true
            self.publish = { [weak self] sources in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == requested else { return }
                    onChange(sources)
                }
            }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRead() }
            var address = Self.address(kAudioHardwarePropertyProcessObjectList)
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address,
                                                    self.queue, block) == noErr {
                self.globalListener = block
            }
            self.readSources()
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        generation = UUID()
        queue.async { [weak self] in self?.removeListeners() }
    }

    private func scheduleRead() {
        guard #available(macOS 14.4, *), active else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.readSources() }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    @available(macOS 14.4, *)
    private func readSources() {
        pending = nil
        guard active else { return }
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
              size <= 4096 * MemoryLayout<AudioObjectID>.size else { return }
        var objects = [AudioObjectID](repeating: 0, count: max(1, Int(size) / MemoryLayout<AudioObjectID>.size))
        let status = objects.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { return }
        objects = Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
        let current = Set(objects)
        for (object, block) in processListeners where !current.contains(object) {
            var runningAddress = Self.address(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(object, &runningAddress, queue, block)
            processListeners.removeValue(forKey: object)
        }
        var sources: [NotchPlaybackSource] = []
        for object in objects {
            if processListeners[object] == nil {
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRead() }
                var runningAddress = Self.address(kAudioProcessPropertyIsRunningOutput)
                if AudioObjectAddPropertyListenerBlock(object, &runningAddress, queue, block) == noErr {
                    processListeners[object] = block
                }
            }
            var running: UInt32 = 0
            var pid: pid_t = 0
            guard Self.readOutput(object, &running), running != 0,
                  Self.readPID(object, &pid), pid > 0,
                  let app = ResponsibleProcess.regularAppOwner(of: pid), !app.isTerminated,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let bundle = NotchAudioSourceSupport.bundleIdentifier(
                      process: app.bundleIdentifier,
                      bundle: app.bundleURL.flatMap { Bundle(url: $0)?.bundleIdentifier }),
                  !sources.contains(where: { $0.pid == app.processIdentifier }) else { continue }
            let category = app.bundleURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String }
            sources.append(NotchPlaybackSource(pid: app.processIdentifier, bundleIdentifier: bundle,
                isMusicApp: NotchPlaybackSource.isMusicApplication(bundleIdentifier: bundle, parentBundleIdentifier: nil,
                                                                  category: category),
                isPlaying: true, hasTrack: false, displayName: app.localizedName, isAudioOnly: true))
        }
        publish?(Array(sources.sorted { $0.pid < $1.pid }.prefix(16)))
    }

    private func removeListeners() {
        active = false
        pending?.cancel(); pending = nil
        publish = nil
        if #available(macOS 14.4, *) {
            if let block = globalListener {
                var address = Self.address(kAudioHardwarePropertyProcessObjectList)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
            }
            for (object, block) in processListeners {
                var address = Self.address(kAudioProcessPropertyIsRunningOutput)
                AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
            }
        }
        globalListener = nil
        processListeners = [:]
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func readOutput(_ object: AudioObjectID, _ value: inout UInt32) -> Bool {
        var address = address(kAudioProcessPropertyIsRunningOutput)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }

    private static func readPID(_ object: AudioObjectID, _ value: inout pid_t) -> Bool {
        var address = address(kAudioProcessPropertyPID)
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }
}
