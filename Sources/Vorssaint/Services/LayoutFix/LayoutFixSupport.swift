// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

/// One physical key with the modifiers that change what a layout types on it.
struct LayoutFixChord: Hashable {
    let keyCode: UInt16
    let shift: Bool
    let option: Bool
}

/// One keystroke as it was typed: the key, its modifiers and the layout that
/// was active, so the same keys can be shown in any other layout.
struct LayoutFixKey: Equatable {
    let keyCode: UInt16
    let shift: Bool
    let option: Bool
    let capsLock: Bool
    let layoutID: String

    var chord: LayoutFixChord { LayoutFixChord(keyCode: keyCode, shift: shift, option: option) }
}

/// An enabled keyboard layout reduced to what the fix needs: its id, the
/// language its words are checked in, and what each chord types with Caps
/// Lock off and on. Both tables come from the layout's own data, so custom
/// layouts and the number row of layouts like Kazakh are covered.
struct LayoutFixLayout: Equatable {
    let id: String
    let language: String
    let table: [LayoutFixChord: String]
    let capsTable: [LayoutFixChord: String]
    /// Chords that start a composed character (⌥e then e is one `é`): the
    /// field shows fewer characters than keys, so a word with one is never
    /// retyped.
    var deadChords: Set<LayoutFixChord> = []
}

/// How the tap treats a key event Vorssaint posted itself.
enum LayoutFixOwnEvent: Equatable {
    /// This feature's own retype: already accounted for.
    case retype
    /// Another feature typed or pasted: the field no longer matches the buffer.
    case otherFeature
    /// A key from the keyboard.
    case typing
}

/// What a key press does to the buffer of keys typed since the caret last moved.
enum LayoutFixBufferAction: Equatable {
    case append, deleteLast, reset, ignore
}

/// The keys typed since the caret last moved somewhere unknown, newest last.
/// Memory only. `generation` moves on every change, so a fix decided on one
/// snapshot can tell that more keys arrived before it ran.
struct LayoutFixBuffer {
    static let capacity = 64

    private(set) var keys: [LayoutFixKey] = []
    private(set) var generation: UInt64 = 0
    /// The app the keys were typed in. Switching away and back, such as to
    /// another desktop, leaves the caret where it was, so the keys stay
    /// until typing goes to a different app.
    private(set) var ownerProcessID: Int32?
    /// How many keys were typed before the last click. A click on a toolbar
    /// leaves the caret where it was, a click in the text moves it: the keys
    /// before it are kept, but only a field that confirms them may be fixed.
    private(set) var clickIndex: Int?

    mutating func noteClick() {
        clickIndex = keys.count
        generation &+= 1
    }

    /// The word a tap would fix. A word never spans a click; one typed
    /// before the last click needs the field to confirm it.
    func wordForFix() -> (word: [LayoutFixKey], trailingSpaces: Int, needsFieldCheck: Bool)? {
        if let clickIndex, clickIndex < keys.count {
            return LayoutFixSupport.lastWord(Array(keys[clickIndex...])).map { ($0.word, $0.trailingSpaces, false) }
        }
        return LayoutFixSupport.lastWord(keys).map { ($0.word, $0.trailingSpaces, clickIndex != nil) }
    }

    mutating func noteTyping(in processID: Int32) {
        guard ownerProcessID != processID else { return }
        if ownerProcessID != nil { apply(.reset, key: nil) }
        ownerProcessID = processID
    }

    mutating func apply(_ action: LayoutFixBufferAction, key: LayoutFixKey?) {
        switch action {
        case .append:
            guard let key else { return }
            keys.append(key)
            if keys.count > Self.capacity {
                let dropped = keys.count - Self.capacity
                keys.removeFirst(dropped)
                clickIndex = clickIndex.map { max(0, $0 - dropped) }
            }
        case .deleteLast:
            if let clickIndex, keys.count <= clickIndex {
                // After a click a backspace deletes wherever the caret is now.
                keys.removeAll()
                self.clickIndex = nil
            } else if !keys.isEmpty {
                keys.removeLast()
            }
        case .reset:
            keys.removeAll()
            clickIndex = nil
        case .ignore:
            return
        }
        generation &+= 1
    }

