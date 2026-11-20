// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// Live animation state backing the notch laser/halo overlay panel.
final class NotchHaloViewModel: ObservableObject {
    @Published var state: NotchHaloState = .idle
    @Published var palette: NotchHaloPalette = .running
    @Published var previousPalette: NotchHaloPalette = .running

    @Published var style: NotchHaloStyle = .rays
    @Published var outlineTheme: NotchOutlineTheme = .adaptive
    @Published var restingOutlineActive: Bool = false
    @Published var armWidth: NotchHaloArmWidth = .medium
    @Published var thicknessScale: Double = 1.0
    @Published var entryMode: NotchHaloEntryMode = .sweep
    @Published var motion: NotchHaloMotion = .ondulation
    @Published var transitionEffect: NotchHaloTransitionEffect = .hybrid
    @Published var surfaceStyle: NotchLightSurfaceStyle = .neon
    @Published var isLightSurface: Bool = false

    @Published var islandRect: CGRect = CGRect(x: 178, y: 0, width: 185, height: 32)
    @Published var floatingGap: CGFloat? = nil

    @Published var levelKind: NotchLevelBarKind?
    @Published var levelValue: Double = 0
    @Published var levelMuted: Bool = false
    @Published var levelDirection: Double = 1

    @Published var isVisible: Bool = false
    @Published var isAnimating: Bool = false

    var entryStart: Date = .distantPast
    var transitionStart: Date = .distantPast
    var copySweepStart: Date = .distantPast
    var contourPulseStart: Date = .distantPast
    var ignitionStart: Date = .distantPast
    var levelSpring = NotchFluidLevelSpring()
    var levelAppearAt: Date = .distantPast
    var levelUpdatedAt: Date = .distantPast
    var levelHoldUntil: Date = .distantPast
    var autoFadeDeadline: Date?

    func beginOrTransition(to newState: NotchHaloState, palette newPalette: NotchHaloPalette, holdDuration: TimeInterval? = nil) {
        let now = Date()
        let wasIdle = state == .idle || !isVisible
        previousPalette = palette
        palette = newPalette
        state = newState
        isVisible = true
        isAnimating = true

        if wasIdle {
            entryStart = now
            if entryMode == .blast {
                ignitionStart = now
            }
        } else if transitionEffect != .off {
            transitionStart = now
        }

        autoFadeDeadline = holdDuration.map { now.addingTimeInterval($0) }
    }

    func triggerCopySweep(palette sweepPalette: NotchHaloPalette? = nil) {
        let now = Date()
        if state == .idle {
            palette = sweepPalette ?? outlineTheme.palette
            autoFadeDeadline = now.addingTimeInterval(0.56)
        }
        copySweepStart = now
        isVisible = true
        isAnimating = true
    }

    func triggerContourPulse(palette pulsePalette: NotchHaloPalette, holdDuration: TimeInterval = 1.35) {
        let now = Date()
        contourPulseStart = now
        if state == .idle || state == .copy {
            beginOrTransition(to: .running, palette: pulsePalette, holdDuration: holdDuration)
        } else if autoFadeDeadline != nil {
            beginOrTransition(to: state, palette: pulsePalette, holdDuration: holdDuration)
        }
    }

    func triggerLevelHUD(kind: NotchLevelBarKind, level: Double, muted: Bool, holdDuration: TimeInterval = 1.9) {
        let now = Date()
        let clamped = level.isFinite ? min(1, max(0, level)) : 0
        let continuing = levelKind == kind && levelHoldUntil > now
        if !continuing {
            levelAppearAt = now
        }
        levelSpring.retarget(to: clamped, at: now.timeIntervalSinceReferenceDate, continuing: continuing)
        levelDirection = clamped >= levelValue ? 1.0 : -1.0
        levelKind = kind
        levelValue = clamped
        levelMuted = muted
        levelUpdatedAt = now
        levelHoldUntil = now.addingTimeInterval(holdDuration)
        isVisible = true
        isAnimating = true
    }

    func deactivate() {
        state = .idle
        autoFadeDeadline = nil
        levelKind = nil
        levelHoldUntil = .distantPast
        let keepAmbient = restingOutlineActive
        if keepAmbient {
            palette = outlineTheme.palette
            isVisible = true
            isAnimating = true
        } else {
            isVisible = false
            isAnimating = false
        }
    }
}

