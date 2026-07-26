// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A brief percentage overlay for every brightness route. The disabled
/// feature owns no window, observer or timer.
enum BrightnessOSD {
    private static var panel: NSPanel?
    private static var host: NSHostingController<BrightnessOSDView>?
    private static var dismissWork: DispatchWorkItem?
    private static var generation = 0

    static func show(displayID: CGDirectDisplayID, brightness: Double) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                show(displayID: displayID, brightness: brightness)
            }
            return
        }
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayID
        }) else { return }

        // One hosting controller for the panel's lifetime: a slider drag
        // shows dozens of updates a second, and rebuilding the SwiftUI host
        // for each would burn CPU for no visual difference.
        let panel = ensurePanel()
        let host: NSHostingController<BrightnessOSDView>
        if let existing = Self.host {
            existing.rootView = BrightnessOSDView(brightness: brightness)
            host = existing
        } else {
            host = NSHostingController(rootView: BrightnessOSDView(brightness: brightness))
            Self.host = host
            panel.contentViewController = host
        }
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2,
                              y: screen.frame.midY - size.height / 2,
                              width: size.width, height: size.height),
                       display: true)

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
struct BrightnessOSDView: View {
    let brightness: Double

    private var percentage: Int {
        BrightnessSupport.wholePercent(brightness)
    }

    private var filledSegments: Int {
        BrightnessSupport.filledBrightnessSegments(brightness)
    }

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: "sun.max.fill")
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
