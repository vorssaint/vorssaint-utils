// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The shelf docked under the menu bar icon or at the top center of the
/// screen. It is a single thing in one place:
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
                          brandWatermark: true)
            } else if shelf.dockedPlacement == .topCenter {
                ShelfTopCenterBadge()
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
    private var targeted: Bool { shelf.dropTargeted }
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
                .opacity(hovered || targeted ? 1 : 0.55)
        }
        .padding(.horizontal, shelf.itemCount > 0 ? 12 : 11)
        .padding(.vertical, 8)
        .background(HUDBackdrop(cornerRadius: 13))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : Color.white.opacity(0.12),
                              lineWidth: targeted ? 2 : 1)
        )
        .scaleEffect(targeted ? 1.06 : 1)
        .shadow(color: targeted ? Color.accentColor.opacity(0.32) : Color.black.opacity(0.16),
                radius: targeted ? 12 : 7, x: 0, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onHover { hovered = $0 }
        .onTapGesture { shelf.expandDocked() }
        .help(l10n.s.shelfOpenNow)
        .animation(.easeOut(duration: 0.13), value: targeted)
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

/// The collapsed shelf docked at the top center of the screen: a solid badge
/// that names the shelf, since there is no menu bar icon above to explain it.
/// A drop on it lands in the shelf, like on the pill.
private struct ShelfTopCenterBadge: View {
    @EnvironmentObject private var shelf: ShelfService
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    private var targeted: Bool { shelf.dropTargeted }
    @State private var hovered = false

    var body: some View {
        let foreground = colorScheme == .dark ? Color.white : Color(white: 0.12)
        HStack(spacing: 8) {
            if shelf.dockedJustCaught {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                BrandMark(width: 18, tint: foreground)
            }
            Text(l10n.s.shelfTitle)
                .font(.system(.callout, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 150, alignment: .leading)
            if shelf.itemCount > 0 {
                Text("\(shelf.itemCount)")
                    .font(.system(.subheadline, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(foreground.opacity(0.08), in: Capsule())
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .opacity(hovered || targeted ? 1 : 0.7)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.96),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : foreground.opacity(hovered ? 0.3 : 0.15),
                              lineWidth: targeted ? 2 : 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.12), radius: 5, x: 0, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onHover { hovered = $0 }
        .onTapGesture { shelf.expandDocked() }
        .help(l10n.s.shelfOpenNow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.s.shelfTitle)
        .accessibilityValue("\(shelf.itemCount)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { shelf.expandDocked() }
        .padding(8)
    }
}
