// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// App icons, looked up once per path. The workspace already caches them,
/// but asking it again for every cell on every redraw is what made the grid
/// stutter.
enum LaunchpadIcons {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }
}

/// The coordinate space every Launchpad view reports its cells in: the
/// window's content, from its top left corner, as the drag reads the pointer.
extension CoordinateSpace {
    static let launchpad = CoordinateSpace.named("launchpad")
}

struct LaunchpadView: View {
    @ObservedObject private var service = LaunchpadService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.launchpadStyle) private var styleRaw = LaunchpadSupport.Style.fullScreen.rawValue
    @Environment(\.colorScheme) private var systemColorScheme
    @FocusState private var searchFocused: Bool

    private var strings: LaunchpadFeatureStrings { FeatureStrings.launchpad(l10n.language) }
    private var style: LaunchpadSupport.Style { .sanitized(styleRaw) }
    private var cornerRadius: CGFloat { style == .panel ? 26 : 0 }
    private var overlayOpen: Bool {
        service.openFolderID != nil || service.openCategory != nil || service.folderEditor != nil
            || service.pendingDelete != nil
    }

    var body: some View {
        ZStack {
            LaunchpadBackdrop(style: style, cornerRadius: cornerRadius)
                .contentShape(Rectangle())
                .gesture(LaunchpadPager.emptySpace)
            LaunchpadEntrance {
                VStack(spacing: 0) {
                    header
                    content
                }
                .padding(.top, style == .panel ? 18 : 36)
                .padding(.bottom, style == .panel ? 12 : 22)
            }
            // An open folder pushes the grid back, as on Launchpad.
            .blur(radius: overlayOpen ? 18 : 0)
            .scaleEffect(overlayOpen ? 0.95 : 1)
            .allowsHitTesting(!overlayOpen)
            if let id = service.openFolderID, let folder = service.layout.folder(id) {
                LaunchpadFolderOverlay(folder: folder)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.2, anchor: service.folderAnchor).combined(with: .opacity),
                        removal: .scale(scale: 0.2, anchor: service.folderAnchor).combined(with: .opacity)))
            }
            if let category = service.openCategory {
                LaunchpadCategoryOverlay(category: category)
            }
            if service.folderEditor != nil {
                LaunchpadFolderEditorView()
            }
            if let path = service.pendingDelete {
                LaunchpadDeleteConfirmation(path: path)
            }
            LaunchpadDragGhost()
        }
        .coordinateSpace(name: "launchpad")
        .animation(.spring(duration: 0.38, bounce: 0.12), value: service.openFolderID)
        .animation(.smooth(duration: 0.3), value: service.openCategory)
        .animation(.smooth(duration: 0.3), value: service.folderEditor != nil)
        .animation(.smooth(duration: 0.25), value: service.pendingDelete)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // Full screen always sits on the darkened wallpaper, as Launchpad
        // did; the panel follows the system appearance like other panels.
        .environment(\.colorScheme, style == .fullScreen ? .dark : systemColorScheme)
        .onChange(of: service.isVisible) { _, visible in
            if visible { searchFocused = true }
        }
        .onChange(of: overlayOpen) { _, open in
            if !open { searchFocused = true }
        }
        .onAppear { searchFocused = true }
    }

    /// The search field carries everything else in its menu, as the
    /// system's own field does.
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(strings.search, text: $service.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
            if !service.query.isEmpty {
                Button { service.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Menu {
                Button { service.beginNewFolder() } label: {
                    Label(strings.newFolder, systemImage: "folder.badge.plus")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(width: 300, height: 38)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8))
        .padding(.bottom, style == .panel ? 14 : 30)
    }

    @ViewBuilder private var content: some View {
        if !service.query.isEmpty {
            LaunchpadSearchResults()
                .padding(.horizontal, style == .panel ? 20 : 120)
        } else {
            // Launchpad left a wide margin on each side; the panel has its own edge.
            LaunchpadPagedGrid(insetFraction: style == .panel ? 0.03 : 0.085)
        }
    }
}

// MARK: - Backdrop and entrance

/// Full screen draws the wallpaper, blurred and darkened, so open windows
/// never show through; the panel uses the frost of the app's other panels.
private struct LaunchpadBackdrop: View {
    let style: LaunchpadSupport.Style
    let cornerRadius: CGFloat
    @ObservedObject private var motion = LaunchpadMotion.shared

    var body: some View {
        Group {
            if style == .fullScreen {
                // An overlay, so a picture filled past the screen's shape
                // never widens the layout above it.
                Color.black
                    .overlay {
                        if let wallpaper = motion.wallpaper {
                            Image(nsImage: wallpaper)
                                .resizable()
                                .interpolation(.medium)
                                .aspectRatio(contentMode: .fill)
                                .transition(.opacity)
                        } else {
                            // Never the windows behind: a plain night sky
                            // until (or unless) the picture can be read.
                            LinearGradient(colors: [Color(red: 0.12, green: 0.12, blue: 0.2),
                                                    Color(red: 0.04, green: 0.04, blue: 0.08)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                    }
                    .overlay(Color.black.opacity(0.32))
                    .clipped()
                    .ignoresSafeArea()
            } else {
                HUDBackdrop(cornerRadius: cornerRadius)
            }
        }
        .opacity(motion.shown ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: motion.wallpaper != nil)
    }
}

/// The grid grows in from slightly large and fades in, and shrinks back out
/// when Launchpad closes, the way the system one did.
private struct LaunchpadEntrance<Content: View>: View {
    @ViewBuilder var content: Content
    @ObservedObject private var motion = LaunchpadMotion.shared

    var body: some View {
        content
            .scaleEffect(motion.shown ? 1 : 1.07)
            .opacity(motion.shown ? 1 : 0)
    }
}

// MARK: - Icons

struct LaunchpadAppIcon: View {
    let path: String
    var size: CGFloat = 96

    var body: some View {
        Image(nsImage: LaunchpadIcons.icon(for: path))
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .frame(width: size, height: size)
    }
}

struct LaunchpadLabel: View {
    let text: String
    var size: CGFloat = 13

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
            // Flattened once, with room for the shadow, so a sliding page
            // moves a picture instead of blurring every name per frame.
            .padding(4)
            .drawingGroup()
            .padding(-4)
    }
}

/// A folder drawn as Launchpad drew it: a frosted tile holding its first
/// nine apps in miniature.
struct LaunchpadFolderTile: View {
    let folder: LaunchpadFolder
    var size: CGFloat = 96

    var body: some View {
        let mini = size * 0.22
        let gap = size * 0.06
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
            .frame(width: size, height: size)
            .overlay {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(mini), spacing: gap), count: 3), spacing: gap) {
                    ForEach(folder.apps.prefix(9), id: \.self) { path in
                        LaunchpadAppIcon(path: path, size: mini)
                    }
                }
                .frame(width: mini * 3 + gap * 2, height: mini * 3 + gap * 2, alignment: .top)
            }
    }
}

