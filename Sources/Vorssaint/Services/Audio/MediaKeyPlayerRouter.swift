// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreAudio
import CoreServices

/// Play/Pause, Next and Previous go to whatever the system last saw playing,
/// which is often a browser tab rather than the music player that is open.
/// With this option on, a running music app takes those keys instead, as
/// `MediaKeyPlayerSupport.route` decides. The tap callback only reads memory:
/// the players, their consent and what is sounding are resolved off it and
/// refreshed on launch, quit, activation, after every routed key and after a
/// failed send, so a revoked consent hands the next key back to the system.
final class MediaKeyPlayerRouter {
    static let shared = MediaKeyPlayerRouter()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastActivePID: Int32?
    private var players: [MediaKeyPlayerSupport.Player] = []
    /// Dictionary events per player, looked up when a key is routed.
    private var events: [Int32: [MediaKeyPlayerSupport.Command: NotchMusicAutomationCapabilities.Event]] = [:]
    /// Main-thread state for presses routed to a player. A repeat can start a
    /// dictionary scan, and its release must then end that same player's scan.
    private struct RoutedKey {
        let pid: Int32
        let press: NotchMusicAutomationCapabilities.Event
        let scan: NotchMusicAutomationCapabilities.Event?
        let resume: NotchMusicAutomationCapabilities.Event?
        var scrubQueued = false
    }
    private var routedKeys: [UInt16: RoutedKey] = [:]
    /// Only touched on sendQueue, after a scan was actually delivered.
    private var activeScrubs: [UInt16: (pid: Int32, resume: NotchMusicAutomationCapabilities.Event)] = [:]
    private var consentRequestedPIDs = Set<Int32>()
    private var refreshGeneration = 0
    private let audioActivity = MediaKeyAudioActivity()