    /// After a fix the same keys stand for the word in another layout. The
    /// generation stays put: nothing new was typed, so the next tap still
    /// belongs to the same cycle. False when the word is not where it is
    /// expected, at the end of the buffer before `trailingSpaces` spaces.
    @discardableResult
    mutating func relabelWord(count: Int, trailingSpaces: Int, layoutID: String) -> Bool {
        let end = keys.count - trailingSpaces
        let start = end - count
        guard count > 0, trailingSpaces >= 0, start >= 0, end <= keys.count,
              !keys[start..<end].contains(where: { $0.keyCode == UInt16(kVK_Space) })
        else { return false }
        for index in start..<end {
            let key = keys[index]
            keys[index] = LayoutFixKey(keyCode: key.keyCode, shift: key.shift, option: key.option,
                                       capsLock: key.capsLock, layoutID: layoutID)
        }
        return true
    }

    /// Puts the word's keys back as they were first typed, layouts included,
    /// when a cycle comes back to the original.
    mutating func restoreWord(_ word: [LayoutFixKey], trailingSpaces: Int) {
        let end = keys.count - trailingSpaces
        let start = end - word.count
        guard start >= 0, end <= keys.count,
              keys[start..<end].map(\.keyCode) == word.map(\.keyCode) else { return }
        keys.replaceSubrange(start..<end, with: word)
    }
}

/// One way the typed keys could read: the text and every participating layout
/// that types exactly it, in participant order. Russian and Kazakh type most
/// words the same, so they share one candidate instead of two identical taps.
struct LayoutFixCandidate: Equatable {
    let text: String
    let layoutIDs: [String]
}

/// The taps on one word: each tap shows the next candidate, and after the
/// last one the original comes back, so with two layouts the second tap is
/// an undo. `shown` is what the field holds now.
struct LayoutFixCycle: Equatable {
    let keys: [LayoutFixKey]
    let trailingSpaces: Int
    let original: LayoutFixCandidate
    let candidates: [LayoutFixCandidate]
    /// -1 while the original is shown.
    private(set) var position = -1

    init(keys: [LayoutFixKey], trailingSpaces: Int,
         original: LayoutFixCandidate, candidates: [LayoutFixCandidate]) {
        self.keys = keys
        self.trailingSpaces = trailingSpaces
        self.original = original
        self.candidates = candidates
    }

    var shown: LayoutFixCandidate {
        candidates.indices.contains(position) ? candidates[position] : original
    }

    mutating func advance() -> LayoutFixCandidate {
        position = position + 1 < candidates.count ? position + 1 : -1
        return shown
    }
}

/// What starts a fix: a lone tap of a modifier, read from the keyboard tap.
enum LayoutFixTrigger: String, CaseIterable, Identifiable {
    case rightOption, leftOption, doubleShift

    var id: String { rawValue }

    static func sanitized(_ raw: String?) -> LayoutFixTrigger {
        raw.flatMap(LayoutFixTrigger.init(rawValue:)) ?? .rightOption
    }

    /// The modifier keys whose lone taps this trigger listens to.
    var keyCodes: Set<Int> {
        switch self {
        case .rightOption: [kVK_RightOption]
        case .leftOption: [kVK_Option]
        case .doubleShift: [kVK_Shift, kVK_RightShift]
        }
    }
}

/// A keyboard or mouse event, reduced to what the trigger needs.
enum LayoutFixTriggerEvent: Equatable {
    /// A modifier key went down or up; timestamps in nanoseconds.
    case modifierDown(keyCode: Int, timestamp: UInt64)
    case modifierUp(keyCode: Int, timestamp: UInt64)
    case otherKey
    case mouse
}

