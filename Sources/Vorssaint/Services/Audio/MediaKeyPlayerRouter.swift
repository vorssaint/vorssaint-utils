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
    /// Keys whose press went to the player, so their repeats and release
    /// never reach the system on their own.
    private var consumedKeyCodes = Set<UInt16>()
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
        consumedKeyCodes.removeAll()
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
            consumedKeyCodes.removeAll()
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
            return consumedKeyCodes.remove(key.code) != nil ? nil : Unmanaged.passUnretained(event)
        case .repeatDown:
            return consumedKeyCodes.contains(key.code) ? nil : Unmanaged.passUnretained(event)
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
                guard let appleEvent = events[pid]?[key.command] else { return Unmanaged.passUnretained(event) }
                consumedKeyCodes.insert(key.code)
                sendQueue.async { [weak self] in
                    let delivered = Self.send(appleEvent, to: pid)
                    DispatchQueue.main.async {
                        // A refusal, a revoked consent above all, shows in
                        // the next snapshot and hands later keys back.
                        if !delivered { self?.refreshPlayers() }
                    }
                }
                // Consent can be revoked at any time; recheck it off the tap.
                refreshPlayers()
                return nil
            }
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
                guard !available.isEmpty else { continue }
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
        consentQueue.async { [weak self] in
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
    private var processObjects = Set<AudioObjectID>()

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
            for object in processObjects {
                var running = Self.address(kAudioProcessPropertyIsRunningOutput)
                AudioObjectRemovePropertyListener(object, &running, Self.callback, client)
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
        for object in objects where !processObjects.contains(object) {
            var address = Self.address(kAudioProcessPropertyIsRunningOutput)
            if AudioObjectAddPropertyListener(object, &address, Self.callback, client) == noErr {
                processObjects.insert(object)
            }
        }
        for object in processObjects.subtracting(objects) {
            var address = Self.address(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListener(object, &address, Self.callback, client)
            processObjects.remove(object)
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
