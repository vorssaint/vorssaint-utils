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
    private var generation: UInt64 = 0
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

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
        guard Self.installSharedHandlerIfNeeded() else { return false }
        Self.instances[hotKeyID] = self
        let id = EventHotKeyID(signature: 0x5655_5154, id: hotKeyID) // 'VUQT'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.carbonKeyCode,
                                         shortcut.carbonModifiers,
                                         id, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            registeredShortcut = nil
            Self.instances.removeValue(forKey: hotKeyID)
            return false
        }
        hotKeyRef = ref
        registeredShortcut = shortcut
        return true
    }

    func unregister() {
        generation &+= 1
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

    private static func installSharedHandlerIfNeeded() -> Bool {
        guard sharedHandler == nil else { return true }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            if let event {
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
            }
            guard id.signature == 0x5655_5154,
                  let instance = QuickToolHotkey.instances[id.id]
            else { return OSStatus(eventNotHandledErr) }
            let kind = event.map(GetEventKind)
            let generation = instance.generation
            DispatchQueue.main.async {
                guard QuickToolHotkey.instances[id.id] === instance,
                      instance.generation == generation,
                      instance.hotKeyRef != nil else { return }
                if kind == UInt32(kEventHotKeyReleased) {
                    instance.onRelease?()
                } else {
                    instance.onPress?()
                }
            }
            return noErr
        }, specs.count, &specs, nil, &sharedHandler)
        guard status == noErr, sharedHandler != nil else {
            sharedHandler = nil
            return false
        }
        return true
    }
}
