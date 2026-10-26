// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Shared by the manual toggle and ambient-light automation. Call on main.
enum SystemAppearance {
    private typealias Get = @convention(c) () -> Bool
    private typealias Set = @convention(c) (Bool) -> Void

    private static let api: (get: Get, set: Set)? = {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY),
              let get = dlsym(handle, "SLSGetAppearanceThemeLegacy"),
              let set = dlsym(handle, "SLSSetAppearanceThemeLegacy") else { return nil }
        return (unsafeBitCast(get, to: Get.self), unsafeBitCast(set, to: Set.self))
    }()

    static var isDark: Bool? { api?.get() }

    @discardableResult
    static func setDark(_ dark: Bool) -> Bool {
        guard let api else { return false }
        if api.get() != dark { api.set(dark) }
        return api.get() == dark
    }
}
