// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The combo overlay: where the typed keys lead so far, then every key
/// available at this level with what it does. This is the centered panel;
/// `ComboModeIslandView` and `ComboModeChipView` show the same state in the
/// Dynamic Island and in a pill at the bottom of the screen.
struct ComboModeOverlayView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ComboModeService.shared

    private var strings: ComboModeFeatureStrings { FeatureStrings.comboMode(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            breadcrumb
            if let feedback = service.feedback {
                Text(feedback)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else if service.navigator.currentChildren.isEmpty {
                Text(strings.overlayEmpty)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else {
                VStack(spacing: 2) {
                    ForEach(service.navigator.currentChildren) { node in
                        ComboOverlayRow(node: node)
                    }
                }
            }
            footer
        }
        .padding(14)
        .frame(width: 320)
        .background { HUDBackdrop(cornerRadius: 18, contrast: .high) }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .id(service.presentationID)
    }

    private var breadcrumb: some View {
        ComboBreadcrumb(path: service.navigator.path, title: strings.title)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "keyboard")
                .font(.system(size: 8.5))
            Text(service.trigger?.displayString ?? "")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
            Spacer()
            Text(strings.overlayHint)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.tertiary)
    }
}

/// The feature's mark, then each group typed so far with its key. At the
/// root it names the feature instead.
struct ComboBreadcrumb: View {
    let path: [ComboNode]
    let title: String
    /// The pill keeps every label short so the keys still fit beside it.
    var labelWidth: CGFloat?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: AppFeature.comboMode.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if path.isEmpty || labelWidth == nil {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(path.isEmpty ? .primary : .secondary)
                    .lineLimit(1)
            }
            ForEach(path) { group in
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                ComboKeyCap(key: group.key, compact: true)
                Text(group.label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: labelWidth, alignment: .leading)
                    .fixedSize(horizontal: labelWidth == nil, vertical: false)
            }
            if labelWidth == nil { Spacer(minLength: 0) }
        }
    }
}

/// One key of the current level in a compact surface: its keycap, then
/// what it does in a few words.
private struct ComboHint: View {
    let node: ComboNode
    var iconSize: CGFloat = 14
    var labelWidth: CGFloat?

    var body: some View {
        HStack(spacing: 5) {
            ComboKeyCap(key: node.key, compact: true)
            ComboNodeIcon(node: node, size: iconSize)
            Text(node.displayLabel)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: labelWidth, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What the compact surfaces show below or beside the breadcrumb: the
/// closing message, an empty level, or the level's keys up to `limit`.
private struct ComboHintList<Layout: View>: View {
    let feedback: String?
    let children: [ComboNode]
    let limit: Int
    let emptyText: String
    @ViewBuilder let layout: (_ hints: AnyView) -> Layout

    var body: some View {
        if let feedback {
            Text(feedback)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
        } else if children.isEmpty {
            Text(emptyText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            let window = ComboHintLayout.window(total: children.count, limit: limit)
            layout(AnyView(Group {
                ForEach(children.prefix(window.shown)) { node in
                    ComboHint(node: node, labelWidth: 88)
                }
                if window.more > 0 {
                    Text("+\(window.more)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }))
        }
    }
}

/// Combo mode inside the open Dynamic Island: the breadcrumb, then the
/// level's keys in a short grid, white on the island's black.
struct ComboModeIslandView: View {
    static let width: CGFloat = 340
    /// The breadcrumb and one row, before the content is measured.
    static let minimumHeight: CGFloat = 52

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ComboModeService.shared

    private var strings: ComboModeFeatureStrings { FeatureStrings.comboMode(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ComboBreadcrumb(path: service.navigator.path, title: strings.title)
            ComboHintList(feedback: service.feedback, children: service.navigator.currentChildren,
                          limit: ComboHintLayout.islandLimit, emptyText: strings.overlayEmpty) { hints in
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 3),
                          alignment: .leading, spacing: 6) {
                    hints
                }
            }
            .frame(maxWidth: .infinity, alignment: service.feedback == nil ? .leading : .center)
            Text(strings.overlayHint)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: Self.width)
        .foregroundStyle(.white)
        // The island is black in either appearance; the keycaps and the
        // secondary text follow it.
        .environment(\.colorScheme, .dark)
        .id(service.presentationID)
    }
}

/// Combo mode as a small pill near the bottom of the screen: where the keys
/// lead so far, then the next keys in one row.
struct ComboModeChipView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ComboModeService.shared

    private var strings: ComboModeFeatureStrings { FeatureStrings.comboMode(l10n.language) }

    var body: some View {
        HStack(spacing: 10) {
            ComboBreadcrumb(path: service.navigator.path, title: strings.title, labelWidth: 80)
            Divider().frame(height: 14)
            ComboHintList(feedback: service.feedback, children: service.navigator.currentChildren,
                          limit: ComboHintLayout.chipLimit, emptyText: strings.overlayEmpty) { hints in
                HStack(spacing: 10) { hints }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .fixedSize()
        .background { HUDBackdrop(cornerRadius: 17, contrast: .high) }
        .clipShape(Capsule(style: .continuous))
        .id(service.presentationID)
    }
}

private struct ComboOverlayRow: View {
    let node: ComboNode

    var body: some View {
        HStack(spacing: 9) {
            ComboKeyCap(key: node.key)
            ComboNodeIcon(node: node, size: 18)
            Text(node.displayLabel)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            if node.isGroup {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A key drawn as a small keycap; Space shows as ␣.
struct ComboKeyCap: View {
    let key: String
    var compact = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(ComboKey.display(key))
            .font(.system(size: compact ? 10 : 12, weight: .semibold, design: .monospaced))
            .frame(minWidth: compact ? 16 : 22, minHeight: compact ? 16 : 22)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: compact ? 4 : 5, style: .continuous)
                    .fill(PanelSurface.raisedFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 4 : 5, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.5)
            )
    }
}

/// The app's own icon for an action, the chosen symbol for a group.
struct ComboNodeIcon: View {
    let node: ComboNode
    var size: CGFloat = 18

    var body: some View {
        switch node.content {
        case .group(let symbol, _):
            Image(systemName: symbol)
                .font(.system(size: size * 0.72, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: size, height: size)
        case .action(.openApplication(let app)):
            Image(nsImage: ComboModeService.icon(for: app))
                .resizable()
                .frame(width: size, height: size)
        }
    }
}

extension ComboNode {
    /// The label, or for an app with no label the app's name.
    var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        switch content {
        case .group: return ""
        case .action(.openApplication(let app)): return ComboModeService.name(for: app)
        }
    }
}
