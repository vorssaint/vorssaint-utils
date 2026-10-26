// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import SwiftUI

enum ScratchpadWorkflowTests {
    static func run(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var document = ScratchpadDocument.initial(defaultName: "Notes", text: "Keep me", modifiedAt: now)
        let first = document.selectedID
        let folder = ScratchpadFolder(id: UUID(), name: "Research")
        document.folders = [folder]
        document.pads[0].folderID = folder.id
        document.pads[0].isPinned = true
        for number in 1..<500 { document = document.addingPad(defaultName: "Note \(number)")! }
        suite.expect(document.pads.count == 500 && document.openIDs.count == 500, "500 notes survive without a tab storage ceiling")
        suite.expect(ScratchpadDocument.decoded(document.encoded(), defaultName: "Notes") == document,
                     "folders, tabs, pinning and all 500 notes round-trip in a backup")
        document = document.removing(first)!
        suite.expect(!document.openIDs.contains(first) && document.pads[0].text == "Keep me", "closing retains note content")
        document = document.selecting(first)!
        suite.expect(document.selectedID == first && document.openIDs.last == first, "a retained note can reopen")
        document.reorderTab(first, before: document.openIDs[0])
        suite.expect(document.openIDs.first == first, "dragging reorders open tabs")
        suite.expect(document.adjacentOpenID(offset: -1) == nil
                     && document.adjacentOpenID(offset: 1) == document.openIDs[1],
                     "adjacent navigation follows tab order and stops at the first note")
        let last = document.selecting(document.openIDs.last!)!
        suite.expect(last.adjacentOpenID(offset: 1) == nil
                     && last.adjacentOpenID(offset: -1) == last.openIDs[last.openIDs.count - 2]
                     && last.adjacentOpenID(offset: Int.max) == nil,
                     "navigation stops at the last note without creating notes or accepting invalid offsets")
        let closed = document.removing(document.openIDs[1])!
        suite.expect(closed.adjacentOpenID(offset: 1) == document.openIDs[2], "navigation skips closed notes")
        suite.expect(document.notes(in: .folder(folder.id)).map(\.id) == [first]
                     && document.notes(in: .pinned).map(\.id) == [first], "folder and pinned filters use note metadata")
        suite.expect(document.notes(in: .all, query: "keep me").map(\.id) == [first], "search includes contents and ignores case")
        document.deleteFolder(folder.id)
        suite.expect(document.folders.isEmpty && document.pads[0].folderID == nil && document.pads[0].text == "Keep me", "deleting a folder moves notes to Inbox")
        document.trash(first, now: now, defaultName: "Notes")
        suite.expect(!document.openIDs.contains(first) && document.notes(in: .trash).first?.text == "Keep me", "Trash retains the deleted content and removes its tab")
        document.restore(first)
        suite.expect(document.selectedID == first && document.pads[0].deletedAt == nil, "restoring reopens the original note")
        document.pads[0].isTemporary = true
        document.pads[0].modifiedAt = now.addingTimeInterval(-90_000)
        document.applyRetention(.day, now: now)
        suite.expect(document.pads[0].text == "Keep me" && document.pads[0].deletedAt != nil, "temporary expiry retains text in Trash")
        document.restore(first)
        document.applyRetention(.day, now: now)
        suite.expect(document.pads[0].deletedAt == nil && !document.pads[0].isTemporary,
                     "restoring an expired note keeps it from immediately expiring again")
        let old = Data("{\"pads\":[{\"id\":\"\(first)\",\"name\":\"Old\",\"text\":\"Original\"}],\"selectedID\":\"\(first)\"}".utf8)
        let migrated = ScratchpadDocument.decoded(old, defaultName: "Notes")
        suite.expect(migrated?.pads.first?.text == "Original" && migrated?.pads.first?.isTemporary == false
                     && migrated?.openIDs == [first], "legacy notes migrate as permanent notes with stable ids")
        var unknown = try! JSONSerialization.jsonObject(with: old) as! [String: Any]
        unknown["schemaVersion"] = 99
        suite.expect(ScratchpadDocument.decoded(try! JSONSerialization.data(withJSONObject: unknown), defaultName: "Notes") == nil,
                     "a future schema is rejected rather than overwritten")
        unknown["schemaVersion"] = 2
        let pad = (unknown["pads"] as! [[String: Any]])[0]
        unknown["pads"] = [pad, pad]
        suite.expect(ScratchpadDocument.decoded(try! JSONSerialization.data(withJSONObject: unknown), defaultName: "Notes") == nil,
                     "duplicate ids fail validation without silently dropping content")
        migration(suite, legacyData: old, now: now)
        titlesAndDuplicates(suite, now: now)
        markdown(suite)
        nativeEditor(suite)
        nativeNavigation(suite)
        for language in AppLanguage.allCases {
            let labels = ScratchpadLibraryStrings(language: language)
            suite.expect(ScratchpadLibraryLabel.allCases.allSatisfy { !labels[$0].isEmpty }, "all Scratchpad labels exist for \(language)")
        }
        let appended = ScratchpadSupport.clipboardAppend("second 🙂", to: "first")
        suite.expect(appended?.replacement == "\n\nsecond 🙂"
                     && appended?.selection == NSRange(location: ("first\n\nsecond 🙂" as NSString).length, length: 0),
                     "clipboard collection separates entries and preserves UTF-16 caret positions")
        suite.expect(ScratchpadSupport.clipboardAppend("third", to: "first\n")?.replacement == "\nthird"
                     && ScratchpadSupport.clipboardAppend("third", to: "first\n\n")?.replacement == "third"
                     && ScratchpadSupport.clipboardAppend(" \n", to: "first") == nil,
                     "clipboard collection avoids duplicate blank lines and ignores blank copies")
    }

