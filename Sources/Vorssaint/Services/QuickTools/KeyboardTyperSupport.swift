// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// One physical key press, with the modifiers held around it.
struct KeyboardTyperKey: Equatable {
    let code: CGKeyCode
    var shift = false
    var option = false
}

/// How one character goes out: as the key the current layout types it with,
/// as that key under AltGr when it sits on the Option layer, or, when no key
/// types it, as a key event carrying the character itself.
enum KeyboardTyperStroke: Equatable {
    case key(KeyboardTyperKey)
    case altGraph(code: CGKeyCode, character: [UniChar])
    case unicode([UniChar])
}

/// How the destination reads what the typer sends. A web console or a VNC
/// viewer passes on the character the Mac's own layout makes of each key, so
/// the Mac types with the destination's layout for the run. A remote desktop
/// app passes on the key's position, so the Mac keeps its layout and each
/// character goes out on the key the destination has it on.
enum KeyboardTyperMethod: String, CaseIterable {
    case characters, keyPositions

    static func sanitized(_ raw: String?) -> Self { raw.flatMap(Self.init(rawValue:)) ?? .characters }

    /// Marks the method in the menu next to Send and on its label.
    var symbolName: String {
        switch self {
        case .characters: return "character.cursor.ibeam"
        case .keyPositions: return "keyboard"
        }
    }
}

/// A keyboard layout the remote side may be set to, as macOS ships it.
struct KeyboardTyperLayout: Identifiable, Equatable {
    let id: String
    let name: String
}

/// A text kept for typing again, named or not.
struct KeyboardTyperSnippet: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var text: String
}

enum KeyboardTyperSupport {
    static let delayRange = 0...2000
    static let defaultDelay = 20
    /// Time for the target window to take the keyboard back after the pad hides.
    static let startDelay: TimeInterval = 0.4

    static func sanitizedDelay(_ value: Int) -> Int {
        min(max(value, delayRange.lowerBound), delayRange.upperBound)
    }

    /// Seconds the delayed Send waits, for apps that lose focus when the
    /// typer goes away and need a click back into their window.
    static let countdownRange = 1...10
    static let defaultCountdown = 3

    static func sanitizedCountdown(_ value: Int) -> Int {
        min(max(value, countdownRange.lowerBound), countdownRange.upperBound)
    }

    /// What the snippet list shows: the name when there is one, otherwise
    /// the text's first line that is not blank.
    static func title(of snippet: KeyboardTyperSnippet) -> String {
        let name = snippet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return snippet.text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }

    /// The app behind this app's own windows: the owner of the frontmost
    /// normal window that is not ours. With this app in front (its menu bar
    /// panel or Settings opened the typer), that is the window the person
    /// was working in, which the frontmost app no longer says.
    static func appBehind(windows: [[String: Any]], ownPID: pid_t) -> pid_t? {
        WindowServerSupport.frontWindowOwner(in: windows.filter {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != ownPID
        })
    }

    /// The characters the layout has no key for, once each, in text order.
    /// A web console drops these, so sending characters refuses to go out
    /// with any rather than type a password with a character missing.
    static func missingCharacters(in strokes: [KeyboardTyperStroke]) -> String {
        var seen = Set<String>()
        return strokes.compactMap { stroke -> String? in
            guard case .unicode(let units) = stroke else { return nil }
            let character = String(utf16CodeUnits: units, count: units.count)
            return seen.insert(character).inserted ? character : nil
        }.joined(separator: " ")
    }

    // MARK: - Destination layouts