private struct LaunchpadItemIcon: View {
    let item: LaunchpadItem
    let size: CGFloat

    var body: some View {
        switch item {
        case .app(let path): LaunchpadAppIcon(path: path, size: size)
        case .folder(let folder): LaunchpadFolderTile(folder: folder, size: size)
        }
    }
}

// MARK: - Cells

/// One icon on the grid or in an open folder. A click opens it; holding it
/// still makes everything wiggle; moving it picks it up. Only the icon and
/// its name count: a click in the space around them falls to the
/// background, which closes Launchpad.
struct LaunchpadCell: View, Equatable {
    let item: LaunchpadItem
    let name: String
    let iconSize: CGFloat
    let cellSize: CGSize
    var inFolder = false
    var editing = false
    var deletable = false
    var mergeTarget = false
    @State private var pressed = false
    @State private var picked = false
    @State private var holdWork: DispatchWorkItem?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.name == rhs.name && lhs.iconSize == rhs.iconSize
            && lhs.cellSize == rhs.cellSize && lhs.inFolder == rhs.inFolder && lhs.editing == rhs.editing
            && lhs.deletable == rhs.deletable && lhs.mergeTarget == rhs.mergeTarget
    }

    /// The icon's middle, in the cell, above its name.
    private var iconCenter: CGPoint {
        CGPoint(x: cellSize.width / 2, y: cellSize.height / 2 - LaunchpadSupport.labelBlock / 2)
    }

    private var hitRect: CGRect {
        let width = min(cellSize.width, max(iconSize + 16, 110))
        let height = iconSize + LaunchpadSupport.labelBlock + 10
        return CGRect(x: (cellSize.width - width) / 2, y: (cellSize.height - height) / 2, width: width, height: height)
    }

    var body: some View {
        VStack(spacing: 9) {
            LaunchpadItemIcon(item: item, size: iconSize)
                // Resting another app on this one: a folder starts to form behind it.
                .background {
                    if mergeTarget, case .app = item {
                        RoundedRectangle(cornerRadius: iconSize * 0.3, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: iconSize * 0.3, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8))
                            .frame(width: iconSize * 1.32, height: iconSize * 1.32)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                .scaleEffect(mergeTarget ? (isFolder ? 1.14 : 0.86) : 1)
                .brightness(pressed && !picked ? -0.22 : 0)
                .overlay(alignment: .topLeading) {
                    if editing, deletable, case .app(let path) = item {
                        LaunchpadDeleteBadge { LaunchpadService.shared.pendingDelete = path }
                            .offset(x: -8, y: -8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .modifier(LaunchpadWiggle(active: editing, seed: abs(item.id.hashValue % 7)))
            LaunchpadLabel(text: name)
                .frame(maxWidth: cellSize.width - 12)
                .opacity(mergeTarget ? 0 : 1)
        }
        .frame(width: cellSize.width, height: cellSize.height)
        .contentShape(Rectangle())
        .gesture(press)
        .contextMenu { menu }
        .animation(.smooth(duration: 0.2), value: mergeTarget)
        .animation(.smooth(duration: 0.12), value: pressed)
    }

    private var isFolder: Bool {
        if case .folder = item { return true }
        return false
    }

    /// One gesture for the whole life of a press, so a click, a hold and a
    /// pick-up never fight over the same mouse button.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !pressed {
                    // Around the icon is empty space, which grabs the pages.
                    guard hitRect.contains(value.startLocation) else {
                        if !inFolder { LaunchpadPager.shared.drag(value, pageCount: LaunchpadService.shared.pageCount) }
                        return
                    }
                    pressed = true
                    let work = DispatchWorkItem { LaunchpadService.shared.toggleEditing(true) }
                    holdWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
                }
                let moved = hypot(value.translation.width, value.translation.height)
                if !picked, moved > 4 {
                    picked = true
                    holdWork?.cancel()
                    LaunchpadDrag.shared.begin(item, grab: CGSize(width: value.startLocation.x - iconCenter.x,
                                                                  height: value.startLocation.y - iconCenter.y))
                }
            }
            .onEnded { value in
                holdWork?.cancel()
                holdWork = nil
                defer {
                    pressed = false
                    picked = false
                }
                // A pick-up ends with the window's own mouse-up, in the drag.
                guard !picked, !LaunchpadPager.shared.drop(pageCount: LaunchpadService.shared.pageCount)
                else { return }
                guard pressed, hitRect.contains(value.location) else {
                    LaunchpadService.shared.dismissFromBackground()
                    return
                }
                if !editing { activate() }
            }
    }

    private func activate() {
        let service = LaunchpadService.shared
        switch item {
        case .app(let path): service.launch(path)
        case .folder(let folder):
            let center = service.gridGeometry.origin
            let slot = (service.layout.items.firstIndex { $0.id == folder.id } ?? 0) - service.page * service.perPage
            service.openFolder(folder.id, from: slot >= 0 ? service.gridGeometry.iconCenter(of: slot) : center)
        }
    }

    @ViewBuilder private var menu: some View {
        let strings = FeatureStrings.launchpad(L10n.shared.language)
        let service = LaunchpadService.shared
        switch item {
        case .app(let path):
            Button(strings.open) { service.launch(path) }
            Button(strings.showInFinder) { service.showInFinder(path) }
            Divider()
            if inFolder {
                Button(strings.removeFromFolder) { service.takeOutOfFolder(path) }
            }
            Button(strings.hideApp) { service.hideApp(path) }
            if deletable {
                Button(strings.moveToTrash) { service.pendingDelete = path }
            }
        case .folder(let folder):
            Button(strings.editFolder) { service.beginEditing(folder.id) }
            Button(strings.deleteFolder) { service.deleteFolder(folder.id) }
        }
    }
}