/// Tells a lone, quick tap of the trigger key from the same key used as a
/// modifier: anything pressed or clicked while it is down, or a hold past
/// 0.3 s, makes it plain Option (Kazakh types its digits with ⌥).
struct LayoutFixTriggerState {
    static let soloTapMaxNanoseconds: UInt64 = 300_000_000
    static let doubleShiftWindowNanoseconds: UInt64 = 400_000_000

    let trigger: LayoutFixTrigger
    private var pressedKey: Int?
    private var pressedAt: UInt64 = 0
    private var alone = false
    /// The release of the first lone Shift tap, while a second may follow.
    private var firstShiftTap: UInt64?

    init(trigger: LayoutFixTrigger) {
        self.trigger = trigger
    }

    mutating func fires(_ event: LayoutFixTriggerEvent) -> Bool {
        switch event {
        case .modifierDown(let keyCode, let timestamp):
            if pressedKey != nil {
                alone = false
            } else if trigger.keyCodes.contains(keyCode) {
                pressedKey = keyCode
                pressedAt = timestamp
                alone = true
            } else {
                firstShiftTap = nil
            }
            return false
        case .modifierUp(let keyCode, let timestamp):
            guard let key = pressedKey, key == keyCode else { return false }
            let quick = alone && timestamp >= pressedAt
                && timestamp - pressedAt <= Self.soloTapMaxNanoseconds
            pressedKey = nil
            alone = false
            guard quick else {
                firstShiftTap = nil
                return false
            }
            guard trigger == .doubleShift else { return true }
            if let first = firstShiftTap, timestamp >= first,
               timestamp - first <= Self.doubleShiftWindowNanoseconds {
                firstShiftTap = nil
                return true
            }
            firstShiftTap = timestamp
            return false
        case .otherKey, .mouse:
            alone = false
            firstShiftTap = nil
            return false
        }
    }
}

/// Whether the field shows what the fix is about to delete.
enum LayoutFixGuard: Equatable {
    /// `matchCapitalized`: the field shows the word with its first letter
    /// capitalized by the system, so the retype is capitalized too.
    case match, matchCapitalized, mismatch, unknown
}

/// What one tap fixes.
enum LayoutFixTarget: Equatable {
    case selection, lastWord, nothing
}

/// The pure half of Layout Fix: key tables, the keystroke buffer, ranking of
/// the layouts a word could have been meant in, and the tap state machine.
/// Nothing here touches events, Accessibility or the text input server.
enum LayoutFixSupport {
    /// The keys of the main block. Higher codes are the keypad, function and
    /// navigation keys, which type the same thing in every layout.
    static let keyCodes = UInt16(0)...50

    // MARK: - Key tables

