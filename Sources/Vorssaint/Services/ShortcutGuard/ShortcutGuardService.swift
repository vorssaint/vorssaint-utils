// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

/// Suppresses selected shortcuts while a selected application or process is
/// frontmost. Bundled applications are matched by bundle identifier; programs
/// without one use the same normalized executable-path identity as the app
/// exception lists.
final class ShortcutGuardService: ObservableObject {
    static let shared = ShortcutGuardService()
    private static let ownProcessID = Int64(getpid())

    @Published private(set) var isRunning = false
    @Published private(set) var revision = 0

    private let eventLock = NSLock()
    private let lifecycleLock = NSLock()

    private var selectedIdentities = Set<String>()
    private var blocked = Set<GlobalShortcut>()
    private var frontmostIdentity: String?
    private var swallowedKeyCodes = Set<Int64>()
    private var captureSuspended = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingStartAfterStop = false
    private var lifecycleGeneration: UInt = 0
    private var activationObserver: NSObjectProtocol?

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    var appIdentities: [String] {
        let values = UserDefaults.standard.stringArray(
            forKey: DefaultsKey.shortcutGuardAppIdentities
        ) ?? []
        return Array(Set(values.filter { !$0.isEmpty })).sorted {
            let lhsName = InstalledApps.name(for: $0)
            let rhsName = InstalledApps.name(for: $1)
            let result = lhsName.localizedCaseInsensitiveCompare(rhsName)
            return result == .orderedSame ? $0 < $1 : result == .orderedAscending
        }
    }

    var blockedShortcuts: [GlobalShortcut] {
        let values = UserDefaults.standard.stringArray(
            forKey: DefaultsKey.shortcutGuardBlockedShortcuts
        ) ?? []
        return Array(Set(values.compactMap(GlobalShortcut.init(storageValue:))))
            .sorted {
                $0.displayString.localizedCaseInsensitiveCompare($1.displayString)
                    == .orderedAscending
            }
    }

    /// Applies the persisted configuration. Main thread only, like the other
    /// feature bindings that own AppKit state.
    func syncWithPreferences() {
        let identities = Set(appIdentities)
        let shortcuts = Set(blockedShortcuts)
        let frontmost = identity(for: NSWorkspace.shared.frontmostApplication)
        eventLock.withLock {
            selectedIdentities = identities
            blocked = shortcuts
            frontmostIdentity = frontmost
            captureSuspended = ShortcutCapture.isCapturing
        }

        let wanted = AppFeature.shortcutGuard.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.shortcutGuardEnabled)
            && !identities.isEmpty
            && !shortcuts.isEmpty

