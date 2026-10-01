// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LaunchpadView: View {
    let onDismiss: () -> Void

    @ObservedObject private var catalog = LaunchpadAppCatalog.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var query = ""
    @State private var page = 0
    @State private var layout = LaunchpadLayoutStore.stored()
    @State private var openFolder: LaunchpadFolder?
    @State private var folderPage = 0
    @State private var folderNameDraft = ""
    @State private var selectedIndex: Int?
    @State private var edgePagingTimer: Timer?
    @State private var hoveringLeadingEdge = false
    @State private var hoveringTrailingEdge = false
    @FocusState private var searchFocused: Bool

    private var text: LaunchpadStrings { FeatureStrings.launchpad(l10n.language) }

    private var apps: [LaunchpadApp] { catalog.apps }
    private var appsByID: [String: LaunchpadApp] { Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) }) }

    /// The grid's tiles in the user's saved order, filtered by the search
    /// query. A folder matches when any app inside it matches.
    private var tiles: [LaunchpadItem] {
        let current = LaunchpadLayoutSupport.applyingCatalog(layout, knownAppIDs: Set(apps.map(\.id)))
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return current.items }
        return current.items.filter { item in
            switch item {
            case .app(let id):
                return appsByID[id].map { !LaunchpadAppSupport.filtered([$0], query: trimmed).isEmpty } ?? false
            case .folder(let folder):
                return folder.appIDs.contains { appsByID[$0].map { !LaunchpadAppSupport.filtered([$0], query: trimmed).isEmpty } ?? false }
            }
        }
    }

    private var pages: [[LaunchpadItem]] {
        guard !tiles.isEmpty else { return [] }
        return stride(from: 0, to: tiles.count, by: LaunchpadAppSupport.perPage)
            .map { Array(tiles[$0..<min($0 + LaunchpadAppSupport.perPage, tiles.count)]) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.001) // catches clicks on empty background without visibly tinting the desktop
                .onTapGesture(perform: onDismiss)
                // A click-and-drag on empty background pages the grid, the
                // mouse equivalent of the trackpad swipe. minimumDistance
                // keeps a plain click free to dismiss instead of registering
                // as a zero-length drag.
                .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                    let step = LaunchpadPagingSupport.pageStep(cumulativeX: -value.translation.width)
                    guard let target = LaunchpadPagingSupport.targetPage(current: page, step: step, pageCount: pages.count) else { return }
                    withAnimation(.easeOut(duration: 0.25)) { page = target }
                })
            VStack(spacing: 24) {
                searchField
                if pages.indices.contains(page) {
                    grid(for: pages[page])
                }
                Spacer()
                if pages.count > 1 { pageDots }
            }
            .padding(.top, 60)
            .padding(.bottom, 90)
            if let openFolder {
                folderOverlay(openFolder)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            // Dragging an icon to the screen edge pages, just like the
            // original — held over one of these strips, not just passed
            // through, since a drag crossing the grid to reach a nearby
            // page shouldn't trigger it by accident.
            HStack(spacing: 0) {
                edgePagingZone(step: -1, isTargeted: $hoveringLeadingEdge)
                Spacer()
                edgePagingZone(step: 1, isTargeted: $hoveringTrailingEdge)
            }
        }
        .onAppear { refreshOnShow() }
        .onChange(of: query) { page = 0; selectedIndex = nil }
        .onChange(of: page) { selectedIndex = nil }
        .onChange(of: hoveringLeadingEdge) { setEdgePaging(active: hoveringLeadingEdge, step: -1) }
        .onChange(of: hoveringTrailingEdge) { setEdgePaging(active: hoveringTrailingEdge, step: 1) }
        .onChange(of: catalog.apps) { materializeDefaultLayoutIfNeeded() }
        .onReceive(LaunchpadService.shared.pageStep) { step in
            guard let target = LaunchpadPagingSupport.targetPage(current: page, step: step, pageCount: pages.count) else { return }
            withAnimation(.easeOut(duration: 0.25)) { page = target }
        }
        .onReceive(LaunchpadService.shared.didShow) { refreshOnShow() }
        .onReceive(LaunchpadService.shared.keyAction) { handleKeyAction($0) }
    }

    /// Ignored while a folder is open: the folder overlay has no keyboard
    /// navigation of its own yet, and applying these to the grid behind it
    /// while it's covered would move a selection nobody can see.
    private func handleKeyAction(_ action: LaunchpadKeyAction) {
        guard openFolder == nil, pages.indices.contains(page) else { return }
        let currentPage = pages[page]
        switch action {
        case .arrow(let direction, let commandHeld):
            if commandHeld {
                let step = direction == .right ? 1 : direction == .left ? -1 : 0
                guard step != 0, let target = LaunchpadPagingSupport.targetPage(current: page, step: step, pageCount: pages.count) else { return }
                withAnimation(.easeOut(duration: 0.25)) { page = target }
            } else {
                selectedIndex = LaunchpadSelectionSupport.moved(current: selectedIndex, direction: direction,
                                                                count: currentPage.count, columns: LaunchpadAppSupport.columns)
            }
        case .launch:
            guard let selectedIndex, currentPage.indices.contains(selectedIndex) else { return }
            switch currentPage[selectedIndex] {
            case .app(let id):
                if let app = appsByID[id] { launch(app) }
            case .folder(let folder):
                open(folder)
            }
        }
    }

    private func open(_ folder: LaunchpadFolder) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { openFolder = folder }
    }

    private func closeFolder() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { openFolder = nil }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(text.searchPlaceholder, text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
        }
        .padding(.horizontal, 14)
        .frame(width: 280, height: 34)
        .background(HUDBackdrop(cornerRadius: 17, contrast: .high))
        .clipShape(Capsule())
    }

    private func grid(for items: [LaunchpadItem]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 28), count: LaunchpadAppSupport.columns), spacing: 28) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                tile(for: item, isSelected: index == selectedIndex)
                    .onTapGesture { selectedIndex = index }
            }
        }
        .padding(.horizontal, 60)
    }

    @ViewBuilder
    private func tile(for item: LaunchpadItem, isSelected: Bool) -> some View {
        switch item {
        case .app(let id):
            if let app = appsByID[id] {
                appTile(app)
                    .selectionHighlight(isSelected)
                    .onDrag { NSItemProvider(object: app.id as NSString) }
                    .onDrop(of: [.text], delegate: LaunchpadDropDelegate(targetID: item.id, layout: $layout, newFolderName: text.newFolderDefaultName))
            }
        case .folder(let folder):
            folderTile(folder)
                .selectionHighlight(isSelected)
                .onDrop(of: [.text], delegate: LaunchpadDropDelegate(targetID: item.id, layout: $layout, newFolderName: text.newFolderDefaultName))
                .onTapGesture { open(folder) }
        }
    }

    private func appTile(_ app: LaunchpadApp) -> some View {
        VStack(spacing: 8) {
            Image(nsImage: LaunchpadIconCache.icon(forPath: app.path))
                .resizable()
                .frame(width: 72, height: 72)
            Text(app.name).font(.system(size: 11)).foregroundStyle(.white).lineLimit(1)
        }
        .frame(width: 96)
        .contentShape(Rectangle())
        .onTapGesture { launch(app) }
    }

    /// The classic Launchpad folder preview: a 3x3 grid of up to nine of the
    /// folder's own icons, shrunk into one tile.
    private func folderTile(_ folder: LaunchpadFolder) -> some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.clear)
                .background(HUDBackdrop(cornerRadius: 16))
                .frame(width: 72, height: 72)
                .overlay {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                        ForEach(folder.appIDs.prefix(9), id: \.self) { id in
                            if let app = appsByID[id] {
                                Image(nsImage: LaunchpadIconCache.icon(forPath: app.path))
                                    .resizable().frame(width: 20, height: 20)
                            }
                        }
                    }
                    .padding(6)
                }
            Text(folder.name).font(.system(size: 11)).foregroundStyle(.white).lineLimit(1)
        }
        .frame(width: 96)
    }

    /// An open folder is a small Launchpad in miniature: its own grid, and
    /// its own pages once it holds more apps than one page can show.
    private func folderOverlay(_ folder: LaunchpadFolder) -> some View {
        let folderApps = folder.appIDs.compactMap { appsByID[$0] }
        let folderPages = LaunchpadAppSupport.folderPages(folderApps)
        return VStack(spacing: 20) {
            TextField(folder.name, text: $folderNameDraft)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 220)
                .onSubmit { commitFolderRename(folder) }
            if folderPages.indices.contains(folderPage) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: LaunchpadAppSupport.folderColumns), spacing: 24) {
                    ForEach(folderPages[folderPage]) { app in
                        appTile(app)
                    }
                }
                .padding(28)
                .background(HUDBackdrop(cornerRadius: 24, contrast: .high))
            }
            if folderPages.count > 1 {
                HStack(spacing: 8) {
                    ForEach(folderPages.indices, id: \.self) { index in
                        Circle()
                            .fill(index == folderPage ? Color.white : Color.white.opacity(0.35))
                            .frame(width: 6, height: 6)
                            .onTapGesture { folderPage = index }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35).onTapGesture {
            commitFolderRename(folder)
            closeFolder()
        })
        .onChange(of: openFolder) { folderPage = 0; folderNameDraft = openFolder?.name ?? "" }
    }

    /// A blank draft (never typed into, or cleared back to nothing) leaves
    /// the folder's name untouched rather than renaming it to empty.
    private func commitFolderRename(_ folder: LaunchpadFolder) {
        guard !folderNameDraft.trimmingCharacters(in: .whitespaces).isEmpty, folderNameDraft != folder.name else { return }
        let updated = LaunchpadLayoutSupport.renamingFolder(layout, folderID: folder.id, name: folderNameDraft)
        layout = updated
        LaunchpadLayoutStore.save(updated)
        if case .folder(let renamed) = updated.items.first(where: { $0.id == folder.id.uuidString }) {
            openFolder = renamed
        }
    }

    private var pageDots: some View {
        let dotSize: CGFloat = 7
        let spacing: CGFloat = 8
        let rowWidth = CGFloat(pages.count) * dotSize + CGFloat(max(pages.count - 1, 0)) * spacing
        return HStack(spacing: spacing) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == page ? Color.white : Color.white.opacity(0.35))
                    .frame(width: dotSize, height: dotSize)
                    .onTapGesture { page = index }
            }
        }
        // A drag across the row scrubs through pages the same way dragging
        // a scrubber does, instead of only jumping to a tap.
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            page = LaunchpadPagingSupport.scrubbedPage(x: value.location.x, width: rowWidth, pageCount: pages.count)
        })
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(HUDBackdrop(cornerRadius: 14))
        .clipShape(Capsule())
        .padding(.bottom, 16)
    }

    /// Re-reads the saved layout and focuses search, both of which only
    /// need to happen once the panel is actually about to be seen.
    private func refreshOnShow() {
        layout = LaunchpadLayoutStore.stored()
        query = ""
        page = 0
        openFolder = nil
        selectedIndex = nil
        searchFocused = true
        edgePagingTimer?.invalidate()
        edgePagingTimer = nil
        materializeDefaultLayoutIfNeeded()
    }

    /// A layout that was never customized starts from the native Utilities
    /// grouping instead of a flat list, the very first time real apps are
    /// known — saved once so it becomes the real stored layout from then on,
    /// not recomputed (with a fresh folder id) on every later open.
    private func materializeDefaultLayoutIfNeeded() {
        guard layout.items.isEmpty, !apps.isEmpty else { return }
        let fresh = LaunchpadLayoutSupport.defaultLayout(for: apps, utilitiesFolderName: text.utilitiesFolderName)
        layout = fresh
        LaunchpadLayoutStore.save(fresh)
    }

    private func edgePagingZone(step: Int, isTargeted: Binding<Bool>) -> some View {
        Color.clear
            .frame(width: 44)
            .contentShape(Rectangle())
            .onDrop(of: [.text], isTargeted: isTargeted) { _ in false }
    }

    private func setEdgePaging(active: Bool, step: Int) {
        edgePagingTimer?.invalidate()
        edgePagingTimer = nil
        guard active else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: LaunchpadPagingSupport.edgePagingInterval, repeats: true) { _ in
            guard let target = LaunchpadPagingSupport.targetPage(current: page, step: step, pageCount: pages.count) else { return }
            withAnimation(.easeOut(duration: 0.25)) { page = target }
        }
        edgePagingTimer = timer
        timer.fire()
    }

    private func launch(_ app: LaunchpadApp) {
        NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
        onDismiss()
    }
}

