// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Intercepts the Delete/Backspace key in Finder to move files to Trash (Command+Backspace)
/// and Shift+Backspace to Undo (Command+Z).
final class FinderDeleteShortcuts: ObservableObject {
    static let shared = FinderDeleteShortcuts()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private static let finderBundleID = "com.apple.finder"

    private enum Key {
        static let backspace: Int64 = 51
    }

    private init() {}

    var isRunning: Bool { tap != nil }

    func syncWithPreferences() {
        let enabled = AppFeature.finderDeleteShortcuts.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.finderDeleteShortcutsEnabled)
        if enabled, Permissions.shared.accessibility {
            installTap()
        } else {
            removeTap()
        }
    }

    func suspend() {
        removeTap()
    }

    // MARK: - Event tap

    private func installTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<FinderDeleteShortcuts>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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
            return Unmanaged.passUnretained(event)
        }
        
        guard Permissions.shared.accessibility else { return Unmanaged.passUnretained(event) }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Only intercept when Finder is frontmost
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finderBundleID,
              AXIsProcessTrusted(),
              !isEditingText()
        else { return Unmanaged.passUnretained(event) }
        
        let eventModifiers = GlobalShortcutModifiers(cgFlags: flags).intersection(.validMask)
        let deleteShortcut = GlobalShortcutRole.finderDelete.savedShortcut
        let revertShortcut = GlobalShortcutRole.finderRevert.savedShortcut
        
        // Ensure no extra modifiers like Command/Option are secretly held when matching empty modifiers
        // GlobalShortcut ignores these by default when comparing if .validMask is applied, but we
        // must be careful since CGEventFlags can be noisy.
        
        let isDelete = (keyCode == deleteShortcut.keyCode && eventModifiers == deleteShortcut.modifiers)
        let isRevert = (keyCode == revertShortcut.keyCode && eventModifiers == revertShortcut.modifiers)

        if isRevert {
            // Revert (Command + Z)
            postSyntheticKeyEvent(keyCode: 6, flags: .maskCommand) // 6 is Z
            return nil
        } else if isDelete {
            // Delete (Command + Backspace)
            postSyntheticKeyEvent(keyCode: 51, flags: .maskCommand) // 51 is Backspace
            return nil
        }

        // Drop the original event if handled, otherwise pass through
        return Unmanaged.passUnretained(event)
    }

    private func postSyntheticKeyEvent(keyCode: Int64, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false) else { return }
        
        keyDown.flags = flags
        keyUp.flags = flags
        
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    private func isEditingText() -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, "AXFocusedUIElement" as CFString, &focused) == .success,
              let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = focused as! AXUIElement
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXRole" as CFString, &roleRef) == .success,
              let role = roleRef as? String else { return false }
        return ["AXTextField", "AXTextArea", "AXComboBox", "AXSecureTextField"].contains(role)
    }
}
