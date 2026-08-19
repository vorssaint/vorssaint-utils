// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

@MainActor
final class MenuBarOrganizerPanelController {
    private weak var service: MenuBarOrganizerService?
    private var panel: NSPanel?

    init(service: MenuBarOrganizerService) {
        self.service = service
    }

    var isVisible: Bool { panel?.isVisible == true }

    func show(anchor: CGRect?) {
        guard let service else { return }
        let hiddenCount = max(service.items.filter { $0.section != .visible }.count, 1)
        let size = CGSize(width: min(max(CGFloat(hiddenCount) * 62 + 32, 260), 720),
                          height: 94)
        let content = MenuBarOrganizerSecondaryBarView(service: service)
        let panel = self.panel ?? makePanel(size: size)
        panel.contentViewController = NSHostingController(rootView: content)
        panel.setContentSize(size)
        position(panel, anchor: anchor)
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel(size: CGSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = true
        return panel
    }

    private func position(_ panel: NSPanel, anchor: CGRect?) {
        guard let anchor else {
            panel.center()
            return
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var origin = CGPoint(x: anchor.midX - panel.frame.width / 2,
                             y: anchor.minY - panel.frame.height - 6)
        origin.x = min(max(origin.x, visible.minX + 8),
                       visible.maxX - panel.frame.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8),
                       visible.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(origin)
    }
}

private struct MenuBarOrganizerSecondaryBarView: View {
    @ObservedObject var service: MenuBarOrganizerService
    @ObservedObject private var l10n = L10n.shared

    private var hiddenItems: [ManagedMenuBarItem] {
        service.items.filter { $0.section != .visible }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                if hiddenItems.isEmpty {
                    Label(FeatureStrings.menuBarOrganizer(l10n.language).emptySection,
                          systemImage: "menubar.rectangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
                ForEach(hiddenItems) { item in
                    Button {
                        service.activate(itemID: item.id)
                    } label: {
                        VStack(spacing: 4) {
                            MenuBarOrganizerItemIcon(item: item, size: 24)
                            Text(item.sourceName.isEmpty ? item.title : item.sourceName)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(maxWidth: 78)
                        }
                        .padding(6)
                    }
                    .buttonStyle(.plain)
                    .help(item.displayName)
                }
            }
            .padding(12)
        }
        .background(.ultraThinMaterial)
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
            if item.identityState == .provisional {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if !item.isMovable {
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
