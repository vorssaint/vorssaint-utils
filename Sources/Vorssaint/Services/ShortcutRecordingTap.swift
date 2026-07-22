// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import CoreGraphics
import Foundation

/// While a shortcut field is listening, every key press belongs to the field.
/// This active tap swallows key events ahead of the system, other apps'
/// global shortcuts and this app's own menu, and hands them to the field.
/// Without it, typing a combination something answers to performs that action
/// instead of landing in the field: recording Command Q would quit an app,
/// and combinations the system consumes could never be recorded at all.
///
/// The tap lives only while a field records, plus the tail of a key still
/// held when recording ends, so its release and autorepeats cannot reach the
/// app as a fresh press of the recorded combination. Only one field ever
/// records at a time (the ShortcutCapture invariant), so one static tap is
/// enough. Main thread only. Without Accessibility, begin fails and the
/// field falls back to plain view events, which is how it always worked.
enum ShortcutRecordingTap {
    private static var tap: CFMachPort?
    private static var runLoopSource: CFRunLoopSource?
    private static var handler: ((Int64, GlobalShortcutModifiers) -> Void)?
    /// The key most recently pressed while recording and possibly still down.
    private static var heldKeyCode: Int64?
    /// Set when recording ends with a key still down: its autorepeats and
    /// release keep being swallowed until the release arrives.
    private static var drainingKeyCode: Int64?
    private static var drainWatchdog: DispatchWorkItem?

    /// Starts swallowing key events and delivering each fresh press to the
    /// handler. Returns false when the tap cannot exist (no Accessibility),
    /// in which case the caller keeps its ordinary event path.
    @discardableResult
    static func begin(_ newHandler: @escaping (Int64, GlobalShortcutModifiers) -> Void) -> Bool {
        drainWatchdog?.cancel()
        drainWatchdog = nil
        drainingKeyCode = nil
        heldKeyCode = nil
        // A tap the system disabled behind our back reads as dead; rebuild.
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            tearDown()
        }
        if tap == nil {
            guard AXIsProcessTrusted() else { return false }
            let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
                | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            guard let created = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, _ in
                    ShortcutRecordingTap.handle(type: type, event: event)
                },
                userInfo: nil
            ) else { return false }
            tap = created
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: created, enable: true)
        }
        handler = newHandler
        return true
    }

    /// Safe to call twice and when begin failed. When the recorded key is
    /// still down, the tap lingers just long enough to swallow its release.
    static func end() {
        handler = nil
        guard tap != nil else { return }
        if let heldKeyCode {
            drainingKeyCode = heldKeyCode
            let watchdog = DispatchWorkItem { tearDown() }
            drainWatchdog = watchdog
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: watchdog)
        } else {
            tearDown()
        }
    }

    private static func tearDown() {
        drainWatchdog?.cancel()
        drainWatchdog = nil
        drainingKeyCode = nil
        heldKeyCode = nil
        handler = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private static func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if let handler {
            if type == .keyDown {
                heldKeyCode = keyCode
                // Autorepeats of a held key are swallowed but never re-fed:
                // the field wants the press, not a stream of it.
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    handler(keyCode, GlobalShortcutModifiers(cgFlags: event.flags))
                }
            } else if keyCode == heldKeyCode {
                heldKeyCode = nil
            }
            return nil
        }
        if let drainingKeyCode, keyCode == drainingKeyCode {
            if type == .keyUp { tearDown() }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
