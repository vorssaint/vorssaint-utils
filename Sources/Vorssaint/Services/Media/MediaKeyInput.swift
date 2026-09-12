// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Presses a media key on the user's behalf, so whatever player owns the
/// physical keys reacts exactly as if F7/F8/F9 was pressed. Reading Now
/// Playing needs a platform binary (`Sources/NowPlayingAdapter`), but
/// *controlling* it does not: the aux-button pair reaches the owning player
/// through the same path the hardware uses, with no private framework and no
/// per-application integration.
///
/// One poster for the whole app. The radial menu's media slices and the
/// panel's Now Playing section press the same keys, and #937 is the record of
/// what happens when each caller grows its own copy of a synthetic-event
/// construction.
enum MediaKeyInput {
    /// `RadialMenuMediaKey.auxKeyType` owns the code numbers; this owns the
    /// event. A key with no aux code (Now Playing) is not a press.
    static func post(auxKeyType: Int32) {
        postAuxKey(auxKeyType, down: true)
        postAuxKey(auxKeyType, down: false)
    }

    private static func postAuxKey(_ type: Int32, down: Bool) {
        let stateFlags: NSEvent.ModifierFlags = down
            ? NSEvent.ModifierFlags(rawValue: 0xA00)
            : NSEvent.ModifierFlags(rawValue: 0xB00)
        let data1 = (Int(type) << 16) | ((down ? 0xA : 0xB) << 8)
        guard let event = NSEvent.otherEvent(with: .systemDefined,
                                             location: .zero,
                                             modifierFlags: stateFlags,
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: 0,
                                             context: nil,
                                             subtype: 8,
                                             data1: data1,
                                             data2: -1)
        else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