/// The iPhone's wiggle: a small rocking that each icon keeps at its own
/// pace, so the grid trembles rather than swaying as one. One repeating
/// animation per icon, left to the renderer, rather than a state change
/// every swing, which crowded out the pages' glide.
private struct LaunchpadWiggle: ViewModifier {
    let active: Bool
    let seed: Int
    @State private var tilted = false

    func body(content: Content) -> some View {
        let angle = (tilted ? 1.5 : -1.5) * (seed.isMultiple(of: 2) ? 1.0 : -1.0)
        content
            .rotationEffect(.degrees(active ? angle : 0))
            .animation(active ? .easeInOut(duration: 0.12 + Double(seed) * 0.008).repeatForever() : .smooth(duration: 0.15),
                       value: tilted)
            .onChange(of: active, initial: true) { _, on in tilted = on }
    }
}

private struct LaunchpadDeleteBadge: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}

/// The icon in the hand: the real icon at its own size, lifted a little
/// with a soft shadow, gliding into its place when let go.
private struct LaunchpadDragGhost: View {
    @ObservedObject private var drag = LaunchpadDrag.shared
    @ObservedObject private var pointer = LaunchpadDragPointer.shared

    var body: some View {
        if let item = drag.item {
            let service = LaunchpadService.shared
            let size = drag.context == .grid ? service.gridGeometry.iconSize : service.folderGeometry.iconSize
            LaunchpadItemIcon(item: item, size: size)
                .scaleEffect(pointer.landing == .merge ? 0.4 : pointer.landing == .slot ? 1 : 1.1)
                .opacity(pointer.landing == .merge ? 0 : 1)
                .shadow(color: .black.opacity(pointer.landing == nil ? 0.35 : 0), radius: 18, y: 10)
                .position(pointer.location)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Paged grid

struct LaunchpadPagedGrid: View {
    let insetFraction: CGFloat
    @ObservedObject private var service = LaunchpadService.shared
    @ObservedObject private var drag = LaunchpadDrag.shared
    @ObservedObject private var pager = LaunchpadPager.shared

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let inset = (width * insetFraction).rounded()
            let gridSize = CGSize(width: max(width - inset * 2, 200),
                                  height: max(geometry.size.height - 34, 100))
            let grid = LaunchpadSupport.grid(for: gridSize)
            let perPage = grid.columns * grid.rows
            let dragging = drag.item != nil && drag.context == .grid
            let shown = dragging ? LaunchpadSupport.shown(drag.gridBase, gap: drag.gap) : service.layout.items.map { $0 }
            let appPages = LaunchpadSupport.pageCount(items: shown.count, perPage: perPage)
            let cell = CGSize(width: gridSize.width / CGFloat(grid.columns),
                              height: gridSize.height / CGFloat(grid.rows))
            let iconSize = min(108, cell.width * 0.5, (cell.height - 34) * 0.8).rounded()
            let metrics = LaunchpadGridGeometry(origin: .zero, cell: cell, columns: grid.columns,
                                                rows: grid.rows, iconSize: iconSize)
            VStack(spacing: 0) {
                LaunchpadPagerTrack {
                    HStack(spacing: 0) {
                        ForEach(0..<appPages, id: \.self) { page in
                            pageView(shown: shown, page: page, perPage: perPage, metrics: metrics)
                                .padding(.horizontal, inset)
                                .frame(width: width, height: gridSize.height)
                        }
                        LaunchpadCategoriesPage(size: gridSize)
                            .padding(.horizontal, inset)
                            .frame(width: width, height: gridSize.height)
                    }
                }
                .frame(width: width, height: gridSize.height, alignment: .leading)
                .clipped()
                .background {
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .launchpad)
                        Color.clear
                            .onAppear { report(frame: frame, inset: inset, metrics: metrics, perPage: perPage) }
                            .onChange(of: frame) { _, value in
                                report(frame: value, inset: inset, metrics: metrics, perPage: perPage)
                            }
                            .onChange(of: metrics) { _, value in
                                report(frame: frame, inset: inset, metrics: value, perPage: perPage)
                            }
                    }
                }
                LaunchpadPageDots(pages: appPages + 1)
            }
        }
    }

    private func report(frame: CGRect, inset: CGFloat, metrics: LaunchpadGridGeometry, perPage: Int) {
        var geometry = metrics
        geometry.origin = CGPoint(x: frame.minX + inset, y: frame.minY)
        service.gridGeometry = geometry
        service.perPage = perPage
        LaunchpadPager.shared.pageWidth = frame.width
    }

    /// Every cell sits at a computed spot, never wherever a stack would
    /// stretch it, so the grid keeps its margins and the icons slide
    /// smoothly when a drag opens a gap among them.
    private func pageView(shown: [LaunchpadItem?], page: Int, perPage: Int,
                          metrics: LaunchpadGridGeometry) -> some View {
        let range = (page * perPage)..<min((page + 1) * perPage, shown.count)
        return ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(LaunchpadPager.emptySpace)
            ForEach(range.compactMap { index in shown[index].map { (index, $0) } }, id: \.1.id) { index, item in
                let slot = index - range.lowerBound
                LaunchpadCell(item: item, name: name(of: item), iconSize: metrics.iconSize, cellSize: metrics.cell,
                              // Pages out of sight keep still, so the wiggle costs no more than one screen.
                              editing: service.isEditing && abs(page - pager.page) <= 1,
                              deletable: service.isDeletable(item),
                              mergeTarget: drag.mergeIndex == index)
                    .equatable()
                    .position(x: (CGFloat(slot % metrics.columns) + 0.5) * metrics.cell.width,
                              y: (CGFloat(slot / metrics.columns) + 0.5) * metrics.cell.height)
            }
        }
    }

    private func name(of item: LaunchpadItem) -> String {
        switch item {
        case .app(let path): return service.name(of: path)
        case .folder(let folder): return folder.name
        }
    }
}