/// Renders the notch halo, entrance curves, state transition bursts,
/// ignition ember particles, copy laser wipe, contour pulse, Audio/Brightness
/// prism outline gauge, and strictly masks out the black notch interior.
struct NotchHaloView: View {
    @ObservedObject var model: NotchHaloViewModel

    var body: some View {
        Group {
            if model.isVisible {
                TimelineView(.animation(minimumInterval: model.levelKind != nil ? (1.0 / 120.0) : (1.0 / 60.0), paused: !model.isAnimating)) { context in
                    frame(at: context.date)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func frame(at now: Date) -> some View {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let adapted = model.palette.adapted(lightSurface: model.isLightSurface, style: model.surfaceStyle)
        let adaptedPrev = model.previousPalette.adapted(lightSurface: model.isLightSurface, style: model.surfaceStyle)
        let themeAdapted = model.outlineTheme.palette.adapted(lightSurface: model.isLightSurface, style: model.surfaceStyle)

        let entryElapsed = max(0, now.timeIntervalSince(model.entryStart))
        let transElapsed = max(0, now.timeIntervalSince(model.transitionStart))
        let copyElapsed = max(0, now.timeIntervalSince(model.copySweepStart))
        let pulseElapsed = max(0, now.timeIntervalSince(model.contourPulseStart))
        let ignitionElapsed = max(0, now.timeIntervalSince(model.ignitionStart))
        let levelRemaining = model.levelHoldUntil.timeIntervalSince(now)
        let levelActive = model.levelKind != nil && levelRemaining > 0
        let sampledLevel = model.levelSpring.sample(at: now.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion)

        let fadeMultiplier: Double = {
            if model.state == .idle { return 0.0 }
            guard let deadline = model.autoFadeDeadline else { return 1.0 }
            let remaining = deadline.timeIntervalSince(now)
            if remaining <= 0 { return 0.0 }
            if remaining < 0.45 { return remaining / 0.45 }
            return 1.0
        }()

        let activePalette = blendedPalette(
            from: adaptedPrev,
            to: adapted,
            transElapsed: transElapsed,
            reduceMotion: reduceMotion
        )
        let armRun = model.armWidth.points
        let entryProgress = Self.entryReveal(mode: model.entryMode, elapsed: entryElapsed, reduceMotion: reduceMotion)
        let intensity = min(1.35, model.thicknessScale * entryProgress * fadeMultiplier)

        let params = NotchHaloRenderParams(
            palette: activePalette,
            islandRect: model.islandRect,
            floatingGap: model.floatingGap,
            armRun: armRun,
            thicknessScale: model.thicknessScale,
            intensity: intensity,
            time: now.timeIntervalSinceReferenceDate,
            motion: reduceMotion ? .none : model.motion
        )

        let settledOut = fadeMultiplier == 0
            && !levelActive
            && copyElapsed >= 0.52
            && pulseElapsed >= 0.85
            && (model.entryMode != .blast || ignitionElapsed >= 3.54)

        ZStack {
            if model.restingOutlineActive && intensity < 0.25 {
                restingOutlineLayer(palette: themeAdapted)
            }

            if intensity > 0.005 {
                primaryStyleLayer(params: params, entryElapsed: entryElapsed, reduceMotion: reduceMotion)
            }

            if !reduceMotion && model.entryMode == .blast && ignitionElapsed < 3.54 {
                NotchIgnitionDustView(
                    palette: adapted,
                    islandRect: model.islandRect,
                    armRun: armRun,
                    thicknessScale: model.thicknessScale,
                    elapsed: ignitionElapsed
                )
            }

            if !reduceMotion && model.transitionEffect != .off && transElapsed < 0.92 {
                NotchHaloTransitionOverlay(
                    effect: model.transitionEffect,
                    palette: adapted,
                    islandRect: model.islandRect,
                    floatingGap: model.floatingGap,
                    armRun: armRun,
                    elapsed: transElapsed
                )
            }

            if !reduceMotion && pulseElapsed < 0.85 {
                contourPulseLayer(palette: adapted, progress: pulseElapsed / 0.85)
            }

            if copyElapsed < 0.52 {
                NotchCopySweepView(
                    palette: adapted,
                    islandRect: model.islandRect,
                    floatingGap: model.floatingGap,
                    armRun: armRun,
                    progress: copyElapsed / 0.52,
                    reduceMotion: reduceMotion
                )
            }

            if let kind = model.levelKind, levelRemaining > 0 {
                let inT = min(1.0, max(0.0, now.timeIntervalSince(model.levelAppearAt) / 0.14))
                let outT = min(1.0, max(0.0, levelRemaining / 0.38))
                let smoothIn = reduceMotion ? 1.0 : inT * inT * (3.0 - 2.0 * inT)
                let smoothOut = reduceMotion ? 1.0 : outT * outT * (3.0 - 2.0 * outT)
                let fade = smoothIn * smoothOut
                NotchLevelPrismOverlay(
                    islandRect: model.islandRect,
                    floatingGap: model.floatingGap,
                    kind: kind,
                    level: sampledLevel.value,
                    muted: model.levelMuted,
                    velocity: sampledLevel.velocity,
                    energy: sampledLevel.energy,
                    thicknessScale: model.thicknessScale,
                    pulseElapsed: max(0, now.timeIntervalSince(model.levelUpdatedAt)),
                    fade: fade,
                    reduceMotion: reduceMotion
                )
            }
        }
        // Strictly mask out Vorssaint's notch interior so glow never enters the black shell.
        .mask(NotchOutsideShellMask(islandRect: model.islandRect, floatingGap: model.floatingGap))
        .modifier(NotchLightSurfaceFinish(isLightSurface: model.isLightSurface, surfaceStyle: model.surfaceStyle))
        .onChange(of: settledOut) { _, finished in
            if finished && (model.autoFadeDeadline != nil || model.levelKind != nil) {
                DispatchQueue.main.async {
                    model.deactivate()
                }
            }
        }
    }

    @ViewBuilder
    private func primaryStyleLayer(params: NotchHaloRenderParams, entryElapsed: TimeInterval, reduceMotion: Bool) -> some View {
        let styleLayer = NotchHaloStyleRenderer(style: model.style, params: params)
        if model.entryMode == .trace && entryElapsed < 0.72 && !reduceMotion {
            styleLayer.mask(traceMask(progress: entryElapsed / 0.72, armRun: params.armRun))
        } else if model.entryMode == .sweep && entryElapsed < 0.56 && !reduceMotion {
            styleLayer.mask(sweepEntranceMask(progress: entryElapsed / 0.56))
        } else {
            styleLayer
        }
    }

    @ViewBuilder
    private func restingOutlineLayer(palette: NotchHaloPalette) -> some View {
        let scale = CGFloat(model.thicknessScale)
        let shape = NotchBottomUShape(
            islandRect: model.islandRect,
            armRun: 0,
            floatingGap: model.floatingGap
        )
        ZStack {
            shape
                .stroke(palette.primary.color.opacity(0.42), style: StrokeStyle(lineWidth: 6.5 * scale, lineCap: .round, lineJoin: .round))
                .blur(radius: 6.0 * scale)
            shape
                .stroke(palette.core.color.opacity(0.82), style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round, lineJoin: .round))
                .blur(radius: 0.6)
        }
    }

    @ViewBuilder
    private func contourPulseLayer(palette: NotchHaloPalette, progress: Double) -> some View {
        let shape = NotchBottomUShape(
            islandRect: model.islandRect,
            armRun: model.armWidth.points * 0.65,
            floatingGap: model.floatingGap
        )
        shape
            .stroke(
                palette.core.color.opacity((1.0 - progress) * 0.95),
                style: StrokeStyle(lineWidth: (4.5 - 2.0 * progress) * CGFloat(model.thicknessScale), lineCap: .round, lineJoin: .round)
            )
            .blur(radius: 3.0 + progress * 6.0)
    }

    private func blendedPalette(from adaptedPrev: NotchHaloPalette, to adapted: NotchHaloPalette,
                                transElapsed: TimeInterval, reduceMotion: Bool) -> NotchHaloPalette {
        guard !reduceMotion,
              model.transitionEffect == .hueSlide || model.transitionEffect == .hybrid,
              transElapsed < 0.65 else {
            return adapted
        }
        let u = min(1, transElapsed / 0.65)
        return NotchHaloPalette(
            primary: adaptedPrev.primary.blended(with: adapted.primary, amount: u),
            secondary: adaptedPrev.secondary.blended(with: adapted.secondary, amount: u),
            core: adaptedPrev.core.blended(with: adapted.core, amount: u),
            rim: adaptedPrev.rim.blended(with: adapted.rim, amount: u)
        )
    }

    private static func entryReveal(mode: NotchHaloEntryMode, elapsed: TimeInterval, reduceMotion: Bool) -> Double {
        if reduceMotion { return min(1.0, elapsed / 0.25) }
        switch mode {
        case .sweep:
            if elapsed < 0.18 { return (elapsed / 0.18) * 0.72 }
            if elapsed < 0.51 { return 0.72 + ((elapsed - 0.18) / 0.33) * 0.28 }
            return 1.0
        case .trace:
            return min(1.0, elapsed / 0.32)
        case .blast:
            if elapsed < 0.14 { return (elapsed / 0.14) * 1.25 }
            if elapsed < 0.55 { return 1.25 - ((elapsed - 0.14) / 0.41) * 0.25 }
            return 1.0
        }
    }

    private func sweepEntranceMask(progress: Double) -> some View {
        let clamped = min(1.0, max(0.02, progress))
        let spread = 0.08 + clamped * 0.92
        return GeometryReader { proxy in
            Rectangle()
                .fill(.white)
                .frame(width: proxy.size.width * spread, height: proxy.size.height)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                .blur(radius: 16 * (1.0 - clamped))
        }
    }

    private func traceMask(progress: Double, armRun: CGFloat) -> some View {
        let u = min(1.0, max(0.0, progress))
        let halfSpan = max(0.01, u * 0.5)
        let shape = NotchBottomUShape(
            islandRect: model.islandRect,
            armRun: armRun,
            floatingGap: model.floatingGap
        )
        return ZStack {
            shape
                .trim(from: max(0, 0.5 - halfSpan), to: 0.5)
                .stroke(.white, style: StrokeStyle(lineWidth: 68, lineCap: .round))
            shape
                .trim(from: 0.5, to: min(1, 0.5 + halfSpan))
                .stroke(.white, style: StrokeStyle(lineWidth: 68, lineCap: .round))
        }
        .blur(radius: 10)
    }
}

/// Prism contour overlay for volume, brightness, and keyboard backlight levels
/// rendered strictly along the exact Vorssaint notch outline (`armRun: 0`).
struct NotchLevelPrismOverlay: View {
    let islandRect: CGRect
    let floatingGap: CGFloat?
    let kind: NotchLevelBarKind
    let level: Double
    let muted: Bool
    let velocity: Double
    let energy: Double
    let thicknessScale: Double
    let pulseElapsed: TimeInterval
    let fade: Double
    let reduceMotion: Bool

    var body: some View {
        let shape = NotchBottomUShape(islandRect: islandRect, armRun: 0, floatingGap: floatingGap)
        let prism = NotchLevelPrismPalette.palette(for: kind, muted: muted)
        let gradient = LinearGradient(
            colors: [prism.trail.color, prism.lead.color, prism.core.color],
            startPoint: .leading,
            endPoint: .trailing
        )
        let scale = CGFloat(thicknessScale)

        ZStack {
            // Subtle dim full-contour rail
            shape
                .stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round, lineJoin: .round))

            if muted && kind == .volume {
                muteFrame(shape: shape, gradient: gradient, prism: prism, scale: scale)
            } else {
                levelFrame(shape: shape, gradient: gradient, prism: prism, scale: scale)
            }
        }
        .opacity(fade)
    }

    @ViewBuilder
    private func levelFrame(shape: NotchBottomUShape, gradient: LinearGradient,
                            prism: NotchLevelPrismPalette, scale: CGFloat) -> some View {
        let clamped = min(1.0, max(0.012, level))
        let springEnergy = reduceMotion ? 0.0 : min(1.0, max(0.0, energy))

        ZStack {
            shape
                .trim(from: 0, to: clamped)
                .stroke(prism.lead.color.opacity(0.42 + 0.28 * springEnergy),
                        style: StrokeStyle(lineWidth: (10.5 + 3.5 * springEnergy) * scale, lineCap: .round, lineJoin: .round))
                .blur(radius: (10.0 + 1.5 * springEnergy) * scale)
            shape
                .trim(from: 0, to: clamped)
                .stroke(gradient, style: StrokeStyle(lineWidth: 4.8 * scale, lineCap: .round, lineJoin: .round))
                .blur(radius: 3.4 * scale)
            shape
                .trim(from: 0, to: clamped)
                .stroke(gradient, style: StrokeStyle(lineWidth: 2.35 * scale, lineCap: .round, lineJoin: .round))
                .blur(radius: 0.6)

            if springEnergy > 0.02 {
                let span = 0.05 + 0.05 * springEnergy
                let crestFrom = velocity >= 0 ? max(0.0, clamped - span) : clamped
                let crestTo = velocity >= 0 ? clamped : min(1.0, clamped + span)
                shape
                    .trim(from: crestFrom, to: max(crestFrom + 0.005, crestTo))
                    .stroke(.white.opacity(0.85 * springEnergy),
                            style: StrokeStyle(lineWidth: (3.4 + 1.0 * springEnergy) * scale, lineCap: .round, lineJoin: .round))
                    .blur(radius: 2.2)
            }
        }
    }

    @ViewBuilder
    private func muteFrame(shape: NotchBottomUShape, gradient: LinearGradient,
                           prism: NotchLevelPrismPalette, scale: CGFloat) -> some View {
        let pulse = !reduceMotion && pulseElapsed < 0.58 ? pulseElapsed / 0.58 : 1.0
        let spread = min(0.5, 0.08 + pulse * 0.42)
        ZStack {
            shape
                .stroke(prism.lead.color.opacity(0.42),
                        style: StrokeStyle(lineWidth: 10.0 * scale, lineCap: .round, lineJoin: .round))
                .blur(radius: 9.0 * scale)
            shape
                .stroke(gradient.opacity(0.88),
                        style: StrokeStyle(lineWidth: 2.8 * scale, lineCap: .round, lineJoin: .round))
                .blur(radius: 1.2)
            if !reduceMotion && pulse < 0.99 {
                shape
                    .trim(from: max(0, 0.5 - spread), to: min(1, 0.5 + spread))
                    .stroke(.white.opacity((1.0 - pulse) * 0.9),
                            style: StrokeStyle(lineWidth: 4.0 * scale, lineCap: .round, lineJoin: .round))
                    .blur(radius: 3.0)
            }
        }
    }
}

/// Drifting incandescent ember sparks emitted during Blast entrances (3.54s lifetime).
struct NotchIgnitionDustView: View {
    let palette: NotchHaloPalette
    let islandRect: CGRect
    let armRun: CGFloat
    let thicknessScale: Double
    let elapsed: TimeInterval

