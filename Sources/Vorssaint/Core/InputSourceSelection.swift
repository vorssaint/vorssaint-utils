// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

/// Selecting an enabled keyboard input source through the system's Text
/// Input Sources services. Shared by the paths that switch a source while
/// their own surface is up: the Super key tap cycles to the next source, and
/// the Command Bar borrows a Latin layout for the length of a presentation.
enum InputSourceSelection {
    /// What one enabled source looks like once read out of TIS. Plain values,
    /// so decisions over them stay pure and testable.
    struct Snapshot: Equatable {
        let id: String
        /// A layout rather than an input method: a layout types what is
        /// printed on the keys, a method types whatever it is set to produce.
        let isLayout: Bool
        let isASCIICapable: Bool
    }

    // MARK: - Decisions (pure)

    /// The source to borrow when plain Latin typing is wanted, or nil when
    /// there is nothing to switch to: either the current source is already an
    /// ASCII layout, or none is enabled (a Mac set to Cyrillic and Greek
    /// alone has no Latin layout to borrow). First enabled wins, because that
    /// is the order the Input menu shows.
    static func asciiLayoutID(currentID: String?, snapshots: [Snapshot]) -> String? {
        if let currentID,
           let current = snapshots.first(where: { $0.id == currentID }),
           current.isASCIICapable, current.isLayout {
            return nil
        }
        return snapshots.first { $0.isASCIICapable && $0.isLayout }?.id
    }

    // MARK: - TIS access

    static func currentSourceID() -> String? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return inputSourceString(current, property: kTISPropertyInputSourceID)
    }

    /// Selects an enabled source by its id, answering whether the system
    /// took the request. The two mistakes are not symmetric: recording
    /// against a switch that never lands restores a source the caller never
    /// left — a no-op — while failing to record one that lands strands the
    /// typist on the borrowed layout, so the caller records on acceptance.
    static func select(sourceID: String) -> Bool {
        guard let source = selectableInputSources().first(where: {
            inputSourceString($0, property: kTISPropertyInputSourceID) == sourceID
        }) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    // MARK: - Shared TIS plumbing

    /// The enabled, selectable keyboard sources, in the order the system
    /// keeps them. TIS talks to the text-input server from the main thread.
    static func selectableInputSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false) else { return [] }
        let values = list.takeRetainedValue() as NSArray
        return (values as! [TISInputSource]).filter {
            inputSourceString($0, property: kTISPropertyInputSourceCategory)
                == kTISCategoryKeyboardInputSource as String
                && inputSourceBool($0, property: kTISPropertyInputSourceIsSelectCapable)
        }
    }

    static func snapshots() -> [Snapshot] {
        selectableInputSources().map {
            Snapshot(id: inputSourceString($0, property: kTISPropertyInputSourceID) ?? "",
                     isLayout: inputSourceString($0, property: kTISPropertyInputSourceType)
                         == kTISTypeKeyboardLayout as String,
                     isASCIICapable: inputSourceBool($0, property: kTISPropertyInputSourceIsASCIICapable))
        }
    }

    // MARK: - Command bar keyboard recovery

    private static var commandBarMaps: [[String: String]]?
    private static var commandBarMapsObserver: NSObjectProtocol?

    /// Read enabled layouts once, then invalidate when the Input Sources list
    /// changes. Input methods without physical key tables are left alone.
    /// No input source is selected or changed to perform this lookup.
    static func commandBarKeyboardMaps() -> [[String: String]] {
        guard Thread.isMainThread else { return [] }
        if let commandBarMaps { return commandBarMaps }
        if commandBarMapsObserver == nil {
            commandBarMapsObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
                object: nil, queue: .main
            ) { _ in commandBarMaps = nil }
        }
        let allLayouts = TISCreateInputSourceList(
            [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary, true)?
            .takeRetainedValue() as? [TISInputSource] ?? []
        guard let us = allLayouts.first(where: {
            inputSourceString($0, property: kTISPropertyInputSourceID) == "com.apple.keylayout.US"
        }), let target = keyboardLayoutData(us) else { return [] }
        let maps = selectableInputSources().compactMap { source -> [String: String]? in
            guard let data = keyboardLayoutData(source) else { return nil }
            let map = keyboardMap(from: data, to: target)
            return map.isEmpty ? nil : map
        }
        commandBarMaps = maps
        return maps
    }

    static func keyboardLayoutData(_ source: TISInputSource) -> Data? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }

    /// Both sides come from macOS, including custom layouts. Lowercase before
    /// folding accents so separate keys such as Russian й and и stay distinct.
    static func keyboardMap(from source: Data, to target: Data) -> [String: String] {
        var map: [String: String] = [:]
        for shifted in [false, true] {
            for code in UInt16(0)...50 {
                guard let typed = keyboardCharacter(code, shifted: shifted, data: source),
                      let intended = keyboardCharacter(code, shifted: shifted, data: target),
                      typed != intended, !typed.allSatisfy(\.isNumber),
                      typed.contains(where: \.isLetter) || intended.contains(where: \.isLetter),
                      map[typed] == nil else { continue }
                map[typed] = intended
            }
        }
        return map
    }

    private static func keyboardCharacter(_ code: UInt16, shifted: Bool, data: Data) -> String? {
        var dead: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 8)
        var count = 0
        let status = data.withUnsafeBytes { bytes -> OSStatus in
            guard let keyboard = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(keyboard, code, UInt16(kUCKeyActionDisplay),
                                  shifted ? UInt32((shiftKey >> 8) & 0xff) : 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                  &dead, characters.count, &count, &characters)
        }
        guard status == noErr, count > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: count).lowercased()
        guard !text.isEmpty, !text.contains(where: \.isWhitespace),
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return text
    }

    static func inputSourceString(_ source: TISInputSource,
                                  property: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    static func inputSourceBool(_ source: TISInputSource,
                                property: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
}
