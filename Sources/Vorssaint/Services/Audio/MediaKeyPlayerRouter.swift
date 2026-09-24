// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices

/// Play/Pause, Next and Previous go to whatever the system last saw playing,
/// which is often a browser tab rather than the music player that is open.
/// With this option on, a music app that is running and scriptable takes
/// those keys instead. With no such player, or before the person allows this
/// app to control it, the keys keep their system behavior.
final class MediaKeyPlayerRouter {
    static let shared = MediaKeyPlayerRouter()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var activationObserver: NSObjectProtocol?
    private var lastActivePID: Int32?
    /// Keys whose press went to the player, so their repeats and release
    /// never reach the system on their own.
    private var consumedKeyCodes = Set<UInt16>()
    private var capabilitiesByBundle: [URL: NotchMusicAutomationCapabilities?] = [:]
    private var musicAppByBundle: [URL: Bool] = [:]
    private var grantedPIDs = Set<Int32>()
    private var consentRequestedPIDs = Set<Int32>()
    private let queue = DispatchQueue(label: "com.vorssaint.media-keys", qos: .userInitiated)

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
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private func start() {
        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      self?.isMusicApp(app) == true else { return }
                self?.lastActivePID = app.processIdentifier
            }
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
            guard let player = player(for: key.command) else { return Unmanaged.passUnretained(event) }
            consumedKeyCodes.insert(key.code)
            queue.async { Self.send(player.event, to: player.pid) }
            return nil
        }
    }

    /// The music app to send `command` to, when one is running, declares the
    /// command and has already been allowed to receive it. A player still
    /// waiting for that consent is asked once, and the key keeps its system
    /// behavior until the answer comes back.
    private func player(for command: MediaKeyPlayerSupport.Command)
        -> (pid: Int32, event: NotchMusicAutomationCapabilities.Event)? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let candidates = NSWorkspace.shared.runningApplications.compactMap {
            app -> (MediaKeyPlayerSupport.Player, NotchMusicAutomationCapabilities.Event)? in
            guard app.processIdentifier != ownPID, !app.isTerminated, isMusicApp(app),
                  let url = app.bundleURL, let capabilities = capabilities(for: url),
                  let event = capabilities.commands[command.dictionaryName]
                    ?? (command == .toggle ? capabilities.playCommand : nil)
            else { return nil }
            return (MediaKeyPlayerSupport.Player(pid: app.processIdentifier, launched: app.launchDate), event)
        }
        guard let pid = MediaKeyPlayerSupport.preferredPlayer(candidates.map(\.0), lastActivePID: lastActivePID),
              let event = candidates.first(where: { $0.0.pid == pid })?.1,
              isAllowed(pid) else { return nil }
        return (pid, event)
    }

    private func isAllowed(_ pid: Int32) -> Bool {
        if grantedPIDs.contains(pid) { return true }
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        switch AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) {
        case noErr:
            grantedPIDs.insert(pid)
            return true
        case OSStatus(errAEEventWouldRequireUserConsent):
            if consentRequestedPIDs.insert(pid).inserted {
                queue.async {
                    let target = NSAppleEventDescriptor(processIdentifier: pid)
                    _ = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
                }
            }
            return false
        default:
            return false
        }
    }

    private func capabilities(for url: URL) -> NotchMusicAutomationCapabilities? {
        if let cached = capabilitiesByBundle[url] { return cached }
        let loaded = NotchMusicAutomationCapabilities.load(bundleURL: url)
        capabilitiesByBundle[url] = loaded
        return loaded
    }

    /// Players declare the music category, as the island's player list reads it.
    private func isMusicApp(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL else { return false }
        if let cached = musicAppByBundle[url] { return cached }
        let music = Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
            == "public.app-category.music"
        musicAppByBundle[url] = music
        return music
    }

    private static func send(_ command: NotchMusicAutomationCapabilities.Event, to pid: Int32) {
        let event = NSAppleEventDescriptor(eventClass: command.eventClass, eventID: command.eventID,
                                           targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                                           returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        // A playback action is never retried: a timeout may follow delivery.
        _ = try? event.sendEvent(options: [.noReply, .neverInteract, .dontRecord], timeout: 1)
    }
}
