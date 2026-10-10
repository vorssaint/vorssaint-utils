// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The history as a vertical list of cards, with everything the panel's list
/// and the quick panel offer on each: paste or copy, pin, move, delete, and
/// the recent ones cleared in one go from the search row.
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
    /// The card the arrow keys chose from the search field, or the top result
    /// of a typed search; Return uses it the way a click would.
    @State private var highlightedID: UUID?
    @FocusState private var searching: Bool
    /// The search field shows only once it is wanted: the magnifier opens it,
    /// pointing at the magnifier opens it, and so does typing a letter.
    @State private var searchOpen = false
    @AppStorage(DefaultsKey.notchClipboardCardSize) private var cardSize = NotchClipboardCardSize.compact.rawValue
    /// The entry under the pointer, and the one it has rested on long enough to open.
    @State private var hoveredID: UUID?
    @State private var expandedID: UUID?
    @State private var dwellTask: Task<Void, Never>?
    @State private var collapseTask: Task<Void, Never>?
    /// The entry the arrow keys have rested on long enough to open, once they have moved.
    @State private var keyExpandedID: UUID?
    @State private var keysMoved = false
    @Environment(\.notchSettingsPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(l10n.language) }

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
        VStack(spacing: NotchLayout.rowSpacing) {
            header
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
                        LazyVStack(spacing: 8) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                card(entry, place: index)
                                    .frame(height: cardHeight(entry))
                                    .onHover { hover(entry, $0) }
                                    .id(entry.id)
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                    // An entry that opens may reach past the edge of the list.
                    .onChange(of: openedID) { _, id in
                        guard let id else { return }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            guard openedID == id else { return }
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                        }
                    }
                    .onChange(of: highlightedID) { _, id in
                        guard let id else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id) }
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
        // A new search starts from its top result instead of a row it hid,
        // and a row that leaves the list hands the highlight on the same way.
        .onChange(of: query) { _, _ in keysMoved = false; highlightedID = searchHighlight(keeping: nil) }
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
                ClipboardKeyMonitor { handleKey(keyCode: $0, characters: $1, hasCommandModifier: $2, editing: $3) }
                    .frame(width: 0, height: 0)
            }
        }
        // The page opens on the entry copied last, so Return pastes it
        // and the arrows move from it.
        .onAppear { if !preview { highlightedID = searchHighlight(keeping: nil) } }
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
        .onDisappear { if !preview { service.setPageLayer(.clipboard, close: nil) } }
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

    private var comfortable: Bool { cardSize == NotchClipboardCardSize.comfortable.rawValue }

    private func isExpanded(_ entry: ClipboardHistoryEntry) -> Bool {
        comfortable || expandedID == entry.id || keyExpandedID == entry.id
    }

    /// The entry that is open, by the pointer or by the keys.
    private var openedID: UUID? { expandedID ?? keyExpandedID }

    /// A comfortable entry is always the same height; a compact one is short until it opens
    /// and then as tall as its text or image asks.
    private func cardHeight(_ entry: ClipboardHistoryEntry) -> CGFloat {
        if comfortable { return NotchLayout.clipboardCardHeight }
        guard isExpanded(entry) else { return NotchLayout.clipboardCompactCardHeight }
        let width = size.width - 40
        switch entry.kind {
        case .text:
            return max(NotchLayout.clipboardCompactCardHeight, NotchClipboardCardSize.openHeight(text: openText(entry), width: width))
        case .image:
            return NotchClipboardCardSize.openHeight(aspectRatio: entry.imageAspectRatio.map { CGFloat($0) }, width: width)
        case .files:
            return NotchLayout.clipboardCardHeight
        }
    }

    /// The text an open entry shows: its own line breaks, and no more than a few lines of it.
    private func openText(_ entry: ClipboardHistoryEntry) -> String {
        String(entry.text.prefix(NotchClipboardCardSize.maximumOpenLines * 120))
    }

    private func setOpen(keyID: UUID?) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { keyExpandedID = keyID }
    }

    /// A compact entry opens once the pointer has rested on it. Leaving closes it after a
    /// moment, so the pointer crossing the card as it changes shape does not close it.
    private func hover(_ entry: ClipboardHistoryEntry, _ inside: Bool) {
        guard !preview, !comfortable else { return }
        if inside {
            collapseTask?.cancel()
            dwellTask?.cancel()
            hoveredID = entry.id
            guard expandedID != entry.id else { return }
            dwellTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(NotchClipboardCardSize.dwell))
                guard !Task.isCancelled, hoveredID == entry.id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { expandedID = entry.id }
            }
        } else {
            dwellTask?.cancel()
            collapseTask?.cancel()
            collapseTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                if hoveredID == entry.id { hoveredID = nil }
                if expandedID == entry.id {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { expandedID = nil }
                }
            }
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

    private func card(_ entry: ClipboardHistoryEntry, place: Int) -> some View {
        Group {
            if isExpanded(entry) { expandedCard(entry, place: place) } else { compactCard(entry, place: place) }
        }
        .modifier(NotchControlSurface(cornerRadius: 14, selected: entry.isPinned))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(highlightedID == entry.id ? 0.34 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .clipped()
        .contextMenu { actions(entry) }
        .accessibilityAction(named: Text(text.moveUp)) { move(entry, .up) }
        .accessibilityAction(named: Text(text.moveDown)) { move(entry, .down) }
    }

    /// One or two lines, with the actions shown only for the entry in use.
    private func compactCard(_ entry: ClipboardHistoryEntry, place: Int) -> some View {
        let active = hoveredID == entry.id || highlightedID == entry.id
        return HStack(spacing: 8) {
            Button { activate(entry) } label: {
                HStack(spacing: 8) {
                    Image(systemName: kindSymbol(entry)).font(.system(size: 10)).foregroundStyle(.secondary)
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

    /// The quick panel's row menu: paste when the app may type, copy, pin,
    /// move within the list and delete.
    @ViewBuilder private func actions(_ entry: ClipboardHistoryEntry) -> some View {
        if permissions.accessibility {
            Button(l10n.s.menuPaste) { paste(entry) }
        }
        Button(text.copy) { copy(entry) }
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

    /// The search field, once the header's magnifier or a typed letter opens
    /// it; until then the page keeps all its room for the entries.
    @ViewBuilder private var header: some View {
        if searchOpen {
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
        }
    }

    private func openSearch() {
        searchOpen = true
        // The field exists on the next pass, and only then can it take focus.
        DispatchQueue.main.async { searching = true }
    }

    private func closeSearch() {
        query = ""
        searching = false
        searchOpen = false
    }

    /// Up and Down move the highlight and Return pastes or copies it like a
    /// click, with or without the search field focused. A letter opens the
    /// search and starts it.
    private func handleKey(keyCode: UInt16, characters: String, hasCommandModifier: Bool, editing: Bool) -> Bool {
        guard let key = NotchSupport.clipboardKey(keyCode: keyCode, characters: characters,
                                                  hasCommandModifier: hasCommandModifier, editing: editing) else { return false }
        let ids = entries.map(\.id)
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
        case .type(let typed):
            query += typed
            openSearch()
            return true
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

    @ViewBuilder private func preview(_ entry: ClipboardHistoryEntry, compact: Bool, open: Bool = false) -> some View {
        switch entry.kind {
        case .image:
            if let name = entry.imageFile {
                ClipboardThumbnailImage(source: .stored(name: name),
                                        aspectRatio: entry.imageAspectRatio,
                                        failureText: "\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
                    .frame(maxWidth: compact ? 72 : .infinity, maxHeight: .infinity, alignment: compact ? .leading : .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
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
                ClipboardThumbnailImage(source: .file(path: path),
                                        failureText: entry.fileNames.first ?? entry.preview)
                    .frame(maxWidth: compact ? 72 : .infinity, maxHeight: .infinity, alignment: compact ? .leading : .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .help(path)
            } else {
                // A count of several files is no text the search reads.
                Label {
                    searchText(entry.filePaths.count == 1
                                   ? (entry.fileNames.first ?? entry.preview)
                                   : String(format: text.fileCountFormat, entry.filePaths.count),
                               matching: entry.filePaths.count == 1 ? searchTokens : [])
                } icon: {
                    Image(systemName: "folder")
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

/// Reads the arrow keys and Return before the search field's editor does,
/// which would otherwise spend them moving the caret, and the letters typed
/// while the field is closed. It lives as long as the page does.
private struct ClipboardKeyMonitor: NSViewRepresentable {
    var handleKey: (UInt16, String, Bool, Bool) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handleKey = handleKey
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(handleKey: handleKey)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var handleKey: (UInt16, String, Bool, Bool) -> Bool
        private var monitor: Any?

        init(handleKey: @escaping (UInt16, String, Bool, Bool) -> Bool) {
            self.handleKey = handleKey
        }

        func install(for view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak view] event in
                guard let self, let window = view?.window, event.window === window else { return event }
                let editor = (window.firstResponder as? NSTextView).flatMap { $0.isFieldEditor ? $0 : nil }
                // A word being composed keeps its keys.
                guard editor?.hasMarkedText() != true else { return event }
                // Another text view, such as a dialog's, keeps its keys too.
                if editor == nil, window.firstResponder is NSTextView { return event }
                let held = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
                return self.handleKey(event.keyCode, event.characters ?? "", held, editor != nil) ? nil : event
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

/// The filter, the clearing of recent entries and the history window, which
/// sit in the island's header beside its other actions.
struct NotchClipboardHeaderActions: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(l10n.language) }

    var body: some View {
        NotchIconButton(symbol: "pin", title: text.pinned, selected: service.clipboardPinnedOnly) {
            service.clipboardPinnedOnly.toggle()
        }
        NotchIconButton(symbol: "trash", title: text.clearRecent) {
            let ids = history.recentEntriesSnapshot
            DispatchQueue.main.async {
                guard NSAlert.confirmAboveIsland(String(format: text.clearRecentConfirmFormat, ids.count),
                                                 message: text.clearRecentConfirmMessage,
                                                 action: text.clearRecent, destructive: true,
                                                 cancel: text.cancel) else { return }
                history.clearRecent(ids)
            }
        }
        .disabled(history.recentEntries.isEmpty)
        NotchIconButton(symbol: "arrow.up.forward.app", title: text.title) {
            service.perform { history.showHistoryWindow(preferNotch: false) }
        }
    }
}
