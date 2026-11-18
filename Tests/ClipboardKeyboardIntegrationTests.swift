// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Executes the production paste routing with a deferred delivery queue. No
/// system pasteboard, application activation or permission prompts are used.
enum ClipboardKeyboardIntegrationTests {
    // Only the AppKit boundary is doubled. The generated monitor methods and
    // selection handlers below are extracted from production without reordering.
    enum Monitor {
        final class NSPanel {
            var attachedSheet: NSPanel?
            var firstResponder: AnyObject?
        }
        final class NSView {
            let window: NSPanel?
            init(window: NSPanel) { self.window = window }
        }
        final class NSTextView {
            var isFieldEditor = true
            var isEditable = true
            func hasMarkedText() -> Bool { false }
            func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
        }
        final class Application { var modalWindow: NSPanel? }
        static let NSApp = Application()
        final class NSEvent {
            typealias ModifierFlags = AppKit.NSEvent.ModifierFlags
            typealias EventType = AppKit.NSEvent.EventType
            typealias EventTypeMask = AppKit.NSEvent.EventTypeMask
            static var mouseLocation: CGPoint { .zero }
            static var handler: ((NSEvent) -> NSEvent?)?
            let native: AppKit.NSEvent
            let window: NSPanel?
            var type: EventType { native.type }
            var modifierFlags: ModifierFlags { native.modifierFlags }
            var keyCode: UInt16 { native.keyCode }
            var charactersIgnoringModifiers: String? { native.charactersIgnoringModifiers }
            init(_ code: UInt16, _ flags: ModifierFlags, window: NSPanel?,
                 type: EventType = .keyDown) {
                self.window = window
                native = AppKit.NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                    timestamp: 0, windowNumber: 0, context: nil, characters: "",
                    charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
            }
            static func addLocalMonitorForEvents(matching: EventTypeMask,
                handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
                self.handler = handler
                return 1
            }
            static func removeMonitor(_ monitor: Any) { handler = nil }
        }
    }

    final class Host {
        final class App {
            var isTerminated = false
            func activate(options: [Int]) { Host.current?.events.append("activate") }
        }
        typealias NSRunningApplication = App
        enum NSSound {
            static func beep() { Host.current?.events.append("beep") }
        }
        enum Permissions {
            static let shared = Access()
            final class Access {
                func requestAccessibility() { Host.current?.events.append("prompt") }
            }
        }
        enum DispatchQueue {
            static let main = Queue()
            final class Queue {
                func asyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) {
                    Host.current?.pending = execute
                }
            }
        }
        static var current: Host?
        var events: [String] = []
        var pending: (() -> Void)?
        var trusted = true
        var promptedForAccessibility = false
        init() { Self.current = self }
        func AXIsProcessTrusted() -> Bool { trusted }

