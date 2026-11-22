// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Slow-drifting washes of the cover's colours with a scatter of rising
/// particles, drawn behind the lyrics. Cheap by design: a few radial
/// gradients and dots at 30 frames a second, no blur filters.
struct AuroraBackdrop: View {
    let palette: [Color]

    private struct Particle {
        let x: Double, y: Double, speed: Double, radius: Double, phase: Double, sway: Double, tone: Int
    }

    private static let particles: [Particle] = {
        var state: UInt64 = 0x1234_5678_9ABC_DEF1
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        return (0..<44).map { _ in
            Particle(x: next(), y: next(), speed: 0.006 + next() * 0.014, radius: 1.2 + next() * 3.2,
                     phase: next() * 6.28, sway: 0.01 + next() * 0.03, tone: Int(next() * 8))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            Canvas { gc, size in
                let colors = palette.isEmpty ? [Color(red: 0.35, green: 0.45, blue: 0.8)] : palette
                let t = context.date.timeIntervalSinceReferenceDate
                let reach = max(size.width, size.height) * 0.62
                for (index, color) in colors.enumerated() {
                    let i = Double(index)
                    let center = CGPoint(x: size.width * (0.5 + 0.40 * sin(t * 0.11 + i * 1.9)),
                                         y: size.height * (0.5 + 0.36 * cos(t * 0.09 + i * 2.4)))
                    gc.fill(Path(ellipseIn: CGRect(x: center.x - reach, y: center.y - reach, width: reach * 2, height: reach * 2)),
                            with: .radialGradient(Gradient(colors: [color.opacity(0.55), color.opacity(0)]),
                                                  center: center, startRadius: 0, endRadius: reach))
                }
                for particle in Self.particles {
                    let rise = (particle.y - t * particle.speed).truncatingRemainder(dividingBy: 1)
                    let y = (rise < 0 ? rise + 1 : rise) * size.height
                    let x = (particle.x + sin(t * 0.4 + particle.phase) * particle.sway) * size.width
                    let twinkle = 0.35 + 0.35 * sin(t * 1.3 + particle.phase)
                    gc.fill(Path(ellipseIn: CGRect(x: x - particle.radius, y: y - particle.radius,
                                                   width: particle.radius * 2, height: particle.radius * 2)),
                            with: .color(colors[particle.tone % colors.count].opacity(twinkle)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
