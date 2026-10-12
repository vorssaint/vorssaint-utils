// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

/// Recognises keyboard events this app posts itself, so a filter meant for
/// physical typing can leave them alone.
///
/// The window server stamps a posted event with the poster's process id, which
/// covers most of them. The user data markers cover the rest: Quit Protection
/// confirms a press by posting a copy of the hardware key down, which starts
/// with the hardware source's process id of 0, and Text Snippets types through
/// a source carrying its own marker.
enum OwnKeyEvent {
    static let quitProtectionMarker: Int64 = 0x5652535341494E54 // "VRSSAINT"
    static let textSnippetMarker: Int64 = 0x564F5253 // "VORS"

    private static let ownProcessID = Int64(getpid())

    static func isPosted(sourceProcessID: Int64, userData: Int64, ownProcessID: Int64) -> Bool {
        sourceProcessID == ownProcessID
            || userData == quitProtectionMarker
            || userData == textSnippetMarker
    }

    /// When this app last posted a key down, for a reader that only has the
    /// system's record of the last key down, which counts posted keys along
    /// with typed ones. Written on the main thread, read on any.
    private static let postLock = NSLock()
    private static var lastPostUptime: TimeInterval = -.infinity

    static func notePosted() {
        let now = ProcessInfo.processInfo.systemUptime
        postLock.withLock { lastPostUptime = now }
    }

    static var secondsSinceLastPost: TimeInterval {
        ProcessInfo.processInfo.systemUptime - postLock.withLock { lastPostUptime }
    }

    static func isPosted(_ event: CGEvent) -> Bool {
        isPosted(sourceProcessID: event.getIntegerValueField(.eventSourceUnixProcessID),
                 userData: event.getIntegerValueField(.eventSourceUserData),
                 ownProcessID: ownProcessID)
    }
}
