// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The shelf docked under the menu bar icon. It is a single thing in one place:
/// a small pill when idle, the full shelf card when opened or when a drag needs
/// a target. It shrinks and grows in place, never a second window and never a
/// new menu bar icon. Shown and hidden by ShelfService.
struct DockedShelfView: View {
    @EnvironmentObject private var shelf: ShelfService
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        // No open/close animation on purpose: the panel resize and the SwiftUI
        // content swap cannot be kept in step, and half-synced frames lag.
        Group {
            if shelf.dockedExpanded {
                ShelfView(dismissSystemImage: "chevron.up",
                          dismissHelp: l10n.s.shelfCollapse,
                          onDismiss: { shelf.collapseDocked() },
                          onAccept: { shelf.dockDidAccept() },
                          brandWatermark: true)
            } else {
                ShelfPill()
            }
        }
    }
}

/// The collapsed shelf: a discreet capsule with the brand mark, the item count
/// and a chevron to expand. It is also a drop target, so a file dropped on the
/// pill lands in the shelf just the same.
private struct ShelfPill: View {
    @EnvironmentObject private var shelf: ShelfService
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 7) {
            leadingGlyph
            if shelf.itemCount > 0 {
                Text("\(shelf.itemCount)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .opacity(hovered || shelf.dropTargeted ? 1 : 0.55)
        }
        .padding(.horizontal, shelf.itemCount > 0 ? 12 : 11)
        .padding(.vertical, 8)
        .background(
            ZStack {
                HUDBackdrop(cornerRadius: 13)
                WindowMoveHandle(acceptsDrops: true) { shelf.dockDidAccept() }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(shelf.dropTargeted ? Color.accentColor : Color.white.opacity(0.12),
                              lineWidth: shelf.dropTargeted ? 2 : 1)
        )
        .scaleEffect(shelf.dropTargeted ? 1.06 : 1)
        .shadow(color: shelf.dropTargeted ? Color.accentColor.opacity(0.32) : Color.black.opacity(0.16),
                radius: shelf.dropTargeted ? 12 : 7, x: 0, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onHover { hovered = $0 }
        .onTapGesture { shelf.expandDocked() }
        .help(l10n.s.shelfOpenNow)
        .animation(.easeOut(duration: 0.13), value: shelf.dropTargeted)
        .animation(.easeOut(duration: 0.15), value: shelf.dockedJustCaught)
        .padding(8)
    }

    /// The Vorssaint mark, quiet, so the pill is unmistakably the app's; it
    /// flips to a green tick for a beat right after a catch.
    @ViewBuilder
    private var leadingGlyph: some View {
        if shelf.dockedJustCaught {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        } else {
            BrandMark(width: 15, tint: colorScheme == .light ? Color(white: 0.16) : .white)
                .opacity(0.85)
        }
    }
}
