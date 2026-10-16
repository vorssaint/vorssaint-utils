// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// One non-activating panel per screen. Never key, so typing in the
/// frontmost app is never interrupted; buttons take the first click.
/// Main thread only.
final class OverlayBreakDelivery: BreakDelivery {
    static let shared = OverlayBreakDelivery()
    static let secureInputWait: TimeInterval = 120

    private final class Host: NSHostingView<BreakOverlayView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private var panels: [UUID: [NSPanel]] = [:]
    private var waiting: [UUID: Timer] = [:]
    private var finishing: [UUID: [Timer]] = [:]

    /// Pause on the finished ring before closing as done.
    static let finishHold: TimeInterval = 3

    /// True while the prompt waits on secure input; decided once, in present.
    func isDeferring(id: UUID) -> Bool { waiting[id] != nil }

    func present(_ prompt: BreakPrompt, respond: @escaping (BreakAction) -> Void) -> Bool {
        if IsSecureEventInputEnabled() {
            // Wait for a password field to clear, up to 2 minutes, then show anyway.
            let started = Date()
            waiting[prompt.id] = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard !IsSecureEventInputEnabled() || Date().timeIntervalSince(started) >= Self.secureInputWait else { return }
                timer.invalidate()
                self?.waiting[prompt.id] = nil
                self?.show(prompt, respond: respond)
                BreakReminderService.shared.overlayShownLate(id: prompt.id)
            }
            return true
        }
        show(prompt, respond: respond)
        return true
    }

    func dismiss(id: UUID) {
        waiting.removeValue(forKey: id)?.invalidate()
        finishing.removeValue(forKey: id)?.forEach { $0.invalidate() }
        // Not inside the panel's own button action.
        guard let gone = panels.removeValue(forKey: id) else { return }
        DispatchQueue.main.async { gone.forEach { $0.orderOut(nil) } }
    }

    private func show(_ prompt: BreakPrompt, respond: @escaping (BreakAction) -> Void) {
        let text = FeatureStrings.breakReminders(L10n.shared.language)
        let generic = prompt.kind == .eyes ? text.eyesGeneric : text.movementGeneric
        let shownAt = Date()
        panels[prompt.id] = NSScreen.screens.map { screen in
            let panel = Panel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.contentView = Host(rootView: BreakOverlayView(
                title: prompt.activity?.text ?? generic,
                symbol: prompt.activity?.symbol ?? (prompt.kind == .eyes ? "eye" : "figure.walk"),
                kind: prompt.kind, seconds: prompt.seconds, shownAt: shownAt,
                breathing: prompt.kind == .movement
                    && UserDefaults.standard.bool(forKey: DefaultsKey.breakRemindersBreathingGuide),
                text: text, respond: respond))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            return panel
        }
        // Once per prompt, not per screen: close as done after the finished ring.
        // The end sound itself is the service's, so every style plays it.
        let length = TimeInterval(prompt.seconds)
        finishing[prompt.id] = [
            Timer.scheduledTimer(withTimeInterval: length + Self.finishHold, repeats: false) { [weak self] _ in
                guard self?.panels[prompt.id] != nil else { return }
                respond(.done)
            },
        ]
    }
}
