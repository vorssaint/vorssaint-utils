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
        migrateSoftwareOutputSelection()
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
        ).filter { !VirtualOutputSupport.isSoftwareDevice($0) }
    }

    func setSelectedDeviceUIDs(_ uids: [String]) {
        let sanitized = Defaults.sanitizedSoundOutputSwitcherDeviceUIDs(uids)
            .filter { !VirtualOutputSupport.isSoftwareDevice($0) }
        if sanitized.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.soundOutputSwitcherDeviceUIDs)
        } else {
            UserDefaults.standard.set(sanitized, forKey: DefaultsKey.soundOutputSwitcherDeviceUIDs)
        }
        lastSwitchFailed = false
    }

    private func migrateSoftwareOutputSelection() {
        let saved = Defaults.sanitizedSoundOutputSwitcherDeviceUIDs(
            UserDefaults.standard.array(forKey: DefaultsKey.soundOutputSwitcherDeviceUIDs) ?? [])
        guard saved.contains(where: { VirtualOutputSupport.isSoftwareDevice($0) }) else { return }
        let physical = VirtualOutputService.shared.physicalOutputUID
            ?? UserDefaults.standard.string(forKey: DefaultsKey.softwareVolumePhysicalOutputUID)
        setSelectedDeviceUIDs(VirtualOutputSupport.migratedOutputSelection(saved, physical: physical))
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
            SystemShortcutTakeover.claim(DefaultsKey.soundOutputSwitcherShortcut, shortcut: shortcut)
        } else {
            hotKeyRef = nil
            registeredShortcut = nil
            registrationFailed = true
        }
    }

    /// Lets go of the global key while a shortcut field is listening, so the
    /// user can record the very combination this feature uses. The next
    /// `syncWithPreferences` takes it back.
    func suspendShortcut() { unregisterHotkey() }

    private func unregisterHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            SystemShortcutTakeover.release(DefaultsKey.soundOutputSwitcherShortcut)
        }
        hotKeyRef = nil
        registeredShortcut = nil
        registrationFailed = false
        lastSwitchFailed = false
    }
}
