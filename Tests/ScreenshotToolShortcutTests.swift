// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox

func screenshotToolShortcutChecks(_ expect: (Bool, String) -> Void) {
    typealias Tool = ScreenshotSupport.Tool
    let sources = (TISCreateInputSourceList(
        [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary, true)?
        .takeRetainedValue() as? [TISInputSource]) ?? []
    func layout(_ id: String) -> Data? {
        guard let source = sources.first(where: {
            guard let pointer = TISGetInputSourceProperty($0, kTISPropertyInputSourceID) else { return false }
            return (Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String) == id
        }), let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }
    func typed(_ code: UInt16, flags: UInt32, data: Data) -> String? {
        var dead: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 8)
        var count = 0
        let status = data.withUnsafeBytes { bytes -> OSStatus in
            guard let keyboard = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(keyboard, code, UInt16(kUCKeyActionDown), (flags >> 8) & 0xff,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &dead, characters.count, &count, &characters)
        }
        guard status == noErr, count > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: count)
    }
    defer { GlobalShortcut.refreshLayoutLabels() }

    // Real keyboard data is the oracle, before the shortcut model discards
    // lock state. Every modifier combination and physical key is considered.
    let layouts = ["US", "French", "French-numerical", "German", "Russian"]
    for name in layouts {
        guard let data = layout("com.apple.keylayout." + name) else {
            expect(false, "keyboard fixture unavailable: " + name)
            continue
        }
        GlobalShortcut.refreshLayoutLabels(layoutData: data)
        for locked in [false, true] {
            for modifierBits in 0..<16 {
                let modifiers = GlobalShortcutModifiers(rawValue: modifierBits)
                for code in UInt16(0)...127 {
                    let flags = modifiers.carbonFlags | (locked ? UInt32(alphaLock) : 0)
                    let character = typed(code, flags: flags, data: data)
                    let expected = !modifiers.hasPrimaryModifier
                        ? character.flatMap { ["1", "2", "3", "4", "5", "6", "7", "8", "9"].firstIndex(of: $0) }.map { $0 + 1 }
                        : nil
                    let shortcut = GlobalShortcut(keyCode: Int64(code), modifiers: modifiers)
                    expect(Tool.shortcutDigit(shortcut, capsLockOn: locked) == expected,
                           "recording follows typed digits on \(name), key \(code), modifiers \(modifierBits), lock \(locked)")
                }
            }
        }
    }

    if let french = layout("com.apple.keylayout.French"), let us = layout("com.apple.keylayout.US"),
       let numerical = layout("com.apple.keylayout.French-numerical") {
        let ampersand = GlobalShortcut(keyCode: Int64(kVK_ANSI_1), modifiers: [])
        let other = GlobalShortcut(keyCode: Int64(kVK_F19), modifiers: [.control, .option, .command])
        GlobalShortcut.refreshLayoutLabels(layoutData: french)
        let original = Tool.assigningBinding(ampersand, to: .text, orderRaw: nil, bindingsRaw: "")
        expect(Tool.activeBindings(from: original.bindingsRaw)[.text] == ampersand,
               "French symbol binding starts active")
        GlobalShortcut.refreshLayoutLabels(layoutData: us)
        expect(Tool.bindings(from: original.bindingsRaw)[.text] == ampersand
               && Tool.activeBindings(from: original.bindingsRaw)[.text] == nil,
               "keyboard changes suspend digit-shaped bindings without deleting them")
        expect(Tool.shortcutLabel(for: .text, orderRaw: nil, bindingsRaw: original.bindingsRaw, enabled: true) == "5"
               && Tool.shortcutTool(keyCode: ampersand.keyCode, modifiers: [], number: 1,
                                    orderRaw: nil, bindingsRaw: original.bindingsRaw, enabled: true) == .select,
               "suspended binding leaves position badges and printed-digit routing consistent")
        let edited = Tool.assigningBinding(other, to: .arrow, orderRaw: original.orderRaw,
                                          bindingsRaw: original.bindingsRaw)
        let clearedOther = Tool.assigningBinding(nil, to: .arrow, orderRaw: edited.orderRaw,
                                                bindingsRaw: edited.bindingsRaw)
        GlobalShortcut.refreshLayoutLabels(layoutData: french)
        expect(Tool.activeBindings(from: edited.bindingsRaw)[.text] == ampersand
               && Tool.activeBindings(from: clearedOther.bindingsRaw)[.text] == ampersand,
               "editing and clearing another tool preserve bindings across a keyboard round trip")

        GlobalShortcut.refreshLayoutLabels(layoutData: numerical)
        expect(Tool.shortcutDigit(ampersand, capsLockOn: true) == 1
               && Tool.shortcutDigit(ampersand, capsLockOn: false) == nil,
               "French numerical Caps Lock changes recording from a symbol to a digit")
        let lockedAssignment = Tool.assigningBinding(ampersand,
            digit: Tool.shortcutDigit(ampersand, capsLockOn: true), to: .text,
            orderRaw: original.orderRaw, bindingsRaw: original.bindingsRaw)
        expect(Tool.ordered(from: lockedAssignment.orderRaw).first == .text
               && Tool.bindings(from: lockedAssignment.bindingsRaw)[.text] == nil,
               "recording a locked digit moves the tool and clears only its explicit binding")
        expect(Tool.shortcutTool(keyCode: ampersand.keyCode, modifiers: [], number: 1,
                                orderRaw: lockedAssignment.orderRaw, bindingsRaw: lockedAssignment.bindingsRaw,
                                enabled: true, capsLockOn: true) == .text,
               "the editor selects the new first tool using the locked digit")
        expect(Tool.activeBindings(from: original.bindingsRaw, capsLockOn: true)[.text] == nil
               && Tool.shortcutLabel(for: .text, orderRaw: nil, bindingsRaw: original.bindingsRaw,
                                     enabled: true, capsLockOn: true) == "5"
               && Tool.activeBindings(from: original.bindingsRaw, capsLockOn: false)[.text] == ampersand,
               "Caps Lock temporarily changes availability and labels, never storage")
        expect(Tool.shortcutTool(keyCode: ampersand.keyCode, modifiers: [], number: 1,
                                orderRaw: nil, bindingsRaw: original.bindingsRaw, enabled: false,
                                capsLockOn: true) == nil,
               "disabled shortcuts remain silent with Caps Lock and a suspended binding")

        GlobalShortcut.refreshLayoutLabels(layoutData: us)
        let text = GlobalShortcut(keyCode: Int64(kVK_ANSI_T), modifiers: [])
        let textBinding = Tool.bindingsStorage([.text: text])
        expect(Tool.shortcutTool(keyCode: text.keyCode, modifiers: [], number: 1,
                                orderRaw: nil, bindingsRaw: textBinding, enabled: true) == .select,
               "an input method's actual printed digit wins over an underlying physical letter")
        expect(Tool.shortcutTool(keyCode: Int64(kVK_ANSI_5), modifiers: [], number: 5,
                                orderRaw: nil, bindingsRaw: textBinding, enabled: true) == nil,
               "an active custom binding keeps its tool's old position shortcut off")
    }

    // Exercise the same raw-flag constructor used by the WindowServer reader.
    for modifiers in [GlobalShortcutModifiers(), [.control, .option]] {
        let letter = GlobalShortcut(keyCode: Int64(kVK_ANSI_N), modifiers: modifiers)
        let fnOwner = LiveSystemShortcut(id: 212, keyCode: letter.keyCode,
                                         flags: modifiers.cgFlags.union(.maskSecondaryFn), enabled: true)
        expect(fnOwner.requiresFunctionKey && !GlobalShortcut.matchesLiveSystemShortcut(letter, entries: [fnOwner]),
               "an Fn-letter system owner does not reserve the same letter without Fn")
        let plainOwner = LiveSystemShortcut(id: 213, keyCode: letter.keyCode, flags: modifiers.cgFlags, enabled: true)
        expect(GlobalShortcut.matchesLiveSystemShortcut(letter, entries: [plainOwner]),
               "a system owner that really uses the same modifiers remains protected")
        let plist: [String: Any] = ["212": ["enabled": true,
            "value": ["type": "standard", "parameters": [0, Int(letter.keyCode),
                Int(modifiers.cgFlags.union(.maskSecondaryFn).rawValue)]]]]
        expect(!GlobalShortcut.matchesSystemShortcut(letter, symbolicHotKeys: plist),
               "the preference fallback also retains the Fn requirement")
    }
    for code in [kVK_F2, kVK_LeftArrow] {
        let key = GlobalShortcut(keyCode: Int64(code), modifiers: [])
        let owner = LiveSystemShortcut(id: 1, keyCode: key.keyCode,
                                       flags: .maskSecondaryFn, enabled: true)
        expect(GlobalShortcut.matchesLiveSystemShortcut(key, entries: [owner]),
               "function and navigation keys retain their intrinsic Fn system protection")
    }

    let directional = GlobalShortcut(keyCode: Int64(kVK_F18), modifiers: [.control, .option, .command])
    let ordinary = GlobalShortcut.windowLayoutLeftDefault
    expect(WindowLayoutShortcutConflict.find(directional, directional: directional,
                                             actionShortcut: { _ in nil }) == .directional,
           "directional window shortcut is detected with ordinary shortcuts disabled")
    expect(WindowLayoutShortcutConflict.find(directional, directional: nil,
                                             actionShortcut: { _ in nil }) == nil,
           "disabling the directional owner releases its combination")
    expect(WindowLayoutShortcutConflict.find(ordinary, directional: directional,
                                             actionShortcut: { $0 == .leftHalf ? ordinary : nil }) == .action(.leftHalf),
           "ordinary window actions remain protected alongside the directional shortcut")
    expect(WindowLayoutShortcutConflict.find(ordinary, directional: directional, excluding: .leftHalf,
                                             actionShortcut: { $0 == .leftHalf ? ordinary : nil }) == nil,
           "a window action may retain its own shortcut without a false self-conflict")
    expect(WindowLayoutShortcutConflict.find(directional, directional: nil,
                                             actionShortcut: { $0 == .leftHalf ? directional : nil }) == .action(.leftHalf),
           "editing the directional shortcut still detects a different ordinary owner")
}
