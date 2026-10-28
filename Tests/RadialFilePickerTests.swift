// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import UniformTypeIdentifiers

/// Executes the production chooser against a deferred panel. Native window
/// placement and SwiftUI sheet dismissal still need an application-level check.
enum RadialFilePickerTests {
    enum NSApplication { enum ModalResponse: Equatable { case OK, cancel, abort } }
    final class Window {
        var isVisible = true
    }
    final class Application {
        let mainWindow = Window()
        var keyWindow: Window? = Window()
        func activate(ignoringOtherApps: Bool) {}
    }
    static var NSApp = Application()

    final class Panel {
        static var current: Panel?
        static var modalResponse = NSApplication.ModalResponse.cancel
        static var modalURL: URL?
        var allowsMultipleSelection = true
        var canChooseFiles = false
        var canChooseDirectories = false
        var allowedContentTypes: [UTType] = []
        var directoryURL: URL?
        var url: URL?
        var parent: Window?
        var ranModal = false
        private var completion: ((NSApplication.ModalResponse) -> Void)?

        init() { Self.current = self }

        func runModal() -> NSApplication.ModalResponse {
            ranModal = true
            url = Self.modalURL
            return Self.modalResponse
        }

        func beginSheetModal(for window: Window,
                             completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
            parent = window
            completion = completionHandler
        }

        func finish(_ response: NSApplication.ModalResponse, url: URL?) {
            self.url = url
            let handler = completion
            completion = nil
            handler?(response)
        }
    }
    typealias NSOpenPanel = Panel

    enum RadialMenuIconStore {
        static var invalidated: [String] = []
        static func invalidate(_ payload: String) { invalidated.append(payload) }
    }

    final class ItemState {
        var item: RadialMenuItem
        init(_ item: RadialMenuItem) { self.item = item }
    }

    static func reset() {
        NSApp = Application()
        Panel.current = nil
        Panel.modalResponse = .cancel
        Panel.modalURL = nil
        RadialMenuIconStore.invalidated = []
    }

    static func run(_ suite: TestSuite) {
        defer { reset() }
        let original = RadialMenuItem(kind: .app, name: "Kept name", symbolName: "star",
                                     payload: "/Applications/Old.app", customIconData: Data([1, 2, 3]))
        let appURL = URL(fileURLWithPath: "/Applications/New.app")

        reset()
        let editor = Editor(state: ItemState(original))
        let editorWindow = NSApp.keyWindow
        editor.choose(applications: true)
        guard let appPanel = Panel.current else {
            suite.expect(false, "radial app selection creates a panel")
            return
        }
        suite.expect(appPanel.parent === editorWindow && appPanel.parent !== NSApp.mainWindow
                     && !appPanel.ranModal,
                     "radial picker attaches to the editor sheet instead of entering an app modal loop")
        suite.expect(appPanel.canChooseFiles && !appPanel.canChooseDirectories
                     && !appPanel.allowsMultipleSelection && appPanel.allowedContentTypes == [.applicationBundle]
                     && appPanel.directoryURL?.path == "/Applications",
                     "radial app selection keeps its single application filter and initial directory")
        suite.expect(editor.item == original && RadialMenuIconStore.invalidated.isEmpty,
                     "opening a radial picker does not change the item before a response")

        let otherEditor = Editor(state: ItemState(RadialMenuItem(kind: .file, payload: "/Other")))
        let otherItem = otherEditor.item
        NSApp.keyWindow = NSApp.mainWindow
        appPanel.finish(.OK, url: appURL)
        var expected = original
        expected.payload = appURL.path
        suite.expect(editor.item == expected && otherEditor.item == otherItem
                     && RadialMenuIconStore.invalidated == [original.payload],
                     "a delayed radial selection updates only its requesting item and invalidates its old icon")

        for (response, url) in [(NSApplication.ModalResponse.cancel, appURL as URL?),
                                (.abort, appURL as URL?), (.OK, nil)] {
            reset()
            let editor = Editor(state: ItemState(original))
            editor.choose(applications: true)
            Panel.current?.finish(response, url: url)
            suite.expect(editor.item == original && RadialMenuIconStore.invalidated.isEmpty,
                         "cancelled, aborted and empty radial selections leave the item untouched")
        }

        reset()
        let fileEditor = Editor(state: ItemState(RadialMenuItem(kind: .file, payload: "/Old")))
        for path in ["/Users/example/report.txt", "/Users/example/Documents"] {
            let previous = fileEditor.item
            fileEditor.choose(applications: false)
            guard let panel = Panel.current else {
                suite.expect(false, "radial file selection creates a panel")
                return
            }
            suite.expect(panel.parent === NSApp.keyWindow && !panel.ranModal
                         && panel.canChooseFiles && panel.canChooseDirectories
                         && !panel.allowsMultipleSelection && panel.allowedContentTypes.isEmpty,
                         "each radial file picker accepts a single file or folder without app restrictions")
            panel.finish(.OK, url: URL(fileURLWithPath: path))
            var expected = previous
            expected.payload = path
            suite.expect(fileEditor.item == expected && RadialMenuIconStore.invalidated.last == previous.payload,
                         "reopening the radial picker replaces the current path and invalidates its icon")
        }

        for missingWindow in [true, false] {
            for response in [NSApplication.ModalResponse.OK, .cancel, .abort] {
                reset()
                if missingWindow { NSApp.keyWindow = nil }
                else { NSApp.keyWindow?.isVisible = false }
                Panel.modalResponse = response
                Panel.modalURL = appURL
                let editor = Editor(state: ItemState(original))
                editor.choose(applications: true)
                var expected = original
                if response == .OK { expected.payload = appURL.path }
                suite.expect(Panel.current?.ranModal == true && Panel.current?.parent == nil
                             && editor.item == expected
                             && RadialMenuIconStore.invalidated == (response == .OK ? [original.payload] : []),
                             "without a visible editor window, the modal fallback applies only a confirmed selection")
            }
        }
    }
}
