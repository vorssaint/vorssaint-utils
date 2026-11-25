// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The Disk Analyzer's own window: one per app, reused while open, forgotten
/// along with its map when closed.
final class DiskAnalyzerWindowController: NSObject, NSWindowDelegate {
    static let shared = DiskAnalyzerWindowController()

    private var window: NSWindow?

    func show() {
        guard AppFeature.diskAnalyzer.isAvailable else { return }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Opens the window and maps the volume or folder at `path` right away.
    func show(scanning path: String) {
        guard AppFeature.diskAnalyzer.isAvailable else { return }
        show()
        let service = DiskAnalyzerService.shared
        guard service.phase != .scanning || service.target?.path != path else { return }
        service.scan(service.folderTarget(URL(fileURLWithPath: path, isDirectory: true)))
    }

    /// Closes the window and drops the map, for uninstall and teardown.
    func suspend() {
        window?.close()
        DiskAnalyzerService.shared.reset()
    }

    private func makeWindow() -> NSWindow {
        let content = DiskAnalyzerView()
            .frame(minWidth: 820, minHeight: 560)
        let host = NSHostingController(rootView: content)
        host.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: host)
        window.title = FeatureStrings.diskAnalyzer(L10n.shared.language).title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.setContentSize(NSSize(width: 1080, height: 720))
        window.setFrameAutosaveName("VorssaintDiskAnalyzer")
        if window.frame.origin == .zero { window.center() }
        WindowActivationPolicy.retain()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
        WindowActivationPolicy.release()
        // The map can hold a whole disk's worth of entries; nothing reopens
        // it later, so it goes with the window.
        DiskAnalyzerService.shared.reset()
    }
}
