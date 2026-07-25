// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

/// One Carbon global hotkey with the register/unregister lifecycle the quick
/// tools share. A single process-wide event handler routes presses to the
/// owning instance by id, so each tool stays a few lines.
final class QuickToolHotkey {
    private static var instances: [UInt32: QuickToolHotkey] = [:]
    private static var sharedHandler: EventHandlerRef?

    private let hotKeyID: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var registeredShortcut: GlobalShortcut?
    var onPress: (() -> Void)?

    init(id: UInt32) {
        hotKeyID = id
    }

    /// Applies the wanted state; returns false when macOS refused the
    /// registration (combination taken by another app).
    @discardableResult
    func sync(enabled: Bool, shortcut: GlobalShortcut) -> Bool {
        guard enabled else {
            unregister()
            return true
        }
        if hotKeyRef != nil, registeredShortcut == shortcut {
            return true
        }
        unregister()
        Self.installSharedHandlerIfNeeded()
        Self.instances[hotKeyID] = self
        let id = EventHotKeyID(signature: 0x5655_5154, id: hotKeyID) // 'VUQT'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.carbonKeyCode,
                                         shortcut.carbonModifiers,
                                         id, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            registeredShortcut = nil
            return false
        }
        hotKeyRef = ref
        registeredShortcut = shortcut
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        registeredShortcut = nil
        Self.instances.removeValue(forKey: hotKeyID)
    }

    /// Releases every quick tool key at once, for the moment a shortcut field
    /// is listening and the combination being typed must reach it instead of
    /// firing a tool. Each owner registers again on its next `sync`.
    static func unregisterAll() {
        for instance in instances.values { instance.unregister() }
    }

    private static func installSharedHandlerIfNeeded() {
        guard sharedHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            if let event {
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
            }
            guard id.signature == 0x5655_5154,
                  let instance = QuickToolHotkey.instances[id.id]
            else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { instance.onPress?() }
            return noErr
        }, 1, &spec, nil, &sharedHandler)
    }
}
