// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

@MainActor
final class MenuBarOrganizerPanelController: NSObject, NSWindowDelegate {
    private weak var service: MenuBarOrganizerService?
    private var panel: DrawerPanel?
    private var outsideMonitor: Any?
    var isVisible: Bool { panel?.isVisible == true }

    init(service: MenuBarOrganizerService) { self.service = service }

    func show(anchor: CGRect?, search: Bool) {
        close()
        guard let service else { return }
        let screen = anchor.flatMap { frame in NSScreen.screens.first { $0.frame.intersects(frame) } }
            ?? NSScreen.main
        guard let screen else { return }
        let width = min(620, max(240, screen.visibleFrame.width - 40))
        let height = min(400, screen.visibleFrame.height - 40)
        let frame = CGRect(x: min(screen.visibleFrame.maxX - width - 12,
                                  max(screen.visibleFrame.minX + 12, (anchor?.midX ?? screen.frame.midX) - width / 2)),
                           y: min(screen.visibleFrame.maxY, anchor?.minY ?? screen.visibleFrame.maxY) - height - 8,
                           width: width, height: height)
        let panel = DrawerPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: MenuBarDrawerView(service: service, searchMode: search) { [weak self] in self?.close() })
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
        panel?.orderOut(nil)
        panel?.delegate = nil
        panel = nil
        service?.drawerClosed()
    }

    func windowDidResignKey(_ notification: Notification) { close() }
}

private final class DrawerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct MenuBarDrawerView: View {
    @ObservedObject var service: MenuBarOrganizerService
    @ObservedObject private var l10n = L10n.shared
    let searchMode: Bool
    let close: () -> Void
    @State private var query = ""
    @State private var selected: MenuBarItemIdentity?
    @FocusState private var searchFocused: Bool
    private var text: MenuBarOrganizerStrings { FeatureStrings.menuBarOrganizer(l10n.language) }

    private var matches: [ManagedMenuBarItem] {
        service.items.filter {
            MenuBarOrganizerPolicy.canActivate($0)
                && (searchMode || !query.isEmpty || $0.section != .visible)
        }.compactMap { item -> (ManagedMenuBarItem, Int)? in
            MenuBarOrganizerPolicy.searchScore(query: query, name: item.displayName).map { (item, $0) }
        }.sorted { $0.1 == $1.1 ? $0.0.frame.minX < $1.0.frame.minX : $0.1 < $1.1 }.map(\.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(searchMode ? text.search : text.drawer, systemImage: searchMode ? "magnifyingglass" : "menubar.rectangle")
                    .font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(l10n.s.menuClose)
            }
            TextField(text.placeholder, text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { if let item = matches.first(where: { $0.id == selected }) ?? matches.first { activate(item) } }
            ScrollView {
                if matches.isEmpty {
                    Text(text.empty).foregroundStyle(.secondary).padding(20)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                        ForEach(matches) { item in
                            Button { activate(item) } label: {
                                VStack(spacing: 6) {
                                    MenuBarItemThumbnail(item: item).frame(width: 26, height: 26)
                                    Text(item.displayName).font(.caption).lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .padding(6)
                                .background(selected == item.id ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .disabled(service.isBusy)
                            .help(item.displayName)
                        }
                    }
                }
            }
            if let message = service.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, _ in selected = matches.first?.id }
        .onMoveCommand { direction in
            let offset = direction == .up || direction == .left ? -1 : 1
            guard !matches.isEmpty else { return }
            let index = matches.firstIndex { $0.id == selected } ?? (offset > 0 ? -1 : matches.count)
            selected = matches[min(matches.count - 1, max(0, index + offset))].id
        }
        .onExitCommand(perform: close)
    }

    private func activate(_ item: ManagedMenuBarItem) { close(); service.activate(id: item.id) }
}

struct MenuBarItemThumbnail: View {
    let item: ManagedMenuBarItem
    @ObservedObject private var previews = MenuBarItemPreviewProvider.shared
    var body: some View {
        if let image = previews.images[item.windowID] { Image(nsImage: image).resizable().scaledToFit() }
        else { Image(systemName: "menubar.rectangle").resizable().scaledToFit().foregroundStyle(.secondary) }
    }
}
