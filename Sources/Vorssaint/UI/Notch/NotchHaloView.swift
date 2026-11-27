// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// Live animation state backing the unified notch light bar overlay panel.
final class NotchHaloViewModel: ObservableObject {
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

    var clipboardActive: Bool = false
    var clipboardPalette: NotchHaloPalette = .running
    var clipboardHoldUntil: Date = .distantPast

    var previewActive: Bool = false
    var previewPalette: NotchHaloPalette = .running
    var previewHoldUntil: Date = .distantPast

    var noticeActive: Bool = false
    var noticePalette: NotchHaloPalette = .running
    var noticeHoldUntil: Date = .distantPast

    @Published var agentActive: Bool = false
    @Published var agentPalette: NotchHaloPalette = .running
    @Published var musicActive: Bool = false
    @Published var musicPalette: NotchHaloPalette = .running

    var fullWidthLevelBars: Bool = true
    var fullWidthAgents: Bool = true
    var fullWidthMusic: Bool = true
    var fullWidthCopy: Bool = true
    var fullWidthNotices: Bool = true
    var fullWidthResting: Bool = true

    @Published var isVisible: Bool = false
    @Published var isAnimating: Bool = false

    var barEntryStart: Date = .distantPast
    var barEntryFast: Bool = false
    var barTransitionStart: Date = .distantPast
    var barTransitionFast: Bool = false
    var barTransitionPalette: NotchLevelPrismPalette = .volume

    var levelSpring = NotchFluidLevelSpring()
    var levelUpdatedAt: Date = .distantPast
    var levelHoldUntil: Date = .distantPast
    var agentAlertPalette: NotchHaloPalette? = nil
    var agentAlertHoldUntil: Date = .distantPast
    var contourState = NotchContourLineState()

    func isFullWidth(for owner: NotchContourLineOwner) -> Bool {
        switch owner {
        case .level: return fullWidthLevelBars
        case .clipboard: return fullWidthCopy
        case .preview, .notice: return fullWidthNotices
        case .agent: return fullWidthAgents
        case .music: return fullWidthMusic
        case .resting: return fullWidthResting
        }
    }

    func refreshContourTarget(at now: Date = Date()) {
        let t = now.timeIntervalSinceReferenceDate
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let levelValid = levelKind != nil && levelHoldUntil > now
        let activeLevelKind = levelValid ? levelKind : nil
        let activeClipboard = clipboardActive && clipboardHoldUntil > now
        let activePreview = previewActive && previewHoldUntil > now
        let activeNotice = noticeActive && noticeHoldUntil > now
        let agentAlertActive = agentAlertPalette != nil && agentAlertHoldUntil > now
        let anyAgentActive = agentAlertActive || agentActive
        let activeAgentPalette = (agentAlertActive ? agentAlertPalette : nil) ?? agentPalette

        let owner = NotchContourLineState.resolveOwner(
            levelKind: activeLevelKind,
            levelMuted: levelMuted,
            clipboardActive: activeClipboard,
            previewActive: activePreview,
            noticeActive: activeNotice,
            agentActive: anyAgentActive,
            musicActive: musicActive,
            restingActive: restingOutlineActive
        )
        let palette = owner.map {
            NotchContourLineState.palette(
                for: $0,
                clipboardPalette: clipboardPalette,
                previewPalette: previewPalette,
                noticePalette: noticePalette,
                agentPalette: activeAgentPalette,
                musicPalette: musicPalette,
                restingPalette: outlineTheme.palette
            )
        }
        let fullWidth = owner.map { isFullWidth(for: $0) } ?? false
        let liveLevel = levelSpring.sample(at: t, reduceMotion: reduceMotion).value
        let change = contourState.update(
            owner: owner,
            palette: palette,
            fullWidth: fullWidth,
            liveLevel: liveLevel,
            at: t,
            reduceMotion: reduceMotion
        )
        switch change {
        case .entered:
            barEntryStart = now
            barEntryFast = (owner?.isClipboard == true || owner?.isTrimmedLevel == true)
        case .transitioned:
            if transitionEffect != .off {
                barTransitionStart = now
                barTransitionFast = (owner?.isClipboard == true)
                barTransitionPalette = palette ?? contourState.targetPalette
            }
        case .none, .exited:
            break
        }
        let activeSample = contourState.sample(at: t, liveLevel: liveLevel, reduceMotion: reduceMotion)
        if owner != nil || activeSample.isActive {
            isVisible = true
            isAnimating = true
        }
    }

