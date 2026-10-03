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
    /// Not a preference: the row is a thing you reach for while writing, not a
    /// choice about the pad, so every opening starts without it and one click
    /// brings it back. Held here rather than in either view so both pads agree
    /// while the pad is up.
    @Published private(set) var marksExpanded = false
    @Published private(set) var pads: [ScratchpadPad] = []
    @Published private(set) var allPads: [ScratchpadPad] = []
    @Published private(set) var folders: [ScratchpadFolder] = []
    @Published var collection: ScratchpadCollection = .inbox
    @Published var search = ""
    @Published var showsSidebar = false
    @Published var isSourceMode = false
    var editingPositions: [UUID: ScratchpadEditorPosition] = [:]
    private let ioQueue = DispatchQueue(label: "com.vorssaint.scratchpad.storage", qos: .utility)
    @Published private(set) var selectedPadID: UUID?
    /// Both pads show this in place until a write succeeds again.
    @Published private(set) var saveFailed = false
    /// Bumped when Command-W asks the floating workspace to close its tab.
    @Published private(set) var keyboardCloseSelectedPadSerial = 0
    @Published var text = "" {
        didSet {
            guard hasLoaded, !isReplacingText, var document else { return }
            document.updateSelectedText(text, modifiedAt: Date())
            self.document = document
            publishNotes(document)
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
    private var store = ScratchpadStore(directoryURL: PrivateFileStore.containerURL,
                                        defaults: .standard)
    private var hasLoaded = false
    private var isReplacingText = false
    private(set) var modalInteractionActive = false

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
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.scratchpadShortcut)
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

    var presentationWindow: NSWindow? { panel }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    /// The shortcut is a strict toggle only while the pad has the keyboard:
    /// visible but unfocused, it grabs focus instead of closing, so one press
    /// always lands the caret in the text.
    func toggle() {
        guard !modalInteractionActive else { return }
        if NotchService.shared.showScratchpad(toggle: true) {
            if isVisible { hide() }
            return
        }
        if isVisible, panel?.isKeyWindow == true {
            hide()
        } else {
            show()
        }
    }

    /// The island's own open action passes false: it moves the document out
    /// to the floating pad instead of routing it back into the island.
    func show(allowsIsland: Bool = true) {
        guard AppFeature.scratchpad.isAvailable, !modalInteractionActive else { return }
        if allowsIsland, NotchService.shared.showScratchpad() {
            if isVisible { hide() }
            return
        }
        if isVisible {
            focusText(requiresKeyWindow: false)
            return
        }
        marksExpanded = false
        isPinned = !closesOnClickOutside
        guard loadApplyingRetention() else {
            QuickToolHUD.show(
                icon: "exclamationmark.triangle",
                message: FeatureStrings.scratchpad(L10n.shared.language).loadFailed)
            return
        }
        let panel = ensurePanel()
        installMonitors(for: panel)
        // The pad keeps the spot and size the user gave it while the app
        // runs; it only re-centers when that spot is no longer on any screen.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            center(panel)
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        focusText(requiresKeyWindow: false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            panel.animator().alphaValue = 1
        }
    }

    /// The island edits the same document in place: load it (or the current
    /// copy) without showing the floating pad, and commit when it leaves.
    func loadForEmbedding() -> Bool {
        guard AppFeature.scratchpad.isAvailable else { return false }
        marksExpanded = false
        return loadApplyingRetention()
    }

    /// The inline warning leaves with the pad or the island, so a final
    /// write that fails on the way out falls back to the HUD.
    func commitEdits() {
        flushSave()
        if saveFailed {
            QuickToolHUD.show(
                icon: "exclamationmark.triangle",
                message: FeatureStrings.scratchpad(L10n.shared.language).saveFailed)
        }
    }

    func hide() {
        guard panel != nil else { return }
        commitEdits()
        removeMonitors()
        panel?.orderOut(nil)
        isPinned = false
        modalInteractionActive = false
    }

    // MARK: - Document

    @discardableResult
    private func loadApplyingRetention() -> Bool {
        if hasLoaded, let document, document != ioQueue.sync(execute: { store.lastSavedDocument }) {
            flushSave()
            return true
        }
        let defaults = UserDefaults.standard
        let defaultName = FeatureStrings.scratchpad(L10n.shared.language).pageTitle
        let retention = ScratchpadRetention.sanitized(
            defaults.string(forKey: DefaultsKey.scratchpadRetention))
        do {
            let loaded = try ioQueue.sync { try store.load(defaultName: defaultName, retention: retention, now: Date()) }
            saveFailed = ioQueue.sync { store.lastSavedDocument != loaded }
            let reopened = loaded.openIDs.isEmpty ? (loaded.selecting(loaded.selectedID) ?? loaded) : loaded
            apply(reopened)
            hasLoaded = true
            return true
        } catch {
            hasLoaded = false
            return false
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hasLoaded, let snapshot = self.document else { return }
            self.ioQueue.async {
                let succeeded = self.store.save(snapshot)
                DispatchQueue.main.async {
                    guard self.hasLoaded, self.document == snapshot else { return }
                    self.saveFailed = !succeeded
                }
            }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func flushSave() {
        pendingSave?.cancel()
        pendingSave = nil
        guard hasLoaded, let document else { return }
        _ = save(document)
    }

    /// A failed write keeps the edits in memory and retries on the next change.
    private func save(_ next: ScratchpadDocument) -> Bool {
        saveFailed = !ioQueue.sync { store.save(next) }
        return !saveFailed
    }

    private func apply(_ document: ScratchpadDocument, focus: Bool = false) {
        self.document = document
        publishNotes(document)
        selectedPadID = document.selectedID
        let selectedText = document.pads.first(where: { $0.id == document.selectedID })?.text ?? ""
        isReplacingText = true
        text = selectedText
        isReplacingText = false
        if focus { focusText() }
    }

    private func publishNotes(_ document: ScratchpadDocument) {
        allPads = document.pads
        folders = document.folders
        let byID = Dictionary(uniqueKeysWithValues: document.pads.map { ($0.id, $0) })
        pads = document.openIDs.compactMap { byID[$0] }
    }

    var canCreatePad: Bool { hasLoaded }
    var canClosePad: Bool { !pads.isEmpty }
    var visibleNotes: [ScratchpadPad] { document?.notes(in: collection, query: search) ?? [] }
    var selectedPad: ScratchpadPad? { allPads.first { $0.id == selectedPadID } }

    func binding(for id: UUID) -> Binding<String> {
        Binding(get: { [weak self] in self?.allPads.first { $0.id == id }?.text ?? "" },
                set: { [weak self] in self?.updateText($0, for: id) })
    }

    private func updateText(_ value: String, for id: UUID) {
        guard hasLoaded, var next = document else { return }
        next.updateText(value, for: id, modifiedAt: Date())
        document = next
        publishNotes(next)
        if id == selectedPadID {
            isReplacingText = true
            text = value
            isReplacingText = false
        }
        scheduleSave()
    }
    var selectedPadName: String {
        pads.first(where: { $0.id == selectedPadID })?.name
            ?? FeatureStrings.scratchpad(L10n.shared.language).pageTitle
    }

    func createPad(defaultName: String) {
        guard let document, let next = document.addingPad(defaultName: defaultName), save(next) else { return }
        apply(next, focus: true)
    }

    func selectPad(_ id: UUID) {
        guard let document, let next = document.selecting(id), save(next) else { return }
        apply(next, focus: true)
    }

    func renamePad(_ id: UUID, to name: String) {
        guard let document, let next = document.renaming(id, to: name), save(next) else { return }
        apply(next, focus: id == selectedPadID)
    }

    func duplicatePad(_ id: UUID) {
        guard let document, let next = document.duplicating(id, now: Date()), save(next) else { return }
        apply(next, focus: true)
        showsSidebar = false
    }

    private func changeDocument(_ edit: (inout ScratchpadDocument) -> Void) {
        guard var next = document else { return }
        edit(&next)
        guard save(next) else { return }
        apply(next)
    }

    func movePad(_ id: UUID, to folderID: UUID?) {
        changeDocument { next in
            guard folderID == nil || next.folders.contains(where: { $0.id == folderID }),
                  let index = next.pads.firstIndex(where: { $0.id == id }) else { return }
            next.pads[index].folderID = folderID
            next.pads[index].isTemporary = false
        }
    }

    func createPadInCollection() {
        guard let document, var next = document.addingPad(defaultName: FeatureStrings.scratchpad(L10n.shared.language).pageTitle) else { return }
        if case .folder(let folder) = collection { next.pads[next.pads.count - 1].folderID = folder }
        guard save(next) else { return }
        apply(next, focus: true)
    }

    func addFolder(named proposedName: String) {
        let name = ScratchpadSupport.sanitizedPadName(proposedName)
        guard !name.isEmpty else { return }
        let id = UUID()
        changeDocument { $0.folders.append(.init(id: id, name: name)) }
        if folders.contains(where: { $0.id == id }) { collection = .folder(id) }
    }

    func renameFolder(_ id: UUID, to proposedName: String) {
        let name = ScratchpadSupport.sanitizedPadName(proposedName)
        guard !name.isEmpty else { return }
        changeDocument { next in
            if let index = next.folders.firstIndex(where: { $0.id == id }) { next.folders[index].name = name }
        }
    }

    func deleteFolder(_ id: UUID) {
        changeDocument { $0.deleteFolder(id) }
        if !folders.contains(where: { $0.id == id }), collection == .folder(id) { collection = .inbox }
    }

    func toggleNotePin(_ id: UUID) {
        changeDocument { next in
            if let index = next.pads.firstIndex(where: { $0.id == id }) { next.pads[index].isPinned.toggle() }
        }
    }

    func toggleTemporary(_ id: UUID) {
        changeDocument { next in
            if let index = next.pads.firstIndex(where: { $0.id == id }) { next.pads[index].isTemporary.toggle() }
        }
    }

    func deletePad(_ id: UUID) {
        changeDocument { $0.trash(id, now: Date(), defaultName: FeatureStrings.scratchpad(L10n.shared.language).pageTitle) }
    }

    func restorePad(_ id: UUID) { changeDocument { $0.restore(id) } }

    /// The caller confirms permanent deletion. Live notes can never be purged.
    func purgeTrash(_ id: UUID? = nil) {
        changeDocument { $0.pads.removeAll { $0.deletedAt != nil && (id == nil || $0.id == id) } }
    }

    func reorderTab(_ id: UUID, before destination: UUID) {
        changeDocument { $0.reorderTab(id, before: destination) }
    }

    @discardableResult
    func closePad(_ id: UUID) -> Bool {
        guard let document, let next = document.removing(id), save(next) else { return false }
        apply(next, focus: true)
        if next.openIDs.isEmpty {
            hide()
            if NotchService.shared.selected == .scratchpad { NotchService.shared.collapse() }
        }
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

    /// Settings imports never replace notes. Flush edits before releasing the cache.
    func prepareForSettingsRestore() {
        flushSave()
        guard !saveFailed else { return }
        pendingSave?.cancel()
        pendingSave = nil
        hasLoaded = false
        document = nil
        ioQueue.sync { store = ScratchpadStore(directoryURL: PrivateFileStore.containerURL, defaults: .standard) }
    }

    // MARK: - Actions

    func copyAll() {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Clearing goes through the text view when it is up, so one Cmd+Z brings
    /// everything back while the pad stays open. The island passes its own
    /// editor for the same undo there.
    func clear(through editor: NSTextView? = nil) {
        guard !text.isEmpty else { return }
        if let textView = editor ?? textView.flatMap({ $0.window === panel ? $0 : nil }) {
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

    /// The toolbar types the Markdown the user would have typed, through the
    /// text view so one Cmd+Z takes the whole mark back. The island passes its
    /// own editor for the same undo there.
    func apply(_ mark: ScratchpadMark, through editor: NSTextView? = nil) {
        guard let textView = editor ?? textView.flatMap({ $0.window === panel ? $0 : nil }) else { return }
        // A live input-method composition holds a marked range into the
        // storage; editing around it leaves that range pointing at nothing.
        if textView.hasMarkedText() { textView.unmarkText() }
        // Clicking a button takes first responder away from the editor, and a
        // selection set on a view that is not first responder does not show.
        textView.window?.makeFirstResponder(textView)
        let edit = ScratchpadSupport.edit(applying: mark,
                                          to: textView.string,
                                          selection: textView.selectedRange())
        guard (textView.string as NSString).substring(with: edit.range) != edit.replacement else { return }
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textView.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()
        textView.setSelectedRange(edit.selection)
        textView.scrollRangeToVisible(edit.selection)
        flushSave()
    }

    func toggleMarks() {
        marksExpanded.toggle()
    }

    func applyChecklist(_ action: ScratchpadMarkdown.ChecklistAction, through editor: NSTextView?) {
        guard let editor, let coordinator = editor.delegate as? ScratchpadEditor.Coordinator,
              coordinator.applyChecklist(action) else { return }
        flushSave()
    }

    func toggleSource() { isSourceMode.toggle() }

    func togglePin() {
        guard isVisible else { return }
        isPinned.toggle()
    }

    func outsideClickPreferenceDidChange() {
        guard isVisible else { return }
        isPinned = !closesOnClickOutside
    }

    /// Activate for dialog input and return focus to the originating host.
    /// The island's dialog floats just above it: a sheet would move and
    /// reskin the borderless surface.
    func exportText(suggestedName: String, from window: NSWindow? = nil) {
        guard !text.isEmpty, !modalInteractionActive, let padID = selectedPadID,
              let sourceWindow = window ?? panel, sourceWindow.isVisible else { return }
        modalInteractionActive = true
        flushSave()
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = suggestedName
        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.modalInteractionActive = false
            if response == .OK, let url = savePanel.url {
                do {
                    // The island's dialog leaves the pad editable, so the file
                    // gets the pad as it is when the save is confirmed. A pad
                    // closed meanwhile is reported like any failed write.
                    guard let content = self?.document?.pads.first(where: { $0.id == padID })?.text else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    try content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    // A read-only volume or a full disk used to end here in
                    // silence, with the save panel closed and nothing written.
                    QuickToolHUD.show(
                        icon: "exclamationmark.triangle",
                        message: FeatureStrings.scratchpad(L10n.shared.language).exportFailed)
                }
            }
            // Dismissal restores the previous key window after completion.
            DispatchQueue.main.async {
                if sourceWindow.isVisible { sourceWindow.makeKey() }
            }
        }
        if sourceWindow === NotchService.shared.presentationWindow {
            // modalInteractionActive keeps the island's working surface
            // while its independent dialog is up.
            savePanel.level = NSWindow.Level(rawValue: sourceWindow.level.rawValue + 1)
            // Like the sheet it replaces, it stays up while another app is active.
            savePanel.hidesOnDeactivate = false
            savePanel.begin(completionHandler: complete)
            NSApp.activate(ignoringOtherApps: true)
            // Activation alone can leave the nonactivating island holding focus.
            savePanel.makeKeyAndOrderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { complete(savePanel.runModal()) }
        }
    }

    // MARK: - Focus

    /// The editor registers itself while the pad's view is alive; the service
    /// only ever aims focus and the undoable clear at it.
    func registerTextView(_ view: NSTextView) {
        textView = view
    }

    /// Document actions keep focus in their host. Only an explicit show may
    /// bring the floating pad forward while the island or another app is key.
    private func focusText(requiresKeyWindow: Bool = true) {
        guard let panel, panel.isVisible, !requiresKeyWindow || panel.isKeyWindow else { return }
        panel.makeKey()
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible, panel.isKeyWindow,
                  let textView = self.textView else { return }
            panel.makeFirstResponder(textView)
        }
    }

    // MARK: - Panel

    /// Borderless panels refuse key status by default; the pad needs it so
    /// typing and Esc work without activating the app.
    private final class KeyableScratchpadPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableScratchpadPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 400),
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
        panel.setContentSize(NSSize(width: 430, height: 400))
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

    private func performFocusedTabShortcut(_ action: ScratchpadFocusedShortcut.Action) {
        switch action {
        case .createPad:
            createPadInCollection()
        case .closeSelectedPad:
            keyboardCloseSelectedPadSerial += 1
        case .hidePad:
            hide()
        case .find:
            requestFind(.showFindInterface)
        case .findNext:
            requestFind(.nextMatch)
        case .findPrevious:
            requestFind(.previousMatch)
        case .switchNotes:
            showNoteSwitcher()
        }
    }

    private func requestFind(_ action: NSTextFinder.Action) {
        NotificationCenter.default.post(name: .scratchpadFind, object: nil, userInfo: ["action": action])
    }

    /// The text view runs the find itself; it only has to be told which of the
    /// finder's actions was asked for, and that arrives as a sender's tag.
    func performFind(_ action: NSTextFinder.Action, in editor: NSTextView? = nil) {
        guard let textView = editor ?? textView.flatMap({ $0.window === panel ? $0 : nil }) else { return }
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        // Command-G keeps focus in the native find field.
        if action == .showFindInterface {
            textView.window?.makeFirstResponder(textView)
        }
        textView.performTextFinderAction(sender)
    }

    /// Dismiss the native find interface without changing document contents.
    func hideFindBar(in editor: NSTextView) {
        guard editor.enclosingScrollView?.isFindBarVisible == true else { return }
        let sender = NSMenuItem()
        sender.tag = NSTextFinder.Action.hideFindInterface.rawValue
        editor.performTextFinderAction(sender)
    }

    /// Independent dialogs preserve the borderless island's size and chrome.
    func ask(title: String, message: String = "", initialName: String? = nil,
             destructive: Bool = false, from window: NSWindow?, completion: @escaping (String?) -> Void) {
        guard !modalInteractionActive else { return }
        modalInteractionActive = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let labels = FeatureStrings.scratchpad(L10n.shared.language)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            let field = initialName.map { NSTextField(string: $0) }
            if let field {
                field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
                alert.accessoryView = field
                alert.window.initialFirstResponder = field
            }
            alert.addButton(withTitle: destructive ? title : labels.saveName).hasDestructiveAction = destructive
            alert.addButton(withTitle: labels.cancel)
            let level = NSWindow.Level(rawValue: (window?.level.rawValue ?? 0) + 1)
            let observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: alert.window, queue: .main) { _ in alert.window.level = level }
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { alert.window.level = level }
            let accepted = alert.runModal() == .alertFirstButtonReturn
            NotificationCenter.default.removeObserver(observer)
            self.modalInteractionActive = false
            if accepted { completion(field?.stringValue ?? "") }
            if window?.isVisible == true { window?.makeKey() }
        }
    }

    private func filePanel(_ panel: NSSavePanel, from window: NSWindow?, complete: @escaping (URL?) -> Void) {
        guard !modalInteractionActive, let window, window.isVisible else { return }
        modalInteractionActive = true
        panel.canCreateDirectories = true
        panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        panel.hidesOnDeactivate = false
        panel.begin { [weak self] response in
            self?.modalInteractionActive = false
            complete(response == .OK ? panel.url : nil)
            if window.isVisible { window.makeKey() }
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func reportFileFailure() {
        QuickToolHUD.show(icon: "exclamationmark.triangle", message: ScratchpadLibraryStrings(language: L10n.shared.language)[.failed])
    }

    func importNotes(from window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = true
        filePanel(panel, from: window) { [weak self] url in
            guard url != nil, let self, let document = self.document else { return }
            do {
                // Decode every input before committing any of them.
                var next = document
                for url in panel.urls {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let id = UUID()
                    let folder: UUID?
                    if case .folder(let value) = self.collection { folder = value } else { folder = nil }
                    next.pads.append(.init(id: id, name: ScratchpadSupport.sanitizedPadName(url.deletingPathExtension().lastPathComponent),
                                           text: content, modifiedAt: Date(), folderID: folder))
                    next.openIDs.append(id)
                    next.selectedID = id
                }
                guard self.save(next) else { return }
                self.apply(next, focus: true)
            } catch { self.reportFileFailure() }
        }
    }

    func backupNotes(from window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Scratchpad Backup.json"
        filePanel(panel, from: window) { [weak self] url in
            guard let self, let url, let data = self.document?.encoded() else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard PrivateFileStore.write(data, to: url) else { self.reportFileFailure(); return }
        }
    }

    func restoreBackup(from window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        filePanel(panel, from: window) { [weak self] url in
            guard let self, let url else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let restored = try JSONDecoder().decode(ScratchpadDocument.self, from: Data(contentsOf: url))
                    .sanitized(defaultName: FeatureStrings.scratchpad(L10n.shared.language).pageTitle)
                let labels = ScratchpadLibraryStrings(language: L10n.shared.language)
                self.ask(title: labels[.restoreBackup], message: labels[.replaceMessage], destructive: true, from: window) { [weak self] _ in
                    guard let self, let existing = self.document,
                          let directory = PrivateFileStore.containerURL, let data = existing.encoded() else { return }
                    let recovery = directory.appendingPathComponent("Scratchpad-recovery-\(UUID().uuidString).json")
                    guard PrivateFileStore.write(data, to: recovery), (try? Data(contentsOf: recovery)) == data else {
                        self.reportFileFailure(); return
                    }
                    self.pendingSave?.cancel()
                    self.pendingSave = nil
                    guard self.save(restored) else { return }
                    self.editingPositions = [:]
                    self.apply(restored, focus: true)
                    self.collection = .all
                }
            } catch { self.reportFileFailure() }
        }
    }

    func exportFolder(from window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        filePanel(panel, from: window) { [weak self] url in
            guard let self, let url else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let notes = self.document?.notes(in: self.collection) ?? []
            let destination = url.appendingPathComponent("Scratchpad-\(UUID().uuidString)", isDirectory: true)
            do {
                guard PrivateFileStore.createDirectory(at: destination, container: destination) else { throw CocoaError(.fileWriteUnknown) }
                for note in notes {
                    let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
                    let name = note.name.components(separatedBy: forbidden).joined(separator: "-")
                    let file = destination.appendingPathComponent("\(name)-\(note.id.uuidString).md")
                    guard PrivateFileStore.write(Data(note.text.utf8), to: file) else { throw CocoaError(.fileWriteUnknown) }
                }
            } catch { self.reportFileFailure() }
        }
    }

    func showNoteSwitcher() {
        collection = .all
        showsSidebar = true
        search = ""
        NotificationCenter.default.post(name: .scratchpadFocusSearch, object: nil)
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
                // The find bar puts itself away on Esc and hands the keyboard
                // back to the text; the pad hides on the next one.
                if PlainTextEditor.findBarHasKeyboard(in: panel) { return event }
                self.hide()
                return nil
            }
            guard !self.modalInteractionActive else { return event }
            let commandOnly = event.modifierFlags
                .intersection([.command, .option, .control]) == .command
            let shift = event.modifierFlags.contains(.shift)
            if let action = ScratchpadFocusedShortcut.action(
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                commandOnly: commandOnly,
                shift: shift,
                canCreatePad: self.canCreatePad,
                canClosePad: self.canClosePad
            ) {
                self.performFocusedTabShortcut(action)
                return nil
            }
            // Command-T still belongs to the pad if its document failed to load.
            if commandOnly, !shift, event.charactersIgnoringModifiers?.lowercased() == "t" {
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
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel),
               // Every key on the Accessibility Keyboard is a click outside this
               // panel. Dismissing on those makes the panel impossible to type into.
               !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) {
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
