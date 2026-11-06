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
        runCandidates(suite, abc: abc, ru: ru, kz: kz)
        runTrigger(suite)

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

        suite.run("LayoutFix relabelWordAfterFix") {
            var buffer = LayoutFixBuffer()
            let typed = keys([4, 14, space] + privet + [space], in: abc.id)
            for key in typed { buffer.apply(.append, key: key) }
            let before = buffer.generation
            suite.expect(buffer.relabelWord(count: privet.count, trailingSpaces: 1,
                                            layoutID: "com.apple.keylayout.Russian"),
                         "a word at the end of the buffer is relabeled")
            suite.expect(buffer.keys.suffix(7).prefix(6).allSatisfy { $0.layoutID == "com.apple.keylayout.Russian" }
                             && buffer.keys.prefix(3).allSatisfy { $0.layoutID == abc.id }
                             && buffer.keys.last?.layoutID == abc.id,
                         "only the word's keys move to the new layout")
            suite.expect(buffer.generation == before, "relabeling is not typing")
            suite.expect(!buffer.relabelWord(count: 9, trailingSpaces: 1, layoutID: "x"),
                         "a word longer than what follows the last space is refused")
            var original = LayoutFixBuffer()
            for key in typed { original.apply(.append, key: key) }
            _ = original.relabelWord(count: privet.count, trailingSpaces: 1, layoutID: "x")
            original.restoreWord(keys(privet, in: abc.id), trailingSpaces: 1)
            suite.expect(original.keys == typed, "restoring puts the original keys back")
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

    static func runCandidates(_ suite: TestSuite, abc: LayoutFixLayout, ru: LayoutFixLayout, kz: LayoutFixLayout) {
        let layouts = [abc, ru, kz]
        let dictionary: Set<String> = ["привет|ru", "hello|en"]
        let isWord: (String, String) -> Bool = { dictionary.contains("\($0)|\($1)") }
        func candidates(_ codes: [UInt16], typedIn layout: LayoutFixLayout) -> [LayoutFixCandidate] {
            let typed = keys(codes, in: layout.id)
            let original = LayoutFixSupport.render(typed, in: layout) ?? ""
            return LayoutFixSupport.candidates(keys: typed, originalText: original, layouts: layouts, isWord: isWord)
        }

        suite.run("LayoutFix isCleanRule") {
            for (text, clean) in [("сәлем", true), ("с2лем", false), ("привет,", true), ("a.b", false),
                                  ("2026", true), ("(hello)", true), ("don't", false)] {
                suite.expect(LayoutFixSupport.isClean(text) == clean, "isClean(\(text)) should be \(clean)")
            }
        }

        suite.run("LayoutFix kazakhBeatsDigitInWord") {
            let ranked = candidates([8, 19, 40, 17, 9], typedIn: abc)
            suite.expect(ranked == [LayoutFixCandidate(text: "сәлем", layoutIDs: [kz.id]),
                                    LayoutFixCandidate(text: "с2лем", layoutIDs: [ru.id])],
                         "сәлем ranks above с2лем, got \(ranked)")
        }

        suite.run("LayoutFix dictionaryWordFirst") {
            let ranked = candidates([5, 4, 11, 2, 17, 45], typedIn: abc)
            suite.expect(ranked == [LayoutFixCandidate(text: "привет", layoutIDs: [ru.id, kz.id])],
                         "identical renderings merge into one candidate, got \(ranked)")
            let english = candidates([4, 14, 37, 37, 31], typedIn: ru)
            suite.expect(english.first == LayoutFixCandidate(text: "hello", layoutIDs: [abc.id]),
                         "a dictionary word comes first, got \(english)")
        }

        suite.run("LayoutFix identicalToOriginalDropped") {
            let ranked = candidates([43, 3, 40, 3], typedIn: ru)
            suite.expect(ranked == [LayoutFixCandidate(text: ",fkf", layoutIDs: [abc.id])],
                         "the Kazakh rendering equals the original and is dropped, got \(ranked)")
        }

        suite.run("LayoutFix targetUsesRecency") {
            let both = LayoutFixCandidate(text: "бала", layoutIDs: [ru.id, kz.id])
            suite.expect(LayoutFixSupport.targetLayoutID(for: both, recency: [kz.id, abc.id, ru.id]) == kz.id,
                         "the most recently used of the merged layouts")
            suite.expect(LayoutFixSupport.targetLayoutID(for: both, recency: []) == ru.id,
                         "the first in order when none was used")
        }

        suite.run("LayoutFix cycleWalksAndReturns") {
            let original = LayoutFixCandidate(text: "c2ktv", layoutIDs: [abc.id])
            let first = LayoutFixCandidate(text: "сәлем", layoutIDs: [kz.id])
            let second = LayoutFixCandidate(text: "с2лем", layoutIDs: [ru.id])
            var cycle = LayoutFixCycle(keys: keys([8, 19, 40, 17, 9], in: abc.id), trailingSpaces: 0,
                                       original: original, candidates: [first, second])
            suite.expect(cycle.shown == original, "nothing is replaced before the first tap")
            let walk = (0..<4).map { _ in cycle.advance() }
            suite.expect(walk == [first, second, original, first], "taps walk the candidates and come back, got \(walk)")
            suite.expect(cycle.shown == first, "shown follows the last tap")
        }

        suite.run("LayoutFix selectionCandidates") {
            let phrase = LayoutFixSupport.selectionCandidates(text: "ghbdtn vbh", layouts: layouts,
                                                              currentID: abc.id, isWord: isWord)
            suite.expect(phrase?.original == LayoutFixCandidate(text: "ghbdtn vbh", layoutIDs: [abc.id]),
                         "the selection is read in the current layout")
            suite.expect(phrase?.candidates.first == LayoutFixCandidate(text: "привет мир", layoutIDs: [ru.id, kz.id]),
                         "each word maps through the keys, got \(String(describing: phrase?.candidates))")
            let lines = LayoutFixSupport.selectionCandidates(text: "ghbdtn\n\tvbh ", layouts: layouts,
                                                             currentID: abc.id, isWord: isWord)
            suite.expect(lines?.candidates.first?.text == "привет\n\tмир ", "whitespace is kept verbatim")
            let kazakh = LayoutFixSupport.selectionCandidates(text: "сәлем", layouts: layouts,
                                                              currentID: ru.id, isWord: isWord)
            suite.expect(kazakh?.original.layoutIDs == [kz.id], "only Kazakh types ә, so it is the source")
            suite.expect(kazakh?.candidates.map(\.text) == ["c2ktv", "с2лем"],
                         "the other layouts follow in order, got \(String(describing: kazakh?.candidates))")
            suite.expect(LayoutFixSupport.selectionCandidates(text: "😀", layouts: layouts,
                                                              currentID: abc.id, isWord: isWord) == nil,
                         "text no layout types has no candidates")
            suite.expect(LayoutFixSupport.selectionCandidates(text: " \n", layouts: layouts,
                                                              currentID: abc.id, isWord: isWord) == nil,
                         "whitespace alone has nothing to fix")
        }

        suite.run("LayoutFix isWordTreatsUnavailableLanguageAsUnknown") {
            let available: Set<String> = ["en", "ru"]
            suite.expect(!LayoutFixSupport.isWord("с2лем", language: "kk", available: available) { _, _ in true },
                         "a language the spell checker lacks never confirms a word")
            suite.expect(LayoutFixSupport.isWord("привет", language: "ru", available: available) { _, _ in true },
                         "an available language asks the checker")
            suite.expect(!LayoutFixSupport.isWord("", language: "ru", available: available) { _, _ in true },
                         "empty text is not a word")
        }
    }

    static func runTrigger(_ suite: TestSuite) {
        let ms: UInt64 = 1_000_000
        let t: UInt64 = 1_000 * ms
        func fires(_ trigger: LayoutFixTrigger, _ events: [LayoutFixTriggerEvent]) -> [Bool] {
            var state = LayoutFixTriggerState(trigger: trigger)
            return events.map { state.fires($0) }
        }
        let right = kVK_RightOption, left = kVK_Option, shift = kVK_Shift, rightShift = kVK_RightShift

        suite.run("LayoutFix rightOptionSoloTap") {
            suite.expect(fires(.rightOption, [.modifierDown(keyCode: right, timestamp: t),
                                              .modifierUp(keyCode: right, timestamp: t + 100 * ms)]) == [false, true],
                         "a quick lone tap fires on release")
            suite.expect(fires(.rightOption, [.modifierDown(keyCode: right, timestamp: t),
                                              .modifierUp(keyCode: right, timestamp: t + 350 * ms)]) == [false, false],
                         "a hold longer than 0.3 s is plain Option")
            suite.expect(LayoutFixTriggerState.soloTapMaxNanoseconds == 300 * ms, "the tap threshold is 0.3 s")
            suite.expect(fires(.rightOption, [.modifierUp(keyCode: right, timestamp: t)]) == [false],
                         "a release without a press does not fire")
        }

        suite.run("LayoutFix optionWithKeyIsNotATap") {
            suite.expect(fires(.rightOption, [.modifierDown(keyCode: right, timestamp: t), .otherKey,
                                              .modifierUp(keyCode: right, timestamp: t + 50 * ms)]).last == false,
                         "⌥ held with a key types a character")
            suite.expect(fires(.rightOption, [.modifierDown(keyCode: right, timestamp: t),
                                              .modifierDown(keyCode: shift, timestamp: t + 10 * ms),
                                              .modifierUp(keyCode: shift, timestamp: t + 20 * ms),
                                              .modifierUp(keyCode: right, timestamp: t + 50 * ms)]).last == false,
                         "another modifier during the press is a chord")
        }

        suite.run("LayoutFix mouseCancelsTap") {
            suite.expect(fires(.rightOption, [.modifierDown(keyCode: right, timestamp: t), .mouse,
                                              .modifierUp(keyCode: right, timestamp: t + 50 * ms)]).last == false,
                         "⌥-click is not a tap")
        }

        suite.run("LayoutFix leftOptionOnlyWhenChosen") {
            let leftTap: [LayoutFixTriggerEvent] = [.modifierDown(keyCode: left, timestamp: t),
                                                    .modifierUp(keyCode: left, timestamp: t + 50 * ms)]
            let rightTap: [LayoutFixTriggerEvent] = [.modifierDown(keyCode: right, timestamp: t),
                                                     .modifierUp(keyCode: right, timestamp: t + 50 * ms)]
            suite.expect(fires(.rightOption, leftTap).last == false, "left ⌥ is ignored for the right ⌥ trigger")
            suite.expect(fires(.leftOption, leftTap).last == true, "left ⌥ fires when chosen")
            suite.expect(fires(.leftOption, rightTap).last == false, "right ⌥ is ignored for the left ⌥ trigger")
        }

        suite.run("LayoutFix doubleShift") {
            func taps(_ code: Int, at start: UInt64, gap: UInt64) -> [LayoutFixTriggerEvent] {
                [.modifierDown(keyCode: code, timestamp: start), .modifierUp(keyCode: code, timestamp: start + 50 * ms),
                 .modifierDown(keyCode: code, timestamp: start + 50 * ms + gap - 50 * ms),
                 .modifierUp(keyCode: code, timestamp: start + 50 * ms + gap)]
            }
            suite.expect(fires(.doubleShift, taps(shift, at: t, gap: 250 * ms)) == [false, false, false, true],
                         "two shift taps 250 ms apart fire on the second release")
            suite.expect(fires(.doubleShift, taps(rightShift, at: t, gap: 250 * ms)).last == true,
                         "right shift counts too")
            suite.expect(fires(.doubleShift, taps(shift, at: t, gap: 500 * ms)).last == false,
                         "500 ms apart is two separate presses")
            suite.expect(fires(.doubleShift, Array(taps(shift, at: t, gap: 250 * ms).prefix(2))).last == false,
                         "a single tap does not fire")
            var events = taps(shift, at: t, gap: 250 * ms)
            events.insert(.otherKey, at: 2)
            suite.expect(fires(.doubleShift, events).last == false, "a key between the taps resets")
            let twoPairs: [LayoutFixTriggerEvent] = taps(shift, at: t, gap: 250 * ms)
                + taps(shift, at: t + 400 * ms, gap: 250 * ms)
            let expected: [Bool] = [false, false, false, true, false, false, false, true]
            suite.expect(fires(.doubleShift, twoPairs) == expected, "after firing, the next pair starts over")
        }

        suite.run("LayoutFix triggerSanitized") {
            suite.expect(LayoutFixTrigger.sanitized(nil) == .rightOption
                             && LayoutFixTrigger.sanitized("doubleShift") == .doubleShift
                             && LayoutFixTrigger.sanitized("bogus") == .rightOption,
                         "unknown stored triggers fall back to right ⌥")
        }

        suite.run("LayoutFix guardDecisions") {
            suite.expect(LayoutFixSupport.guardDecision(expected: "ghbdtn ", textBeforeCaret: "hi ghbdtn ") == .match,
                         "the field ends with the expected word")
            suite.expect(LayoutFixSupport.guardDecision(expected: "ghbdtn ", textBeforeCaret: "hi ghbdt") == .mismatch,
                         "the field shows something else")
            suite.expect(LayoutFixSupport.guardDecision(expected: "ghbdtn ", textBeforeCaret: nil) == .unknown,
                         "no answer from the field")
        }

        suite.run("LayoutFix targetRules") {
            func target(_ length: Int, markers: Bool = false, app: String? = "com.apple.TextEdit",
                        word: Bool = true) -> LayoutFixTarget {
                LayoutFixSupport.target(selectionLength: length, selectionFromTextMarkers: markers,
                                        bundleID: app, hasWord: word)
            }
            suite.expect(target(5) == .selection, "a field selection wins")
            suite.expect(target(5, markers: true) == .lastWord, "web selections fall back to the last word")
            suite.expect(target(5, markers: true, word: false) == .nothing, "web selection without a word")
            suite.expect(target(5, app: "com.apple.Terminal") == .lastWord, "terminal selections are scrollback")
            suite.expect(target(0) == .lastWord, "no selection fixes the last word")
            suite.expect(target(0, word: false) == .nothing, "nothing to fix")
            suite.expect(LayoutFixSupport.terminalBundleIDs.contains("com.googlecode.iterm2"), "iTerm is a terminal")
        }
    }
}
