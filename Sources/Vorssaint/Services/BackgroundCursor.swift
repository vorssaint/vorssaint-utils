// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The window server ignores cursor changes from an app in the background,
/// and Vorssaint's full-screen surfaces keep the app there, so a pointer they
/// set or hide never takes effect (measured on macOS 27). The connection
/// property lifts that while any surface needs it. Resolved at runtime, so a
/// macOS that drops it degrades to the ordinary pointer as before.
///
/// Each surface holds the property under its own name, so one finishing
/// cannot take it from another that is still on screen.
enum BackgroundCursor {
    enum Owner: Hashable {
        /// The screenshot and recording selection, which shows its crosshair.
        case screenCapture
        /// The presentation pointer, which hides the system pointer.
        case presentationPointer
    }

    /// Posted on the main thread whenever the set of owners changes.
    static let ownersDidChange = Notification.Name("VorssaintBackgroundCursorOwnersDidChange")

    private(set) static var owners: Set<Owner> = []

    static func setAllowed(_ allowed: Bool, by owner: Owner) {
        let wasAllowed = !owners.isEmpty
        let changed = allowed ? owners.insert(owner).inserted : owners.remove(owner) != nil
        guard changed else { return }
        if wasAllowed != !owners.isEmpty {
            apply(!owners.isEmpty)
        }
        NotificationCenter.default.post(name: ownersDidChange, object: nil)
    }

    private typealias ConnectionID = UInt32
    private typealias SetPropertyFunction =
        @convention(c) (ConnectionID, ConnectionID, CFString, CFTypeRef) -> CGError

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name)
    }

    private static let connection: ConnectionID = {
        typealias Function = @convention(c) () -> ConnectionID
        guard let symbol = symbol("CGSMainConnectionID") else { return 0 }
        return unsafeBitCast(symbol, to: Function.self)()
    }()

    private static let setProperty: SetPropertyFunction? = {
        guard let symbol = symbol("CGSSetConnectionProperty") else { return nil }
        return unsafeBitCast(symbol, to: SetPropertyFunction.self)
    }()

    private static func apply(_ allowed: Bool) {
        guard connection != 0, let setProperty else { return }
        _ = setProperty(connection, connection, "SetsCursorInBackground" as CFString,
                        allowed ? kCFBooleanTrue : kCFBooleanFalse)
    }
}