/// Slides the strip of pages. It alone follows the pager's every frame, so
/// the cells it holds are not rebuilt as the pages move.
private struct LaunchpadPagerTrack<Content: View>: View {
    @ViewBuilder var content: Content
    @ObservedObject private var strip = LaunchpadPager.shared.strip

    var body: some View {
        content.offset(x: -strip.position)
    }
}

extension LaunchpadPager {
    /// Empty space on the grid: a mouse drags the pages with it, as Launchpad
    /// let it, and a click that never moves puts Launchpad (or the wiggle)
    /// away, as before.
    static var emptySpace: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let service = LaunchpadService.shared
                if service.browsingGrid { shared.drag(value, pageCount: service.pageCount) }
            }
            .onEnded { _ in
                let service = LaunchpadService.shared
                if !shared.drop(pageCount: service.pageCount) { service.dismissFromBackground() }
            }
    }
}

private struct LaunchpadPageDots: View {
    let pages: Int
    @ObservedObject private var pager = LaunchpadPager.shared

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<pages, id: \.self) { page in
                Circle()
                    .fill(Color.white.opacity(page == pager.page ? 0.95 : 0.32))
                    .frame(width: 7, height: 7)
                    .contentShape(Rectangle().inset(by: -5))
                    .onTapGesture { LaunchpadService.shared.setPage(page, pageCount: pages) }
            }
        }
        .frame(height: 34)
        .opacity(pages > 1 ? 1 : 0)
        .animation(.smooth(duration: 0.2), value: pager.page)
    }
}

