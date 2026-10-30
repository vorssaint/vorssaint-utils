// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The history as a vertical list of cards, with everything the panel's list
/// and the quick panel offer on each: paste or copy, pin, move, delete, and
/// the recent ones cleared in one go from the island's top row.
struct NotchClipboardView: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.clipboardHistoryEnabled) private var enabled = false
    @State private var query = ""
    @State private var copiedID: UUID?
    private var pinnedOnly: Bool {
        get { service.clipboardPinnedOnly }
        nonmutating set { service.clipboardPinnedOnly = newValue }
    }
    /// The card the arrow keys chose, the top result of a typed search, or
    /// the entry copied last; Return uses it the way a click would.
    @State private var highlightedID: UUID?
    @FocusState private var searching: Bool
    /// The search field shows only once it is wanted: the header's magnifier
    /// opens it, and so does typing. Hidden, it keeps the focus.
    @State private var searchOpen = false
    @AppStorage(DefaultsKey.notchClipboardCardSize) private var cardSize = NotchClipboardCardSize.comfortable.rawValue
    /// The entry under the pointer, and the one it has rested on long enough to open.
    @State private var hoveredID: UUID?
    /// Filtering may move a new row under a stationary pointer. Typing keeps
    /// Space until the pointer actually moves again.
    @State private var searchPointerLocation: CGPoint?
    @State private var expandedID: UUID?
    /// The entry the pointer rests on until it opens, and the open entry the
    /// pointer left until it closes.
    @State private var dwell: (id: UUID, task: Task<Void, Never>)?
    @State private var closing: (id: UUID, task: Task<Void, Never>)?
    /// The entry the arrow keys have rested on long enough to open, once they have moved.
    @State private var keyExpandedID: UUID?
    @State private var keysMoved = false
    @Environment(\.notchSettingsPreview) private var preview
    @Environment(\.notchGlassSurface) private var glassSurface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(l10n.language) }
    private static let listSpace = "notch.clipboard.list"

    private var entries: [ClipboardHistoryEntry] {
        history.filteredEntries(matching: query).filter { !pinnedOnly || $0.isPinned }
    }

    /// Moving swaps neighbours in the list, which a search would misreport.
    private var canReorder: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var searchTokens: [String] {
        ClipboardHistorySearch.searchTokens(for: query)
    }

    /// The island draws its text in white and never in the accent color, so a
    /// match stands out by weight alone.
    private func searchText(_ string: String, matching tokens: [String]) -> Text {
        SearchHighlightText.text(string, tokens: tokens, fontSize: 12, highlightColor: nil)
    }

    var body: some View {
        VStack(spacing: searchOpen ? NotchLayout.rowSpacing : 0) {
            searchField
            if !enabled, history.entries.isEmpty {
                // The panel offers the switch beside its caption; the page
                // says why it is empty and turns the history on from here.
                VStack(spacing: 10) {
                    NotchEmptyView(symbol: "doc.on.clipboard", message: text.disabled)
                    Button(text.enable) {
                        enabled = true
                        history.syncWithPreferences()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .frame(maxHeight: .infinity)
            } else if entries.isEmpty {
                NotchEmptyView(symbol: pinnedOnly ? "pin" : "doc.on.clipboard",
                               message: query.isEmpty && !pinnedOnly ? text.empty : text.noResults)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: NotchLayout.clipboardCardSpacing) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                row(entry, place: index)
                                    .id(entry.id)
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                    .coordinateSpace(.named(Self.listSpace))
                    .onChange(of: highlightedID) { previous, id in
                        guard let id else { return }
                        follow(id, from: previous, in: proxy)
                    }
                    // A copied recent entry moves to the top, so the list
                    // follows it and the tick stays in view.
                    .onChange(of: copiedID) { _, id in
                        guard let id else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The magnifier and the history's own actions sit in the island's top
        // row, so the cards start at the top of the page.
        .notchBand(leading: {
            if !searchOpen {
                NotchIconButton(symbol: "magnifyingglass", title: text.search, action: service.requestClipboardSearch)
            }
        }, trailing: {
            HStack(spacing: 6) { NotchClipboardHeaderActions(service: service) }
        })
        .onChange(of: query) { _, query in queryChanged(query) }
        // Resting on an entry with the arrow keys opens it, as resting the pointer does.
        .task(id: highlightedID) {
            keyExpandedID = nil
            guard !preview, !comfortable, keysMoved, let id = highlightedID else { return }
            try? await Task.sleep(for: .seconds(NotchClipboardCardSize.keyDwell))
            guard !Task.isCancelled else { return }
            setOpen(keyID: id)
        }
        .background {
            if !preview {
                ClipboardKeyMonitor(handleKey: handleKey, composed: { searchOpen = true })
                    .frame(width: 0, height: 0)
            }
        }
        .onAppear(perform: appeared)
        .onChange(of: service.clipboardSearchRequest) { _, _ in if !preview { openSearch() } }
        .onChange(of: pinnedOnly) { _, _ in highlightedID = searchHighlight(keeping: nil) }
        .onChange(of: searchOpen) { _, open in
            guard !preview else { return }
            // Escape closes the search before it closes the island.
            service.setPageLayer(.clipboard, close: open ? { closeSearch() } : nil)
        }
        .onChange(of: searching) { _, focused in
            // A field left empty has nothing to keep open.
            if !focused, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { searchOpen = false }
        }
        .onDisappear {
            dwell?.task.cancel()
            closing?.task.cancel()
            hoveredID = nil
            if !preview {
                service.setClipboardPagePointerInside(false)
                service.setPageLayer(.clipboard, close: nil)
            }
        }
        // A row that leaves the list hands the highlight on, as a new search does.
        .onChange(of: entries.map(\.id)) { _, _ in highlightedID = searchHighlight(keeping: highlightedID) }
        .onChange(of: service.clipboardPastePress) { _, press in
            guard let press, !preview else { return }
            guard entries.indices.contains(press.index) else {
                NSSound.beep()
                return
            }
            activate(entries[press.index])
        }
        .task(id: copiedID) {
            // The tick confirms one copy; leaving it on the row forever would
            // read as a permanent state instead of an answer.
            guard copiedID != nil else { return }
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            copiedID = nil
        }
    }

    /// The page opens on the entry copied last, so Return pastes it and the
    /// arrows move from it. Typing filters it from the first key, as in
    /// Explore: the field takes the focus while it is still hidden.
    private func appeared() {
        guard !preview else { return }
        highlightedID = searchHighlight(keeping: nil)
        searching = true
    }

    /// The list follows the highlight the least that shows it whole. With no
    /// highlight before it, the list has just appeared at its top, as when the
    /// page opens, and the pinned entries above the highlight keep their room:
    /// the list stays there while half a compact entry's height of the
    /// highlighted one shows, a comfortable one's first line or a compact
    /// one's outline and top, and otherwise moves by whole entries, the
    /// fewest that show that much, so the entry at its top is never cut.
    private func follow(_ id: UUID, from previous: UUID?, in proxy: ScrollViewProxy) {
        var target = id, anchor: UnitPoint?
        if previous == nil {
            let list = size.height - (searchOpen ? NotchLayout.clipboardSearchHeight + NotchLayout.rowSpacing : 0)
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            let rows = NotchSupport.clipboardOpeningScroll(index: index, rowHeight: rowHeight,
                                                           spacing: NotchLayout.clipboardCardSpacing,
                                                           shown: NotchLayout.clipboardCompactCardHeight / 2,
                                                           visibleHeight: list)
            guard rows > 0 else { return }
            target = entries[rows].id
            anchor = .top
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(target, anchor: anchor) }
    }

    /// A new search starts from its top result instead of a row it hid. Text
    /// that reaches the hidden field, pasted into it too, shows it.
    private func queryChanged(_ query: String) {
        keysMoved = false
        // Typing takes ownership back from a pointer left over the list.
        hoveredID = nil
        searchPointerLocation = NSEvent.mouseLocation
        highlightedID = searchHighlight(keeping: nil)
        if !query.isEmpty { searchOpen = true }
    }

    /// The size Settings chose, read the way Settings reads it.
    private var comfortable: Bool {
        NotchClipboardCardSize(stored: cardSize) == .comfortable
    }

    /// The entry that is open, by the pointer or by the keys.
    private var openedID: UUID? { expandedID ?? keyExpandedID }

    /// A row keeps its height while its entry is open: the open entry is drawn
    /// over the rows around it, so none of them moves under a resting pointer.
    private var rowHeight: CGFloat {
        comfortable ? NotchLayout.clipboardCardHeight : NotchLayout.clipboardCompactCardHeight
    }

    private func row(_ entry: ClipboardHistoryEntry, place: Int) -> some View {
        let open = !comfortable && openedID == entry.id
        return card(entry) {
            if comfortable { expandedCard(entry, place: place) } else { compactCard(entry, place: place) }
        }
        .frame(height: rowHeight)
        .accessibilityHidden(open)
        .overlay(alignment: .top) {
            if open { openCard(entry, place: place) }
        }
        // One region for the row and the entry open over it, drawn above the rows it covers.
        .onContinuousHover { phase in
            switch phase {
            case .active: hover(entry, true)
            case .ended: hover(entry, false)
            }
        }
        .zIndex(open ? 1 : 0)
    }

    /// The open entry, from its row's top and moved only as far as it takes
    /// to show all of it within the list. It is lifted over the rows it
    /// covers and casts a soft shadow on them. Beneath it, a backing one
    /// point wider all around edges it the way a window lifted over others is
    /// edged, its corners following the card's own: it covers what those
    /// corners leave of a covered row, whose text starts 10 points in, where
    /// they still leave almost a point.
    private func openCard(_ entry: ClipboardHistoryEntry, place: Int) -> some View {
        GeometryReader { proxy in
            let visible = proxy.bounds(of: .named(Self.listSpace))?.height ?? size.height
            let height = min(openHeight(entry), visible)
            card(entry, lifted: true) { expandedCard(entry, place: place) }
                .frame(height: height)
                .background {
                    let backing = RoundedRectangle(cornerRadius: 14, style: .continuous).inset(by: -1)
                    Group {
                        if glassSurface { backing.fill(.ultraThickMaterial) } else { backing.fill(.black) }
                    }
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                }
                .offset(y: NotchSupport.clipboardOpenOffset(rowTop: proxy.frame(in: .named(Self.listSpace)).minY,
                                                            rowHeight: proxy.size.height,
                                                            height: height, visibleHeight: visible))
        }
    }

    /// An open entry is as tall as its text or image asks.
    private func openHeight(_ entry: ClipboardHistoryEntry) -> CGFloat {
        switch entry.kind {
        case .text:
            return max(NotchLayout.clipboardCompactCardHeight,
                       NotchClipboardCardSize.openHeight(text: openText(entry), width: openTextWidth(entry), id: entry.id))
        case .image:
            return NotchClipboardCardSize.openHeight(aspectRatio: entry.imageAspectRatio.map { CGFloat($0) },
                                                     width: size.width - 40)
        case .files:
            return NotchLayout.clipboardCardHeight
        }
    }

    /// The width an open entry's text wraps in: the card less its padding and
    /// any color swatch, and less a scroll bar where one takes room.
    private func openTextWidth(_ entry: ClipboardHistoryEntry) -> CGFloat {
        let scroller = NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
        return size.width - 2 * 10 - (entry.color == nil ? 0 : 12 + 7) - scroller
    }

    /// The text an open entry shows: the card preview the quick panel's cards
    /// show, its line breaks kept and blank lines around it trimmed, and no
    /// more than a few lines of it.
    private func openText(_ entry: ClipboardHistoryEntry) -> String {
        String(entry.cardPreview.prefix(NotchClipboardCardSize.maximumOpenLines * 120))
    }

    private func setOpen(keyID: UUID?) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { keyExpandedID = keyID }
    }

    /// A compact entry opens once the pointer has rested on it and closes a
    /// moment after the pointer leaves it. Only coming back to that entry
    /// keeps it open; resting on another one or leaving the list closes it.
    private func hover(_ entry: ClipboardHistoryEntry, _ inside: Bool, at point: CGPoint = NSEvent.mouseLocation) {
        guard !preview else { return }
        if inside {
            guard searchPointerLocation != point else { return }
            searchPointerLocation = nil
            guard hoveredID != entry.id else { return }
            hoveredID = entry.id
        }
        else if hoveredID == entry.id { hoveredID = nil }
        // Both card sizes track the preview target; only compact cards expand.
        guard !comfortable else { return }
        if inside {
            if closing?.id == entry.id {
                closing?.task.cancel()
                closing = nil
            }
            dwell?.task.cancel()
            dwell = nil
            guard expandedID != entry.id else { return }
            dwell = (entry.id, Task { @MainActor in
                try? await Task.sleep(for: .seconds(NotchClipboardCardSize.dwell))
                guard !Task.isCancelled, hoveredID == entry.id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { expandedID = entry.id }
            })
        } else {
            if dwell?.id == entry.id {
                dwell?.task.cancel()
                dwell = nil
            }
            guard expandedID == entry.id else { return }
            closing?.task.cancel()
            closing = (entry.id, Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, expandedID == entry.id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { expandedID = nil }
            })
        }
    }

    /// The icon of the app the entry was copied from, or the kind of entry when that is unknown.
    @ViewBuilder private func sourceBadge(_ entry: ClipboardHistoryEntry) -> some View {
        if let id = entry.sourceBundleID, let app = ClipboardSourceApps.app(for: id) {
            Image(nsImage: app.icon)
                .resizable().interpolation(.high)
                .frame(width: 14, height: 14)
                .help(app.name)
                .accessibilityLabel(app.name)
        } else {
            Image(systemName: kindSymbol(entry))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func kindSymbol(_ entry: ClipboardHistoryEntry) -> String {
        entry.kind == .image ? "photo" : entry.kind == .files ? "doc" : "text.alignleft"
    }

    /// The surface an entry sits on, with its menu and actions. An open entry
    /// is lifted over the rows around it, which must not show through it: an
    /// opaque surface a step lighter than theirs and edged by a hairline, so
    /// the rows it covers read as underneath. On a frosted pane it lies on
    /// Liquid Glass instead, as an opaque gray would stand out of the glass.
    private func card<Content: View>(_ entry: ClipboardHistoryEntry, lifted: Bool = false,
                                     @ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return content()
            .modifier(NotchControlSurface(cornerRadius: 14, selected: entry.isPinned))
            .background {
                if lifted {
                    if glassSurface { shape.fill(.ultraThickMaterial) } else { shape.fill(Color(white: 0.09)) }
                }
            }
            .overlay {
                ZStack {
                    if lifted { shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.5) }
                    shape.strokeBorder(.white.opacity(highlightedID == entry.id ? 0.34 : 0), lineWidth: 1)
                }
                .allowsHitTesting(false)
            }
            .clipped()
            .contextMenu { actions(entry) }
            .accessibilityAction(named: Text(text.previewLabel)) { history.previewEntry(entry) }
            .accessibilityAction(named: Text(text.moveUp)) { move(entry, .up) }
            .accessibilityAction(named: Text(text.moveDown)) { move(entry, .down) }
    }

    /// One or two lines, with the actions shown only for the entry in use.
    private func compactCard(_ entry: ClipboardHistoryEntry, place: Int) -> some View {
        let active = hoveredID == entry.id || highlightedID == entry.id
        return HStack(spacing: 8) {
            Button { activate(entry) } label: {
                HStack(spacing: 8) {
                    leadingIcon(entry)
                    preview(entry, compact: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .clipped()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchButtonStyle(lifts: false))
            .help(permissions.accessibility ? text.clickRowShortcut : text.copy)
            if active {
                HStack(spacing: 2) {
                    if entry.kind == .image, AppFeature.screenshot.isAvailable {
                        NotchIconButton(symbol: "pencil", title: text.edit) { history.editImage(entry) }
                    }
                    NotchIconButton(symbol: copiedID == entry.id ? "checkmark" : "doc.on.doc",
                                    title: copiedID == entry.id ? text.copied : text.copy) { copy(entry) }
                    NotchIconButton(symbol: entry.isPinned ? "pin.fill" : "pin",
                                    title: entry.isPinned ? text.unpin : text.pin) { history.togglePin(entry) }
                    NotchIconButton(symbol: "trash", title: text.delete) { remove(entry) }
                }
            } else {
                HStack(spacing: 6) {
                    if entry.isPinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                    if place < 9, service.panelIsKey {
                        Text("⌘\(place + 1)").font(.system(size: 9.5, weight: .medium)).monospacedDigit()
                            .foregroundStyle(.tertiary).accessibilityHidden(true)
                    }
                    Text(entry.copiedAt, style: .time).font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    /// What a compact row leads with: the files' own icon, the one Finder
    /// shows for their type, or the glyph of the kind of entry. All of them
    /// take one column, so the rows' text lines up.
    private func leadingIcon(_ entry: ClipboardHistoryEntry) -> some View {
        Group {
            if entry.kind == .files, let icon = ClipboardFileIcons.icon(for: entry.filePaths) {
                // VoiceOver reads the name beside it, which says all the icon does.
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 14, height: 14)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: kindSymbol(entry)).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 14)
    }

    /// The whole entry, with its actions in the bottom row.
    private func expandedCard(_ entry: ClipboardHistoryEntry, place: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { activate(entry) } label: {
                preview(entry, compact: false, open: !comfortable)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .contentShape(Rectangle())
            }
            .buttonStyle(NotchButtonStyle(lifts: false))
            .help(permissions.accessibility ? text.clickRowShortcut : text.copy)
            HStack(spacing: 5) {
                sourceBadge(entry)
                Text(entry.copiedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .environment(\.locale, l10n.language.formattingLocale())
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
                Spacer(minLength: 0)
                if place < 9, service.panelIsKey {
                    Text("⌘\(place + 1)")
                        .font(.system(size: 9.5, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if entry.kind == .image, AppFeature.screenshot.isAvailable {
                    NotchIconButton(symbol: "pencil", title: text.edit) { history.editImage(entry) }
                }
                NotchIconButton(symbol: copiedID == entry.id ? "checkmark" : "doc.on.doc",
                                title: copiedID == entry.id ? text.copied : text.copy) { copy(entry) }
                NotchIconButton(symbol: entry.isPinned ? "pin.fill" : "pin",
                                title: entry.isPinned ? text.unpin : text.pin) {
                    history.togglePin(entry)
                }
                NotchIconButton(symbol: "trash", title: text.delete) { remove(entry) }
            }
            .frame(height: 28)
        }
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
    }

    /// The quick panel's row menu: paste when the app may type, copy, preview, pin,
    /// move within the list and delete.
    @ViewBuilder private func actions(_ entry: ClipboardHistoryEntry) -> some View {
        if permissions.accessibility {
            Button(l10n.s.menuPaste) { paste(entry) }
        }
        Button(text.copy) { copy(entry) }
        Button(text.previewLabel) { history.previewEntry(entry) }
        Divider()
        Button(entry.isPinned ? text.unpin : text.pin) { history.togglePin(entry) }
        Button(text.moveUp) { move(entry, .up) }
            .disabled(!canReorder || !history.canMove(entry, .up))
        Button(text.moveDown) { move(entry, .down) }
            .disabled(!canReorder || !history.canMove(entry, .down))
        Divider()
        Button(text.delete, role: .destructive) { remove(entry) }
    }

    /// The highlighted row, or with no search the entry copied last.
    private func searchHighlight(keeping current: UUID?) -> UUID? {
        NotchSupport.searchHighlight(keeping: current, in: entries.map(\.id), query: query)
            ?? NotchSupport.restingClipboardHighlight(entries.map { ($0.id, $0.isPinned) })
    }

    /// The search field stays mounted and focused while it is hidden, so its
    /// editor and any input method get every key from the first one. The
    /// magnifier or typing shows it; until then the entries keep its room.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(text.search, text: $query).textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searching)
                .accessibilityLabel(text.search)
        }
        .padding(.horizontal, 12)
        .frame(height: NotchLayout.clipboardSearchHeight)
        .modifier(NotchControlSurface(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(searching ? 0.34 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.15), value: searching)
        .frame(height: searchOpen ? NotchLayout.clipboardSearchHeight : 0, alignment: .top)
        .opacity(searchOpen ? 1 : 0)
        .clipped()
        .allowsHitTesting(searchOpen)
        .accessibilityHidden(!searchOpen)
    }

    private func openSearch() {
        searchOpen = true
        searching = true
    }

    /// Closing empties the search and hides the field, which keeps the focus
    /// so the next key typed starts a new one.
    private func closeSearch() {
        query = ""
        searchOpen = false
        searching = true
    }

    /// Up/Control-P and Down/Control-N move the highlight, Return pastes or
    /// copies it, and Space previews the hovered entry or keyboard highlight.
    /// A visible search keeps its spaces until the pointer or navigation moves
    /// into the list. A typed letter shows the field and goes on to it.
    private func handleKey(_ event: NSEvent, composing: Bool, editing: Bool) -> Bool {
        // Control produces control characters; match its shortcuts by the
        // layout's letter, while ordinary typing keeps the original text.
        let characters = event.modifierFlags.contains(.control) ? event.charactersIgnoringModifiers : event.characters
        let ids = entries.map(\.id)
        let hovered = hoveredID.flatMap { ids.contains($0) ? $0 : nil }
        guard let key = NotchSupport.clipboardKey(keyCode: event.keyCode, characters: characters ?? "",
                                                  modifiers: event.modifierFlags, composing: composing,
                                                  previewOnSpace: !searchOpen || keysMoved || hovered != nil) else { return false }
        switch key {
        case .move(let backwards):
            guard !ids.isEmpty else { return false }
            keysMoved = true
            highlightedID = NotchSupport.steppedItem(from: highlightedID, in: ids, backwards: backwards)
            return true
        case .paste:
            guard let id = NotchSupport.clipboardPasteTarget(highlighted: highlightedID, in: ids),
                  let entry = entries.first(where: { $0.id == id }) else { return false }
            activate(entry)
            return true
        case .preview:
            guard !event.isARepeat else { return true }
            guard let id = hovered ?? NotchSupport.clipboardPasteTarget(highlighted: highlightedID, in: ids),
                  let entry = entries.first(where: { $0.id == id }) else { return false }
            history.previewEntry(entry)
            return true
        case .reveal:
            searchOpen = true
            // The focus Tab took elsewhere comes back for the keys that follow.
            if !editing { searching = true }
            return false
        }
    }

    private func activate(_ entry: ClipboardHistoryEntry) {
        if permissions.accessibility { paste(entry) } else { copy(entry) }
    }

    private func paste(_ entry: ClipboardHistoryEntry) {
        service.collapse()
        history.copyQuickEntry(entry)
    }

    private func copy(_ entry: ClipboardHistoryEntry) {
        // A copied recent entry moves to the top, so the second click of a
        // double click would copy whichever entry took its place.
        if let event = NSApp.currentEvent, [.leftMouseDown, .leftMouseUp].contains(event.type),
           event.clickCount > 1 { return }
        history.copy(entry) { copied in
            if copied {
                copiedID = entry.id
            } else {
                NSSound.beep()
            }
        }
    }

    private func move(_ entry: ClipboardHistoryEntry, _ direction: ClipboardHistoryMoveDirection) {
        guard canReorder, history.canMove(entry, direction) else { return }
        history.move(entry, direction)
    }

    private func remove(_ entry: ClipboardHistoryEntry) {
        if copiedID == entry.id { copiedID = nil }
        history.remove(entry)
    }

    /// A picture rounded at its own edges, then placed in the room it may
    /// take. Rounding that room instead would leave square corners wherever
    /// the picture is narrower than it.
    private func thumbnail<Picture: View>(_ picture: Picture, compact: Bool) -> some View {
        picture
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: compact ? 72 : .infinity, maxHeight: .infinity, alignment: compact ? .leading : .topLeading)
    }

    @ViewBuilder private func preview(_ entry: ClipboardHistoryEntry, compact: Bool, open: Bool = false) -> some View {
        switch entry.kind {
        case .image:
            if let name = entry.imageFile {
                thumbnail(ClipboardThumbnailImage(source: .stored(name: name),
                                                  aspectRatio: entry.imageAspectRatio,
                                                  failureText: "\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)"),
                          compact: compact)
                    .help("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
            } else {
                searchText("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)", matching: searchTokens)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .files:
            // One image file shows itself; anything else reads as its name
            // or its count, the way the panel lists files.
            if entry.filePaths.count == 1, let path = entry.filePaths.first,
               ClipboardImageStore.isImageFile(atPath: path) {
                thumbnail(ClipboardThumbnailImage(source: .file(path: path),
                                                  failureText: entry.fileNames.first ?? entry.preview),
                          compact: compact)
                    .help(path)
            } else {
                // A count of several files is no text the search reads.
                let name = searchText(entry.filePaths.count == 1
                                          ? (entry.fileNames.first ?? entry.preview)
                                          : String(format: text.fileCountFormat, entry.filePaths.count),
                                      matching: entry.filePaths.count == 1 ? searchTokens : [])
                // A compact row leads with the files' own icon already, and
                // opened it keeps that icon rather than becoming a folder.
                Group {
                    if compact {
                        name
                    } else {
                        Label { name } icon: { if open { leadingIcon(entry) } else { Image(systemName: "folder") } }
                    }
                }
                .font(.system(size: 12))
                .lineLimit(compact ? 1 : 2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .help(entry.filePaths.joined(separator: "\n"))
            }
        case .text:
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if let color = entry.color {
                    ColorSwatch(color: color, size: 12)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                }
                searchText(open ? openText(entry) : entry.preview, matching: searchTokens)
                    .font(.system(size: 12))
                    .lineLimit(compact ? 2 : open ? NotchClipboardCardSize.maximumOpenLines : 3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// Reads arrows, Control-P/N, Return and preview Space before the search field's editor,
/// which would otherwise spend them moving the caret, and shows the hidden
/// field as typing reaches it. It lives as long as the page does.
private struct ClipboardKeyMonitor: NSViewRepresentable {
    var handleKey: (NSEvent, Bool, Bool) -> Bool
    /// A dead key or an input method's first key marks text in the field.
    var composed: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handleKey = handleKey
        context.coordinator.composed = composed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(handleKey: handleKey, composed: composed)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var handleKey: (NSEvent, Bool, Bool) -> Bool
        var composed: () -> Void
        private var monitor: Any?

        init(handleKey: @escaping (NSEvent, Bool, Bool) -> Bool,
             composed: @escaping () -> Void) {
            self.handleKey = handleKey
            self.composed = composed
        }

        func install(for view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak view] event in
                guard let self, let window = view?.window, event.window === window else { return event }
                let editor = (window.firstResponder as? NSTextView).flatMap { $0.isFieldEditor ? $0 : nil }
                // Another text view, such as a dialog's, keeps its keys.
                if editor == nil, window.firstResponder is NSTextView { return event }
                let composing = editor?.hasMarkedText() == true
                if self.handleKey(event, composing, editor != nil) {
                    return nil
                }
                // A dead key reports no character and marks its accent only
                // once the editor has it, so the field shows then.
                if let editor, !composing {
                    DispatchQueue.main.async { [weak self, weak editor] in
                        if editor?.hasMarkedText() == true { self?.composed() }
                    }
                }
                return event
            }
        }

        func removeMonitor() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

/// Name and icon of the apps entries were copied from, looked up once each. An
/// app removed since the copy has nothing to show; a miss is not kept, so an app
/// installed later shows up without a restart.
@MainActor
private enum ClipboardSourceApps {
    struct App { let name: String; let icon: NSImage }
    private static var cache: [String: App] = [:]

    static func app(for bundleID: String) -> App? {
        if let cached = cache[bundleID] { return cached }
        guard let url = InstalledApps.url(for: bundleID) else { return nil }
        let app = App(name: InstalledApps.name(for: bundleID), icon: NSWorkspace.shared.icon(forFile: url.path))
        cache[bundleID] = app
        return app
    }
}

/// The icon Finder shows for an entry's files, looked up once per set of
/// paths: the page draws its rows again whenever the pointer moves between them.
@MainActor
private enum ClipboardFileIcons {
    private static var cache: [[String]: NSImage] = [:]

    static func icon(for paths: [String]) -> NSImage? {
        if let cached = cache[paths] { return cached }
        guard let icon = NSWorkspace.shared.icon(forFiles: paths) else { return nil }
        // Entries come and go over days; a full cache starts again.
        if cache.count >= 256 { cache.removeAll() }
        cache[paths] = icon
        return icon
    }
}

/// The filter, the clearing of recent entries and the history window, at the
/// trailing end of the island's top row.
struct NotchClipboardHeaderActions: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(l10n.language) }

    var body: some View {
        // A filter's glyph: the row's pin keeps the island open.
        NotchIconButton(symbol: service.clipboardPinnedOnly ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle",
                        title: text.pinned, selected: service.clipboardPinnedOnly) {
            service.clipboardPinnedOnly.toggle()
        }
        NotchIconButton(symbol: "trash", title: text.clearRecent, action: Self.confirmClearRecent)
            .disabled(history.recentEntries.isEmpty)
        NotchIconButton(symbol: "arrow.up.forward.app", title: text.title) {
            service.perform { history.showHistoryWindow(preferNotch: false) }
        }
    }

    /// Clearing the recent entries asks first, above the island.
    static func confirmClearRecent() {
        let history = ClipboardHistoryService.shared
        let text = FeatureStrings.clipboard(L10n.shared.language)
        let ids = history.recentEntriesSnapshot
        guard !ids.isEmpty else { return }
        DispatchQueue.main.async {
            guard NSAlert.confirmAboveIsland(String(format: text.clearRecentConfirmFormat, ids.count),
                                             message: text.clearRecentConfirmMessage,
                                             action: text.clearRecent, destructive: true,
                                             cancel: text.cancel) else { return }
            history.clearRecent(ids)
        }
    }
}
