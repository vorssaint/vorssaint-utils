// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

@MainActor
final class MenuBarOrganizerPanelController {
    enum Kind: Equatable { case search, secondary, group(MenuBarOrganizerGroupReference) }

    private let kind: Kind
    private weak var service: MenuBarOrganizerService?
    private var panel: NSPanel?

    init(kind: Kind, service: MenuBarOrganizerService) {
        self.kind = kind
        self.service = service
    }

    var isVisible: Bool { panel?.isVisible == true }

    func show(anchor: CGRect? = nil) {
        guard let service else { return }
        let content: AnyView
        let size: CGSize
        switch kind {
        case .search:
            content = AnyView(MenuBarOrganizerSearchView(service: service))
            size = CGSize(width: 470, height: 420)
        case .secondary:
            content = AnyView(MenuBarOrganizerSecondaryBarView(service: service))
            let itemCount = max(service.items.filter { $0.section != .visible }.count, 1)
            size = CGSize(width: min(max(CGFloat(itemCount) * 54 + 32, 260), 720), height: 92)
        case .group(let reference):
            content = AnyView(MenuBarOrganizerGroupPanelView(service: service, reference: reference))
            let itemCount = max(service.items(inGroup: reference).count, 1)
            size = CGSize(width: min(max(CGFloat(itemCount) * 58 + 44, 260), 720), height: 98)
        }

        let panel = self.panel ?? makePanel(content: content, size: size)
        panel.contentViewController = NSHostingController(rootView: content)
        panel.setContentSize(size)
        position(panel, anchor: anchor)
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel(content: AnyView, size: CGSize) -> NSPanel {
        let style: NSWindow.StyleMask = kind == .search
            ? [.titled, .fullSizeContentView]
            : [.titled, .fullSizeContentView, .nonactivatingPanel]
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: style,
                            backing: .buffered,
                            defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = kind == .search
        panel.hidesOnDeactivate = kind != .search
        panel.contentViewController = NSHostingController(rootView: content)
        return panel
    }

    private func position(_ panel: NSPanel, anchor: CGRect?) {
        if let anchor, kind != .search {
            let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? .zero
            var origin = CGPoint(x: anchor.midX - panel.frame.width / 2,
                                 y: anchor.minY - panel.frame.height - 6)
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - panel.frame.height - 8)
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }
    }
}

private struct MenuBarOrganizerSearchView: View {
    @ObservedObject var service: MenuBarOrganizerService
    @ObservedObject private var l10n = L10n.shared
    @State private var query = ""
    @State private var selectedID: MenuBarItemIdentity?
    @FocusState private var searchFocused: Bool

    private var text: MenuBarOrganizerStrings {
        FeatureStrings.menuBarOrganizer(l10n.language)
    }

    private var matches: [ManagedMenuBarItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return service.items
        }
        return service.items.compactMap { item -> (ManagedMenuBarItem, Int)? in
            guard let score = MenuBarOrganizerSupport.searchScore(
                displayName: item.displayName,
                bundleIdentifier: item.bundleIdentifier,
                ownerName: item.ownerName,
                title: item.title,
                query: trimmed)
            else { return nil }
            return (item, score)
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.0.frame.minX < $1.0.frame.minX
        }
        .map(\.0)
    }

    private var groupMatches: [MenuBarOrganizerGroupReference] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return service.groupReferencesWithItems().compactMap { reference -> (MenuBarOrganizerGroupReference, Int)? in
            let title = service.title(forGroup: reference)
            guard !trimmed.isEmpty else { return (reference, 0) }
            guard let score = MenuBarOrganizerSupport.searchScore(
                displayName: title,
                bundleIdentifier: "vorssaint.menu-bar.group.\(reference.id)",
                ownerName: title,
                title: text.groupsTitle,
                query: trimmed)
            else { return nil }
            return (reference, score)
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(text.searchPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { activateSelected() }
            }
            .padding(14)
            Divider()
            if matches.isEmpty && groupMatches.isEmpty {
                ContentUnavailableView(text.searchEmptyTitle,
                                       systemImage: "menubar.rectangle",
                                       description: Text(text.searchEmptyCaption))
            } else {
                if !groupMatches.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(groupMatches) { reference in
                                Button {
                                    service.showGroup(reference: reference)
                                } label: {
                                    Label(service.title(forGroup: reference),
                                          systemImage: service.symbolName(forGroup: reference))
                                }
                                .buttonStyle(.bordered)
                                .help(text.groupOpen)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    Divider()
                }
                List(selection: $selectedID) {
                    ForEach(matches) { item in
                        HStack(spacing: 8) {
                        MenuBarOrganizerItemLabel(item: item, showsSection: true)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedID = item.id
                                    service.activate(itemID: item.id)
                                }
                            Button {
                                selectedID = item.id
                                service.reveal(itemID: item.id)
                            } label: {
                                Label(text.searchShow, systemImage: "eye")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .help(text.searchShow)
                            Button {
                                selectedID = item.id
                                service.activate(itemID: item.id)
                            } label: {
                                Label(text.searchOpen, systemImage: "return")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .help(text.searchOpen)
                        }
                        .tag(item.id)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .onAppear {
            service.refresh()
            selectFirstMatch()
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: query) { _, _ in selectFirstMatch() }
        .onChange(of: service.items.count) { _, _ in selectFirstMatch() }
        .onMoveCommand { direction in moveSelection(direction) }
        .onExitCommand { service.closeSearch() }
    }

    private func selectFirstMatch() {
        if let selectedID, matches.contains(where: { $0.id == selectedID }) { return }
        selectedID = matches.first?.id
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !matches.isEmpty else { return }
        let current = selectedID.flatMap { id in matches.firstIndex(where: { $0.id == id }) }
        switch direction {
        case .down:
            selectedID = matches[min((current ?? -1) + 1, matches.count - 1)].id
        case .up:
            selectedID = matches[max((current ?? matches.count) - 1, 0)].id
        default:
            break
        }
    }

    private func activateSelected() {
        guard let selectedID else { return }
        service.activate(itemID: selectedID)
    }

}

private struct MenuBarOrganizerSecondaryBarView: View {
    @ObservedObject var service: MenuBarOrganizerService
    @ObservedObject private var l10n = L10n.shared

    private var text: MenuBarOrganizerStrings {
        FeatureStrings.menuBarOrganizer(l10n.language)
    }

    private var hiddenGroupReferences: [MenuBarOrganizerGroupReference] {
        service.groupReferencesWithItems().filter { reference in
            service.items(inGroup: reference).contains { $0.section != .visible }
        }
    }

    private var ungroupedHiddenItems: [ManagedMenuBarItem] {
        service.items.filter { $0.section != .visible && !service.isGrouped(itemID: $0.id) }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(hiddenGroupReferences) { reference in
                    Button {
                        service.showGroup(reference: reference)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: service.symbolName(forGroup: reference))
                                .font(.system(size: 22))
                            Text(service.title(forGroup: reference))
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(maxWidth: 76)
                        }
                        .padding(6)
                    }
                    .buttonStyle(.plain)
                    .help(text.groupOpen)
                }
                if !hiddenGroupReferences.isEmpty && !ungroupedHiddenItems.isEmpty {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.24))
                        .frame(width: 1, height: 46)
                }
                ForEach(ungroupedHiddenItems) { item in
                    Button {
                        service.activate(itemID: item.id)
                    } label: {
                        VStack(spacing: 4) {
                            MenuBarOrganizerItemIcon(item: item, size: 24)
                            Text(item.ownerName.isEmpty ? item.title : item.ownerName)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(maxWidth: 70)
                        }
                        .padding(6)
                    }
                    .buttonStyle(.plain)
                    .help(item.displayName)
                }
            }
            .padding(12)
        }
        .modifier(MenuBarOrganizerBarChrome())
    }

}

