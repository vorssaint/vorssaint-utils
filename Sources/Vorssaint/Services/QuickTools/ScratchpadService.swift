// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

/// A floating pad for short-lived text: meeting notes, numbers, fragments on
/// their way somewhere else. Summoned from the panel, the quick panel or a
/// global shortcut, it saves every edit by itself to one local file and stays
/// on top while the user works in other apps, so nothing exists at rest and
/// nothing is ever lost between openings.
final class ScratchpadService: ObservableObject {
    static let shared = ScratchpadService()

    @Published private(set) var shortcutRegistrationFailed = false
    /// The single buffer. The pad's editor binds straight to it; every change
    /// schedules a save, so there is no save ceremony anywhere.
    @Published var text = "" {
        didSet { scheduleSave() }
    }

    private let hotkey = QuickToolHotkey(id: 18)
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private weak var textView: NSTextView?
    private var pendingSave: DispatchWorkItem?
    private var lastSavedText: String?
    private var hasLoaded = false
    private static var exportModalActive = false

    private init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    func syncWithPreferences() {
        let available = AppFeature.scratchpad.isAvailable
        let enabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.scratchpadShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.scratchpadShortcut,
                                            fallback: .scratchpadDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut)
        if !available {
            hide()
            // Uninstalled in the hub: nothing stays resident.
            panel = nil
        }
    }

    func suspend() {
        hotkey.unregister()
        hide()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    /// The shortcut is a strict toggle only while the pad has the keyboard:
    /// visible but unfocused, it grabs focus instead of closing, so one press
    /// always lands the caret in the text.
    func toggle() {
        guard !Self.exportModalActive else { return }
        if isVisible, panel?.isKeyWindow == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard AppFeature.scratchpad.isAvailable, !Self.exportModalActive else { return }
        if isVisible {
            focusText()
            return
        }
        loadApplyingRetention()
        let panel = ensurePanel()
        installMonitors(for: panel)
        // The pad keeps the spot and size the user gave it while the app
        // runs; it only re-centers when that spot is no longer on any screen.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            center(panel)
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        focusText()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel != nil else { return }
        flushSave()
        removeMonitors()
        panel?.orderOut(nil)
    }

    // MARK: - Buffer

    /// The buffer file. Plain text the user could open by hand; its
    /// modification date doubles as the "last edit" the retention rule reads,
    /// so no extra bookkeeping exists anywhere. Without a resolvable home the
    /// pad simply keeps text in memory for the session.
    private static var storeURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Scratchpad.txt")
    }

    private func loadApplyingRetention() {
        hasLoaded = true
        guard let url = Self.storeURL else { return }
        // A dirty buffer means an edit newer than anything on disk (a failed
        // flush left it behind); reloading would clobber the user's text with
        // the stale file. Retry the save instead and keep the buffer.
        if let lastSavedText, text != lastSavedText {
            flushSave()
            return
        }
        let manager = FileManager.default
        let retention = ScratchpadRetention.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.scratchpadRetention))
        let lastEdited = (try? manager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if ScratchpadSupport.shouldClear(lastEdited: lastEdited, now: Date(), retention: retention) {
            try? manager.removeItem(at: url)
        }
        let saved = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        lastSavedText = saved
        if text != saved {
            text = saved
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushSave() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    /// Writes only when the buffer really changed since the last write, so
    /// reopening the pad never touches the file's modification date.
    private func flushSave() {
        pendingSave?.cancel()
        pendingSave = nil
        guard hasLoaded, text != lastSavedText, let url = Self.storeURL else { return }
        if text.isEmpty {
            try? FileManager.default.removeItem(at: url)
            lastSavedText = text
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            // Only a write that really landed marks the buffer clean, so a
            // failed save retries on the next edit or close.
            if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil {
                lastSavedText = text
            }
        }
    }

    // MARK: - Actions

    func copyAll() {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Clearing goes through the text view when it is up, so one Cmd+Z brings
    /// everything back while the pad stays open.
    func clear() {
        guard !text.isEmpty else { return }
        if let textView, textView.window === panel {
            // A live input-method composition holds a marked range into the
            // storage; replacing the whole text underneath it leaves that
            // range pointing at nothing. Commit it first.
            if textView.hasMarkedText() { textView.unmarkText() }
            let full = NSRange(location: 0, length: (textView.string as NSString).length)
            if textView.shouldChangeText(in: full, replacementString: "") {
                textView.replaceCharacters(in: full, with: "")
                textView.didChangeText()
            }
        } else {
            text = ""
        }
        flushSave()
    }

    /// The hosts never activate the app, and a modal dialog in an inactive app
    /// takes no clicks or keys. Activate first and let the run loop turn, then
    /// hand key focus back to the pad.
    func exportText(suggestedName: String) {
        guard !text.isEmpty, !Self.exportModalActive else { return }
        Self.exportModalActive = true
        flushSave()
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = suggestedName
        let content = text
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            let response = savePanel.runModal()
            Self.exportModalActive = false
            if response == .OK, let url = savePanel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
            guard let self, let panel = self.panel, panel.isVisible else { return }
            panel.makeKey()
        }
    }

    // MARK: - Focus

    /// The editor registers itself while the pad's view is alive; the service
    /// only ever aims focus and the undoable clear at it.
    func registerTextView(_ view: NSTextView) {
        textView = view
    }

    private func focusText() {
        guard let panel else { return }
        panel.makeKey()
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible,
                  let textView = self.textView else { return }
            panel.makeFirstResponder(textView)
            let end = NSRange(location: (textView.string as NSString).length, length: 0)
            textView.setSelectedRange(end)
            textView.scrollRangeToVisible(end)
        }
    }

    // MARK: - Panel

    /// Borderless panels refuse key status by default; the pad needs it so
    /// typing and Esc work without activating the app.
    private final class KeyableScratchpadPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableScratchpadPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                                           styleMask: [.borderless, .nonactivatingPanel, .resizable],
                                           backing: .buffered,
                                           defer: false)
        panel.title = "Vorssaint"
        panel.isReleasedWhenClosed = false
        // Dragging inside the pad must select text, never move the window;
        // the header strip is the handle.
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentMinSize = NSSize(width: 280, height: 220)
        let host = NSHostingController(rootView: ScratchpadView())
        // No preferred-size tracking: the pad is user-resizable and the view
        // fills whatever frame the panel has.
        host.sizingOptions = []
        panel.contentViewController = host
        // Assigning the content controller shrinks the window to the view's
        // minimum; restore the pad's starting size.
        panel.setContentSize(NSSize(width: 380, height: 300))
        center(panel)
        self.panel = panel
        return panel
    }

    private func center(_ panel: NSPanel) {
        let size = panel.frame.size
        let screen = NSScreen.pointerVisibleFrame
        let x = screen.midX - size.width / 2
        let y = screen.minY + (screen.height - size.height) * 0.58
        panel.setFrame(NSRect(x: max(screen.minX + 16, min(x, screen.maxX - size.width - 16)),
                              y: max(screen.minY + 16, min(y, screen.maxY - size.height - 16)),
                              width: size.width,
                              height: size.height),
                       display: true,
                       animate: false)
    }

    // MARK: - Monitors

    /// Only Esc: the pad is a working surface, so clicks in other apps (to
    /// copy something into it) and app switches never close it. It leaves by
    /// Esc, its close button or the shortcut.
    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                // Mid-composition Esc belongs to the input method, not the pad.
                if let textView = self.textView, textView.hasMarkedText() {
                    return event
                }
                self.hide()
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
