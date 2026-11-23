// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// One half of the island's drop area. It draws once and changes only when the file
/// moves over it: the edge lights, the plate fills with the zone's colour and the
/// glyph grows. Nothing animates on its own, because a continuously redrawn view
/// over the island's glass makes the window server recomposite every frame and
/// slows the whole Mac while a file is held there.
///
/// `compact` is the small pair shown as soon as a drag starts, before the pointer
/// reaches the island. The full pair fades in as the island opens.
struct ConvertDropZone: View {
    let title: String
    let symbol: String
    let selected: Bool
    let tint: Color
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 16 : 20, style: .continuous)
                .fill(selected ? tint.opacity(0.22) : Color.white.opacity(compact ? 0.05 : 0.04))
            RoundedRectangle(cornerRadius: compact ? 16 : 20, style: .continuous)
                .strokeBorder(tint.opacity(selected ? 0.95 : compact ? 0.4 : 0.28),
                              style: StrokeStyle(lineWidth: selected ? 1.6 : 0.9, dash: [5, 6]))
            if compact {
                HStack(spacing: 7) {
                    Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tint == .white ? .white.opacity(0.85) : tint)
                    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 8)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(selected ? tint : .white.opacity(0.85))
                        .scaleEffect(selected ? 1.18 : 1)
                    Text(title).font(.callout.weight(.medium)).multilineTextAlignment(.center)
                        .foregroundStyle(selected ? .white : .white.opacity(0.75))
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Each box stays inside its own outline: scaling it, or a spring overshooting, would push
        // the dotted edge past the island's rounded sides while the island is still growing.
        .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 20, style: .continuous))
        .opacity(compact || grown ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: selected)
        .onAppear {
            guard !compact else { return }
            if reduceMotion { grown = true } else { withAnimation(.easeOut(duration: 0.25)) { grown = true } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
