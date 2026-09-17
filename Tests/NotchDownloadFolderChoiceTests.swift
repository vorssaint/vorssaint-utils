// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The chooser and its cancellation/return methods are extracted from production.
/// These objects model native dismissal order without creating windows or reading UI.
enum NotchDownloadFolderChoiceContract {
    final class Window {
        var isVisible = true
        var attachedSheet: Panel?
        var focusReturns = 0
        func makeKeyAndOrderFront(_ sender: Any?) {
            focusReturns += 1
            NSApp.keyWindow = self
        }
    }
    typealias NSWindow = Window
    struct Event { let window: Window? }
    enum NSApplication { enum ModalResponse { case OK, cancel } }
    struct Location {
        var fails = false
        func bookmarkData(options: URL.BookmarkCreationOptions,
                          includingResourceValuesForKeys: [URLResourceKey]?, relativeTo: URL?) throws -> Data {
            if fails { throw CocoaError(.fileReadNoPermission) }
            return Data([1, 2, 3])
        }
    }
    final class Panel {
        var canChooseFiles = true
        var canChooseDirectories = false
        var allowsMultipleSelection = true
        var directoryURL: URL?
        var message = ""
        var url: Location? = Location()
        weak var parent: Window?
        var standalone = false
        private var completed: ((NSApplication.ModalResponse) -> Void)?
        func beginSheetModal(for parent: Window, completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
            self.parent = parent
            parent.attachedSheet = self
            completed = completionHandler
        }
        func begin(completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
            standalone = true
            completed = completionHandler
        }
        func finish(_ response: NSApplication.ModalResponse) {
            parent?.attachedSheet = nil
            completed?(response)
            // Reproduce AppKit restoring a key window after calling completion.
            NSApp.keyWindow = NSApp.settingsWindow
        }
        func cancel(_ sender: Any?) { finish(.cancel) }
    }
    typealias NSOpenPanel = Panel
    final class Application {
        let settingsWindow = Window()
        var currentEvent: Event?
        var keyWindow: Window?
        var activatedWithAttachedSheet = false
        func activate(ignoringOtherApps: Bool) {
            let notch = NotchService.shared
            activatedWithAttachedSheet = notch.presentationWindow?.attachedSheet != nil
            if currentEvent?.window === notch.presentationWindow,
               !activatedWithAttachedSheet, !notch.pinned { notch.expanded = false }
            keyWindow = settingsWindow
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
        var presentationWindow: Window? = Window()
        var acceptsSystemFeedback = true
        var expanded = true
        var selected: NotchModule = .downloads
        var showingAppPanel = false
        var selectedMetric: Bool?
        var captureControls: Bool?
        var pinned = false
        var syncs = 0
        func syncWithPreferences() { syncs += 1 }
        func open(_ module: NotchModule, feedback: Bool) {
            selected = module
            expanded = true
            presentationWindow?.makeKeyAndOrderFront(nil)
        }
    }
    enum NotchSupport {
        static var enabled = true
        static var downloadsVisible = true
        static func isEnabled() -> Bool { enabled }
        static func modules() -> [NotchModule] { downloadsVisible ? [.downloads] : [.music] }
    }
    enum AppFeature {
        static let notchDownloads = Feature()
        final class Feature { var isAvailable = true }
    }
    enum UserDefaults {
        static var standard = Store()
        final class Store {
            var values: [String: Any] = [:]
            func set(_ value: Any, forKey key: String) { values[key] = value }
        }
    }
    enum L10n {
        static let shared = Localization()
        final class Localization { let language: AppLanguage = .enUS }
    }

    static func reset(fromNotch: Bool = true, pinned: Bool = false, menuAction: Bool = false) {
        NSApp = Application()
        DispatchQueue.main = DispatchQueue.Queue()
        NotchService.shared = NotchService()
        NotchService.shared.pinned = pinned
        NotchSupport.enabled = true
        NotchSupport.downloadsVisible = true
        AppFeature.notchDownloads.isAvailable = true
        UserDefaults.standard = UserDefaults.Store()
        let origin = fromNotch ? NotchService.shared.presentationWindow : NSApp.settingsWindow
        NSApp.keyWindow = origin
        NSApp.currentEvent = menuAction ? nil : Event(window: origin)
    }
}

enum NotchDownloadFolderChoiceTests {
    private typealias Context = NotchDownloadFolderChoiceContract