    func triggerClipboard(palette: NotchHaloPalette, holdDuration: TimeInterval = 0.38) {
        let now = Date()
        let alreadyClipboard = clipboardActive && clipboardHoldUntil > now
        clipboardActive = true
        clipboardPalette = palette
        clipboardHoldUntil = now.addingTimeInterval(holdDuration)
        refreshContourTarget(at: now)
        if alreadyClipboard && transitionEffect != .off {
            barTransitionStart = now
            barTransitionFast = true
            barTransitionPalette = NotchLevelPrismPalette(halo: palette)
        }
        isVisible = true
        isAnimating = true
    }

    func expireClipboard(at now: Date = Date()) {
        guard clipboardActive else { return }
        clipboardActive = false
        clipboardHoldUntil = .distantPast
        refreshContourTarget(at: now)
    }

    func triggerPreview(palette: NotchHaloPalette, holdDuration: TimeInterval = 2.4) {
        let now = Date()
        previewActive = true
        previewPalette = palette
        previewHoldUntil = now.addingTimeInterval(holdDuration)
        refreshContourTarget(at: now)
        barEntryStart = now
        barEntryFast = false
        isVisible = true
        isAnimating = true
    }

    func triggerPreviewTransitionDemo(palette: NotchHaloPalette, holdDuration: TimeInterval = 2.0) {
        let now = Date()
        previewActive = true
        previewPalette = palette
        previewHoldUntil = now.addingTimeInterval(holdDuration)
        refreshContourTarget(at: now)
        if transitionEffect != .off {
            barTransitionStart = now
            barTransitionFast = false
            barTransitionPalette = NotchLevelPrismPalette(halo: palette)
        }
        isVisible = true
        isAnimating = true
    }

    func expirePreview(at now: Date = Date()) {
        guard previewActive else { return }
        previewActive = false
        previewHoldUntil = .distantPast
        refreshContourTarget(at: now)
    }

    func triggerNoticeLight(palette: NotchHaloPalette, holdDuration: TimeInterval) {
        let now = Date()
        noticeActive = true
        noticePalette = palette
        noticeHoldUntil = now.addingTimeInterval(holdDuration)
        refreshContourTarget(at: now)
        isVisible = true
        isAnimating = true
    }

    func expireNotice(at now: Date = Date()) {
        guard noticeActive else { return }
        noticeActive = false
        noticeHoldUntil = .distantPast
        refreshContourTarget(at: now)
    }

    func triggerLevelHUD(kind: NotchLevelBarKind, level: Double, muted: Bool, holdDuration: TimeInterval = 1.9) {
        let now = Date()
        let clamped = level.isFinite ? min(1, max(0, level)) : 0
        let continuing = levelKind != nil && !levelMuted && levelHoldUntil > now
        levelSpring.retarget(to: clamped, at: now.timeIntervalSinceReferenceDate, continuing: continuing)
        levelDirection = clamped >= levelValue ? 1.0 : -1.0
        levelKind = kind
        levelValue = clamped
        levelMuted = muted
        levelUpdatedAt = now
        levelHoldUntil = now.addingTimeInterval(holdDuration)
        refreshContourTarget(at: now)
        isVisible = true
        isAnimating = true
    }

    func expireLevelHUD(at now: Date = Date()) {
        guard levelKind != nil else { return }
        levelKind = nil
        levelHoldUntil = .distantPast
        refreshContourTarget(at: now)
    }