    /// Reading bundles, dictionaries and consent can block; it stays here.
    private let snapshotQueue = DispatchQueue(label: "com.vorssaint.media-keys.snapshot", qos: .userInitiated)
    /// Only touched on `snapshotQueue`.
    private var musicAppByBundle: [URL: Bool] = [:]
    private var capabilitiesByBundle: [URL: NotchMusicAutomationCapabilities?] = [:]
    /// Sends and the consent prompt never wait on each other.
    private let sendQueue = DispatchQueue(label: "com.vorssaint.media-keys.send", qos: .userInitiated)
    private let consentQueue = DispatchQueue(label: "com.vorssaint.media-keys.consent", qos: .userInitiated)
    /// Both queues go through it, so `stop()` drops what they still hold.
    private let queuedWork = MediaKeyPlayerSupport.Gate()

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    private var isWanted: Bool {
        AppFeature.musicBlock.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.mediaKeysPlayerOnly)
    }

    func syncWithPreferences() {
        if SessionActivitySupport.tapShouldRun(featureWanted: isWanted,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            start()
        } else {
            stop()
        }
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        queuedWork.close()
        clearRoutedKeys()
        consentRequestedPIDs.removeAll()
        refreshGeneration &+= 1
        players = []
        events = [:]
        audioActivity.stop()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    private func start() {
        queuedWork.open()
        if workspaceObservers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didLaunchApplicationNotification,
                         NSWorkspace.didTerminateApplicationNotification,
                         NSWorkspace.didActivateApplicationNotification] {
                workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    guard let self else { return }
                    if name == NSWorkspace.didActivateApplicationNotification,
                       let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                       self.players.contains(where: { $0.pid == app.processIdentifier }) {
                        self.lastActivePID = app.processIdentifier
                    }
                    self.refreshPlayers()
                })
            }
            audioActivity.start()
            refreshPlayers()
        }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
        guard tap == nil else { return }
        let systemDefined = CGEventType(rawValue: MusicLaunchSupport.systemDefinedEventTypeRawValue)!
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let router = Unmanaged<MediaKeyPlayerRouter>.fromOpaque(userInfo).takeUnretainedValue()
            return router.handle(type: type, event: event)
        }
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                              options: .defaultTap,
                                              eventsOfInterest: CGEventMask(1 << systemDefined.rawValue),
                                              callback: callback,
                                              userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        else { return }
        tap = created
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            clearRoutedKeys()
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == MusicLaunchSupport.systemDefinedEventTypeRawValue,
              let nsEvent = NSEvent(cgEvent: event),
              let key = MediaKeyPlayerSupport.key(subtype: Int(nsEvent.subtype.rawValue), data1: nsEvent.data1)
        else { return Unmanaged.passUnretained(event) }

        switch key.phase {
        case .up:
            guard let routed = routedKeys.removeValue(forKey: key.code) else {
                return Unmanaged.passUnretained(event)
            }
            if routed.scrubQueued {
                sendQueue.async { [weak self] in self?.finishScrub(key.code) }
            } else if routed.scan != nil {
                // A short press skips only on release. A hold started a scan
                // on the original track instead of skipping it first.
                sendPlayback(routed.press, to: routed.pid)
            }
            return nil
        case .repeatDown:
            guard var routed = routedKeys[key.code] else { return Unmanaged.passUnretained(event) }
            if !routed.scrubQueued, let scan = routed.scan, let resume = routed.resume {
                routed.scrubQueued = true
                routedKeys[key.code] = routed
                let pid = routed.pid
                queuedWork.async(on: sendQueue) { [weak self] in
                    guard Self.send(scan, to: pid) else { return }
                    self?.activeScrubs[key.code] = (pid, resume)
                }
            }
            return nil
        case .down:
            let route = MediaKeyPlayerSupport.route(key.command, players: players,
                                                    sounding: audioActivity.sounding,
                                                    lastActivePID: lastActivePID,
                                                    ownPID: ProcessInfo.processInfo.processIdentifier)
            switch route {
            case .system:
                return Unmanaged.passUnretained(event)
            case .askConsent(let pid):
                requestConsent(pid)
                return Unmanaged.passUnretained(event)
            case .player(let pid):
                guard let available = events[pid],
                      let command = MediaKeyPlayerSupport.playbackCommand(for: key.command,
                                                                           available: Set(available.keys)),
                      let appleEvent = available[command] else { return Unmanaged.passUnretained(event) }
                let scan = MediaKeyPlayerSupport.scrubCommand(for: key.command, available: Set(available.keys))
                    .flatMap { available[$0] }
                routedKeys[key.code] = RoutedKey(pid: pid, press: appleEvent,
                                                 scan: scan, resume: available[.resume])
                if scan == nil { sendPlayback(appleEvent, to: pid) }
                // Consent can be revoked at any time; recheck it off the tap.
                refreshPlayers()
                return nil
            }
        }
    }

    private func sendPlayback(_ command: NotchMusicAutomationCapabilities.Event, to pid: Int32) {
        queuedWork.async(on: sendQueue) { [weak self] in
            let delivered = Self.send(command, to: pid)
            DispatchQueue.main.async {
                // A refusal, especially revoked consent, hands later keys
                // back to the system after the next snapshot.
                if !delivered { self?.refreshPlayers() }
            }
        }
    }

    /// A scan is sticky in Music's scripting dictionary. Its resume is a
    /// cleanup of work already delivered, not a new playback request. It runs
    /// on the send queue after any pending scan, even if the router stopped.
    private func finishScrub(_ code: UInt16) {
        guard let active = activeScrubs.removeValue(forKey: code) else { return }
        _ = Self.send(active.resume, to: active.pid)
    }

    private func clearRoutedKeys() {
        routedKeys.removeAll()
        sendQueue.async { [weak self] in
            guard let self else { return }
            for code in Array(self.activeScrubs.keys) { self.finishScrub(code) }
        }
    }

    /// Resolves the running players off the tap and publishes them on main.
    private func refreshPlayers() {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (Int32, String, URL, Date?)? in
            guard app.processIdentifier != ownPID, !app.isTerminated,
                  let bundle = app.bundleIdentifier, let url = app.bundleURL else { return nil }
            return (app.processIdentifier, bundle, url, app.launchDate)
        }
        snapshotQueue.async { [weak self] in
            guard let self else { return }
            var players: [MediaKeyPlayerSupport.Player] = []
            var events: [Int32: [MediaKeyPlayerSupport.Command: NotchMusicAutomationCapabilities.Event]] = [:]
            for (pid, bundle, url, launched) in apps where self.isMusicApp(url) {
                guard let capabilities = self.capabilities(for: url) else { continue }
                var available: [MediaKeyPlayerSupport.Command: NotchMusicAutomationCapabilities.Event] = [:]
                for command in MediaKeyPlayerSupport.Command.allCases {
                    available[command] = capabilities.commands[command.dictionaryName]
                }
                guard [.toggle, .next, .previous, .back].contains(where: { available[$0] != nil })
                else { continue }
                events[pid] = available
                players.append(MediaKeyPlayerSupport.Player(pid: pid, bundleIdentifier: bundle, launched: launched,
                                                            commands: Set(available.keys),
                                                            access: Self.access(to: pid)))
            }
            DispatchQueue.main.async {
                guard self.refreshGeneration == generation, !self.workspaceObservers.isEmpty else { return }
                self.players = players
                self.events = events
            }
        }
    }

    /// Asked once per player, off the tap and apart from the sends. The key
    /// that asked keeps its system behavior; the answer lands in the next
    /// snapshot.
    private func requestConsent(_ pid: Int32) {
        guard consentRequestedPIDs.insert(pid).inserted else { return }
        queuedWork.async(on: consentQueue) { [weak self] in
            let target = NSAppleEventDescriptor(processIdentifier: pid)
            _ = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
            DispatchQueue.main.async { self?.refreshPlayers() }
        }
    }

    private static func access(to pid: Int32) -> MediaKeyPlayerSupport.Access {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        switch AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) {
        case noErr: return .granted
        case OSStatus(errAEEventWouldRequireUserConsent): return .consent
        default: return .denied
        }
    }

    /// Players declare the music category, as the island's player list reads it.
    private func isMusicApp(_ url: URL) -> Bool {
        if let cached = musicAppByBundle[url] { return cached }
        let music = Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
            == "public.app-category.music"
        musicAppByBundle[url] = music
        return music
    }

    private func capabilities(for url: URL) -> NotchMusicAutomationCapabilities? {
        if let cached = capabilitiesByBundle[url] { return cached }
        let loaded = NotchMusicAutomationCapabilities.load(bundleURL: url)
        capabilitiesByBundle[url] = loaded
        return loaded
    }

    private static func send(_ command: NotchMusicAutomationCapabilities.Event, to pid: Int32) -> Bool {
        let event = NSAppleEventDescriptor(eventClass: command.eventClass, eventID: command.eventID,
                                           targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                                           returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        // A playback action is never retried: a timeout may follow delivery.
        guard let reply = try? event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: 1)
        else { return false }
        return (reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0) == 0
    }
}

