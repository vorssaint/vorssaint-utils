// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The island's clipboard page as it reads its entry size, its keys and the
/// pointer, compiled from the page itself onto a page that only keeps state.
/// An open compact entry is drawn over the list, so only the pointer decides
/// when it closes: resting on the entry below must not keep it open.
enum NotchClipboardPageTests {
    /// The history's own entry, whose card preview the page's open entries show.
    typealias HistoryEntry = ClipboardHistoryEntry

    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated { checks(suite) }
    }

    @MainActor private static func checks(_ suite: TestSuite) {
        keyboardSelectionRouting(suite)
        keyboardSelectionPage(suite)
        searchSelectionKeepsArrows(suite)
        batchActivation(suite)
        let first = Page.ClipboardHistoryEntry(id: UUID()), second = Page.ClipboardHistoryEntry(id: UUID())

        let page = Page()
        page.hover(first, true)
        suite.expect(page.dwell?.id == first.id && page.hoveredID == first.id,
                     "resting on a compact clipboard entry waits to open it")
        page.expandedID = first.id
        page.hover(first, false)
        let closing = page.closing?.task
        suite.expect(page.closing?.id == first.id && page.dwell == nil && page.hoveredID == nil,
                     "leaving the open clipboard entry starts its close")
        page.hover(second, true)
        suite.expect(page.closing?.id == first.id && closing?.isCancelled == false && page.dwell?.id == second.id,
                     "resting on the next clipboard entry leaves the open one's close running")
        page.hover(second, false)
        suite.expect(page.closing?.id == first.id && closing?.isCancelled == false && page.dwell == nil,
                     "the open clipboard entry closes when the pointer leaves the list through the next one")
        page.hover(first, true)
        suite.expect(page.closing == nil && closing?.isCancelled == true && page.dwell == nil,
                     "coming back to the open clipboard entry keeps it open")
        finish(page)

        // The pointer may reach the next entry before it is reported leaving the open one.
        let early = Page()
        early.expandedID = first.id
        early.hoveredID = first.id
        early.hover(second, true)
        early.hover(first, false)
        suite.expect(early.dwell?.id == second.id && early.dwell?.task.isCancelled == false
                     && early.closing?.id == first.id && early.hoveredID == second.id,
                     "a late exit from the open clipboard entry neither stops the next one opening nor keeps it open")
        finish(early)

        // The open entry is drawn over the rows below, which keep their place.
        let rows = Page()
        rows.expandedID = first.id
        suite.expect(rows.rowHeight == NotchLayout.clipboardCompactCardHeight,
                     "an open compact clipboard entry keeps its row's height, so the rows below stay put")
        rows.cardSize = NotchClipboardCardSize.comfortable.rawValue
        suite.expect(rows.rowHeight == NotchLayout.clipboardCardHeight, "comfortable clipboard rows keep their height")

        // The search field keeps the focus while hidden: the keys typed reach
        // it as they are, and only show it; the arrows and Return drive the list.
        let opening = Page()
        opening.entries = [first, second]
        opening.appeared()
        suite.expect(opening.searching && !opening.searchOpen && opening.highlightedID == first.id,
                     "the clipboard page opens on its first entry with the hidden search field focused")
        let preview = Page()
        preview.preview = true
        preview.appeared()
        suite.expect(!preview.searching && preview.highlightedID == nil,
                     "the clipboard page drawn in Settings leaves the keyboard alone")
        opening.keysMoved = true
        opening.queryChanged("n")
        suite.expect(opening.searchOpen && !opening.keysMoved,
                     "text reaching the hidden clipboard search, pasted into it too, shows it")
        opening.searchOpen = false
        opening.queryChanged("")
        suite.expect(!opening.searchOpen, "an emptied clipboard search does not show itself")

        // Pinned entries lead the list, so the entry copied last is the first
        // recent one: the page opens there, and a search on its top result.
        let pinned = Page.ClipboardHistoryEntry(id: UUID(), isPinned: true)
        let recent = Page.ClipboardHistoryEntry(id: UUID())
        let resting = Page()
        resting.entries = [pinned, recent]
        resting.appeared()
        suite.expect(resting.highlightedID == recent.id,
                     "the clipboard page opens on the entry copied last, below the pinned ones")
        resting.query = "note"
        resting.queryChanged("note")
        suite.expect(resting.highlightedID == pinned.id, "a clipboard search highlights its top result, pinned or not")
        resting.query = ""
        resting.queryChanged("")
        suite.expect(resting.highlightedID == recent.id, "an emptied clipboard search goes back to the entry copied last")

        // The page opens at the list's top, the pinned entries whole, while
        // the entry copied last shows half a compact entry's height or more:
        // below one pinned comfortable 104-point entry it keeps 68 points of a
        // 180-point list, and below two 40 of a 264-point one. Otherwise the
        // list moves by whole entries, keeping the one at its top whole.
        let pinnedToo = Page.ClipboardHistoryEntry(id: UUID(), isPinned: true)
        func scrollsOpening(_ entries: [Page.ClipboardHistoryEntry], comfortable: Bool = true,
                     height: CGFloat) -> [(id: UUID, anchor: UnitPoint?)] {
            let page = Page()
            if comfortable { page.cardSize = NotchClipboardCardSize.comfortable.rawValue }
            page.entries = entries
            page.size.height = height
            let list = Page.ScrollViewProxy()
            page.follow(recent.id, from: nil, in: list)
            return list.scrolls
        }
        suite.expect(scrollsOpening([pinned, recent], height: 180).isEmpty
                     && scrollsOpening([pinned, pinnedToo, recent], height: 264).isEmpty
                     && scrollsOpening([pinned, pinnedToo, recent], comfortable: false, height: 180).isEmpty,
                     "the clipboard page opens unscrolled while the entry copied last shows its top")
        let moved = scrollsOpening([pinned, pinnedToo, recent], height: 180)
        suite.expect(moved.count == 1 && moved.first?.id == pinnedToo.id && moved.first?.anchor == .top,
                     "the clipboard page opens moved by whole entries when the entry copied last is out of view")
        let following = Page()
        following.cardSize = NotchClipboardCardSize.comfortable.rawValue
        following.entries = [pinned, recent]
        let list = Page.ScrollViewProxy()
        following.follow(pinned.id, from: recent.id, in: list)
        suite.expect(list.scrolls.count == 1 && list.scrolls.first?.id == pinned.id && list.scrolls.first?.anchor == nil,
                     "a highlight that moves brings its clipboard entry into view the least the list can")

        func key(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags = [],
                 unmodified: String? = nil) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                             windowNumber: 0, context: nil, characters: characters,
                             charactersIgnoringModifiers: unmodified ?? characters, isARepeat: false, keyCode: code)!
        }
        let keys = Page()
        keys.entries = [first, second]
        keys.highlightedID = first.id
        suite.expect(!keys.handleKey(key(0, "a"), composing: false, editing: true)
                     && keys.searchOpen && keys.query.isEmpty,
                     "a letter typed on the clipboard page shows the hidden search field and goes on to it")
        suite.expect(!keys.handleKey(key(36, "\r"), composing: true, editing: true)
                     && keys.activated.isEmpty,
                     "Return while an input method composes in the clipboard search stays the input method's")
        suite.expect(keys.handleKey(key(125, "\u{F701}"), composing: false, editing: true)
                     && keys.highlightedID == first.id && keys.keysMoved
                     && keys.handleKey(key(125, "\u{F701}"), composing: false, editing: true)
                     && keys.highlightedID == second.id
                     && keys.handleKey(key(36, "\r"), composing: false, editing: true)
                     && keys.activated == [second.id],
                     "Down and Return in the focused clipboard search move to and paste the next entry")
        suite.expect(keys.handleKey(key(126, "\u{F700}", [.shift, .numericPad, .function]),
                                    composing: false, editing: true)
                     && !keys.handleKey(key(36, "\r", .shift), composing: false, editing: true)
                     && keys.highlightedID == first.id && keys.selectedIDs == [first.id, second.id]
                     && keys.activated == [second.id],
                     "Shift arrows select clipboard entries while Shift-Return retains search ownership")
        keys.query = "note"
        keys.closeSearch()
        suite.expect(keys.query.isEmpty && !keys.searchOpen && keys.searching,
                     "closing the clipboard search empties and hides it, keeping the field focused for the next key")

        // Real Control events carry control characters. The letters come from
        // the active layout, so these deliberately use other physical keys.
        let next = key(0, "\u{e}", .control, unmodified: "n")
        let previous = key(2, "\u{10}", [.control, .capsLock], unmodified: "P")
        for searchOpen in [false, true] {
            let navigation = Page()
            navigation.entries = [first, second]
            navigation.highlightedID = first.id
            navigation.searching = true
            navigation.searchOpen = searchOpen
            navigation.query = searchOpen ? "note" : ""
            let query = navigation.query
            suite.expect(navigation.handleKey(next, composing: false, editing: true)
                         && navigation.highlightedID == second.id && navigation.keysMoved
                         && navigation.handleKey(previous, composing: false, editing: true)
                         && navigation.highlightedID == first.id,
                         "Control-N/P move through the clipboard with the search hidden or open")
            suite.expect(navigation.handleKey(previous, composing: false, editing: true)
                         && navigation.highlightedID == first.id
                         && navigation.handleKey(next, composing: false, editing: true)
                         && navigation.handleKey(next, composing: false, editing: true)
                         && navigation.highlightedID == second.id,
                         "Control-N/P stop at the ends of the clipboard list, like the arrows")
            suite.expect(navigation.query == query && navigation.searchOpen == searchOpen && navigation.searching
                         && navigation.activated.isEmpty,
                         "Control navigation neither edits nor reveals the search and never pastes on its own")
            navigation.keysMoved = false
            suite.expect(!navigation.handleKey(next, composing: true, editing: true)
                         && !navigation.handleKey(previous, composing: true, editing: true)
                         && navigation.highlightedID == second.id && !navigation.keysMoved,
                         "a composing input method keeps Control-N/P without moving the highlight")
            for modifiers: NSEvent.ModifierFlags in [[.control, .shift], [.control, .option], [.control, .command]] {
                suite.expect(!navigation.handleKey(key(2, "\u{10}", modifiers, unmodified: "p"),
                                                  composing: false, editing: true)
                             && navigation.highlightedID == second.id && !navigation.keysMoved,
                             "an extra modifier leaves Control-P with its existing shortcut")
            }
            suite.expect(!navigation.handleKey(key(0, "\u{1}", .control, unmodified: "a"),
                                              composing: false, editing: true)
                         && navigation.query == query && navigation.searchOpen == searchOpen,
                         "unrelated Control shortcuts keep editing the search without changing its visibility")
            suite.expect(navigation.handleKey(key(36, "\r"), composing: false, editing: true)
                         && navigation.activated == [second.id],
                         "Return pastes the entry selected by Control navigation")
        }
        let empty = Page()
        suite.expect(!empty.handleKey(next, composing: false, editing: true)
                     && !empty.handleKey(previous, composing: false, editing: true)
                     && empty.highlightedID == nil && !empty.keysMoved && !empty.searchOpen,
                     "an empty clipboard does not consume Control navigation or reveal the search")
        let unfocused = Page()
        suite.expect(!unfocused.handleKey(key(0, "a"), composing: false, editing: false)
                     && unfocused.searchOpen && unfocused.searching,
                     "typing after the focus left the clipboard search brings the focus back to it")
        unfocused.searching = false
        unfocused.searchOpen = false
        unfocused.openSearch()
        suite.expect(unfocused.searchOpen && unfocused.searching, "the magnifier shows the clipboard search with the focus in it")

        // A copy often starts or ends with blank lines; the open entry shows
        // its text from the first line, tabs as spaces, as the panel's cards do.
        let spaced = Page.ClipboardHistoryEntry(id: UUID(), text: "\n\n\n\tlet x = 1\n\treturn x\n\n")
        let long = Page.ClipboardHistoryEntry(id: UUID(), text: String(repeating: "word ", count: 2_000))
        suite.expect(Page().openText(spaced) == "let x = 1\n return x"
                     && Page().openText(long).count <= NotchClipboardCardSize.maximumOpenLines * 120,
                     "an open clipboard entry shows the card preview, not the blank lines a copy starts with")

        // A 3:2 picture in a 40-point row is 60 points wide, narrower than the
        // 72 points a compact row gives it: it is rounded at its own corners,
        // in a compact row and in a comfortable card alike.
        for compact in [true, false] {
            let picture = Page().thumbnail(Color.white.aspectRatio(1.5, contentMode: .fit), compact: compact)
                .frame(width: 100, height: 40, alignment: .topLeading)
            let renderer = ImageRenderer(content: picture)
            renderer.scale = 2
            let corners = renderer.cgImage.map { image in
                [alpha(image, x: 0, y: 0), alpha(image, x: 119, y: 0), alpha(image, x: 119, y: 79), alpha(image, x: 60, y: 40)]
            }
            suite.expect(corners == [0, 0, 0, 255],
                         "a \(compact ? "compact" : "comfortable") clipboard thumbnail is rounded at the picture's own corners")
        }

        // Comfortable entries are whole already, nothing stored included.
        for stored in [NotchClipboardCardSize.comfortable.rawValue, "", "huge"] {
            let page = Page()
            page.cardSize = stored
            page.hover(first, true)
            suite.expect(page.dwell == nil && page.hoveredID == nil,
                         "the clipboard page reads \"\(stored)\" as comfortable entries, which never open on hover")
        }
    }

    /// The opacity of one pixel, counted from the image's top left.
    private static func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        }
        return pixel[3]
    }

    @MainActor private static func finish(_ page: Page) {
        page.dwell?.task.cancel()
        page.closing?.task.cancel()
    }

    private static func keyboardSelectionRouting(_ suite: TestSuite) {
        for code: UInt16 in [125, 126] {
            let step = code == 126 ? -1 : 1
            for incidental: NSEvent.ModifierFlags in [[], [.capsLock, .function, .numericPad]] {
                suite.expect(NotchSupport.clipboardKey(keyCode: code, characters: "", modifiers: [.shift, incidental],
                                                       composing: false) == .extend(step),
                             "the vertical clipboard page routes Shift arrows to range selection")
                suite.expect(NotchSupport.clipboardKey(keyCode: code, characters: "",
                                                       modifiers: [.command, .shift, incidental],
                                                       composing: false) == .toggle(step),
                             "Command-Shift arrows invert the range including its anchor")
            }
            for extra: NSEvent.ModifierFlags in [.option, .control] {
                for modifiers: NSEvent.ModifierFlags in [[.shift, extra], [.command, .shift, extra]] {
                    suite.expect(NotchSupport.clipboardKey(keyCode: code, characters: "",
                                                           modifiers: modifiers, composing: false) == nil,
                                 "extra shortcut modifiers leave selection keys unclaimed")
                }
            }
            for modifiers: NSEvent.ModifierFlags in [.shift, [.command, .shift], .command] {
                suite.expect(NotchSupport.clipboardKey(keyCode: code, characters: "", modifiers: modifiers,
                                                       composing: true) == (modifiers == .shift ? .reveal : nil),
                             "composition keeps selection keys and may reveal the search without consuming them")
                suite.expect(NotchSupport.clipboardKey(keyCode: code, characters: "", modifiers: modifiers,
                                                       composing: false, isEditingBody: true) == nil,
                             "body editing keeps clipboard selection and navigation keys")
                suite.expect(NotchSupport.clipboardKey(keyCode: code, characters: "", modifiers: modifiers,
                                                       composing: false, searchIsEmpty: false) == nil,
                             "nonempty search owns modified arrows before list navigation")
            }
            for active in [false, true] {
                suite.expect(NotchSupport.clipboardKey(keyCode: code, characters: "", modifiers: .command,
                                                       composing: false, interactionActive: active) == .skip(step),
                             "Command arrows navigate whether or not a clipboard session is active")
            }
            suite.expect(NotchSupport.clipboardKey(keyCode: code, characters: "", modifiers: .shift,
                                                   composing: false, searchIsEmpty: false,
                                                   listNavigationActive: true) == .extend(step)
                         && NotchSupport.clipboardKey(keyCode: code, characters: "", modifiers: [.command, .shift],
                                                      composing: false, searchIsEmpty: false,
                                                      listNavigationActive: true) == .toggle(step),
                         "list navigation hands nonempty search results to range and toggle selection")
        }
        for code: UInt16 in [123, 124] {
            for modifiers: NSEvent.ModifierFlags in [.shift, [.command, .shift], .command] {
                suite.expect(NotchSupport.clipboardKey(keyCode: code, characters: "", modifiers: modifiers,
                                                       composing: false) == nil,
                             "the vertical clipboard page leaves side arrows to text editing")
            }
        }
        suite.expect(NotchSupport.clipboardKey(keyCode: 53, characters: "", modifiers: [],
                                               composing: false, hasSelection: true) == .clearSelection,
                     "Escape clears a retained selection outside a keyboard session")
        suite.expect(NotchSupport.clipboardKey(keyCode: 53, characters: "", modifiers: [],
                                               composing: false) == nil,
                     "Escape without selected entries retains the island close handling")
    }

    @MainActor private static func keyboardSelectionPage(_ suite: TestSuite) {
        let a = Page.ClipboardHistoryEntry(id: UUID())
        let b = Page.ClipboardHistoryEntry(id: UUID())
        let c = Page.ClipboardHistoryEntry(id: UUID())
        let d = Page.ClipboardHistoryEntry(id: UUID())
        let e = Page.ClipboardHistoryEntry(id: UUID())
        func page() -> Page {
            let page = Page()
            page.entries = [a, b, c, d, e]
            page.history.entries = [a, b, c, d, e]
            page.appeared()
            return page
        }
        func arrow(_ code: UInt16 = 125, _ modifiers: NSEvent.ModifierFlags = .shift,
                   type: NSEvent.EventType = .keyDown) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
                             windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                             isARepeat: false, keyCode: code)!
        }

        for modifiers: NSEvent.ModifierFlags in [[], .command, .shift, [.command, .shift]] {
            for code: UInt16 in [125, 126] {
                let first = page()
                first.highlightedID = c.id // Resting highlights are not explicit keyboard focus.
                suite.expect(first.handleKey(arrow(code, modifiers), composing: false, editing: true)
                             && first.highlightedID == a.id && first.keysMoved
                             && first.selectedIDs == (modifiers.contains(.shift) ? Set([a.id]) : Set<UUID>()),
                             "the first arrow reveals the first entry and both selection chords include that anchor")
            }
        }

        let range = page()
        range.highlightedID = b.id
        range.keysMoved = true
        range.selectedIDs = [b.id, e.id]
        for (code, focus, selected) in [
            (UInt16(125), c.id, Set([b.id, c.id, e.id])),
            (125, d.id, Set([b.id, c.id, d.id, e.id])),
            (126, c.id, Set([b.id, c.id, e.id])),
            (126, b.id, Set([b.id, e.id])),
            (126, a.id, Set([a.id, b.id, e.id]))
        ] {
            suite.expect(range.handleKey(arrow(code), composing: false, editing: true)
                         && range.highlightedID == focus && range.selectedIDs == selected && range.showsSelection,
                         "Shift expands and shrinks across a fixed anchor while retaining discrete selections")
        }
        let bounded = range.selectedIDs
        suite.expect(range.handleKey(arrow(126), composing: false, editing: true)
                     && range.selectedIDs == bounded && range.highlightedID == a.id,
                     "range selection stops at the first clipboard entry")
        let list = Page.ScrollViewProxy()
        range.follow(a.id, from: b.id, in: list)
        suite.expect(list.scrolls.last?.id == a.id, "selection focus follows the existing clipboard scroll behavior")

        let toggled = page()
        toggled.highlightedID = b.id
        toggled.keysMoved = true
        toggled.selectedIDs = [b.id, c.id]
        for (code, focus, selected) in [
            (UInt16(125), c.id, Set<UUID>()),
            (125, d.id, Set([d.id])),
            (126, c.id, Set<UUID>()),
            (126, b.id, Set([c.id])),
            (126, a.id, Set([a.id, c.id]))
        ] {
            suite.expect(toggled.handleKey(arrow(code, [.command, .shift]), composing: false, editing: true)
                         && toggled.highlightedID == focus && toggled.selectedIDs == selected,
                         "Command-Shift inverts the inclusive anchored range and restores the original state on retreat")
        }
        toggled.highlightedID = e.id
        toggled.keyboardSelection.reset()
        let atEnd = toggled.selectedIDs
        suite.expect(toggled.handleKey(arrow(125, [.command, .shift]), composing: false, editing: true)
                     && toggled.highlightedID == e.id && toggled.selectedIDs == atEnd,
                     "repeated toggle arrows at the boundary do not toggle the stationary focus")

        let release = page()
        release.highlightedID = b.id
        release.keysMoved = true
        _ = release.handleKey(arrow(), composing: false, editing: true)
        _ = release.handleKey(arrow(), composing: false, editing: true)
        suite.expect(!release.handleKey(arrow(56, [], type: .flagsChanged), composing: true, editing: true,
                                       searchHasSelection: true, isEditingBody: true)
                     && !release.keyboardSelection.isActive && release.selectedIDs == [b.id, c.id, d.id]
                     && release.highlightedID == d.id && release.showsSelection,
                     "modifier release ends a keyboard session before text ownership checks and keeps all markers")
        suite.expect(release.handleKey(arrow(126), composing: false, editing: true)
                     && release.selectedIDs == [b.id, c.id, d.id] && release.highlightedID == c.id,
                     "a new Shift session starts from the retained focus and final selection")
        suite.expect(!release.handleKey(arrow(56, [], type: .flagsChanged), composing: false, editing: true)
                     && release.handleKey(arrow(53, []), composing: false, editing: true)
                     && release.selectedIDs.isEmpty && !release.showsSelection && !release.keyboardSelection.isActive,
                     "Escape clears retained selections after the modifier session has ended")
        suite.expect(!release.handleKey(arrow(53, []), composing: false, editing: true),
                     "Escape without a selection returns to the island close handling")

        for modifiers: NSEvent.ModifierFlags in [[], .command] {
            let navigation = page()
            navigation.highlightedID = b.id
            navigation.keysMoved = true
            _ = navigation.handleKey(arrow(), composing: false, editing: true)
            suite.expect(navigation.handleKey(arrow(125, modifiers), composing: false, editing: true)
                         && navigation.highlightedID == d.id && navigation.selectedIDs == [b.id, c.id]
                         && !navigation.keyboardSelection.isActive && navigation.showsSelection,
                         "ordinary and Command navigation end the session while retaining selection")
            navigation.hover(e, true)
            suite.expect(navigation.highlightedID == d.id && navigation.selectedIDs == [b.id, c.id],
                         "hovering does not change keyboard focus or selection")
            finish(navigation)
            suite.expect(navigation.handleKey(arrow(), composing: false, editing: true)
                         && navigation.selectedIDs == [b.id, c.id, d.id, e.id],
                         "resumed range selection includes the new origin after navigation")
        }

        let mouse = page()
        mouse.toggleSelection(b)
        suite.expect(mouse.selectedIDs == [b.id] && mouse.highlightedID == b.id && mouse.keysMoved
                     && mouse.keyboardSelection.focusID == b.id && !mouse.keyboardSelection.isActive
                     && mouse.showsSelection && mouse.activated.isEmpty,
                     "a checkbox establishes focus and anchor without activating clipboard content")
        suite.expect(mouse.handleKey(arrow(), composing: false, editing: true)
                     && mouse.selectedIDs == [b.id, c.id] && mouse.highlightedID == c.id,
                     "keyboard range selection starts from the checkbox anchor")
        mouse.toggleSelection(c)
        suite.expect(mouse.selectedIDs == [b.id] && mouse.highlightedID == c.id && mouse.showsSelection,
                     "a checkbox ends the keyboard session while preserving other selections")
        mouse.toggleSelection(b)
        suite.expect(mouse.selectedIDs.isEmpty && !mouse.showsSelection && !mouse.keyboardSelection.isActive
                     && mouse.highlightedID == b.id && mouse.keysMoved && mouse.keyboardSelection.focusID == b.id,
                     "unchecking the last entry retains its explicit mouse focus for the next range")

        let lifecycle = page()
        lifecycle.highlightedID = b.id
        lifecycle.keysMoved = true
        lifecycle.selectedIDs = [b.id]
        _ = lifecycle.handleKey(arrow(), composing: false, editing: true)
        lifecycle.visibleEntriesChanged()
        suite.expect(lifecycle.selectedIDs == [b.id, c.id] && lifecycle.keyboardSelection.isActive,
                     "identical visible identities preserve an active clipboard range")
        lifecycle.entries = [e, d, c, b, a]
        lifecycle.visibleEntriesChanged()
        suite.expect(lifecycle.selectedIDs == [b.id, c.id] && !lifecycle.keyboardSelection.isActive
                     && lifecycle.highlightedID == c.id && lifecycle.showsSelection,
                     "reordering ends the range while preserving selected UUIDs and visible focus")
        let inserted = Page.ClipboardHistoryEntry(id: UUID())
        lifecycle.history.entries.insert(inserted, at: 0)
        lifecycle.entries.insert(inserted, at: 0)
        lifecycle.visibleEntriesChanged()
        suite.expect(lifecycle.selectedIDs == [b.id, c.id] && !lifecycle.selectedIDs.contains(inserted.id),
                     "inserting clipboard history never selects the new identity")
        lifecycle.entries = [d, e]
        lifecycle.query = "filtered"
        lifecycle.queryChanged("filtered")
        suite.expect(lifecycle.selectedIDs == [b.id, c.id] && !lifecycle.keyboardSelection.isActive
                     && !lifecycle.keysMoved && lifecycle.highlightedID == d.id && lifecycle.showsSelection,
                     "queries retain hidden history selections and restore a visible resting focus")
        suite.expect(!lifecycle.handleKey(arrow(), composing: false, editing: true),
                     "nonempty search keeps Shift arrows until list navigation begins")
        _ = lifecycle.handleKey(arrow(125, []), composing: false, editing: true)
        suite.expect(lifecycle.highlightedID == d.id
                     && lifecycle.handleKey(arrow(), composing: false, editing: true)
                     && lifecycle.selectedIDs == [b.id, c.id, d.id, e.id],
                     "a fresh filtered range uses visible order without losing hidden selections")
        lifecycle.history.entries.removeAll { $0.id == b.id }
        lifecycle.visibleEntriesChanged()
        suite.expect(!lifecycle.keyboardSelection.isActive && lifecycle.selectedIDs == [c.id, d.id, e.id]
                     && lifecycle.highlightedID == e.id,
                     "deleting a hidden selection ends the range even when visible results do not change")
        suite.expect(lifecycle.handleKey(arrow(126), composing: false, editing: true)
                     && lifecycle.selectedIDs == [c.id, d.id, e.id] && lifecycle.highlightedID == d.id,
                     "a fresh range cannot resurrect the deleted hidden identity from its old base snapshot")
        lifecycle.entries = []
        lifecycle.visibleEntriesChanged()
        suite.expect(lifecycle.highlightedID == nil && !lifecycle.keyboardSelection.isActive
                     && lifecycle.selectedIDs == [c.id, d.id, e.id] && lifecycle.showsSelection,
                     "empty results clear focus and session while retaining all existing hidden selections")
        lifecycle.history.entries.removeAll { $0.id == b.id || $0.id == d.id }
        lifecycle.visibleEntriesChanged()
        suite.expect(lifecycle.selectedIDs == [c.id, e.id] && lifecycle.showsSelection,
                     "history deletion prunes only removed identities even when results stay empty")
        lifecycle.disappeared()
        suite.expect(lifecycle.selectedIDs.isEmpty && !lifecycle.keyboardSelection.isActive && !lifecycle.keysMoved,
                     "leaving the clipboard page clears its independent selection")

        let layout = page()
        layout.toggleSelection(b)
        _ = layout.handleKey(arrow(), composing: false, editing: true)
        layout.selectionContextChanged()
        suite.expect(layout.selectedIDs == [b.id, c.id] && layout.highlightedID == c.id
                     && !layout.keyboardSelection.isActive && layout.showsSelection,
                     "layout and filter context changes end the range without clearing valid selection")

        let deletedAnchor = page()
        deletedAnchor.toggleSelection(b)
        _ = deletedAnchor.handleKey(arrow(), composing: false, editing: true)
        _ = deletedAnchor.handleKey(arrow(), composing: false, editing: true)
        deletedAnchor.history.entries.removeAll { $0.id == b.id || $0.id == d.id }
        deletedAnchor.entries = [a, c, e]
        deletedAnchor.visibleEntriesChanged()
        suite.expect(deletedAnchor.selectedIDs == [c.id] && deletedAnchor.highlightedID == a.id
                     && !deletedAnchor.keyboardSelection.isActive,
                     "deleting anchor and focus keeps surviving selections and restores a visible focus")

        for enter: UInt16 in [36, 76] {
            let batch = page()
            _ = batch.handleKey(arrow(), composing: false, editing: true)
            _ = batch.handleKey(arrow(), composing: false, editing: true)
            _ = batch.handleKey(arrow(125, .command), composing: false, editing: true)
            suite.expect(batch.handleKey(arrow(enter, []), composing: false, editing: true)
                         && batch.history.writtenBatches == [[a.id, b.id]]
                         && batch.history.pastedTargets.count == 1 && batch.activated.isEmpty,
                         "Return and keypad Enter activate the final selection rather than the unselected focus")
        }

        let empty = Page()
        suite.expect(!empty.handleKey(arrow(), composing: false, editing: true)
                     && !empty.handleKey(arrow(76, []), composing: false, editing: true)
                     && !empty.showsSelection && empty.highlightedID == nil && empty.activated.isEmpty,
                     "an empty clipboard cannot start selection or activate another entry")
    }

    @MainActor private static func searchSelectionKeepsArrows(_ suite: TestSuite) {
        for code: UInt16 in [125, 126] {
            let entries = (0..<4).map { _ in Page.ClipboardHistoryEntry(id: UUID()) }
            let page = Page()
            page.entries = entries
            page.query = "note"
            page.highlightedID = entries[1].id
            page.keysMoved = true
            func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
                NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                 windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                 isARepeat: false, keyCode: code)!
            }
            _ = page.handleKey(key(125, .shift), composing: false, editing: true)
            let selected = page.selectedIDs
            let focus = page.highlightedID
            suite.expect(NotchSupport.clipboardKey(keyCode: code, characters: "", modifiers: [],
                                                   composing: false, interactionActive: true,
                                                   searchIsEmpty: false, searchHasSelection: true,
                                                   listNavigationActive: true) == nil,
                         "selected search text keeps ordinary arrows during clipboard range selection")
            suite.expect(!page.handleKey(key(code, []), composing: false, editing: true, searchHasSelection: true)
                         && page.highlightedID == focus && page.keyboardSelection.focusID == focus
                         && page.selectedIDs == selected && page.keyboardSelection.isActive,
                         "search-owned arrows neither consume the event nor move the clipboard range focus")
            // Re-enter list ownership without changing the model, then reverse
            // the prior extension. An erroneously ended segment would preserve
            // both selected entries instead of shrinking back to the origin.
            page.keysMoved = true
            suite.expect(page.handleKey(key(126, .shift), composing: false, editing: true)
                         && page.selectedIDs == [entries[1].id] && page.highlightedID == entries[1].id,
                         "search-owned arrows do not finish the current clipboard range segment")
        }
    }

    @MainActor final class BatchTarget {
        var isTerminated = false
    }

    @MainActor final class BatchPermissions {
        var accessibility = true
    }

    @MainActor final class BatchService {
        var collapseCount = 0
        var onCollapse: (() -> Void)?
        func collapse() {
            collapseCount += 1
            onCollapse?()
        }
    }

    /// Only OS side effects are replaced; the generator supplies the real
    /// batch ordering and activation methods alongside the real page method.
    @MainActor final class BatchHistory {
        typealias ClipboardHistoryEntry = Page.ClipboardHistoryEntry
        typealias NSRunningApplication = BatchTarget
        var entries: [ClipboardHistoryEntry] = []
        var batchPasteTarget: BatchTarget? = BatchTarget()
        var writtenBatches: [[UUID]] = []
        var pastedTargets: [BatchTarget] = []
        var writeSucceeds = true
        var deferWrite = false
        var writeCompletion: ((Bool) -> Void)?
        var accessibilityTrusted = true

        func copy(_ entries: [ClipboardHistoryEntry], completion: @escaping (Bool) -> Void) {
            writtenBatches.append(entries.map(\.id))
            if deferWrite { writeCompletion = completion } else { completion(writeSucceeds) }
        }

        func pasteIntoPreviousApp(_ target: BatchTarget?) {
            if let target { pastedTargets.append(target) }
        }

        func finishWrite(_ success: Bool) {
            let completion = writeCompletion
            writeCompletion = nil
            completion?(success)
        }
    }

    @MainActor private static func batchActivation(_ suite: TestSuite) {
        let a = Page.ClipboardHistoryEntry(id: UUID(), text: "alpha")
        let b = Page.ClipboardHistoryEntry(id: UUID(), text: "beta")
        let c = Page.ClipboardHistoryEntry(id: UUID(), text: "gamma")
        func page() -> Page {
            let page = Page()
            page.entries = [c, b, a] // Search order deliberately differs from history.
            page.history.entries = [a, b, c]
            page.selectedIDs = [c.id, a.id]
            page.highlightedID = b.id
            return page
        }

        let snapshot = page()
        let originalTarget = snapshot.history.batchPasteTarget
        snapshot.service.onCollapse = { [weak snapshot] in
            snapshot?.disappeared()
            snapshot?.history.batchPasteTarget = nil
            snapshot?.history.entries = []
        }
        snapshot.activateSelection()
        suite.expect(snapshot.service.collapseCount == 1 && snapshot.selectedIDs.isEmpty
                     && snapshot.history.batchPasteTarget == nil && snapshot.history.entries.isEmpty,
                     "clipboard collapse immediately cleans page selection and the live paste target")
        suite.expect(snapshot.history.writtenBatches == [[a.id, c.id]]
                     && snapshot.history.pastedTargets.count == 1
                     && snapshot.history.pastedTargets.first === originalTarget,
                     "real clipboard activation keeps the history-ordered batch and original target captured before collapse")

        let copy = page()
        copy.permissions.accessibility = false
        copy.history.batchPasteTarget = nil
        copy.activateSelection()
        suite.expect(copy.service.collapseCount == 0 && copy.history.writtenBatches == [[a.id, c.id]]
                     && copy.history.pastedTargets.isEmpty && copy.copiedID == a.id,
                     "clipboard activation without permission copies the entire batch and confirms it without collapse")

        let failed = page()
        failed.permissions.accessibility = false
        failed.history.writeSucceeds = false
        failed.activateSelection()
        suite.expect(failed.history.writtenBatches == [[a.id, c.id]] && failed.history.pastedTargets.isEmpty
                     && failed.copiedID == nil && failed.service.collapseCount == 0,
                     "failed clipboard batch copies neither paste nor report copied feedback")
        let failedPaste = page()
        failedPaste.history.writeSucceeds = false
        failedPaste.activateSelection()
        suite.expect(failedPaste.history.writtenBatches == [[a.id, c.id]]
                     && failedPaste.history.pastedTargets.isEmpty && failedPaste.copiedID == nil,
                     "a failed clipboard batch write cannot paste old clipboard contents")

        let empty = page()
        empty.history.entries = []
        empty.activateSelection()
        suite.expect(empty.history.writtenBatches.isEmpty && empty.history.pastedTargets.isEmpty
                     && empty.service.collapseCount == 0 && empty.selectedIDs.isEmpty && empty.copiedID == nil,
                     "an empty batch snapshot clears stale clipboard selection without collapse, writing or pasting")

        let exited = page()
        exited.history.batchPasteTarget?.isTerminated = true
        exited.activateSelection()
        suite.expect(exited.history.writtenBatches.isEmpty && exited.history.pastedTargets.isEmpty
                     && exited.service.collapseCount == 0 && exited.copiedID == nil,
                     "a terminated clipboard target does not collapse the page, write or paste")
        let missing = page()
        missing.history.batchPasteTarget = nil
        missing.activateSelection()
        suite.expect(missing.history.writtenBatches.isEmpty && missing.history.pastedTargets.isEmpty
                     && missing.service.collapseCount == 0,
                     "a missing clipboard target cannot redirect a batch paste to another app")

        let exitsDuringWrite = page()
        let departing = exitsDuringWrite.history.batchPasteTarget
        exitsDuringWrite.history.deferWrite = true
        exitsDuringWrite.activateSelection()
        departing?.isTerminated = true
        exitsDuringWrite.history.finishWrite(true)
        suite.expect(exitsDuringWrite.history.writtenBatches == [[a.id, c.id]]
                     && exitsDuringWrite.history.pastedTargets.isEmpty && exitsDuringWrite.copiedID == nil,
                     "a target that exits during a clipboard write never receives a paste")

        let revoked = page()
        revoked.history.accessibilityTrusted = false
        revoked.activateSelection()
        suite.expect(revoked.history.writtenBatches == [[a.id, c.id]]
                     && revoked.history.pastedTargets.isEmpty,
                     "a revoked accessibility grant preserves the clipboard copy without pasting")
    }
}
