// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Parameters driving the unified on-bar light renderer across styles and motions.
struct NotchContourBarRenderParams {
    let shape: NotchBottomUShape
    let palette: NotchLevelPrismPalette
    let fillExtent: Double
    let armWidth: NotchHaloArmWidth
    let thicknessScale: Double
    let time: TimeInterval
    let motion: NotchHaloMotion
    let motionStrength: Double
    let energy: Double
    let isTrimmedLevel: Bool
    let reduceMotion: Bool

    var clampedExtent: Double {
        min(1.0, max(0.012, fillExtent))
    }

    var scale: CGFloat {
        CGFloat(thicknessScale)
    }

    var spread: CGFloat {
        CGFloat(armWidth.glowSpread)
    }

    var springEnergy: Double {
        reduceMotion ? 0.0 : min(1.0, max(0.0, energy))
    }

    var ambientBreath: Double {
        guard !reduceMotion, motion != .none else { return 1.0 }
        switch motion {
        case .ondulation:
            return 1.0 - 0.10 * motionStrength + 0.10 * motionStrength * (0.5 + 0.5 * sin(time * 2.1))
        case .flux, .ripple, .shimmer:
            return 1.0 - 0.05 * motionStrength + 0.05 * motionStrength * (0.5 + 0.5 * sin(time * 2.6))
        case .none:
            return 1.0
        }
    }

