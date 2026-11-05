// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Edits one display at a time. A UUID, rather than its place in NSScreen.screens,
/// keeps the saved zones attached when monitors are rearranged or reconnected.
struct WindowCustomZoneEditor: View {
    @ObservedObject private var l10n = L10n.shared
    let screen: NSScreen
    @Binding var storageValue: String
    @State private var selectedIndex = 0

    private var text: WindowCustomZoneStrings { .localized(l10n.language) }
    private var displayID: String { WindowCustomZoneLayouts.id(for: screen) }
    private var aspectRatio: CGFloat {
        screen.visibleFrame.width / max(screen.visibleFrame.height, 1)
    }
    private var zones: [WindowCustomZone] {
        WindowCustomZoneLayouts(storageValue: storageValue)
            .zones(for: displayID, aspectRatio: aspectRatio)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(screen.localizedName, systemImage: "display")
                    .font(.headline)
                Spacer()
                Menu(text.preset) {
                    Button(text.twoColumns) { save(WindowCustomZoneLayouts.columns(2)) }
                    Button(text.threeColumns) { save(WindowCustomZoneLayouts.columns(3)) }
                    Button(text.fourColumns) { save(WindowCustomZoneLayouts.columns(4)) }
                    Button(text.fourTiles) { save(WindowCustomZoneLayouts.grid(columns: 2, rows: 2)) }
                    Button(text.sixTiles) { save(WindowCustomZoneLayouts.grid(columns: 3, rows: 2)) }
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.09))
                    ForEach(zones.indices, id: \.self) { index in
                        let zone = zones[index]
                        let tile = CGRect(x: zone.x * geometry.size.width,
                                          y: zone.y * geometry.size.height,
                                          width: zone.width * geometry.size.width,
                                          height: zone.height * geometry.size.height)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.accentColor.opacity(index == selectedIndex ? 0.38 : 0.14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Color.accentColor.opacity(index == selectedIndex ? 1 : 0.6),
                                                  lineWidth: index == selectedIndex ? 2 : 1)
                            }
                            .overlay {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                            }
                            .frame(width: max(1, tile.width - 4), height: max(1, tile.height - 4))
                            .position(x: tile.midX, y: tile.midY)
                            .onTapGesture { selectedIndex = index }
                            .accessibilityLabel(String(format: text.editTile, index + 1))
                    }
                }
            }
            .frame(maxWidth: 440)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .accessibilityLabel(String(format: text.tilePreview, screen.localizedName))

            HStack {
                Picker(text.tile, selection: $selectedIndex) {
                    ForEach(zones.indices, id: \.self) { index in
                        Text("\(index + 1)").tag(index)
                    }
                }
                .frame(width: 130)
                Spacer()
                Button(text.addTile) {
                    // New zones have priority while overlapping an existing tile.
                    save([WindowCustomZone(x: 0.25, y: 0.25, width: 0.5, height: 0.5)] + zones)
                    selectedIndex = 0
                }
                .disabled(zones.count >= 16)
                Button(text.remove) {
                    guard zones.count > 1, zones.indices.contains(selectedIndex) else { return }
                    var changed = zones
                    changed.remove(at: selectedIndex)
                    save(changed)
                    selectedIndex = min(selectedIndex, changed.count - 1)
                }
                .disabled(zones.count <= 1)
            }
            if zones.indices.contains(selectedIndex) {
                VStack(spacing: 6) {
                    coordinate(text.left, keyPath: \.x)
                    coordinate(text.top, keyPath: \.y)
                    coordinate(text.width, keyPath: \.width)
                    coordinate(text.height, keyPath: \.height)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func coordinate(_ label: String,
                            keyPath: WritableKeyPath<WindowCustomZone, Double>) -> some View {
        HStack {
            Text(label).frame(width: 54, alignment: .leading)
            Slider(value: binding(for: keyPath), in: 0...100, step: 1)
            Text("\(Int((zones[selectedIndex][keyPath: keyPath] * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func binding(for keyPath: WritableKeyPath<WindowCustomZone, Double>) -> Binding<Double> {
        Binding(
            get: { zones.indices.contains(selectedIndex)
                ? zones[selectedIndex][keyPath: keyPath] * 100 : 0 },
            set: { percent in
                var changed = zones
                guard changed.indices.contains(selectedIndex) else { return }
                var zone = changed[selectedIndex]
                let fraction = min(max(percent / 100, 0), 1)
                zone[keyPath: keyPath] = fraction
                if keyPath == \.x { zone.x = min(zone.x, 1 - zone.width) }
                if keyPath == \.y { zone.y = min(zone.y, 1 - zone.height) }
                if keyPath == \.width { zone.width = max(0.05, min(zone.width, 1 - zone.x)) }
                if keyPath == \.height { zone.height = max(0.05, min(zone.height, 1 - zone.y)) }
                guard zone.isValid else { return }
                changed[selectedIndex] = zone
                save(changed)
            })
    }

    private func save(_ zones: [WindowCustomZone]) {
        var layouts = WindowCustomZoneLayouts(storageValue: storageValue)
        layouts.set(zones, for: displayID)
        storageValue = layouts.storageValue
        selectedIndex = min(selectedIndex, zones.count - 1)
        WindowLayoutService.shared.refreshCustomZoneOverlays()
    }
}
