// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The command bar's face: one field, one list. Reads top to bottom with no
/// chrome to learn; every row is icon, name in plain words, where it lives,
/// and its shortcut so the bar teaches the faster way while being used.
struct CommandBarView: View {
    /// Short enough to sit on one line, chosen to show three different things
    /// the bar can do that a list of commands would never reveal.
    static var examples: [String] {
        ["100 km to mi", "2+2*3", "battery", "fire"].filter {
            $0 != "battery" || PowerSampler.hasInternalBattery
        }
    }
    /// As tall as the list is ever allowed to be, so the panel never grows
    /// past what a laptop screen can show above the fold.
    static let listCeiling: CGFloat = 452
    private static let homeChipID = "category.all"

    @ObservedObject private var service = CommandBarService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFocused: Bool

    /// The mark, made a handle. Dragging rides on AppKit's own window
    /// dragging — the same machinery a title bar uses — rather than a
    /// SwiftUI gesture, whose translation is read in a coordinate space
    /// that moves with the window and jitters under its own feet.
    private struct DragHandle: NSViewRepresentable {
        func makeNSView(context: Context) -> HandleView { HandleView() }
        func updateNSView(_ view: HandleView, context: Context) {}

        final class HandleView: NSView {
            private var moveObserver: NSObjectProtocol?
            private var saveTask: DispatchWorkItem?

            deinit {
                saveTask?.cancel()
                if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
            }

            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

            override func resetCursorRects() {
                // Cursor rects, not a pushed NSCursor: the system hands the
                // arrow back on its own the moment the pointer leaves, even
                // if the bar hides mid-hover.
                addCursorRect(bounds, cursor: .openHand)
            }

            override func mouseDown(with event: NSEvent) {
                if event.clickCount == 2 {
                    CommandBarService.shared.resetPanelPosition()
                    return
                }
                guard let window else { return }
                NSCursor.closedHand.set()
                observeMovement(of: window)
                window.performDrag(with: event)
                scheduleSave()
                NSCursor.openHand.set()
            }

            private func observeMovement(of window: NSWindow) {
                saveTask?.cancel()
                if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
                moveObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didMoveNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.scheduleSave()
                }
            }

