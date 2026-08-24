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
/// real parked window and a stale leftover surface: real windows normally
/// belong to at least one Space, leftovers belong to none. Some auxiliary
/// surfaces share a Space with a real window but explicitly opt out of window
/// cycling, so their window-server tag is checked separately.
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

    private typealias GetWindowTagsFunction =
        @convention(c) (ConnectionID, CGWindowID, UnsafeMutablePointer<UInt32>, Int) -> CGError
    private static let getWindowTags: GetWindowTagsFunction? = {
        guard let symbol = symbol("CGSGetWindowTags") else { return nil }
        return unsafeBitCast(symbol, to: GetWindowTagsFunction.self)
    }()

    // MARK: - Space membership

    private typealias CopySpacesFunction =
        @convention(c) (ConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let copySpacesForWindows: CopySpacesFunction? = {
        guard let symbol = symbol("CGSCopySpacesForWindows") else { return nil }
        return unsafeBitCast(symbol, to: CopySpacesFunction.self)
    }()

    /// Whether `spaces(of:)` can actually answer in this session. Callers use
    /// it to tell "this surface belongs to no Space" (the leftover signature)
    /// apart from "the Space queries are unavailable here", so a macOS that
    /// drops the private symbol keeps the pre-existing behavior instead of
    /// misreading every window as a leftover (issue #807).
    static var canResolveSpaces: Bool {
        connection != 0 && copySpacesForWindows != nil
    }

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
        struct DisplayInfo {
            let displayID: CGDirectDisplayID?
            let spaces: [UInt64]
            let currentSpace: UInt64?
        }

        /// Displays in order.
        let displays: [DisplayInfo]
        /// Space ids in left-to-right order, one row per display.
        var orderedSpacesPerDisplay: [[UInt64]] { displays.map(\.spaces) }
        /// The Space currently showing on each display.
        var visibleSpaces: Set<UInt64> { Set(displays.compactMap(\.currentSpace)) }
    }

    static func topology() -> Topology? {
        guard connection != 0, let copyManagedDisplaySpaces,
              let displayDicts = copyManagedDisplaySpaces(connection)?
                .takeRetainedValue() as? [[String: Any]],
              !displayDicts.isEmpty
        else { return nil }

        let screenMap: [String: CGDirectDisplayID] = {
            var map: [String: CGDirectDisplayID] = [:]
            for screen in NSScreen.screens {
                guard let screenNum = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                      let uuid = CGDisplayCreateUUIDFromDisplayID(screenNum)?.takeRetainedValue(),
                      let uuidStr = CFUUIDCreateString(nil, uuid) as String?
                else { continue }
                map[uuidStr] = screenNum
            }
            return map
        }()

        var displays: [Topology.DisplayInfo] = []
        for display in displayDicts {
            let row = (display["Spaces"] as? [[String: Any]])?
                .compactMap { ($0["id64"] as? NSNumber)?.uint64Value } ?? []
            guard !row.isEmpty else { continue }
            let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber
            let uuidStr = display["Display Identifier"] as? String
            let displayID = uuidStr.flatMap { screenMap[$0] }
            displays.append(Topology.DisplayInfo(displayID: displayID,
                                                 spaces: row,
                                                 currentSpace: current?.uint64Value))
        }
        guard !displays.isEmpty else { return nil }
        return Topology(displays: displays)
    }

    private typealias MoveWindowsToSpaceFunction =
        @convention(c) (ConnectionID, CFArray, UInt64) -> Void
    private static let moveWindowsToManagedSpace: MoveWindowsToSpaceFunction? = {
        guard let symbol = symbol("CGSMoveWindowsToManagedSpace") else { return nil }
        return unsafeBitCast(symbol, to: MoveWindowsToSpaceFunction.self)
    }()

    /// The Space showing on the display under `pointer`, an AppKit screen
    /// point. Nil when the Space queries are unavailable, so callers can carry
    /// on without moving anything rather than guessing at a destination.
    static func visibleSpace(near pointer: CGPoint) -> UInt64? {
        guard let topology = topology() else { return nil }
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        if let number = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value,
           let display = topology.displays.first(where: { $0.displayID == number }) {
            return display.currentSpace
        }
        return topology.displays.first?.currentSpace
    }

    /// Brings one window onto the Space the pointer's display is showing. A
    /// window dropped from another desktop otherwise takes the position it was
    /// given and stays where nobody can see it.
    @discardableResult
    static func moveToVisibleSpace(_ windowID: CGWindowID, near pointer: CGPoint) -> Bool {
        guard connection != 0,
              let moveWindowsToManagedSpace,
              let destination = visibleSpace(near: pointer)
        else { return false }
        guard !spaces(of: windowID).contains(destination) else { return true }
        moveWindowsToManagedSpace(connection, [NSNumber(value: windowID)] as CFArray, destination)
        return true
    }

    /// Whether the window sits on at least one Space and none of them is
    /// visible. False when the Space queries are unavailable, so every caller
    /// falls back to the pre-existing behavior.
    static func isParkedOnHiddenSpace(_ windowID: CGWindowID, visibleSpaces: Set<UInt64>? = nil) -> Bool {
        guard let visible = visibleSpaces ?? topology()?.visibleSpaces else { return false }
        return SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: spaces(of: windowID),
                                                     visibleSpaces: visible)
    }

    /// False when the private query is unavailable, preserving the existing
    /// cross-Space behavior instead of hiding a legitimate window on a guess.
    static func isExcludedFromWindowCycle(_ windowID: CGWindowID) -> Bool {
        guard connection != 0, let getWindowTags else { return false }
        var tags = [UInt32](repeating: 0, count: 2)
        return tags.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress,
                  getWindowTags(connection, windowID, base,
                                MemoryLayout<UnsafeRawPointer>.size * 8) == .success
            else { return false }
            return SpaceHopSupport.isExcludedFromWindowCycle(windowTagsLow: buffer[0])
        }
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