    private static func titlesAndDuplicates(_ suite: TestSuite, now: Date) {
        var document = ScratchpadDocument.initial(defaultName: "Notes")
        let id = document.selectedID
        document.updateSelectedText("\n# **Shopping** 🙂\n\n- [ ] Milk", modifiedAt: now)
        suite.expect(document.pads[0].name == "Shopping 🙂" && document.pads[0].usesAutomaticTitle,
                     "new notes use the first meaningful line without Markdown markers")
        document.updateSelectedText("# 明日の買い物\n- [ ] Milk", modifiedAt: now)
        suite.expect(document.pads[0].name == "明日の買い物", "automatic titles follow edits in any writing language")
        suite.expect(ScratchpadMarkdown.suggestedTitle(in: "\n- [ ] \n- **Buy milk**") == nil
                     && ScratchpadMarkdown.suggestedTitle(in: "[Plan](https://example.com)") == nil
                     && ScratchpadMarkdown.suggestedTitle(in: "# ***Strong title***") == "Strong title",
                     "automatic titles come from an explicit top-level heading")
        document = document.renaming(id, to: "My list")!
        document.updateSelectedText("# Changed heading\n- [x] Milk", modifiedAt: now)
        suite.expect(document.pads[0].name == "My list" && !document.pads[0].usesAutomaticTitle,
                     "manual names stop automatic title changes")
        let folder = ScratchpadFolder(id: UUID(), name: "Home")
        document.folders = [folder]
        document.pads[0].folderID = folder.id
        document.pads[0].isPinned = true
        document.pads[0].isTemporary = true
        let original = document.pads[0]
        document = document.duplicating(id, now: now)!
        let copy = document.pads.last!
        suite.expect(copy.id != id && copy.text == original.text && copy.folderID == folder.id
                     && copy.name != original.name && !copy.isTemporary && !copy.isPinned && !copy.usesAutomaticTitle
                     && document.selectedID == copy.id && document.openIDs.last == copy.id && document.pads[0] == original,
                     "duplication opens an independent permanent copy in the same folder without changing the source")
        document.updateSelectedText("Different content", modifiedAt: now)
        suite.expect(document.pads[0] == original && document.pads.last?.name == copy.name,
                     "editing a duplicate preserves its title and the original note")
        let another = document.duplicating(id, now: now)!
        suite.expect(Set(another.pads.map(\.name)).count == another.pads.count, "repeated duplicates have distinct names")
        suite.expect(document.duplicating(id, id: id, now: now) == nil, "duplication rejects reused ids")
        document.trash(id, now: now, defaultName: "Notes")
        suite.expect(document.duplicating(id, now: now) == nil, "trashed notes cannot be duplicated")
        let automatic = ScratchpadDocument.initial(defaultName: "Notes")
        suite.expect(ScratchpadDocument.decoded(automatic.encoded(), defaultName: "Notes")?.pads[0].usesAutomaticTitle == true,
                     "automatic title ownership survives a save and reload")
        let old = Data("{\"pads\":[{\"id\":\"\(id)\",\"name\":\"Existing title\",\"text\":\"Different first line\"}],\"selectedID\":\"\(id)\"}".utf8)
        var legacy = ScratchpadDocument.decoded(old, defaultName: "Notes")!
        legacy.updateSelectedText("A new line", modifiedAt: now)
        suite.expect(legacy.pads[0].name == "Existing title" && !legacy.pads[0].usesAutomaticTitle,
                     "existing titles remain user-owned after migration")
    }

