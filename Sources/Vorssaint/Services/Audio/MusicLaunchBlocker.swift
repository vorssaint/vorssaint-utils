// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Blocks a new system music-app process only when a trusted media-key
/// observation explains it. Other launches are preserved, including voice,
/// automation, login and headphone commands that deliver no observable key.
/// Nothing runs while the option, feature or required permission is off.
final class MusicLaunchBlocker: ObservableObject {
    static let shared = MusicLaunchBlocker()

    /// The current and the legacy identifier of the system music app.
    static let blockedBundleIDs: Set<String> = ["com.apple.Music", "com.apple.iTunes"]

    @Published private(set) var isMonitoring = false

    private var observers: [NSObjectProtocol] = []
    private var mediaKeyTap: CFMachPort?
    private var mediaKeyTapSource: CFRunLoopSource?
    /// One media key press produces both a will-launch and a did-launch
    /// notification; the replacement should open once, not twice.
    private var lastReplacementLaunch: TimeInterval = 0
    private var lastMediaKeyAt: TimeInterval?
    /// The launch already judged at will-launch. Did-launch for the same
    /// process arrives seconds later, once the app is up, by which time the
    /// click that started it is old enough to look like no gesture at all;
    /// judging it again would terminate a launch the user asked for.
    private var judgedLaunchPID: pid_t?

    private init() {}

    func syncWithPreferences() {
        if isEnabled, AXIsProcessTrusted() {
            start()
        } else {
            stop()
        }
    }

    private var isEnabled: Bool {
        AppFeature.musicBlock.isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.musicBlockEnabled)
    }

    private func start() {
        installMediaKeyTap()
        guard let mediaKeyTap, CGEvent.tapIsEnabled(tap: mediaKeyTap) else {
            stop()
            return
        }
        isMonitoring = true
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        // Will-launch usually wins the race before any window shows;
        // did-launch catches the rare launch that slips past it.
        observers = [NSWorkspace.willLaunchApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.handleLaunch(note)
            }
        }
    }

    func stop() {
        isMonitoring = false
        removeMediaKeyTap()
        lastMediaKeyAt = nil
        judgedLaunchPID = nil
        guard !observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers = []
    }

    private func handleLaunch(_ note: Notification) {
        guard isEnabled, AXIsProcessTrusted(), !observers.isEmpty else {
            stop()
            return
        }
        guard let mediaKeyTap, CGEvent.tapIsEnabled(tap: mediaKeyTap) else {
            lastMediaKeyAt = nil
            isMonitoring = false
            return
        }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              Self.blockedBundleIDs.contains(bundleID),
              app.processIdentifier != judgedLaunchPID else { return }
        judgedLaunchPID = app.processIdentifier
        // One observed key may explain one launch, never a second app process
        // or a relaunch requested while that key is still recent.
        let trigger = lastMediaKeyAt
        lastMediaKeyAt = nil
        guard MusicLaunchSupport.shouldBlockLaunch(
            now: ProcessInfo.processInfo.systemUptime,
            lastTriggerAt: trigger,
            secondsSinceUserGesture: Self.secondsSinceUserGesture
        ) else { return }
        guard app.forceTerminate() || app.terminate() else { return }
        openReplacementIfConfigured()
    }

    /// Pointer buttons and ordinary keys can ask to open an app. Modifier
    /// keys are excluded because holding fn may be how a media key is sent.
    private static let userGestureEventTypes: [CGEventType] = [
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp, .keyDown,
    ]

    /// Read from the session's event state, which needs no tap and no
    /// permission.
    private static var secondsSinceUserGesture: TimeInterval {
        userGestureEventTypes.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.min() ?? .infinity
    }

    private func openReplacementIfConfigured() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastReplacementLaunch > 1.0 else { return }
        lastReplacementLaunch = now

        let path = UserDefaults.standard.string(forKey: DefaultsKey.musicBlockReplacementPath) ?? ""
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        // The replacement must never be the app being blocked, or the two
        // settings would chase each other in a launch-and-kill loop.
        guard let replacementID = Bundle(url: url)?.bundleIdentifier,
              !Self.blockedBundleIDs.contains(replacementID),
              FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func installMediaKeyTap() {
        guard mediaKeyTap == nil else { return }
        let systemDefined = CGEventType(rawValue: MusicLaunchSupport.systemDefinedEventTypeRawValue)!
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let blocker = Unmanaged<MusicLaunchBlocker>.fromOpaque(userInfo).takeUnretainedValue()
            return blocker.handleMediaKeyEvent(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << systemDefined.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }
        mediaKeyTap = tap
        mediaKeyTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeMediaKeyTap() {
        guard let tap = mediaKeyTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let mediaKeyTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), mediaKeyTapSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        mediaKeyTapSource = nil
        mediaKeyTap = nil
    }

    private func handleMediaKeyEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isEnabled, AXIsProcessTrusted(), let mediaKeyTap else {
            stop()
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // A gap in observation invalidates the pending launch decision.
            lastMediaKeyAt = nil
            CGEvent.tapEnable(tap: mediaKeyTap, enable: true)
            isMonitoring = CGEvent.tapIsEnabled(tap: mediaKeyTap)
            return Unmanaged.passUnretained(event)
        }
        guard CGEvent.tapIsEnabled(tap: mediaKeyTap) else {
            lastMediaKeyAt = nil
            isMonitoring = false
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == MusicLaunchSupport.systemDefinedEventTypeRawValue,
              let nsEvent = NSEvent(cgEvent: event),
              MusicLaunchSupport.isMusicLaunchTrigger(subtype: Int(nsEvent.subtype.rawValue),
                                                      data1: nsEvent.data1)
        else { return Unmanaged.passUnretained(event) }
        // A key sent to an existing player cannot explain a later new launch.
        // A race with startup errs on the side of leaving the app alone.
        guard !Self.blockedBundleIDs.contains(where: {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }) else {
            lastMediaKeyAt = nil
            return Unmanaged.passUnretained(event)
        }
        // Use the event's time, not delivery time: a delayed callback must
        // not turn an old key press into fresh launch evidence.
        lastMediaKeyAt = nsEvent.timestamp
        return Unmanaged.passUnretained(event)
    }
}
