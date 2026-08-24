// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics

final class AlwaysOnTopService: ObservableObject {
    static let shared = AlwaysOnTopService()

    @Published private(set) var isRunning = false

    var pinningAvailable: Bool { pinning.client.isAvailable }

    private let pinning = AlwaysOnTopPinning(client: AlwaysOnTopSkyLightClient.shared)
    private var map = AlwaysOnTopPinMap()
    private var borders: [CGWindowID: AlwaysOnTopBorder] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var watchedWindows: [CGWindowID: AXUIElement] = [:]

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var registeredShortcut: GlobalShortcut?
    private var terminateObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?

    private init() {}

    func syncWithPreferences() {
        let wanted = AppFeature.alwaysOnTop.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.alwaysOnTopEnabled)
        if wanted, Permissions.shared.accessibility {
            start()
        } else {
            stop()
        }
    }

    func toggleFrontmost() {
        guard isRunning else { return }
        guard let pid = frontmostPID() else { return }
        guard let windowID = WindowActivator.focusedWindowID(for: pid) else { return }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let exceptions = UserDefaults.standard.stringArray(forKey: DefaultsKey.alwaysOnTopExcludedApps) ?? []
        if AlwaysOnTopSupport.isExcluded(bundleIdentifier: bundleID, exceptions: exceptions) { return }
        if map.contains(windowID) {
            unpin(windowID)
            return
        }
        guard let original = pinning.pin(windowID) else { return }
        map.pin(AlwaysOnTopPin(windowID: windowID, originalLevel: original, pid: pid))
        if let element = focusedAXWindow(pid: pid) {
            watch(windowID: windowID, pid: pid, element: element)
        }
        if UserDefaults.standard.bool(forKey: DefaultsKey.alwaysOnTopShowBorder) {
            let border = AlwaysOnTopBorder()
            let color = UserDefaults.standard.string(forKey: DefaultsKey.alwaysOnTopBorderColor) ?? "#00ADEF"
            let thickness = UserDefaults.standard.object(forKey: DefaultsKey.alwaysOnTopBorderThickness) as? Double ?? 4
            border.show(windowID: windowID, colorHex: color, thickness: CGFloat(thickness))
            borders[windowID] = border
        }
        if UserDefaults.standard.bool(forKey: DefaultsKey.alwaysOnTopPlaySound) {
            (NSSound(named: "Tink") ?? NSSound(named: "Funk"))?.play()
        }
    }

    func unpinAll() {
        for pin in map.unpinAll() {
            _ = pinning.unpin(pin.windowID, originalLevel: pin.originalLevel)
            dropBorder(pin.windowID)
            unwatch(windowID: pin.windowID, pid: pin.pid)
        }
    }

    func handleAX(element: AXUIElement, notification: String) {
        let windowID = AXWindowResolver.windowID(for: element)
        if notification == (kAXUIElementDestroyedNotification as String) {
            if let windowID { unpin(windowID) }
            return
        }
        guard let windowID else { return }
        if notification == (kAXWindowMiniaturizedNotification as String) {
            borders[windowID]?.setMinimized(true)
        } else if notification == (kAXWindowDeminiaturizedNotification as String) {
            borders[windowID]?.setMinimized(false)
            borders[windowID]?.updateFrame()
        }
    }

    private func start() {
        registerHotkey()
        if terminateObserver == nil {
            terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.handleAppTerminated(app.processIdentifier)
            }
        }
        if defaultsObserver == nil {
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.unpinExcluded()
            }
        }
        isRunning = true
    }

    private func stop() {
        unpinAll()
        unregisterHotkey()
        if let terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver)
            self.terminateObserver = nil
        }
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
        isRunning = false
    }

    private func unpin(_ windowID: CGWindowID) {
        guard let pin = map.unpin(windowID) else { return }
        _ = pinning.unpin(windowID, originalLevel: pin.originalLevel)
        dropBorder(windowID)
        unwatch(windowID: windowID, pid: pin.pid)
    }

    private func dropBorder(_ windowID: CGWindowID) {
        borders[windowID]?.hide()
        borders[windowID] = nil
    }

    private func handleAppTerminated(_ pid: pid_t) {
        for pin in map.remove(pid: pid) {
            _ = pinning.unpin(pin.windowID, originalLevel: pin.originalLevel)
            dropBorder(pin.windowID)
            unwatch(windowID: pin.windowID, pid: pid)
        }
    }

    private func unpinExcluded() {
        let exceptions = UserDefaults.standard.stringArray(forKey: DefaultsKey.alwaysOnTopExcludedApps) ?? []
        let gone = AlwaysOnTopSupport.windowIDsToUnpinAfterExclude(
            pins: Array(map.pins.values),
            exceptions: exceptions,
            bundleIDForPID: { pid in
                NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            }
        )
        for windowID in gone { unpin(windowID) }
    }

    private func frontmostPID() -> pid_t? {
        let ownBundleID = Bundle.main.bundleIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownKeyWindow = NSApp.keyWindow
        let hasFocusedResizableOwnWindow = NSApp.isActive
            && ownKeyWindow?.styleMask.contains(.resizable) == true
            && !(ownKeyWindow is NSPanel)
        let pid = hasFocusedResizableOwnWindow
            ? ownPID
            : NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let pid else { return nil }
        if hasFocusedResizableOwnWindow, pid == ownPID { return pid }
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular,
              !app.isHidden,
              app.bundleIdentifier != ownBundleID
        else { return nil }
        return pid
    }

    private func focusedAXWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.35)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private func watch(windowID: CGWindowID, pid: pid_t, element: AXUIElement) {
        if observers[pid] == nil {
            var observerRef: AXObserver?
            guard AXObserverCreate(pid, alwaysOnTopAXCallback, &observerRef) == .success,
                  let observer = observerRef else { return }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers[pid] = observer
        }
        guard let observer = observers[pid] else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXUIElementDestroyedNotification,
                     kAXWindowMiniaturizedNotification,
                     kAXWindowDeminiaturizedNotification] {
            AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
        watchedWindows[windowID] = element
    }

    private func unwatch(windowID: CGWindowID, pid: pid_t) {
        if let observer = observers[pid], let element = watchedWindows[windowID] {
            for name in [kAXUIElementDestroyedNotification,
                         kAXWindowMiniaturizedNotification,
                         kAXWindowDeminiaturizedNotification] {
                AXObserverRemoveNotification(observer, element, name as CFString)
            }
        }
        watchedWindows[windowID] = nil
        if map.pins(for: pid).isEmpty, let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }

    private func registerHotkey() {
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.alwaysOnTopShortcut,
                                            fallback: .alwaysOnTopDefault)
        if hotKeyRef != nil, registeredShortcut == shortcut { return }
        unregisterHotkey()
        if eventHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                if let event {
                    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                }
                guard hotKeyID.signature == 0x5655_4154, hotKeyID.id == 1
                else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<AlwaysOnTopService>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { service.toggleFrontmost() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }
        let hotKeyID = EventHotKeyID(signature: 0x5655_4154, id: 1) // 'VUAT'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.carbonKeyCode,
                                         shortcut.carbonModifiers,
                                         hotKeyID,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &ref)
        if status == noErr, let ref {
            hotKeyRef = ref
            registeredShortcut = shortcut
        } else {
            hotKeyRef = nil
            registeredShortcut = nil
        }
    }

    private func unregisterHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        registeredShortcut = nil
    }
}

private func alwaysOnTopAXCallback(_ observer: AXObserver,
                                  _ element: AXUIElement,
                                  _ notification: CFString,
                                  _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let service = Unmanaged<AlwaysOnTopService>.fromOpaque(refcon).takeUnretainedValue()
    DispatchQueue.main.async {
        service.handleAX(element: element, notification: notification as String)
    }
}
