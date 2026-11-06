// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Download (filled) and upload (line) history on one scale, so they compare
/// fairly. Hovering marks a sample and names both speeds at that moment.
struct NetworkHistoryGraph: View {
    var down: [Double]
    var up: [Double]
    var inBits: Bool
    var height: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoverX: CGFloat?

    var body: some View {
        let peak = MetricFormat.networkGraphCeiling(max(down.max() ?? 0, up.max() ?? 0, 1), inBits: inBits)
        ZStack {
            Sparkline(values: down, color: .accentColor, maxValue: peak, showsZeroBaseline: true)
            Sparkline(values: up,
                      color: PanelMetricColor.green(for: colorScheme),
                      maxValue: peak,
                      fillOpacity: 0.08)
        }
        .frame(height: height)
        .graphCeilingLabel(MetricFormat.networkRate(peak, inBits: inBits))
        .overlay {
            GeometryReader { geometry in
                if let hoverX {
                    hoverReadout(at: hoverX, width: geometry.size.width)
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): hoverX = location.x
            case .ended: hoverX = nil
            }
        }
    }

    /// The sample under the pointer, with its two speeds right beside the
    /// rule: on its right, or on its left where the right edge would cut
    /// the label off.
    @ViewBuilder
    private func hoverReadout(at x: CGFloat, width: CGFloat) -> some View {
        let count = max(down.count, up.count)
        if count >= 2, width > 0 {
            let index = Int((min(max(x, 0), width) / width * CGFloat(count - 1)).rounded())
            // Sparkline spreads each series over the full width, so the rule
            // snaps to where that sample is drawn.
            let sampleX = width * CGFloat(index) / CGFloat(count - 1)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: sampleX, y: 0))
                    path.addLine(to: CGPoint(x: sampleX, y: height))
                }
                .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
                Text("↓\(rate(down, index, count))  ↑\(rate(up, index, count))")
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .padding(.horizontal, 3)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
                    .fixedSize()
                    // The guide hands over the label's own width, so it can
                    // flip sides without being measured first.
                    .alignmentGuide(.leading) { label in
                        -Self.readoutX(ruleX: sampleX, labelWidth: label.width, graphWidth: width)
                    }
            }
            .frame(width: width, height: height, alignment: .topLeading)
        }
    }

    /// Where the readout's left edge goes: a small gap right of the rule,
    /// else left of it, and kept inside the graph when neither side fits.
    static func readoutX(ruleX: CGFloat, labelWidth: CGFloat, graphWidth: CGFloat) -> CGFloat {
        let gap: CGFloat = 4
        let right = ruleX + gap
        let x = right + labelWidth <= graphWidth ? right : ruleX - gap - labelWidth
        return min(max(x, 0), max(graphWidth - labelWidth, 0))
    }

    /// Both series end at the newest sample, so a shorter one lines up from
    /// the right.
    private func rate(_ values: [Double], _ index: Int, _ count: Int) -> String {
        let aligned = index - (count - values.count)
        guard values.indices.contains(aligned) else { return "–" }
        return MetricFormat.networkRateCompact(values[aligned], inBits: inBits)
    }
}
