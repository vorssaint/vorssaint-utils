// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

enum GestureEvent {
    static let magnifySubtype: Int64 = 0x08
    static let swipeSubtype: Int64 = kTLInfoSubtypeSwipe

    static func make(subtype: Int64, phase: Int64, at point: CGPoint?,
                     configure: (CGEvent) -> Void = { _ in }) -> CGEvent? {
        guard let gesture = CGEvent(source: nil) else { return nil }
        if let point { gesture.location = point }
        gesture.type = CGEventType(rawValue: 29)!
        gesture.setIntegerValueField(CGEventField(rawValue: 110)!, value: subtype)
        gesture.setIntegerValueField(CGEventField(rawValue: 132)!, value: phase)
        configure(gesture)
        return gesture
    }

    static func post(subtype: Int64, phase: Int64, at point: CGPoint?,
                     configure: (CGEvent) -> Void = { _ in }) {
        make(subtype: subtype, phase: phase, at: point, configure: configure)?
            .post(tap: .cgSessionEventTap)
    }
}
