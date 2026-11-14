// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Draws an AgentDotAnimation as round dots in one color, frame by frame at
/// its own pace. With reduced motion it shows its still frame alone.
struct AgentDotAnimationView: View {
    let animation: AgentDotAnimation
    let tint: Color
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        Group {
            if reduceMotion {
                dots(frame: animation.still)
            } else {
                TimelineView(.periodic(from: start, by: 1 / Double(max(1, animation.fps)))) { context in
                    dots(frame: animation.frameIndex(elapsed: context.date.timeIntervalSince(start)))
                }
            }
        }
        .frame(width: size, height: size)
        // A new animation, as a different choice in Settings, starts over.
        .onChange(of: animation.id) { _, _ in start = Date() }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func dots(frame: Int) -> some View {
        Canvas { context, canvas in
            let columns = max(1, animation.columns)
            let rows = max(1, animation.rows)
            let cell = min(canvas.width / CGFloat(columns), canvas.height / CGFloat(rows))
            let radius = cell * 0.36
            let originX = (canvas.width - cell * CGFloat(columns)) / 2
            let originY = (canvas.height - cell * CGFloat(rows)) / 2
            for row in 0..<rows {
                for column in 0..<columns {
                    let level = animation.level(frame: frame, column: column, row: row)
                    guard level > 0 else { continue }
                    let center = CGPoint(x: originX + (CGFloat(column) + 0.5) * cell,
                                         y: originY + (CGFloat(row) + 0.5) * cell)
                    let dot = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: dot), with: .color(tint.opacity(level)))
                }
            }
        }
    }
}