            private func scheduleSave() {
                saveTask?.cancel()
                let task = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
                    moveObserver = nil
                    saveTask = nil
                    CommandBarService.shared.finishPanelDrag()
                }
                saveTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
            }
        }
    }

    private var markTint: Color {
        colorScheme == .light ? Color(white: 0.03) : .white
    }

    private var text: CommandBarFeatureStrings { FeatureStrings.commandBar(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            switch service.mode {
            case .search:
                if showsCategoryChips {
                    Divider()
                    categoryChipsRow
                }
                if service.rows.isEmpty {
                    // A category with nothing in it needs the same way out a
                    // fruitless search gets, or the panel is a room with no
                    // door in it.
                    if !trimmedQuery.isEmpty || service.activeCategory != nil {
                        Divider()
                        emptyState
                    }
                } else {
                    if !showsCategoryChips { Divider() }
                    resultsList
                }
            case .argument(let entryID):
                Divider()
                argumentCard(entryID: entryID)
            case .confirm(let entryID):
                Divider()
                confirmCard(entryID: entryID)
            case .actions:
                Divider()
                actionsList
            case .naming(let entryID):
                Divider()
                namingCard(entryID: entryID)
            case .capturingShortcut(let entryID):
                Divider()
                shortcutCard(entryID: entryID)
            }
            Divider()
            footer
        }
        .frame(width: 560)
        .background(HUDBackdrop(cornerRadius: 22, contrast: .high))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear { focusSearch() }
        .onChange(of: service.presentationID) { _, _ in focusSearch() }
        .onChange(of: service.mode) { _, _ in focusSearch() }
    }

    private func focusSearch() {
        DispatchQueue.main.async { searchFocused = true }
    }

    // MARK: - Field

    private var searchBar: some View {
        HStack(spacing: 10) {
            // The mark leads the field, the same face the quick panel and the
            // radial menu wear; modes speak through the chip and the cards.
            // Both axes are pinned: the panel re-fits on every keystroke and
            // a mark left to follow the proposed height shrinks or vanishes
            // mid-layout. It is also the handle that carries the bar to
            // wherever the hand wants it; a double-click brings it home.
            BrandMark(width: 22, tint: markTint)
                .opacity(0.85)
                .frame(width: 22, height: 22)
                .allowsHitTesting(false)
                .overlay(
                    DragHandle()
                        .help(text.dragHint)
                )
            if case .naming(let entryID) = service.mode,
               let entry = service.entry(withID: entryID) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            }
            if case .argument(let entryID) = service.mode,
               let entry = service.entry(withID: entryID) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            }
            TextField(fieldPlaceholder, text: $service.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
                .disableAutocorrection(true)
                .accessibilityLabel(text.pageTitle)
            if !service.query.isEmpty {
                Button {
                    service.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// Everything that can be done to the selected row, in the same list
    /// shape as the results so there is nothing new to learn.
    private var actionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text.actionsTitle.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 2)
            VStack(spacing: 1) {
                ForEach(Array(service.actionRows.enumerated()), id: \.element.id) { index, action in
                    Button {
                        service.runAction(action)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: action.symbolName)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(action.isDestructive
                                                 ? Color.red : Color.primary.opacity(0.85))
                                .frame(width: 30, height: 30)
                            Text(action.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(action.isDestructive ? Color.red : Color.primary)
                            Spacer(minLength: 12)
                            Image(systemName: "return")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .opacity(index == service.actionIndex ? 1 : 0)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(index == service.actionIndex
                                      ? (action.isDestructive
                                         ? Color.red.opacity(0.12)
                                         : Color.accentColor.opacity(0.14))
                                      : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    /// Naming a row: the field becomes the name, and says so when the name is
    /// already taken instead of quietly stealing it.
    private func namingCard(entryID: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let entry = service.entry(withID: entryID) {
                HStack(spacing: 10) {
                    iconView(entry)
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 17)
                .padding(.top, 12)
            }
            Text(service.aliasWarning ?? text.argumentHint)
                .font(.system(size: 10.5))
                .foregroundStyle(service.aliasWarning == nil
                                 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.orange))
                .padding(.horizontal, 17)
                .padding(.bottom, 12)
        }
    }

    /// Listening for the combination one row should answer to. The card says
    /// so plainly, because a field that silently swallows every key is the
    /// most confusing thing a panel can do.
    private func shortcutCard(entryID: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let entry = service.entry(withID: entryID) {
                HStack(spacing: 10) {
                    iconView(entry)
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    if let existing = service.rowShortcut(for: entry) {
                        Text(existing.displayString)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    }
                }
                .padding(.horizontal, 17)
                .padding(.top, 12)
            }
            Text(text.shortcutCaptureHint)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 17)
                .padding(.bottom, 12)
        }
    }

    private var fieldPlaceholder: String {
        if case .argument(let entryID) = service.mode,
           let range = service.entry(withID: entryID)?.numericRange {
            return String(format: text.argumentRangeFormat, range.lowerBound, range.upperBound)
        }
        if case .naming = service.mode { return text.aliasPlaceholder }
        return text.searchPlaceholder
    }

    // MARK: - Results

    private var trimmedQuery: String {
        service.query.trimmingCharacters(in: .whitespaces)
    }

    /// The chips stay up while a category is on, typing or not: a filter the
    /// person cannot see is a filter they will blame the bar for.
    private var showsCategoryChips: Bool {
        !service.categoryChips.isEmpty
            && (service.isShowingSuggestions || service.activeCategory != nil)
    }

    /// The categories, one tap deep: the same drill-in the launchers people
    /// know. "All" is home; Esc always walks back to it.
    private var categoryChipsRow: some View {
        ScrollViewReader { chips in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    categoryChip(nil, label: text.categoryAll)
                        .id(Self.homeChipID)
                    ForEach(service.categoryChips, id: \.self) { source in
                        categoryChip(source, label: service.categoryTitle(source))
                            .id(source.rawValue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
            .onChange(of: service.activeCategory) { _, category in
                // The arrow keys can walk past the edge of the row.
                withAnimation(.easeOut(duration: 0.12)) {
                    chips.scrollTo(category?.rawValue ?? Self.homeChipID)
                }
            }
        }
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if service.isShowingSuggestions, service.activeCategory == nil {
                // A list of commands never says the bar can add up, convert or
                // reach into another app's menus. Examples do, and clicking
                // one fills the field so it can be tried on the spot.
                HStack(spacing: 5) {
                    Text(text.tryTheseLabel)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)
                    ForEach(CommandBarView.examples, id: \.self) { example in
                        Button {
                            service.query = example
                        } label: {
                            Text(example)
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            ScrollViewReader { proxy in
                // The bar shows more than fits when nothing is typed, and a
                // list with no scrollbar looks like a list that ends there.
                ScrollView(showsIndicators: service.rows.count > 14) {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(service.rows.enumerated()), id: \.element.id) { index, entry in
                            // Every heading lives in the list, directly above
                            // the rows it names.
                            if let heading = service.sectionTitles[index] {
                                sectionHeader(heading)
                            }
                            row(entry, index: index)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                // A short list makes the panel exactly as tall as it needs to
                // be. A long one is pinned to its ceiling instead: asking the
                // layout for the ideal height of a hundred rows would measure
                // every one of them and throw the laziness away.
                .frame(maxHeight: Self.listCeiling)
                .fixedSize(horizontal: false, vertical: service.rows.count <= 14)
                .frame(minHeight: service.rows.count > 14 ? Self.listCeiling : nil)
                .onChange(of: service.selectedIndex) { _, index in
                    guard service.rows.indices.contains(index) else { return }
                    proxy.scrollTo(service.rows[index].id)
                }
            }
        }
    }

    private func categoryChip(_ source: CommandBarSource?, label: String) -> some View {
        let isActive = service.activeCategory == source
        return Button {
            service.setCategory(source)
        } label: {
            HStack(spacing: 3) {
                if let source {
                    Image(systemName: source.symbolName)
                        .font(.system(size: 8.5, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 10, weight: isActive ? .semibold : .regular))
            }
            // Tinted, never filled: white on a pale accent (yellow, orange in
            // light appearance) leaves the label invisible, and every other
            // selected surface in the panel is already accent at low opacity.
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(isActive
                                       ? Color.accentColor.opacity(0.18)
                                       : Color.primary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(isActive ? 0.45 : 0),
                                            lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 3)
    }

    private func row(_ entry: CommandBarEntry, index: Int) -> some View {
        let isSelected = index == service.selectedIndex
        return Button {
            // By identity, not by position: a background load can rebuild the
            // list between the click and this call.
            service.run(entry, fromClick: true)
        } label: {
            HStack(spacing: 10) {
                iconView(entry)
                VStack(alignment: .leading, spacing: 1.5) {
                    titleView(entry)
                    subtitleView(entry)
                }
                Spacer(minLength: 12)
                if service.commandIsHeld, index < 9 {
                    // Holding Command turns the list into nine numbered rows.
                    Text("⌘\(index + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                } else if let value = entry.answerValue {
                    Text(value)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .monospacedDigit()
                } else if let shortcut = service.rowShortcut(for: entry)?.displayString
                            ?? entry.shortcut?.displayString ?? entry.menuShortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    // Always laid out, only drawn on the selected row: without
                    // the reserved width every row shifted as the selection
                    // moved.
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, entry.isAnswer ? 9 : 7)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { service.selectFromHover(index) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(entry))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Everything the eye gets from a row, said in words: the name, where it
    /// lives, its value or shortcut, and the states that are only a colour.
    private func accessibilityLabel(_ entry: CommandBarEntry) -> String {
        var parts = [entry.title, entry.subtitle]
        if let value = entry.answerValue { parts.append(value) }
        if let shortcut = service.rowShortcut(for: entry)?.displayString
            ?? entry.shortcut?.displayString ?? entry.menuShortcut { parts.append(shortcut) }
        if entry.isActive { parts.append(text.stateOn) }
        if service.isPinned(entry) { parts.append(text.pinnedTitle) }
        switch entry.trouble {
        case .needsSetup(let feature, _): parts.append(String(format: text.needsSetupFormat, feature))
        case .needsPermission: parts.append(text.needsPermissionHint)
        case nil: break
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The title with the letters that actually matched in accent, so the row
    /// shows why it is here. The calculator's result gets the loud treatment.
    @ViewBuilder
    private func titleView(_ entry: CommandBarEntry) -> some View {
        if entry.isAnswer {
            Text(entry.title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            let offsets = service.highlightOffsets(for: entry)
            if offsets.isEmpty {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(entry.title)
            } else {
                Text(highlighted(entry.title, offsets: offsets))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func highlighted(_ title: String, offsets: Set<Int>) -> AttributedString {
        var result = AttributedString()
        for (index, character) in title.enumerated() {
            var piece = AttributedString(String(character))
            if offsets.contains(index) {
                piece.foregroundColor = Color.accentColor
                piece.font = .system(size: 13, weight: .bold)
            } else {
                piece.foregroundColor = .primary
            }
            result.append(piece)
        }
        return result
    }

    @ViewBuilder
    private func subtitleView(_ entry: CommandBarEntry) -> some View {
        switch entry.trouble {
        case .needsSetup(let featureTitle, _):
            Text(String(format: text.needsSetupFormat, featureTitle))
                .font(.system(size: 10.5))
                .foregroundStyle(.orange)
                .lineLimit(1)
        case .needsPermission:
            Text(text.needsPermissionHint)
                .font(.system(size: 10.5))
                .foregroundStyle(.orange)
                .lineLimit(1)
        case nil:
            // A row under a heading that already names its area carries no
            // caption at all, which makes the browse list read as one column
            // of names instead of a wall of repetition.
            if !entry.subtitle.isEmpty {
                Text(entry.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func iconView(_ entry: CommandBarEntry) -> some View {
        ZStack(alignment: .topTrailing) {
            // An app or file icon already has its own shape and padding, so a
            // plate behind it reads as a second frame; only glyphs get one.
            if entry.usesPlateIcon {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(entry.isActive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                    .frame(width: 30, height: 30)
                    .overlay(iconContent(entry))
            } else {
                iconContent(entry)
                    .frame(width: 30, height: 30)
            }
            if entry.isActive {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    // A ring keeps the dot legible on top of a colorful icon.
                    .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.2))
                    .offset(x: 2.5, y: -2.5)
            }
        }
    }

    @ViewBuilder
    private func iconContent(_ entry: CommandBarEntry) -> some View {
        switch entry.icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(entry.isActive ? Color.accentColor : Color.primary.opacity(0.85))
        case .appIcon(let path):
            Image(nsImage: CommandBarIconCache.icon(forPath: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
        case .clipboardImage(let name):
            if let thumbnail = ClipboardImageStore.thumbnail(named: name) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.85))
            }
        case .filePath(let path):
            Image(nsImage: CommandBarIconCache.icon(forPath: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
        }
    }

    // MARK: - Empty, argument and confirm states

    private var emptyState: some View {
        VStack(spacing: 9) {
            BrandMark(width: 26, tint: markTint)
                .opacity(0.3)
                .frame(width: 26, height: 26)
                .padding(.bottom, 2)
            Text(text.noResultsTitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {
                service.goHome()
            } label: {
                Text(text.noResultsAction)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func argumentCard(entryID: String) -> some View {
        VStack(spacing: 4) {
            if let entry = service.entry(withID: entryID) {
                HStack(spacing: 10) {
                    iconView(entry)
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 17)
                .padding(.top, 12)
            }
            Text(text.argumentHint)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 17)
                .padding(.bottom, 12)
        }
    }

    private func confirmCard(entryID: String) -> some View {
        VStack(spacing: 6) {
            if let entry = service.entry(withID: entryID) {
                HStack(spacing: 10) {
                    iconView(entry)
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(entry.confirmationPrompt ?? entry.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(text.confirmHint)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Someone who opened the bar with the mouse has to be able
                    // to finish with the mouse.
                    Button(l10n.s.uninstallerCancel) { service.stepBack() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(text.confirmButton) {
                        service.runSelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.09))
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "keyboard")
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
            Text(GlobalShortcut.saved(for: DefaultsKey.commandBarShortcut,
                                      fallback: .commandBarDefault).displayString)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
            if service.canOpenActions {
                Text("⌘K")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text(text.actionsHint)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 4)
            }
            Text(service.isShowingSuggestions && !service.categoryChips.isEmpty ? "⌃P ⌃N ↑↓ ←→" : "⌃P ⌃N ↑↓")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            Image(systemName: "return")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            Text("Esc")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// App and file icons resolved once and kept; NSWorkspace re-reads them from
/// disk on every call otherwise, once per row per render.
///
/// What it keeps is a small bitmap, not what the system hands over: a real
/// app icon carries every representation up to 1024 points, and a few hundred
/// of those held at full size would cost more memory than the rest of the app
/// put together. The rows draw at 28 points, so 64 pixels is already more
/// than any display needs.
enum CommandBarIconCache {
    private static let side: CGFloat = 64

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        // NSCache alone only sheds under system memory pressure, which is too
        // late; the cost ceiling keeps the whole set inside a few megabytes.
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    static func icon(forPath path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let full = NSWorkspace.shared.icon(forFile: path)
        let small = downsampled(full)
        cache.setObject(small, forKey: path as NSString, cost: Int(side * side * 4))
        return small
    }

    private static func downsampled(_ image: NSImage) -> NSImage {
        let size = NSSize(width: side, height: side)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(side),
                                         pixelsHigh: Int(side),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0)
        else { return image }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero,
                   operation: .copy,
                   fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: size)
        result.addRepresentation(rep)
        return result
    }
}
