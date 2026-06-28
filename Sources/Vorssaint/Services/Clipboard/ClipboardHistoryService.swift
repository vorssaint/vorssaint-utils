// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics
import Foundation
import SwiftUI

struct ClipboardHistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    var copiedAt: Date
    var pinnedAt: Date?

    init(id: UUID = UUID(), text: String, copiedAt: Date = Date(), pinnedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.pinnedAt = pinnedAt
    }

    var isPinned: Bool {
        pinnedAt != nil
    }

    var preview: String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? text : collapsed
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, copiedAt, pinnedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        copiedAt = try container.decodeIfPresent(Date.self, forKey: .copiedAt) ?? Date()
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
    }
}

enum ClipboardHistoryMoveDirection {
    case up
    case down
}

/// Opt-in text clipboard history. It records only plain text, keeps a small
/// local history, and avoids obvious secret-looking strings by default.
final class ClipboardHistoryService: ObservableObject {
    static let shared = ClipboardHistoryService()

    @Published private(set) var entries: [ClipboardHistoryEntry] = []
    @Published private(set) var isRunning = false
    @Published private(set) var shortcutRegistrationFailed = false
    @Published var quickQuery = "" {
        didSet {
            if quickQuery != oldValue {
                resetQuickSelection()
            }
        }
    }
    @Published private(set) var quickSelectionIndex = 0

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var registeredShortcut: GlobalShortcut?
    private var pasteTargetApp: NSRunningApplication?
    private let maxCharacters = 20_000

    private init() {
        load()
    }

