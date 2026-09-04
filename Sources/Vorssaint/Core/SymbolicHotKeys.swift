// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

/// One row of the WindowServer's symbolic hotkey table as it stands right now.
struct LiveSystemShortcut: Equatable {
    let id: Int32
    let shortcut: GlobalShortcut
    let enabled: Bool
}

/// The WindowServer's own shortcut table, reached through the same private
/// SkyLight calls the App Switcher's take-over uses. Every symbol is resolved
/// at runtime and every reader tolerates its absence, so a macOS that drops
/// them leaves the app on its plist fallback rather than crashing.
enum SymbolicHotKeys {
    typealias SetEnabledFunction = @convention(c) (Int32, Bool) -> CGError
    typealias IsEnabledFunction = @convention(c) (Int32) -> Bool
    typealias GetValueFunction =
        @convention(c) (Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> CGError

    /// Writes go through `SystemShortcutTakeover.apply`, which owns the
    /// write-ahead marker and the restore-after-crash bookkeeping. Nothing
    /// else should call this directly.
    static let setEnabled: SetEnabledFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetSymbolicHotKeyEnabled") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetEnabledFunction.self)
    }()
    static let isEnabled: IsEnabledFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSIsSymbolicHotKeyEnabled") else {
            return nil
        }
        return unsafeBitCast(symbol, to: IsEnabledFunction.self)
    }()
    static let getValue: GetValueFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSGetSymbolicHotKeyValue") else {
            return nil
        }
        return unsafeBitCast(symbol, to: GetValueFunction.self)
    }()

    /// macOS 26 populates ids up to 255; scanning the headroom costs a few
    /// milliseconds of WindowServer round trips per full read, which the
    /// recorder pays on a save, and spares a hardcoded ceiling.
    static let scanRange: Range<Int32> = 0..<512

    /// The key code an entry carries when no key is assigned to it.
    static let unassignedKeyCode: UInt32 = 0xFFFF

    /// Every populated row, read fresh: System Settings can change the table
    /// while a shortcut field is open. `nil` when the private calls are gone.
    /// A caller that already knows its ids should use `entries(for:)` instead
    /// of paying for the whole scan.
    static func liveEntries() -> [LiveSystemShortcut]? {
        guard let getValue, let isEnabled else { return nil }
        return scanRange.compactMap { entry(id: $0, getValue: getValue, isEnabled: isEnabled) }
    }

    /// The rows for a known set of ids, in the same shape as `liveEntries()`,
    /// at one round trip per id instead of one per possible id.
    static func entries(for ids: Set<Int32>) -> [LiveSystemShortcut]? {
        guard let getValue, let isEnabled else { return nil }
        return ids.sorted().compactMap { entry(id: $0, getValue: getValue, isEnabled: isEnabled) }
    }

    private static func entry(id: Int32, getValue: GetValueFunction,
                              isEnabled: IsEnabledFunction) -> LiveSystemShortcut? {
        var character: UInt32 = 0
        var keyCode: UInt32 = 0
        var modifiers: UInt32 = 0
        guard getValue(id, &character, &keyCode, &modifiers) == .success,
              keyCode != unassignedKeyCode else { return nil }
        return LiveSystemShortcut(
            id: id,
            shortcut: GlobalShortcut(
                keyCode: Int64(keyCode),
                modifiers: GlobalShortcutModifiers(
                    cgFlags: SpaceHopSupport.eventFlags(fromCarbonModifiers: modifiers))),
            enabled: isEnabled(id))
    }
}