    static func run(expect: (Bool, String) -> Void) {
        for pinned in [false, true] {
            for menu in [false, true] {
                Context.reset(pinned: pinned, menuAction: menu)
                let service = Context.Service()
                let notch = Context.NotchService.shared
                let window = notch.presentationWindow!
                service.chooseFolder()
                guard let panel = service.chooser else { expect(false, "the folder chooser was created"); continue }
                expect(panel.parent === window && !panel.standalone && Context.NSApp.activatedWithAttachedSheet,
                       "notch buttons and menus attach the picker before application activation")
                expect(notch.expanded && notch.pinned == pinned,
                       "opening the native sheet preserves the working surface and existing pin")
                panel.finish(.OK)
                expect(Context.NSApp.keyWindow !== window && window.focusReturns == 0,
                       "focus is not restored before native dismissal finishes")
                Context.DispatchQueue.main.drain()
                expect(Context.NSApp.keyWindow === window && window.focusReturns == 1 && notch.pinned == pinned,
                       "successful folder selection returns to the same Downloads surface without altering pin")
                expect(Context.UserDefaults.standard.values[DefaultsKey.notchDownloadsFolderBookmark] as? Data == Data([1, 2, 3])
                       && Context.UserDefaults.standard.values[DefaultsKey.notchDownloadsEnabled] as? Bool == true,
                       "only successful selection saves the folder authority and enables monitoring")
            }
        }
        Context.reset()
        let cancelled = Context.Service()
        let original = Context.NotchService.shared.presentationWindow!
        cancelled.chooseFolder()
        cancelled.chooser?.finish(.cancel)
        Context.DispatchQueue.main.drain()
        expect(original.focusReturns == 1 && Context.UserDefaults.standard.values.isEmpty,
               "Cancel returns to the still-open origin without saving a folder or enabling downloads")

        Context.reset(fromNotch: false, pinned: true)
        let settings = Context.Service()
        let backgroundNotch = Context.NotchService.shared.presentationWindow!
        settings.chooseFolder()
        expect(settings.chooser?.standalone == true && settings.chooser?.parent == nil,
               "a Settings action never borrows a pinned notch as its parent")
        settings.chooser?.finish(.OK)
        Context.DispatchQueue.main.drain()
        expect(backgroundNotch.focusReturns == 0 && Context.NSApp.keyWindow === Context.NSApp.settingsWindow,
               "Settings selection stays in Settings and never opens or focuses the notch")

        for interruption in 0..<7 {
            Context.reset()
            let service = Context.Service()
            let window = Context.NotchService.shared.presentationWindow!
            service.chooseFolder()
            let panel = service.chooser!
            switch interruption {
            case 0: service.stop()
            case 1: Context.AppFeature.notchDownloads.isAvailable = false
            case 2: Context.NotchService.shared.acceptsSystemFeedback = false
            case 3: Context.NotchService.shared.selected = .music
            case 4: Context.NotchService.shared.expanded = false
            case 5: Context.NotchService.shared.presentationWindow = Context.Window()
            default: Context.NotchSupport.downloadsVisible = false
            }
            panel.finish(.OK)
            Context.DispatchQueue.main.drain()
            expect(window.focusReturns == 0 && Context.UserDefaults.standard.values.isEmpty,
                   "stop, disable, lock, section change, collapse, replacement or hide rejects the stale folder result")
        }
        for interruption in 0..<4 {
            Context.reset()
            let service = Context.Service()
            let window = Context.NotchService.shared.presentationWindow!
            service.chooseFolder()
            service.chooser?.finish(.OK)
            switch interruption {
            case 0: service.stop()
            case 1: Context.NotchService.shared.selected = .music
            case 2: Context.NotchService.shared.expanded = false
            default: Context.AppFeature.notchDownloads.isAvailable = false
            }
            Context.DispatchQueue.main.drain()
            expect(window.focusReturns == 0, "an interruption during native dismissal cancels the deferred focus return too")
        }
        Context.reset()
        let newer = Context.Service()
        let window = Context.NotchService.shared.presentationWindow!
        newer.chooseFolder()
        newer.chooser?.finish(.OK)
        Context.NSApp.currentEvent = Context.Event(window: Context.NSApp.settingsWindow)
        Context.NSApp.keyWindow = Context.NSApp.settingsWindow
        newer.chooseFolder()
        newer.chooser?.finish(.cancel)
        Context.DispatchQueue.main.drain()
        expect(window.focusReturns == 0, "a newer Settings chooser supersedes the old pending notch return")

        Context.reset()
        let failed = Context.Service()
        let failureOrigin = Context.NotchService.shared.presentationWindow!
        failed.chooseFolder()
        failed.chooser?.url = Context.Location(fails: true)
        failed.chooser?.finish(.OK)
        Context.DispatchQueue.main.drain()
        expect(failed.folderUnavailable && failureOrigin.focusReturns == 1 && Context.UserDefaults.standard.values.isEmpty,
               "a failed folder grant returns to the existing error surface without saving or enabling anything")
    }
}
