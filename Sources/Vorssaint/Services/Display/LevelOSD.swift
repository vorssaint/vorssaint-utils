// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A brief percentage overlay for a level the app moved: every brightness
/// route, and the software volume master, whose keys macOS draws nothing for.
/// The disabled feature owns no window, observer or timer.
enum LevelOSD {
    /// What the overlay draws around the level, and the shape it takes. The
    /// two follow their native counterparts rather than each other: macOS 26
    /// draws volume as a named device over a track, and that is the one the
    /// app takes over.
    enum Style: Equatable {
        /// One large glyph over the level, as the brightness overlay has
        /// always drawn it.
        case glyph(String)
        /// The horizontal panel macOS draws for volume: the output device
        /// named above a track between a quiet and a loud speaker.
        case volume(deviceName: String?)

        /// macOS' own volume overlay is part of a screenshot; the brightness
        /// one this replaces has always been left out of capture, and stays
        /// that way.
        var appearsInCaptures: Bool {
            if case .volume = self { return true }
            return false
        }
    }

    private static var panel: NSPanel?
    private static var host: NSHostingController<LevelOSDView>?
    private static var dismissWork: DispatchWorkItem?
    private static var generation = 0

    /// `displayID` names the screen the level belongs to. Volume belongs to no
    /// display, so it passes nil and lands on the focused screen, where macOS
    /// draws its own volume overlay.
    static func show(displayID: CGDirectDisplayID?, level: Double, style: Style) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                show(displayID: displayID, level: level, style: style)
            }
            return
        }
        guard let screen = displayID.flatMap({ id in
            NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                    .uint32Value == id
            }
        }) ?? NSScreen.main else { return }

        // One hosting controller for the panel's lifetime: a slider drag
        // shows dozens of updates a second, and rebuilding the SwiftUI host
        // for each would burn CPU for no visual difference.
        let panel = ensurePanel()
        let sharing: NSWindow.SharingType = style.appearsInCaptures ? .readOnly : .none
        if panel.sharingType != sharing { panel.sharingType = sharing }
        let host: NSHostingController<LevelOSDView>
        if let existing = Self.host {
            existing.rootView = LevelOSDView(level: level, style: style)
            host = existing
        } else {
            host = NSHostingController(rootView: LevelOSDView(level: level, style: style))
            Self.host = host
            panel.contentViewController = host
        }
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize
        panel.setFrame(Self.frame(for: style, size: size, on: screen), display: true)

        generation += 1
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                panel.animator().alphaValue = 1
            }
        } else {
            // A dismiss fade may be mid-flight; replacing the animation on
            // the same key is the only way to stop it from dragging the
            // fresh show back to zero.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().alphaValue = 1
            }
            panel.orderFrontRegardless()
        }

        dismissWork?.cancel()
        let work = DispatchWorkItem { dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// Each overlay lands where its native counterpart does: brightness in the
    /// middle of the display it belongs to, volume tucked under the menu bar
    /// at the right, where macOS 26 moved it — beneath the Control Center icon
    /// the level belongs to.
    private static func frame(for style: Style, size: NSSize, on screen: NSScreen) -> NSRect {
        switch style {
        case .glyph:
            return BrightnessSupport.centeredOverlayFrame(size: size, in: screen.frame)
        case .volume:
            return BrightnessSupport.cornerOverlayFrame(size: size,
                                                        in: screen.visibleFrame,
                                                        inset: cornerInset)
        }
    }

    /// Measured off the system overlay: ten points in from the right edge and
    /// thirteen below the menu bar.
    private static let cornerInset = CGSize(width: 10, height: 13)

    /// Releases the window entirely; the disabled feature owns no panel.
    static func teardown() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { teardown() }
            return
        }
        dismissWork?.cancel()
        dismissWork = nil
        panel?.orderOut(nil)
        panel = nil
        host = nil
    }

    static func dismiss() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { dismiss() }
            return
        }
        dismissWork?.cancel()
        dismissWork = nil
        guard let panel, panel.isVisible else { return }
        let dismissedGeneration = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.20
            panel.animator().alphaValue = 0
        }, completionHandler: {
            guard generation == dismissedGeneration else { return }
            panel.orderOut(nil)
        })
    }

    private static func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.sharingType = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications,
            .transient, .ignoresCycle,
        ]
        self.panel = panel
        return panel
    }
}

/// Kept separate from the transient panel so the mandatory UI preview can
/// host and inspect the exact shipped surface.
struct LevelOSDView: View {
    let level: Double
    let style: LevelOSD.Style

    private var percentage: Int {
        BrightnessSupport.wholePercent(level)
    }

    private var filledSegments: Int {
        BrightnessSupport.filledBrightnessSegments(level)
    }

    var body: some View {
        switch style {
        case .glyph(let symbol): glyphBody(symbol: symbol)
        case .volume(let deviceName): volumeBody(deviceName: deviceName)
        }
    }

