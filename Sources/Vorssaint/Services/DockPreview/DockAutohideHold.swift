// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// A temporary, opt-in change to the Dock preference, owned by one hover session.
/// CoreDock has no public equivalent. Resolve it at runtime so its removal does
/// not prevent the app (or the normal Dock preview) from working.
final class DockAutohideHold {
    private let defaults: UserDefaults
    private let readAutohide: () -> Bool?
    private let writeAutohide: (Bool) -> Bool
    private(set) var isHolding = false

    static var isSupported: Bool { CoreDock.get != nil && CoreDock.set != nil }

    init(defaults: UserDefaults = .standard,
         readAutohide: @escaping () -> Bool? = { CoreDock.read() },
         writeAutohide: @escaping (Bool) -> Bool = { CoreDock.write($0) }) {
        self.defaults = defaults
        self.readAutohide = readAutohide
        self.writeAutohide = writeAutohide
        // Recover even if the experimental toggle was disabled after a crash.
        end()
    }

    @discardableResult
    func begin() -> Bool {
        if isHolding { return true }
        guard !defaults.bool(forKey: DefaultsKey.dockPreviewRestoreAutohide),
              readAutohide() == true else { return false }
        // Persist the restoration before touching the system preference.
        defaults.set(true, forKey: DefaultsKey.dockPreviewRestoreAutohide)
        defaults.synchronize()
        guard writeAutohide(false) else {
            end()
            return false
        }
        isHolding = true
        return true
    }

    func end() {
        isHolding = false
        guard defaults.bool(forKey: DefaultsKey.dockPreviewRestoreAutohide) else { return }
        // Keep the recovery marker if the API disappears or restoration fails.
        guard writeAutohide(true) else { return }
        defaults.removeObject(forKey: DefaultsKey.dockPreviewRestoreAutohide)
        defaults.synchronize()
    }
}

private enum CoreDock {
    typealias Getter = @convention(c) () -> UInt8
    typealias Setter = @convention(c) (UInt8) -> Void
    // Retain the handle for the lifetime of the function pointers.
    static let handle = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
        RTLD_LAZY | RTLD_LOCAL)
    static let get: Getter? = symbol("CoreDockGetAutoHideEnabled", as: Getter.self)
    static let set: Setter? = symbol("CoreDockSetAutoHideEnabled", as: Setter.self)

    static func read() -> Bool? { get.map { $0() != 0 } }

    static func write(_ enabled: Bool) -> Bool {
        guard let set, get != nil else { return false }
        set(enabled ? 1 : 0)
        return read() == enabled
    }

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let address = dlsym(handle, name) else { return nil }
        return unsafeBitCast(address, to: type)
    }
}
