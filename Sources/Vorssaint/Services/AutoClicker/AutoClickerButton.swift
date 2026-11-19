// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

public enum AutoClickerButton: String, CaseIterable, Identifiable, Codable {
    case left
    case right
    case middle

    public var id: String { rawValue }

    public var cgMouseButton: CGMouseButton {
        switch self {
        case .left: return .left
        case .right: return .right
        case .middle: return .center
        }
    }

    public var cgEventTypeDown: CGEventType {
        switch self {
        case .left: return .leftMouseDown
        case .right: return .rightMouseDown
        case .middle: return .otherMouseDown
        }
    }

    public var cgEventTypeUp: CGEventType {
        switch self {
        case .left: return .leftMouseUp
        case .right: return .rightMouseUp
        case .middle: return .otherMouseUp
        }
    }

    public var buttonNumber: Int64 {
        switch self {
        case .left: return 0
        case .right: return 1
        case .middle: return 2
        }
    }
}
