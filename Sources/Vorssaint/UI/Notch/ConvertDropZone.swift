// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// One half of the island's drop area. Idle, its dashed edge marches slowly
/// and the glyph floats; when the file is over it, the edge lights, the plate
/// fills with the zone's colour, the glyph leaps and rings spread from it.
struct ConvertDropZone: View {
    let title: String
    let symbol: String
    let selected: Bool
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selected ? AnyShapeStyle(RadialGradient(colors: [tint.opacity(0.32), tint.opacity(0.08)],
                                                                  center: .center, startRadius: 4, endRadius: 140))
                                   : AnyShapeStyle(Color.white.opacity(0.04)))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(tint.opacity(selected ? 0.95 : 0.28),
                                  style: StrokeStyle(lineWidth: selected ? 1.6 : 0.9, dash: [5, 6], dashPhase: reduceMotion ? 0 : -t * 14))
                if selected { rings(t) }
                VStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(selected ? tint : .white.opacity(0.85))
                        .scaleEffect(selected ? 1.18 : 1)
                        .offset(y: reduceMotion ? 0 : CGFloat(sin(t * 1.8 + (selected ? 0 : 1))) * (selected ? 3 : 2))
                        .rotationEffect(.degrees(symbol.contains("arrow") && !reduceMotion ? t * (selected ? 90 : 14) : 0))
                    Text(title).font(.callout.weight(.medium)).multilineTextAlignment(.center)
                        .foregroundStyle(selected ? .white : .white.opacity(0.75))
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(selected ? 1.02 : 1)
        .shadow(color: tint.opacity(selected ? 0.4 : 0), radius: 16)
        .animation(.spring(response: 0.34, dampingFraction: 0.7), value: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Three rings that swell outward and fade, one after another.
    private func rings(_ t: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let phase = (t * 0.9 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                Circle().stroke(tint.opacity(0.5 * (1 - phase)), lineWidth: 1.5)
                    .frame(width: 30 + phase * 120, height: 30 + phase * 120)
            }
        }
        .allowsHitTesting(false)
    }
}
