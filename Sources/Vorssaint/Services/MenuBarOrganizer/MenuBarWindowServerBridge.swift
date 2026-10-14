// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Optional menu bar queries adapted from #360. Callers gate these on macOS
/// 14–26 before touching the connection. Missing symbols degrade to public
/// window inventory; unknown geometry never authorizes a synthetic event.
enum MenuBarWindowServerBridge {
    private typealias ConnectionID = UInt32

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name)
    }

    private static let connection: ConnectionID = {
        typealias Function = @convention(c) () -> ConnectionID
        guard let symbol = symbol("CGSMainConnectionID") else { return 0 }
        return unsafeBitCast(symbol, to: Function.self)()
    }()

    private typealias WindowCountFunction = @convention(c) (
        ConnectionID, Int32, UnsafeMutablePointer<Int32>
    ) -> CGError
    private static let windowCount: WindowCountFunction? = {
        guard let symbol = symbol("CGSGetWindowCount") else { return nil }
        return unsafeBitCast(symbol, to: WindowCountFunction.self)
    }()

    private typealias MenuBarWindowListFunction = @convention(c) (
        ConnectionID, Int32, Int32, UnsafeMutablePointer<CGWindowID>, UnsafeMutablePointer<Int32>
    ) -> CGError
    private static let menuBarWindowList: MenuBarWindowListFunction? = {
        guard let symbol = symbol("CGSGetProcessMenuBarWindowList") else { return nil }
        return unsafeBitCast(symbol, to: MenuBarWindowListFunction.self)
    }()

    private typealias WindowFrameFunction = @convention(c) (
        ConnectionID, CGWindowID, UnsafeMutablePointer<CGRect>
    ) -> CGError
    private static let windowFrame: WindowFrameFunction? = {
        guard let symbol = symbol("CGSGetScreenRectForWindow") else { return nil }
        return unsafeBitCast(symbol, to: WindowFrameFunction.self)
    }()

    private typealias WindowLevelFunction = @convention(c) (
        ConnectionID, CGWindowID, UnsafeMutablePointer<CGWindowLevel>
    ) -> CGError
    private static let windowLevel: WindowLevelFunction? = {
        guard let symbol = symbol("CGSGetWindowLevel") else { return nil }
        return unsafeBitCast(symbol, to: WindowLevelFunction.self)
    }()

    static var canListMenuBarWindows: Bool {
        connection != 0 && windowCount != nil && menuBarWindowList != nil
    }

    static var canResolveWindowFrames: Bool {
        connection != 0 && windowFrame != nil
    }

    static func menuBarWindowIDs() -> [CGWindowID]? {
        guard connection != 0, let windowCount, let menuBarWindowList else { return nil }
        var count: Int32 = 0
        guard windowCount(connection, 0, &count) == .success, count > 0, count <= 100_000 else { return nil }
        var ids = [CGWindowID](repeating: 0, count: Int(count))
        var actualCount = count
        guard menuBarWindowList(connection, 0, count, &ids, &actualCount) == .success,
              actualCount >= 0,
              actualCount <= count
        else { return nil }
        return Array(ids.prefix(Int(actualCount)))
    }

    static func frame(of windowID: CGWindowID) -> CGRect? {
        guard connection != 0, let windowFrame else { return nil }
        var frame = CGRect.zero
        guard windowFrame(connection, windowID, &frame) == .success,
              frame.width > 0,
              frame.height > 0
        else { return nil }
        return frame
    }

    static func level(of windowID: CGWindowID) -> CGWindowLevel? {
        guard connection != 0, let windowLevel else { return nil }
        var level: CGWindowLevel = 0
        guard windowLevel(connection, windowID, &level) == .success else { return nil }
        return level
    }

}
