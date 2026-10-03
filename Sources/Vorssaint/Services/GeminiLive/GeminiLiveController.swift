// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// Voice lives independently of its launcher. A window is only needed to enter a key.
@MainActor
final class GeminiLiveController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = GeminiLiveController()
    private var window: NSWindow?
    private var observers = Set<AnyCancellable>()

    override init() {
        super.init()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor in self?.close() }
            }.store(in: &observers)
        }
        DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.screenIsLocked"))
            .sink { [weak self] _ in Task { @MainActor in self?.close() } }.store(in: &observers)
    }

    func toggle(apiKey: String? = nil) {
        guard AppFeature.geminiLive.isAvailable, SessionActivity.shared.isActive else { return }
        if GeminiLiveService.shared.state == .idle { start(apiKey: apiKey) }
        else { close() }
    }

    func start(apiKey: String? = nil) {
        guard AppFeature.geminiLive.isAvailable, SessionActivity.shared.isActive,
              GeminiLiveService.shared.state == .idle else { return }
        do {
            let key = try apiKey ?? GeminiLiveKeyStore.load()
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { show(); return }
            GeminiLiveService.shared.start(apiKey: key)
            dismissSetup()
        } catch { show() }
    }

    private func dismissSetup() {
        guard let window else { return }
        window.close()
    }

    private func show(apiKey: String? = nil) {
        guard AppFeature.geminiLive.isAvailable, SessionActivity.shared.isActive else { return }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = FeatureStrings.geminiLive(L10n.shared.language).title
        window.contentMinSize = NSSize(width: 420, height: 260)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: GeminiLiveSetupView(initialKey: apiKey))
        self.window = window
        WindowActivationPolicy.retain()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        GeminiLiveService.shared.stop()
        dismissSetup()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        window = nil
        WindowActivationPolicy.release()
    }
}
