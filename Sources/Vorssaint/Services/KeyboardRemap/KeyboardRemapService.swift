// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import IOKit
import IOKit.hidsystem

/// HID mappings handle modifiers (including mouse chords); a session tap
/// handles language switching and complete shortcut down/up pairs. Main thread.
final class KeyboardRemapService: ObservableObject {
    static let shared = KeyboardRemapService()
    @Published private(set) var isRunning = false
    @Published private(set) var statusKey: String?
    var ownsNativeQuit: Bool {
        guard isRunning else { return false }
        return config.shortcutRules.contains { $0.enabled && $0.source.isQuitShortcut }
    }
    private var config = KeyboardRemapConfiguration()
    private var state = KeyboardRemapSupport.State()
    private let translatedSource = CGEventSource(stateID: .hidSystemState)
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var mappingGuard: KeyboardRemapGuard.Handle?
    private var wakeObserver: NSObjectProtocol?
    private var repairPending = false
    private var lastRepair: TimeInterval = 0

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.syncWithPreferences() }
    }

    static func recoverPendingAtLaunch() {
        let defaults = UserDefaults.standard
        let owned = KeyboardRemapSupport.storedMappings(defaults.string(forKey: DefaultsKey.keyboardRemapOwnedMappings) ?? "")
        if KeyboardRemapGuard.clear(owned: owned) { defaults.removeObject(forKey: DefaultsKey.keyboardRemapOwnedMappings) }
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let wanted = AppFeature.keyboardRemap.isAvailable && defaults.bool(forKey: DefaultsKey.keyboardRemapEnabled)
        guard wanted, SessionActivity.shared.isActive, AXIsProcessTrusted() else {
            guard suspend() else { return }
            statusKey = wanted && !AXIsProcessTrusted() ? "permissionStatus" : nil
            return
        }
        // Both services manage the same global HID table. Keep one owner and
        // finish restoring this table before Super Key begins its queued write.
        guard !(AppFeature.superKey.isAvailable && defaults.bool(forKey: DefaultsKey.superKeyEnabled)) else {
            guard suspend() else { return }
            statusKey = "superkeyStatus"
            return
        }
        let next = KeyboardRemapConfiguration(defaults: defaults)
        if let error = next.validationKey {
            guard suspend() else { return }
            statusKey = error
            return
        }
        if next.isEmpty {
            guard suspend() else { return }
            statusKey = "emptyRules"
            return
        }
        guard !KeyboardRemapSupport.hasModifierConflict(
            KeyboardRemapGuard.systemModifierMappings(), wanted: next.mappings) else {
            suspend()
            statusKey = "modifierConflict"
            return
        }
        if next != config, !suspend() { return }
        config = next
        guard installTap() else { statusKey = "tapStatus"; return }
        let owned = KeyboardRemapSupport.storedMappings(defaults.string(forKey: DefaultsKey.keyboardRemapOwnedMappings) ?? "")
        let report = KeyboardRemapGuard.read()
        guard report.status == 0,
              let table = KeyboardRemapSupport.mergedMappings(report.output, owned: owned, wanted: config.mappings) else {
            suspend()
            statusKey = "conflictStatus"
            return
        }
        if !config.mappings.isEmpty, mappingGuard == nil {
            guard let handle = KeyboardRemapGuard.Handle(mappings: config.mappings) else {
                suspend(); statusKey = "recoveryStatus"; return
            }
            mappingGuard = handle
        }
        // Write ahead: a partial write or process crash remains recoverable.
        defaults.set(KeyboardRemapSupport.storage(config.mappings), forKey: DefaultsKey.keyboardRemapOwnedMappings)
        guard KeyboardRemapGuard.write(table) else {
            suspend(); statusKey = "writeStatus"; return
        }
        isRunning = true
        statusKey = nil
    }

    @discardableResult
    func suspend() -> Bool {
        isRunning = false
        state.reset()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        let defaults = UserDefaults.standard
        let owned = KeyboardRemapSupport.storedMappings(defaults.string(forKey: DefaultsKey.keyboardRemapOwnedMappings) ?? "")
        let cleared = KeyboardRemapGuard.clear(owned: owned)
        let guardCleared = mappingGuard?.stop() ?? cleared
        mappingGuard = nil
        if cleared || guardCleared { defaults.removeObject(forKey: DefaultsKey.keyboardRemapOwnedMappings) }
        else { statusKey = "clearStatus" }
        return cleared || guardCleared
    }

    private func installTap() -> Bool {
        if let tap, CGEvent.tapIsEnabled(tap: tap) { return true }
        if tap != nil { suspend() }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                return Unmanaged<KeyboardRemapService>.fromOpaque(info).takeUnretainedValue().handle(type: type, event: event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            state.reset()
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else { DispatchQueue.main.async { self.syncWithPreferences() } }
            return Unmanaged.passUnretained(event)
        }
        guard isRunning, !OwnKeyEvent.isPosted(event) else { return Unmanaged.passUnretained(event) }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        guard type == .flagsChanged || type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }
        // A hot-plugged keyboard can arrive without the HID table. Its first
        // raw source event schedules a repair, never a subprocess inside a tap.
        if type != .keyUp, let physicalKey = KeyboardRemapKey.at(key),
           config.mappings.contains(where: { $0.source == physicalKey.usage }) {
            scheduleRepair()
        }
        guard type != .flagsChanged else { return Unmanaged.passUnretained(event) }
        let label = GlobalShortcut.layoutKeyLabel(for: key, usesCommand: true)?.lowercased()
        let action = state.decide(key: key, down: type == .keyDown,
                                  repeatKey: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                                  flags: event.flags, commandLabel: label, config: config)
        switch action {
        case .pass: return Unmanaged.passUnretained(event)
        case .swallow: return nil
        case .inputSource: selectNextInputSource(); return nil
        case .capsLock: toggleCapsLock(); return nil
        case .application(let bundleID):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            } else {
                DispatchQueue.main.async { self.statusKey = "missingApp" }
            }
            return nil
        case .key(let destination, let flags):
            guard let translatedSource else { return nil }
            event.setSource(translatedSource)
            event.setIntegerValueField(.keyboardEventKeycode, value: destination)
            event.flags = flags.union(event.flags.intersection(.maskAlphaShift))
            // Alternate quit is intentional and bypasses Quit Protection's
            // Command-Q confirmation, regardless of event-tap installation order.
            event.setIntegerValueField(.eventSourceUserData, value: OwnKeyEvent.keyboardRemapMarker)
            return Unmanaged.passUnretained(event)
        }
    }

    private func scheduleRepair() {
        guard !repairPending, ProcessInfo.processInfo.systemUptime - lastRepair > 3 else { return }
        repairPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.repairPending = false
            self.lastRepair = ProcessInfo.processInfo.systemUptime
            self.syncWithPreferences()
        }
    }

    private func selectNextInputSource() {
        let sources = InputSourceSelection.selectableInputSources()
        let ids = sources.compactMap { InputSourceSelection.inputSourceString($0, property: kTISPropertyInputSourceID) }
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let nextID = SuperKeySupport.nextInputSourceID(
                currentID: InputSourceSelection.inputSourceString(current, property: kTISPropertyInputSourceID), enabledIDs: ids),
              let next = sources.first(where: {
                  InputSourceSelection.inputSourceString($0, property: kTISPropertyInputSourceID) == nextID
              }) else { return }
        _ = TISSelectInputSource(next)
    }

    private func toggleCapsLock() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS else { return }
        defer { IOServiceClose(connection) }
        var on = false
        if IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &on) == KERN_SUCCESS {
            IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), !on)
        }
    }
}
