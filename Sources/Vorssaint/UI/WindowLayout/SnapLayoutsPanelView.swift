// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Windows 11 style "Snap Layouts" flyout: a row of mini grid diagrams,
/// dark translucent to match the app's other floating panels (same material
/// pair `RadialMenuView`'s backplate uses). Purely presentational — the
/// CGEvent tap that already drives the window drag computes which cell is
/// under the pointer and writes it into `state`; this view only reflects it,
/// per "UI observes services" (`CONTRIBUTING.md`).
struct SnapLayoutsPanelView: View {
    @ObservedObject var state: SnapLayoutsPanelState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: SnapLayoutPresets.defaultLayout.spacing) {
            ForEach(state.presets) { preset in
                SnapLayoutCardView(preset: preset, highlightedCellIndex: highlightedCellIndex(in: preset))
            }
        }
        .padding(SnapLayoutPresets.defaultLayout.padding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PanelSurface.baseFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(colorScheme == .light ? 0.16 : 0.45), radius: 14, y: 4)
    }

    /// `state.highlighted` names a cell by (preset id, index); a card only
    /// needs the index half once it already knows which preset it is.
    private func highlightedCellIndex(in preset: SnapLayoutPreset) -> Int? {
        guard let highlighted = state.highlighted, highlighted.presetID == preset.id else { return nil }
        return highlighted.index
    }
}

/// One preset's mini grid: as many cells as `preset.zones` has, arranged in
/// `preset.columns` columns, the currently hovered cell picked out in the
/// accent color.
private struct SnapLayoutCardView: View {
    let preset: SnapLayoutPreset
    let highlightedCellIndex: Int?
    @Environment(\.colorScheme) private var colorScheme

    private var rows: Int {
        max(1, Int(ceil(Double(preset.zones.count) / Double(preset.columns))))
    }

    var body: some View {
        let size = SnapLayoutPresets.defaultLayout.cardSize
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<preset.columns, id: \.self) { column in
                        let index = row * preset.columns + column
                        if preset.zones.indices.contains(index) {
                            cell(highlighted: index == highlightedCellIndex)
                        }
                    }
                }
            }
        }
        .padding(6)
        .frame(width: size.width, height: size.height)
        .background(PanelSurface.controlFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func cell(highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(highlighted ? Color.accentColor : PanelSurface.cardFill(for: colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(highlighted ? Color.accentColor : PanelSurface.border(for: colorScheme),
                                 lineWidth: 0.8)
            )
    }
}