/// The processes Core Audio reports as producing output, kept current by
/// its own listeners so the key tap only reads the last answer. Empty before
/// macOS 14.4, where processes are not reported, which leaves the keys with
/// the player whenever one is open.
final class MediaKeyAudioActivity {
    private let queue = DispatchQueue(label: "com.vorssaint.media-keys.audio", qos: .utility)
    private let lock = NSLock()
    private var current: [MediaKeyPlayerSupport.SoundingProcess] = []
    /// Only touched on `queue`.
    private var running = false
    private var processObjects: [AudioObjectID: Set<AudioObjectPropertySelector>] = [:]

    /// Some HAL versions change IsRunningOutput without notifying its
    /// listener. IsRunning reports output IO starting or stopping, so either
    /// notification refreshes the authoritative IsRunningOutput reading.
    private static let runningSelectors: [AudioObjectPropertySelector] = [
        kAudioProcessPropertyIsRunningOutput, kAudioProcessPropertyIsRunning,
    ]

    var sounding: [MediaKeyPlayerSupport.SoundingProcess] { lock.withLock { current } }

    private static let callback: AudioObjectPropertyListenerProc = { _, _, _, client in
        guard let client else { return noErr }
        Unmanaged<MediaKeyAudioActivity>.fromOpaque(client).takeUnretainedValue().scheduleRefresh()
        return noErr
    }

    private var client: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    func start() {
        guard #available(macOS 14.4, *) else { return }
        queue.async { [self] in
            guard !running else { return }
            running = true
            var address = Self.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &address, Self.callback, client)
            refresh()
        }
    }

    func stop() {
        queue.async { [self] in
            guard running else { return }
            running = false
            var address = Self.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &address, Self.callback, client)
            for (object, selectors) in processObjects {
                for selector in selectors {
                    var address = Self.address(selector)
                    AudioObjectRemovePropertyListener(object, &address, Self.callback, client)
                }
            }
            processObjects.removeAll()
            lock.withLock { current = [] }
        }
    }

    private func scheduleRefresh() {
        queue.async { [self] in if running { refresh() } }
    }

    private func refresh() {
        guard #available(macOS 14.4, *) else { return }
        let objects = Self.processObjectList()
        for object in objects {
            for selector in Self.runningSelectors where processObjects[object]?.contains(selector) != true {
                var address = Self.address(selector)
                if AudioObjectAddPropertyListener(object, &address, Self.callback, client) == noErr {
                    processObjects[object, default: []].insert(selector)
                }
            }
        }
        for object in processObjects.keys.filter({ !objects.contains($0) }) {
            guard let selectors = processObjects.removeValue(forKey: object) else { continue }
            for selector in selectors {
                var address = Self.address(selector)
                AudioObjectRemovePropertyListener(object, &address, Self.callback, client)
            }
        }
        let sounding = objects.compactMap { object -> MediaKeyPlayerSupport.SoundingProcess? in
            var isRunning: UInt32 = 0
            var pid: pid_t = 0
            guard Self.read(object, kAudioProcessPropertyIsRunningOutput, &isRunning), isRunning != 0,
                  Self.read(object, kAudioProcessPropertyPID, &pid), pid > 0 else { return nil }
            var bundle: Unmanaged<CFString>?
            let identifier = Self.read(object, kAudioProcessPropertyBundleID, &bundle)
                ? bundle?.takeRetainedValue() as String? : nil
            return MediaKeyPlayerSupport.SoundingProcess(pid: pid,
                                                         bundleIdentifier: identifier?.isEmpty == false ? identifier : nil)
        }
        lock.withLock { current = sounding }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjectList() -> Set<AudioObjectID> {
        guard #available(macOS 14.4, *) else { return [] }
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return Set(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                _ value: inout T) -> Bool {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer)) == noErr
        }
    }
}
