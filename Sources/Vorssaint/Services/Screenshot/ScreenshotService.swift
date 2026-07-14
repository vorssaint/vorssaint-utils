// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Combine
import Foundation

final class ScreenshotService: ObservableObject {
    static let shared = ScreenshotService()
    
    @Published var hotkeyRegistrationFailed = false
    
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var registeredShortcut: GlobalShortcut?
    
    private init() {}
    
    func syncWithPreferences() {
        if UserDefaults.standard.bool(forKey: DefaultsKey.screenshotEnabled) {
            registerHotkey()
        } else {
            unregisterHotkey()
        }
    }
    
    private func registerHotkey() {
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.screenshotShortcut,
                                            fallback: .screenshotDefault)
        if hotKeyRef != nil, registeredShortcut == shortcut { return }
        unregisterHotkey()
        
        if hotKeyHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
                guard userData != nil else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                if let event {
                    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &id)
                }
                guard id.id == 8 else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async {
                    ScreenshotOverlayController.shared.startCapture()
                }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        }
        
        let id = EventHotKeyID(signature: 0x5655_5353, id: 8) // 'VUSS'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.carbonKeyCode,
                                         shortcut.carbonModifiers,
                                         id, GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRef = ref
            registeredShortcut = shortcut
            hotkeyRegistrationFailed = false
        } else {
            hotKeyRef = nil
            registeredShortcut = nil
            hotkeyRegistrationFailed = true
        }
    }
    
    private func unregisterHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        registeredShortcut = nil
        hotkeyRegistrationFailed = false
    }
}
