// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Shared presentation for brief, nonactivating confirmations.
final class TransientOSD<Content: View> {
    private var panel: NSPanel?
    private var host: NSHostingController<Content>?
    private var dismissWork: DispatchWorkItem?
    private var generation = 0

    func show(_ content: Content, on screen: NSScreen, duration: TimeInterval = 1.0) {
        precondition(Thread.isMainThread)
        let panel = ensurePanel()
        let host: NSHostingController<Content>
        if let existing = self.host {
            existing.rootView = content
            host = existing
        } else {
            host = NSHostingController(rootView: content)
            self.host = host
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
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// Releases the window entirely; the disabled feature owns no panel.
    func teardown() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.teardown() }
            return
        }
        dismissWork?.cancel()
        dismissWork = nil
        panel?.orderOut(nil)
        panel = nil
        host = nil
    }

    func dismiss() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.dismiss() }
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
            guard self.generation == dismissedGeneration else { return }
            panel.orderOut(nil)
        })
    }

    private func ensurePanel() -> NSPanel {
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
