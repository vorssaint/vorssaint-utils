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

        let resting = NotchLightsSupport.showsRestingOutline()
        viewModel.restingOutlineActive = resting
        if viewModel.state == .idle {
            viewModel.palette = theme.palette
            viewModel.isVisible = resting || viewModel.levelKind != nil
            viewModel.isAnimating = viewModel.isVisible
        } else if viewModel.state == .running && theme != .adaptive {
            viewModel.palette = theme.palette
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
        guard NotchLightsSupport.isEnabled(), NotchSupport.isEnabled(), NotchLightsSupport.tracksAgents() else {
            if viewModel.state == .running { viewModel.deactivate() }
            return
        }
        if let active = live.first {
            let palette = viewModel.outlineTheme == .adaptive
                ? Self.palette(from: active.provider.tint, fallback: .running)
                : viewModel.outlineTheme.palette
            if viewModel.state != .running || viewModel.palette != palette || viewModel.autoFadeDeadline != nil {
                viewModel.beginOrTransition(to: .running, palette: palette, holdDuration: nil)
                repositionPanel()
            }
        } else if viewModel.state == .running && viewModel.autoFadeDeadline == nil {
            viewModel.autoFadeDeadline = Date().addingTimeInterval(0.45)
        }
    }

    func triggerAgentEvent(_ event: AgentUsageEvent) {
        guard NotchLightsSupport.isEnabled(), NotchSupport.isEnabled(), NotchLightsSupport.tracksAgents() else { return }
        switch event {
        case .finished:
            viewModel.beginOrTransition(to: .success, palette: .success, holdDuration: 2.4)
            triggerEdgeWave(palette: .success)
        case .limitWarning:
            viewModel.beginOrTransition(to: .warning, palette: .warning, holdDuration: 2.8)
            triggerEdgeWave(palette: .warning)
        case .limitReset:
            viewModel.beginOrTransition(to: .success, palette: .success, holdDuration: 2.0)
            triggerEdgeWave(palette: .success)
        case .budgetReached:
            viewModel.beginOrTransition(to: .error, palette: .error, holdDuration: 3.0)
            triggerEdgeWave(palette: .error)
        }
        repositionPanel()
    }

    func updateMusic(playing: Bool, tint: NotchArtworkTint?) {
        guard NotchLightsSupport.isEnabled(), NotchSupport.isEnabled(), NotchLightsSupport.tracksMusic() else {
            if viewModel.state == .music { viewModel.deactivate() }
            return
        }
        if viewModel.state == .running && viewModel.autoFadeDeadline == nil { return }
        if playing {
            let palette: NotchHaloPalette = viewModel.outlineTheme == .adaptive
                ? (tint.map { NotchHaloPalette.matching(r: $0.red, g: $0.green, b: $0.blue) } ?? .running)
                : viewModel.outlineTheme.palette
            if viewModel.state != .music || viewModel.palette != palette {
                viewModel.beginOrTransition(to: .music, palette: palette, holdDuration: nil)
                repositionPanel()
            }
        } else if viewModel.state == .music {
            viewModel.autoFadeDeadline = Date().addingTimeInterval(0.55)
        }
    }

    func triggerCopySweep() {
        guard NotchLightsSupport.isEnabled(), NotchSupport.isEnabled(), NotchLightsSupport.tracksCopy() else { return }
        viewModel.triggerCopySweep(palette: viewModel.outlineTheme.palette)
        repositionPanel()
    }

    func triggerLevelHUD(kind: NotchLevelBarKind, level: Double, muted: Bool, holdDuration: TimeInterval = 1.9) {
        guard NotchLightsSupport.isEnabled(), NotchSupport.isEnabled(), NotchLightsSupport.tracksLevelBars() else { return }
        viewModel.triggerLevelHUD(kind: kind, level: level, muted: muted, holdDuration: holdDuration)
        repositionPanel()
    }

    func triggerNotice(_ notice: NotchNotice) {
        guard NotchLightsSupport.isEnabled(), NotchSupport.isEnabled() else { return }

        if let kind = Self.levelBarKind(for: notice.event), NotchLightsSupport.tracksLevelBars() {
            let level = notice.level ?? 0
            let muted = kind == .volume && level <= 0.001
            viewModel.triggerLevelHUD(kind: kind, level: level, muted: muted, holdDuration: max(1.5, notice.event.duration + 0.35))
            repositionPanel()
            return
        }

        // Copy uses a dedicated subtle hairline sweep, never the full halo burst.
        if notice.event == .clipboard { return }

        guard NotchLightsSupport.tracksNotices() else { return }
        let palette: NotchHaloPalette = {
            if let agent = notice.agent {
                return Self.palette(from: agent.tint, fallback: viewModel.outlineTheme.palette)
            }
            switch notice.event {
            case .battery, .timer, .watch:
                return .warning
            case .track:
                if viewModel.outlineTheme == .adaptive, let tint = NotchMusicService.shared.artworkTint {
                    return .matching(r: tint.red, g: tint.green, b: tint.blue)
                }
                return viewModel.outlineTheme.palette
            default:
                return viewModel.outlineTheme.palette
            }
        }()
        let hold = max(1.2, notice.event.duration)
        if viewModel.state == .idle {
            viewModel.beginOrTransition(to: .running, palette: palette, holdDuration: hold)
        }
        viewModel.triggerContourPulse(palette: palette, holdDuration: hold)
        if notice.event == .timer || notice.event == .watch {
            triggerEdgeWave(palette: palette)
        }
        repositionPanel()
    }

    func previewHalo() {
        syncWithPreferences()
        ensureFallbackLayout()
        viewModel.beginOrTransition(to: .running, palette: viewModel.outlineTheme.palette, holdDuration: 3.2)
        viewModel.triggerContourPulse(palette: viewModel.outlineTheme.palette, holdDuration: 3.2)
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
        repositionPanel(forceVisible: true)
    }

    func stop() {
        edgeWave.stop()
        viewModel.restingOutlineActive = false
        viewModel.deactivate()
        panel?.orderOut(nil)
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
        let layout = NotchLightsSupport.overlayLayout(
            islandScreenRect: islandScreenRect,
            floatingGap: gap,
            armRun: viewModel.armWidth.points,
            thicknessScale: viewModel.thicknessScale,
            screenScale: scale
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