    var body: some View {
        Canvas { context, _ in
            let midX = Double(islandRect.midX)
            let progress = elapsed / 3.54
            let fade = max(0, 1.0 - progress * progress)
            let count = 36
            for i in 0..<count {
                let s = Double(i)
                let angle = (NotchLightsSupport.hash(s + 13.7) - 0.5) * .pi
                let speed = 35.0 + NotchLightsSupport.hash(s + 71.1) * 95.0
                let radius = (1.1 + NotchLightsSupport.hash(s + 42.3) * 1.9) * thicknessScale
                let startX = midX + (NotchLightsSupport.hash(s + 91.5) - 0.5) * Double(islandRect.width + armRun * 0.6)
                let startY = Double(islandRect.maxY + 2)
                let x = startX + sin(angle) * speed * pow(progress, 0.72)
                let y = startY + abs(cos(angle)) * speed * 0.65 * pow(progress, 0.78) + progress * progress * 18.0
                let sparkle = 0.55 + 0.45 * sin(elapsed * 14.0 + s * 2.1)
                let color = i.isMultiple(of: 3) ? palette.core.color : palette.primary.color
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(color.opacity(fade * sparkle))
                )
            }
        }
    }
}

/// Implements the 10 active transition burst visual layers when halo state shifts.
struct NotchHaloTransitionOverlay: View {
    let effect: NotchHaloTransitionEffect
    let palette: NotchHaloPalette
    let islandRect: CGRect
    let floatingGap: CGFloat?
    let armRun: CGFloat
    let elapsed: TimeInterval