// MARK: - Search and categories

/// Apps laid out without pages, for a list that scrolls: the inside of a
/// category. Only an icon and its name open the app.
struct LaunchpadAppList: View {
    let apps: [LaunchpadService.App]
    var iconSize: CGFloat = 72
    @ObservedObject private var l10n = L10n.shared

    private var strings: LaunchpadFeatureStrings { FeatureStrings.launchpad(l10n.language) }

    var body: some View {
        let service = LaunchpadService.shared
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: iconSize + 60), spacing: 8)], spacing: 26) {
                ForEach(apps) { app in
                    VStack(spacing: 9) {
                        LaunchpadAppIcon(path: app.path, size: iconSize)
                        LaunchpadLabel(text: app.name)
                    }
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { service.launch(app.path) }
                    .contextMenu {
                        Button(strings.open) { service.launch(app.path) }
                        Button(strings.showInFinder) { service.showInFinder(app.path) }
                        Divider()
                        if service.layout.hidden.contains(app.path) {
                            Button(strings.unhideApp) { service.unhideApp(app.path) }
                        } else {
                            Button(strings.hideApp) { service.hideApp(app.path) }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
    }
}

/// Typing filters every app, hidden ones and those in folders included. The
/// best match is picked, the arrows move the pick and Return opens it.
struct LaunchpadSearchResults: View {
    @ObservedObject private var service = LaunchpadService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let results = service.searchResults
        let strings = FeatureStrings.launchpad(l10n.language)
        if results.isEmpty {
            Text(strings.noResults)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { reader in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0),
                                             count: LaunchpadService.searchColumns), spacing: 18) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, app in
                            VStack(spacing: 9) {
                                LaunchpadAppIcon(path: app.path, size: 88)
                                LaunchpadLabel(text: app.name)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 10)
                            .background {
                                if index == service.selection {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color.white.opacity(0.16))
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { service.launch(app.path) }
                            .contextMenu {
                                Button(strings.open) { service.launch(app.path) }
                                Button(strings.showInFinder) { service.showInFinder(app.path) }
                                Divider()
                                if service.layout.hidden.contains(app.path) {
                                    Button(strings.unhideApp) { service.unhideApp(app.path) }
                                } else {
                                    Button(strings.hideApp) { service.hideApp(app.path) }
                                }
                            }
                            .id(app.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.never)
                .onChange(of: service.selection) { _, index in
                    guard results.indices.contains(index) else { return }
                    withAnimation(.smooth(duration: 0.2)) { reader.scrollTo(results[index].id) }
                }
            }
        }
    }
}

