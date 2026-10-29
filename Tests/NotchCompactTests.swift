// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Production rail, editor, and focus bodies with inert services. Windows stay
/// hidden; these contracts neither capture pixels nor send input events.
enum NotchCompactTests {
    typealias L10n = NotchUpdateTests.L10n
    final class CameraPreviewService: ObservableObject {
        static let shared = CameraPreviewService()
        @Published var isEmbeddedPresented = false
        var stops = 0
        /// Whether the island's preview offers its own camera picker over the image.
        var previewMenu: Bool?
        func showEmbedded() { isEmbeddedPresented = true }
        func hideEmbedded() {
            guard isEmbeddedPresented else { return }
            stops += 1
            isEmbeddedPresented = false
        }
    }
    struct CameraPreviewView: View {
        let size: CGSize
        let showsCameraMenu: Bool
        var body: some View {
            Color.black.frame(width: size.width, height: size.height)
                .onAppear { CameraPreviewService.shared.previewMenu = showsCameraMenu }
        }
    }
    final class NotchService: ObservableObject {
        var presentationWindow: NSWindow?
        @Published var scratchpadCloseSerial = 0
        @Published var scratchpadFindSerial = 0
        var scratchpadFindAction = NSTextFinder.Action.showFindInterface
        var contentSize = CGSize(width: 304, height: 122)
        var selected = NotchModule.controls
        var musicShowsVolume = false
        var notice: NotchNotice?
        var showingSections = false
        var modules: [NotchModule] = [.controls, .music]
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                     safeAreaTop: 0, cameraWidth: 0, layout: .custom,
                                     menuBarHeight: 64, customWidth: 360, customHeight: 260)
        var expandedGeometry: NotchGeometry {
            var result = geometry
            result.pageTop = selected.pageTop
            return result
        }
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
        @Published var saveFailed = false
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
        func apply(_ mark: ScratchpadMark, through editor: NSTextView? = nil) {}
        @Published var marksExpanded = false
        func toggleMarks() { marksExpanded.toggle() }
        func performFind(_ action: NSTextFinder.Action, in editor: NSTextView? = nil) {}
        func hideFindBar(in editor: NSTextView) {}
        func togglePreview() { isPreviewing.toggle() }
        func show(allowsIsland: Bool = true) {}
        func exportText(suggestedName: String, from window: NSWindow? = nil) {}
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
    /// What each button the pages draw would do, by its title, so a test can press it.
    static var buttonActions: [String: () -> Void] = [:]
    struct NotchIconButton: View {
        let symbol: String
        let title: String
        var selected = false
        let action: () -> Void
        var body: some View {
            let _ = (NotchCompactTests.buttonActions[title] = action)
            Button(title, action: action)
        }
    }
    struct NotchPillButton: View {
        let title: String
        var prominent = false
        let action: () -> Void
        var body: some View {
            let _ = (NotchCompactTests.buttonActions[title] = action)
            Button(title, action: action)
        }
    }
    struct NotchMenuItem {
        let title: String
        var checked = false
        var symbol: String? = nil
        var enabled = true
        var action: () -> Void = {}
        static let separator = NotchMenuItem(title: "")
    }
    struct NotchMenuButton<Label: View>: View {
        let title: String
        let items: [NotchMenuItem]
        var cornerRadius: CGFloat = 6
        @ViewBuilder let label: () -> Label
        var body: some View { label() }
    }
    struct ScratchpadFormatBar: View {
        enum Style { case pad, island }
        let style: Style
        var editor: NSTextView?
        var body: some View { Color.clear }
    }
    struct Music { var playback: Bool? = true }
    struct Page {
        var music = Music()
        var showsDetail = false
        var service = NotchService()
        var controls: [NotchControlItem] = [.music, .volume, .brightness, .timer]
        var timerMode = NotchTimerMode.timer
        var brightnessSlider = true
    }
    final class Window {
        static var key: Window?
        var isVisible = true
        var isKeyWindow: Bool { Self.key === self }
        var responderChanges = 0
        func makeKey() { Self.key = self }
        func makeFirstResponder(_ view: TextView?) { responderChanges += 1 }
    }
    /// Not named ScrollView: inside this namespace that would shadow SwiftUI's
    /// own, which the notch views use for their rows.
    final class EditorScrollView {
        var isFindBarVisible = false
    }
    final class TextView {
        var window: Window?
        var string = "note"
        var enclosingScrollView: EditorScrollView? = EditorScrollView()
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
        @Published var count = 1000
        @Published var width: CGFloat = 424
        @Published var leastSpacing: CGFloat?
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
            let entries = (0..<state.count).map { NotchCompactTests.Entry(id: $0) }
            return NotchRail(items: entries, rows: state.rows, itemWidth: 76, width: state.width,
                             leastSpacing: state.leastSpacing, scrollTarget: state.selected, content: marker)
                .frame(width: state.width, height: 152)
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
        camera(suite)
        calendarRows(suite)
        rail(suite)
        scratchpad(suite)
        readingLayout(suite)
        readingLevels(suite)
        focus(suite)
        sizing(suite)
        musicVolumeSizing(suite)
    }
    private static func calendarRows(_ suite: TestSuite) {
        // Local noon, so the one-hour event never crosses midnight in any time zone.
        let day = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0,
                                        of: Date(timeIntervalSince1970: 1_780_000_000)) ?? Date(timeIntervalSince1970: 1_780_000_000)
        for language in AppLanguage.allCases {
            for width: CGFloat in [192, 304, 424] {
                func height(title: String, chosen: Bool? = nil) -> CGFloat {
                    let event = NotchCalendarEvent(id: "layout", title: title, calendar: "Calendar",
                                                   start: day, end: day.addingTimeInterval(3600),
                                                   allDay: false, location: "Meeting room")
                    let host = NSHostingView(rootView: NotchCalendarEventRow(event: event, day: day, now: day,
                                                                           isNext: true,
                                                                           text: FeatureStrings.notchCalendar(language),
                                                                           countdown: chosen, choose: { _ in }, open: {})
                        .environment(\.locale, Locale(identifier: language.rawValue))
                        .frame(width: width))
                    host.layoutSubtreeIfNeeded()
                    suite.expect(host.fittingSize.width == width && host.fittingSize.height.isFinite,
                                 "agenda rows stay inside the available width in \(language.rawValue)")
                    return host.fittingSize.height
                }
                let short = height(title: "Meeting")
                let long = height(title: Array(repeating: "A long appointment title", count: 10).joined(separator: " "))
                suite.expect(long > short + 40,
                             "long agenda titles grow vertically instead of clipping into a fixed-height card")
                suite.expect(height(title: "Meeting", chosen: true) == short,
                             "the mark of an event chosen to count down fits its time line without growing the card")
            }
        }
    }
    private static func camera(_ suite: TestSuite) {
        let service = CameraPreviewService.shared
        service.isEmbeddedPresented = false
        service.stops = 0
        service.previewMenu = nil
        let host = NSHostingView(rootView: AnyView(VStack {
            NotchCameraView(size: CGSize(width: 424, height: 180))
        }))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 424, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; service.isEmbeddedPresented = false }
        host.frame = NSRect(x: 0, y: 0, width: 424, height: 180)
        settle(host)
        service.showEmbedded()
        settle(host)
        suite.expect(service.isEmbeddedPresented && service.stops == 0,
                     "starting the embedded camera does not dismiss it when the start card disappears")
        suite.expect(service.previewMenu == false,
                     "the island's preview leaves its camera picker and stop button to the top row, clear of the image")
        // The top row's stop button, as a pill in a full row and a glyph
        // beside the camera.
        var band = NotchBand()
        let stopTitle = FeatureStrings.notchActivities(L10n.shared.language).stopCamera
        for besideCamera in [false, true] {
            band.besideCamera = besideCamera
            buttonActions = [:]
            let stop = NSHostingView(rootView: NotchCameraStopButton().environment(\.notchBand, band))
            stop.layoutSubtreeIfNeeded()
            suite.expect(buttonActions[stopTitle] != nil, "the top row offers Stop while the mirror runs, beside a camera: \(besideCamera)")
        }
        buttonActions[stopTitle]?()
        settle(host)
        service.showEmbedded()
        settle(host)
        suite.expect(service.isEmbeddedPresented && service.stops == 1,
                     "stopping from the top row brings back the start card, and the camera starts again within the same page")
        host.rootView = AnyView(EmptyView())
        settle(host)
        suite.expect(!service.isEmbeddedPresented && service.stops == 2,
                     "leaving the camera page still stops capture")
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
        let firstTiles = (0..<3).compactMap { id in
            descendants(host).first { $0.identifier?.rawValue == "rail-\(id)" }.map { $0.convert($0.bounds, to: host) }
        }
        if firstTiles.count == 3 {
            let gap = CGPoint(x: (firstTiles[0].maxX + firstTiles[2].minX) / 2, y: firstTiles[0].midY)
            var target = host.hitTest(gap)
            while let view = target, !(view is NSScrollView) { target = view.superview }
            suite.expect(target is NSScrollView,
                         "empty space between rail columns routes wheel events through the scroll view")
        } else {
            suite.expect(false, "the visible rail has enough columns to exercise its empty gap")
        }
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
        // Five tiles over two rows fit three columns wide: they read across
        // the rows, and the two on the last row sit centered under the three.
        state.count = 5
        state.rows = 2
        state.selected = nil
        settle(host)
        let frames = (0..<5).compactMap { id in
            descendants(host).first { $0.identifier?.rawValue == "rail-\(id)" }.map { $0.convert($0.bounds, to: host) }
        }
        suite.expect(frames.count == 5
               && frames[0].minY == frames[1].minY && frames[1].minY == frames[2].minY
               && frames[0].minX < frames[1].minX && frames[1].minX < frames[2].minX
               && frames[3].minY == frames[4].minY && frames[3].minY != frames[0].minY,
               "a rail that fits reads left to right along its rows")
        suite.expect(frames.count == 5
               && abs(frames[3].width - frames[0].width) < 0.5
               && abs(frames[3].midX - (frames[0].midX + frames[1].midX) / 2) < 0.5
               && abs((frames[3].minX + frames[4].maxX) / 2 - host.bounds.midX) < 0.5,
               "a short last row keeps the cell width and sits centered under the row above")
        // Four tiles in one row just miss the narrowest page with their gaps.
        // A rail that may close them keeps every tile whole, side by side;
        // any other still scrolls its last column past the edge.
        state.count = 4
        state.rows = 1
        state.width = 304
        host.frame = NSRect(x: 0, y: 0, width: 304, height: 152)
        for least in [NotchLayout.shortcutLeastSpacing, nil] {
            state.leastSpacing = least
            settle(host)
            let tiles = (0..<4).compactMap { id in
                descendants(host).first { $0.identifier?.rawValue == "rail-\(id)" }.map { $0.convert($0.bounds, to: host) }
            }
            let whole = tiles.count == 4 && tiles.allSatisfy { (tile: CGRect) -> Bool in
                tile.minX >= -0.5 && tile.maxX <= 304.5 && abs(tile.width - 76) < 0.5
            }
            suite.expect(whole == (least != nil), least != nil
                         ? "a rail that closes its gaps keeps four tiles whole across the narrowest page"
                         : "a rail with no least gap still scrolls the column that misses its width")
        }
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
        // Option-Up trades two lines; undo and redo put the text and the
        // selection back exactly, not the caret at the end of the note.
        if let coordinator = editor.delegate as? PlainTextEditor.Coordinator {
            editor.string = "one\ntwo\nthree\nfour"
            editor.didChangeText()
            settle(host)
            editor.undoManager?.removeAllActions()
            editor.setSelectedRange(NSRange(location: 5, length: 2))
            let moved = coordinator.moveLine(.up, in: editor)
            settle(host)
            suite.expect(moved && editor.string == "two\none\nthree\nfour"
                         && editor.selectedRange() == NSRange(location: 1, length: 2),
                         "option-up moves the line with its selection")
            editor.undoManager?.undo()
            suite.expect(editor.string == "one\ntwo\nthree\nfour"
                         && editor.selectedRange() == NSRange(location: 5, length: 2),
                         "one undo after a line move restores the text and the selection")
            editor.undoManager?.redo()
            suite.expect(editor.string == "two\none\nthree\nfour"
                         && editor.selectedRange() == NSRange(location: 1, length: 2),
                         "redo moves the line again with the selection on it")
            editor.string = "a\na\nb"
            editor.didChangeText()
            settle(host)
            editor.undoManager?.removeAllActions()
            editor.setSelectedRange(NSRange(location: 2, length: 0))
            suite.expect(coordinator.moveLine(.up, in: editor) && editor.string == "a\na\nb"
                         && editor.selectedRange() == NSRange(location: 0, length: 0)
                         && editor.undoManager?.canUndo != true,
                         "trading two identical lines only moves the caret and leaves no empty undo step")
        } else {
            suite.expect(false, "the scratchpad editor's coordinator is its delegate")
        }
        readingTasks(suite, pad: pad, host: host, editor: editor, window: window)
        pad.isPreviewing = false
        settle(host)
        window.contentView = nil
    }
    /// The formatted reading draws each task with the system checklist
    /// circle, which VoiceOver meets as a checkbox, and keeps done tasks
    /// where they are. A click on a box is one edit of the editor's own: one
    /// undo puts the box back, and what was typed before the click can still
    /// be undone, on the island and in the floating pad.
    private static func readingTasks(_ suite: TestSuite, pad: ScratchpadService, host: NSView,
                                     editor: NSTextView, window: NSWindow) {
        pad.isPreviewing = false
        pad.text = "- [x] done\n- [ ] open"
        settle(host)
        let end = NSRange(location: (editor.string as NSString).length, length: 0)
        if editor.shouldChangeText(in: end, replacementString: "\n- [ ] new") {
            editor.replaceCharacters(in: end, with: "\n- [ ] new")
            editor.didChangeText()
        }
        settle(host)
        pad.isPreviewing = true
        settle(host)
        guard let reading = descendants(host).compactMap({ $0 as? TaskPreviewTextView }).first,
              let storage = reading.textStorage else {
            suite.expect(false, "the scratchpad reading shows its native text view")
            return
        }
        var boxes: [URL?] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let box = value as? TaskBoxAttachment, box.image != nil else { return }
            boxes.append(storage.attribute(.link, at: range.location, effectiveRange: nil) as? URL)
        }
        let strings = FeatureStrings.scratchpad(L10n.shared.language)
        let shown = storage.string as NSString
        suite.expect(boxes.count == 3
                     && shown.range(of: "done").location < shown.range(of: "open").location
                     && shown.range(of: "open").location < shown.range(of: "new").location,
                     "the reading draws each task's checklist circle, with done tasks in place")
        // The text view alone would offer each box as a link named by the
        // attachment's object replacement character.
        let children = reading.accessibilityChildren() ?? []
        let checks = children.compactMap { $0 as? NSAccessibilityElement }.filter { $0.accessibilityRole() == .checkBox }
        suite.expect(checks.map { $0.accessibilityLabel() } == ["done", "open", "new"]
                     && checks.map { ($0.accessibilityValue() as? NSNumber)?.boolValue } == [true, false, false]
                     && checks.map { $0.accessibilityValueDescription() }
                         == [strings.taskDone, strings.taskNotDone, strings.taskNotDone]
                     && !children.contains {
                         ($0 as? NSAccessibilityElement)?.accessibilityURL()?.scheme == ScratchpadSupport.taskScheme },
                     "VoiceOver meets each box as a checkbox named by its task and said done or not done, not as a bare link")
        guard boxes.count == 3, let link = boxes[1] else {
            suite.expect(false, "each checkbox in the reading carries its task's link")
            return
        }
        _ = reading.delegate?.textView?(reading, clickedOnLink: link, at: 0)
        settle(host)
        suite.expect(editor.string == "- [x] done\n- [x] open\n- [ ] new" && pad.text == editor.string
                     && editor.undoManager?.canUndo == true,
                     "a checkbox click checks its own task through the editor, as an undoable edit")
        window.makeFirstResponder(editor)
        editor.undoManager?.undo()
        suite.expect(editor.string == "- [x] done\n- [ ] open\n- [ ] new",
                     "one undo after a checkbox click puts the box back")
        editor.undoManager?.undo()
        suite.expect(editor.string == "- [x] done\n- [ ] open",
                     "what was typed before a checkbox click can still be undone after it")
        // The floating pad passes no editor: the toggle finds the text view
        // registered in its panel and edits through it the same way.
        let panel = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: 240, height: 120),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let floating = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        floating.allowsUndo = true
        panel.contentView = floating
        floating.string = "- [ ] call ann\n- [ ] buy milk"
        pad.panel = panel
        pad.textView = floating
        pad.toggleTask(box: 17)
        settle(floating)
        suite.expect(floating.string == "- [ ] call ann\n- [x] buy milk" && floating.undoManager?.canUndo == true,
                     "a checkbox click in the floating pad checks its task through the pad's editor, as an undoable edit")
        floating.undoManager?.undo()
        suite.expect(floating.string == "- [ ] call ann\n- [ ] buy milk",
                     "one undo after a checkbox click in the floating pad puts the box back")
        pad.panel = nil
        pad.textView = nil
        panel.contentView = nil

        // Every render makes new checkbox attachments, which never compare
        // equal, so only the inputs can tell that nothing changed.
        let coordinator = MarkdownPreview.Coordinator()
        let view = TaskPreviewTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        var renders = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: view.textStorage, queue: nil) { _ in
            renders += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let blocks = ScratchpadSupport.markdownPreview("- [ ] call ann\n- [x] buy milk")
        let states = (done: strings.taskDone, notDone: strings.taskNotDone)
        coordinator.show(blocks, base: 13, taskStates: states, in: view)
        view.setSelectedRange(NSRange(location: 2, length: 4))
        coordinator.show(ScratchpadSupport.markdownPreview("- [ ] call ann\n- [x] buy milk"), base: 13,
                         taskStates: states, in: view)
        suite.expect(renders == 1 && view.selectedRange() == NSRange(location: 2, length: 4),
                     "an update with the same note leaves the reading and its selection alone")
        coordinator.show(ScratchpadSupport.markdownPreview("- [x] call ann\n- [x] buy milk"), base: 13,
                         taskStates: states, in: view)
        coordinator.show(ScratchpadSupport.markdownPreview("- [x] call ann\n- [x] buy milk"), base: 15,
                         taskStates: states, in: view)
        coordinator.show(ScratchpadSupport.markdownPreview("- [x] call ann\n- [x] buy milk"), base: 15,
                         taskStates: (done: "Hecha", notDone: "Pendiente"), in: view)
        suite.expect(renders == 4, "a changed note, size or language draws the reading again")
        var pressed: [Int] = []
        view.onToggleTask = { pressed.append($0) }
        let presses = (view.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityElement }
            .filter { $0.accessibilityRole() == .checkBox }
        suite.expect(presses.count == 2 && presses[1].accessibilityPerformPress() && pressed == [17],
                     "pressing a checkbox with VoiceOver toggles its own box")

        // AppKit asks for tracking areas again on every geometry change.
        view.updateTrackingAreas()
        let areas = view.trackingAreas.count
        for _ in 0..<5 { view.updateTrackingAreas() }
        suite.expect(view.trackingAreas.count == areas,
                     "the reading keeps one pointer tracking area however often AppKit asks for them")
    }
    /// The reading lays a checklist out as Notes does: the empty circle shows
    /// in light and dark, a nested task's circle sits under its parent's
    /// text, a task's wrapped lines hang under its own text, and a task in a
    /// quote keeps the quote's bar and colour.
    private static func readingLayout(_ suite: TestSuite) {
        // The most opaque pixel of an empty circle drawn in `appearance`; a
        // palette would lay tertiary label's alpha over the ring's, at ~7%.
        func ink(_ appearance: NSAppearance.Name) -> CGFloat {
            guard let image = TaskBoxAttachment(checked: false, size: 16, description: "").image,
                  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return 0 }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
            }
            NSGraphicsContext.restoreGraphicsState()
            var most: CGFloat = 0
            for x in 0..<32 { for y in 0..<32 { most = max(most, bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) } }
            return most
        }
        suite.expect(ink(.aqua) > 0.18 && ink(.darkAqua) > 0.18,
                     "the empty task circle draws at tertiary label strength in light and dark, not faded twice")

        let note = "- [ ] Call the bank\n  - [ ] Ask about the fee\n  - spare key\n    - [ ] copy\n"
            + "- [ ] Book train tickets for Saturday morning and check whether the return can move to Sunday evening\n"
            + "- bread\n  - [ ] rye\n  - crust\n\n> Reminder\n"
            + "> - [ ] Bring the key and the parking pass for the guests who arrive near midnight\n>   - [ ] spare one"
        let view = TaskPreviewTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        MarkdownPreview.Coordinator().show(ScratchpadSupport.markdownPreview(note), base: 13,
                                           taskStates: (done: "Done", notDone: "Not done"), in: view)
        guard let layout = view.layoutManager, let container = view.textContainer, let storage = view.textStorage else {
            suite.expect(false, "the reading lays its text out")
            return
        }
        layout.ensureLayout(for: container)
        let shown = storage.string as NSString
        guard ["Call the bank", "Ask about", "spare key", "copy", "Book train", "evening", "bread", "rye", "Reminder",
               "Bring the key", "midnight", "spare one"]
            .allSatisfy({ shown.range(of: $0).location != NSNotFound }) else {
            suite.expect(false, "the reading shows every line of the checklist")
            return
        }
        func x(glyph: Int) -> CGFloat {
            layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).minX
        }
        func x(_ character: Int) -> CGFloat { x(glyph: layout.glyphIndexForCharacter(at: character)) }
        func x(of text: String) -> CGFloat { x(shown.range(of: text).location) }
        /// Where the circle or bullet in front of `text`, and its space, starts.
        func marker(before text: String) -> CGFloat { x(shown.range(of: text).location - 2) }
        suite.expect(abs(marker(before: "Ask about") - x(of: "Call the bank")) < 0.5
                     && abs(marker(before: "spare key") - x(of: "Call the bank")) < 0.5
                     && abs(marker(before: "rye") - x(of: "bread")) < 0.5
                     && abs(marker(before: "copy") - x(of: "spare key")) < 0.5,
                     "a nested task or bullet starts under its parent's text, and a task under a bullet under the bullet's text")
        suite.expect(shown.range(of: "\n  • crust").location != NSNotFound,
                     "a bullet under a plain bullet keeps its leading spaces")
        /// Whether the line holding `last` wraps from the line that opens
        /// with `first` and starts where `first` does.
        func hangs(_ last: String, under first: String) -> Bool {
            var line = NSRange()
            _ = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: shown.range(of: last).location),
                                        effectiveRange: &line)
            return line.location > layout.glyphIndexForCharacter(at: shown.range(of: first).location)
                && abs(x(glyph: line.location) - x(of: first)) < 0.5
        }
        suite.expect(hangs("evening", under: "Book train") && hangs("midnight", under: "Bring the key"),
                     "a wrapped task line hangs under the task's text, not under its circle, in a quote as well")
        let bring = shown.range(of: "Bring the key").location
        let quoted = shown.lineRange(for: NSRange(location: bring, length: 0)).location
        let reminder = shown.lineRange(for: shown.range(of: "Reminder")).location
        suite.expect(shown.substring(with: NSRange(location: quoted, length: 1)) == "▏"
                     && abs(x(quoted) - x(reminder)) < 0.5
                     && storage.attribute(.attachment, at: bring - 2, effectiveRange: nil) is TaskBoxAttachment
                     && abs(marker(before: "Bring the key") - x(of: "Reminder")) < 0.5
                     && abs(marker(before: "spare one") - x(of: "Bring the key")) < 0.5
                     && shown.substring(with: NSRange(location: shown.lineRange(for: shown.range(of: "spare one")).location,
                                                      length: 1)) == "▏"
                     && storage.attribute(.foregroundColor, at: bring, effectiveRange: nil) as? NSColor == .secondaryLabelColor,
                     "a task in a quote keeps the quote's bar and colour, with its circle where the quote's text starts and a nested one under its parent's text")
    }
    /// A list that opens below depth 1 lines its items up by their own
    /// depth, whatever list came before, and a task quoted inside a bullet
    /// starts after the quote's bar, which is wider than the bullet.
    private static func readingLevels(_ suite: TestSuite) {
        let note = "- [ ] Water the plants\n\nLater\n\n- - [ ] Feed the cat\n  - [ ] Lock the door\n\n"
            + "- Garden\n  > - [ ] Prune the roses\n  >   - [ ] Buy shears"
        let view = TaskPreviewTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 300))
        MarkdownPreview.Coordinator().show(ScratchpadSupport.markdownPreview(note), base: 13,
                                           taskStates: (done: "Done", notDone: "Not done"), in: view)
        guard let layout = view.layoutManager, let container = view.textContainer, let storage = view.textStorage else {
            suite.expect(false, "the reading lays its text out")
            return
        }
        layout.ensureLayout(for: container)
        let shown = storage.string as NSString
        /// The circle in front of `text`, as a character offset.
        func circle(before text: String) -> Int? {
            let location = shown.range(of: text).location
            guard location != NSNotFound, location >= 2,
                  storage.attribute(.attachment, at: location - 2, effectiveRange: nil) is TaskBoxAttachment else { return nil }
            return location - 2
        }
        func x(_ character: Int) -> CGFloat {
            layout.boundingRect(forGlyphRange: NSRange(location: layout.glyphIndexForCharacter(at: character), length: 1),
                                in: container).minX
        }
        let circles = ["Water the plants", "Feed the cat", "Lock the door", "Prune the roses", "Buy shears"]
            .compactMap(circle(before:))
        guard circles.count == 5 else {
            suite.expect(false, "the reading shows every task of the deeper lists with its circle")
            return
        }
        let water = x(circles[0]), feed = x(circles[1])
        suite.expect(abs(feed - x(circles[2])) < 0.5 && feed > water + 1 && feed < x(circles[0] + 2) - 1,
                     "a list that opens below depth 1 keeps its tasks in line, indented, and not under an earlier list's text")
        suite.expect(abs(x(circles[4]) - x(circles[3] + 2)) < 0.5,
                     "a task quoted inside a bullet starts after the quote's bar, and a task under it sits under its text")
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
    private static func musicVolumeSizing(_ suite: TestSuite) {
        var page = Page()
        page.service.selected = .music
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for notched in [false, true] {
            for layout: NotchSize in [.compact, .spacious, .custom] {
                page.service.geometry = NotchGeometry(screen: screen, safeAreaTop: notched ? 32 : 0,
                                                      cameraWidth: notched ? 210 : 0, layout: layout,
                                                      customWidth: 480, customHeight: 260)
                for playing in [false, true] {
                    page.music.playback = playing ? true : nil
                    for showVolume in [false, true] {
                        page.service.musicShowsVolume = showVolume
                        let minimum = NotchLayout.musicPlayerHeight(band: page.service.expandedGeometry.musicBandHeight,
                                                                    playing: playing, showVolume: showVolume)
                        for available: CGFloat in [100, minimum, 300] {
                            page.service.contentSize = CGSize(width: 304, height: available)
                            suite.expect(page.pageSize == CGSize(width: 304, height: max(available, minimum)),
                                         "the music page keeps all controls reachable in short islands and adds no scrolling when they fit: \(layout), notched \(notched), playing \(playing), volume \(showVolume)")
                        }
                    }
                }
            }
        }
    }

    private static func sizing(_ suite: TestSuite) {
        var page = Page()
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for bar: CGFloat in [24, 32, 40, 48, 64] {
            let geometry = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, layout: .custom,
                                         menuBarHeight: bar, customWidth: 360, customHeight: 260)
            for module in [NotchModule.controls, .timer, .calendar, .files, .music, .clipboard, .camera, .mixer] {
                page.service.selected = module
                page.service.contentSize = geometry.contentSize(for: geometry.expandedSize(module: module))
                let layout = page.pageSize
                suite.expect(layout.width == page.service.contentSize.width
                             && layout.height >= page.service.contentSize.height,
                             "\(module) keeps the chosen width and exposes any vertically overflowing content")
                if module == .controls {
                    // Playback keeps the card row; the levels sit in the top row.
                    let required = NotchLayout.controls(hasCards: page.controls.contains(.music), shortcutCount: 1,
                                                        width: layout.width, height: layout.height)
                    suite.expect(required.height <= layout.height, "home buttons fit their scrollable layout at menu height \(bar)")
                } else if module == .timer {
                    // Each mode sizes the island for itself, the Pomodoro a line taller.
                    for mode in NotchTimerMode.allCases {
                        page.timerMode = mode
                        page.service.contentSize = geometry.contentSize(for: geometry.expandedSize(module: module, timerMode: mode))
                        let layout = page.pageSize
                        let required = NotchLayout.timer(mode: mode, hasSession: false, height: layout.height)
                        suite.expect(required <= layout.height && layout.height >= page.service.contentSize.height,
                                     "timer controls remain reachable at menu height \(bar): \(mode)")
                    }
                    // A page shorter than every mode needs scrolls to the
                    // mode it shows, which only the page's own mode decides.
                    let short = CGSize(width: page.service.contentSize.width, height: 60)
                    let heights = NotchTimerMode.allCases.map { mode -> CGFloat in
                        page.timerMode = mode
                        page.service.contentSize = short
                        return page.pageSize.height
                    }
                    suite.expect(heights == NotchTimerMode.allCases.map { NotchLayout.timer(mode: $0, hasSession: false, height: 60) }
                                 && heights[1] > heights[0],
                                 "a short page scrolls to its own mode's controls at menu height \(bar): \(heights)")
                    page.timerMode = .timer
                } else if module == .calendar {
                    let required = NotchLayout.calendarMonthWeekdayHeight
                        + 6 * NotchLayout.calendarMonthRowHeight(height: layout.height)
                    suite.expect(required <= layout.height, "all six month rows remain reachable at menu height \(bar)")
                } else if module == .clipboard {
                    suite.expect(layout.height >= NotchLayout.clipboardCardHeight,
                                 "a short clipboard page keeps a complete card reachable")
                } else if module == .camera || module == .mixer {
                    // The mixer's controls sit in the top row, so its faders take the whole page.
                    let minimum = module == .camera ? 144 : NotchLayout.mixerMinimumHeight
                    suite.expect(layout.height >= minimum, "camera and mixer controls keep a usable height in a short island")
                    if page.service.contentSize.height >= minimum {
                        suite.expect(layout.height == page.service.contentSize.height,
                                     "camera and mixer actions fit without outer scrolling in a short island")
                    }
                }
            }
        }
        page.controls = [.volume]
        page.service.selected = .controls
        page.service.contentSize = CGSize(width: 424, height: 96)
        suite.expect(page.pageSize == page.service.contentSize, "a single home card does not introduce unnecessary scrolling")
        page.showsDetail = true
        suite.expect(page.pageSize == page.service.contentSize, "vertical detail pages preserve their existing layout")

        func reading(_ event: NotchEvent) -> NotchNotice? {
            page.service.notice = NotchNotice(event: event, title: "", detail: "", symbol: "", level: 0.5)
            return page.headerFeedback
        }
        page.showsDetail = false
        page.controls = [.music, .brightness, .keyboardLight, .volume, .timer]
        let levelsQuiet = reading(.brightness) == nil && reading(.keyboardLight) == nil && reading(.volume) == nil
        page.controls = [.music, .brightness, .keyboardLight, .timer]
        let hiddenLevelShows = reading(.volume) != nil
        page.service.selected = .music
        let otherPageShows = reading(.brightness) != nil
        page.service.selected = .controls
        page.service.showingSections = true
        let galleryShows = reading(.brightness) != nil
        page.service.showingSections = false
        page.showsDetail = true
        let detailShows = reading(.brightness) != nil
        page.showsDetail = false
        suite.expect(levelsQuiet && hiddenLevelShows && otherPageShows && galleryShows && detailShows,
                     "a level key leaves the home page's levels uncovered, since the level it moves is already on the page")
        // The row's brightness shows the display the keys last moved, so only
        // the way to set brightness up, with no slider, leaves the reading.
        page.brightnessSlider = false
        suite.expect(reading(.brightness) != nil && reading(.keyboardLight) == nil,
                     "a brightness key keeps its reading on the home page while its row has no slider")
        page.brightnessSlider = true
    }
}

/// The island's top row as the scratchpad page uses it. The row itself is not
/// part of these tests, so a page's items are drawn above it, built from the
/// page's state as the island builds them.
private struct NotchCompactBandKey: EnvironmentKey {
    static let defaultValue = NotchBand()
}

extension EnvironmentValues {
    var notchBand: NotchBand {
        get { self[NotchCompactBandKey.self] }
        set { self[NotchCompactBandKey.self] = newValue }
    }
}

extension View {
    func notchBand<Leading: View, Trailing: View>(@ViewBuilder leading: () -> Leading,
                                                  @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(spacing: 0) {
            HStack { leading(); trailing() }
            self
        }
    }
}

/// A menu's label in the row, as the island draws it.
struct NotchBandMenuLabel: View {
    let title: String
    var symbol: String? = nil
    var truncation: Text.TruncationMode = .tail

    var body: some View { Text(title).lineLimit(1).truncationMode(truncation) }
}
