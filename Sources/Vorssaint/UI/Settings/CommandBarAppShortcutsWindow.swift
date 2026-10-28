// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Reuses one independent App Shortcuts window across presentations.
final class CommandBarAppShortcutsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = CommandBarAppShortcutsWindowController()

    private static let initialContentSize = NSSize(width: 780, height: 560)
    private var didPlaceWindow = false
    private var retainsRegularActivation = false

    private var windowTitle: String {
        FeatureStrings.commandBar(L10n.shared.language).appCenterTitle
    }

    private init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { nil }

    func show(relativeTo sourceWindow: NSWindow?) {
        let window = window ?? makeWindow()
        window.title = windowTitle

        if !didPlaceWindow {
            place(window, over: sourceWindow)
            didPlaceWindow = true
        } else if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            // A closed window whose screen was detached has no usable spot to
            // return to; put it back over Settings.
            place(window, over: sourceWindow)
        }

        if window.isMiniaturized { window.deminiaturize(nil) }
        if !retainsRegularActivation {
            retainsRegularActivation = true
            WindowActivationPolicy.retain()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Reused content doesn't run onAppear on every presentation.
        CommandBarService.shared.refreshApplications()
    }

    func dismiss() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard retainsRegularActivation else { return }
        retainsRegularActivation = false
        WindowActivationPolicy.release()
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: CommandBarAppShortcutsView { [weak self] in
            self?.dismiss()
        })
        // Track only the view's minimum: the window owns its size, so loading
        // the table never resizes a window the person placed themselves.
        host.sizingOptions = [.minSize]

        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = false
        window.delegate = self
        window.contentMinSize = Self.initialContentSize
        window.setContentSize(Self.initialContentSize)
        self.window = window
        return window
    }

    private func place(_ window: NSWindow, over sourceWindow: NSWindow?) {
        let visibleFrame = sourceWindow?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? .zero
        let size = window.frame.size
        let anchor = sourceWindow?.frame

        var origin = NSPoint(x: visibleFrame.midX - size.width / 2,
                             y: visibleFrame.midY - size.height / 2)
        if let anchor, anchor.width > 0, anchor.height > 0 {
            origin = NSPoint(x: anchor.midX - size.width / 2,
                             y: anchor.midY - size.height / 2)
        }

        let margin: CGFloat = 20
        let highestX = max(visibleFrame.minX + margin, visibleFrame.maxX - size.width - margin)
        let highestY = max(visibleFrame.minY + margin, visibleFrame.maxY - size.height - margin)
        origin.x = min(max(origin.x, visibleFrame.minX + margin), highestX)
        origin.y = min(max(origin.y, visibleFrame.minY + margin), highestY)
        window.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        window?.title = windowTitle
    }
}

/// Remembers the window hosting the Settings page, so opening the table centers
/// over Settings rather than whatever unrelated window happens to be key.
final class CommandBarSettingsWindowReference {
    weak var window: NSWindow?
}

struct CommandBarSettingsWindowReader: NSViewRepresentable {
    let reference: CommandBarSettingsWindowReference

    func makeNSView(context: Context) -> WindowReaderView {
        WindowReaderView(reference: reference)
    }

    func updateNSView(_ view: WindowReaderView, context: Context) {
        view.reference = reference
    }

    final class WindowReaderView: NSView {
        var reference: CommandBarSettingsWindowReference

        init(reference: CommandBarSettingsWindowReference) {
            self.reference = reference
            super.init(frame: .zero)
            setAccessibilityElement(false)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reference.window = window
        }
    }
}
