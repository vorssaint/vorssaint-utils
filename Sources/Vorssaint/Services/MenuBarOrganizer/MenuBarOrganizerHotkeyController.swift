// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

@MainActor
final class MenuBarOrganizerHotkeyController {
    enum Action: UInt32, CaseIterable {
        case toggleHidden = 1
        case toggleAlwaysHidden = 2
        case search = 3
    }

    private static let signature: OSType = 0x564D_424F // 'VMBO'
    private var refs: [Action: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var actions: [Action: () -> Void] = [:]
    private(set) var registrationFailed = false

    func sync(registrations: [(Action, Bool, GlobalShortcut, @MainActor () -> Void)]) {
        unregisterAll()
        installHandlerIfNeeded()
        for (action, enabled, shortcut, callback) in registrations where enabled {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let status = RegisterEventHotKey(shortcut.carbonKeyCode,
                                             shortcut.carbonModifiers,
                                             id,
                                             GetEventDispatcherTarget(),
                                             0,
                                             &ref)
            if status == noErr, let ref {
                refs[action] = ref
                actions[action] = callback
            } else {
                registrationFailed = true
            }
        }
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        actions.removeAll()
        registrationFailed = false
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == MenuBarOrganizerHotkeyController.signature,
                  let action = Action(rawValue: id.id)
            else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<MenuBarOrganizerHotkeyController>
                .fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { controller.actions[action]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}