    private static func migration(_ suite: TestSuite, legacyData: Data, now: Date) {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "com.vorssaint.tests.scratchpad.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { try? manager.removeItem(at: directory); defaults.removePersistentDomain(forName: domain) }
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let old = directory.appendingPathComponent("Scratchpad.json")
            let new = directory.appendingPathComponent("Scratchpad-v2.json")
            try legacyData.write(to: old)
            var store = ScratchpadStore(directoryURL: directory, defaults: defaults)
            let loaded = try store.load(defaultName: "Notes", retention: .day, now: now)
            suite.expect(loaded.pads[0].text == "Original" && (try? Data(contentsOf: old)) == legacyData
                         && manager.fileExists(atPath: new.path), "migration writes the new version and leaves the original bytes untouched")
            suite.expect(try store.load(defaultName: "Notes", retention: .never, now: now) == loaded,
                         "repeated migration does not duplicate notes")
            let damaged = Data("{damaged".utf8)
            try damaged.write(to: new)
            suite.expect((try? store.load(defaultName: "Notes", retention: .never, now: now)) == nil
                         && !store.save(loaded), "corrupt new data blocks writes and legacy fallback")
            suite.expect((try? Data(contentsOf: new)) == damaged && (try? Data(contentsOf: old)) == legacyData,
                         "a corrupt new document preserves both recovery copies")
        } catch { suite.expect(false, "migration fixture completes: \(error)") }
    }

    private static func markdown(_ suite: TestSuite) {
        let source = "# Title\n\n**Bold** and *italic* [site](https://example.com)\n\n- [ ] A 🙂\n- [x] Done\n\n```\n- [ ] literal\n```"
        let analysis = ScratchpadMarkdown(source)
        suite.expect(analysis.spans.contains { $0.heading == 1 } && analysis.spans.contains { $0.inline.contains(.stronglyEmphasized) }, "native source positions retain heading and inline formatting")
        suite.expect(analysis.tasks.count == 2 && analysis.tasks[1].checked, "task controls exclude fenced code")
        let ns = source as NSString
        let bold = ns.range(of: "Bold")
        suite.expect(analysis.spans.contains { $0.heading == 1 && ns.substring(with: $0.range) == "Title" }
                     && analysis.spans.contains { $0.inline.contains(.stronglyEmphasized) && $0.range == bold },
                     "native source ranges cover entire headings and inline words")
        let unicode = "# 中文🙂\r\n\r\n**é🙂**"
        let unicodeAnalysis = ScratchpadMarkdown(unicode)
        suite.expect(unicodeAnalysis.spans.contains { $0.heading == 1 && (unicode as NSString).substring(with: $0.range) == "中文🙂" }
                     && unicodeAnalysis.spans.contains { $0.inline.contains(.stronglyEmphasized) && (unicode as NSString).substring(with: $0.range) == "é🙂" },
                     "source positions convert UTF-8 columns into full UTF-16 ranges across CRLF lines")
        suite.expect(analysis.markers.contains { ns.substring(with: $0) == "**" }
                     && analysis.markers.contains { ns.substring(with: $0) == "](https://example.com)" },
                     "paired inline delimiters are identified for live editing")
        let nestedLink = "[site](https://example.com/path_(one))"
        suite.expect(ScratchpadMarkdown(nestedLink).markers.contains { (nestedLink as NSString).substring(with: $0) == "](https://example.com/path_(one))" },
                     "live link syntax includes balanced parentheses in the address")
        suite.expect(analysis.activeMarks(at: bold) == [.bold]
                     && analysis.activeMarks(at: NSRange(location: NSMaxRange(bold), length: 0)) == [.bold],
                     "formatting feedback follows selections and the caret before a closing delimiter")
        suite.expect(analysis.activeMarks(at: ns.range(of: "Bold** and *italic")).isEmpty,
                     "mixed selections do not claim a shared inline format")
        suite.expect(analysis.activeMarks(at: analysis.tasks[0].content) == [.checklist],
                     "checklists select their own toolbar mark instead of the bullet mark")
        let lists = "- bullet\n\n1. numbered\n\n> quote"
        let listAnalysis = ScratchpadMarkdown(lists)
        suite.expect(listAnalysis.activeMarks(at: (lists as NSString).range(of: "bullet")) == [.bullet]
                     && listAnalysis.activeMarks(at: (lists as NSString).range(of: "numbered")) == [.numbered]
                     && listAnalysis.activeMarks(at: (lists as NSString).range(of: "quote")) == [.quote],
                     "formatting feedback distinguishes native lists and quotes")
        suite.expect(analysis.markers.allSatisfy { NSMaxRange($0) <= ns.length }, "all formatting ranges remain valid with emoji")
        let toggle = ScratchpadMarkdown.toggleTask(in: source, at: analysis.tasks[0].content.location)!
        suite.expect(ns.replacingCharacters(in: toggle.range, with: toggle.replacement).contains("- [x] A 🙂"), "toggling edits only the checkbox character")
        suite.expect(ScratchpadMarkdown.toggleTask(in: source, at: analysis.tasks[1].line.location)?.replacement == " ", "a caret at the next line belongs to that checkbox")
        let continuation = ScratchpadMarkdown.continueList(in: "  - [x] Done", selection: NSRange(location: 12, length: 0))!
        suite.expect(continuation.replacement == "\n  - [ ] ", "Return continues a checklist with an unchecked item")
        let empty = ScratchpadMarkdown.continueList(in: "- [ ] ", selection: NSRange(location: 6, length: 0))!
        suite.expect(empty.replacement.isEmpty && empty.range.length == 6, "Return on an empty item ends the list")
        suite.expect(ScratchpadMarkdown.continueList(in: "9. Task", selection: NSRange(location: 7, length: 0))?.replacement == "\n10. ", "numbered list continuation increments its number")
        suite.expect(ScratchpadMarkdown.continueList(in: "Task", selection: NSRange(location: 4, length: 0),
                                                     createCheckboxOnNewLine: true)?.replacement == "\n- [ ] ",
                     "checklist mode creates a checkbox on a new line")
        suite.expect(ScratchpadMarkdown.continueList(in: "```\n- item\n```", selection: NSRange(location: 10, length: 0)) == nil, "Return inside code stays literal")
        let indent = ScratchpadMarkdown.indentList(in: "- a\n- b", selection: NSRange(location: 0, length: 7), outdent: false)!
        suite.expect(indent.replacement == "    - a\n    - b", "Tab indents every selected item")
        let unindent = ScratchpadMarkdown.indentList(in: indent.replacement, selection: indent.selection, outdent: true)!
        suite.expect(unindent.replacement == "- a\n- b", "Shift-Tab reverses list indentation")
        let literal = ScratchpadMarkdown("\\*literal\\* and unfinished **text")
        suite.expect(literal.markers.isEmpty, "escaped and incomplete inline syntax stays visible")
        let checklist = ScratchpadSupport.edit(applying: .checklist, to: "Task", selection: NSRange(location: 4, length: 0))
        suite.expect(checklist.replacement == "- [ ] Task", "the toolbar creates a checklist through the shared edit helper")
        let reusable = "# List\r\n- [X] Done 🙂\r\n    - [ ] Keep child\r\n- [ ] Pending\r\n\r\n```\r\n- [x] Example\r\n```\r\n- [x] Last"
        let reusableAnalysis = ScratchpadMarkdown(reusable)
        let pending = (reusable as NSString).range(of: "Pending")
        let reset = reusableAnalysis.checklistEdit(.uncheckAll, in: reusable, selection: pending)!
        let resetText = (reusable as NSString).replacingCharacters(in: reset.range, with: reset.replacement)
        suite.expect(resetText.contains("- [ ] Done 🙂") && resetText.hasSuffix("- [ ] Last")
                     && resetText.contains("- [x] Example") && reset.selection == pending,
                     "uncheck all resets real tasks and preserves code and the selected text")
        let clean = reusableAnalysis.checklistEdit(.removeCompleted, in: reusable, selection: pending)!
        let cleanText = (reusable as NSString).replacingCharacters(in: clean.range, with: clean.replacement)
        suite.expect(cleanText == "# List\r\n    - [ ] Keep child\r\n- [ ] Pending\r\n\r\n```\r\n- [x] Example\r\n```\r\n"
                     && (cleanText as NSString).substring(with: clean.selection) == "Pending",
                     "completed cleanup preserves unchecked descendants, code, CRLF and the selected text")
        let inside = reusableAnalysis.checklistEdit(.removeCompleted, in: reusable,
            selection: (reusable as NSString).range(of: "Done 🙂"))!
        suite.expect(inside.selection == NSRange(location: 8, length: 0), "selection in a removed task lands at the next surviving line")
        suite.expect(ScratchpadMarkdown("- [ ] Pending").checklistEdit(.uncheckAll, in: "- [ ] Pending", selection: .init(location: 0, length: 0)) == nil,
                     "checklist actions do nothing when all items are unchecked")
    }

    private final class EditorState: ObservableObject { @Published var text = "# Heading\n\n- [ ] First\n- [x] Second"; @Published var source = false }
    private struct Fixture: View {
        @ObservedObject var state: EditorState
        var body: some View { ScratchpadEditor(text: $state.text, sourceMode: state.source) }
    }
    private final class NavigationState: ObservableObject {
        @Published var texts = ["First note", "Second note"]
        @Published var selected = 0
        @Published var browsing = false
        var navigations: [Int] = []
        let ids = [UUID(), UUID()]
        let sessions = ScratchpadEditor.Sessions()
    }
    private struct NavigationFixture: View {
        @ObservedObject var state: NavigationState
        var body: some View {
            if !state.browsing {
                ScratchpadEditor(text: $state.texts[state.selected],
                                 session: state.sessions.session(for: state.ids[state.selected]),
                                 onNavigate: { state.navigations.append($0) })
                    .id(state.selected)
            }
        }
    }
    private static func nativeNavigation(_ suite: TestSuite) {
        let state = NavigationState()
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 430, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: NavigationFixture(state: state))
        window.contentView = host
        defer { window.contentView = nil }
        func settle() {
            for _ in 0..<8 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        }
        func findEditor(_ view: NSView) -> ScratchpadEditor.TextView? {
            (view as? ScratchpadEditor.TextView) ?? view.subviews.compactMap(findEditor).first
        }
        settle()
        guard let first = findEditor(host) else { suite.expect(false, "first cached editor exists"); return }
        window.makeFirstResponder(first)
        first.setSelectedRange(NSRange(location: 0, length: 0))
        first.insertText("A ", replacementRange: first.selectedRange())
        first.breakUndoCoalescing()
        settle()
        state.selected = 1
        settle()
        guard let second = findEditor(host) else { suite.expect(false, "second cached editor exists"); return }
        window.makeFirstResponder(second)
        second.setSelectedRange(NSRange(location: 0, length: 0))
        second.insertText("B ", replacementRange: second.selectedRange())
        second.breakUndoCoalescing()
        settle()
        state.selected = 0
        settle()
        suite.expect(findEditor(host) === first && first.undoManager !== second.undoManager,
                     "switching notes reuses the native editor with a separate undo history per note")
        for (key, code) in [("[", UInt16(33)), ("]", UInt16(30))] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code)!
            first.keyDown(with: event)
        }
        suite.expect(state.navigations == [-1, 1] && state.texts == ["A First note", "B Second note"],
                     "Command-bracket navigation reaches the workspace without inserting text")
        first.undoManager?.undo()
        settle()
        suite.expect(state.texts == ["First note", "B Second note"], "undo after switching changes only the selected note")
        state.browsing = true
        settle()
        state.browsing = false
        settle()
        first.undoManager?.redo()
        settle()
        suite.expect(findEditor(host) === first && state.texts == ["A First note", "B Second note"],
                     "opening and closing the library preserves the editor and redo history")
        state.texts[0] = "Restored externally"
        settle()
        suite.expect(first.string == "Restored externally" && first.undoManager?.canUndo == false,
                     "external document replacement clears obsolete undo history")
        state.selected = 1
        settle()
        second.undoManager?.undo()
        settle()
        suite.expect(state.texts == ["Restored externally", "Second note"], "the other note keeps its independent undo history")
        state.browsing = true
        settle()
        state.sessions.retain([])
        state.browsing = false
        settle()
        suite.expect(findEditor(host) !== second && findEditor(host)?.undoManager?.canUndo == false,
                     "closing notes releases cached editing sessions")
    }
    private static func nativeEditor(_ suite: TestSuite) {
        _ = NSApplication.shared
        let state = EditorState()
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 430, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: Fixture(state: state))
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 430, height: 300)
        func settle() {
            for _ in 0..<8 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        settle()
        guard let editor = descendants(host).compactMap({ $0 as? ScratchpadEditor.TextView }).first,
              let coordinator = editor.delegate as? ScratchpadEditor.Coordinator else {
            suite.expect(false, "the native Scratchpad editor is created"); return
        }
        suite.expect(editor.string == state.text && descendants(editor).filter { $0 is NSButton }.count == 2,
                     "rendered tasks expose native checkboxes without replacing source text")
        let headingFont = editor.textStorage?.attribute(.font, at: 8, effectiveRange: nil) as? NSFont
        suite.expect((headingFont?.pointSize ?? 0) > 13, "heading presentation styles its final character")
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.undoManager?.removeAllActions()
        guard let checkbox = descendants(editor).compactMap({ $0 as? NSButton }).first else { return }
        let task = ScratchpadMarkdown(editor.string).tasks[0]
        func taskGlyphX(at character: Int) -> CGFloat {
            let manager = editor.layoutManager!
            manager.ensureLayout(forCharacterRange: task.line)
            let glyph = manager.glyphIndexForCharacter(at: character)
            return editor.textContainerOrigin.x + manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minX
                + manager.location(forGlyphAt: glyph).x
        }
        suite.expect(checkbox.frame.maxX <= taskGlyphX(at: task.content.location), "inactive checklist controls stay in the gutter")
        editor.setSelectedRange(NSRange(location: task.content.location, length: 0))
        settle()
        let manager = editor.layoutManager!
        let prefixGlyph = manager.glyphIndexForCharacter(at: task.prefix.location)
        suite.expect(manager.propertyForGlyph(at: prefixGlyph).contains(.null),
                     "an active checklist hides its Markdown prefix")
        suite.expect(checkbox.frame.maxX <= taskGlyphX(at: task.content.location),
                     "the active checkbox stays beside the content")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        checkbox.performClick(nil)
        settle()
        suite.expect(state.text.contains("- [x] First"), "clicking a native checkbox updates Markdown")
        editor.undoManager?.undo()
        editor.didChangeText()
        settle()
        suite.expect(state.text.contains("- [ ] First"), "one undo restores the checkbox")
        for action in [ScratchpadMarkdown.ChecklistAction.uncheckAll, .removeCompleted] {
            editor.undoManager?.removeAllActions()
            let original = editor.string
            suite.expect(coordinator.applyChecklist(action), "bulk checklist action is available")
            settle()
            suite.expect(!state.text.contains("- [x] Second"), "bulk checklist action updates the actual editor")
            editor.undoManager?.undo()
            editor.didChangeText()
            settle()
            suite.expect(state.text == original, "one native Undo restores the entire \(action) action: \(state.text)")
        }
        editor.setSelectedRange(NSRange(location: task.content.location, length: 2))
        let selected = editor.selectedRange()
        let before = editor.string
        state.source = true
        settle()
        suite.expect(editor.string == before && editor.selectedRange() == selected
                     && descendants(editor).filter { $0 is NSButton }.isEmpty,
                     "source mode preserves the document and selection and removes checkbox overlays")
        state.source = false
        settle()
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        let count = (editor.string as NSString).length
        let edit = ScratchpadMarkdown.continueList(in: editor.string, selection: NSRange(location: count, length: 0))!
        coordinator.apply(edit)
        settle()
        suite.expect(editor.string.hasSuffix("\n- [ ] "), "native list continuation commits an editable new task")
        let emptyButton = descendants(editor).compactMap { $0 as? NSButton }.last
        suite.expect(emptyButton?.isHidden == false, "an empty checklist item keeps its checkbox while typing")
        let continued = editor.string
        suite.expect(coordinator.textView(editor, doCommandBy: #selector(NSTextView.deleteBackward(_:))),
                     "Backspace at the start of a task removes its hidden prefix as one edit")
        settle()
        suite.expect(editor.string == String(continued.dropLast(6)), "removing a task prefix leaves no broken Markdown")
        state.text = "- Bullet\n- "
        settle()
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        let bulletFont = editor.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        var bulletCharacter: UniChar = 0x2022
        var bulletGlyph = CGGlyph()
        CTFontGetGlyphsForCharacters(bulletFont, &bulletCharacter, &bulletGlyph, 1)
        suite.expect(manager.glyph(at: manager.glyphIndexForCharacter(at: 0)) == bulletGlyph
                     && manager.glyph(at: manager.glyphIndexForCharacter(at: 9)) == bulletGlyph,
                     "typed dash prefixes display bullet glyphs including the empty active item")
        state.source = true
        settle()
        var dashCharacter: UniChar = 45
        var dashGlyph = CGGlyph()
        CTFontGetGlyphsForCharacters(bulletFont, &dashCharacter, &dashGlyph, 1)
        suite.expect(editor.string == "- Bullet\n- " && manager.glyph(at: manager.glyphIndexForCharacter(at: 0)) == dashGlyph,
                     "source mode restores literal list syntax without changing canonical Markdown")
        state.source = false
        state.text = "- [ ] Parent\n    - [ ] Nested"
        settle()
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        settle()
        let nestedButtons = descendants(editor).compactMap { $0 as? NSButton }.sorted { $0.tag < $1.tag }
        suite.expect(nestedButtons.count == 2 && nestedButtons[1].frame.minX > nestedButtons[0].frame.minX,
                     "nested task controls follow the indentation of their content")
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.setMarkedText("漢", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.didChangeText()
        let composition = editor.string
        let marked = editor.markedRange()
        state.source = true
        settle()
        coordinator.apply(ScratchpadSupport.edit(applying: .bold, to: editor.string, selection: editor.selectedRange()))
        suite.expect(editor.hasMarkedText() && editor.markedRange() == marked && editor.string == composition,
                     "source changes and formatting leave active input-method composition intact")
        editor.unmarkText()
        window.contentView = nil
    }
}
