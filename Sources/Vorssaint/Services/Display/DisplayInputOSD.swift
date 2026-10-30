// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A brief overlay naming the input the shortcut switched a monitor to,
/// styled like the brightness overlay. It owns no window until first shown.
enum DisplayInputOSD {
    private static var panel: NSPanel?
    private static var dismissWork: DispatchWorkItem?
    private static var generation = 0

    static func show(displayID: CGDirectDisplayID, name: String) {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) else { return }
        let panel = ensurePanel()
        let host = NSHostingController(rootView: DisplayInputOSDView(name: name))
        panel.contentViewController = host
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2,
                              y: screen.frame.midY - size.height / 2,
                              width: size.width, height: size.height),
                       display: true)
        generation += 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = panel.isVisible ? 0 : 0.10
            panel.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()

        dismissWork?.cancel()
        let work = DispatchWorkItem { dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Releases the window entirely when display control turns off.
    static func teardown() {
        dismissWork?.cancel()
        dismissWork = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private static func dismiss() {
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
        let panel = OverlayPanel(contentRect: .zero,
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
        panel.alphaValue = 0
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications,
            .transient, .ignoresCycle,
        ]
        self.panel = panel
        return panel
    }
}

struct DisplayInputOSDView: View {
    let name: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.right.square")
                .font(.system(size: 39, weight: .regular))
                .foregroundStyle(.white.opacity(0.82))
                .frame(height: 44)
            Text(name)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 18)
        .frame(minWidth: 196, minHeight: 130)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}