    func triggerAgentAlert(palette: NotchHaloPalette, holdDuration: TimeInterval) {
        let now = Date()
        agentAlertPalette = palette
        agentAlertHoldUntil = now.addingTimeInterval(holdDuration)
        refreshContourTarget(at: now)
        isVisible = true
        isAnimating = true
    }

    func expireAgentAlert(at now: Date = Date()) {
        guard agentAlertPalette != nil else { return }
        agentAlertPalette = nil
        agentAlertHoldUntil = .distantPast
        refreshContourTarget(at: now)
    }

    func settleIfIdle(at now: Date = Date()) {
        var expired = false
        if levelKind != nil && levelHoldUntil <= now {
            levelKind = nil
            levelHoldUntil = .distantPast
            expired = true
        }
        if clipboardActive && clipboardHoldUntil <= now {
            clipboardActive = false
            clipboardHoldUntil = .distantPast
            expired = true
        }
        if previewActive && previewHoldUntil <= now {
            previewActive = false
            previewHoldUntil = .distantPast
            expired = true
        }
        if noticeActive && noticeHoldUntil <= now {
            noticeActive = false
            noticeHoldUntil = .distantPast
            expired = true
        }
        if agentAlertPalette != nil && agentAlertHoldUntil <= now {
            agentAlertPalette = nil
            agentAlertHoldUntil = .distantPast
            expired = true
        }
        if expired {
            refreshContourTarget(at: now)
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let sampled = contourState.sample(at: now.timeIntervalSinceReferenceDate, liveLevel: levelValue, reduceMotion: reduceMotion)
        if contourState.targetOwner == nil && !sampled.isActive {
            isVisible = false
            isAnimating = false
        }
    }

    func deactivate() {
        levelKind = nil
        levelHoldUntil = .distantPast
        clipboardActive = false
        clipboardHoldUntil = .distantPast
        previewActive = false
        previewHoldUntil = .distantPast
        noticeActive = false
        noticeHoldUntil = .distantPast
        agentActive = false
        agentAlertPalette = nil
        agentAlertHoldUntil = .distantPast
        musicActive = false
        restingOutlineActive = false
        contourState.reset()
        isVisible = false
        isAnimating = false
    }
}

/// Renders Vorssaint's unified notch-hugging or full-width light bar with all
/// styles, entrances, motions, state transitions, and strict interior masking.
struct NotchHaloView: View {
    @ObservedObject var model: NotchHaloViewModel

    private var needsHighCadence: Bool {
        if model.levelKind != nil || model.clipboardActive { return true }
        let now = Date()
        return now.timeIntervalSince(model.barEntryStart) < 0.35
            || now.timeIntervalSince(model.barTransitionStart) < 0.40
    }

