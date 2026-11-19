// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

public enum AutoClickerMode: String, CaseIterable, Identifiable, Codable {
    case single
    case macro

    public var id: String { rawValue }
}

public enum AutoClickerTargetMode: String, CaseIterable, Identifiable, Codable {
    case cursor
    case fixedPoint

    public var id: String { rawValue }
}

public struct AutoClickerMacroStep: Identifiable, Codable, Equatable {
    public var id: UUID
    public var x: Double
    public var y: Double
    public var button: AutoClickerButton
    public var delayAfterMs: Int
    public var clickCount: Int

    public init(
        id: UUID = UUID(),
        x: Double,
        y: Double,
        button: AutoClickerButton = .left,
        delayAfterMs: Int = 200,
        clickCount: Int = 1
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.button = button
        self.delayAfterMs = AutoClickerCoordinates.clampedDelayMs(delayAfterMs)
        self.clickCount = max(1, min(clickCount, 2))
    }
}

public struct AutoClickerMacro: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var steps: [AutoClickerMacroStep]
    public var repeatCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        steps: [AutoClickerMacroStep] = [],
        repeatCount: Int = 1
    ) {
        self.id = id
        self.name = name
        self.steps = steps
        self.repeatCount = max(0, repeatCount)
    }
}

public enum AutoClickerMacroStore {
    public static func encode(_ macros: [AutoClickerMacro]) -> String {
        guard let data = try? JSONEncoder().encode(macros),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }

    public static func decode(_ raw: String) -> [AutoClickerMacro] {
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let macros = try? JSONDecoder().decode([AutoClickerMacro].self, from: data) else {
            return []
        }
        return macros
    }
}

public enum AutoClickerCoordinates {
    public static func cgPoint(fromAppKitPoint point: CGPoint, primaryScreenMaxY: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenMaxY - point.y)
    }

    public static func appKitPoint(fromCGPoint point: CGPoint, primaryScreenMaxY: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenMaxY - point.y)
    }

    public static func clampedDelayMs(_ ms: Int) -> Int {
        max(10, ms)
    }
}
