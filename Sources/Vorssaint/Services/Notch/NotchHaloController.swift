// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation
import SwiftUI

/// Orchestrates the click-through halo NSPanel directly behind Vorssaint's notch
/// island and triggers the screen-edge Metal wave on agent completions, volume
/// and brightness adjustments, music playback, clipboard copies, and Settings previews.
final class NotchHaloController {
    static let shared = NotchHaloController()

    private let viewModel = NotchHaloViewModel()
    private let surfaceProbe = NotchLightSurfaceProbe()
    private let edgeWave = NotchEdgeWaveController()
    private var panel: NSPanel?
    private var hostingView: NSHostingView<NotchHaloView>?
    private var cancellables: Set<AnyCancellable> = []

    private weak var attachedHost: NotchWindowHost?
    private var lastIslandScreenRect: CGRect?
    private var lastFloatingGap: CGFloat? = nil
    private var lastGeometry: NotchGeometry?
    private var lastClosedSize = CGSize(width: 185, height: 32)
    private var lastNotchWindowNumber: Int?
    private var lastVisible = false
    private var lastFullscreenHidden = false
    private weak var lastScreen: NSScreen?

    private var hasSyncedPreferences = false
    private var lastMusicPlaying = false
    private var lastMusicTint: NotchArtworkTint?
    private var lastAgentRunning = false
    private var lastAgentTint: Color?
    private var levelExpiryWork: DispatchWorkItem?
    private var clipboardExpiryWork: DispatchWorkItem?
    private var previewExpiryWork: DispatchWorkItem?
    private var previewTransitionWork: DispatchWorkItem?
    private var noticeExpiryWork: DispatchWorkItem?
    private var agentAlertExpiryWork: DispatchWorkItem?

    private init() {
        surfaceProbe.$isLightSurface
            .receive(on: DispatchQueue.main)
            .sink { [weak self] light in
                self?.viewModel.isLightSurface = light
            }
            .store(in: &cancellables)

        viewModel.$isVisible
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                if !visible {
                    self?.panel?.orderOut(nil)
                }
            }
            .store(in: &cancellables)

