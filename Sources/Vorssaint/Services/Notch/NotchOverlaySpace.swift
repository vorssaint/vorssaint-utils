// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// A Space of the island's own, shown over the desktops at the default level.
/// A stationary window stays put when the desktop is revealed, but it belongs
/// to the desktops, so a swipe between desktops or into a full-screen app
/// slides it away with the wallpaper and back. A window that joins this Space
/// before it is first shown belongs to no desktop at all, so no desktop change
/// moves it, like the menu bar. Windows still order by their own level
/// against every other window: native menus and dialogs stay above the island.
///
/// AppKit then never counts the window as on the active Space; key focus,
/// tracking and the display link work as before. Its only Space must never
/// be destroyed under it, or the window would have none and never show
/// again. The symbols are resolved at runtime; without them the island keeps
/// sliding with the desktop, as before.
final class NotchOverlaySpace {
    private typealias ConnectionID = UInt32
    private typealias CreateFunction = @convention(c) (ConnectionID, Int32, CFDictionary?) -> UInt64
    private typealias SpacesFunction = @convention(c) (ConnectionID, CFArray) -> Int32
    private typealias WindowsFunction = @convention(c) (ConnectionID, CFArray, CFArray) -> Void
    private typealias DestroyFunction = @convention(c) (ConnectionID, UInt64) -> Void

    private struct Bridge {
        let connection: ConnectionID
        let create: CreateFunction
        let show: SpacesFunction
        let hide: SpacesFunction
        let add: WindowsFunction
        let remove: WindowsFunction
        let destroy: DestroyFunction
    }

    private static let bridge: Bridge? = {
        func symbol(_ name: String) -> UnsafeMutableRawPointer? {
            dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name)
        }
        guard let main = symbol("CGSMainConnectionID"), let create = symbol("CGSSpaceCreate"),
              let show = symbol("CGSShowSpaces"), let hide = symbol("CGSHideSpaces"),
              let add = symbol("CGSAddWindowsToSpaces"), let remove = symbol("CGSRemoveWindowsFromSpaces"),
              let destroy = symbol("CGSSpaceDestroy") else { return nil }
        let connection = unsafeBitCast(main, to: (@convention(c) () -> ConnectionID).self)()
        guard connection != 0 else { return nil }
        return Bridge(connection: connection,
                      create: unsafeBitCast(create, to: CreateFunction.self),
                      show: unsafeBitCast(show, to: SpacesFunction.self),
                      hide: unsafeBitCast(hide, to: SpacesFunction.self),
                      add: unsafeBitCast(add, to: WindowsFunction.self),
                      remove: unsafeBitCast(remove, to: WindowsFunction.self),
                      destroy: unsafeBitCast(destroy, to: DestroyFunction.self))
    }()

    private let bridge: Bridge
    private let space: UInt64
    private var windows = Set<Int>()
    private var closed = false

    init?() {
        guard let bridge = Self.bridge else { return nil }
        // Any flag but 1 makes Finder draw the desktop icons in this Space.
        let space = bridge.create(bridge.connection, 1, nil)
        guard space != 0 else { return nil }
        self.bridge = bridge
        self.space = space
        _ = bridge.show(bridge.connection, [NSNumber(value: space)] as CFArray)
    }

    deinit { close() }

    /// Joins a window before it is first ordered in: one already on screen
    /// would stay on its desktop as well and still slide with it. Ordering
    /// out and in again keeps the window here.
    func add(_ window: NSWindow) {
        guard !closed, window.windowNumber > 0, windows.insert(window.windowNumber).inserted else { return }
        bridge.add(bridge.connection, [NSNumber(value: window.windowNumber)] as CFArray,
                   [NSNumber(value: space)] as CFArray)
    }

#if VORSSAINT_DEVELOPMENT
    /// The window server's own answer: the window belongs to this Space and
    /// to no desktop a swipe could move.
    func probeHolds(_ window: NSWindow) -> Bool {
        typealias CopyFunction = @convention(c) (ConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSCopySpacesForWindows") else { return false }
        let copy = unsafeBitCast(symbol, to: CopyFunction.self)
        // 0x7 lists the desktops; 0x8 adds Spaces like this one.
        func spaces(_ mask: Int32) -> Set<UInt64> {
            Set((copy(bridge.connection, mask, [NSNumber(value: window.windowNumber)] as CFArray)?
                .takeRetainedValue() as? [NSNumber])?.map(\.uint64Value) ?? [])
        }
        return spaces(0xF) == [space] && spaces(0x7).isEmpty
    }
#endif

    /// Windows leave before the Space goes: a window whose only Space is
    /// destroyed would belong to none and never show again.
    func close() {
        guard !closed else { return }
        closed = true
        if !windows.isEmpty {
            bridge.remove(bridge.connection, windows.map { NSNumber(value: $0) } as CFArray,
                          [NSNumber(value: space)] as CFArray)
            windows.removeAll()
        }
        _ = bridge.hide(bridge.connection, [NSNumber(value: space)] as CFArray)
        bridge.destroy(bridge.connection, space)
    }
}
