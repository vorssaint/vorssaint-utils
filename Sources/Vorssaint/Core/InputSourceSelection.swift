// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

/// Selecting an enabled keyboard input source through the system's Text
/// Input Sources services. Shared by the paths that switch a source while
/// their own surface is up: the Super key and Fn key taps cycle to the next
/// source, and the Command Bar borrows a Latin layout for the length of a
/// presentation.
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

    /// The source after the current one in the enabled order, wrapping from
    /// the last back to the first, or nil when there is nothing to cycle to.
    /// A current source the list does not hold (one just disabled, or a
    /// palette) starts the cycle again at the first.
    static func nextSourceID(currentID: String?, enabledIDs: [String]) -> String? {
        guard enabledIDs.count > 1 else { return nil }
        guard let currentID, let index = enabledIDs.firstIndex(of: currentID) else {
            return enabledIDs.first
        }
        return enabledIDs[(index + 1) % enabledIDs.count]
    }

    /// The short code the island's layout notice shows: the source's first
    /// language without its script or region, so "zh-Hans" reads as ZH. Empty
    /// when a source claims no language, which leaves the notice its mark alone.
    static func shortCode(languages: [String]) -> String {
        guard let base = languages.first?.split(separator: "-").first else { return "" }
        return base.uppercased()
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

    /// Cycles to the next enabled source, answering whether the system took
    /// the request. The list and the current source are read afresh on every
    /// call, so a source added or removed since the last one counts at once.
    ///
    /// A tap calls this before it lets its key event go: the next keystroke
    /// is already in flight behind it, and hopping to main asynchronously (or
    /// waiting on Accessibility) left that character in the old source. TIS
    /// talks to the text-input server from the main thread, so the work runs
    /// there synchronously. Selecting the source directly lets an input
    /// method commit or cancel its composition on its own, the same way the
    /// Input menu does, with no wait on every tap.
    @discardableResult
    static func selectNext() -> Bool {
        let apply = { () -> Bool in
            let sources = selectableInputSources().compactMap { source in
                inputSourceString(source, property: kTISPropertyInputSourceID).map { (id: $0, source: source) }
            }
            guard let nextID = nextSourceID(currentID: currentSourceID(), enabledIDs: sources.map(\.id)),
                  let next = sources.first(where: { $0.id == nextID })
            else { return false }
            return TISSelectInputSource(next.source) == noErr
        }
        if Thread.isMainThread {
            return apply()
        }
        return DispatchQueue.main.sync(execute: apply)
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

    /// What the island's notice says about the source now typing: its id, so
    /// a caller can tell one change from the next, its short code and the
    /// name the system itself shows in the Input menu.
    struct Reading: Equatable {
        let id: String
        let code: String
        let name: String
    }

    static func currentReading() -> Reading? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let id = inputSourceString(source, property: kTISPropertyInputSourceID)
        else { return nil }
        return Reading(id: id,
                       code: shortCode(languages: languages(of: source)),
                       name: inputSourceString(source, property: kTISPropertyLocalizedName) ?? "")
    }

    /// The languages a source types, in the order TIS keeps them.
    static func languages(of source: TISInputSource) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
              let list = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]
        else { return [] }
        return list
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
