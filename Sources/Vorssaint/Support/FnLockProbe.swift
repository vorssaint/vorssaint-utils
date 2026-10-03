// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT

import AppKit
import CoreGraphics
import Foundation

/// The development-only keycode probe for the per-app F-row translation
/// (issue #1227), run with:
///
///     open -a "Vorssaint (Developer)" --args --fn-probe
///
/// Apple keeps the function row's media forms to itself: the header stops at
/// the classic NX ids and the F-row's newer keys (Spotlight, Dictation,
/// Focus) are Apple-vendor usages whose CGEvent shapes are not documented.
/// This probe prints every keystroke the session sees, so the translation
/// table in `FnLockSupport` can be filled in from the hardware it runs on:
/// press F1-F12 bare and then with Fn held, read the lines, and paste the
/// pairs into the tables.
///
/// It must be launched through LaunchServices, not run from a shell: a
/// shell-launched binary is not the app TCC knows, so its active tap is
/// refused (and a listen-only one is created but never fed). The lines go
/// to stdout and to /tmp/vorssaint-fn-probe.log, because a GUI process has
/// no usable stdout. Quit other Vorssaint instances first, or their
/// listeners may translate a press before this probe sees its original
/// form.
enum FnLockProbe {
    /// Probe sessions end on their own, so a stray terminal never leaves one
    /// running in the background.
    private static let sessionSeconds: TimeInterval = 300

    /// Launched through LaunchServices (`open -a`), a GUI process has no
    /// usable stdout, so the lines also land here. A fixed path, because the
    /// point of the probe is to be readable by someone else afterwards.
    private static let logPath = "/tmp/vorssaint-fn-probe.log"

    private static func print(_ line: String) {
        Swift.print(line)
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write((line + "\n").data(using: .utf8)!)
            try? handle.close()
        }
    }

    static func runAndExit() -> Never {
        setbuf(stdout, nil)
        try? FileManager.default.removeItem(atPath: logPath)
        FileManager.default.createFile(atPath: logPath, contents: nil)
        let systemDefined = CGEventType(rawValue: 14)!
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << systemDefined.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            Self.describe(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        // An active tap, not a listen-only one: the Fn-Lock and brightness
        // taps this app already runs are active and their Accessibility
        // grant covers them, while a listen-only keyboard tap falls under
        // Input Monitoring instead, which this probe has no way to ask for.
        // The callback returns every event untouched, so head-inserting
        // changes nothing downstream.
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: nil) else {
            print("fn-probe: the session refused an active tap; this binary"
                  + " needs the Accessibility grant the installed app has")
            exit(1)
        }
        print("fn-probe: press F1-F12 bare, then hold Fn and press them again.")
        print("fn-probe: ends in \(Int(sessionSeconds)) seconds; Ctrl-C also works.")
        print("fn-probe: keycode=<virtual key> nxKey=<system-defined id> "
              + "state=a(down)/b(up) fn=0/1 repeat=0/1 flags=<cg flags>")
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        // Self test: post one synthetic NX event with an id no hardware
        // uses. The system ignores it, so nothing happens on screen; if the
        // probe logs it, the tap is alive and any silence about physical
        // keys is the permission layer, not a dead run loop.
        if let probe = FnLockKeyEvents.mediaEvent(nxKey: 0x99, isKeyDown: true) {
            probe.post(tap: .cgSessionEventTap)
            print("fn-probe: self test posted an NX 0x99 event; "
                  + "if it does not appear above the physical keys, the tap is dead")
        }
        let deadline = DispatchWorkItem {
            print("fn-probe: session over")
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            exit(0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + sessionSeconds, execute: deadline)
        CFRunLoopRun()
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        exit(0)
    }

    private static func describe(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // The one diagnosis that explains a silent probe: the window
            // server disables an unauthorized tap instead of answering it.
            print("fn-probe: TAP DISABLED by \(type == .tapDisabledByTimeout ? "timeout" : "user input")"
                  + " — run this binary from the installed app bundle that has"
                  + " the Accessibility grant, and grant it if asked")
            return
        }
        let flags = event.flags
        let fn = flags.contains(.maskSecondaryFn) ? 1 : 0
        let repeatBit = event.getIntegerValueField(.keyboardEventAutorepeat) != 0 ? 1 : 0
        switch type {
        case .keyDown, .keyUp, .flagsChanged:
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let name = type == .keyDown ? "down " : (type == .keyUp ? "up   " : "flags")
            print("fn-probe: \(name) keycode=\(keyCode) fn=\(fn) repeat=\(repeatBit) "
                  + "flags=\(String(describing: flags))")
        default:
            // System-defined: subtype 8 carries the media id in data1 as
            // (id << 16) | (state << 8) | repeat, exactly the form the volume
            // roller and the brightness media tap already read.
            guard let nsEvent = NSEvent(cgEvent: event),
                  nsEvent.subtype.rawValue == 8 else { return }
            let raw = Int32(truncatingIfNeeded: nsEvent.data1)
            let nxKey = (raw >> 16) & 0xFFFF
            let state = (raw >> 8) & 0xFF
            let repeats = raw & 0x1
            print("fn-probe: sysdef nxKey=\(nxKey) state=\(String(state, radix: 16)) "
                  + "fn=\(fn) repeat=\(repeats) data1=\(String(raw, radix: 16)) "
                  + "flags=\(String(describing: nsEvent.modifierFlags))")
        }
    }
}

#endif
