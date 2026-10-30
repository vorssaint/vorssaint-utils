// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// The input callback only arbitrates keys. Audio, permissions and UI run on
/// the main queue; no event waits for inference or an Accessibility query.
final class DictationShortcut {
    private let lock = NSLock()
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var shortcut: GlobalShortcut?
    private var useFunction = true
    private var held = false
    private var busy = false
    private var heldCode: Int64?
    var press: (() -> Void)?
    var release: (() -> Void)?
    var cancel: (() -> Void)?

    func setBusy(_ busy: Bool) { lock.lock(); self.busy = busy; lock.unlock() }

    func start(storage: String) -> Bool {
        stop()
        lock.lock()
        useFunction = storage == "fn"
        shortcut = GlobalShortcut(storageValue: storage)
        lock.unlock()
        guard storage == "fn" || shortcut != nil else { return false }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<DictationShortcut>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let port = owner.port { CGEvent.tapEnable(tap: port, enable: true) }
                DispatchQueue.main.async { owner.cancel?() }
                return Unmanaged.passUnretained(event)
            }
            return owner.handle(type, event: event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else { return false }
        self.port = port
        self.source = source
        PointerTapRunLoop.add(source)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { PointerTapRunLoop.remove(source, invalidating: port) }
        port = nil; source = nil
        lock.lock(); held = false; heldCode = nil; busy = false; lock.unlock()
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown, code == 53, busy {
            DispatchQueue.main.async { self.cancel?() }
            return true
        }
        if useFunction {
            if type == .flagsChanged, code == 63 {
                let down = event.flags.contains(.maskSecondaryFn)
                guard down != held else { return false }
                held = down
                if down {
                    // Fn plus an already held modifier belongs to macOS.
                    guard GlobalShortcutModifiers(cgFlags: event.flags).isEmpty else { return false }
                    heldCode = code
                    DispatchQueue.main.async { self.press?() }
                } else if heldCode != nil {
                    heldCode = nil
                    DispatchQueue.main.async { self.release?() }
                } else { return false }
                return true
            }
            if type == .keyDown, held, heldCode != nil {
                heldCode = nil
                DispatchQueue.main.async { self.cancel?() }
            }
            return false
        }
        if type == .keyUp, code == heldCode {
            heldCode = nil; held = false
            DispatchQueue.main.async { self.release?() }
            return true
        }
        guard type == .keyDown, let shortcut, code == shortcut.keyCode,
              GlobalShortcutModifiers(cgFlags: event.flags) == shortcut.modifiers else { return false }
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0, !held {
            held = true; heldCode = code
            DispatchQueue.main.async { self.press?() }
        }
        return true
    }
}
