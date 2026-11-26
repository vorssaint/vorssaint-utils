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

/// The keyboard layout borrowed for the length of a presentation, and the
/// channel that reports the app's own switches to whichever surface shows a
/// layout notice. It lives here rather than in Command Bar because giving the
/// source back is not the bar's business: quitting must restore a layout even
/// with the bar, or the island, uninstalled and therefore never built.
enum InputSourceBorrow {
    /// The source to return to when the presentation that borrowed a Latin
    /// layout ends, or nil when nothing is borrowed. Written only once TIS
    /// accepts the switch, so a refused borrow creates no obligation.
    private(set) static var restoreTo: String?

    /// Whoever shows a layout notice, told about a switch made on the
    /// person's behalf so it stays quiet about it. No island subscribed
    /// simply means nobody is listening.
    private static var switchObservers: [UUID: (String) -> Void] = [:]

    /// Joins the channel, answering a token that leaves it again.
    @discardableResult
    static func observeSwitches(_ observer: @escaping (String) -> Void) -> UUID {
        let token = UUID()
        switchObservers[token] = observer
        return token
    }

    static func stopObservingSwitches(_ token: UUID) {
        switchObservers.removeValue(forKey: token)
    }

    /// Borrows the first enabled ASCII layout, remembering the source to
    /// return to. The record belongs to acceptance, not to the request: a
    /// switch that never landed must not restore a source nobody left.
    static func borrow(restoreTo currentID: String?) {
        guard let currentID,
              let target = InputSourceSelection.asciiLayoutID(
                currentID: currentID,
                snapshots: InputSourceSelection.snapshots()),
              InputSourceSelection.select(sourceID: target)
        else { return }
        restoreTo = currentID
        reportSwitch(target)
    }

    /// Gives the borrowed layout back, telling the channel it was the app's
    /// own doing. Clears the obligation only when TIS accepts, so a refused
    /// restoration stays available to a later close or to quit.
    static func restoreAll() {
        guard let sourceID = restoreTo,
              InputSourceSelection.select(sourceID: sourceID)
        else { return }
        restoreTo = nil
        reportSwitch(sourceID)
    }

    private static func reportSwitch(_ sourceID: String) {
        for observer in switchObservers.values { observer(sourceID) }
    }
}