    var body: some View {
        let midX = islandRect.midX
        let centerY = islandRect.maxY
        switch effect {
        case .off, .hueSlide:
            EmptyView()
        case .whiteFlash:
            let p = min(1, elapsed / 0.45)
            NotchBottomUShape(islandRect: islandRect, armRun: armRun * 0.75, floatingGap: floatingGap)
                .stroke(.white.opacity((1.0 - p) * 0.92), style: StrokeStyle(lineWidth: 6 + 10 * (1 - p), lineCap: .round, lineJoin: .round))
                .blur(radius: 6 + 8 * p)
        case .hybrid, .shockwave:
            let p = min(1, elapsed / 0.65)
            Ellipse()
                .stroke(palette.core.color.opacity((1.0 - p) * 0.9), lineWidth: max(1, 5.0 * (1.0 - p)))
                .frame(width: islandRect.width + p * (armRun * 2.2), height: islandRect.height + p * 88)
                .position(x: midX, y: centerY)
                .blur(radius: 3 + p * 6)
        case .pulse:
            let p = min(1, elapsed / 0.8)
            let beat = abs(sin(p * .pi * 2.0)) * (1.0 - p)
            NotchBottomUShape(islandRect: islandRect, armRun: armRun, floatingGap: floatingGap)
                .stroke(palette.core.color.opacity(beat * 0.85), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .blur(radius: 10)
        case .supernova, .bigBang:
            let p = min(1, elapsed / 0.82)
            let radius = (islandRect.width * 0.4 + p * (armRun + 90))
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity((1.0 - p) * 0.95), palette.primary.color.opacity((1.0 - p) * 0.65), .clear],
                        center: .center,
                        startRadius: 1,
                        endRadius: radius
                    )
                )
                .frame(width: radius * 2, height: radius * 1.1)
                .position(x: midX, y: centerY)
                .blur(radius: 6)
        case .rings:
            let p = min(1, elapsed / 0.88)
            ForEach(0..<3, id: \.self) { idx in
                let rp = max(0, min(1, (p - Double(idx) * 0.14) / 0.72))
                Ellipse()
                    .stroke(palette.primary.color.opacity((1.0 - rp) * 0.75), lineWidth: 2.5)
                    .frame(width: islandRect.width * (0.7 + rp * 1.8), height: islandRect.height * (0.8 + rp * 2.2))
                    .position(x: midX, y: centerY)
                    .blur(radius: 2 + rp * 4)
            }
        case .prism:
            let p = min(1, elapsed / 0.7)
            let colors: [Color] = [.red, .green, .blue]
            ForEach(0..<3, id: \.self) { idx in
                NotchBottomUShape(islandRect: islandRect, armRun: armRun, floatingGap: floatingGap)
                    .stroke(colors[idx].opacity((1.0 - p) * 0.75), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .offset(x: CGFloat(idx - 1) * CGFloat(p * 14.0), y: CGFloat(p * 5.0))
                    .blur(radius: 4)
            }
        case .strobe:
            let p = min(1, elapsed / 0.55)
            let gate = sin(elapsed * 42.0) > 0 ? 1.0 : 0.15
            NotchBottomUShape(islandRect: islandRect, armRun: armRun, floatingGap: floatingGap)
                .stroke(palette.core.color.opacity((1.0 - p) * gate), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .blur(radius: 4)
        }
    }
}