        syncWithPreferences()
    }

    func attach(to host: NotchWindowHost) {
        if attachedHost !== host {
            attachedHost = host
            if let panel {
                host.attachBackgroundOverlay(panel)
            }
            host.onSilhouetteChange = { [weak self] rect, gap, windowNumber, _, screen in
                guard let self else { return }
                self.lastIslandScreenRect = rect
                self.lastFloatingGap = gap
                self.lastNotchWindowNumber = windowNumber
                if let screen { self.lastScreen = screen }
                self.repositionPanel()
            }
        }
    }

    func syncWithPreferences() {
        let oldEntry = viewModel.entryMode
        let oldTransition = viewModel.transitionEffect
        let wasSynced = hasSyncedPreferences
        hasSyncedPreferences = true

        viewModel.style = NotchLightsSupport.style()
        let theme = NotchLightsSupport.outlineTheme()
        viewModel.outlineTheme = theme
        viewModel.armWidth = NotchLightsSupport.armWidth()
        viewModel.thicknessScale = NotchLightsSupport.thickness()
        viewModel.entryMode = NotchLightsSupport.entryMode()
        viewModel.motion = NotchLightsSupport.motion()
        viewModel.transitionEffect = NotchLightsSupport.transitionEffect()
        viewModel.surfaceStyle = NotchLightsSupport.lightSurfaceStyle()
        viewModel.isLightSurface = surfaceProbe.isLightSurface

        guard NotchLightsSupport.isEnabled(), NotchSupport.isEnabled() else {
            viewModel.restingOutlineActive = false
            stop()
            return
        }

        viewModel.restingOutlineActive = NotchLightsSupport.showsRestingOutline()
        viewModel.fullWidthLevelBars = NotchLightsSupport.fullWidthLevelBars()
        viewModel.fullWidthAgents = NotchLightsSupport.fullWidthAgents()
        viewModel.fullWidthMusic = NotchLightsSupport.fullWidthMusic()
        viewModel.fullWidthCopy = NotchLightsSupport.fullWidthCopy()
        viewModel.fullWidthNotices = NotchLightsSupport.fullWidthNotices()
        viewModel.fullWidthResting = NotchLightsSupport.fullWidthResting()
        viewModel.agentActive = lastAgentRunning && NotchLightsSupport.tracksAgents()
        viewModel.agentPalette = resolvedAgentPalette(tint: lastAgentTint, theme: theme)
        viewModel.musicActive = lastMusicPlaying && NotchLightsSupport.tracksMusic()
        viewModel.musicPalette = resolvedMusicPalette(tint: lastMusicTint, theme: theme)
        if viewModel.previewActive {
            viewModel.previewPalette = theme.palette
        }

        viewModel.refreshContourTarget(at: Date())

        if wasSynced && viewModel.isVisible && viewModel.contourState.targetOwner != nil {
            let now = Date()
            if viewModel.entryMode != oldEntry {
                viewModel.barEntryStart = now
                viewModel.barEntryFast = false
            }
            if viewModel.transitionEffect != oldTransition && viewModel.transitionEffect != .off {
                viewModel.barTransitionStart = now
                viewModel.barTransitionFast = false
                viewModel.barTransitionPalette = viewModel.contourState.targetPalette
            }
        }

        repositionPanel()
    }

    func updateLayout(geometry: NotchGeometry, closedSize: CGSize, notchWindowNumber: Int?,
                      visible: Bool, fullscreenHidden: Bool, screen: NSScreen?) {
        lastGeometry = geometry
        lastClosedSize = closedSize
        lastNotchWindowNumber = notchWindowNumber
        lastVisible = visible
        lastFullscreenHidden = fullscreenHidden
        lastScreen = screen

        if lastIslandScreenRect == nil || attachedHost == nil {
            lastIslandScreenRect = geometry.frame(for: closedSize)
            lastFloatingGap = geometry.floatingGap
        }
        repositionPanel()
    }

    func updateAgentSessions(_ live: [AgentLiveSession]) {
        lastAgentRunning = !live.isEmpty
        lastAgentTint = live.first?.provider.tint
        let active = lastAgentRunning
            && NotchLightsSupport.isEnabled()
            && NotchSupport.isEnabled()
            && NotchLightsSupport.tracksAgents()
        viewModel.agentActive = active
        if active {
            viewModel.agentPalette = resolvedAgentPalette(tint: lastAgentTint, theme: viewModel.outlineTheme)
        }
        viewModel.refreshContourTarget(at: Date())
        repositionPanel()
    }

    func triggerAgentEvent(_ event: AgentUsageEvent) {
        guard NotchLightsSupport.isEnabled(), NotchSupport.isEnabled(), NotchLightsSupport.tracksAgents() else { return }
        switch event {
        case .finished:
            viewModel.triggerAgentAlert(palette: .success, holdDuration: 2.4)
            scheduleExpiry(&agentAlertExpiryWork, after: 2.4) { $0.expireAgentAlert(at: Date()) }
            triggerEdgeWave(palette: .success)
        case .limitWarning:
            viewModel.triggerAgentAlert(palette: .warning, holdDuration: 2.8)
            scheduleExpiry(&agentAlertExpiryWork, after: 2.8) { $0.expireAgentAlert(at: Date()) }
            triggerEdgeWave(palette: .warning)
        case .limitReset:
            viewModel.triggerAgentAlert(palette: .success, holdDuration: 2.0)
            scheduleExpiry(&agentAlertExpiryWork, after: 2.0) { $0.expireAgentAlert(at: Date()) }
            triggerEdgeWave(palette: .success)
        case .budgetReached:
            viewModel.triggerAgentAlert(palette: .error, holdDuration: 3.0)
            scheduleExpiry(&agentAlertExpiryWork, after: 3.0) { $0.expireAgentAlert(at: Date()) }
            triggerEdgeWave(palette: .error)
        }
        repositionPanel()
    }

    func updateMusic(playing: Bool, tint: NotchArtworkTint?) {
        lastMusicPlaying = playing
        lastMusicTint = tint
        let active = playing && NotchLightsSupport.isEnabled() && NotchSupport.isEnabled() && NotchLightsSupport.tracksMusic()
        viewModel.musicActive = active
        if active {
            viewModel.musicPalette = resolvedMusicPalette(tint: tint, theme: viewModel.outlineTheme)
        }
        viewModel.refreshContourTarget(at: Date())
        repositionPanel()
    }

    func triggerCopySweep() {
        guard NotchLightsSupport.isEnabled(), NotchSupport.isEnabled(), NotchLightsSupport.tracksCopy() else { return }
        let hold: TimeInterval = 0.38
        viewModel.triggerClipboard(palette: viewModel.outlineTheme.palette, holdDuration: hold)
        scheduleExpiry(&clipboardExpiryWork, after: hold) { $0.expireClipboard(at: Date()) }
        repositionPanel()
    }

    func triggerLevelHUD(kind: NotchLevelBarKind, level: Double, muted: Bool, holdDuration: TimeInterval = 1.9) {
        guard NotchLightsSupport.isEnabled(), NotchSupport.isEnabled(), NotchLightsSupport.tracksLevelBars() else { return }
        viewModel.triggerLevelHUD(kind: kind, level: level, muted: muted, holdDuration: holdDuration)
        scheduleExpiry(&levelExpiryWork, after: holdDuration) { $0.expireLevelHUD(at: Date()) }
        repositionPanel()
    }

    func triggerNotice(_ notice: NotchNotice) {
        guard NotchLightsSupport.isEnabled(), NotchSupport.isEnabled() else { return }

        if let kind = Self.levelBarKind(for: notice.event), NotchLightsSupport.tracksLevelBars() {
            let level = notice.level ?? 0
            let muted = kind == .volume && level <= 0.001
            let hold = max(1.5, notice.event.duration + 0.35)
            viewModel.triggerLevelHUD(kind: kind, level: level, muted: muted, holdDuration: hold)
            scheduleExpiry(&levelExpiryWork, after: hold) { $0.expireLevelHUD(at: Date()) }
            repositionPanel()
            return
        }

        // Copy and music track changes use clipboard / contour line handlers, never notices.
        if notice.event == .clipboard || notice.event == .track { return }

        guard NotchLightsSupport.tracksNotices() else { return }
        let palette: NotchHaloPalette = {
            if let agent = notice.agent {
                return Self.palette(from: agent.tint, fallback: viewModel.outlineTheme.palette)
            }
            switch notice.event {
            case .battery, .timer, .watch:
                return .warning
            default:
                return viewModel.outlineTheme.palette
            }
        }()
        let hold = max(1.2, notice.event.duration)
        viewModel.triggerNoticeLight(palette: palette, holdDuration: hold)
        scheduleExpiry(&noticeExpiryWork, after: hold) { $0.expireNotice(at: Date()) }
        if notice.event == .timer || notice.event == .watch {
            triggerEdgeWave(palette: palette)
        }
        repositionPanel()
    }

    func previewHalo() {
        syncWithPreferences()
        ensureFallbackLayout()
        previewTransitionWork?.cancel()
        previewTransitionWork = nil

        let theme = viewModel.outlineTheme
        let basePalette = theme.palette
        let demoPalette = Self.alternatePreviewPalette(for: theme)

        if viewModel.previewActive && viewModel.previewHoldUntil > Date() {
            let target = viewModel.previewPalette == basePalette ? demoPalette : basePalette
            viewModel.triggerPreviewTransitionDemo(palette: target, holdDuration: 2.0)
            scheduleExpiry(&previewExpiryWork, after: 2.0) { $0.expirePreview(at: Date()) }
        } else {
            viewModel.triggerPreview(palette: basePalette, holdDuration: 2.4)
            scheduleExpiry(&previewExpiryWork, after: 2.4) { $0.expirePreview(at: Date()) }
            if viewModel.transitionEffect != .off {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.previewTransitionWork = nil
                    guard self.viewModel.previewActive else { return }
                    self.viewModel.triggerPreviewTransitionDemo(palette: demoPalette, holdDuration: 1.55)
                    self.repositionPanel(forceVisible: true)
                }
                previewTransitionWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: work)
            }
        }
        repositionPanel(forceVisible: true)
    }

    func previewEdgeWave() {
        syncWithPreferences()
        ensureFallbackLayout()
        guard let screen = lastScreen ?? NSScreen.main,
              let geometry = lastGeometry else { return }
        edgeWave.trigger(
            palette: viewModel.outlineTheme.palette,
            on: screen,
            geometry: geometry,
            closedSize: lastClosedSize,
            inward: false,
            lightSurface: surfaceProbe.isLightSurface
        )
    }

    func previewLevelBar(_ kind: NotchLevelBarKind) {
        syncWithPreferences()
        ensureFallbackLayout()
        viewModel.triggerLevelHUD(kind: kind, level: kind == .volume ? 0.68 : 0.75, muted: false, holdDuration: 2.2)
        scheduleExpiry(&levelExpiryWork, after: 2.2) { $0.expireLevelHUD(at: Date()) }
        repositionPanel(forceVisible: true)
    }

    func stop() {
        levelExpiryWork?.cancel()
        levelExpiryWork = nil
        clipboardExpiryWork?.cancel()
        clipboardExpiryWork = nil
        previewExpiryWork?.cancel()
        previewExpiryWork = nil
        previewTransitionWork?.cancel()
        previewTransitionWork = nil
        noticeExpiryWork?.cancel()
        noticeExpiryWork = nil
        agentAlertExpiryWork?.cancel()
        agentAlertExpiryWork = nil
        edgeWave.stop()
        viewModel.deactivate()
        panel?.orderOut(nil)
    }

    private func scheduleExpiry(_ slot: inout DispatchWorkItem?, after holdDuration: TimeInterval,
                                action: @escaping (NotchHaloViewModel) -> Void) {
        slot?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            action(self.viewModel)
            self.repositionPanel()
        }
        slot = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration + 0.01, execute: work)
    }

    private func resolvedAgentPalette(tint: Color?, theme: NotchOutlineTheme) -> NotchHaloPalette {
        theme == .adaptive
            ? (tint.map { Self.palette(from: $0, fallback: .running) } ?? .running)
            : theme.palette
    }

    private func resolvedMusicPalette(tint: NotchArtworkTint?, theme: NotchOutlineTheme) -> NotchHaloPalette {
        theme == .adaptive
            ? (tint.map { NotchHaloPalette.matching(r: $0.red, g: $0.green, b: $0.blue) } ?? .running)
            : theme.palette
    }

    private static func alternatePreviewPalette(for theme: NotchOutlineTheme) -> NotchHaloPalette {
        switch theme {
        case .adaptive, .cyan, .monochrome:
            return NotchOutlineTheme.prism.palette
        case .prism:
            return NotchOutlineTheme.aurora.palette
        case .aurora, .emerald:
            return NotchOutlineTheme.sunlight.palette
        case .sunlight, .crimson:
            return .running
        }
    }

    // MARK: Internal layout & windowing

    private func triggerEdgeWave(palette: NotchHaloPalette, inward: Bool = false) {
        guard NotchLightsSupport.edgeWaveEnabled() else { return }
        ensureFallbackLayout()
        guard let screen = lastScreen ?? NSScreen.main,
              let geometry = lastGeometry else { return }
        edgeWave.trigger(
            palette: palette,
            on: screen,
            geometry: geometry,
            closedSize: lastClosedSize,
            inward: inward,
            lightSurface: surfaceProbe.isLightSurface
        )
    }

    private func ensureFallbackLayout() {
        if lastGeometry == nil, let screen = NSScreen.main {
            let safeTop = screen.safeAreaInsets.top
            let camWidth: CGFloat = safeTop > 0 ? 185 : 180
            let silhouette = NotchSilhouette(
                rawValue: UserDefaults.standard.string(forKey: DefaultsKey.notchSilhouette) ?? ""
            ) ?? .capsule
            let geom = NotchGeometry(
                screen: screen.frame,
                safeAreaTop: safeTop,
                cameraWidth: camWidth,
                layout: .compact,
                menuBarHeight: max(24, safeTop),
                silhouette: silhouette
            )
            lastGeometry = geom
            lastScreen = screen
            lastClosedSize = geom.restingSize(showsContent: false)
            lastIslandScreenRect = geom.frame(for: lastClosedSize)
            lastFloatingGap = geom.floatingGap
        }
    }

    private func repositionPanel(forceVisible: Bool = false) {
        let islandScreenRect: CGRect
        let gap: CGFloat?
        if let rect = lastIslandScreenRect {
            islandScreenRect = rect
            gap = lastFloatingGap
        } else if let geometry = lastGeometry {
            islandScreenRect = geometry.frame(for: lastClosedSize)
            gap = geometry.floatingGap
        } else {
            return
        }

        let scale = (lastScreen ?? NSScreen.main)?.backingScaleFactor ?? 2.0
        let screenFrame = (lastScreen ?? NSScreen.main)?.frame ?? lastGeometry?.screen
        let wantsFullWidth = NotchLightsSupport.anyFullWidthEnabled()
            || viewModel.contourState.usesFullWidth(at: Date().timeIntervalSinceReferenceDate)
        let layout = NotchLightsSupport.overlayLayout(
            islandScreenRect: islandScreenRect,
            floatingGap: gap,
            armRun: viewModel.armWidth.points,
            thicknessScale: viewModel.thicknessScale,
            screenScale: scale,
            screenFrame: screenFrame,
            fullWidth: wantsFullWidth
        )

        let pan = ensurePanel(frame: layout.overlayScreenRect)
        pan.setFrame(layout.overlayScreenRect, display: false)
        hostingView?.frame = CGRect(origin: .zero, size: layout.overlayScreenRect.size)
        viewModel.islandRect = layout.islandRect
        viewModel.floatingGap = layout.floatingGap

        let shouldShow = (forceVisible || (lastVisible && !lastFullscreenHidden))
            && NotchLightsSupport.isEnabled()
            && viewModel.isVisible

        if let host = attachedHost {
            host.orderBackgroundOverlay(pan, visible: shouldShow)
            return
        }

        guard shouldShow else {
            pan.orderOut(nil)
            return
        }
        pan.level = NotchPanel.normalLevel
        if let notchWin = lastNotchWindowNumber, notchWin > 0 {
            pan.order(.below, relativeTo: notchWin)
        } else {
            pan.orderFrontRegardless()
        }
    }

    private func ensurePanel(frame: CGRect) -> NSPanel {
        if let panel { return panel }
        let pan = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        pan.isReleasedWhenClosed = false
        pan.ignoresMouseEvents = true
        pan.isOpaque = false
        pan.backgroundColor = .clear
        pan.hasShadow = false
        pan.level = NotchPanel.normalLevel
        pan.collectionBehavior = NotchPanel.overlayCollectionBehavior
        let hosting = NSHostingView(rootView: NotchHaloView(model: viewModel))
        hosting.frame = CGRect(origin: .zero, size: frame.size)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        pan.contentView = hosting
        attachedHost?.attachBackgroundOverlay(pan)
        self.panel = pan
        self.hostingView = hosting
        return pan
    }

    private static func levelBarKind(for event: NotchEvent) -> NotchLevelBarKind? {
        switch event {
        case .volume: return .volume
        case .brightness: return .brightness
        case .keyboardLight: return .keyboardLight
        default: return nil
        }
    }

    private static func palette(from color: Color, fallback: NotchHaloPalette) -> NotchHaloPalette {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return fallback }
        return NotchHaloPalette.matching(
            r: Double(ns.redComponent),
            g: Double(ns.greenComponent),
            b: Double(ns.blueComponent)
        )
    }
}
