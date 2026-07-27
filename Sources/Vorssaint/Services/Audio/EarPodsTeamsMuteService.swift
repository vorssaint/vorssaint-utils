// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

/// Intercepts the media Play/Pause button at the HID level to block the macOS rcd daemon
/// from launching Apple Music, and instead forwards a mute/unmute shortcut (Cmd+Shift+M)
/// to Microsoft Teams.
final class EarPodsTeamsMuteService: ObservableObject {
    static let shared = EarPodsTeamsMuteService()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Magic Number for Media Keys
    private let NX_KEYTYPE_PLAY: UInt32 = 16
    
    private init() {}
    
    func syncWithPreferences() {
        if AppFeature.musicBlock.isAvailable, UserDefaults.standard.bool(forKey: DefaultsKey.musicBlockTeamsMute) {
            start()
        } else {
            stop()
        }
    }
    
    private func start() {
        guard eventTap == nil else { return }
        
        let systemDefinedEventTypeRawValue: UInt32 = 14
        let eventMask = (1 << systemDefinedEventTypeRawValue)
        
        // Use cghidEventTap to catch the event before the remote control daemon (rcd) does
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                let mySelf = Unmanaged<EarPodsTeamsMuteService>.fromOpaque(refcon!).takeUnretainedValue()
                return mySelf.handleEvent(event: event, type: type)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("EarPodsTeamsMuteService: Failed to create event tap. Check accessibility permissions.")
            return
        }
        
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        self.eventTap = tap
        self.runLoopSource = source
    }
    
    private func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            self.eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.runLoopSource = nil
        }
    }
    
    private func handleEvent(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        let systemDefinedEventTypeRawValue: UInt32 = 14
        guard type.rawValue == systemDefinedEventTypeRawValue else { return Unmanaged.passRetained(event) }
        
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype == .screenChanged else {
            return Unmanaged.passRetained(event)
        }
        
        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyFlags = (data1 & 0x0000FFFF)
        let keyState = (keyFlags & 0xFF00) >> 8
        
        if UInt32(keyCode) == NX_KEYTYPE_PLAY {
            if keyState == 1 { // Key down
                postTeamsMuteShortcut()
            }
            // Consume the event completely so Apple Music does not launch
            return nil
        }
        
        return Unmanaged.passRetained(event)
    }
    
    private func postTeamsMuteShortcut() {
        let cmdKey: CGEventFlags = .maskCommand
        let shiftKey: CGEventFlags = .maskShift
        let flags: CGEventFlags = [cmdKey, shiftKey]
        
        let keyCode: CGKeyCode = 46 // 'M'
        
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }
        
        keyDown.flags = flags
        keyUp.flags = flags
        
        let teamsBundleIDs = ["com.microsoft.teams", "com.microsoft.teams2"]
        var teamsApp: NSRunningApplication?
        
        for bundleID in teamsBundleIDs {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                teamsApp = app
                break
            }
        }
        
        guard let targetApp = teamsApp else { return }
        
        keyDown.postToPid(targetApp.processIdentifier)
        keyUp.postToPid(targetApp.processIdentifier)
    }
}
