// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics
import IOKit.hid

/// Temporarily suppresses keyboard input so MacBook keys can be wiped without
/// sending input to the system. The menu panel toggle is the only way to start
/// and stop the mode; no overlay, shortcut or timed escape is shown.
final class CleaningModeManager: ObservableObject {
    enum Status: Equatable {
        case inactive
        case active
        case failed(CleaningModeError)

        var isActive: Bool {
            if case .active = self { return true }
            return false
        }
    }

    enum CleaningModeError: Equatable {
        case missingInputMonitoring
        case missingAccessibility
        case eventTapFailed
    }

    static let shared = CleaningModeManager()

    private static let systemDefinedEventType = CGEventType(rawValue: CleaningSystemKeyEvent.systemDefinedEventTypeRawValue)!

    @Published private(set) var status: Status = .inactive

    var isActive: Bool { status.isActive }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    func toggle() { isActive ? deactivate() : activate() }

    func activate() {
        guard !isActive else { return }

        guard Permissions.shared.inputMonitoring else {
            status = .failed(.missingInputMonitoring)
            promptForInputMonitoring()
            return
        }
        guard Permissions.shared.accessibility else {
            status = .failed(.missingAccessibility)
            promptForAccessibility()
            return
        }

        guard installTap() else {
            status = .failed(.eventTapFailed)
            KeyboardDebounceService.shared.syncWithPreferences()
            return
        }

        KeyboardDebounceService.shared.suspend()
        status = .active
    }

    func deactivate() {
        guard isActive else { return }
        removeTap()
        status = .inactive
        KeyboardDebounceService.shared.syncWithPreferences()
    }

    func statusText(_ strings: Strings) -> String {
        switch status {
        case .inactive:
            return strings.keyboardCleaningInactive
        case .active:
            return strings.keyboardCleaningActive
        case let .failed(error):
            return error.localizedDescription(strings)
        }
    }

    // MARK: - Event tap supplement

    private func installTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << Self.systemDefinedEventType.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<CleaningModeManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }
        return nil
    }

    // MARK: - Permission prompts

    private func promptForInputMonitoring() {
        let strings = L10n.shared.s
        let alert = NSAlert()
        alert.messageText = strings.keyboardCleaningInputMonitoring
        alert.informativeText = strings.keyboardCleaningNeedsInputMonitoring
        alert.addButton(withTitle: strings.permissionOpenSettings)
        alert.addButton(withTitle: strings.uninstallerCancel)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.shared.requestInputMonitoring()
            Permissions.shared.openInputMonitoringSettings()
        }
    }

    private func promptForAccessibility() {
        let strings = L10n.shared.s
        let alert = NSAlert()
        alert.messageText = strings.cleaningNeedsAxTitle
        alert.informativeText = strings.cleaningNeedsAxBody
        alert.addButton(withTitle: strings.permissionOpenSettings)
        alert.addButton(withTitle: strings.uninstallerCancel)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.shared.requestAccessibility()
            Permissions.shared.openAccessibilitySettings()
        }
    }
}

extension CleaningModeManager.CleaningModeError {
    func localizedDescription(_ strings: Strings) -> String {
        switch self {
        case .missingInputMonitoring:
            return strings.keyboardCleaningNeedsInputMonitoring
        case .missingAccessibility:
            return "\(strings.permissionRequired): \(strings.permissionAccessibility)"
        case .eventTapFailed:
            return strings.cleaningNeedsAxBody
        }
    }
}