    /// Favorites persist as comma separated input source ids, in the order starred.
    static func favorites(from raw: String?) -> [String] {
        var seen = Set<String>()
        return (raw ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func toggling(_ id: String, in favorites: [String]) -> [String] {
        favorites.contains(id) ? favorites.filter { $0 != id } : favorites + [id]
    }

    /// The layout to type with, or nil for the system's own. A choice that is
    /// no longer a favorite is not offered next to Send, so it no longer applies.
    static func destinationLayoutID(selected: String?, favorites: [String]) -> String? {
        guard let selected, !selected.isEmpty, favorites.contains(selected) else { return nil }
        return selected
    }

    /// Every keyboard layout macOS ships, enabled or not, by its localized
    /// name. Input methods are left out: they type what they are set to
    /// produce, not what is printed on the keys.
    /// A few Chinese stroke layouts come back once per input mode under one
    /// id; the first name is kept.
    static func installedLayouts() -> [KeyboardTyperLayout] {
        var seen = Set<String>()
        return layoutSources().compactMap { source in
            guard let id = InputSourceSelection.inputSourceString(source, property: kTISPropertyInputSourceID),
                  TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil,
                  seen.insert(id).inserted
            else { return nil }
            let name = InputSourceSelection.inputSourceString(source, property: kTISPropertyLocalizedName) ?? id
            return KeyboardTyperLayout(id: id, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func layoutData(id: String) -> Data? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first,
              let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        return Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue() as Data
    }

    private static func layoutSources() -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
        return TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    /// Every character the layout types with one key press, under no
    /// modifier, Shift, Option or both. The plainest press wins, so a digit
    /// comes from the top row rather than a Shift combination. Keypad keys are
    /// left out: a remote host reads them through its own Num Lock state.
    /// Dead keys are left out too: pressing one starts a composition instead
    /// of typing its accent.
    static func keyMap(layoutData: Data, keyboardType: UInt32) -> [Character: KeyboardTyperKey] {
        let keypad = UInt16(kVK_ANSI_KeypadDecimal)...UInt16(kVK_ANSI_Keypad9)
        let shift = UInt32((shiftKey >> 8) & 0xFF)
        let option = UInt32((optionKey >> 8) & 0xFF)
        var map: [Character: KeyboardTyperKey] = [:]
        layoutData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            for (usesShift, usesOption) in [(false, false), (true, false), (false, true), (true, true)] {
                let modifierState = (usesShift ? shift : 0) | (usesOption ? option : 0)
                for code in UInt16(0)..<128 where !keypad.contains(code) {
                    var deadKeyState: UInt32 = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    var length = 0
                    let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), modifierState,
                                                keyboardType, 0, &deadKeyState,
                                                chars.count, &length, &chars)
                    guard status == noErr, deadKeyState == 0, length > 0 else { continue }
                    let text = String(utf16CodeUnits: chars, count: length)
                    guard text.count == 1, let character = text.first,
                          !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                          map[character] == nil
                    else { continue }
                    map[character] = KeyboardTyperKey(code: CGKeyCode(code), shift: usesShift, option: usesOption)
                }
            }
        }
        return map
    }

    /// Line breaks of any kind press Return and tabs press Tab, so the remote
    /// side sees the keys a person would press there. Sending characters, an
    /// Option-layer character keeps its key but drops Shift: Windows and Linux
    /// type these with AltGr alone, and a host that maps characters to its own
    /// keys (a web console) accepts one only with exactly its own modifiers
    /// held. Sending key positions, it is the Mac's own Option combination.
    static func strokes(for text: String, map: [Character: KeyboardTyperKey],
                        method: KeyboardTyperMethod = .characters) -> [KeyboardTyperStroke] {
        text.map { character in
            switch character {
            case "\n", "\r", "\r\n": return .key(KeyboardTyperKey(code: CGKeyCode(kVK_Return)))
            case "\t": return .key(KeyboardTyperKey(code: CGKeyCode(kVK_Tab)))
            default:
                if let key = map[character] {
                    return key.option && method == .characters ? .altGraph(code: key.code, character: Array(String(character).utf16)) : .key(key)
                }
                // shortcut: one event per character; a grapheme over ~20 UTF-16 units may be cut by some apps.
                return .unicode(Array(String(character).utf16))
            }
        }
    }
}
