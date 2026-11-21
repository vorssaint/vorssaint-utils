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
                     && keys.highlightedID == second.id && keys.keysMoved
                     && keys.handleKey(key(36, "\r"), composing: false, editing: true)
                     && keys.activated == [second.id],
                     "Down and Return in the focused clipboard search move to and paste the next entry")
        suite.expect(!keys.handleKey(key(126, "\u{F700}", [.shift, .numericPad, .function]),
                                     composing: false, editing: true)
                     && !keys.handleKey(key(36, "\r", .shift), composing: false, editing: true)
                     && keys.highlightedID == second.id && keys.activated == [second.id],
                     "Shift with an arrow or Return stays the clipboard search field's, which selects with it")
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
}