private struct MenuBarOrganizerGroupPanelView: View {
    @ObservedObject var service: MenuBarOrganizerService
    @ObservedObject private var l10n = L10n.shared
    let reference: MenuBarOrganizerGroupReference

    private var text: MenuBarOrganizerStrings {
        FeatureStrings.menuBarOrganizer(l10n.language)
    }

    private var groupItems: [ManagedMenuBarItem] {
        service.items(inGroup: reference)
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                if groupItems.isEmpty {
                    Label(text.groupEmpty, systemImage: "folder.badge.questionmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
                ForEach(groupItems) { item in
                    Button {
                        service.activate(itemID: item.id)
                    } label: {
                        VStack(spacing: 4) {
                            MenuBarOrganizerItemIcon(item: item, size: 24)
                            Text(item.ownerName.isEmpty ? item.title : item.ownerName)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(maxWidth: 72)
                        }
                        .padding(6)
                    }
                    .buttonStyle(.plain)
                    .help(item.displayName)
                }
            }
            .padding(12)
        }
        .modifier(MenuBarOrganizerBarChrome())
    }
}

private struct MenuBarOrganizerBarChrome: ViewModifier {
    @AppStorage(DefaultsKey.menuBarOrganizerBarStyle) private var rawStyle =
        MenuBarOrganizerBarStyle.system.rawValue

    private var style: MenuBarOrganizerBarStyle {
        MenuBarOrganizerBarStyle.sanitized(rawStyle)
    }

    func body(content: Content) -> some View {
        content
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: style == .system ? 0 : 16,
                                        style: .continuous))
            .overlay {
                if style != .system {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.16))
                }
            }
            .shadow(color: style == .system ? .clear : .black.opacity(0.18),
                    radius: 14, x: 0, y: -2)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .system:
            Rectangle().fill(.ultraThinMaterial)
        case .tinted:
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.accentColor.opacity(0.18))
        case .graphite:
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.28))
        case .vibrant:
            LinearGradient(colors: [
                Color.accentColor.opacity(0.34),
                Color.purple.opacity(0.22),
                Color.cyan.opacity(0.18),
            ], startPoint: .leading, endPoint: .trailing)
            .background(.ultraThinMaterial)
        }
    }
}

struct MenuBarOrganizerItemLabel: View {
    let item: ManagedMenuBarItem
    var showsSection = false

    var body: some View {
        HStack(spacing: 10) {
            MenuBarOrganizerItemIcon(item: item, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).lineLimit(1)
                if showsSection {
                    Text(item.section.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !item.isMovable {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MenuBarOrganizerItemIcon: View {
    let item: ManagedMenuBarItem
    let size: CGFloat

    var body: some View {
        Group {
            if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: item.bundleIdentifier.hasPrefix("com.apple.")
                      ? "switch.2" : "app.dashed")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
