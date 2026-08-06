// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Small floating confirmation used by the quick tools (color picked, text
/// copied, mic muted): a non-activating panel near the top of the screen with
/// the mouse, fading out on its own. Purely visual; never takes focus.
enum QuickToolHUD {
    private static var panel: NSPanel?
    private static var scrollingPanel: NSPanel?
    private static var dismissWork: DispatchWorkItem?
    /// Bumped by every show(). A dismiss whose fade-out was overtaken by a
    /// newer show() must not order the panel out from its completion handler.
    private static var generation = 0

    /// The confirmation panel, when one is on screen. A recording in progress
    /// leaves it out of the picture; nothing else needs to know it exists.
    static var currentWindowNumber: Int? {
        guard let panel, panel.isVisible else { return nil }
        return panel.windowNumber
    }

    /// The scrolling capture controls, when they are on screen. They belong to
    /// the capture in progress and must stay out of its own pictures.
    static var currentScrollingWindowNumber: Int? {
        guard let scrollingPanel, scrollingPanel.isVisible else { return nil }
        return scrollingPanel.windowNumber
    }

    static func show(icon: String, message: String, swatch: NSColor? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { show(icon: icon, message: message, swatch: swatch) }
            return
        }
        let content = HStack(spacing: 8) {
            if let swatch {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: swatch))
                    .frame(width: 18, height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
                    )
            } else {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text(message)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        present(AnyView(content), dismissAfter: 1.5)
    }

    static func showCountdown(_ value: Int) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { showCountdown(value) }
            return
        }
        let content = ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            Circle()
                .trim(from: 0.04, to: 0.96)
                .stroke(Color.accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(6)
            Text("\(value)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 82, height: 82)
        .background(.regularMaterial, in: Circle())
        .padding(12)

        present(AnyView(content), dismissAfter: 0.92, windowShadow: false)
    }

    /// The scrolling capture stays visible and controllable while the target
    /// keeps moving. The panel does not activate the app, so clicking either
    /// action never steals focus from the page being captured.
    static func showScrollingCapture(message: String,
                                     finishTitle: String,
                                     cancelTitle: String,
                                     onFinish: @escaping () -> Void,
                                     onCancel: @escaping () -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                showScrollingCapture(message: message,
                                     finishTitle: finishTitle,
                                     cancelTitle: cancelTitle,
                                     onFinish: onFinish,
                                     onCancel: onCancel)
            }
            return
        }
        let content = HStack(spacing: 10) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
            Button(cancelTitle, action: onCancel)
                .controlSize(.small)
            Button(finishTitle, action: onFinish)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        let host = NSHostingController(rootView: AnyView(content))
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize
        let panel = ensureScrollingPanel()
        panel.contentViewController = host
        let frame = NSScreen.pointerVisibleFrame
        panel.setFrame(NSRect(x: frame.midX - size.width / 2,
                              y: frame.maxY - size.height - 24,
                              width: size.width,
                              height: size.height),
                       display: true)
        panel.orderFrontRegardless()
    }

    static func dismissScrollingCapture() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { dismissScrollingCapture() }
            return
        }
        scrollingPanel?.orderOut(nil)
    }

    private static func present(_ content: AnyView,
                                dismissAfter: Double,
                                windowShadow: Bool = true) {
        let host = NSHostingController(rootView: content)
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize

        let panel = ensurePanel()
        panel.hasShadow = windowShadow
        panel.contentViewController = host

        let frame = NSScreen.pointerVisibleFrame
        panel.setFrame(NSRect(x: frame.midX - size.width / 2,
                              y: frame.maxY - size.height - 24,
                              width: size.width,
                              height: size.height),
                       display: true)
        generation += 1
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        dismissWork?.cancel()
        let work = DispatchWorkItem { dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissAfter, execute: work)
    }

    private static func dismiss() {
        guard let panel else { return }
        let dismissed = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        }, completionHandler: {
            guard generation == dismissed else { return }
            panel.orderOut(nil)
        })
    }

    private static func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = makePanel()
        self.panel = panel
        return panel
    }

    private static func ensureScrollingPanel() -> NSPanel {
        if let scrollingPanel { return scrollingPanel }
        let panel = makePanel()
        panel.ignoresMouseEvents = false
        scrollingPanel = panel
        return panel
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return panel
    }
}
