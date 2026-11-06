// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

/// Layout Fix decisions against the real ABC, Russian and Kazakh key tables
/// macOS ships. The layouts are read whether or not they are enabled, so the
/// suite does not depend on the Mac it runs on having them in the Input menu.
enum LayoutFixSupportTests {
    static func systemLayout(_ id: String, language: String) -> LayoutFixLayout? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first,
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return LayoutFixLayout(id: id,
                               language: language,
                               table: LayoutFixSupport.table(from: data, capsLock: false),
                               capsTable: LayoutFixSupport.table(from: data, capsLock: true))
    }

    static func keys(_ codes: [UInt16], in id: String,
                     shift: Bool = false, option: Bool = false, capsLock: Bool = false) -> [LayoutFixKey] {
        codes.map { LayoutFixKey(keyCode: $0, shift: shift, option: option, capsLock: capsLock, layoutID: id) }
    }

    static func run(_ suite: TestSuite) {
        guard let abc = systemLayout("com.apple.keylayout.ABC", language: "en"),
              let ru = systemLayout("com.apple.keylayout.Russian", language: "ru"),
              let kz = systemLayout("com.apple.keylayout.Kazakh", language: "kk")
        else {
            suite.expect(false, "the ABC, Russian and Kazakh layouts are readable from TIS")
            return
        }
        func expectEqual(_ actual: String?, _ expected: String?, _ label: String,
                         file: StaticString = #filePath, line: UInt = #line) {
            suite.expect(actual == expected,
                         "\(label): got \(actual ?? "nil"), expected \(expected ?? "nil")",
                         file: file, line: line)
        }
        let privet: [UInt16] = [5, 4, 11, 2, 17, 45]
        let salem: [UInt16] = [8, 19, 40, 17, 9]
        let bala: [UInt16] = [43, 3, 40, 3]
        let hello: [UInt16] = [4, 14, 37, 37, 31]

        suite.run("LayoutFix renderAcrossLayouts") {
            expectEqual(LayoutFixSupport.render(keys(privet, in: abc.id), in: abc), "ghbdtn", "privet ABC")
            expectEqual(LayoutFixSupport.render(keys(privet, in: abc.id), in: ru), "привет", "privet RU")
            expectEqual(LayoutFixSupport.render(keys(privet, in: abc.id), in: kz), "привет", "privet KZ")
            expectEqual(LayoutFixSupport.render(keys(salem, in: abc.id), in: abc), "c2ktv", "salem ABC")
            expectEqual(LayoutFixSupport.render(keys(salem, in: abc.id), in: ru), "с2лем", "salem RU")
            expectEqual(LayoutFixSupport.render(keys(salem, in: abc.id), in: kz), "сәлем", "salem KZ")
            expectEqual(LayoutFixSupport.render(keys(bala, in: abc.id), in: abc), ",fkf", "bala ABC")
            expectEqual(LayoutFixSupport.render(keys(bala, in: abc.id), in: ru), "бала", "bala RU")
            expectEqual(LayoutFixSupport.render(keys(bala, in: abc.id), in: kz), "бала", "bala KZ")
            expectEqual(LayoutFixSupport.render(keys(hello, in: abc.id), in: ru), "руддщ", "hello RU")
        }

        suite.run("LayoutFix kazakhNumberRow") {
            expectEqual(LayoutFixSupport.render(keys([19, 29, 19, 22], in: kz.id), in: kz), "әқә,", "2026 typed in KZ")
            var differing = 0
            for code in UInt16(0)...50 {
                for shift in [false, true] {
                    let chord = LayoutFixChord(keyCode: code, shift: shift, option: false)
                    if ru.table[chord] != kz.table[chord] { differing += 1 }
                }
            }
            suite.expect(differing == 27, "Russian and Kazakh differ at 27 chords, got \(differing)")
        }

        suite.run("LayoutFix kazakhOptionDigits") {
            expectEqual(LayoutFixSupport.render(keys([19], in: kz.id, option: true), in: kz), "2", "⌥2 KZ")
            expectEqual(LayoutFixSupport.render(keys([19], in: kz.id, option: true), in: ru), "@", "⌥2 RU")
        }

        suite.run("LayoutFix capsLockRendersThroughLayout") {
            expectEqual(LayoutFixSupport.render(keys([5], in: abc.id, shift: true), in: abc), "G", "shift g ABC")
            expectEqual(LayoutFixSupport.render(keys([5], in: ru.id, capsLock: true), in: ru), "П", "caps g RU")
            expectEqual(LayoutFixSupport.render(keys([19], in: kz.id, capsLock: true), in: kz), "Ә", "caps 2 KZ")
            expectEqual(LayoutFixSupport.render(keys([19], in: ru.id, capsLock: true), in: ru), "2", "caps 2 RU")
        }

        suite.run("LayoutFix reverseMap") {
            let typed = LayoutFixSupport.keys(for: "привет", in: ru)
            expectEqual(typed.flatMap { LayoutFixSupport.render($0, in: ru) }, "привет", "round trip RU")
            expectEqual(typed.flatMap { LayoutFixSupport.render($0, in: abc) }, "ghbdtn", "RU keys in ABC")
            suite.expect(LayoutFixSupport.keys(for: "Привет", in: ru)?.first?.shift == true,
                         "capital letter maps to a shifted key")
            suite.expect(LayoutFixSupport.keys(for: "a😀", in: abc) == nil,
                         "a character no key types has no keys")
        }

        suite.run("LayoutFix sourceLayoutPrefersCurrent") {
            let layouts = [abc, ru, kz]
            expectEqual(LayoutFixSupport.sourceLayout(for: "бала", layouts: layouts, currentID: kz.id)?.id,
                        kz.id, "current layout covers the text")
            expectEqual(LayoutFixSupport.sourceLayout(for: "бала", layouts: layouts, currentID: abc.id)?.id,
                        ru.id, "first covering layout in order")
            expectEqual(LayoutFixSupport.sourceLayout(for: "сәлем", layouts: layouts, currentID: ru.id)?.id,
                        kz.id, "only Kazakh types ә")
            suite.expect(LayoutFixSupport.sourceLayout(for: "😀", layouts: layouts, currentID: nil) == nil,
                         "no layout types an emoji")
        }

        suite.run("LayoutFix unmappedKeyDropsRendering") {
            let missing = LayoutFixKey(keyCode: 200, shift: false, option: false, capsLock: false, layoutID: abc.id)
            suite.expect(LayoutFixSupport.render(keys([5], in: abc.id) + [missing], in: ru) == nil,
                         "a key absent from the table makes the whole rendering nil")
        }

        runBuffer(suite, abc: abc)

        suite.run("LayoutFix renderOriginalUsesEachKeysLayout") {
            let mixed = keys([5, 4], in: abc.id) + keys([11, 2], in: ru.id)
            expectEqual(LayoutFixSupport.renderOriginal(mixed, layouts: [abc, ru, kz]), "ghив",
                        "each key in the layout it was typed in")
        }
    }

    static func runBuffer(_ suite: TestSuite, abc: LayoutFixLayout) {
        let space = UInt16(kVK_Space)
        let privet: [UInt16] = [5, 4, 11, 2, 17, 45]

        suite.run("LayoutFix bufferActionTable") {
            func action(_ code: Int, command: Bool = false, control: Bool = false) -> LayoutFixBufferAction {
                LayoutFixSupport.bufferAction(keyCode: code, command: command, control: control)
            }
            suite.expect(action(kVK_Delete) == .deleteLast, "backspace removes the last key")
            for code in [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End,
                         kVK_PageUp, kVK_PageDown, kVK_Escape, kVK_Tab, kVK_Return, kVK_ANSI_KeypadEnter,
                         kVK_ForwardDelete] {
                suite.expect(action(code) == .reset, "key \(code) resets the buffer")
            }
            suite.expect(action(kVK_ANSI_G, command: true) == .reset, "a command shortcut resets")
            suite.expect(action(kVK_ANSI_G, control: true) == .reset, "a control shortcut resets")
            for code in [kVK_ANSI_G, kVK_ANSI_2, kVK_Space, kVK_ANSI_Comma, kVK_ISO_Section, kVK_ANSI_Grave] {
                suite.expect(action(code) == .append, "key \(code) is typing")
            }
            suite.expect(action(kVK_F5) == .reset, "a function key is not typing")
        }

        suite.run("LayoutFix returnResetsBuffer") {
            var buffer = LayoutFixBuffer()
            for key in keys([5, 4, 11], in: abc.id) { buffer.apply(.append, key: key) }
            buffer.apply(.reset, key: nil)
            suite.expect(buffer.keys.isEmpty, "reset empties the buffer")
        }

        suite.run("LayoutFix capacityDropsOldest") {
            var buffer = LayoutFixBuffer()
            for index in 0..<70 {
                buffer.apply(.append, key: LayoutFixKey(keyCode: UInt16(index % 50), shift: false, option: false,
                                                        capsLock: false, layoutID: abc.id))
            }
            suite.expect(buffer.keys.count == LayoutFixBuffer.capacity && LayoutFixBuffer.capacity == 64,
                         "the buffer holds the last 64 keys, got \(buffer.keys.count)")
            suite.expect(buffer.keys.first?.keyCode == UInt16(6 % 50), "the oldest keys are dropped first")
        }

        suite.run("LayoutFix deleteLastRemovesOneKey") {
            var buffer = LayoutFixBuffer()
            for key in keys([5, 4], in: abc.id) { buffer.apply(.append, key: key) }
            buffer.apply(.deleteLast, key: nil)
            suite.expect(buffer.keys.map(\.keyCode) == [5], "backspace drops the last key")
            buffer.apply(.deleteLast, key: nil)
            buffer.apply(.deleteLast, key: nil)
            suite.expect(buffer.keys.isEmpty, "backspace on an empty buffer is harmless")
        }

        suite.run("LayoutFix generationChangesOnEveryMutation") {
            var buffer = LayoutFixBuffer()
            var last = buffer.generation
            for (action, key) in [(LayoutFixBufferAction.append, keys([5], in: abc.id).first),
                                  (.deleteLast, nil), (.reset, nil), (.reset, nil)] {
                buffer.apply(action, key: key)
                suite.expect(buffer.generation == last + 1, "\(action) advances the generation")
                last = buffer.generation
            }
            buffer.apply(.ignore, key: nil)
            suite.expect(buffer.generation == last, "an ignored key leaves the generation alone")
        }

        suite.run("LayoutFix lastWordKeepsTrailingSpaces") {
            let word = keys(privet, in: abc.id)
            let spaces = keys([space, space], in: abc.id)
            let trailing = LayoutFixSupport.lastWord(word + spaces)
            suite.expect(trailing?.word == word && trailing?.trailingSpaces == 2,
                         "the word before two spaces keeps both spaces")
            let second = LayoutFixSupport.lastWord(keys([4, 14, 37, 37, 31, space], in: abc.id) + word)
            suite.expect(second?.word == word && second?.trailingSpaces == 0,
                         "only the word after the last space")
            suite.expect(LayoutFixSupport.lastWord(spaces) == nil, "only spaces is no word")
            suite.expect(LayoutFixSupport.lastWord([]) == nil, "an empty buffer is no word")
        }
    }
}
