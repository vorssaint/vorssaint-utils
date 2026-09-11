// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct AnnotationPoint: Codable, Equatable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

enum AnnotationTool: String, Codable, CaseIterable {
    case select
    case pen
    case highlighter
    case arrow
    case line
    case rectangle
    case ellipse
    case text
    case redact
    case eraser

    var isRectangular: Bool {
        switch self {
        case .rectangle, .ellipse, .redact: return true
        case .select, .text, .eraser, .pen, .highlighter, .arrow, .line: return false
        }
    }

    var isFreehand: Bool { self == .pen || self == .highlighter }
}

struct AnnotationColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    static let red = AnnotationColor(red: 0.95, green: 0.18, blue: 0.18)
    static let orange = AnnotationColor(red: 0.98, green: 0.36, blue: 0.02)
    static let yellow = AnnotationColor(red: 1.0, green: 0.82, blue: 0.02)
    static let green = AnnotationColor(red: 0.20, green: 0.78, blue: 0.35)
    static let blue = AnnotationColor(red: 0.18, green: 0.45, blue: 0.95)
    static let purple = AnnotationColor(red: 0.69, green: 0.32, blue: 0.87)
    static let black = AnnotationColor(red: 0.09, green: 0.09, blue: 0.11)
    static let white = AnnotationColor(red: 1, green: 1, blue: 1)

    func clamped() -> AnnotationColor {
        AnnotationColor(red: red.clamped(to: 0...1), green: green.clamped(to: 0...1), blue: blue.clamped(to: 0...1))
    }
}

struct AnnotationStroke: Codable, Equatable {
    let tool: AnnotationTool
    let color: AnnotationColor
    let width: Double
    let points: [AnnotationPoint]
    let text: String

    init(tool: AnnotationTool, color: AnnotationColor, width: Double,
         points: [AnnotationPoint], text: String = "") {
        self.tool = tool
        self.color = color.clamped()
        self.width = width.clamped(to: 1...40)
        self.points = Array(points.prefix(ScreenAnnotationSupport.maxPointsPerStroke))
        self.text = String(text.prefix(2_000))
    }
}

enum AnnotationMode: String, Equatable {
    case inactive
    case drawing
    case exiting
    case clearing
    case teardown
}

enum ScreenAnnotationSupport {
    static let maxPointsPerStroke = 600
    static let defaultWidth = 6.0
    /// Points are normalized before they reach `append`. This is roughly a
    /// single physical pixel on ordinary desktop displays; comparing against
    /// `0.25` here would instead require a half-screen movement.
    static let minimumPointDistanceSquared = 0.000_000_25

    /// The canvas remains visible after Escape so existing strokes stay on
    /// screen, but it must stop participating in hit testing outside drawing.
    static func canvasIgnoresMouseEvents(isDrawing: Bool) -> Bool { !isDrawing }

    static func normalized(point: AnnotationPoint, in size: (width: Double, height: Double)) -> AnnotationPoint {
        AnnotationPoint(x: (point.x / max(size.width, 1)).clamped(to: 0...1),
                        y: (point.y / max(size.height, 1)).clamped(to: 0...1))
    }

    static func append(_ point: AnnotationPoint, to points: [AnnotationPoint]) -> [AnnotationPoint] {
        guard points.count < maxPointsPerStroke else { return points }
        guard let last = points.last else { return [point] }
        let dx = point.x - last.x
        let dy = point.y - last.y
        guard (dx * dx + dy * dy) >= minimumPointDistanceSquared else { return points }
        return points + [point]
    }

    static func undo(_ strokes: [AnnotationStroke]) -> [AnnotationStroke] {
        strokes.isEmpty ? [] : Array(strokes.dropLast())
    }

    static func clear(_ strokes: [AnnotationStroke]) -> [AnnotationStroke] { [] }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