    /// What each chord of the layout types. Dead keys are read as their own
    /// character, and chords that type nothing or a control character are
    /// left out.
    static func table(from layoutData: Data, capsLock: Bool) -> [LayoutFixChord: String] {
        var table: [LayoutFixChord: String] = [:]
        layoutData.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            for keyCode in keyCodes {
                for shift in [false, true] {
                    for option in [false, true] {
                        let modifiers = (shift ? shiftKey : 0) | (option ? optionKey : 0) | (capsLock ? alphaLock : 0)
                        var deadKeyState: UInt32 = 0
                        var length = 0
                        var characters = [UniChar](repeating: 0, count: 8)
                        let status = UCKeyTranslate(layout,
                                                    keyCode,
                                                    UInt16(kUCKeyActionDown),
                                                    UInt32(modifiers >> 8),
                                                    UInt32(LMGetKbdType()),
                                                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                                    &deadKeyState,
                                                    characters.count,
                                                    &length,
                                                    &characters)
                        guard status == noErr, length > 0 else { continue }
                        let text = String(utf16CodeUnits: characters, count: length)
                        guard !text.unicodeScalars.contains(where: {
                            CharacterSet.controlCharacters.contains($0)
                        }) else { continue }
                        table[LayoutFixChord(keyCode: keyCode, shift: shift, option: option)] = text
                    }
                }
            }
        }
        return table
    }

    /// The chords that leave a dead-key state behind instead of a character.
    static func deadChords(from layoutData: Data) -> Set<LayoutFixChord> {
        var dead: Set<LayoutFixChord> = []
        layoutData.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            for keyCode in keyCodes {
                for shift in [false, true] {
                    for option in [false, true] {
                        let modifiers = (shift ? shiftKey : 0) | (option ? optionKey : 0)
                        var deadKeyState: UInt32 = 0
                        var length = 0
                        var characters = [UniChar](repeating: 0, count: 8)
                        let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown),
                                                    UInt32(modifiers >> 8), UInt32(LMGetKbdType()),
                                                    0, &deadKeyState, characters.count, &length, &characters)
                        if status == noErr, deadKeyState != 0 {
                            dead.insert(LayoutFixChord(keyCode: keyCode, shift: shift, option: option))
                        }
                    }
                }
            }
        }
        return dead
    }

    static func containsDeadKey(_ keys: [LayoutFixKey], layouts: [LayoutFixLayout]) -> Bool {
        keys.contains { key in
            layouts.first { $0.id == key.layoutID }?.deadChords.contains(key.chord) == true
        }
    }

    // MARK: - Rendering

    static func render(_ key: LayoutFixKey, in layout: LayoutFixLayout) -> String? {
        (key.capsLock ? layout.capsTable : layout.table)[key.chord]
    }

    /// The keys as the layout types them, or nil when any key types nothing
    /// there: a partial word would be worse than no candidate.
    static func render(_ keys: [LayoutFixKey], in layout: LayoutFixLayout) -> String? {
        var text = ""
        for key in keys {
            guard let typed = render(key, in: layout) else { return nil }
            text += typed
        }
        return text
    }

    /// The keys as they appeared when typed: each in its own layout.
    static func renderOriginal(_ keys: [LayoutFixKey], layouts: [LayoutFixLayout]) -> String? {
        var text = ""
        for key in keys {
            guard let layout = layouts.first(where: { $0.id == key.layoutID }),
                  let typed = render(key, in: layout) else { return nil }
            text += typed
        }
        return text
    }

    /// The keys that type `text` in the layout, plain keys before Shift and
    /// Shift before Option, so a selection maps back the way a person would
    /// have typed it. Nil when any character has no key there.
    static func keys(for text: String, in layout: LayoutFixLayout) -> [LayoutFixKey]? {
        var reverse: [String: LayoutFixChord] = [:]
        let preference: [(shift: Bool, option: Bool)] = [(false, false), (true, false), (false, true), (true, true)]
        for (shift, option) in preference {
            for keyCode in keyCodes {
                let chord = LayoutFixChord(keyCode: keyCode, shift: shift, option: option)
                if let typed = layout.table[chord], reverse[typed] == nil {
                    reverse[typed] = chord
                }
            }
        }
        var keys: [LayoutFixKey] = []
        for character in text {
            guard let chord = reverse[String(character)] else { return nil }
            keys.append(LayoutFixKey(keyCode: chord.keyCode, shift: chord.shift, option: chord.option,
                                     capsLock: false, layoutID: layout.id))
        }
        return keys
    }

    // MARK: - Buffer

    /// Typing keys of the main block are kept; Backspace takes one back;
    /// anything that moves the caret, sends the line or runs a shortcut makes
    /// the buffer meaningless. Return is a reset: in a chat it sends the
    /// message, so the word before it is no longer in the field.
    static func bufferAction(keyCode: Int, command: Bool, control: Bool) -> LayoutFixBufferAction {
        if command || control { return .reset }
        if keyCode == kVK_Delete { return .deleteLast }
        if keyCode == kVK_Tab || keyCode == kVK_Return { return .reset }
        return (0...Int(keyCodes.upperBound)).contains(keyCode) ? .append : .reset
    }

    /// The keys after the last space, and how many spaces follow them.
    static func lastWord(_ keys: [LayoutFixKey]) -> (word: [LayoutFixKey], trailingSpaces: Int)? {
        let space = UInt16(kVK_Space)
        var end = keys.count
        while end > 0, keys[end - 1].keyCode == space { end -= 1 }
        guard end > 0 else { return nil }
        var start = end
        while start > 0, keys[start - 1].keyCode != space { start -= 1 }
        return (Array(keys[start..<end]), keys.count - end)
    }

    // MARK: - Candidates

    /// No digit or punctuation sits between two letters. A wrong layout
    /// leaves exactly that behind: `с2лем` for `сәлем`, `,fkf` for `бала`.
    static func isClean(_ text: String) -> Bool {
        let characters = Array(text)
        guard let first = characters.firstIndex(where: \.isLetter),
              let last = characters.lastIndex(where: \.isLetter) else { return true }
        return characters[first...last].allSatisfy(\.isLetter)
    }

    /// A word the system spell checker knows in `language`. A language the
    /// checker does not have is never a confirmation: asked anyway, it calls
    /// every string correct (Kazakh does exactly that).
    static func isWord(_ text: String, language: String, available: Set<String>,
                       check: (String, String) -> Bool) -> Bool {
        guard !text.isEmpty, available.contains(language) else { return false }
        return check(text, language)
    }

    /// The other readings of the keys, best first: a dictionary word, then a
    /// clean one, then layout order. Readings equal to what is on screen are
    /// left out, and identical readings share one candidate.
    static func candidates(keys: [LayoutFixKey], originalText: String, layouts: [LayoutFixLayout],
                           isWord: (_ text: String, _ language: String) -> Bool) -> [LayoutFixCandidate] {
        var texts: [String] = []
        var layoutIDs: [String: [String]] = [:]
        var languages: [String: [String]] = [:]
        for layout in layouts {
            guard let text = render(keys, in: layout), text != originalText else { continue }
            if layoutIDs[text] == nil { texts.append(text) }
            layoutIDs[text, default: []].append(layout.id)
            languages[text, default: []].append(layout.language)
        }
        let ranked = texts.enumerated().sorted { lhs, rhs in
            func rank(_ entry: (offset: Int, element: String)) -> (Int, Int, Int) {
                let word = languages[entry.element, default: []].contains { isWord(entry.element, $0) }
                return (word ? 0 : 1, isClean(entry.element) ? 0 : 1, entry.offset)
            }
            return rank(lhs) < rank(rhs)
        }
        return ranked.map { LayoutFixCandidate(text: $0.element, layoutIDs: layoutIDs[$0.element, default: []]) }
    }

    /// A selection read back through the keys that typed it: each word is
    /// read in the layout that types it (the current one first), so a
    /// selection mixing `привет ghbdtn` still maps, and every layout gives a
    /// candidate. Whitespace and line breaks stay
    /// exactly as selected. Ranked like a single word, by the share of words
    /// the dictionary knows. Nil when no layout types the text or there is
    /// nothing but whitespace.
    static func selectionCandidates(text: String, layouts: [LayoutFixLayout], currentID: String?,
                                    isWord: (_ text: String, _ language: String) -> Bool)
        -> (original: LayoutFixCandidate, candidates: [LayoutFixCandidate])? {
        var runs: [(text: String, isWord: Bool)] = []
        for character in text {
            let word = !character.isWhitespace
            if let last = runs.last, last.isWord == word {
                runs[runs.count - 1].text.append(character)
            } else {
                runs.append((String(character), word))
            }
        }
        let words = runs.filter(\.isWord).map(\.text)
        guard !words.isEmpty else { return nil }
        let sources = words.compactMap { sourceLayout(for: $0, layouts: layouts, currentID: currentID) }
        guard sources.count == words.count else { return nil }
        let keysByWord = zip(words, sources).compactMap { keys(for: $0, in: $1) }
        guard keysByWord.count == words.count else { return nil }
        let source = sourceLayout(for: words.joined(), layouts: layouts, currentID: currentID)
            ?? layouts.first { $0.id == currentID } ?? sources[0]

        var texts: [String] = []
        var layoutIDs: [String: [String]] = [:]
        var wordShare: [String: Double] = [:]
        var clean: [String: Bool] = [:]
        for layout in layouts {
            let rendered = keysByWord.compactMap { render($0, in: layout) }
            guard rendered.count == words.count else { continue }
            var index = 0
            let joined = runs.map { run -> String in
                guard run.isWord else { return run.text }
                defer { index += 1 }
                return rendered[index]
            }.joined()
            guard joined != text else { continue }
            if layoutIDs[joined] == nil {
                texts.append(joined)
                wordShare[joined] = 0
                clean[joined] = rendered.allSatisfy(isClean)
            }
            layoutIDs[joined, default: []].append(layout.id)
            let known = Double(rendered.filter { isWord($0, layout.language) }.count) / Double(rendered.count)
            wordShare[joined] = max(wordShare[joined] ?? 0, known)
        }
        let ranked = texts.enumerated().sorted { lhs, rhs in
            func rank(_ entry: (offset: Int, element: String)) -> (Double, Int, Int) {
                (-(wordShare[entry.element] ?? 0), clean[entry.element] == true ? 0 : 1, entry.offset)
            }
            return rank(lhs) < rank(rhs)
        }
        return (LayoutFixCandidate(text: text, layoutIDs: [source.id]),
                ranked.map { LayoutFixCandidate(text: $0.element, layoutIDs: layoutIDs[$0.element, default: []]) })
    }

    /// Where typing goes on after the fix: of the layouts that type the
    /// candidate, the one used most recently, else the first. Someone who
    /// writes Kazakh stays on Kazakh after `бала`, so the next `сәлем` does
    /// not come out as `с2лем`.
    static func targetLayoutID(for candidate: LayoutFixCandidate, recency: [String]) -> String {
        recency.first { candidate.layoutIDs.contains($0) } ?? candidate.layoutIDs.first ?? ""
    }

    /// Where typing goes on when the candidate reads the same in several
    /// layouts: first a layout whose dictionary knows the word, then one with
    /// no dictionary to ask (Kazakh), and only then one whose dictionary
    /// rejects it. Within the best of those, the most recently used.
    /// `рахмет` goes to Kazakh because Russian does not know it; `привет`
    /// goes to Russian.
    static func targetLayoutID(for candidate: LayoutFixCandidate, recency: [String], layouts: [LayoutFixLayout],
                               isWord: (_ text: String, _ language: String) -> Bool,
                               hasDictionary: (_ language: String) -> Bool) -> String {
        func tier(_ id: String) -> Int {
            guard let language = layouts.first(where: { $0.id == id })?.language else { return 2 }
            if isWord(candidate.text, language) { return 0 }
            return hasDictionary(language) ? 2 : 1
        }
        guard let best = candidate.layoutIDs.map(tier).min() else { return "" }
        let preferred = candidate.layoutIDs.filter { tier($0) == best }
        return targetLayoutID(for: LayoutFixCandidate(text: candidate.text, layoutIDs: preferred), recency: recency)
    }

    // MARK: - Safety

    /// Terminals keep a selection in their scrollback while typing goes to
    /// the prompt, so typing over a selection there would land elsewhere.
    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "org.alacritty", "com.mitchellh.ghostty",
    ]

    /// The backspaces only go out when the field ends with the word they are
    /// meant for. A field that does not answer cannot be checked.
    static func guardDecision(expected: String, textBeforeCaret: String?) -> LayoutFixGuard {
        guard let textBeforeCaret else { return .unknown }
        if textBeforeCaret.hasSuffix(expected) { return .match }
        // "Capitalize words automatically" turns the first word of a
        // sentence into `Ghbdtn` once a space follows it.
        if let capitalized = capitalizingFirst(expected), textBeforeCaret.hasSuffix(capitalized) {
            return .matchCapitalized
        }
        return .mismatch
    }

    /// The text with its first letter upper-cased, or nil when it does not
    /// start with a lowercase letter or the capital would change its length.
    static func capitalizingFirst(_ text: String) -> String? {
        guard let first = text.first, first.isLowercase else { return nil }
        let upper = String(first).uppercased()
        guard (upper as NSString).length == (String(first) as NSString).length else { return nil }
        return upper + text.dropFirst()
    }

    /// An inline completion: the field selected what it suggests after the
    /// typed word, up to the end of the text (an address bar does this).
    /// The word is what was meant; the delete count clears the suggestion.
    static func isCompletion(selection: NSRange, textLength: Int, expected: String,
                             textBefore: (NSRange) -> String?) -> Bool {
        let length = (expected as NSString).length
        guard selection.length > 0, length > 0, selection.location >= length,
              NSMaxRange(selection) == textLength,
              let before = textBefore(NSRange(location: selection.location - length, length: length))
        else { return false }
        return before.compare(expected, options: .caseInsensitive) == .orderedSame
    }

    /// Whether the field shows `expected` right before where the backspaces
    /// go. A caret is compared with the text before it; an inline completion
    /// after the word is fine; any other selection would be deleted by the
    /// first backspace. A field that does not answer cannot be checked.
    static func fieldGuard(selection: NSRange?, textLength: Int, expected: String,
                           textBefore: (NSRange) -> String?) -> LayoutFixGuard {
        guard let selection else { return .unknown }
        if selection.length > 0 {
            return isCompletion(selection: selection, textLength: textLength,
                                expected: expected, textBefore: textBefore) ? .match : .mismatch
        }
        let length = (expected as NSString).length
        // Keys were typed since the caret last moved, so it cannot be at the
        // very start: a field that says so has not caught up (a freshly
        // opened Word document does this). Backspaces there delete nothing.
        if selection.location == 0, length > 0 { return .unknown }
        guard selection.location >= length else { return .mismatch }
        return guardDecision(expected: expected,
                             textBeforeCaret: textBefore(NSRange(location: selection.location - length,
                                                                 length: length)))
    }

    /// Our own retype is skipped; anything else Vorssaint posts (a snippet
    /// expansion, a pasted clip) changes the field behind the buffer's back.
    static func ownEvent(userData: Int64, isPosted: Bool) -> LayoutFixOwnEvent {
        guard isPosted else { return .typing }
        return userData == OwnKeyEvent.layoutFixMarker ? .retype : .otherFeature
    }

    /// A selection is fixed only where typing replaces it: an ordinary text
    /// field. A web page selection (text markers) and a terminal selection
    /// fall back to the last typed word.
    static func target(selectionLength: Int, selectionFromTextMarkers: Bool,
                       bundleID: String?, hasWord: Bool,
                       selectionIsCompletion: Bool = false) -> LayoutFixTarget {
        let inTerminal = bundleID.map(terminalBundleIDs.contains) ?? false
        if selectionLength > 0, !selectionFromTextMarkers, !inTerminal, !selectionIsCompletion {
            return .selection
        }
        return hasWord ? .lastWord : .nothing
    }

    /// The layout a selection was most likely typed in: the current one when
    /// it types every character, else the first in order that does.
    static func sourceLayout(for text: String, layouts: [LayoutFixLayout],
                             currentID: String?) -> LayoutFixLayout? {
        let covering = layouts.filter { keys(for: text, in: $0) != nil }
        return covering.first { $0.id == currentID } ?? covering.first
    }
}
