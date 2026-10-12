// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class TrackpadWindowSwitcher {
    static let shared = TrackpadWindowSwitcher()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var detector = TrackpadSwipeDetector()
    private var opened = false
    private init() {}
    func start() {
        guard tap == nil else { return }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: NSEvent.EventTypeMask.gesture.rawValue, callback: { _, type, cgEvent, context in
                guard let context else { return Unmanaged.passUnretained(cgEvent) }
                let service = Unmanaged<TrackpadWindowSwitcher>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if SessionActivity.shared.isActive, let tap = service.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                } else if SessionActivity.shared.isActive, let event = NSEvent(cgEvent: cgEvent) { service.handle(event) }
                return Unmanaged.passUnretained(cgEvent)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap; let source = CFMachPortCreateRunLoopSource(nil, tap, 0); self.source = source
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    private func handle(_ event: NSEvent) {
        let touches = event.allTouches().filter { $0.type == .indirect && NSTouch.Phase.touching.contains($0.phase) && !$0.isResting }
        let sample = touches.map { SwipeTouch(id: $0.identity.hash, position: $0.normalizedPosition) }
        guard let action = detector.handle(sample, fingers: min(max(DockOption.trackpadFingers.int, 3), 4), horizontal: DockOption.trackpadDirection.string != "vertical") else { return }
        switch action {
        case .open: opened = AppSwitcher.shared.openExternalSession()
        case .cycleForward: if opened { AppSwitcher.shared.cycleExternalSession(by: 1) }
        case .cycleBackward: if opened { AppSwitcher.shared.cycleExternalSession(by: -1) }
        case .release: if opened { AppSwitcher.shared.commitExternalSession() }; opened = false
        }
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; detector = .init()
        if opened { AppSwitcher.shared.cancelExternalSession() }; opened = false
    }
}
