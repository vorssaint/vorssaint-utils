// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreAudio
import Foundation

/// One regular app represented by Core Audio's process objects. "Running
/// output" is intentionally named as the HAL names it: it means an active
/// output stream, not proof that non-silent samples reached the speakers.
struct AudioProcessActivity: Equatable {
    let ownerPid: pid_t
    let bundleIdentifier: String?
    let name: String
    let audioObjects: [AudioObjectID]
    let isRunningOutput: Bool
    let bypassesProcessTap: Bool
}

struct AudioProcessActivitySnapshot: Equatable {
    static let empty = AudioProcessActivitySnapshot(apps: [])

    let apps: [AudioProcessActivity]
}

/// The single owner of Core Audio process discovery for the app-volume mixer
/// and features that need to react to output activity. It listens to process
/// list changes and each process object's IsRunningOutput property, coalesces
/// notification bursts, then publishes one shared snapshot. No polling runs.
final class AudioProcessActivityMonitor {
    static let shared = AudioProcessActivityMonitor()

    typealias Observer = (AudioProcessActivitySnapshot) -> Void

    private struct Group {
        let ownerPid: pid_t
        var bundleIdentifier: String?
        var name: String
        var audioObjects: [AudioObjectID] = []
        var isRunningOutput = false
    }

    private let halQueue = DispatchQueue(
        label: "com.vorssaint.utils.audio-process-activity",
        qos: .userInitiated)
    private var observers: [UUID: Observer] = [:]
    private var runningListeners = Set<AudioObjectID>()
    private var snapshot = AudioProcessActivitySnapshot.empty
    private var isMonitoring = false
    private var refreshGeneration: Int?
    private var refreshAgain = false
    private var refreshPending = false
    private var lifecycleGeneration = 0
    private var lastRefreshAt: CFAbsoluteTime = 0

    private init() {}

    @discardableResult
    func observe(_ observer: @escaping Observer) -> UUID {
        dispatchPrecondition(condition: .onQueue(.main))
        let id = UUID()
        observers[id] = observer
        if !isMonitoring { start() }
        observer(snapshot)
        return id
    }

    func removeObserver(_ id: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        observers.removeValue(forKey: id)
        if observers.isEmpty { stop() }
    }

    private static let listenerCallback: AudioObjectPropertyListenerProc = { _, _, _, client in
        guard let client else { return noErr }
        let monitor = Unmanaged<AudioProcessActivityMonitor>.fromOpaque(client).takeUnretainedValue()
        DispatchQueue.main.async { monitor.scheduleRefresh() }
        return noErr
    }

