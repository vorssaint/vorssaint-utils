// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Combine
import Foundation

/// Cycles the system output through the devices selected in the mixer panel.
final class SoundOutputSwitcher: ObservableObject {
    static let shared = SoundOutputSwitcher()

    @Published private(set) var registrationFailed = false
    @Published private(set) var lastSwitchFailed = false

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var registeredShortcut: GlobalShortcut?

    private init() {}

    func syncWithPreferences() {
        AppFeature.soundOutputSwitcher.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.soundOutputSwitcherEnabled)
            ? registerHotkey()
            : unregisterHotkey()
    }

    func stop() {
        unregisterHotkey()
    }

    func selectedDeviceUIDs() -> [String] {
        Defaults.sanitizedSoundOutputSwitcherDeviceUIDs(
            UserDefaults.standard.array(forKey: DefaultsKey.soundOutputSwitcherDeviceUIDs) ?? []
        )
    }

    func setSelectedDeviceUIDs(_ uids: [String]) {
        let sanitized = Defaults.sanitizedSoundOutputSwitcherDeviceUIDs(uids)
        if sanitized.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.soundOutputSwitcherDeviceUIDs)
        } else {
            UserDefaults.standard.set(sanitized, forKey: DefaultsKey.soundOutputSwitcherDeviceUIDs)
        }
        lastSwitchFailed = false
    }

    @discardableResult
    func switchToNextOutput() -> Bool {
        let ok = AppVolumeMixer.shared.switchToNextSoundOutput(in: selectedDeviceUIDs())
        lastSwitchFailed = !ok
        return ok
    }

    private func registerHotkey() {
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.soundOutputSwitcherShortcut,
                                            fallback: .soundOutputSwitcherDefault)
        if hotKeyRef != nil, registeredShortcut == shortcut { return }
        unregisterHotkey()
        if eventHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                if let event {
                    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &id)
                }
                guard id.signature == 0x5655_534F, id.id == 4
                else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<SoundOutputSwitcher>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { service.switchToNextOutput() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }
        let id = EventHotKeyID(signature: 0x5655_534F, id: 4) // 'VUSO'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.carbonKeyCode,
                                         shortcut.carbonModifiers,
                                         id,
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

    private func unregisterHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        registeredShortcut = nil
        registrationFailed = false
        lastSwitchFailed = false
    }
}