    var barGradient: LinearGradient {
        if isTrimmedLevel {
            return LinearGradient(
                colors: [palette.trail.color, palette.lead.color, palette.core.color],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        let drift: Double
        if reduceMotion {
            drift = 0.5
        } else {
            switch motion {
            case .ondulation:
                drift = 0.5 + 0.22 * sin(time * 1.9)
            case .flux:
                drift = 0.22 + 0.56 * NotchLightsSupport.fract(time * 0.42)
            case .none, .ripple, .shimmer:
                drift = 0.5
            }
        }
        let leftStop = max(0.08, drift - 0.24)
        let rightStop = min(0.92, drift + 0.24)
        return LinearGradient(
            stops: [
                .init(color: palette.trail.color, location: 0.0),
                .init(color: palette.lead.color, location: leftStop),
                .init(color: palette.core.color, location: drift),
                .init(color: palette.lead.color, location: rightStop),
                .init(color: palette.trail.color, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    func trimmedBounds(center: Double, halfWidth: Double) -> (from: Double, to: Double)? {
        let maxE = clampedExtent
        let c = min(maxE, max(0.0, center))
        let lo = max(0.0, c - halfWidth)
        let hi = min(maxE, c + halfWidth)
        guard hi - lo > 0.002 else { return nil }
        return (lo, hi)
    }
}

/// Active style dispatcher rendering all 7 laser styles strictly along `NotchBottomUShape`.
struct NotchContourStyleLayer: View {
    let style: NotchHaloStyle
    let params: NotchContourBarRenderParams

    var body: some View {
        switch style {
        case .classic:
            NotchClassicBarStyleView(params: params)
        case .pixelated:
            NotchPixelatedBarStyleView(params: params)
        case .volumetric:
            NotchVolumetricBarStyleView(params: params)
        case .rays:
            NotchRaysBarStyleView(params: params)
        case .bioluminescent:
            NotchBioluminescentBarStyleView(params: params)
        case .prism:
            NotchPrismBarStyleView(params: params)
        case .nimbus:
            NotchNimbusBarStyleView(params: params)
        }
    }
}

// MARK: - 1. Classic Neon Laser Tube

private struct NotchClassicBarStyleView: View {
    let params: NotchContourBarRenderParams

    var body: some View {
        let scale = params.scale
        let spread = params.spread
        let extent = params.clampedExtent
        let energy = params.springEnergy
        let gradient = params.barGradient
        let runnerCenter = params.reduceMotion
            ? extent * 0.5
            : extent * (0.12 + 0.76 * (0.5 + 0.5 * sin(params.time * 1.85)))
        let runnerHalf = min(extent * 0.35, 0.075 * min(1.4, Double(spread)))

        ZStack {
            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    gradient.opacity(0.44 + 0.24 * energy),
                    style: StrokeStyle(lineWidth: (9.0 + 3.2 * energy) * scale * spread, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: (8.5 + 2.0 * energy) * scale * spread)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    gradient.opacity(0.92),
                    style: StrokeStyle(lineWidth: 4.0 * scale, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 2.6 * scale)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    gradient,
                    style: StrokeStyle(lineWidth: 1.9 * scale, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 0.45)

            if !params.reduceMotion, let span = params.trimmedBounds(center: runnerCenter, halfWidth: runnerHalf) {
                params.shape
                    .trim(from: span.from, to: span.to)
                    .stroke(
                        params.palette.core.color.opacity(0.82),
                        style: StrokeStyle(lineWidth: 2.8 * scale, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 1.4 * scale)
            }
        }
    }
}

// MARK: - 2. Pixelated Bayer Segmented Bar

private struct NotchPixelatedBarStyleView: View {
    let params: NotchContourBarRenderParams

    var body: some View {
        let scale = params.scale
        let spread = params.spread
        let extent = params.clampedExtent
        let energy = params.springEnergy
        let gradient = params.barGradient
        let stepFrame = params.reduceMotion ? 0 : Int(floor(params.time * 12.0))
        let cellPitch = 7.0 * scale
        let blockStyle = StrokeStyle(
            lineWidth: 3.2 * scale,
            lineCap: .butt,
            lineJoin: .miter,
            dash: [4.5 * scale, 2.5 * scale]
        )

        ZStack {
            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    gradient.opacity(0.48 + 0.22 * energy),
                    style: StrokeStyle(
                        lineWidth: (7.5 + 2.0 * energy) * scale * spread,
                        lineCap: .butt,
                        lineJoin: .miter,
                        dash: [4.5 * scale, 2.5 * scale]
                    )
                )
                .blur(radius: 5.0 * scale * spread)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(gradient.opacity(0.96), style: blockStyle)

            ForEach(0..<4, id: \.self) { lane in
                let bayerIdx = (stepFrame + lane * 11) & 63
                let threshold = NotchLightsSupport.bayer8x8[bayerIdx]
                let activeOpacity = threshold < 0.58 ? (0.45 + 0.45 * (1.0 - threshold)) : 0.14
                params.shape
                    .trim(from: 0, to: extent)
                    .stroke(
                        params.palette.core.color.opacity(activeOpacity),
                        style: StrokeStyle(
                            lineWidth: 2.2 * scale,
                            lineCap: .butt,
                            lineJoin: .miter,
                            dash: [2.2 * scale, cellPitch * 3.0 - 2.2 * scale],
                            dashPhase: CGFloat(lane) * cellPitch
                        )
                    )
            }
        }
    }
}

// MARK: - 3. Volumetric Velvet Multi-Layer Bar

private struct NotchVolumetricBarStyleView: View {
    let params: NotchContourBarRenderParams

    var body: some View {
        let scale = params.scale
        let spread = params.spread
        let extent = params.clampedExtent
        let energy = params.springEnergy

        ZStack {
            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    params.palette.trail.color.opacity(0.36 + 0.16 * energy),
                    style: StrokeStyle(lineWidth: (18.0 + 3.0 * energy) * scale * spread, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 18.0 * scale * spread)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    params.palette.lead.color.opacity(0.58 + 0.18 * energy),
                    style: StrokeStyle(lineWidth: 11.5 * scale * spread, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 10.0 * scale * spread)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    params.barGradient.opacity(0.90),
                    style: StrokeStyle(lineWidth: 5.2 * scale, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 3.6 * scale)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    params.palette.core.color.opacity(0.96),
                    style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 0.9 * scale)
        }
    }
}

// MARK: - 4. Electric Faceted Laser Rays on Bar

private struct NotchRaysBarStyleView: View {
    let params: NotchContourBarRenderParams

    var body: some View {
        let scale = params.scale
        let spread = params.spread
        let extent = params.clampedExtent
        let energy = params.springEnergy
        let phase = params.reduceMotion ? 0.0 : -params.time * 56.0

        ZStack {
            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    params.barGradient.opacity(0.46 + 0.22 * energy),
                    style: StrokeStyle(lineWidth: (7.5 + 2.5 * energy) * scale * spread, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 6.5 * scale * spread)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    params.barGradient,
                    style: StrokeStyle(lineWidth: 2.0 * scale, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 0.35)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    params.palette.core.color.opacity(0.68),
                    style: StrokeStyle(
                        lineWidth: 1.4 * scale,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [14.0 * scale, 18.0 * scale],
                        dashPhase: CGFloat(phase) * scale
                    )
                )
                .blur(radius: 0.5)

            if !params.reduceMotion {
                ForEach(0..<6, id: \.self) { idx in
                    let s = Double(idx)
                    let forward = idx.isMultiple(of: 2)
                    let speed = 0.42 + 0.16 * NotchLightsSupport.hash(s + 19.3)
                    let rawU = NotchLightsSupport.fract(params.time * speed + NotchLightsSupport.hash(s + 41.7))
                    let u = forward ? rawU : (1.0 - rawU)
                    let halfW = (0.020 + 0.025 * NotchLightsSupport.hash(s + 73.1)) * min(1.3, Double(spread))
                    let envelope = sin(rawU * .pi)
                    if envelope > 0.03, let span = params.trimmedBounds(center: u * extent, halfWidth: halfW) {
                        params.shape
                            .trim(from: span.from, to: span.to)
                            .stroke(
                                (idx.isMultiple(of: 3) ? Color.white : params.palette.core.color).opacity(0.88 * envelope),
                                style: StrokeStyle(lineWidth: 3.1 * scale, lineCap: .round, lineJoin: .round)
                            )
                            .blur(radius: 1.1)
                    }
                }
            }
        }
    }
}

// MARK: - 5. Bioluminescent Living Plasma Ribbon

private struct NotchBioluminescentBarStyleView: View {
    let params: NotchContourBarRenderParams

    var body: some View {
        let scale = params.scale
        let spread = params.spread
        let extent = params.clampedExtent
        let energy = params.springEnergy

        ZStack {
            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    params.palette.trail.color.opacity(0.42 + 0.18 * energy),
                    style: StrokeStyle(lineWidth: 11.5 * scale * spread, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 11.0 * scale * spread)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    params.barGradient.opacity(0.86),
                    style: StrokeStyle(lineWidth: 3.6 * scale, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 2.2 * scale)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    params.palette.core.color.opacity(0.58),
                    style: StrokeStyle(lineWidth: 1.3 * scale, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 0.5)

            ForEach(0..<8, id: \.self) { idx in
                let s = Double(idx)
                let baseU = (s + 0.5) / 8.0
                let drift = params.reduceMotion ? 0.0 : sin(params.time * (0.75 + 0.25 * NotchLightsSupport.hash(s + 9.2)) + s * 1.4) * 0.045
                let pulse = params.reduceMotion ? 0.8 : (0.35 + 0.65 * (0.5 + 0.5 * sin(params.time * (2.2 + NotchLightsSupport.hash(s + 31.1)) + s * 1.9)))
                let center = (baseU + drift) * extent
                if let span = params.trimmedBounds(center: center, halfWidth: 0.011) {
                    params.shape
                        .trim(from: span.from, to: span.to)
                        .stroke(
                            params.palette.lead.color.opacity(0.48 * pulse),
                            style: StrokeStyle(lineWidth: (6.5 * spread) * scale, lineCap: .round, lineJoin: .round)
                        )
                        .blur(radius: 4.5 * scale)
                    params.shape
                        .trim(from: span.from, to: span.to)
                        .stroke(
                            params.palette.core.color.opacity(0.95 * pulse),
                            style: StrokeStyle(lineWidth: (2.6 + 2.0 * pulse) * scale, lineCap: .round, lineJoin: .round)
                        )
                        .blur(radius: 1.2 * scale)
                }
            }
        }
    }
}

// MARK: - 6. Crystalline Prism Dispersion Bar

private struct NotchPrismBarStyleView: View {
    let params: NotchContourBarRenderParams

    var body: some View {
        let scale = params.scale
        let spread = params.spread
        let extent = params.clampedExtent
        let energy = params.springEnergy
        let phase = params.reduceMotion ? 0.0 : 0.06 * sin(params.time * 1.4)
        let prismGradient = LinearGradient(
            stops: [
                .init(color: params.palette.trail.color, location: 0.0),
                .init(color: Color(red: 0.22, green: 0.86, blue: 1.00), location: max(0.06, 0.22 + phase)),
                .init(color: params.palette.core.color, location: 0.50),
                .init(color: Color(red: 0.96, green: 0.42, blue: 0.88), location: min(0.94, 0.78 - phase)),
                .init(color: params.palette.lead.color, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        ZStack {
            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    prismGradient.opacity(0.55 + 0.20 * energy),
                    style: StrokeStyle(lineWidth: 10.5 * scale * spread, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 9.5 * scale * spread)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    Color(red: 0.16, green: 0.90, blue: 1.00).opacity(0.76),
                    style: StrokeStyle(lineWidth: 2.3 * scale, lineCap: .round, lineJoin: .round)
                )
                .offset(y: 0.7 * scale)
                .blur(radius: 1.5 * scale)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    Color(red: 0.98, green: 0.36, blue: 0.82).opacity(0.68),
                    style: StrokeStyle(lineWidth: 2.3 * scale, lineCap: .round, lineJoin: .round)
                )
                .offset(y: 1.5 * scale)
                .blur(radius: 1.5 * scale)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    prismGradient.opacity(0.86),
                    style: StrokeStyle(lineWidth: 3.4 * scale, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 1.8 * scale)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    Color.white.opacity(0.95),
                    style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 0.35)
        }
    }
}

// MARK: - 7. Pearlescent Nimbus Satin Bar

private struct NotchNimbusBarStyleView: View {
    let params: NotchContourBarRenderParams

    var body: some View {
        let scale = params.scale
        let spread = params.spread
        let extent = params.clampedExtent
        let energy = params.springEnergy
        let driftA = params.reduceMotion ? 0.5 : 0.5 + 0.28 * sin(params.time * 0.9)
        let driftB = 1.0 - driftA
        let satinA = LinearGradient(
            stops: [
                .init(color: params.palette.trail.color.opacity(0.45), location: 0.0),
                .init(color: params.palette.core.color, location: driftA),
                .init(color: params.palette.lead.color.opacity(0.55), location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        let satinB = LinearGradient(
            stops: [
                .init(color: params.palette.lead.color.opacity(0.50), location: 0.0),
                .init(color: params.palette.core.color, location: driftB),
                .init(color: params.palette.trail.color.opacity(0.45), location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        ZStack {
            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    params.palette.trail.color.opacity(0.48 + 0.14 * energy),
                    style: StrokeStyle(lineWidth: 16.0 * scale * spread, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 15.0 * scale * spread)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    satinA.opacity(0.66),
                    style: StrokeStyle(lineWidth: 7.5 * scale, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 5.5 * scale)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    satinB.opacity(0.48),
                    style: StrokeStyle(lineWidth: 6.0 * scale, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 5.0 * scale)

            params.shape
                .trim(from: 0, to: extent)
                .stroke(
                    params.palette.core.color.opacity(0.82),
                    style: StrokeStyle(lineWidth: 2.8 * scale, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 1.8 * scale)
        }
    }
}

// MARK: - On-Bar Ongoing Motion Modes

/// Modulates traveling highlights, waves, ripples, and sparkles strictly along `NotchBottomUShape`.
struct NotchContourMotionLayer: View {
    let params: NotchContourBarRenderParams

    var body: some View {
        if !params.reduceMotion && params.motion != .none {
            switch params.motion {
            case .none:
                EmptyView()
            case .ondulation:
                ondulationView
            case .flux:
                fluxView
            case .ripple:
                rippleView
            case .shimmer:
                shimmerView
            }
        }
    }

    private var ondulationView: some View {
        let extent = params.clampedExtent
        let strength = params.motionStrength
        let center = extent * (0.5 + 0.42 * sin(params.time * 1.9))
        let halfW = min(extent * 0.35, 0.12 * min(1.35, Double(params.spread)))
        return Group {
            if let span = params.trimmedBounds(center: center, halfWidth: halfW) {
                params.shape
                    .trim(from: span.from, to: span.to)
                    .stroke(
                        params.palette.core.color.opacity(0.62 * strength),
                        style: StrokeStyle(lineWidth: 4.8 * params.scale, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 3.4 * params.scale)
                params.shape
                    .trim(from: span.from, to: span.to)
                    .stroke(
                        Color.white.opacity(0.55 * strength),
                        style: StrokeStyle(lineWidth: 2.0 * params.scale, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 0.9)
            }
        }
    }

    private var fluxView: some View {
        let extent = params.clampedExtent
        let strength = params.motionStrength
        let halfW = min(extent * 0.25, 0.065 * min(1.35, Double(params.spread)))
        return ForEach(0..<2, id: \.self) { idx in
            let u = NotchLightsSupport.fract(params.time * 0.55 + Double(idx) * 0.5)
            let fade = sin(u * .pi)
            if fade > 0.03, let span = params.trimmedBounds(center: u * extent, halfWidth: halfW) {
                params.shape
                    .trim(from: span.from, to: span.to)
                    .stroke(
                        params.palette.core.color.opacity(0.75 * fade * strength),
                        style: StrokeStyle(lineWidth: 4.2 * params.scale, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 2.6 * params.scale)
                params.shape
                    .trim(from: span.from, to: span.to)
                    .stroke(
                        Color.white.opacity(0.70 * fade * strength),
                        style: StrokeStyle(lineWidth: 1.8 * params.scale, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 0.7)
            }
        }
    }

    private var rippleView: some View {
        let extent = params.clampedExtent
        let strength = params.motionStrength
        let mid = extent * 0.5
        let halfW = min(extent * 0.14, 0.045 * min(1.35, Double(params.spread)))
        return ForEach(0..<2, id: \.self) { idx in
            let r = NotchLightsSupport.fract(params.time * 0.62 + Double(idx) * 0.5)
            let fade = sin(r * .pi)
            if fade > 0.03 {
                if let rightSpan = params.trimmedBounds(center: mid + r * mid, halfWidth: halfW) {
                    params.shape
                        .trim(from: rightSpan.from, to: rightSpan.to)
                        .stroke(
                            params.palette.core.color.opacity(0.78 * fade * strength),
                            style: StrokeStyle(lineWidth: 3.6 * params.scale, lineCap: .round, lineJoin: .round)
                        )
                        .blur(radius: 2.0 * params.scale)
                }
                if let leftSpan = params.trimmedBounds(center: mid - r * mid, halfWidth: halfW) {
                    params.shape
                        .trim(from: leftSpan.from, to: leftSpan.to)
                        .stroke(
                            params.palette.core.color.opacity(0.78 * fade * strength),
                            style: StrokeStyle(lineWidth: 3.6 * params.scale, lineCap: .round, lineJoin: .round)
                        )
                        .blur(radius: 2.0 * params.scale)
                }
            }
        }
    }

    private var shimmerView: some View {
        let extent = params.clampedExtent
        let strength = params.motionStrength
        return ForEach(0..<7, id: \.self) { idx in
            let s = Double(idx)
            let posU = (s + 0.5 + (NotchLightsSupport.hash(s + 12.4) - 0.5) * 0.35) / 7.0
            let freq = 2.8 + NotchLightsSupport.hash(s + 57.9) * 3.4
            let phase = NotchLightsSupport.hash(s + 93.1) * .pi * 2.0
            let wave = 0.5 + 0.5 * sin(params.time * freq + phase)
            let glint = wave * wave * wave
            if glint > 0.08, let span = params.trimmedBounds(center: posU * extent, halfWidth: 0.012) {
                params.shape
                    .trim(from: span.from, to: span.to)
                    .stroke(
                        Color.white.opacity(0.92 * glint * strength),
                        style: StrokeStyle(lineWidth: (2.2 + 1.8 * glint) * params.scale, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 0.9 * params.scale)
            }
        }
    }
}