enum LaunchpadCategories {
    /// Each shelf with the apps it holds, empty shelves left out. Hidden
    /// apps sit only on the Hidden shelf, so hiding still means out of sight.
    static func shelves(_ service: LaunchpadService) -> [(LaunchpadCategory, [LaunchpadService.App])] {
        let hidden = Set(service.layout.hidden)
        let apps = service.sortedApps
        return LaunchpadCategory.allCases.compactMap { category in
            let members = category == .hidden
                ? apps.filter { hidden.contains($0.path) }
                : apps.filter { $0.category == category && !hidden.contains($0.path) }
            return members.isEmpty ? nil : (category, members)
        }
    }
}

/// The last page, like the App Library after the last home screen: one
/// card per category, sized so every card fits on the page.
struct LaunchpadCategoriesPage: View {
    let size: CGSize
    @ObservedObject private var service = LaunchpadService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let strings = FeatureStrings.launchpad(l10n.language)
        let shelves = LaunchpadCategories.shelves(service)
        let columns = 4
        let rows = max(1, (shelves.count + columns - 1) / columns)
        let spacing: CGFloat = 28
        let cardWidth = min((size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns),
                            ((size.height - CGFloat(rows) * 30) / CGFloat(rows) - spacing) * 1.45)
        let mini = (cardWidth - 36 - 3 * 12) / 4
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .gesture(LaunchpadPager.emptySpace)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing), count: columns),
                      spacing: spacing) {
                ForEach(shelves, id: \.0) { category, apps in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
                            .frame(width: cardWidth, height: cardWidth / 1.45)
                            .overlay(alignment: .topLeading) {
                                LazyVGrid(columns: Array(repeating: GridItem(.fixed(mini), spacing: 12), count: 4),
                                          alignment: .leading, spacing: 12) {
                                    ForEach(apps.prefix(8)) { app in
                                        LaunchpadAppIcon(path: app.path, size: mini)
                                    }
                                }
                                .padding(18)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .onTapGesture { service.openCategory = category }
                        LaunchpadLabel(text: strings.title(category))
                    }
                }
            }
        }
    }
}

