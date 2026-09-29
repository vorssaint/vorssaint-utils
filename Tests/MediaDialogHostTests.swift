// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The dialog host is extracted from production. Panels, windows and the
/// application are doubles: no dialog opens and nothing activates.
enum MediaDialogHostContract {
    final class Island {
        var isVisible = true
        var level = NSWindow.Level(rawValue: 26)
        var attachedSheet: NSSavePanel?
        var keyRequests = 0
        func makeKey() { keyRequests += 1 }
    }
    struct Event { let window: Island? }
    final class NSSavePanel {
        static weak var current: NSSavePanel?
        weak var parent: Island?
        var level = NSWindow.Level(rawValue: 0)
        var hidesOnDeactivate = true
        var focused = false
        var modalRuns = 0
        private var completed: ((NSApplication.ModalResponse) -> Void)?
        func beginSheetModal(for parent: Island, completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
            self.parent = parent
            parent.attachedSheet = self
            completed = completionHandler
        }
        func begin(completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
            Self.current = self
            completed = completionHandler
        }
        func makeKeyAndOrderFront(_ sender: Any?) { focused = true }
        func runModal() -> NSApplication.ModalResponse {
            modalRuns += 1
            return .OK
        }
        func finish(_ response: NSApplication.ModalResponse) {
            if Self.current === self { Self.current = nil }
            parent?.attachedSheet = nil
            completed?(response)
        }
    }
    final class Application {
        var currentEvent: Event?
        var keyWindow: Island?
        /// Whether the island's own dialog was already up at each activation.
        var activations: [Bool] = []
        func activate(ignoringOtherApps: Bool) {
            activations.append(NSSavePanel.current != nil)
        }
    }
    static var NSApp = Application()
    enum DispatchQueue {
        static var main = Queue()
        final class Queue {
            var jobs: [() -> Void] = []
            func async(execute action: @escaping () -> Void) { jobs.append(action) }
            func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
        }
    }
    final class NotchService {
        static var shared = NotchService()
        var presentationWindow: Island? = Island()
        var expanded = true
    }
    final class QuickLauncherService {
        static var shared = QuickLauncherService()
        var refocuses = 0
        func refocusAfterModal() { refocuses += 1 }
    }

    static func reset() {
        NSApp = Application()
        DispatchQueue.main = DispatchQueue.Queue()
        NSSavePanel.current = nil
        NotchService.shared = NotchService()
        QuickLauncherService.shared = QuickLauncherService()
        Dialogs.panelModalActive = false
    }
}

enum MediaDialogHostTests {
    private typealias Context = MediaDialogHostContract

    static func run(expect: (Bool, String) -> Void) {
        for viaEvent in [true, false] {
            Context.reset()
            let island = Context.NotchService.shared.presentationWindow!
            if viaEvent { Context.NSApp.currentEvent = Context.Event(window: island) }
            else { Context.NSApp.keyWindow = island }
            let panel = Context.NSSavePanel()
            var responses: [NSApplication.ModalResponse] = []
            Context.Dialogs.runPanelModal(panel) { responses.append($0) }
            expect(panel.parent == nil && island.attachedSheet == nil && panel.focused && panel.modalRuns == 0
                   && panel.level.rawValue > island.level.rawValue && Context.NSApp.activations == [true]
                   && !panel.hidesOnDeactivate,
                   "a dialog begun from the island opens above it on its own before activation, never as a sheet "
                   + "that moves the island or an application-modal window that opens behind it")
            let second = Context.NSSavePanel()
            Context.Dialogs.runPanelModal(second) { _ in }
            expect(second.parent == nil && !second.focused && second.modalRuns == 0 && Context.Dialogs.panelModalActive,
                   "a second request while the dialog is up is ignored")
            panel.finish(.OK)
            expect(responses == [.OK] && !Context.Dialogs.panelModalActive && island.keyRequests == 0,
                   "the completion runs before focus returns, while native dismissal is still restoring key windows")
            Context.DispatchQueue.main.drain()
            expect(island.keyRequests == 1 && Context.QuickLauncherService.shared.refocuses == 0,
                   "focus returns to the still-open island on the next turn")
        }

        Context.reset()
        let collapsing = Context.NotchService.shared.presentationWindow!
        Context.NSApp.currentEvent = Context.Event(window: collapsing)
        let cancelled = Context.NSSavePanel()
        Context.Dialogs.runPanelModal(cancelled) { _ in }
        Context.NotchService.shared.expanded = false
        cancelled.finish(.cancel)
        Context.DispatchQueue.main.drain()
        expect(collapsing.keyRequests == 0 && !Context.Dialogs.panelModalActive,
               "an island that collapsed meanwhile is not made key again")

        for hidden in [false, true] {
            Context.reset()
            let island = Context.NotchService.shared.presentationWindow!
            island.isVisible = !hidden
            Context.NSApp.currentEvent = Context.Event(window: hidden ? island : nil)
            let panel = Context.NSSavePanel()
            var responses: [NSApplication.ModalResponse] = []
            Context.Dialogs.runPanelModal(panel) { responses.append($0) }
            expect(panel.parent == nil && panel.modalRuns == 0 && Context.NSApp.activations == [false]
                   && Context.Dialogs.panelModalActive,
                   "a dialog begun from a popover, the launcher or an ordered-out island activates first and "
                   + "runs modal on the next turn")
            Context.DispatchQueue.main.drain()
            expect(panel.modalRuns == 1 && responses == [.OK] && !Context.Dialogs.panelModalActive
                   && Context.QuickLauncherService.shared.refocuses == 1 && island.keyRequests == 0,
                   "the modal path still hands focus back through the launcher")
        }
    }
}
