// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The window's name, scrolled instead of clipped while the pointer is on the
/// card. A middle ellipsis is what a long name looks like at rest, and it eats
/// exactly the part that tells two windows of one app apart -- but the pointer
/// is already on the card by the time anybody is trying to read it, so that is
/// where the name is allowed to move.
struct ScrollingTitle: View {
    let text: String
    let weight: Font.Weight
    let width: CGFloat
    let scrolls: Bool

    @State private var began: Date?

    private static let size: CGFloat = 13
    private static let speed: CGFloat = 26
    private static let gap: CGFloat = 20
    /// Long enough that arriving on a card is a still frame, not a moving one.
    private static let startDelay: Double = 0.4
    private static let fade: CGFloat = 6

    private var overflows: Bool {
        SwitcherSupport.titleOverflows(text,
                                       width: width,
                                       fontSize: Self.size,
                                       weight: weight == .semibold ? .semibold : .regular)
    }

    var body: some View {
        Group {
            if scrolls, overflows {
                scrollingLine
            } else {
                Text(text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.system(size: Self.size, weight: weight))
        .frame(width: width, alignment: .leading)
    }

    /// Two copies a gap apart, slid left and wrapped, so the name reads
    /// continuously instead of snapping back at the end. Time is counted from
    /// the moment the pointer arrived, not from the clock: against the clock
    /// the line appeared at whatever phase the cycle happened to be in, which
    /// is why it looked like it started from the middle.
    private var scrollingLine: some View {
        let measured = SwitcherSupport.titleWidth(text,
                                                  fontSize: Self.size,
                                                  weight: weight == .semibold ? .semibold : .regular)
        let run = measured + Self.gap
        let cycle = Double(run) / Double(Self.speed) + Self.startDelay
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let start = began ?? context.date
            let phase = context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle)
            let travelled = max(0, phase - Self.startDelay)
            let moved = CGFloat(travelled) * Self.speed
            // The leading fade arrives with the movement. Drawn from the first
            // frame it ate the first characters while the line was still parked
            // at the edge, which read as the selection outline covering them.
            let lead = min(1, moved / Self.fade) * Self.fade / width
            HStack(spacing: Self.gap) {
                Text(text).lineLimit(1).fixedSize()
                Text(text).lineLimit(1).fixedSize()
            }
            .offset(x: -moved)
            .frame(width: width, alignment: .leading)
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: lead),
                    .init(color: .black, location: 1 - Self.fade / width),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            )
        }
        .frame(width: width, alignment: .leading)
        .clipped()
        .onAppear { began = Date() }
        .onChange(of: text) { _, _ in began = Date() }
    }
}
