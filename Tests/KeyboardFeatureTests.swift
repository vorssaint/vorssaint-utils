// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat

enum KeyboardFeatureTests {
    static func run(_ suite: TestSuite) {
        func expectEqual(_ actual: String, _ expected: String, _ label: String,
                         file: StaticString = #filePath, line: UInt = #line) {
            suite.expect(actual == expected, "\(label): got \(actual), expected \(expected)",
                         file: file, line: line)
        }
        GlobalShortcut.startObservingKeyboardLayout()
        GlobalShortcut.refreshLayoutLabels()
        let backgroundISOKeyIsValid = DispatchQueue.global().sync {
            GlobalShortcut(keyCode: Int64(kVK_ISO_Section),
                           modifiers: [.control, .option, .command]).isValid
        }
        suite.expect(backgroundISOKeyIsValid,
               "layout-dependent shortcut labels are safe to read off the main thread")
        let shortcutM = GlobalShortcut(keyCode: Int64(kVK_ANSI_M), modifiers: [.control, .option, .command])
        let shortcutSemi = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: [.control, .option, .command])
        suite.expect(shortcutM.isValid && !shortcutM.displayString.isEmpty,
               "letter shortcuts resolve valid caps on the active keyboard layout")
        suite.expect(shortcutSemi.isValid && !shortcutSemi.displayString.isEmpty,
               "punctuation and layout-specific keys resolve valid caps on the active keyboard layout")

        // Multi-layout dynamic keycap resolution tests
        let layoutTestModifiers: GlobalShortcutModifiers = [.control, .option, .command]
        let layoutDict = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary
        let allLayoutSources = (TISCreateInputSourceList(layoutDict, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
        func testLayoutData(for idString: String) -> Data? {
            guard let src = allLayoutSources.first(where: {
                guard let id = TISGetInputSourceProperty($0, kTISPropertyInputSourceID) else { return false }
                let str = Unmanaged<CFString>.fromOpaque(id).takeUnretainedValue() as String
                return str == idString
            }), let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else {
                return nil
            }
            return Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        }

        if let frenchData = testLayoutData(for: "com.apple.keylayout.French") {
            GlobalShortcut.refreshLayoutLabels(layoutData: frenchData)
            let frenchM = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: layoutTestModifiers)
            let frenchComma = GlobalShortcut(keyCode: Int64(kVK_ANSI_M), modifiers: layoutTestModifiers)
            let frenchA = GlobalShortcut(keyCode: Int64(kVK_ANSI_Q), modifiers: layoutTestModifiers)
            let frenchQ = GlobalShortcut(keyCode: Int64(kVK_ANSI_A), modifiers: layoutTestModifiers)
            let frenchZ = GlobalShortcut(keyCode: Int64(kVK_ANSI_W), modifiers: layoutTestModifiers)
            let frenchW = GlobalShortcut(keyCode: Int64(kVK_ANSI_Z), modifiers: layoutTestModifiers)
            expectEqual(frenchM.displayString, "⌃⌥⌘M", "French AZERTY resolves physical semicolon key as M")
            expectEqual(frenchComma.displayString, "⌃⌥⌘ ,", "French AZERTY resolves physical M key as comma")
            expectEqual(frenchA.displayString, "⌃⌥⌘A", "French AZERTY resolves physical Q key as A")
            expectEqual(frenchQ.displayString, "⌃⌥⌘Q", "French AZERTY resolves physical A key as Q")
            expectEqual(frenchZ.displayString, "⌃⌥⌘Z", "French AZERTY resolves physical W key as Z")
            expectEqual(frenchW.displayString, "⌃⌥⌘W", "French AZERTY resolves physical Z key as W")
        }

        if let germanData = testLayoutData(for: "com.apple.keylayout.German") {
            GlobalShortcut.refreshLayoutLabels(layoutData: germanData)
            let germanZ = GlobalShortcut(keyCode: Int64(kVK_ANSI_Y), modifiers: layoutTestModifiers)
            let germanY = GlobalShortcut(keyCode: Int64(kVK_ANSI_Z), modifiers: layoutTestModifiers)
            let germanOuml = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: layoutTestModifiers)
            expectEqual(germanZ.displayString, "⌃⌥⌘Z", "German QWERTZ resolves physical Y key as Z")
            expectEqual(germanY.displayString, "⌃⌥⌘Y", "German QWERTZ resolves physical Z key as Y")
            expectEqual(germanOuml.displayString, "⌃⌥⌘Ö", "German QWERTZ resolves physical semicolon key as Ö")
        }