    func syncWithPreferences() {
        if UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryEnabled) {
            start()
            syncHotkey()
        } else {
            stop()
            unregisterHotkey()
        }
    }

    func copy(_ entry: ClipboardHistoryEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].copiedAt = Date()
            save()
        }
    }

    func togglePin(_ entry: ClipboardHistoryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entries.remove(at: index)
        if updated.isPinned {
            updated.pinnedAt = nil
            entries.insert(updated, at: firstRecentIndex)
        } else {
            updated.pinnedAt = Date()
            entries.insert(updated, at: 0)
        }
        normalizeEntryOrder()
        save()
    }

    func remove(_ entry: ClipboardHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearRecent() {
        entries.removeAll { !$0.isPinned }
        save()
    }

    func clearAll() {
        clearRecent()
    }

    func canMove(_ entry: ClipboardHistoryEntry, _ direction: ClipboardHistoryMoveDirection) -> Bool {
        moveDestination(for: entry, direction) != nil
    }

    func move(_ entry: ClipboardHistoryEntry, _ direction: ClipboardHistoryMoveDirection) {
        guard let from = entries.firstIndex(where: { $0.id == entry.id }),
              let to = moveDestination(for: entry, direction)
        else { return }
        entries.swapAt(from, to)
        save()
    }

    var pinnedEntries: [ClipboardHistoryEntry] {
        entries.filter(\.isPinned)
    }

    var recentEntries: [ClipboardHistoryEntry] {
        entries.filter { !$0.isPinned }
    }

    var filteredQuickEntries: [ClipboardHistoryEntry] {
        filteredEntries(matching: quickQuery)
    }

    var selectedQuickEntryID: UUID? {
        selectedQuickEntry?.id
    }

    var selectedQuickEntry: ClipboardHistoryEntry? {
        let matches = filteredQuickEntries
        guard !matches.isEmpty else { return nil }
        return matches[clampedQuickSelectionIndex(for: matches.count)]
    }

    func filteredEntries(matching query: String) -> [ClipboardHistoryEntry] {
        let candidates = entries.enumerated().map { index, entry in
            ClipboardHistorySearchCandidate(index: index,
                                            text: entry.text,
                                            isPinned: entry.isPinned)
        }
        return ClipboardHistorySearch.rankedIndexes(candidates: candidates, matching: query)
            .map { entries[$0] }
    }

    func copyQuickEntry(at index: Int) {
        let matches = filteredQuickEntries
        guard matches.indices.contains(index) else { return }
        copyQuickEntry(matches[index])
    }

    func copySelectedQuickEntry() {
        let count = filteredQuickEntries.count
        guard count > 0 else { return }
        copyQuickEntry(at: clampedQuickSelectionIndex(for: count))
    }

    func copySelectedQuickEntryOnly() {
        guard let entry = selectedQuickEntry else { return }
        copyOnlyQuickEntry(entry)
    }

    func togglePinSelectedQuickEntry() {
        guard let entry = selectedQuickEntry else { return }
        togglePin(entry)
        quickSelectionIndex = clampedQuickSelectionIndex(for: filteredQuickEntries.count)
    }

    func removeSelectedQuickEntry() {
        guard let entry = selectedQuickEntry else { return }
        remove(entry)
        quickSelectionIndex = clampedQuickSelectionIndex(for: filteredQuickEntries.count)
    }

    func moveQuickSelection(_ delta: Int) {
        let count = filteredQuickEntries.count
        guard count > 0 else {
            quickSelectionIndex = 0
            return
        }
        quickSelectionIndex = min(max(quickSelectionIndex + delta, 0), count - 1)
    }

    func copyQuickEntry(_ entry: ClipboardHistoryEntry) {
        copy(entry)
        let target = pasteTargetApp
        hideHistoryWindow()
        pasteTargetApp = nil
        pasteIntoPreviousApp(target)
    }

    func copyOnlyQuickEntry(_ entry: ClipboardHistoryEntry) {
        copy(entry)
        hideHistoryWindow()
        pasteTargetApp = nil
    }

    private func start() {
        guard timer == nil else {
            isRunning = true
            return
        }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.captureIfChanged()
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
        captureIfChanged()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    private func captureIfChanged() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string) else { return }
        promote(text)
    }

    private func promote(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maxCharacters else { return }
        if UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistorySkipSensitive),
           looksSensitive(text) {
            return
        }

        let existing = entries.first(where: { $0.text == text })
        entries.removeAll { $0.text == text }
        if let existing {
            insertPromoted(ClipboardHistoryEntry(id: existing.id,
                                                 text: text,
                                                 copiedAt: Date(),
                                                 pinnedAt: existing.pinnedAt))
        } else {
            insertPromoted(ClipboardHistoryEntry(text: text))
        }
        normalizeEntryOrder()
        trimToLimit()
        save()
    }

    private func trimToLimit() {
        let limit = Defaults.sanitizedClipboardHistoryLimit(
            UserDefaults.standard.integer(forKey: DefaultsKey.clipboardHistoryLimit)
        )
        let pinned = entries.filter(\.isPinned)
        var recent = entries.filter { !$0.isPinned }
        if recent.count > limit {
            recent.removeSubrange(limit..<recent.count)
        }
        entries = pinned + recent
    }

    private var firstRecentIndex: Int {
        entries.firstIndex { !$0.isPinned } ?? entries.endIndex
    }

    private func insertPromoted(_ entry: ClipboardHistoryEntry) {
        if entry.isPinned {
            entries.insert(entry, at: 0)
        } else {
            entries.insert(entry, at: firstRecentIndex)
        }
    }

    private func normalizeEntryOrder() {
        let pinned = entries.filter(\.isPinned)
        let recent = entries.filter { !$0.isPinned }
        entries = pinned + recent
    }

    private func moveDestination(for entry: ClipboardHistoryEntry,
                                 _ direction: ClipboardHistoryMoveDirection) -> Int? {
        let groupIndices = entries.indices.filter { entries[$0].isPinned == entry.isPinned }
        guard let groupPosition = groupIndices.firstIndex(where: { entries[$0].id == entry.id }) else {
            return nil
        }
        switch direction {
        case .up:
            guard groupPosition > groupIndices.startIndex else { return nil }
            return groupIndices[groupIndices.index(before: groupPosition)]
        case .down:
            let next = groupIndices.index(after: groupPosition)
            guard next < groupIndices.endIndex else { return nil }
            return groupIndices[next]
        }
    }

    private func looksSensitive(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let obviousWords = ["password", "passwd", "secret", "token", "apikey", "api_key", "authorization"]
        if obviousWords.contains(where: lowered.contains) { return true }

        guard text.count >= 20, text.count <= 160, !text.contains(where: { $0.isWhitespace }) else {
            return false
        }
        let hasLetter = text.contains { $0.isLetter }
        let hasDigit = text.contains { $0.isNumber }
        let hasSymbol = text.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
        return hasLetter && hasDigit && hasSymbol
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.clipboardHistoryEntries),
              let decoded = try? JSONDecoder().decode([ClipboardHistoryEntry].self, from: data)
        else { return }
        entries = decoded
        normalizeEntryOrder()
        trimToLimit()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: DefaultsKey.clipboardHistoryEntries)
    }

    // MARK: - Shortcut

    func syncHotkey() {
        let wanted = UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryEnabled)
            && UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryShortcutEnabled)
        wanted ? registerHotkey() : unregisterHotkey()
    }

    private func registerHotkey() {
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.clipboardHistoryShortcut,
                                            fallback: .clipboardDefault)
        if hotKeyRef != nil, registeredShortcut == shortcut { return }
        unregisterHotkey()
        if hotKeyHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                if let event {
                    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &id)
                }
                guard id.id == 3 else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<ClipboardHistoryService>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { service.toggleHistoryWindow() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        }
        let id = EventHotKeyID(signature: 0x5655_434C, id: 3) // 'VUCL'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.carbonKeyCode,
                                         shortcut.carbonModifiers,
                                         id, GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRef = ref
            registeredShortcut = shortcut
            shortcutRegistrationFailed = false
        } else {
            hotKeyRef = nil
            registeredShortcut = nil
            shortcutRegistrationFailed = true
        }
    }

    private func unregisterHotkey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        registeredShortcut = nil
        shortcutRegistrationFailed = false
    }

    // MARK: - Quick window

    func toggleHistoryWindow() {
        if panel?.isVisible == true {
            hideHistoryWindow()
        } else {
            showHistoryWindow()
        }
    }

    func showHistoryWindow() {
        let panel = ensurePanel()
        rememberPasteTarget()
        quickQuery = ""
        resetQuickSelection()
        position(panel)
        installKeyMonitor(for: panel)
        installDismissMonitors(for: panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hideHistoryWindow() {
        removeKeyMonitor()
        removeDismissMonitors()
        panel?.orderOut(nil)
    }

    private func rememberPasteTarget() {
        let ownBundleID = Bundle.main.bundleIdentifier
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != ownBundleID,
              app.activationPolicy == .regular,
              !app.isTerminated
        else {
            pasteTargetApp = nil
            return
        }
        pasteTargetApp = app
    }

    private func pasteIntoPreviousApp(_ app: NSRunningApplication?) {
        guard let app, !app.isTerminated else { return }
        app.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.postPasteShortcut()
        }
    }

    private static func postPasteShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source,
                                    virtualKey: CGKeyCode(kVK_ANSI_V),
                                    keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source,
                                  virtualKey: CGKeyCode(kVK_ANSI_V),
                                  keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.title = FeatureStrings.clipboard(L10n.shared.language).title
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: ClipboardQuickPanelView())
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? NSSize(width: 520, height: 560)
        let screen = NSScreen.withMouse.visibleFrame
        let x = screen.midX - size.width / 2
        let y = min(screen.maxY - size.height - 54, screen.midY - size.height / 2)
        panel.setFrame(NSRect(x: max(screen.minX + 16, min(x, screen.maxX - size.width - 16)),
                              y: max(screen.minY + 16, y),
                              width: size.width,
                              height: size.height),
                       display: true,
                       animate: false)
    }

    private func installKeyMonitor(for panel: NSPanel) {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.hideHistoryWindow()
                return nil
            }
            if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
                let enterModifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
                if enterModifiers == [.shift] {
                    self.copySelectedQuickEntryOnly()
                    return nil
                }
                if enterModifiers.isEmpty {
                    self.copySelectedQuickEntry()
                    return nil
                }
                return event
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
            if modifiers == [.option], event.keyCode == UInt16(kVK_ANSI_P) {
                self.togglePinSelectedQuickEntry()
                return nil
            }
            if modifiers == [.option],
               event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
                self.removeSelectedQuickEntry()
                return nil
            }
            if event.keyCode == UInt16(kVK_DownArrow) {
                self.moveQuickSelection(1)
                return nil
            }
            if event.keyCode == UInt16(kVK_UpArrow) {
                self.moveQuickSelection(-1)
                return nil
            }
            if modifiers == [.command],
               let index = Self.digitIndex(for: event.keyCode) {
                self.copyQuickEntry(at: index)
                return nil
            }
            return event
        }
    }

    private func installDismissMonitors(for panel: NSPanel) {
        removeDismissMonitors()
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) {
                self.hideHistoryWindow()
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel) {
                self.hideHistoryWindow()
            }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            self.hideHistoryWindow()
        }
    }

    private static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func removeDismissMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func resetQuickSelection() {
        quickSelectionIndex = ClipboardHistorySelection.initialIndex(totalCount: filteredQuickEntries.count,
                                                                    pinnedCount: pinnedEntries.count,
                                                                    query: quickQuery)
    }

    private static func digitIndex(for keyCode: UInt16) -> Int? {
        switch Int(keyCode) {
        case kVK_ANSI_1: return 0
        case kVK_ANSI_2: return 1
        case kVK_ANSI_3: return 2
        case kVK_ANSI_4: return 3
        case kVK_ANSI_5: return 4
        case kVK_ANSI_6: return 5
        case kVK_ANSI_7: return 6
        case kVK_ANSI_8: return 7
        case kVK_ANSI_9: return 8
        default: return nil
        }
    }

    private func clampedQuickSelectionIndex(for count: Int) -> Int {
        min(max(quickSelectionIndex, 0), max(count - 1, 0))
    }
}