// MARK: - Overlays

/// The dimmed layer behind an open category or a dialog; a click on it
/// closes what is open.
private struct LaunchpadOverlayCard<Content: View>: View {
    var onDismiss: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            content
                .padding(28)
                .frame(maxWidth: 860, maxHeight: 580)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
                        .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
                )
                .padding(40)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }
}

/// An open folder as Launchpad showed one: its name above a frosted card of
/// its apps, grown out of the folder's icon. Apps move inside it like on
/// the grid, and an app pulled past its edge takes the folder away so it
/// can be placed anywhere.
struct LaunchpadFolderOverlay: View {
    let folder: LaunchpadFolder
    @ObservedObject private var service = LaunchpadService.shared
    @ObservedObject private var drag = LaunchpadDrag.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private static let cell = CGSize(width: 150, height: 142)
    private static let iconSize: CGFloat = 84
    private static let padding: CGFloat = 22

    var body: some View {
        let strings = FeatureStrings.launchpad(l10n.language)
        let dragging = drag.item != nil && drag.context == .folder(folder.id)
        let shown = dragging ? LaunchpadSupport.shown(drag.folderBase(folder), gap: drag.gap) : folder.apps.map { $0 }
        let columns = min(max(shown.count, 3), 6)
        let rows = max(1, (shown.count + columns - 1) / columns)
        let cardSize = CGSize(width: CGFloat(columns) * Self.cell.width + Self.padding * 2,
                              height: CGFloat(rows) * Self.cell.height + Self.padding * 2)
        ZStack {
            Color.black.opacity(0.22)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
            VStack(spacing: 22) {
                TextField(strings.folderName, text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: 460)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .focused($nameFocused)
                    .onSubmit {
                        service.renameFolder(folder.id, to: name)
                        nameFocused = false
                    }
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 38, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8))
                        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
                    ForEach(shown.indices.compactMap { index in shown[index].map { (index, $0) } }, id: \.1) { index, path in
                        LaunchpadCell(item: .app(path), name: service.name(of: path), iconSize: Self.iconSize,
                                      cellSize: Self.cell, inFolder: true, editing: service.isEditing,
                                      deletable: service.isDeletable(.app(path)))
                            .equatable()
                            .position(x: Self.padding + (CGFloat(index % columns) + 0.5) * Self.cell.width,
                                      y: Self.padding + (CGFloat(index / columns) + 0.5) * Self.cell.height)
                    }
                }
                .frame(width: cardSize.width, height: cardSize.height)
                .animation(.smooth(duration: 0.28), value: drag.gap)
                .background {
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .launchpad)
                        Color.clear
                            .onAppear { report(frame, columns: columns, rows: rows) }
                            .onChange(of: frame) { _, value in report(value, columns: columns, rows: rows) }
                            .onChange(of: columns) { _, value in report(frame, columns: value, rows: rows) }
                    }
                }
            }
        }
        .onAppear {
            name = folder.name
            if service.focusFolderName {
                service.focusFolderName = false
                nameFocused = true
            }
        }
        .onChange(of: folder.id) { _, _ in name = folder.name }
    }

    private func report(_ frame: CGRect, columns: Int, rows: Int) {
        service.folderCardFrame = frame
        service.folderGeometry = LaunchpadGridGeometry(
            origin: CGPoint(x: frame.minX + Self.padding, y: frame.minY + Self.padding),
            cell: Self.cell, columns: columns, rows: rows, iconSize: Self.iconSize)
    }

    private func close() {
        service.renameFolder(folder.id, to: name)
        service.closeFolder()
    }
}

