// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The same immediate lock as the system's own shortcut, with the password
/// prompt. SACLockScreenImmediate lives in the login framework, resolved once
/// and guarded: a missing symbol just means the screen saver stands in, which
/// locks too when a password is required.
enum ScreenLock {
    private static let lockFunction: (@convention(c) () -> Int32)? = {
        let path = "/System/Library/PrivateFrameworks/login.framework/login"
        guard let handle = dlopen(path, RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) () -> Int32).self)
    }()

    static func lockNow() {
        if let lockFunction {
            _ = lockFunction()
        } else {
            let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            NSWorkspace.shared.openApplication(at: url,
                                               configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
