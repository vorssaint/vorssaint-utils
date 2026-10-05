// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A small history graph: a filled area under a smooth polyline. Hand-drawn with
/// `Path` so the app needs no charting framework (and stays clear of the SwiftUI
/// macro plugins the Command Line Tools cannot load).
///
/// `maxValue` fixes the vertical scale (CPU/memory use 1.0 for an absolute 0–100%
/// reading); when nil the graph auto-scales to its own peak (network, power).
struct Sparkline: View {
    var values: [Double]
    var color: Color
    var maxValue: Double? = nil
    var fillOpacity: Double = 0.16
    var lineWidth: CGFloat = 1.5
    var showsZeroBaseline = false

    var body: some View {
        GeometryReader { geometry in
            let baselineY = max(0.5, geometry.size.height - 0.5)
            let points = points(in: geometry.size, baselineY: baselineY)
            if points.count >= 2 {
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: baselineY))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: baselineY))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(colors: [color.opacity(fillOpacity), color.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    if showsZeroBaseline {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: baselineY))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: baselineY))
                        }
                        .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
                    }
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize, baselineY: CGFloat) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let peak = max(maxValue ?? (values.max() ?? 1), 0.0001)
        let topY: CGFloat = 0.5
        let plotHeight = max(1, baselineY - topY)
        let lastIndex = values.count - 1
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(lastIndex)
            let normalized = min(1, max(0, value / peak))
            let y = baselineY - plotHeight * CGFloat(normalized)
            return CGPoint(x: x, y: y)
        }
    }
}

extension View {
    /// Marks the top of a graph with a dashed rule and names its value on that
    /// rule, so the number reads as the scale and not as a sample.
    func graphCeilingLabel(_ text: String) -> some View {
        modifier(GraphCeilingLabel(text: text))
    }
}

private struct GraphCeilingLabel: ViewModifier {
    @AppStorage(DefaultsKey.monitorGraphScale) private var visible = true
    let text: String

    func body(content: Content) -> some View {
        if visible {
            content
                .overlay {
                    GeometryReader { geometry in
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0.5))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: 0.5))
                        }
                        .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                    .allowsHitTesting(false)
                }
                // Over the oldest samples, so the newest stay clear.
                .overlay(alignment: .topLeading) {
                    Text(text)
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
                        .alignmentGuide(.top) { $0[VerticalAlignment.center] }
                        .allowsHitTesting(false)
                }
        } else {
            content
        }
    }
}
