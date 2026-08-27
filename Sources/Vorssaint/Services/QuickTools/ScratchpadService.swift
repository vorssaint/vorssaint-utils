// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

/// A floating pad for short-lived text: meeting notes, numbers, fragments on
/// their way somewhere else. Summoned from the panel, the quick panel or a
/// global shortcut, it saves every edit by itself in a small tabbed document, so
/// nothing runs at rest and edits remain available between openings. It steps
/// aside on a click outside, and an option keeps it floating over other apps
/// instead.
final class ScratchpadService: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ScratchpadService()

    @Published private(set) var shortcutRegistrationFailed = false
    @Published private(set) var isPinned = false
    @Published private(set) var isPreviewing = false
    @Published private(set) var pads: [ScratchpadPad] = []
    @Published private(set) var selectedPadID: UUID?
    @Published var text = "" {
        didSet {
            guard hasLoaded, !isReplacingText, var document else { return }
            document.updateSelectedText(text, modifiedAt: Date())
            self.document = document
            pads = document.pads
            scheduleSave()
        }
    }

    private let hotkey = QuickToolHotkey(id: 18)
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private weak var textView: NSTextView?
    private var pendingSave: DispatchWorkItem?
    private var document: ScratchpadDocument?
    private var lastSavedDocument: ScratchpadDocument?
    private var hasLoaded = false
    private var isReplacingText = false
    private var modalInteractionActive = false

    private override init() {
        super.init()
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
        guard !modalInteractionActive else { return }
        if isVisible, panel?.isKeyWindow == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard AppFeature.scratchpad.isAvailable, !modalInteractionActive else { return }
        if isVisible {
            focusText()
            return
        }
        isPreviewing = false
        isPinned = !closesOnClickOutside
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
        isPinned = false
        isPreviewing = false
        modalInteractionActive = false
    }

    // MARK: - Document

    /// The former single-buffer file is read once and removed only after the
    /// replacement document has been written and read back successfully.
    private static var legacyStoreURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("Scratchpad.txt")
    }

    private func loadApplyingRetention() {
        hasLoaded = true
        if let document, document != lastSavedDocument {
            flushSave()
            return
        }
        let defaults = UserDefaults.standard
        let defaultName = FeatureStrings.scratchpad(L10n.shared.language).pageTitle
        let retention = ScratchpadRetention.sanitized(
            defaults.string(forKey: DefaultsKey.scratchpadRetention))

        if let stored = defaults.object(forKey: DefaultsKey.scratchpadDocument) {
            let data = stored as? Data
            let decoded = data.flatMap { try? JSONDecoder().decode(ScratchpadDocument.self, from: $0) }
            var loaded = decoded?.sanitized(defaultName: defaultName)
                ?? .initial(defaultName: defaultName)
            loaded.applyRetention(retention, now: Date())
            if loaded == decoded {
                lastSavedDocument = loaded
            } else {
                _ = persist(loaded)
            }
            apply(loaded)
            return
        }

        let manager = FileManager.default
        let legacyURL = Self.legacyStoreURL
        let legacyText = legacyURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let lastEdited = legacyURL.flatMap {
            (try? manager.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date
        }
        let migrated = ScratchpadSupport.migratedLegacyDocument(
            text: legacyText,
            lastEdited: lastEdited,
            defaultName: defaultName,
            retention: retention,
            now: Date())
        if persist(migrated), let legacyURL {
            try? manager.removeItem(at: legacyURL)
        }
        apply(migrated)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushSave() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func flushSave() {
        pendingSave?.cancel()
        pendingSave = nil
        guard hasLoaded, let document else { return }
        _ = persist(document)
    }

    @discardableResult
    private func persist(_ document: ScratchpadDocument) -> Bool {
        if document == lastSavedDocument { return true }
        guard let data = document.encoded() else { return false }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: DefaultsKey.scratchpadDocument)
        guard defaults.data(forKey: DefaultsKey.scratchpadDocument) == data else { return false }
        lastSavedDocument = document
        return true
    }

    private func apply(_ document: ScratchpadDocument, focus: Bool = false) {
        self.document = document
        pads = document.pads
        selectedPadID = document.selectedID
        let selectedText = document.pads.first(where: { $0.id == document.selectedID })?.text ?? ""
        isReplacingText = true
        text = selectedText
        isReplacingText = false
        if text.isEmpty { isPreviewing = false }
        if focus { focusText() }
    }

    var canCreatePad: Bool { pads.count < ScratchpadDocument.maximumPadCount }
    var canClosePad: Bool { pads.count > 1 }
    var selectedPadName: String {
        pads.first(where: { $0.id == selectedPadID })?.name
            ?? FeatureStrings.scratchpad(L10n.shared.language).pageTitle
    }

    func createPad(defaultName: String) {
        guard let document, let next = document.addingPad(defaultName: defaultName), persist(next) else { return }
        apply(next, focus: true)
    }

    func selectPad(_ id: UUID) {
        guard id != selectedPadID, let document, let next = document.selecting(id), persist(next) else { return }
        apply(next, focus: true)
    }

    func renamePad(_ id: UUID, to name: String) {
        guard let document, let next = document.renaming(id, to: name), persist(next) else { return }
        apply(next, focus: id == selectedPadID)
    }

    @discardableResult
    func closePad(_ id: UUID) -> Bool {
        guard let document, let next = document.removing(id), persist(next) else { return false }
        apply(next, focus: true)
        return true
    }

    func setModalInteractionActive(_ active: Bool) {
        modalInteractionActive = active
    }

    /// Settings export asks for a current document only when the user invokes
    /// it; normal app launch still performs no scratchpad content read.
    func prepareForSettingsBackup() {
        if hasLoaded { flushSave() } else { loadApplyingRetention() }
    }

    /// Import intentionally replaces settings. Drop the in-memory document so
    /// the termination flush cannot overwrite the restored backup on the way out.
    func prepareForSettingsRestore() {
        pendingSave?.cancel()
        pendingSave = nil
        hasLoaded = false
        document = nil
        lastSavedDocument = nil
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
        if isPreviewing {
            isPreviewing = false
            focusText()
        }
        flushSave()
    }

    func togglePreview() {
        guard !text.isEmpty else { return }
        isPreviewing.toggle()
        if isPreviewing {
            panel?.makeFirstResponder(nil)
        } else {
            focusText()
        }
    }

    func togglePin() {
        guard isVisible else { return }
        isPinned.toggle()
    }

    func outsideClickPreferenceDidChange() {
        guard isVisible else { return }
        isPinned = !closesOnClickOutside
    }

    /// The hosts never activate the app, and a modal dialog in an inactive app
    /// takes no clicks or keys. Activate first and let the run loop turn, then
    /// hand key focus back to the pad.
    func exportText(suggestedName: String) {
        guard !text.isEmpty, !modalInteractionActive else { return }
        modalInteractionActive = true
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
            self?.modalInteractionActive = false
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
        panel.minSize = NSSize(width: 280, height: 220)
        panel.delegate = self
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

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(280, frameSize.width), height: max(220, frameSize.height))
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

    /// Esc always closes the pad, and so does a click anywhere outside it
    /// unless the user asked for a pad that stays put while working in other
    /// apps. The choice is read at click time, so flipping it in Settings
    /// takes effect on an open pad.
    private var closesOnClickOutside: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.scratchpadCloseOnClickOutside)
    }

    /// The export dialog is a click outside the pad by geometry, so saving to
    /// a file must never be what closes it.
    private var dismissesOnOutsideClick: Bool {
        ScratchpadSupport.dismissesOnOutsideClick(isPinned: isPinned,
                                                  exportModalActive: modalInteractionActive)
    }

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
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideClick else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) {
                self.hide()
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideClick else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel) {
                self.hide()
            }
        }
    }

    /// A click on the pad's own edge (its resize border) still belongs to it.
    private static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }
}