struct LaunchpadCategoryOverlay: View {
    let category: LaunchpadCategory
    @ObservedObject private var service = LaunchpadService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let apps = LaunchpadCategories.shelves(service).first { $0.0 == category }?.1 ?? []
        LaunchpadOverlayCard(onDismiss: { service.openCategory = nil }) {
            VStack(spacing: 20) {
                Text(FeatureStrings.launchpad(l10n.language).title(category))
                    .font(.system(size: 24, weight: .semibold))
                LaunchpadAppList(apps: apps)
            }
        }
    }
}

/// Makes a folder from picked apps, or edits one: its name and which apps
/// it holds. The apps already filed elsewhere move here when picked.
struct LaunchpadFolderEditorView: View {
    @ObservedObject private var service = LaunchpadService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var filter = ""
    @FocusState private var nameFocused: Bool

    private var strings: LaunchpadFeatureStrings { FeatureStrings.launchpad(l10n.language) }

    var body: some View {
        LaunchpadOverlayCard(onDismiss: { service.folderEditor = nil }) {
            VStack(spacing: 14) {
                TextField(strings.folderName, text: binding(\.name))
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .focused($nameFocused)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(strings.searchApps, text: $filter).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: Capsule())
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 16) {
                        ForEach(LaunchpadSupport.search(filter, in: service.sortedApps, name: \.name)) { app in
                            pick(app)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.never)
                HStack {
                    Spacer()
                    Button(strings.cancel) { service.folderEditor = nil }
                        .keyboardShortcut(.cancelAction)
                    Button(strings.done) { service.commitFolderEditor() }
                        .keyboardShortcut(.defaultAction)
                        // A new folder needs two apps; an edit may empty one away.
                        .disabled(service.folderEditor.map { $0.folderID == nil && $0.apps.count < 2 } ?? true)
                }
            }
        }
        .onAppear { nameFocused = true }
    }

    private func pick(_ app: LaunchpadService.App) -> some View {
        let picked = service.folderEditor?.apps.contains(app.path) == true
        return VStack(spacing: 6) {
            LaunchpadAppIcon(path: app.path, size: 48)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(picked ? Color.accentColor : Color.secondary)
                        .background(Circle().fill(.background).padding(2))
                        .offset(x: 6, y: -6)
                }
            Text(app.name)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard var editor = service.folderEditor else { return }
            if picked { editor.apps.removeAll { $0 == app.path } } else { editor.apps.append(app.path) }
            service.folderEditor = editor
        }
    }

    private func binding(_ keyPath: WritableKeyPath<LaunchpadService.FolderEditor, String>) -> Binding<String> {
        Binding(get: { service.folderEditor?[keyPath: keyPath] ?? "" },
                set: { value in service.folderEditor?[keyPath: keyPath] = value })
    }
}

/// The ✕ on a wiggling icon asks first, inside Launchpad, as the iPhone does.
struct LaunchpadDeleteConfirmation: View {
    let path: String
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let strings = FeatureStrings.launchpad(l10n.language)
        let service = LaunchpadService.shared
        ZStack {
            Color.black.opacity(0.3)
                .contentShape(Rectangle())
                .onTapGesture { service.pendingDelete = nil }
            VStack(spacing: 14) {
                LaunchpadAppIcon(path: path, size: 72)
                Text(String(format: strings.deleteTitleFormat, service.name(of: path)))
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(strings.deleteMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button(strings.cancel) { service.pendingDelete = nil }
                        .keyboardShortcut(.cancelAction)
                        .frame(maxWidth: .infinity)
                    Button(strings.moveToTrash, role: .destructive) { service.deleteApp(path) }
                        .keyboardShortcut(.defaultAction)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
            .padding(22)
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }
}