    /// macOS 26's volume overlay: the output device named over a track, since
    /// the level belongs to a device the user can change, and a percentage on
    /// its own would not say which one moved.
    /// Every number here was measured off the overlay macOS 26 draws for its
    /// own volume keys, on a 1x display, in points: the panel, where the track
    /// and the icons sit inside it, and the sixteen step marks under the
    /// track. The point of this surface is to be the one the user already
    /// knows, so the measurements are the specification.
    enum VolumeMetrics {
        static let panel = CGSize(width: 294, height: 58)
        static let cornerRadius: CGFloat = 19
        /// How much of the surface is the glass filter rather than the screen
        /// behind it. Calibrated against the system overlay, which passes
        /// noticeably more detail than the filter alone does.
        /// How much of the surface is the blurred material rather than the
        /// screen behind it. The material at full strength holds back nearly
        /// all the contrast; fading it lets the screen through unfiltered,
        /// which is what the system overlay reads as.
        static let materialOpacity: Double = 0.55
        static let labelOrigin = CGPoint(x: 21, y: 7)
        static let labelSize: CGFloat = 12
        static let trackOrigin = CGPoint(x: 33, y: 36)
        static let trackWidth: CGFloat = 223
        static let trackHeight: CGFloat = 4
        /// The step marks sit this far under the track, and there is one at
        /// each end of the sixteen steps a volume key moves through.
        static let markGap: CGFloat = 3
        static let markSize: CGFloat = 2
        static let markCount = 17
        static let iconSize: CGFloat = 11
        static let quietIconCenter = CGPoint(x: 21, y: 38)
        static let loudIconCenter = CGPoint(x: 268, y: 38)
    }

    private func volumeBody(deviceName: String?) -> some View {
        let metrics = VolumeMetrics.self
        let fraction = min(max(level, 0), 1)
        return ZStack(alignment: .topLeading) {
            if let deviceName, !deviceName.isEmpty {
                Text(deviceName)
                    .font(.system(size: metrics.labelSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: metrics.panel.width - metrics.labelOrigin.x * 2,
                           alignment: .leading)
                    .offset(x: metrics.labelOrigin.x, y: metrics.labelOrigin.y)
            }

            volumeIcon("speaker.fill", at: metrics.quietIconCenter)
            volumeIcon("speaker.wave.3.fill", at: metrics.loudIconCenter)

            ZStack(alignment: .topLeading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.20))
                    .frame(width: metrics.trackWidth, height: metrics.trackHeight)
                Capsule(style: .continuous)
                    .fill(.white)
                    .frame(width: metrics.trackWidth * fraction, height: metrics.trackHeight)
                HStack(spacing: 0) {
                    ForEach(0..<metrics.markCount, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.30))
                            .frame(width: metrics.markSize, height: metrics.markSize)
                        if index < metrics.markCount - 1 { Spacer(minLength: 0) }
                    }
                }
                .frame(width: metrics.trackWidth, height: metrics.markSize)
                .offset(y: metrics.trackHeight + metrics.markGap)
            }
            .offset(x: metrics.trackOrigin.x, y: metrics.trackOrigin.y)
        }
        .frame(width: metrics.panel.width, height: metrics.panel.height, alignment: .topLeading)
        .background(VolumeOverlayBackdrop(cornerRadius: metrics.cornerRadius))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(deviceName ?? "\(percentage)%")
        .accessibilityValue("\(percentage)%")
    }

    private func volumeIcon(_ symbol: String, at center: CGPoint) -> some View {
        Image(systemName: symbol)
            .font(.system(size: VolumeMetrics.iconSize, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 20, height: 20)
            .offset(x: center.x - 10, y: center.y - 10)
    }

    private func glyphBody(symbol: String) -> some View {
        VStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 39, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white.opacity(0.82))
                .frame(height: 44)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(percentage)")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.52))
            }
            .frame(height: 36)

            HStack(spacing: 2) {
                ForEach(0..<16, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(index < filledSegments
                              ? Color.white.opacity(0.70)
                              : Color.white.opacity(0.12))
                }
            }
            .frame(width: 152, height: 7)
        }
        .frame(width: 196, height: 154)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percentage)%")
        .accessibilityValue("\(percentage)%")
    }
}


/// The volume overlay's surface, kept apart from the app's own panels because
/// it stands in for a system overlay rather than matching the app.
///
/// A blurred material faded over the screen, not Liquid Glass: glass refracts
/// what is behind it inside the window, a borderless panel has nothing there,
/// and the effect flattens into frost. Measured against the system overlay,
/// this passes the detail that reads as transparent without the effect's cost.
private struct VolumeOverlayBackdrop: View {
    var cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.clear)
            .background(
                HUDBackdropMaterial(
                    cornerRadius: cornerRadius,
                    opacity: reduceTransparency ? 1 : LevelOSDView.VolumeMetrics.materialOpacity)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
            )
    }
}
