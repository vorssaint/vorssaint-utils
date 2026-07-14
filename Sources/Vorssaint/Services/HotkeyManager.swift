// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Combine
import Foundation

/// Global Keep Awake shortcut via Carbon (no Accessibility permission required).
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    @Published private(set) var registrationFailed = false
    var onActivate: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var registeredShortcut: GlobalShortcut?

    private init() {}

    func syncWithPreferences() {
        setEnabled(AppFeature.keepAwake.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.hotkeyEnabled))
    }

    func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    private func register() {
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.keepAwakeShortcut,
                                            fallback: .keepAwakeDefault)
        if hotKeyRef != nil, registeredShortcut == shortcut { return }
        unregister()
        if eventHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            // The dispatcher delivers every registered hotkey to every handler,
            // so filter by id — other features (e.g. the shelf) register their own.
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                if let event {
                    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                }
                // Not our hotkey: hand it back so the dispatcher keeps walking the
                // handler chain (the shelf installs its own handler on the same
                // target). Returning noErr here would swallow the shelf's key.
                // The signature must be checked too — ids alone repeat across
                // the app's registrars and would hijack another feature's key.
                guard hotKeyID.signature == 0x5655_544C, hotKeyID.id == 1
                else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onActivate?() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }
        let hotKeyID = EventHotKeyID(signature: 0x5655_544C, id: 1) // 'VUTL'
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
            registrationFailed = false
        } else {
            hotKeyRef = nil
            registeredShortcut = nil
            registrationFailed = true
        }
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        registeredShortcut = nil
        registrationFailed = false
    }
}