        if let abntData = testLayoutData(for: "com.apple.keylayout.Brazilian-ABNT2") {
            GlobalShortcut.refreshLayoutLabels(layoutData: abntData)
            let abntC = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: layoutTestModifiers)
            expectEqual(abntC.displayString, "⌃⌥⌘Ç", "Brazilian ABNT2 resolves physical semicolon key as Ç")
        }

        if let usData = testLayoutData(for: "com.apple.keylayout.US") {
            GlobalShortcut.refreshLayoutLabels(layoutData: usData)
            let usM = GlobalShortcut(keyCode: Int64(kVK_ANSI_M), modifiers: layoutTestModifiers)
            let usSemi = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: layoutTestModifiers)
            expectEqual(usM.displayString, "⌃⌥⌘M", "US layout resolves physical M key as M")
            expectEqual(usSemi.displayString, "⌃⌥⌘ ;", "US layout resolves physical semicolon key as semicolon")
        }

        // A keycap names a combination, not a key, and macOS resolves a Command
        // combination through the layout's Command table. Layouts that type a
        // non-Latin script answer differently there than they do bare, and
        // DVORAK-QWERTYCMD exists for nothing but that difference, so both
        // tables have to come out of the same layout.
        if let russianData = testLayoutData(for: "com.apple.keylayout.Russian") {
            GlobalShortcut.refreshLayoutLabels(layoutData: russianData)
            let russianCommandQ = GlobalShortcut(keyCode: Int64(kVK_ANSI_Q), modifiers: layoutTestModifiers)
            let russianBareQ = GlobalShortcut(keyCode: Int64(kVK_ANSI_Q), modifiers: [.control, .option])
            expectEqual(russianCommandQ.displayString, "⌃⌥⌘Q",
                        "Russian reads a Command shortcut off the layout's Command table")
            expectEqual(russianBareQ.displayString, "⌃⌥Й",
                        "Russian reads a shortcut without Command off the character the key types")
        }

        if let dvorakCommandData = testLayoutData(for: "com.apple.keylayout.DVORAK-QWERTYCMD") {
            GlobalShortcut.refreshLayoutLabels(layoutData: dvorakCommandData)
            let dvorakCommandSemi = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon),
                                                   modifiers: layoutTestModifiers)
            let dvorakBareSemi = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon),
                                                modifiers: [.control, .option])
            expectEqual(dvorakCommandSemi.displayString, "⌃⌥⌘ ;",
                        "Dvorak with QWERTY Command keeps Command shortcuts on the QWERTY cap")
            expectEqual(dvorakBareSemi.displayString, "⌃⌥S",
                        "Dvorak with QWERTY Command keeps the rest on the Dvorak cap")
        }

        // The ANSI table answers when no layout can be read at all. On a live
        // system that is a caller off the main thread meeting a cold cache:
        // Text Input Services cannot be asked from there, so nothing derives a
        // cap and nothing warms the entry either.
        GlobalShortcut.refreshLayoutLabels(layoutData: nil)
        var coldCacheCaps: [String] = []
        let coldCacheDone = DispatchSemaphore(value: 0)
        // A thread of its own, not `sync`: dispatch runs a synchronous block on
        // whichever thread called it, so `sync` would still be the main thread
        // and would reach Text Input Services after all.
        Thread {
            coldCacheCaps = [
                GlobalShortcut(keyCode: Int64(kVK_ANSI_M), modifiers: layoutTestModifiers).displayString,
                GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: layoutTestModifiers).displayString,
            ]
            coldCacheDone.signal()
        }.start()
        suite.expect(coldCacheDone.wait(timeout: .now() + 5) == .success,
                     "cold keyboard-label lookup finishes inside its bounded deadline")
        expectEqual(coldCacheCaps.first ?? "", "⌃⌥⌘M",
                    "a cold cache off the main thread falls back to ANSI M")
        expectEqual(coldCacheCaps.last ?? "", "⌃⌥⌘ ;",
                    "a cold cache off the main thread falls back to ANSI semicolon")

        GlobalShortcut.refreshLayoutLabels()

        // Every assertion above compares labels the live input source produced,
        // so on a Latin-layout Mac they all pass whichever source the keycaps
        // are read from, and the one thing that made them wrong is invisible:
        // an input method answers the current-layout call with the layout it
        // types through, not the one printed on the keys. Pinned on the public
        // symbols rather than on the private member holding them, so renaming
        // it stays green and dropping the ASCII-capable lookup goes red.
        let shortcutSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Core/GlobalShortcut.swift",
            encoding: .utf8)) ?? ""
        let shortcutCode = shortcutSource.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(shortcutCode.contains("TISCopyCurrentASCIICapableKeyboardLayoutInputSource")
                && shortcutCode.contains("TISCopyCurrentKeyboardInputSource")
                && shortcutCode.contains("kTISPropertyInputSourceType"),
               "keycaps come from the ASCII-capable layout while an input method is active")

        // MARK: Editing, navigation and upper function keys as shortcuts (#308)

        let recorderModifiers: GlobalShortcutModifiers = [.control, .option, .command]
        let editingAndNavigationKeys: [(Int, String)] = [
            (kVK_Delete, "delete"), (kVK_ForwardDelete, "forward delete"),
            (kVK_Home, "home"), (kVK_End, "end"),
            (kVK_PageUp, "page up"), (kVK_PageDown, "page down"),
            (kVK_ANSI_KeypadEnter, "keypad enter"),
        ]
        for (keyCode, name) in editingAndNavigationKeys {
            let shortcut = GlobalShortcut(keyCode: Int64(keyCode), modifiers: recorderModifiers)
            suite.expect(shortcut.isValid, "\(name) is recordable as a shortcut")
            suite.expect(!shortcut.displayString.isEmpty
                   && shortcut.displayString != "Key \(keyCode)",
                   "\(name) prints a real cap instead of a raw key code")
        }
        let upperFunctionKeys: [(Int, String)] = [
            (kVK_F13, "F13"), (kVK_F14, "F14"), (kVK_F15, "F15"), (kVK_F16, "F16"),
            (kVK_F17, "F17"), (kVK_F18, "F18"), (kVK_F19, "F19"), (kVK_F20, "F20"),
        ]
        for (keyCode, name) in upperFunctionKeys {
            let shortcut = GlobalShortcut(keyCode: Int64(keyCode), modifiers: recorderModifiers)
            suite.expect(shortcut.isValid, "\(name) is recordable as a shortcut")
            suite.expect(shortcut.displayString.hasSuffix(name), "\(name) prints its own cap")
        }
        suite.expect(Set(editingAndNavigationKeys.map {
                   GlobalShortcut(keyCode: Int64($0.0), modifiers: recorderModifiers).displayString
               }).count == editingAndNavigationKeys.count,
               "each editing and navigation key prints a cap of its own")

        // Delete on its own clears the field; held with a real modifier it is
        // an ordinary key and records like any other.
        suite.expect(GlobalShortcut.clearsShortcut(keyCode: Int64(kVK_Delete), modifiers: []),
               "delete alone clears the shortcut")
        suite.expect(GlobalShortcut.clearsShortcut(keyCode: Int64(kVK_ForwardDelete), modifiers: [.shift]),
               "forward delete with only Shift still clears the shortcut")
        suite.expect(!GlobalShortcut.clearsShortcut(keyCode: Int64(kVK_Delete), modifiers: recorderModifiers),
               "delete with a real modifier records instead of clearing")
        suite.expect(!GlobalShortcut.clearsShortcut(keyCode: Int64(kVK_ANSI_D), modifiers: []),
               "an ordinary key never clears the shortcut")
        suite.expect(GlobalShortcut.finderRenameDefault.isValid
                && GlobalShortcut.finderRenameDefault.displayString == "F2"
                && GlobalShortcut(storageValue: GlobalShortcut.finderRenameDefault.storageValue)
                    == .finderRenameDefault,
               "a standalone function key records, displays and survives storage")
        suite.expect(!GlobalShortcut(keyCode: Int64(kVK_ANSI_F), modifiers: []).isValid,
               "a bare letter still cannot become a shortcut")
        suite.expect(GlobalShortcut.finderRenameDefault.matches(keyCode: Int64(kVK_F2), modifiers: [])
                && !GlobalShortcut.finderRenameDefault.matches(
                    keyCode: Int64(kVK_F2), modifiers: [.command]),
               "Finder rename matches the chosen key and no extra modifiers")

        // MARK: Shortcuts the app silences while a field is listening (#308)

        let silenced = GlobalShortcutRole.featuresToSilenceWhileRecording
        suite.expect(Set(silenced).count == silenced.count,
               "the list of features to silence has no repeats")
        suite.expect(GlobalShortcutRole.allCases.allSatisfy { silenced.contains($0.feature) },
               "every configurable shortcut's feature is silenced while recording")
        suite.expect(silenced.contains(.windowLayout),
               "the window layout keys are silenced too, though they have no role")
        suite.expect(silenced.contains(.finderRename),
               "the scoped Finder key steps aside while its recorder is listening")
        suite.expect(silenced.contains(.switcher) && silenced.contains(.radialMenu)
               && silenced.contains(.keepAwake) && silenced.contains(.clipboardHistory),
               "the features that hold a global key are all in the silenced list")
        suite.expect(silenced.allSatisfy { AppFeature.allCases.contains($0) },
               "the silenced list only names real features, so re-syncing them restores the keys")
        GlobalShortcut.refreshLayoutLabels()

        // MARK: Keystroke overlay (KeyCastr-style visualizer)

        suite.expect(!AppFeature.keystrokeOverlay.installedByDefault,
               "keystroke overlay ships opt-in on the Features page")
        suite.expect(AppFeature.keystrokeOverlay.permissions == [.accessibility]
                && AppFeature.keystrokeOverlay.enabledKeys == [DefaultsKey.keystrokeOverlayEnabled]
                && AppFeature.keystrokeOverlay.group == .mouseKeyboard
                && AppFeature.keystrokeOverlay.energyProfile == .keyboard,
               "keystroke overlay declares its Accessibility requirement, enable key and keyboard energy profile")

        // Secure Input and auto-repeat suppression
        suite.expect(KeystrokeOverlaySupport.keyCaps(
            keyCode: Int64(kVK_ANSI_A),
            modifiers: [],
            mode: .allKeys,
            isAutoRepeat: false,
            secureInputActive: true,
            typedCharacter: "a") == nil,
               "keystroke overlay suppresses all keys while macOS Secure Input is active")
        suite.expect(KeystrokeOverlaySupport.keyCaps(
            keyCode: Int64(kVK_ANSI_A),
            modifiers: [],
            mode: .allKeys,
            isAutoRepeat: true,
            secureInputActive: false,
            typedCharacter: "a") == nil,
               "keystroke overlay ignores held key auto-repeat events")

        // Mode filtering: All keys vs Shortcuts only
        suite.expect(KeystrokeOverlaySupport.keyCaps(
            keyCode: Int64(kVK_ANSI_A),
            modifiers: [],
            mode: .allKeys,
            isAutoRepeat: false,
            secureInputActive: false,
            typedCharacter: "a") == ["A"],
               "all-keys mode shows plain letter keys")
        suite.expect(KeystrokeOverlaySupport.keyCaps(
            keyCode: Int64(kVK_ANSI_A),
            modifiers: [.shift],
            mode: .allKeys,
            isAutoRepeat: false,
            secureInputActive: false,
            typedCharacter: "A") == ["A"],
               "all-keys mode folds Shift into a single character cap")
        suite.expect(KeystrokeOverlaySupport.keyCaps(
            keyCode: Int64(kVK_Tab),
            modifiers: [.shift],
            mode: .allKeys,
            isAutoRepeat: false,
            secureInputActive: false) == ["⇧", "⇥"],
               "special keys keep the Shift cap alongside their symbol")
        suite.expect(KeystrokeOverlaySupport.keyCaps(
            keyCode: Int64(kVK_ANSI_A),
            modifiers: [.shift],
            mode: .shortcutsOnly,
            isAutoRepeat: false,
            secureInputActive: false,
            typedCharacter: "A") == nil,
               "shortcuts-only mode ignores ordinary typing and Shift-only letters")
        suite.expect(KeystrokeOverlaySupport.keyCaps(
            keyCode: Int64(kVK_ANSI_C),
            modifiers: [.command],
            mode: .shortcutsOnly,
            isAutoRepeat: false,
            secureInputActive: false,
            typedCharacter: "c") == ["⌘", "C"],
               "shortcuts-only mode shows primary modifier combinations")
        suite.expect(KeystrokeOverlaySupport.keyCaps(
            keyCode: Int64(kVK_F5),
            modifiers: [],
            mode: .shortcutsOnly,
            isAutoRepeat: false,
            secureInputActive: false) == ["F5"],
               "shortcuts-only mode still shows standalone function keys")

        // Buffer repeat merging, pruning and max visible capacity
        var buffer = KeystrokeOverlayBuffer()
        let firstItems = buffer.record(caps: ["⌘", "C"], now: 10.0, duration: 1.5)
        suite.expect(firstItems.count == 1 && firstItems.first?.repeatCount == 1
                && firstItems.first?.displayText == "⌘ C",
               "first keystroke records with repeat count 1")
        let repeatedItems = buffer.record(caps: ["⌘", "C"], now: 10.4, duration: 1.5)
        suite.expect(repeatedItems.count == 1 && repeatedItems.first?.repeatCount == 2
                && repeatedItems.first?.displayText == "⌘ C ×2",
               "rapid consecutive presses of the same key merge into a repeat count")
        for step in 0..<6 {
            _ = buffer.record(caps: ["\(step)"], now: 11.0 + Double(step) * 0.1, duration: 5.0)
        }
        suite.expect(buffer.items.count == KeystrokeOverlayBuffer.maxVisibleItems
                && buffer.items.first?.caps == ["1"]
                && buffer.items.last?.caps == ["5"],
               "overlay buffer bounds visible items to \(KeystrokeOverlayBuffer.maxVisibleItems)")
        buffer.prune(now: 20.0, duration: 1.5)
        suite.expect(buffer.items.isEmpty, "pruning after the fade-out delay clears expired items")

        // Screen placement math and custom drag-and-drop origin clamping
        let screenRect = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let pillSize = CGSize(width: 140, height: 50)
        let bottomCenter = KeystrokeOverlaySupport.panelFrame(
            size: pillSize, visibleFrame: screenRect, position: .bottomCenter, margin: 28)
        let topRight = KeystrokeOverlaySupport.panelFrame(
            size: pillSize, visibleFrame: screenRect, position: .topRight, margin: 28)
        suite.expect(bottomCenter.midX == screenRect.midX && bottomCenter.minY == 28,
               "bottom-center placement centers horizontally above the bottom margin")
        suite.expect(topRight.maxX == screenRect.maxX - 28 && topRight.maxY == screenRect.maxY - 28,
               "top-right placement insets from the top and right edges")
        let draggedInBounds = KeystrokeOverlaySupport.panelFrame(
            size: pillSize,
            visibleFrame: screenRect,
            position: .bottomCenter,
            customOrigin: CGPoint(x: 320, y: 410)
        )
        suite.expect(draggedInBounds.origin == CGPoint(x: 320, y: 410),
               "custom dragged origin overrides preset placement when inside visible screen bounds")
        let draggedOffscreen = KeystrokeOverlaySupport.panelFrame(
            size: pillSize,
            visibleFrame: screenRect,
            position: .bottomCenter,
            customOrigin: CGPoint(x: -500, y: 5000)
        )
        suite.expect(draggedOffscreen.minX == 8 && draggedOffscreen.maxY == screenRect.maxY - 8,
               "custom dragged origin clamps inside the screen's visible frame")

        // Svelte theme metrics, modifier cells, Space/Shift/Super rendering
        suite.expect(KeystrokeOverlayStyle.sanitized(nil) == .svelte
                && KeystrokeOverlayStyle.sanitized("keycaps") == .keycaps
                && KeystrokeOverlaySize.medium.svelteBoxSize == CGSize(width: 200, height: 100),
               "Svelte theme is the default style and matches KeyCastr's 200x100 medium box")
        suite.expect(KeystrokeOverlaySupport.svelteModifierCells.map(\.symbol) == ["⇧", "⌃", "⌥", "⌘"],
               "Svelte bottom bar lists Shift, Control, Option and Command in order")
        suite.expect(KeystrokeOverlaySupport.modifierPreviewLabel(modifiers: [.shift]) == "⇧"
                && KeystrokeOverlaySupport.modifierPreviewLabel(modifiers: [.shift, .command]) == "⇧ ⌘"
                && KeystrokeOverlaySupport.modifierPreviewLabel(modifiers: [], superKeyHeld: true) == "Super"
                && KeystrokeOverlaySupport.modifierPreviewLabel(modifiers: .validMask) == "Super",
               "modifier preview renders Shift, modifier chords and Super")
        suite.expect(KeystrokeOverlaySupport.svelteToken(
            keyCode: Int64(kVK_Space),
            modifiers: [],
            mode: .allKeys,
            isAutoRepeat: false,
            secureInputActive: false)?.text == "␣",
               "Svelte token renders Space as ␣")
        suite.expect(KeystrokeOverlaySupport.svelteToken(
            keyCode: Int64(kVK_Tab),
            modifiers: [.shift],
            mode: .allKeys,
            isAutoRepeat: false,
            secureInputActive: false)?.text == "⇤",
               "Svelte token renders Shift+Tab as ⇤")
        suite.expect(KeystrokeOverlaySupport.svelteToken(
            keyCode: Int64(kVK_Space),
            modifiers: [.command, .option, .control, .shift],
            mode: .shortcutsOnly,
            isAutoRepeat: false,
            secureInputActive: false,
            superKeyHeld: true)?.text == "Super ␣",
               "Svelte token renders Super+Space even in shortcuts-only mode")
        suite.expect(KeystrokeOverlaySupport.keyCaps(
            keyCode: Int64(SuperKeySupport.triggerKeyCode),
            modifiers: [],
            mode: .shortcutsOnly,
            isAutoRepeat: false,
            secureInputActive: false) == ["Super"],
               "standalone Super key trigger renders as Super")

        var svelteBuffer = KeystrokeOverlaySvelteBuffer()
        svelteBuffer.setTransientModifier("⇧")
        suite.expect(svelteBuffer.displayText == "⇧",
               "holding Shift shows ⇧ in the Svelte box before another key is pressed")
        _ = svelteBuffer.record(token: "H", isStandalone: false, now: 1.0, duration: 1.5)
        _ = svelteBuffer.record(token: "I", isStandalone: false, now: 1.1, duration: 1.5)
        _ = svelteBuffer.record(token: "␣", isStandalone: false, now: 1.2, duration: 1.5)
        suite.expect(svelteBuffer.displayText == "HI␣",
               "rolling typing in Svelte accumulates characters and Space inside the box")
        _ = svelteBuffer.record(token: "Super K", isStandalone: true, now: 1.3, duration: 1.5)
        suite.expect(svelteBuffer.displayText == "Super K",
               "standalone shortcut replaces rolling text in the Svelte box")

        let captureSuiteName = "vorssaint.test.keystroke-captures.\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: captureSuiteName) {
            defer { defaults.removePersistentDomain(forName: captureSuiteName) }
            suite.expect(KeystrokeOverlayConfig.showsInCaptures(in: defaults) == true,
                   "keystroke overlay defaults to visible in screen recordings and screenshots")
            defaults.set(false, forKey: DefaultsKey.keystrokeOverlayShowInCaptures)
            suite.expect(KeystrokeOverlayConfig.showsInCaptures(in: defaults) == false,
                   "keystroke overlay respects disabling visibility in captures")
            defaults.set(true, forKey: DefaultsKey.keystrokeOverlayShowInCaptures)
            suite.expect(KeystrokeOverlayConfig.showsInCaptures(in: defaults) == true,
                   "keystroke overlay respects enabling visibility in captures")
        }
    }
}
