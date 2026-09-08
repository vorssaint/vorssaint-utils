// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

// Keep saved positions for features that are not available.
struct StatusItemContextMenuOrderEditor: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.shelfEnabled) private var shelfEnabled = false
    @State private var order = StatusItemContextMenuLayout.order()
    @State private var hiddenItems = StatusItemContextMenuLayout.hiddenItems()
    @State private var dragging: StatusItemContextMenuItemID?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(editableOrder) { id in
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                            Text(id.title(l10n.s))
                                .foregroundStyle(isShown(id) ? .primary : .secondary)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .opacity(dragging == id ? 0.45 : 1)
                        .onDrag {
                            dragging = id
                            return NSItemProvider(object: id.rawValue as NSString)
                        }
                        .onDrop(of: [UTType.text],
                                delegate: StatusItemContextMenuOrderDropDelegate(target: id,
                                                                                  order: $order,
                                                                                  dragging: $dragging))

                        visibilityControl(for: id)
                    }
                    .frame(height: 32)

                    if id != editableOrder.last {
                        Divider()
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .onAppear { reload() }
    }

    private var editableOrder: [StatusItemContextMenuItemID] {
        order.filter { id in
            id.isAvailable && (id != .shelf || shelfEnabled)
        }
    }

    private func isShown(_ id: StatusItemContextMenuItemID) -> Bool {
        !hiddenItems.contains(id) || !id.canHide
    }

    @ViewBuilder
    private func visibilityControl(for id: StatusItemContextMenuItemID) -> some View {
        if id.canHide {
            let shown = isShown(id)
            Button {
                if shown {
                    hiddenItems.insert(id)
                } else {
                    hiddenItems.remove(id)
                }
                StatusItemContextMenuLayout.setHiddenItems(hiddenItems)
            } label: {
                Image(systemName: shown ? "eye.fill" : "eye.slash.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(shown ? Color.accentColor : Color.secondary)
                    .frame(width: 30, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(shown ? l10n.s.statusItemContextMenuHideItem
                        : l10n.s.statusItemContextMenuShowItem)
            .accessibilityLabel(shown ? l10n.s.statusItemContextMenuHideItem
                                      : l10n.s.statusItemContextMenuShowItem)
        } else {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 24)
                .help(l10n.s.statusItemContextMenuAlwaysShown)
                .accessibilityLabel(l10n.s.statusItemContextMenuAlwaysShown)
        }
    }

    private func reload() {
        order = StatusItemContextMenuLayout.order()
        hiddenItems = StatusItemContextMenuLayout.hiddenItems()
    }
}
