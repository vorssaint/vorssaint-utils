// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

/// Optional WindowServer helpers. Symbols are resolved dynamically so a macOS
/// update can remove them without preventing Vorssaint from launching.
final class DynamicMenuBarAPI {
    static let shared = DynamicMenuBarAPI()

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias WindowFrame = @convention(c) (Int32, CGWindowID, UnsafeMutablePointer<CGRect>) -> Int32

    private let handle: UnsafeMutableRawPointer?
    private let mainConnection: MainConnection?
    private let windowFrame: WindowFrame?

    var hasWindowFrame: Bool { mainConnection != nil && windowFrame != nil }

    private init() {
        let path = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
        handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL)
        if let handle,
           let connectionSymbol = dlsym(handle, "CGSMainConnectionID"),
           let frameSymbol = dlsym(handle, "CGSGetScreenRectForWindow") {
            mainConnection = unsafeBitCast(connectionSymbol, to: MainConnection.self)
            windowFrame = unsafeBitCast(frameSymbol, to: WindowFrame.self)
        } else {
            mainConnection = nil
            windowFrame = nil
        }
    }

    deinit {
        if let handle { dlclose(handle) }
    }

    func frame(for windowID: CGWindowID) -> CGRect? {
        guard let mainConnection, let windowFrame else { return nil }
        var rect = CGRect.zero
        guard windowFrame(mainConnection(), windowID, &rect) == 0,
              rect.width > 0, rect.height > 0
        else { return nil }
        return rect
    }
}
