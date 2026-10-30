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
                 unmodified: String? = nil, repeating: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                             windowNumber: 0, context: nil, characters: characters,
                             charactersIgnoringModifiers: unmodified ?? characters, isARepeat: repeating, keyCode: code)!
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
            suite.expect(navigation.handleKey(next, composing: false, editing: true)
                         && navigation.handleKey(key(49, " "), composing: false, editing: true)
                         && navigation.history.previewed == [second.id] && navigation.query == query,
                         "Space previews the entry selected by Control navigation without changing the search")
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

        let quickLook = Page()
        quickLook.entries = [first, second]
        quickLook.appeared()
        suite.expect(quickLook.handleKey(key(49, " ", []), composing: false, editing: true)
                     && quickLook.history.previewed == [first.id] && quickLook.activated.isEmpty && !quickLook.searchOpen,
                     "Space on the newly opened clipboard page previews its current entry without pasting or starting search")
        suite.expect(quickLook.handleKey(key(49, " ", [], repeating: true), composing: false, editing: true)
                     && quickLook.history.previewed == [first.id] && quickLook.highlightedID == first.id,
                     "holding preview Space does not decode or open another popup or move the clipboard selection")
        quickLook.openSearch()
        suite.expect(!quickLook.handleKey(key(49, " ", []), composing: false, editing: true)
                     && quickLook.history.previewed == [first.id],
                     "an opened clipboard search keeps its typed spaces")
        suite.expect(!quickLook.handleKey(key(49, " ", [], repeating: true), composing: false, editing: true),
                     "holding Space while typing in the clipboard search still inserts its spaces")
        _ = quickLook.handleKey(key(125, "\u{F701}", []), composing: false, editing: true)
        suite.expect(quickLook.handleKey(key(49, " ", []), composing: false, editing: true)
                     && quickLook.history.previewed == [first.id, second.id],
                     "Space after arrow navigation previews the highlighted clipboard search result")
        quickLook.query = "two words"
        quickLook.queryChanged(quickLook.query)
        suite.expect(!quickLook.handleKey(key(49, " ", []), composing: false, editing: true)
                     && quickLook.history.previewed == [first.id, second.id],
                     "typing after clipboard navigation returns Space to the search field")
        quickLook.closeSearch()
        for modifiers in [NSEvent.ModifierFlags.command, .control, .option, .shift, .function] {
            suite.expect(!quickLook.handleKey(key(49, " ", modifiers), composing: false, editing: true),
                         "modified Space keeps its system or text editing shortcut on the clipboard page")
        }
        suite.expect(!quickLook.handleKey(key(49, " ", []), composing: true, editing: true)
                     && quickLook.history.previewed == [first.id, second.id],
                     "Space while an input method composes stays with the clipboard search")
        quickLook.closeSearch()
        quickLook.highlightedID = UUID()
        suite.expect(quickLook.handleKey(key(49, " ", []), composing: false, editing: true)
                     && quickLook.history.previewed.last == first.id,
                     "clipboard preview recovers a removed highlight with the first visible entry, as paste does")
        quickLook.entries = []
        suite.expect(!quickLook.handleKey(key(49, " ", []), composing: false, editing: true),
                     "Space leaves an empty clipboard list without opening a stale preview")

        for cardSize in [NotchClipboardCardSize.compact, .comfortable] {
            let pointerPreview = Page()
            pointerPreview.cardSize = cardSize.rawValue
            pointerPreview.entries = [first, second]
            pointerPreview.appeared()
            pointerPreview.hover(second, true)
            suite.expect(pointerPreview.hoveredID == second.id
                         && pointerPreview.handleKey(key(49, " ", []), composing: false, editing: true)
                         && pointerPreview.history.previewed == [second.id]
                         && pointerPreview.highlightedID == first.id,
                         "Space previews the hovered \(cardSize.rawValue) card ahead of the keyboard highlight")
            pointerPreview.hover(first, true)
            pointerPreview.hover(second, false)
            suite.expect(pointerPreview.hoveredID == first.id,
                         "a late exit from the previous card preserves the new hover preview target")
            pointerPreview.hover(first, false)
            suite.expect(pointerPreview.handleKey(key(49, " ", []), composing: false, editing: true)
                         && pointerPreview.history.previewed == [second.id, first.id],
                         "Space falls back to the keyboard selection after leaving the clipboard cards")
            pointerPreview.openSearch()
            pointerPreview.hover(second, true)
            suite.expect(pointerPreview.handleKey(key(49, " ", []), composing: false, editing: true)
                         && pointerPreview.history.previewed.last == second.id,
                         "hovering a visible search result gives Space to that result without requiring arrow navigation")
            pointerPreview.queryChanged("two words")
            pointerPreview.hover(second, true, at: pointerPreview.searchPointerLocation!)
            suite.expect(pointerPreview.hoveredID == nil
                         && !pointerPreview.handleKey(key(49, " ", []), composing: false, editing: true),
                         "typing keeps search spaces when filtering moves a result under the stationary pointer")
            let stationary = pointerPreview.searchPointerLocation!
            pointerPreview.hover(second, true, at: CGPoint(x: stationary.x + 1, y: stationary.y))
            suite.expect(pointerPreview.handleKey(key(49, " ", []), composing: false, editing: true)
                         && pointerPreview.history.previewed.last == second.id,
                         "moving the pointer over a filtered result restores its preview without requiring a row exit")
            pointerPreview.closeSearch()
            pointerPreview.highlightedID = second.id
            pointerPreview.hoveredID = UUID()
            suite.expect(pointerPreview.handleKey(key(49, " ", []), composing: false, editing: true)
                         && pointerPreview.history.previewed.last == second.id,
                         "a removed hover target falls back to the valid keyboard highlight instead of another row")
            if cardSize == .comfortable {
                suite.expect(pointerPreview.dwell == nil && pointerPreview.expandedID == nil,
                             "comfortable hover targeting does not start compact-card expansion")
            }
            finish(pointerPreview)
        }
        let settingsHover = Page()
        settingsHover.preview = true
        settingsHover.hover(first, true)
        suite.expect(settingsHover.hoveredID == nil && settingsHover.dwell == nil,
                     "the Settings clipboard mockup does not acquire a hover preview target")

        let focus = HoverFocus()
        focus.setClipboardPagePointerInside(false)
        suite.expect(focus.panel?.claims == 0 && focus.resignations == 0,
                     "an unopened clipboard hover region leaves the active application's keyboard alone")
        focus.setClipboardPagePointerInside(true)
        focus.setClipboardPagePointerInside(true)
        suite.expect(focus.panel?.claims == 1 && focus.panel?.isKeyWindow == true && focus.clipboardHoverHasKey,
                     "entering the hover-opened clipboard page gives real keys to its local monitor once")
        focus.setClipboardPagePointerInside(false)
        suite.expect(focus.resignations == 1 && focus.panel?.isKeyWindow == false && !focus.clipboardHoverHasKey,
                     "leaving the clipboard cards immediately returns borrowed keyboard focus before delayed collapse")
        focus.setClipboardPagePointerInside(true)
        focus.panel?.isKeyWindow = false
        focus.setClipboardPagePointerInside(false)
        suite.expect(focus.resignations == 1 && !focus.clipboardHoverHasKey,
                     "a clipboard page disappearing behind its popup leaves the popup's keyboard focus alone")
        let clickedFocus = HoverFocus()
        clickedFocus.setClipboardPagePointerInside(true)
        clickedFocus.clickedSinceOpening = true
        clickedFocus.setClipboardPagePointerInside(false)
        suite.expect(clickedFocus.panel?.isKeyWindow == true && clickedFocus.resignations == 0,
                     "a click makes the clipboard's focus explicit, so pointer movement does not interrupt typing")
        let alreadyFocused = HoverFocus()
        alreadyFocused.panel?.isKeyWindow = true
        alreadyFocused.setClipboardPagePointerInside(true)
        alreadyFocused.setClipboardPagePointerInside(false)
        suite.expect(alreadyFocused.panel?.claims == 0 && alreadyFocused.resignations == 0,
                     "clipboard hover does not borrow or release focus the island already owns")
        let excluded: [(HoverFocus) -> Void] = [
            { $0.openedByHover = false }, { $0.expanded = false }, { $0.selected = .controls },
            { $0.showingAppPanel = true }, { $0.showingSections = true }, { $0.showingCommandBar = true },
            { $0.selectedMetric = 1 }, { $0.captureControls = 1 }, { $0.panel = nil }
        ]
        for change in excluded {
            let other = HoverFocus()
            change(other)
            other.setClipboardPagePointerInside(true)
            suite.expect(!other.clipboardHoverHasKey && (other.panel?.claims ?? 0) == 0,
                         "hover focus is limited to the clipboard page, outside details, capture controls and explicit openings")
        }

        let attached = HoverFocus()
        let popup = HoverFocus.Panel()
        var closed = 0
        let scheduledClose = DispatchWorkItem {}
        attached.hoverWork = scheduledClose
        suite.expect(attached.attachClipboardPreview(popup, close: {
            closed += 1
            attached.detachClipboardPreview(popup)
        }) && popup.parent === attached.panel && attached.panel?.children.count == 1
                     && attached.clipboardPreviewWindow === popup && scheduledClose.isCancelled,
                     "the enlarged clipboard preview attaches above its island and cancels a pending hover dismissal")
        attached.setClipboardPagePointerInside(true)
        suite.expect(attached.panel?.claims == 0,
                     "moving back over the island leaves keyboard focus with its attached preview")
        suite.expect(attached.attachClipboardPreview(popup, close: {
            closed += 1
            attached.detachClipboardPreview(popup)
        }) && attached.panel?.children.count == 1 && closed == 0,
                     "showing the same clipboard preview again keeps a single child window")
        attached.windowHost?.pointerInside = true
        attached.detachClipboardPreview(popup)
        suite.expect(popup.parent == nil && attached.panel?.children.isEmpty == true
                     && attached.clipboardPreviewClose == nil && attached.panel?.claims == 1 && closed == 0,
                     "closing an attached preview returns focus to the expanded clipboard page and clears its ownership")
        suite.expect(attached.clipboardHoverHasKey,
                     "returning preview focus to a hover-opened island rearms its pointer-limited keyboard ownership")
        attached.setClipboardPagePointerInside(false)
        suite.expect(attached.resignations == 1 && attached.panel?.isKeyWindow == false && !attached.clipboardHoverHasKey,
                     "leaving the island after closing its preview immediately returns borrowed keyboard focus")
        _ = attached.attachClipboardPreview(popup) {
            closed += 1
            attached.detachClipboardPreview(popup)
        }
        attached.closeClipboardPreview()
        suite.expect(closed == 1 && popup.parent == nil && attached.clipboardPreviewWindow == nil
                     && attached.panel?.claims == 1,
                     "dismissing the island closes its child once without reentrant detach restoring the keyboard")
        let replacement = HoverFocus.Panel()
        _ = attached.attachClipboardPreview(popup) {
            closed += 1
            attached.detachClipboardPreview(popup)
        }
        _ = attached.attachClipboardPreview(replacement) {}
        suite.expect(closed == 2 && popup.parent == nil && replacement.parent === attached.panel
                     && attached.panel?.children.count == 1,
                     "another clipboard preview replaces the previous child without leaving an orphan")
        attached.closeClipboardPreview()
        let departed = HoverFocus()
        let departedPopup = HoverFocus.Panel()
        _ = departed.attachClipboardPreview(departedPopup, close: {})
        departed.detachClipboardPreview(departedPopup)
        suite.expect(departed.panel?.claims == 0 && departed.resignations == 1 && departed.hoverExits == 1,
                     "closing a hover preview below the island returns keys to the previous app and resumes hover dismissal")
        let explicit = HoverFocus()
        explicit.openedByHover = false
        explicit.resumeClipboardAfterPreview(pointerInside: false)
        suite.expect(explicit.panel?.claims == 1 && explicit.resignations == 0 && explicit.hoverExits == 0,
                     "closing a keyboard-opened preview returns navigation to the island even with the pointer elsewhere")
        let clicked = HoverFocus()
        clicked.clickedSinceOpening = true
        clicked.resumeClipboardAfterPreview(pointerInside: false)
        suite.expect(clicked.panel?.claims == 1 && clicked.resignations == 0,
                     "a clipboard page explicitly clicked keeps its keyboard after preview dismissal")
        for change in excluded {
            let other = HoverFocus()
            change(other)
            // An explicitly opened clipboard page can own a preview too.
            if !other.openedByHover { continue }
            suite.expect(!other.attachClipboardPreview(HoverFocus.Panel(), close: {}),
                         "a closed island or another surface cannot adopt a clipboard popup")
        }

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
            suite.expect(page.dwell == nil && page.hoveredID == first.id && page.expandedID == nil,
                         "the clipboard page reads \"\(stored)\" as comfortable entries, tracking previews without hover expansion")
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