    private var listenerClient: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    private func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        lifecycleGeneration &+= 1
        var address = Self.processListAddress()
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject),
                                       &address,
                                       Self.listenerCallback,
                                       listenerClient)
        refresh()
    }

    private func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        lifecycleGeneration &+= 1
        refreshGeneration = nil
        refreshAgain = false
        refreshPending = false
        var processAddress = Self.processListAddress()
        AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject),
                                          &processAddress,
                                          Self.listenerCallback,
                                          listenerClient)
        pruneRunningListeners(keeping: [])
        snapshot = .empty
    }

    private func scheduleRefresh() {
        guard isMonitoring else { return }
        guard !refreshPending else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastRefreshAt
        if elapsed >= Self.refreshInterval {
            lastRefreshAt = now
            refresh()
            return
        }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refreshInterval - elapsed) { [weak self] in
            guard let self, self.isMonitoring else { return }
            self.refreshPending = false
            self.lastRefreshAt = CFAbsoluteTimeGetCurrent()
            self.refresh()
        }
    }

    private static let refreshInterval: CFAbsoluteTime = 0.2

    private func refresh() {
        guard isMonitoring else { return }
        guard refreshGeneration == nil else {
            refreshAgain = true
            return
        }
        let generation = lifecycleGeneration
        refreshGeneration = generation
        let ownPid = ProcessInfo.processInfo.processIdentifier
        halQueue.async { [weak self] in
            let snapshot = Self.readSnapshot(ownPid: ownPid)
            DispatchQueue.main.async {
                self?.apply(snapshot, generation: generation)
            }
        }
    }

    private func apply(_ next: AudioProcessActivitySnapshot, generation: Int) {
        guard refreshGeneration == generation else { return }
        refreshGeneration = nil
        guard isMonitoring, lifecycleGeneration == generation else { return }

        let repeatRefresh = refreshAgain
        refreshAgain = false
        let objects = Set(next.apps.flatMap(\.audioObjects))
        pruneRunningListeners(keeping: objects)
        for object in objects { subscribeToRunningChanges(of: object) }

        if snapshot != next {
            snapshot = next
            for observer in observers.values { observer(next) }
        }
        if repeatRefresh { refresh() }
    }

    private func subscribeToRunningChanges(of object: AudioObjectID) {
        guard !runningListeners.contains(object) else { return }
        var address = Self.runningOutputAddress()
        if AudioObjectAddPropertyListener(object,
                                          &address,
                                          Self.listenerCallback,
                                          listenerClient) == noErr {
            runningListeners.insert(object)
        }
    }

    private func pruneRunningListeners(keeping current: Set<AudioObjectID>) {
        for object in runningListeners where !current.contains(object) {
            var address = Self.runningOutputAddress()
            AudioObjectRemovePropertyListener(object,
                                              &address,
                                              Self.listenerCallback,
                                              listenerClient)
            runningListeners.remove(object)
        }
    }

    private static func readSupportedSnapshot(ownPid: pid_t) -> AudioProcessActivitySnapshot {
        var groups: [pid_t: Group] = [:]
        for object in audioProcessObjects() {
            var pid: pid_t = -1
            guard read(object, kAudioProcessPropertyPID, &pid), pid > 0, pid != ownPid,
                  let app = ResponsibleProcess.regularAppOwner(of: pid) else { continue }

            let ownerPid = app.processIdentifier
            let fallbackName = app.localizedName ?? "pid \(ownerPid)"
            let name = ResponsibleProcess.displayName(pid: ownerPid, fallback: fallbackName)
            let bundleIdentifier = app.bundleIdentifier
                ?? (pid == ownerPid ? processBundleIdentifier(of: object) : nil)
            var group = groups[ownerPid]
                ?? Group(ownerPid: ownerPid, bundleIdentifier: bundleIdentifier, name: name)
            if group.bundleIdentifier == nil { group.bundleIdentifier = bundleIdentifier }
            group.audioObjects.append(object)
            var running: UInt32 = 0
            if read(object, kAudioProcessPropertyIsRunningOutput, &running), running != 0 {
                group.isRunningOutput = true
            }
            groups[ownerPid] = group
        }

        let apps = groups.values.map { group in
            AudioProcessActivity(
                ownerPid: group.ownerPid,
                bundleIdentifier: group.bundleIdentifier,
                name: group.name,
                audioObjects: group.audioObjects.sorted(),
                isRunningOutput: group.isRunningOutput,
                bypassesProcessTap: MixerRoutingSupport.bypassesProcessTap(
                    bundleIdentifier: group.bundleIdentifier,
                    name: group.name))
        }.sorted { lhs, rhs in
            if lhs.ownerPid != rhs.ownerPid { return lhs.ownerPid < rhs.ownerPid }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return AudioProcessActivitySnapshot(apps: apps)
    }

    private static func readSnapshot(ownPid: pid_t) -> AudioProcessActivitySnapshot {
        guard AudioProcessActivitySupport.isSupported else { return .empty }
        return readSupportedSnapshot(ownPid: ownPid)
    }

    private static func audioProcessObjects() -> [AudioObjectID] {
        var address = processListAddress()
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return [] }
        var objects = [AudioObjectID](repeating: 0,
                                      count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private static func processBundleIdentifier(of object: AudioObjectID) -> String? {
        var bundleRef: CFString = "" as CFString
        guard read(object, kAudioProcessPropertyBundleID, &bundleRef) else { return nil }
        let bundleID = bundleRef as String
        return bundleID.isEmpty ? nil : bundleID
    }

    private static func read<T>(_ object: AudioObjectID,
                                _ selector: AudioObjectPropertySelector,
                                _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer)) == noErr
        }
    }

    private static func processListAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func runningOutputAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
