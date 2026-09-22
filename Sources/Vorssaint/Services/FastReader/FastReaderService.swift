// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Presents `FastReaderSession` over whatever selection triggered it: the
/// Services menu route, which already holds the text, and the global
/// shortcut route, which reads it from the frontmost application through
/// Accessibility. Gated end to end on `AppFeature.fastReader.isAvailable`,
/// so a feature switched off in the hub does nothing at any entry point —
/// no window opens, no shortcut fires, and the Services handler forwards
/// here only to find there is nothing to do. Main thread only, like the
/// panel and the session it drives.
final class FastReaderService {
    static let shared = FastReaderService()

    /// Long enough to hold a real document; short enough that an editor
    /// with megabytes selected cannot make the reader tokenize something
    /// nobody meant to read start to finish. Text past this point is cut,
    /// not refused outright — the reader opens on the part that fits, and
    /// says so.
    private static let selectionCap = 200_000

    // 21 belongs to RecentCaptureService; the quick tools occupy 10 through 24.
    private let hotkey = QuickToolHotkey(id: 25)
    private var panel: NSPanel?
    private var keyMonitor: Any?
    /// The system Accessibility prompt shows itself at most once per launch;
    /// pressing the shortcut again before it is answered should beep, not
    /// summon a second copy of the same system dialog.
    private var promptedForAccessibility = false

    private init() {
        hotkey.onPress = { [weak self] in self?.openWithCurrentSelection() }
    }

    /// Registers or unregisters the global shortcut against the current
    /// preferences and availability, and — because this is the one hook
    /// `FeatureRuntime` calls whenever Fast Reader's availability changes —
    /// also closes any open reader the moment the feature is switched off.
    /// A feature that just left the hub must stop existing immediately, not
    /// merely stop accepting its shortcut.
    func syncShortcutRegistration() {
        let available = AppFeature.fastReader.isAvailable
        let enabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.fastReaderShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.fastReaderShortcut,
                                            fallback: .fastReaderDefault)
        _ = hotkey.sync(enabled: enabled, shortcut: shortcut,
                        storageKey: DefaultsKey.fastReaderShortcut)
        if !available { teardownForUninstall() }
    }

    /// The shortcut route. Reading the selection through Accessibility is a
    /// blocking call, so it runs off the main thread and comes back to
    /// present.
    func openWithCurrentSelection() {
        guard AppFeature.fastReader.isAvailable else { return }
        guard AXIsProcessTrusted() else {
            handleAccessibilityMissing()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            // Uncapped on purpose: Command Bar's own cap answers empty for
            // anything past it, which would be indistinguishable here from
            // nothing being selected at all. Fast Reader needs to tell those
            // two cases apart, so it reads everything and caps afterward in
            // `present(rawText:)`, where a truncation can still be reported.
            let text = CommandBarSelectionReader.readSelectedText(maximumLength: .max)
            DispatchQueue.main.async { [weak self] in
                self?.present(rawText: text)
            }
        }
    }

    /// The Services route. The text is already in hand, so there is nothing
    /// to read and no Accessibility check to make.
    func open(text: String) {
        guard AppFeature.fastReader.isAvailable else { return }
        present(rawText: text)
    }

    func close() {
        guard let panel else { return }
        FastReaderSession.shared.pause()
        removeMonitors()
        panel.orderOut(nil)
    }

    func teardownForUninstall() {
        close()
        FastReaderSession.shared.teardown()
    }

    // MARK: - Presentation

    private func present(rawText: String) {
        let strings = FeatureStrings.fastReader(L10n.shared.language)
        guard !rawText.isEmpty else {
            QuickToolHUD.show(icon: AppFeature.fastReader.symbolName, message: strings.noSelection)
            return
        }
        let truncated = rawText.count > Self.selectionCap
        let text = truncated ? String(rawText.prefix(Self.selectionCap)) : rawText
        guard !FastReaderEngine.tokenize(text).isEmpty else {
            QuickToolHUD.show(icon: AppFeature.fastReader.symbolName, message: strings.emptySelection)
            return
        }
        // Paused at the first chunk: whatever brought the reader up — a
        // shortcut fired by accident, a slip in the Services menu — must
        // not start flashing text before the controls are even visible.
        FastReaderSession.shared.load(text, options: FastReaderPreferences.options())
        showFloatingPanel()
        if truncated {
            QuickToolHUD.show(icon: AppFeature.fastReader.symbolName,
                              message: String(format: strings.truncatedFormat, Self.selectionCap))
        }
    }

    private func showFloatingPanel() {
        switch FastReaderPreferences.surface {
        case .floating, .notch:
            // `.notch` is reserved for the Dynamic Island surface Phase 2
            // adds. Until that surface exists both settings land here, on
            // the same floating panel — there is no `NotchControlItem` case
            // for Fast Reader yet, and this is deliberately not where one
            // gets added.
            break
        }
        let panel = ensurePanel()
        installMonitors(for: panel)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            center(panel)
        }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func handleAccessibilityMissing() {
        let strings = FeatureStrings.fastReader(L10n.shared.language)
        QuickToolHUD.show(icon: AppFeature.fastReader.symbolName, message: strings.accessibilityNeeded)
        if promptedForAccessibility {
            NSSound.beep()
        } else {
            promptedForAccessibility = true
            Permissions.shared.requestAccessibility()
        }
    }

    // MARK: - Panel

    /// Borderless panels refuse key status by default; the reader needs it
    /// so Escape and the playback keys work without activating the app the
    /// selection was read from.
    private final class KeyableFastReaderPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        // Sized from the view, not from a number kept here: the reading row's
        // geometry is fixed on purpose, and a window narrower than it would
        // clip the very alignment the row exists to hold.
        let size = FastReaderPanelView.preferredContentSize
        let panel = KeyableFastReaderPanel(contentRect: NSRect(origin: .zero, size: size),
                                           styleMask: [.borderless, .nonactivatingPanel],
                                           backing: .buffered,
                                           defer: false)
        panel.title = "Vorssaint"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: FastReaderPanelView())
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        center(panel)
        self.panel = panel
        return panel
    }

    private func center(_ panel: NSPanel) {
        let size = panel.frame.size
        let screen = NSScreen.pointerVisibleFrame
        let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }

    // MARK: - Monitors

    /// The reader's own keys (space, arrows, speed) are the view's concern;
    /// the service only owns Escape, the one key that must close the panel
    /// no matter which control inside it currently has focus.
    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.close()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