/// Backs both drag-to-reorder and drag-onto-icon-to-create-a-folder: the
/// actual decision (reorder vs. combine vs. add-to-folder) is
/// `LaunchpadLayoutSupport`'s, this delegate only reads the dropped id and
/// writes the result back to the store.
private struct LaunchpadDropDelegate: DropDelegate {
    let targetID: String
    @Binding var layout: LaunchpadLayout
    let newFolderName: String

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let draggedID = reading as? String, draggedID != targetID else { return }
            DispatchQueue.main.async {
                let updated: LaunchpadLayout
                if layout.items.contains(where: { $0.id == targetID }) {
                    updated = LaunchpadLayoutSupport.combining(layout, draggedAppID: draggedID, ontoID: targetID,
                                                               defaultFolderName: newFolderName)
                } else {
                    updated = LaunchpadLayoutSupport.moving(layout, itemID: draggedID, beforeItemID: targetID)
                }
                layout = updated
                LaunchpadLayoutStore.save(updated)
            }
        }
        return true
    }
}

private extension View {
    /// The keyboard-navigated tile, outlined the same way a focus ring
    /// would be — arrow keys move this, Return activates whichever tile
    /// currently has it.
    @ViewBuilder
    func selectionHighlight(_ isSelected: Bool) -> some View {
        if isSelected {
            self.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                .padding(-6))
        } else {
            self
        }
    }
}