        if SessionActivitySupport.tapShouldRun(
            featureWanted: wanted,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        ) {
            start()
        } else {
            stop()
        }
    }

    func suspend() {
        stop()
    }

    /// Shortcut fields temporarily need every combination to reach their own
    /// recording tap. Keep this tap installed and make it pass through instead
    /// of tearing the system keyboard path down for every recording session.
    func setCapturingShortcut(_ capturing: Bool) {
        eventLock.withLock { captureSuspended = capturing }
    }

    @discardableResult
    func addPickedURL(_ url: URL) -> Bool {
        addPickedURLs([url]) == 1
    }

    @discardableResult
    func addPickedURLs(_ urls: [URL]) -> Int {
        let candidates = urls.compactMap { url -> String? in
            guard ShortcutGuardSupport.acceptsPickedURL(url) else { return nil }
            return MouseAppExceptionSupport.pickedIdentity(for: url)
        }
        let merged = ShortcutGuardSupport.mergingIdentities(
            existing: appIdentities,
            candidates: candidates
        )
        guard merged.addedCount > 0 else { return 0 }

        UserDefaults.standard.set(merged.values, forKey: DefaultsKey.shortcutGuardAppIdentities)
        revision += 1
        syncWithPreferences()
        return merged.addedCount
    }

    func removeAppIdentity(_ identity: String) {
        let current = appIdentities
        let values = current.filter { $0 != identity }
        guard values.count != current.count else { return }
        UserDefaults.standard.set(values, forKey: DefaultsKey.shortcutGuardAppIdentities)
        revision += 1
        syncWithPreferences()
    }

    func addShortcut(_ shortcut: GlobalShortcut) {
        guard shortcut.isValid else { return }
        var values = blockedShortcuts.map(\.storageValue)
        guard !values.contains(shortcut.storageValue) else { return }
        values.append(shortcut.storageValue)
        UserDefaults.standard.set(values, forKey: DefaultsKey.shortcutGuardBlockedShortcuts)
        revision += 1
        syncWithPreferences()
    }

    func removeShortcut(_ shortcut: GlobalShortcut) {
        let current = blockedShortcuts
        let values = current.filter { $0 != shortcut }.map(\.storageValue)
        guard values.count != current.count else { return }
        UserDefaults.standard.set(values, forKey: DefaultsKey.shortcutGuardBlockedShortcuts)
        revision += 1
        syncWithPreferences()
    }

    func selectableApplications(excluding excluded: Set<String>) -> [InstalledApps.InstalledApp] {
        InstalledApps.identityPickerApplications(excluding: excluded)
    }

    // MARK: - Event-tap lifecycle

    private func start() {
        installActivationObserverIfNeeded()

        let startState = lifecycleLock.withLock {
            () -> (thread: Thread?, tap: CFMachPort?, generation: UInt) in
            if tapThread != nil {
                if shouldStopTapThread {
                    pendingStartAfterStop = true
                    return (nil, nil, lifecycleGeneration)
                }
                return (nil, tap, lifecycleGeneration)
            }

            shouldStopTapThread = false
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            let generation = lifecycleGeneration
            let thread = Thread { [weak self] in
                self?.runEventTap(generation: generation)
            }
            thread.name = "Vorssaint Shortcut Guard"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return (thread, nil, generation)
        }

        if let thread = startState.thread {
            thread.start()
        } else if let tap = startState.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            publishRunning(true, generation: startState.generation)
        }
    }

    private func stop() {
        removeActivationObserver()
        eventLock.withLock {
            swallowedKeyCodes.removeAll()
        }

        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool, generation: UInt) in
            shouldStopTapThread = true
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            return (tapRunLoop, tap, tapThread != nil, lifecycleGeneration)
        }

        if let tap = snapshot.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
        publishRunning(false, generation: snapshot.generation)
    }

    private func runEventTap(generation: UInt) {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock {
                tapRunLoop = runLoop
            }

            guard !lifecycleLock.withLock({ shouldStopTapThread }) else {
                finishEventTapThread(generation: generation)
                return
            }

            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.keyUp.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<ShortcutGuardService>
                        .fromOpaque(userInfo).takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                finishFailedEventTapThread(generation: generation)
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock {
                self.tap = tap
                runLoopSource = source
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            if lifecycleLock.withLock({ shouldStopTapThread }) {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                publishRunning(true, generation: generation)
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            eventLock.withLock {
                swallowedKeyCodes.removeAll()
            }
            finishEventTapThread(generation: generation)
        }
    }

    private func finishFailedEventTapThread(generation: UInt) {
        let shouldRestart = clearEventTapThread()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if shouldRestart {
                self.syncWithPreferences()
                return
            }
            let isStillIdle = self.lifecycleLock.withLock {
                generation == self.lifecycleGeneration && self.tapThread == nil
            }
            if isStillIdle {
                self.removeActivationObserver()
            }
            self.publishRunning(false, generation: generation)
        }
    }

    private func finishEventTapThread(generation: UInt) {
        let shouldRestart = clearEventTapThread()
        if shouldRestart {
            DispatchQueue.main.async { [weak self] in
                self?.syncWithPreferences()
            }
        } else {
            publishRunning(false, generation: generation)
        }
    }

    private func clearEventTapThread() -> Bool {
        lifecycleLock.withLock {
            let shouldRestart = pendingStartAfterStop
            tap = nil
            runLoopSource = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingStartAfterStop = false
            return shouldRestart
        }
    }

    private func publishRunning(_ running: Bool, generation: UInt) {
        let update = { [weak self] in
            guard let self else { return }
            let isCurrent = self.lifecycleLock.withLock {
                generation == self.lifecycleGeneration
            }
            guard isCurrent else { return }
            self.isRunning = running
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    private func installActivationObserverIfNeeded() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            let identity = self.identity(for: app)
            self.eventLock.withLock {
                self.frontmostIdentity = identity
            }
        }
    }

    private func removeActivationObserver() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    private func identity(for app: NSRunningApplication?) -> String? {
        guard let app else { return nil }
        return MouseAppExceptionSupport.identity(
            bundleID: app.bundleIdentifier,
            executablePath: app.executableURL?.path
        )
    }

    // MARK: - Event routing

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            eventLock.withLock {
                swallowedKeyCodes.removeAll()
            }
            DispatchQueue.main.async { [weak self] in
                self?.syncWithPreferences()
            }
            return Unmanaged.passUnretained(event)
        }

        let sourceProcessID = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard !ShortcutGuardSupport.isOwnProcessEvent(sourceProcessID: sourceProcessID,
                                                       ownProcessID: Self.ownProcessID) else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // A key-down already claimed by this tap keeps its matching release,
        // even if shortcut recording or an app switch starts in between.
        if type == .keyUp {
            let swallowed = eventLock.withLock {
                swallowedKeyCodes.remove(keyCode) != nil
            }
            return swallowed ? nil : Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let shortcut = GlobalShortcut(
            keyCode: keyCode,
            modifiers: GlobalShortcutModifiers(cgFlags: event.flags)
        )
        let shouldBlock = eventLock.withLock { () -> Bool in
            guard !captureSuspended,
                  ShortcutGuardSupport.shouldBlock(
                frontmostIdentity: frontmostIdentity,
                selectedIdentities: selectedIdentities,
                shortcut: shortcut,
                blockedShortcuts: blocked
            ) else { return false }
            swallowedKeyCodes.insert(keyCode)
            return true
        }
        return shouldBlock ? nil : Unmanaged.passUnretained(event)
    }
}
