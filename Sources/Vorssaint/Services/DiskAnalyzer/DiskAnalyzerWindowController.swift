// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Owns the Disk Analyzer workspace window. Settings and the menu panel only
/// launch this; the treemap itself is not embedded in Settings.
final class DiskAnalyzerWindowController: NSObject, NSWindowDelegate {
    static let shared = DiskAnalyzerWindowController()

    private var window: NSWindow?
    private var retainedActivation = false

    private override init() {
        super.init()
    }

    func show() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.show() }
            return
        }
        let window = ensureWindow()
        window.title = FeatureStrings.diskAnalyzer(L10n.shared.language).pageTitle
        if !window.isVisible {
            retainActivation()
            centerIfNeeded(window)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DiskAnalyzerService.shared.cancel()
        releaseActivation()
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let content = DiskAnalyzerWorkspaceView()
        let host = NSHostingController(rootView: content)
        host.sizingOptions = []

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = FeatureStrings.diskAnalyzer(L10n.shared.language).pageTitle
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 480)
        window.contentViewController = host
        window.delegate = self
        window.setFrameAutosaveName("DiskAnalyzerWindow")
        self.window = window
        return window
    }

    private func centerIfNeeded(_ window: NSWindow) {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        guard screen.width > 0 else { return }
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
        guard !onScreen || window.frame.size.width < 100 else { return }
        window.setFrame(NSRect(x: screen.midX - 480, y: screen.midY - 340,
                               width: 960, height: 680),
                        display: false)
    }

    private func retainActivation() {
        guard !retainedActivation else { return }
        WindowActivationPolicy.retain()
        retainedActivation = true
    }

    private func releaseActivation() {
        guard retainedActivation else { return }
        WindowActivationPolicy.release()
        retainedActivation = false
    }
}
