// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum KeyboardTyperTests {
    static func run(_ suite: TestSuite) {
        suite.expect(KeyboardTyperSupport.sanitizedDelay(-5) == 0
                        && KeyboardTyperSupport.sanitizedDelay(99_999) == 2000
                        && KeyboardTyperSupport.sanitizedDelay(35) == 35,
                     "the keyboard typer delay stays within 0 to 2000 ms")
        suite.expect(KeyboardTyperSupport.sanitizedCountdown(0) == 1
                        && KeyboardTyperSupport.sanitizedCountdown(11) == 10
                        && KeyboardTyperSupport.sanitizedCountdown(4) == 4,
                     "the delayed Send waits 1 to 10 seconds")
        let named = KeyboardTyperSnippet(name: "  VPN  ", text: "secret")
        let unnamed = KeyboardTyperSnippet(name: " ", text: "\n  \n  first line \nsecond")
        suite.expect(KeyboardTyperSupport.title(of: named) == "VPN"
                        && KeyboardTyperSupport.title(of: unnamed) == "first line",
                     "a snippet shows its name, otherwise its first line with text")
        let encoded = try? JSONEncoder().encode([named, unnamed])
        suite.expect(encoded.flatMap { try? JSONDecoder().decode([KeyboardTyperSnippet].self, from: $0) }
                        == [named, unnamed],
                     "saved snippets read back whole, ids included")

        func window(_ pid: Int32, layer: Int = 0) -> [String: Any] {
            [kCGWindowOwnerPID as String: NSNumber(value: pid), kCGWindowLayer as String: NSNumber(value: layer)]
        }
        suite.expect(KeyboardTyperSupport.appBehind(windows: [window(7, layer: 25), window(1), window(42), window(9)],
                                                    ownPID: 1) == 42
                        && KeyboardTyperSupport.appBehind(windows: [window(1), window(1, layer: 3)], ownPID: 1) == nil,
                     "with this app in front, Send aims at the app whose window is right behind ours, never at ours")
        suite.expect(KeyboardTyperSupport.missingCharacters(in: [.unicode(Array("é".utf16)),
                                                                 .key(KeyboardTyperKey(code: 0)),
                                                                 .unicode(Array("€".utf16)),
                                                                 .unicode(Array("é".utf16))]) == "é €"
                        && KeyboardTyperSupport.missingCharacters(in: [.key(KeyboardTyperKey(code: 0))]).isEmpty,
                     "the characters a layout cannot type are named once each")

        suite.expect(KeyboardTyperSupport.favorites(from: "a,,b,a") == ["a", "b"]
                        && KeyboardTyperSupport.favorites(from: nil).isEmpty
                        && KeyboardTyperSupport.toggling("b", in: ["a", "b"]) == ["a"]
                        && KeyboardTyperSupport.toggling("c", in: ["a"]) == ["a", "c"],
                     "keyboard typer favorites keep their starred order, once each")
        suite.expect(KeyboardTyperSupport.destinationLayoutID(selected: "b", favorites: ["a", "b"]) == "b"
                        && KeyboardTyperSupport.destinationLayoutID(selected: "c", favorites: ["a"]) == nil
                        && KeyboardTyperSupport.destinationLayoutID(selected: "", favorites: [""]) == nil
                        && KeyboardTyperSupport.destinationLayoutID(selected: nil, favorites: ["a"]) == nil,
                     "only a starred destination layout replaces the system one")

        let layouts = KeyboardTyperSupport.installedLayouts()
        suite.expect(layouts.contains { $0.id == "com.apple.keylayout.US" }
                        && layouts.contains { $0.id == "com.apple.keylayout.French" }
                        && Set(layouts.map(\.id)).count == layouts.count,
                     "the keyboard typer lists every layout macOS ships, once each, found \(layouts.count)")

        if let french = KeyboardTyperSupport.layoutData(id: "com.apple.keylayout.French") {
            let azerty = KeyboardTyperSupport.keyMap(layoutData: french, keyboardType: UInt32(LMGetKbdType()))
            if let swiss = KeyboardTyperSupport.layoutData(id: "com.apple.keylayout.SwissGerman") {
                let swissMap = KeyboardTyperSupport.keyMap(layoutData: swiss, keyboardType: UInt32(LMGetKbdType()))
                let typed = KeyboardTyperSupport.strokes(for: "/\\y", map: swissMap)
                suite.expect(typed == [.key(KeyboardTyperKey(code: CGKeyCode(kVK_ANSI_7), shift: true)),
                                       .altGraph(code: CGKeyCode(kVK_ANSI_7), character: Array("\\".utf16)),
                                       .key(KeyboardTyperKey(code: CGKeyCode(kVK_ANSI_Z)))],
                             "Swiss German types / with Shift, y on its own key, and \\ under AltGr without Shift, found \(typed)")
                let positions = KeyboardTyperSupport.strokes(for: "\\", map: swissMap, method: .keyPositions)
                suite.expect(positions == [.key(KeyboardTyperKey(code: CGKeyCode(kVK_ANSI_7), shift: true, option: true))],
                             "sending key positions types \\ with the Mac's own Option and Shift, found \(positions)")
                suite.expect(KeyboardTyperMethod.sanitized(nil) == .characters
                                && KeyboardTyperMethod.sanitized("bogus") == .characters
                                && KeyboardTyperMethod.sanitized("keyPositions") == .keyPositions,
                             "the typing method defaults to characters")
            } else {
                suite.expect(false, "the Swiss German layout is available to the keyboard typer tests")
            }
            suite.expect(azerty["a"] == KeyboardTyperKey(code: CGKeyCode(kVK_ANSI_Q))
                            && azerty["1"] == KeyboardTyperKey(code: CGKeyCode(kVK_ANSI_1), shift: true),
                         "a French destination presses the AZERTY keys")
        } else {
            suite.expect(false, "the French layout is available to the keyboard typer tests")
        }

        guard let layoutData = KeyboardTyperSupport.layoutData(id: "com.apple.keylayout.US") else {
            suite.expect(false, "the U.S. keyboard layout is available to the keyboard typer tests")
            return
        }
        let map = KeyboardTyperSupport.keyMap(layoutData: layoutData, keyboardType: UInt32(LMGetKbdType()))
        let key = { (code: Int, shift: Bool) in KeyboardTyperStroke.key(KeyboardTyperKey(code: CGKeyCode(code), shift: shift)) }

        let strokes = KeyboardTyperSupport.strokes(for: "aA!1\r\n\t", map: map)
        suite.expect(strokes == [key(kVK_ANSI_A, false), key(kVK_ANSI_A, true), key(kVK_ANSI_1, true),
                                 key(kVK_ANSI_1, false), key(kVK_Return, false), key(kVK_Tab, false)],
                     "the keyboard typer presses the U.S. keys, Shift included, and one Return for CRLF, found \(strokes)")

        suite.expect(map["*"] == KeyboardTyperKey(code: CGKeyCode(kVK_ANSI_8), shift: true),
                     "the keyboard typer types * from the top row, never the keypad")
        // Option-E is the U.S. acute dead key; Shift-Option-E types ´ outright.
        suite.expect(!map.values.contains(KeyboardTyperKey(code: CGKeyCode(kVK_ANSI_E), option: true))
                        && map["`"] == KeyboardTyperKey(code: CGKeyCode(kVK_ANSI_Grave)),
                     "the keyboard typer never presses a dead key, but keeps the plain grave key")

        let fallback = KeyboardTyperSupport.strokes(for: "é😀", map: map)
        suite.expect(fallback == [.unicode(Array("é".utf16)), .unicode(Array("😀".utf16))],
                     "characters without a single key go out whole as Unicode, found \(fallback)")
    }
}
