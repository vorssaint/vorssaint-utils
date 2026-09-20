// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Production rail, editor, and focus bodies with inert services. Windows stay
/// hidden; these contracts neither capture pixels nor send input events.
enum NotchCompactTests {
    typealias L10n = NotchUpdateTests.L10n
    final class NotchService: ObservableObject {
        @Published var scratchpadCloseSerial = 0
        var contentSize = CGSize(width: 304, height: 122)
        var selected = NotchModule.controls
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                     safeAreaTop: 0, cameraWidth: 0, layout: .custom,
                                     menuBarHeight: 64, customWidth: 360, customHeight: 260)
        func perform(_ action: () -> Void) { action() }
    }
    final class NotchTimerService {
        static let shared = NotchTimerService()
        var session = NotchTimerSession()
    }
    final class ScratchpadService: ObservableObject {
        static let shared = ScratchpadService()
        @Published var text = "original note"
        @Published var isPreviewing = false
        @Published var pads: [ScratchpadPad] = []
        @Published var selectedPadID: UUID?
        var canCreatePad: Bool { true }
        var canClosePad: Bool { false }
        var selectedPadName: String { "pad" }
        var panel: NSPanel?
        weak var textView: NSTextView?
        func flushSave() {}
        func focusText() {}
        func loadForEmbedding() -> Bool { true }
        func commitEdits() {}
        func createPad(defaultName: String) {}
        func closePad(_ id: UUID) -> Bool { true }
        func renamePad(_ id: UUID, to name: String) {}
        func selectPad(_ id: UUID) {}
        func copyAll() {}
        func togglePreview() { isPreviewing.toggle() }
        func show() {}
        func exportText(suggestedName: String) {}
    }
    struct NotchEmptyView: View {
        let symbol: String
        let message: String
        var body: some View { Text(message) }
    }
    struct NotchControlSurface: ViewModifier {
        let cornerRadius: CGFloat
        var interactive = true
        func body(content: Content) -> some View { content }
    }
    struct NotchButtonStyle: ButtonStyle {
        var cornerRadius: CGFloat = 10
        var lifts = true
        func makeBody(configuration: Configuration) -> some View { configuration.label }
    }
    struct NotchIconButton: View {
        let symbol: String
        let title: String
        var selected = false
        let action: () -> Void
        var body: some View { Button(title, action: action) }
    }
    struct MarkdownPreview: View {
        let blocks: [ScratchpadMarkdownBlock]
        var body: some View { Color.clear }
    }
    struct Music { var playback: Bool? = true }
    struct Page {
        var music = Music()
        var showsDetail = false
        var service = NotchService()
        var controls: [NotchControlItem] = [.music, .volume, .brightness, .timer]
    }
    final class Window {
        static var key: Window?
        var isVisible = true
        var isKeyWindow: Bool { Self.key === self }
        var responderChanges = 0
        func makeKey() { Self.key = self }
        func makeFirstResponder(_ view: TextView?) { responderChanges += 1 }
    }
    final class TextView {
        var window: Window?
        var string = "note"
        func setSelectedRange(_ range: NSRange) {}
        func scrollRangeToVisible(_ range: NSRange) {}
    }
    final class Floating {
        var panel: Window? = Window()
        var textView: TextView? = TextView()
    }
    final class Embedded {
        class Handle { var view: TextView? = TextView() }
        var editor = Handle()
        var pad = ScratchpadService.shared
    }
    struct Entry: Identifiable { let id: Int }
    final class RailState: ObservableObject {
        @Published var selected: Int?
        @Published var rows = 2
        var realized = Set<Int>()
    }
    struct Marker: NSViewRepresentable {
        let id: Int
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            view.identifier = NSUserInterfaceItemIdentifier("rail-\(id)")
            return view
        }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }
    struct Rail: View {
        @ObservedObject var state: RailState
        var body: some View {
            let entries = (0..<1000).map { NotchCompactTests.Entry(id: $0) }
            return NotchRail(items: entries, rows: state.rows, itemWidth: 76, width: 424,
                             scrollTarget: state.selected, content: marker)
                .frame(width: 424, height: 152)
        }
        private func marker(_ item: NotchCompactTests.Entry) -> some View {
            state.realized.insert(item.id)
            return NotchCompactTests.Marker(id: item.id).frame(height: 72)
        }
    }

    static func settle(_ view: NSView? = nil) {
        for _ in 0..<30 {
            view?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }
    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
    static func run(_ suite: TestSuite) {
        rail(suite)
        scratchpad(suite)
        focus(suite)
        sizing(suite)
    }
    private static func rail(_ suite: TestSuite) {
        let state = RailState()
        let host = NSHostingView(rootView: Rail(state: state))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 424, height: 152),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil }
        host.frame = NSRect(x: 0, y: 0, width: 424, height: 152)
        settle(host)
        suite.expect(state.realized.count > 0 && state.realized.count < 40,
                     "a thousand history entries create only the visible rail neighborhood")
        for (target, rows) in [(12, 2), (900, 2), (901, 2), (901, 1), (0, 1)] {
            state.rows = rows
            state.selected = target
            settle(host)
            let marker = descendants(host).first { $0.identifier?.rawValue == "rail-\(target)" }
            suite.expect(marker.map { host.bounds.intersects($0.convert($0.bounds, to: host)) } == true,
                         "selection \(target) remains visible after navigating or changing to \(rows) rail rows")
        }
        suite.expect(state.realized.count < 500,
                     "jumping to distant selections does not realize the intervening history")
    }
    private static func scratchpad(_ suite: TestSuite) {
        let pad = ScratchpadService.shared
        pad.text = "original note"
        pad.isPreviewing = false
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 424, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: NotchScratchpadView(service: NotchService()))
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 424, height: 180)
        settle(host)
        guard let editor = descendants(host).compactMap({ $0 as? NSTextView }).first else {
            suite.expect(false, "the embedded scratchpad creates its native editor")
            return
        }
        for preview in [true, false] {
            pad.isPreviewing = preview
            settle(host)
            suite.expect(descendants(host).contains { $0 === editor },
                         "preview preserves the same editor and undo history")
            pad.clear(through: editor)
            settle(host)
            suite.expect(pad.text.isEmpty && editor.undoManager?.canUndo == true,
                         "clearing from preview or editing records an undoable text edit")
            window.makeFirstResponder(editor)
            editor.undoManager?.undo()
            suite.expect(editor.string == "original note", "one native undo restores the complete note")
            // This window never becomes key. Commit the restored text explicitly
            // to exercise the editor's delegate independently of AppKit's event loop.
            editor.didChangeText()
            settle(host)
            suite.expect(pad.text == "original note", "committing the restored text updates the shared document")
        }
        pad.isPreviewing = true
        settle(host)
        pad.text = "another pad"
        settle(host)
        pad.isPreviewing = false
        settle(host)
        suite.expect(editor.string == "another pad" && editor.undoManager?.canUndo != true,
                     "switching documents while previewing cannot undo into the previous document")
        window.contentView = nil
    }
    private static func focus(_ suite: TestSuite) {
        let floating = Floating()
        let embedded = Embedded()
        let island = Window()
        embedded.editor.view?.window = island
        floating.textView?.window = floating.panel
        defer { Window.key = nil }
        for visible in [true, false] {
            floating.panel?.isVisible = visible
            Window.key = island
            floating.focusText()
            embedded.focusEditor()
            settle()
            suite.expect(Window.key === island && floating.panel?.responderChanges == 0,
                         "document actions preserve island focus with the floating host visible or hidden")
        }
        floating.panel?.isVisible = true
        floating.focusText(requiresKeyWindow: false)
        settle()
        suite.expect(Window.key === floating.panel && floating.panel?.responderChanges == 1,
                     "explicitly opening the floating pad still gives its editor the keyboard")
        let before = island.responderChanges
        embedded.focusEditor()
        suite.expect(island.responderChanges == before, "an island observer cannot change the nonkey editor selection")
        floating.focusText()
        Window.key = island
        settle()
        suite.expect(floating.panel?.responderChanges == 1,
                     "a queued floating focus request is discarded after the user changes hosts")
    }
    private static func sizing(_ suite: TestSuite) {
        var page = Page()
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for bar: CGFloat in [24, 32, 40, 48, 64] {
            let geometry = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, layout: .custom,
                                         menuBarHeight: bar, customWidth: 360, customHeight: 260)
            for module in [NotchModule.controls, .timer, .calendar, .files, .music] {
                page.service.selected = module
                page.service.contentSize = geometry.contentSize(for: geometry.expandedSize(module: module))
                let layout = page.pageSize
                suite.expect(layout.width == page.service.contentSize.width
                             && layout.height >= page.service.contentSize.height,
                             "\(module) keeps the chosen width and exposes any vertically overflowing content")
                if module == .controls {
                    let required = NotchLayout.controls(hasCards: true, shortcutCount: 1, width: layout.width, height: layout.height)
                    suite.expect(required.height <= layout.height, "home buttons fit their scrollable layout at menu height \(bar)")
                } else if module == .timer {
                    for mode in NotchTimerMode.allCases {
                        let required = NotchLayout.timer(mode: mode, hasSession: false, width: layout.width, height: layout.height)
                        suite.expect(required <= layout.height, "timer controls remain reachable at menu height \(bar)")
                    }
                } else if module == .calendar {
                    let required = NotchLayout.calendarMonthHeaderHeight + NotchLayout.calendarMonthWeekdayHeight
                        + NotchLayout.calendarMonthSpacing * 2 + 6 * NotchLayout.calendarMonthRowHeight(height: layout.height)
                    suite.expect(required <= layout.height, "all six month rows remain reachable at menu height \(bar)")
                }
            }
        }
        page.controls = [.volume]
        page.service.selected = .controls
        page.service.contentSize = CGSize(width: 424, height: 96)
        suite.expect(page.pageSize == page.service.contentSize, "a single home card does not introduce unnecessary scrolling")
        page.showsDetail = true
        suite.expect(page.pageSize == page.service.contentSize, "vertical detail pages preserve their existing layout")
    }
}