        enum NSCursor {
            static func setHiddenUntilMouseMoves(_ hidden: Bool) {}
        }
        typealias NSEvent = Monitor.NSEvent
        typealias NSPanel = Monitor.NSPanel
        typealias NSTextView = Monitor.NSTextView
        var keyMonitor: Any?
        var quickQuery = ""
        var quickLayout = ClipboardHistoryLayout.list
        var quickBatchCount: Int { quickBatchEntryIDs.count }
        func removeKeyMonitor() { keyMonitor = nil }
        func clearQuickBatchSelection() { quickBatchEntryIDs = [] }
        func hideHistoryWindow() { events.append("hide") }
        func toggleQuickPreview() { events.append("preview") }
        func toggleSelectedQuickEntryBatchSelection() { events.append("toggle") }
        func copySelectedQuickEntryOnly() { events.append("copyOnly") }
        func copySelectedQuickEntry() { events.append("copy") }
        func selectAllQuickEntries() { events.append("selectAll") }
        func togglePinSelectedQuickEntry() { events.append("pin") }
        func removeSelectedQuickEntries() { events.append("remove") }
        func moveQuickSelection(_ step: Int) { events.append("legacyMove") }
        static func digitIndex(for code: UInt16) -> Int? { nil }
        func copyQuickEntry(at index: Int) { events.append("digit") }
        var keyboardSelectionPointer = CGPoint.zero
        var quickKeyboardSelection = ClipboardKeyboardSelection()
        var quickListNavigationActive = false
        var quickBatchEntryIDs: Set<UUID> = []
        var quickSelectionID: UUID?
        var quickSelectionIsVisible = false
        var entries: [ClipboardHistoryEntry] = []
        var filteredQuickEntries: [ClipboardHistoryEntry] = []
        var selectedQuickEntryID: UUID? { quickSelectionID ?? filteredQuickEntries.first?.id }
        var copiedBatches: [[UUID]] = []
        var pendingCopy: ((Bool) -> Void)?
        func copy(_ entries: [ClipboardHistoryEntry], completion: @escaping (Bool) -> Void) {
            copiedBatches.append(entries.map(\.id))
            pendingCopy = completion
        }
        static func postPasteShortcut() { current?.events.append("paste") }
    }

    static func run(_ suite: TestSuite) {
        batchChecks(suite)
        lifecycleChecks(suite)
        MainActor.assumeIsolated { monitorChecks(suite) }
        let host = Host()
        let target = Host.App()
        host.pasteIntoPreviousApp(target)
        suite.expect(host.events == ["activate"], "paste waits for the original target to activate")
        target.isTerminated = true
        host.pending?()
        suite.expect(host.events == ["activate", "beep"],
                     "a target exiting during activation never pastes into another application")
        let success = Host()
        success.pasteIntoPreviousApp(Host.App())
        success.pending?()
        suite.expect(success.events == ["activate", "paste"], "a live target receives exactly one deferred paste")
        Host.current = nil
    }

    @MainActor static func monitorChecks(_ suite: TestSuite) {
        typealias Event = Monitor.NSEvent
        // Shift release ends extension; either modifier release ends inversion.
        let cases: [(String, Event.ModifierFlags, Event.ModifierFlags, Event.ModifierFlags, Set<Int>)] = [
            ("Shift", .shift, [], .shift, [1, 2, 3]),
            ("Command", [.command, .shift], .shift, [.command, .shift], [1]),
            ("Shift with Command held", [.command, .shift], .command, [.command, .shift], [1])
        ]
        for (release, initialFlags, remainingFlags, resumedFlags, finalIndices) in cases {
            let records = ["A", "B", "C", "D", "E"].map { ClipboardHistoryEntry(text: $0) }
            let ids = records.map(\.id)
            let host = Host()
            host.entries = records
            host.filteredQuickEntries = records
            host.quickSelectionID = ids[1]
            host.quickSelectionIsVisible = true
            host.quickBatchEntryIDs = initialFlags == .shift ? [ids[1]] : []
            let panel = Monitor.NSPanel()
            host.installKeyMonitor(for: panel)
            let panelHandler = Event.handler!

            let page = NotchClipboardPageTests.Page()
            page.entries = records.map { .init(id: $0.id) }
            page.history.entries = page.entries
            page.appeared()
            page.highlightedID = ids[1]
            page.keysMoved = true
            page.selectedIDs = initialFlags == .shift ? [ids[1]] : []
            let window = Monitor.NSPanel()
            let view = Monitor.NSView(window: window)
            let coordinator = Monitor.Coordinator(handleKey: { event, composing, editing, selection in
                page.handleKey(event.native, composing: composing, editing: editing, searchHasSelection: selection)
            }, composed: {})
            coordinator.install(for: view)
            let notchHandler = Event.handler!
            defer { coordinator.removeMonitor() }

            let endpoints: [(String, Monitor.NSPanel, (Event) -> Event?, () -> Set<UUID>, () -> UUID?, () -> Bool)] = [
                ("panel", panel, panelHandler, { host.quickBatchEntryIDs }, { host.quickSelectionID },
                 { host.quickKeyboardSelection.isActive }),
                ("notch", window, notchHandler, { page.selectedIDs }, { page.highlightedID },
                 { page.keyboardSelection.isActive })
            ]
            for (name, owner, send, selected, focus, active) in endpoints {
                for _ in 0..<2 {
                    suite.expect(send(Event(125, initialFlags, window: owner)) == nil,
                                 "\(name): selection arrows reach the production handler")
                }
                suite.expect(selected() == Set([ids[1], ids[2], ids[3]]) && focus() == ids[3] && active(),
                             "\(name): \(release) fixture establishes BCD with focus D")
                let dialog = Monitor.NSPanel()
                defer { Monitor.NSApp.modalWindow = nil }
                // Also check an unrelated window without modal/sheet guards:
                // removing the window identity filter must fail this test.
                for dialogActive in [false, true] {
                    owner.attachedSheet = dialogActive ? dialog : nil
                    Monitor.NSApp.modalWindow = dialogActive ? dialog : nil
                    for code: UInt16 in [126, 36, 53] {
                        let event = Event(code, initialFlags, window: dialog)
                        suite.expect(send(event) === event && selected() == Set([ids[1], ids[2], ids[3]])
                                     && focus() == ids[3] && active(),
                                     "\(name): another window keeps keyDown \(code), dialog active: \(dialogActive)")
                    }
                }
                let event = Event(release == "Command" ? 55 : 56, remainingFlags,
                                  window: dialog, type: .flagsChanged)
                suite.expect(send(event) === event && !active()
                             && selected() == Set([ids[1], ids[2], ids[3]]) && focus() == ids[3],
                             "\(name): \(release) release in a dialog ends the session and retains BCD/focus D")
                owner.attachedSheet = nil
                Monitor.NSApp.modalWindow = nil
                suite.expect(send(Event(126, resumedFlags, window: owner)) == nil
                             && selected() == Set(finalIndices.map { ids[$0] }) && focus() == ids[2],
                             "\(name): after cancelling a dialog, \(release) starts a fresh session at D")
            }
            suite.expect(host.events.isEmpty, "dialog keys never invoke panel actions or legacy navigation")
            page.disappeared()
        }
        Event.handler = nil
        Host.current = nil
    }

    static func batchChecks(_ suite: TestSuite) {
        let records = ["A", "B", "C", "D"].map { ClipboardHistoryEntry(text: $0) }
        let host = Host()
        host.entries = records
        host.filteredQuickEntries = records
        host.quickSelectionID = records[0].id
        host.quickSelectionIsVisible = true
        host.navigateQuickSelection(.extend(1))
        host.navigateQuickSelection(.skip(1))
        suite.expect(host.quickBatchEntryIDs == Set([records[0].id, records[1].id])
                     && host.quickSelectionID == records[2].id,
                     "panel skip moves highlight without adding it to the batch")
        host.navigateQuickSelection(.toggle(1))
        let snapshot = host.batchEntries(selectedIDs: host.quickBatchEntryIDs)
        suite.expect(snapshot.map(\.text) == ["A", "B", "C", "D"],
                     "panel inversion includes its anchor C and target D while preserving the selected A B base")
        host.filteredQuickEntries = records.reversed()
        suite.expect(host.batchEntries(selectedIDs: host.quickBatchEntryIDs).map(\.text) == ["A", "B", "C", "D"],
                     "search ranking never changes historical batch order")
        let target = Host.App()
        host.activateBatch(snapshot, paste: true, target: target) { _ in }
        host.entries = []
        host.quickBatchEntryIDs = []
        suite.expect(host.copiedBatches == [snapshot.map(\.id)] && host.events.isEmpty,
                     "batch writes one captured snapshot before any paste or activation")
        host.pendingCopy?(true)
        host.pending?()
        suite.expect(host.events == ["activate", "paste"],
                     "clearing UI state while writing cannot change the captured batch or target")

        let failed = Host()
        var result: Bool?
        failed.activateBatch(snapshot, paste: true, target: target) { result = $0 }
        failed.pendingCopy?(false)
        suite.expect(result == false && failed.events == ["beep"] && failed.pending == nil,
                     "failed batch writes never activate or paste stale clipboard data")
        let exitsDuringWrite = Host()
        let departingTarget = Host.App()
        exitsDuringWrite.activateBatch(snapshot, paste: true, target: departingTarget) { result = $0 }
        departingTarget.isTerminated = true
        exitsDuringWrite.pendingCopy?(true)
        suite.expect(result == false && exitsDuringWrite.events == ["beep"] && exitsDuringWrite.pending == nil,
                     "a target exiting while batch content is written never reports activation success")
        let revoked = Host()
        revoked.activateBatch(snapshot, paste: true, target: target) { result = $0 }
        revoked.trusted = false
        revoked.pendingCopy?(true)
        suite.expect(result == true && revoked.events.isEmpty && revoked.pending == nil,
                     "a revoked grant keeps the copy without prompting or sending paste")
        let copyOnly = Host()
        copyOnly.activateBatch(snapshot, paste: false, target: nil) { result = $0 }
        copyOnly.pendingCopy?(true)
        suite.expect(result == true && copyOnly.events.isEmpty && copyOnly.pending == nil,
                     "permission fallback copies a complete batch without activating another app")
        let exited = Host()
        target.isTerminated = true
        exited.activateBatch(snapshot, paste: true, target: target) { result = $0 }
        suite.expect(result == false && exited.copiedBatches.isEmpty && exited.pending == nil,
                     "a terminated original target rejects batch paste without another target")
        let empty = Host()
        empty.activateBatch([], paste: true, target: target) { result = $0 }
        suite.expect(result == false && empty.copiedBatches.isEmpty && empty.pending == nil,
                     "empty results never fall back to an unrelated history entry")
        Host.current = nil
    }

    static func lifecycleChecks(_ suite: TestSuite) {
        let records = ["row A", "row B", "row C", "row D"].map { ClipboardHistoryEntry(text: $0) }
        let panel = ClipboardPreviewContract.Service()
        panel.setEntries(records)
        panel.quickQuery = "row"
        suite.expect(panel.quickNavigationAction(keyCode: 125, flags: [.shift], searchHasSelection: false) == nil,
                     "nonempty search keeps selection chords until list navigation")
        panel.moveQuickSelection(1)
        suite.expect(panel.quickSelectionID == records[0].id && panel.quickSelectionIsVisible,
                     "first plain navigation reveals the first item without skipping it")
        suite.expect(panel.quickNavigationAction(keyCode: 125, flags: [.shift], searchHasSelection: false) == .extend(1),
                     "ordinary navigation gives search results ownership of Shift ranges")
        panel.navigateQuickSelection(.extend(1))
        suite.expect(panel.quickBatchEntryIDs == Set([records[0].id, records[1].id]),
                     "T01: routed range selects the initial anchor and new target")
        _ = panel.quickNavigationAction(keyCode: 125, flags: [.command, .shift], searchHasSelection: true)
        suite.expect(panel.quickNavigationAction(keyCode: 125, flags: [.shift], searchHasSelection: false) == nil,
                     "search text selection returns chord ownership until list navigation resumes")
        let resumed = panel.quickNavigationAction(keyCode: 125, flags: [], searchHasSelection: false)
        suite.expect(resumed == .skip(1), "plain arrows can resume list navigation after text selection collapses")
        if let resumed { panel.navigateQuickSelection(resumed) }
        let originalSelection = Set([records[0].id, records[1].id])
        panel.quickQuery = "row A"
        suite.expect(panel.quickBatchEntryIDs == originalSelection && !panel.quickKeyboardSelection.isActive,
                     "T09: filtering preserves valid UUIDs including hidden selected entries")
        panel.quickQuery = "no results"
        suite.expect(panel.quickSelectionID == nil && panel.quickBatchEntryIDs == originalSelection,
                     "empty visible results clear focus without losing hidden history selection")
        panel.quickQuery = "row"
        let inserted = ClipboardHistoryEntry(text: "row X")
        panel.setEntries([inserted] + records)
        suite.expect(panel.quickBatchEntryIDs == originalSelection && !panel.quickBatchEntryIDs.contains(inserted.id),
                     "T14: insertion does not shift selection identities")
        panel.setEntries([inserted, records[1], records[2], records[3]])
        suite.expect(panel.quickBatchEntryIDs == [records[1].id]
                     && panel.filteredQuickEntries.contains(where: { $0.id == panel.quickSelectionID }),
                     "T14: deletion prunes only the missing ID and restores a valid focus")
        panel.setEntries(records)
        panel.quickQuery = ""
        panel.clearQuickBatchSelection()
        panel.toggleQuickBatchSelection(records[1])
        panel.extendQuickBatchSelection(to: records[3])
        panel.extendQuickBatchSelection(to: records[2])
        suite.expect(panel.quickBatchEntryIDs == Set([records[1].id, records[2].id])
                     && panel.quickSelectionID == records[2].id,
                     "T15: real mouse selection methods keep the anchor while shrinking")
        panel.quickKeyboardSelection.modifiersChanged([])
        panel.navigateQuickSelection(.extend(-1))
        suite.expect(panel.quickBatchEntryIDs == [records[1].id],
                     "mouse range and keyboard range share the same anchor and base")
        panel.clearQuickBatchSelection()
        panel.toggleQuickBatchSelection(records[1])
        panel.toggleQuickBatchSelection(records[3])
        panel.toggleQuickBatchSelection(records[1])
        panel.toggleQuickBatchSelection(records[1])
        panel.extendQuickBatchSelection(to: records[2], additive: true)
        suite.expect(panel.quickBatchEntryIDs == Set([records[1].id, records[2].id, records[3].id]),
                     "Cmd-Shift-click adds a complete range and keeps outside selections")
        panel.quickKeyboardSelection.modifiersChanged([])
        let selectedBeforeLayout = panel.quickBatchEntryIDs
        panel.quickLayout = panel.quickLayout == .list ? .cards : .list
        suite.expect(panel.quickBatchEntryIDs == selectedBeforeLayout && !panel.quickKeyboardSelection.isActive,
                     "layout changes end the session while retaining selected UUIDs")
        panel.quickSelectionID = records[1].id
        panel.quickSelectionIsVisible = true
        panel.quickBatchEntryIDs = Set([records[1].id, records[2].id])
        panel.navigateQuickSelection(.toggle(1))
        suite.expect(panel.quickBatchEntryIDs.isEmpty && panel.quickSelectionID == records[2].id,
                     "T06: service inverts the complete selected B-C range including anchor B")
        panel.quickKeyboardSelection.modifiersChanged([.shift])
        panel.navigateQuickSelection(.extend(1))
        suite.expect(panel.quickBatchEntryIDs == Set([records[2].id, records[3].id]),
                     "T13: releasing Command starts a fresh inclusive range from the inverted base")
        panel.clearQuickBatchSelection()
        panel.toggleQuickBatchSelection(records[1])
        panel.toggleQuickBatchSelection(records[3])
        panel.quickSelectionID = records[2].id
        panel.removeSelectedQuickEntries()
        suite.expect(panel.entries == [records[0], records[2]] && panel.quickBatchEntryIDs.isEmpty,
                     "T12: batch deletion removes only selected B/D while leaving unselected focus C")
        panel.quickQuery = ""
        panel.setEntries(records)
        panel.clearQuickBatchSelection()
        panel.toggleQuickBatchSelection(records[2])
        panel.toggleQuickBatchSelection(records[1])
        panel.togglePin(records[1])
        suite.expect(panel.quickBatchEntryIDs == Set([records[1].id, records[2].id])
                     && panel.quickSelectionID == records[1].id,
                     "pinning a selected row is one logical reorder and preserves its UUID and focus")
        panel.promote(records[1].text, source: nil, keepsSource: true)
        suite.expect(panel.quickBatchEntryIDs == Set([records[1].id, records[2].id])
                     && panel.quickSelectionID == records[1].id,
                     "recapturing selected text preserves its UUID through promotion")
        let hiddenRecords = ["match A", "match B", "hidden D"].map { ClipboardHistoryEntry(text: $0) }
        panel.setEntries(hiddenRecords)
        panel.quickQuery = "match"
        panel.quickBatchEntryIDs = Set([hiddenRecords[0].id, hiddenRecords[2].id])
        panel.quickSelectionID = hiddenRecords[0].id
        panel.quickSelectionIsVisible = true
        panel.navigateQuickSelection(.extend(1))
        panel.setEntries(Array(hiddenRecords.prefix(2)))
        panel.navigateQuickSelection(.extend(-1))
        suite.expect(!panel.quickBatchEntryIDs.contains(hiddenRecords[2].id),
                     "deleting a hidden selected entry cannot be undone by an older range snapshot")
        panel.setEntries([])
        suite.expect(panel.quickBatchEntryIDs.isEmpty && panel.quickSelectionID == nil,
                     "deleting all history prunes the entire selection and focus")
    }
}
