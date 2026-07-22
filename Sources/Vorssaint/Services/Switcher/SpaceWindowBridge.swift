// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Window-server queries and requests around Spaces, resolved at runtime so a
/// macOS that drops a symbol degrades to the previous behavior (windows on
/// other Spaces stay invisible and unreachable) instead of failing to launch.
///
/// Accessibility cannot describe a window parked on a Space that is not
/// visible: the app's window list omits it and direct element access is
/// refused (measured on macOS 26 and 27). The window server is the only
/// witness that such a window exists, and the only reliable tell between a
/// real parked window and a stale leftover surface: real windows always belong
/// to at least one Space, leftovers belong to none.
enum SpaceWindowBridge {
    private typealias ConnectionID = UInt32

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name)
    }

    private static let connection: ConnectionID = {
        typealias Function = @convention(c) () -> ConnectionID
        guard let symbol = symbol("CGSMainConnectionID") else { return 0 }
        return unsafeBitCast(symbol, to: Function.self)()
    }()

    // MARK: - Space membership

    private typealias CopySpacesFunction =
        @convention(c) (ConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let copySpacesForWindows: CopySpacesFunction? = {
        guard let symbol = symbol("CGSCopySpacesForWindows") else { return nil }
        return unsafeBitCast(symbol, to: CopySpacesFunction.self)
    }()

    /// Every Space (user desktops and fullscreen Spaces alike) containing the
    /// window. Empty for leftover surfaces, and when the query is unavailable.
    static func spaces(of windowID: CGWindowID) -> [UInt64] {
        guard connection != 0, let copySpacesForWindows else { return [] }
        let mask: Int32 = 0x7
        guard let array = copySpacesForWindows(connection, mask,
                                               [NSNumber(value: windowID)] as CFArray)?
            .takeRetainedValue() as? [NSNumber]
        else { return [] }
        return array.map(\.uint64Value)
    }

    // MARK: - Display topology

    private typealias CopyDisplaySpacesFunction = @convention(c) (ConnectionID) -> Unmanaged<CFArray>?
    private static let copyManagedDisplaySpaces: CopyDisplaySpacesFunction? = {
        guard let symbol = symbol("CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(symbol, to: CopyDisplaySpacesFunction.self)
    }()

    struct Topology {
        /// Space ids in left-to-right order, one row per display.
        let orderedSpacesPerDisplay: [[UInt64]]
        /// The Space currently showing on each display.
        let visibleSpaces: Set<UInt64>
    }

    static func topology() -> Topology? {
        guard connection != 0, let copyManagedDisplaySpaces,
              let displays = copyManagedDisplaySpaces(connection)?
                .takeRetainedValue() as? [[String: Any]],
              !displays.isEmpty
        else { return nil }

        var rows: [[UInt64]] = []
        var visible: Set<UInt64> = []
        for display in displays {
            let row = (display["Spaces"] as? [[String: Any]])?
                .compactMap { ($0["id64"] as? NSNumber)?.uint64Value } ?? []
            if !row.isEmpty { rows.append(row) }
            if let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber {
                visible.insert(current.uint64Value)
            }
        }
        guard !rows.isEmpty, !visible.isEmpty else { return nil }
        return Topology(orderedSpacesPerDisplay: rows, visibleSpaces: visible)
    }

    /// Whether the window sits on at least one Space and none of them is
    /// visible. False when the Space queries are unavailable, so every caller
    /// falls back to the pre-existing behavior.
    static func isParkedOnHiddenSpace(_ windowID: CGWindowID, visibleSpaces: Set<UInt64>? = nil) -> Bool {
        guard let visible = visibleSpaces ?? topology()?.visibleSpaces else { return false }
        return SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: spaces(of: windowID),
                                                     visibleSpaces: visible)
    }

    // MARK: - Fronting a specific window

    private typealias SetFrontFunction =
        @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private static let setFrontProcess: SetFrontFunction? = {
        guard let symbol = symbol("_SLPSSetFrontProcessWithOptions") else { return nil }
        return unsafeBitCast(symbol, to: SetFrontFunction.self)
    }()

    private typealias PostEventRecordFunction =
        @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private static let postEventRecord: PostEventRecordFunction? = {
        guard let symbol = symbol("SLPSPostEventRecordTo") else { return nil }
        return unsafeBitCast(symbol, to: PostEventRecordFunction.self)
    }()

    private typealias ProcessForPIDFunction =
        @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private static let processForPID: ProcessForPIDFunction? = {
        guard let symbol = symbol("GetProcessForPID") else { return nil }
        return unsafeBitCast(symbol, to: ProcessForPIDFunction.self)
    }()

    /// Asks the window server to bring the process forward with this exact
    /// window as the one that comes up front, marked as user-initiated. Older
    /// macOS also travels to the window's Space; current macOS ignores the
    /// Space part, which is why SpaceHop verifies the outcome and escalates.
    /// The follow-up record pair makes the window key without clicking any of
    /// its content (the synthetic click points just outside the frame).
    static func frontWindow(_ windowID: CGWindowID, ownerPID: pid_t) {
        guard let setFrontProcess, let processForPID else { return }
        var psn = ProcessSerialNumber()
        guard processForPID(ownerPID, &psn) == noErr else { return }
        let userGenerated: UInt32 = 0x200
        guard setFrontProcess(&psn, windowID, userGenerated) == .success else { return }
        guard let postEventRecord else { return }
        var targetID = windowID
        var clickPoint = CGPoint(x: -1, y: -1)
        var record = [UInt8](repeating: 0, count: 0x100)
        record[0x04] = 0xf8 // declared record length
        record[0x3a] = 0x10
        withUnsafeBytes(of: &targetID) { record.replaceSubrange(0x3c..<0x3c + $0.count, with: $0) }
        withUnsafeBytes(of: &clickPoint) { record.replaceSubrange(0x20..<0x20 + $0.count, with: $0) }
        record[0x08] = 0x01 // left mouse down…
        _ = postEventRecord(&psn, &record)
        record[0x08] = 0x02 // …then up: the pair makes the window key
        _ = postEventRecord(&psn, &record)
    }

    // MARK: - The user's "move a space" shortcut

    private typealias HotKeyValueFunction =
        @convention(c) (Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> CGError
    private static let symbolicHotKeyValue: HotKeyValueFunction? = {
        guard let symbol = symbol("CGSGetSymbolicHotKeyValue") else { return nil }
        return unsafeBitCast(symbol, to: HotKeyValueFunction.self)
    }()

    private typealias HotKeyEnabledFunction = @convention(c) (Int32) -> Bool
    private static let symbolicHotKeyEnabled: HotKeyEnabledFunction? = {
        guard let symbol = symbol("CGSIsSymbolicHotKeyEnabled") else { return nil }
        return unsafeBitCast(symbol, to: HotKeyEnabledFunction.self)
    }()

    enum SpaceDirection {
        case left
        case right

        /// System symbolic hotkey ids for "Move left/right a space".
        fileprivate var hotKeyID: Int32 { self == .left ? 79 : 81 }
    }

    struct SpaceShortcut {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    /// The key combination the system itself has registered for moving one
    /// Space over, honoring user remaps. Nil when the shortcut is disabled or
    /// unreadable, in which case no synthetic travel is attempted.
    static func spaceShortcut(_ direction: SpaceDirection) -> SpaceShortcut? {
        guard let symbolicHotKeyValue, let symbolicHotKeyEnabled,
              symbolicHotKeyEnabled(direction.hotKeyID) else { return nil }
        var options: UInt32 = 0
        var keyCode: UInt32 = 0
        var modifiers: UInt32 = 0
        guard symbolicHotKeyValue(direction.hotKeyID, &options, &keyCode, &modifiers) == .success,
              keyCode != 0
        else { return nil }
        return SpaceShortcut(keyCode: CGKeyCode(keyCode),
                             flags: SpaceHopSupport.eventFlags(fromCarbonModifiers: modifiers))
    }

    /// Replays one press of a Spaces shortcut. The modifiers must match the
    /// registered combination exactly or the system ignores the press.
    static func pressSpaceShortcut(_ shortcut: SpaceShortcut) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: false)
        else { return }
        down.flags = shortcut.flags
        up.flags = shortcut.flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
