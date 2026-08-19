// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

/// Dynamically resolves the small private WindowServer surface needed to
/// identify menu bar windows. Every call has a public fallback in the provider;
/// a missing symbol must disable a capability, never prevent app launch.
final class MenuBarWindowServerBridge: @unchecked Sendable {
    static let shared = MenuBarWindowServerBridge()

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias WindowCount = @convention(c) (
        Int32, Int32, UnsafeMutablePointer<Int32>
    ) -> CGError
    private typealias MenuBarWindowList = @convention(c) (
        Int32, Int32, Int32, UnsafeMutablePointer<CGWindowID>, UnsafeMutablePointer<Int32>
    ) -> CGError
    private typealias WindowFrame = @convention(c) (
        Int32, CGWindowID, UnsafeMutablePointer<CGRect>
    ) -> CGError
    private typealias WindowLevel = @convention(c) (
        Int32, CGWindowID, UnsafeMutablePointer<CGWindowLevel>
    ) -> CGError

    private let handle: UnsafeMutableRawPointer?
    private let mainConnection: MainConnection?
    private let windowCount: WindowCount?
    private let menuBarWindowList: MenuBarWindowList?
    private let windowFrame: WindowFrame?
    private let windowLevel: WindowLevel?

    var hasPrivateWindowList: Bool {
        mainConnection != nil && windowCount != nil && menuBarWindowList != nil
    }

    var hasWindowFrame: Bool {
        mainConnection != nil && windowFrame != nil
    }

    private init() {
        handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
                        RTLD_LAZY | RTLD_LOCAL)
        mainConnection = Self.symbol("CGSMainConnectionID", in: handle, as: MainConnection.self)
        windowCount = Self.symbol("CGSGetWindowCount", in: handle, as: WindowCount.self)
        menuBarWindowList = Self.symbol(
            "CGSGetProcessMenuBarWindowList", in: handle, as: MenuBarWindowList.self)
        windowFrame = Self.symbol(
            "CGSGetScreenRectForWindow", in: handle, as: WindowFrame.self)
        windowLevel = Self.symbol("CGSGetWindowLevel", in: handle, as: WindowLevel.self)
    }

    deinit {
        if let handle { dlclose(handle) }
    }

    func menuBarWindowIDs() -> [CGWindowID]? {
        guard let mainConnection, let windowCount, let menuBarWindowList else { return nil }
        let connection = mainConnection()
        var count: Int32 = 0
        guard windowCount(connection, 0, &count) == .success, count > 0 else { return nil }
        var ids = [CGWindowID](repeating: 0, count: Int(count))
        var actualCount = count
        guard menuBarWindowList(connection, 0, count, &ids, &actualCount) == .success,
              actualCount >= 0,
              actualCount <= count
        else { return nil }
        return Array(ids.prefix(Int(actualCount)))
    }

    func frame(for windowID: CGWindowID) -> CGRect? {
        guard let mainConnection, let windowFrame else { return nil }
        var frame = CGRect.zero
        guard windowFrame(mainConnection(), windowID, &frame) == .success,
              frame.width > 0,
              frame.height > 0
        else { return nil }
        return frame
    }

    func level(for windowID: CGWindowID) -> CGWindowLevel? {
        guard let mainConnection, let windowLevel else { return nil }
        var level: CGWindowLevel = 0
        guard windowLevel(mainConnection(), windowID, &level) == .success else { return nil }
        return level
    }

    private static func symbol<T>(_ name: String,
                                  in handle: UnsafeMutableRawPointer?,
                                  as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }
}