/// Subtle whisper hairline sweep along the notch contour when text/files are copied.
struct NotchCopySweepView: View {
    let palette: NotchHaloPalette
    let islandRect: CGRect
    let floatingGap: CGFloat?
    let armRun: CGFloat
    let progress: Double
    let reduceMotion: Bool

    var body: some View {
        let p = min(1.0, max(0.0, progress))
        let eased = reduceMotion ? 0.5 : (p < 0.5 ? 4.0 * p * p * p : 1.0 - pow(-2.0 * p + 2.0, 3.0) / 2.0)
        let alpha = sin(p * .pi)
        let hugArm = min(armRun * 0.20, 26.0)
        let shape = NotchBottomUShape(islandRect: islandRect, armRun: hugArm, floatingGap: floatingGap)
        let from = reduceMotion ? 0.0 : max(0.0, eased - 0.18)
        let to = reduceMotion ? 1.0 : min(1.0, eased + 0.03)
        ZStack {
            shape
                .trim(from: from, to: max(from + 0.01, to))
                .stroke(palette.primary.color.opacity(alpha * 0.28),
                        style: StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round))
                .blur(radius: 4.5)
            shape
                .trim(from: from, to: max(from + 0.01, to))
                .stroke(palette.core.color.opacity(alpha * 0.46),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .blur(radius: 0.9)
        }
    }
}