    var body: some View {
        Group {
            if model.isVisible {
                TimelineView(.animation(minimumInterval: needsHighCadence ? (1.0 / 120.0) : (1.0 / 60.0), paused: !model.isAnimating)) { context in
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
        let refNow = now.timeIntervalSinceReferenceDate
        let sampledLevel = model.levelSpring.sample(at: refNow, reduceMotion: reduceMotion)
        let contourSample = model.contourState.sample(
            at: refNow,
            liveLevel: sampledLevel.value,
            reduceMotion: reduceMotion
        )

        let levelActive = model.levelKind != nil && model.levelHoldUntil > now
        let entryDuration = model.entryMode.duration(fast: model.barEntryFast)
        let entryElapsed = max(0, now.timeIntervalSince(model.barEntryStart))
        let entryProgress = (reduceMotion || entryDuration <= 0) ? 1.0 : min(1.0, entryElapsed / entryDuration)

        let transDuration = model.transitionEffect.duration(fast: model.barTransitionFast)
        let transElapsed = max(0, now.timeIntervalSince(model.barTransitionStart))
        let transProgress = (reduceMotion || transDuration <= 0) ? 1.0 : min(1.0, transElapsed / transDuration)

        let isTrimmed = model.contourState.targetOwner?.isTrimmedLevel == true
        let isResting = model.contourState.targetOwner?.isAmbientResting == true
        let motionStrength = isResting ? 0.68 : (isTrimmed ? 0.55 : 1.0)

        let settledOut = !contourSample.isActive
            && model.contourState.targetOwner == nil
            && !levelActive
            && !model.clipboardActive
            && !model.previewActive
            && !model.noticeActive

        ZStack {
            if contourSample.isActive {
                NotchContourLineOverlay(
                    islandRect: model.islandRect,
                    floatingGap: model.floatingGap,
                    palette: contourSample.palette.adapted(lightSurface: model.isLightSurface, style: model.surfaceStyle),
                    transitionPalette: model.barTransitionPalette.adapted(lightSurface: model.isLightSurface, style: model.surfaceStyle),
                    opacity: contourSample.opacity,
                    fillExtent: contourSample.fillExtent,
                    railOpacity: contourSample.railOpacity,
                    armSpan: contourSample.armSpan,
                    velocity: levelActive ? sampledLevel.velocity : 0,
                    energy: (levelActive && !model.levelMuted) ? sampledLevel.energy : 0,
                    isMutedPulseActive: levelActive && model.levelKind == .volume && model.levelMuted,
                    isTrimmedLevel: isTrimmed,
                    style: model.style,
                    armWidth: model.armWidth,
                    motion: model.motion,
                    motionStrength: motionStrength,
                    entryMode: model.entryMode,
                    entryProgress: entryProgress,
                    transitionEffect: model.transitionEffect,
                    transitionProgress: transProgress,
                    time: refNow,
                    thicknessScale: model.thicknessScale,
                    pulseElapsed: max(0, now.timeIntervalSince(model.levelUpdatedAt)),
                    reduceMotion: reduceMotion
                )
            }
        }
        // Strictly mask out Vorssaint's notch interior so glow never enters the black shell.
        .mask(NotchOutsideShellMask(islandRect: model.islandRect, floatingGap: model.floatingGap))
        .modifier(NotchLightSurfaceFinish(isLightSurface: model.isLightSurface, surfaceStyle: model.surfaceStyle))
        .onChange(of: settledOut, initial: true) { _, finished in
            if finished {
                DispatchQueue.main.async {
                    model.settleIfIdle()
                }
            }
        }
    }
}

/// Unified notch-hugging / full-screen contour bar shared across all light modes.
struct NotchContourLineOverlay: View {
    let islandRect: CGRect
    let floatingGap: CGFloat?
    let palette: NotchLevelPrismPalette
    let transitionPalette: NotchLevelPrismPalette
    let opacity: Double
    let fillExtent: Double
    let railOpacity: Double
    let armSpan: Double
    let velocity: Double
    let energy: Double
    let isMutedPulseActive: Bool
    let isTrimmedLevel: Bool
    let style: NotchHaloStyle
    let armWidth: NotchHaloArmWidth
    let motion: NotchHaloMotion
    let motionStrength: Double
    let entryMode: NotchHaloEntryMode
    let entryProgress: Double
    let transitionEffect: NotchHaloTransitionEffect
    let transitionProgress: Double
    let time: TimeInterval
    let thicknessScale: Double
    let pulseElapsed: TimeInterval
    let reduceMotion: Bool

    var body: some View {
        let shape = NotchBottomUShape(
            islandRect: islandRect,
            armRun: 0,
            fullWidthSpan: CGFloat(armSpan),
            floatingGap: floatingGap
        )
        let renderParams = NotchContourBarRenderParams(
            shape: shape,
            palette: palette,
            fillExtent: fillExtent,
            armWidth: armWidth,
            thicknessScale: thicknessScale,
            time: time,
            motion: motion,
            motionStrength: motionStrength,
            energy: energy,
            isTrimmedLevel: isTrimmedLevel,
            reduceMotion: reduceMotion
        )
        let scale = renderParams.scale
        let spread = renderParams.spread
        let extent = renderParams.clampedExtent
        let springEnergy = renderParams.springEnergy
        let activeEntry = !reduceMotion && entryProgress < 0.999
        let blastBoost = (activeEntry && entryMode == .blast)
            ? (1.0 + 0.42 * sin(min(1.0, entryProgress) * .pi))
            : 1.0

        ZStack {
            if railOpacity > 0.005 {
                shape
                    .stroke(
                        .white.opacity(0.18 * railOpacity),
                        style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round, lineJoin: .round)
                    )
            }

            if isMutedPulseActive {
                muteFrame(shape: shape, gradient: renderParams.barGradient, scale: scale, spread: spread)
            } else {
                barContent(params: renderParams, activeEntry: activeEntry, scale: scale, spread: spread)
                    .opacity(min(1.0, renderParams.ambientBreath))
                    .brightness((blastBoost - 1.0) * 0.45)

                if activeEntry {
                    entryHighlightOverlay(shape: shape, extent: extent, scale: scale)
                }

                if springEnergy > 0.02 {
                    let span = 0.05 + 0.05 * springEnergy
                    let crestFrom = velocity >= 0 ? max(0.0, extent - span) : extent
                    let crestTo = velocity >= 0 ? extent : min(1.0, extent + span)
                    shape
                        .trim(from: crestFrom, to: max(crestFrom + 0.005, crestTo))
                        .stroke(
                            .white.opacity(0.85 * springEnergy),
                            style: StrokeStyle(lineWidth: (3.4 + 1.0 * springEnergy) * scale, lineCap: .round, lineJoin: .round)
                        )
                        .blur(radius: 2.2)
                }

                if !reduceMotion && transitionEffect != .off && transitionProgress < 0.999 {
                    NotchBarTransitionOverlay(
                        shape: shape,
                        extent: extent,
                        effect: transitionEffect,
                        palette: transitionPalette,
                        progress: transitionProgress,
                        scale: scale,
                        spread: spread
                    )
                }
            }
        }
        .opacity(opacity)
    }

    @ViewBuilder
    private func barContent(params: NotchContourBarRenderParams, activeEntry: Bool,
                            scale: CGFloat, spread: CGFloat) -> some View {
        let coreBar = ZStack {
            NotchContourStyleLayer(style: style, params: params)
            NotchContourMotionLayer(params: params)
        }
        if activeEntry && entryMode == .sweep {
            let eased = 1.0 - pow(1.0 - entryProgress, 2.5)
            let mid = params.clampedExtent * 0.5
            let half = max(0.02, eased * mid)
            coreBar.mask(
                ZStack {
                    params.shape
                        .trim(from: max(0.0, mid - half), to: min(params.clampedExtent, mid + half))
                        .stroke(.white, style: StrokeStyle(lineWidth: 56.0 * scale * spread, lineCap: .round, lineJoin: .round))
                        .blur(radius: 4.0 * scale)
                }
            )
        } else if activeEntry && entryMode == .trace {
            let eased = 1.0 - pow(1.0 - entryProgress, 2.2)
            let head = max(0.02, eased * params.clampedExtent)
            coreBar.mask(
                params.shape
                    .trim(from: 0.0, to: head)
                    .stroke(.white, style: StrokeStyle(lineWidth: 56.0 * scale * spread, lineCap: .round, lineJoin: .round))
                    .blur(radius: 3.0 * scale)
            )
        } else {
            coreBar
        }
    }

    @ViewBuilder
    private func entryHighlightOverlay(shape: NotchBottomUShape, extent: Double, scale: CGFloat) -> some View {
        switch entryMode {
        case .sweep:
            let eased = 1.0 - pow(1.0 - entryProgress, 2.5)
            let mid = extent * 0.5
            let half = eased * mid
            let fade = sin(entryProgress * .pi)
            if fade > 0.03 {
                let lo = max(0.0, mid - half)
                let hi = min(extent, mid + half)
                ZStack {
                    shape
                        .trim(from: lo, to: min(extent, lo + 0.035))
                        .stroke(.white.opacity(0.88 * fade), style: StrokeStyle(lineWidth: 3.2 * scale, lineCap: .round))
                        .blur(radius: 1.2)
                    shape
                        .trim(from: max(0.0, hi - 0.035), to: hi)
                        .stroke(.white.opacity(0.88 * fade), style: StrokeStyle(lineWidth: 3.2 * scale, lineCap: .round))
                        .blur(radius: 1.2)
                }
            }
        case .trace:
            let eased = 1.0 - pow(1.0 - entryProgress, 2.2)
            let head = min(extent, max(0.02, eased * extent))
            let fade = 1.0 - entryProgress * 0.35
            shape
                .trim(from: max(0.0, head - 0.045), to: head)
                .stroke(.white.opacity(0.95 * fade), style: StrokeStyle(lineWidth: 3.6 * scale, lineCap: .round))
                .blur(radius: 1.4)
        case .blast:
            let fade = pow(1.0 - entryProgress, 1.5)
            ZStack {
                shape
                    .trim(from: 0, to: extent)
                    .stroke(palette.core.color.opacity(0.65 * fade), style: StrokeStyle(lineWidth: 8.5 * scale, lineCap: .round, lineJoin: .round))
                    .blur(radius: 5.5 * scale)
                shape
                    .trim(from: 0, to: extent)
                    .stroke(.white.opacity(0.95 * fade), style: StrokeStyle(lineWidth: 2.8 * scale, lineCap: .round, lineJoin: .round))
                    .blur(radius: 0.8)
            }
        }
    }

    @ViewBuilder
    private func muteFrame(shape: NotchBottomUShape, gradient: LinearGradient,
                           scale: CGFloat, spread: CGFloat) -> some View {
        let pulse = !reduceMotion && pulseElapsed < 0.48 ? pulseElapsed / 0.48 : 1.0
        let span = min(0.5, 0.08 + pulse * 0.42)
        ZStack {
            shape
                .stroke(
                    palette.lead.color.opacity(0.42),
                    style: StrokeStyle(lineWidth: 10.0 * scale * spread, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 9.0 * scale * spread)
            shape
                .stroke(
                    gradient.opacity(0.88),
                    style: StrokeStyle(lineWidth: 2.8 * scale, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 1.2)
            if !reduceMotion && pulse < 0.99 {
                shape
                    .trim(from: max(0, 0.5 - span), to: min(1, 0.5 + span))
                    .stroke(
                        .white.opacity((1.0 - pulse) * 0.9),
                        style: StrokeStyle(lineWidth: 4.0 * scale, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 3.0)
            }
        }
    }
}

// MARK: - On-Bar State Transition Overlay

/// Renders all 10 active state transition bursts strictly along the unified light bar path.
private struct NotchBarTransitionOverlay: View {
    let shape: NotchBottomUShape
    let extent: Double
    let effect: NotchHaloTransitionEffect
    let palette: NotchLevelPrismPalette
    let progress: Double
    let scale: CGFloat
    let spread: CGFloat

    private func clamped(_ from: Double, _ to: Double) -> (from: Double, to: Double)? {
        let lo = max(0.0, from)
        let hi = min(extent, to)
        guard hi - lo > 0.003 else { return nil }
        return (lo, hi)
    }

    var body: some View {
        let p = min(1.0, max(0.0, progress))
        let mid = extent * 0.5

        switch effect {
        case .off:
            EmptyView()

        case .hueSlide:
            let pos = extent * (1.0 - pow(1.0 - p, 2.2))
            let fade = sin(p * .pi)
            if fade > 0.02 {
                if let bodySpan = clamped(pos - 0.14 * extent, pos) {
                    shape
                        .trim(from: bodySpan.from, to: bodySpan.to)
                        .stroke(
                            palette.lead.color.opacity(0.82 * fade),
                            style: StrokeStyle(lineWidth: 5.5 * scale, lineCap: .round, lineJoin: .round)
                        )
                        .blur(radius: 3.2 * scale)
                }
                if let tipSpan = clamped(pos - 0.025 * extent, pos) {
                    shape
                        .trim(from: tipSpan.from, to: tipSpan.to)
                        .stroke(
                            Color.white.opacity(0.95 * fade),
                            style: StrokeStyle(lineWidth: 2.6 * scale, lineCap: .round, lineJoin: .round)
                        )
                        .blur(radius: 0.7)
                }
            }

        case .whiteFlash:
            let fade = pow(1.0 - p, 1.8)
            ZStack {
                shape
                    .trim(from: 0, to: extent)
                    .stroke(
                        Color.white.opacity(0.55 * fade),
                        style: StrokeStyle(lineWidth: 8.5 * scale * spread, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 5.0 * scale)
                shape
                    .trim(from: 0, to: extent)
                    .stroke(
                        Color.white.opacity(0.96 * fade),
                        style: StrokeStyle(lineWidth: 2.8 * scale, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 0.6)
            }

        case .hybrid:
            let u = 1.0 - pow(1.0 - p, 2.3)
            let fade = 1.0 - pow(p, 1.5)
            twinWave(dist: u * mid, wakeWidth: 0.11 * extent, tipWidth: 0.028 * extent,
                     color: palette.lead.color, fade: fade, lineScale: 1.0)

        case .shockwave:
            let u = 1.0 - pow(1.0 - p, 3.0)
            let fade = 1.0 - pow(p, 1.7)
            twinWave(dist: u * mid, wakeWidth: 0.048 * extent, tipWidth: 0.018 * extent,
                     color: palette.core.color, fade: fade, lineScale: 1.15)

        case .pulse:
            let beat = abs(sin(p * .pi * 2.0)) * (1.0 - p)
            ZStack {
                shape
                    .trim(from: 0, to: extent)
                    .stroke(
                        palette.core.color.opacity(0.70 * beat),
                        style: StrokeStyle(lineWidth: 7.5 * scale * spread, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 4.5 * scale)
                shape
                    .trim(from: 0, to: extent)
                    .stroke(
                        Color.white.opacity(0.90 * beat),
                        style: StrokeStyle(lineWidth: 2.6 * scale, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 0.8)
            }

        case .supernova:
            let reach = min(1.0, p * 2.1) * mid
            let fade = pow(1.0 - p, 1.35)
            if let span = clamped(mid - reach, mid + reach) {
                ZStack {
                    shape
                        .trim(from: span.from, to: span.to)
                        .stroke(
                            palette.core.color.opacity(0.85 * fade),
                            style: StrokeStyle(lineWidth: 10.0 * scale * spread, lineCap: .round, lineJoin: .round)
                        )
                        .blur(radius: 6.5 * scale)
                    shape
                        .trim(from: span.from, to: span.to)
                        .stroke(
                            Color.white.opacity(0.98 * fade),
                            style: StrokeStyle(lineWidth: 3.4 * scale, lineCap: .round, lineJoin: .round)
                        )
                        .blur(radius: 1.0)
                }
            }

        case .rings:
            ForEach(0..<3, id: \.self) { idx in
                let delay = Double(idx) * 0.16
                let rp = max(0.0, min(1.0, (p - delay) / (1.0 - delay)))
                let fade = sin(rp * .pi)
                if rp > 0.01 && fade > 0.03 {
                    twinWave(
                        dist: rp * mid,
                        wakeWidth: 0.055 * extent,
                        tipWidth: 0.020 * extent,
                        color: idx == 0 ? Color.white : palette.core.color,
                        fade: fade * (1.0 - Double(idx) * 0.15),
                        lineScale: 0.92
                    )
                }
            }

        case .prism:
            let env = sin(p * .pi)
            let disp = CGFloat(env) * 2.6 * scale
            if env > 0.02 {
                ZStack {
                    shape
                        .trim(from: 0, to: extent)
                        .stroke(Color(red: 1.0, green: 0.25, blue: 0.35).opacity(0.82 * env),
                                style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round, lineJoin: .round))
                        .offset(y: -disp)
                        .blur(radius: 1.0)
                    shape
                        .trim(from: 0, to: extent)
                        .stroke(Color(red: 0.28, green: 0.96, blue: 0.55).opacity(0.82 * env),
                                style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round, lineJoin: .round))
                        .blur(radius: 1.0)
                    shape
                        .trim(from: 0, to: extent)
                        .stroke(Color(red: 0.25, green: 0.65, blue: 1.0).opacity(0.82 * env),
                                style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round, lineJoin: .round))
                        .offset(y: disp)
                        .blur(radius: 1.0)
                }
            }

        case .strobe:
            let gate = abs(sin(p * .pi * 3.0))
            let fade = gate > 0.35 ? (1.0 - p * 0.45) : 0.08
            let alpha = fade * (1.0 - p * 0.5)
            ZStack {
                shape
                    .trim(from: 0, to: extent)
                    .stroke(
                        palette.core.color.opacity(0.75 * alpha),
                        style: StrokeStyle(lineWidth: 7.5 * scale * spread, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 3.5 * scale)
                shape
                    .trim(from: 0, to: extent)
                    .stroke(
                        Color.white.opacity(0.95 * alpha),
                        style: StrokeStyle(lineWidth: 2.8 * scale, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 0.6)
            }

        case .bigBang:
            if p < 0.28 {
                let u = p / 0.28
                let dist = (1.0 - u * u) * mid
                twinWave(dist: dist, wakeWidth: 0.07 * extent, tipWidth: 0.025 * extent,
                         color: palette.lead.color, fade: 0.5 + 0.5 * u, lineScale: 0.9)
            } else {
                let u = (p - 0.28) / 0.72
                let eased = 1.0 - pow(1.0 - u, 2.2)
                let fade = pow(1.0 - u, 1.3)
                if u < 0.22, let coreSpan = clamped(mid - 0.05 * extent, mid + 0.05 * extent) {
                    let pinch = 1.0 - u / 0.22
                    shape
                        .trim(from: coreSpan.from, to: coreSpan.to)
                        .stroke(Color.white.opacity(pinch), style: StrokeStyle(lineWidth: 6.5 * scale, lineCap: .round))
                        .blur(radius: 2.2 * scale)
                }
                twinWave(dist: eased * mid, wakeWidth: 0.13 * extent, tipWidth: 0.034 * extent,
                         color: palette.lead.color, fade: fade, lineScale: 1.25)
            }
        }
    }

    @ViewBuilder
    private func twinWave(dist: Double, wakeWidth: Double, tipWidth: Double,
                          color: Color, fade: Double, lineScale: CGFloat) -> some View {
        let mid = extent * 0.5
        let leftCenter = mid - dist
        let rightCenter = mid + dist

        if fade > 0.02 {
            ZStack {
                if let lWake = clamped(leftCenter, leftCenter + wakeWidth) {
                    shape
                        .trim(from: lWake.from, to: lWake.to)
                        .stroke(color.opacity(0.85 * fade),
                                style: StrokeStyle(lineWidth: 5.2 * scale * lineScale, lineCap: .round))
                        .blur(radius: 2.8 * scale)
                }
                if let lTip = clamped(leftCenter, leftCenter + tipWidth) {
                    shape
                        .trim(from: lTip.from, to: lTip.to)
                        .stroke(Color.white.opacity(0.98 * fade),
                                style: StrokeStyle(lineWidth: 2.8 * scale * lineScale, lineCap: .round))
                        .blur(radius: 0.6)
                }
                if let rWake = clamped(rightCenter - wakeWidth, rightCenter) {
                    shape
                        .trim(from: rWake.from, to: rWake.to)
                        .stroke(color.opacity(0.85 * fade),
                                style: StrokeStyle(lineWidth: 5.2 * scale * lineScale, lineCap: .round))
                        .blur(radius: 2.8 * scale)
                }
                if let rTip = clamped(rightCenter - tipWidth, rightCenter) {
                    shape
                        .trim(from: rTip.from, to: rTip.to)
                        .stroke(Color.white.opacity(0.98 * fade),
                                style: StrokeStyle(lineWidth: 2.8 * scale * lineScale, lineCap: .round))
                        .blur(radius: 0.6)
                }
            }
        }
    }
}
