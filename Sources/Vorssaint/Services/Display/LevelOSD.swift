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
            return NSRect(x: screen.frame.midX - size.width / 2,
                          y: screen.frame.midY - size.height / 2,
                          width: size.width, height: size.height)
        case .volume:
            // visibleFrame, so the panel clears the menu bar (and the notch's
            // taller one) instead of a hardcoded height that is wrong on half
            // the Macs.
            let area = screen.visibleFrame
            return NSRect(x: area.maxX - size.width - cornerInset,
                          y: area.maxY - size.height - cornerInset,
                          width: size.width, height: size.height)
        }
    }

    private static let cornerInset: CGFloat = 10

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
    private func volumeBody(deviceName: String?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let deviceName, !deviceName.isEmpty {
                Text(deviceName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))

                GeometryReader { geometry in
                    let width = geometry.size.width
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.20))
                        .overlay(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(.white)
                                .frame(width: max(width * min(max(level, 0), 1), 0))
                        }
                }
                .frame(height: 24)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 285)
        .background(HUDBackdrop(cornerRadius: 20))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(deviceName ?? "")
        .accessibilityValue("\(percentage)%")
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
