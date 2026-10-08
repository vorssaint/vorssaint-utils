// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The screen map of the drop areas. Each area draws where it puts the window,
/// and a click opens its menu: on or off, which placement, and for an edge
/// how many areas it is split into.
struct WindowEdgeSnapZonePicker: View {
    @Binding var disabledZonesStorage: String
    @Binding var zoneActionsStorage: String
    let text: WindowLayoutFeatureStrings
    let resetTitle: String
    var compact = false

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 6 : 9) {
            VStack(spacing: cellSpacing) {
                zoneRow(left: .topLeft, center: .top, right: .topRight,
                        height: compact ? 36 : 50)
                zoneRow(left: .left, center: nil, right: .right,
                        height: sideRowHeight)
                zoneRow(left: .bottomLeft, center: .bottom, right: .bottomRight,
                        height: compact ? 36 : 50)
            }
            .padding(compact ? 5 : 7)
            .frame(width: compact ? 258 : 340)
            .background(
                RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                    .fill(Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14))
            )

            Button {
                disabledZonesStorage = ""
                zoneActionsStorage = ""
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                    )
            }
            .buttonStyle(.plain)
            .disabled(isStandard)
            .opacity(isStandard ? 0.35 : 1)
            .help(resetTitle)
            .accessibilityLabel(resetTitle)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.14), value: disabledZonesStorage)
        .animation(.easeInOut(duration: 0.14), value: zoneActionsStorage)
    }

    private var cellSpacing: CGFloat { compact ? 4 : 5 }
    private var partSpacing: CGFloat { compact ? 2 : 3 }
    private var sideCellWidth: CGFloat { compact ? 56 : 78 }

    /// The side edges grow with the areas stacked on them, so each area keeps
    /// room for its drawing.
    private var sideRowHeight: CGFloat {
        let parts = CGFloat(max(layout.actions(for: .left).count, layout.actions(for: .right).count))
        let stacked = parts * (compact ? 16 : 22) + (parts - 1) * partSpacing
        return max(compact ? 44 : 62, stacked)
    }

    private var disabledZones: Set<WindowEdgeSnapZone> {
        WindowEdgeSnapZone.disabledZones(from: disabledZonesStorage)
    }

    private var layout: WindowEdgeSnapLayout {
        WindowEdgeSnapLayout(storageValue: zoneActionsStorage)
    }

    private var isStandard: Bool {
        disabledZones.isEmpty && layout == .standard
    }

    private func zoneRow(left: WindowEdgeSnapZone,
                         center: WindowEdgeSnapZone?,
                         right: WindowEdgeSnapZone,
                         height: CGFloat) -> some View {
        HStack(spacing: cellSpacing) {
            zoneCell(left)
                .frame(width: sideCellWidth)
            if let center {
                zoneCell(center)
                    .frame(maxWidth: .infinity)
            } else {
                RoundedRectangle(cornerRadius: compact ? 5 : 7, style: .continuous)
                    .fill(Color.primary.opacity(0.018))
                    .overlay {
                        Image(systemName: "cursorarrow.motionlines")
                            .font(.system(size: compact ? 11 : 14, weight: .medium))
                            .foregroundStyle(.quaternary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
            zoneCell(right)
                .frame(width: sideCellWidth)
        }
        .frame(height: height)
    }

    /// One zone: a single area, or the areas of a split edge side by side
    /// along the top and bottom and stacked along the sides.
    private func zoneCell(_ zone: WindowEdgeSnapZone) -> some View {
        let isOn = !disabledZones.contains(zone)
        let actions = layout.actions(for: zone)
        let place = zoneName(zone)
        let areas = ForEach(actions.indices, id: \.self) { part in
            WindowEdgeSnapAreaButton(action: actions[part],
                                     isOn: isOn,
                                     // Areas of a split edge also say which one they are.
                                     place: actions.count > 1 ? "\(place) \(part + 1)/\(actions.count)" : place,
                                     title: actions[part].title(text),
                                     compact: compact) {
                menu(for: zone, part: part)
            }
        }
        return Group {
            if zone.isVerticalEdge {
                VStack(spacing: partSpacing) { areas }
            } else {
                HStack(spacing: partSpacing) { areas }
            }
        }
        .overlay(alignment: .topTrailing) {
            if !isOn {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: compact ? 7 : 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(compact ? 3 : 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Where the zone sits on the map, named like the same spot on the
    /// screenshot watermark's grid of positions, so VoiceOver tells apart two
    /// areas that hold the same placement.
    private func zoneName(_ zone: WindowEdgeSnapZone) -> String {
        let positions = FeatureStrings.screenshot(l10n.language)
        switch zone {
        case .topLeft: return positions.watermarkPositionTopLeading
        case .top: return positions.watermarkPositionTop
        case .topRight: return positions.watermarkPositionTopTrailing
        case .left: return positions.watermarkPositionLeading
        case .right: return positions.watermarkPositionTrailing
        case .bottomLeft: return positions.watermarkPositionBottomLeading
        case .bottom: return positions.watermarkPositionBottom
        case .bottomRight: return positions.watermarkPositionBottomTrailing
        }
    }

    private func menu(for zone: WindowEdgeSnapZone, part: Int) -> [WindowEdgeSnapMenuEntry] {
        let isOn = !disabledZones.contains(zone)
        let actions = layout.actions(for: zone)
        let current = actions[part]
        // A split edge turns on and off as a whole, so the switch names the
        // edge rather than the area that opened the menu.
        let useTitle = zone.maximumParts > 1 ? text.edgeSnapUseEdge : text.edgeSnapUseCorner
        var entries: [WindowEdgeSnapMenuEntry] = [
            .item(useTitle, checked: isOn) { setZone(zone, on: !isOn) },
            .separator,
        ]
        for group in WindowEdgeSnapPlacementGroup.allCases {
            let items = group.actions.map { action in
                WindowEdgeSnapMenuEntry.item(action.title(text), checked: action == current) {
                    choose(action, for: zone, part: part)
                }
            }
            if group == .other {
                entries += items
            } else {
                entries.append(.submenu(group.title(text), checked: group.actions.contains(current), items))
            }
        }
        if zone.maximumParts > 1 {
            entries.append(.separator)
            let counts = (1...zone.maximumParts).map { count in
                WindowEdgeSnapMenuEntry.item("\(count)", checked: count == actions.count) {
                    split(zone, into: count)
                }
            }
            entries.append(.submenu(text.edgeSnapAreasOnEdge, checked: false, counts))
        }
        return entries
    }

    /// Choosing a placement for an area that is off also turns it on.
    private func choose(_ action: WindowLayoutAction, for zone: WindowEdgeSnapZone, part: Int) {
        var layout = layout
        layout.setAction(action, for: zone, part: part)
        zoneActionsStorage = layout.storageValue
        setZone(zone, on: true)
    }

    private func split(_ zone: WindowEdgeSnapZone, into count: Int) {
        var layout = layout
        layout.setPartCount(count, for: zone)
        zoneActionsStorage = layout.storageValue
        setZone(zone, on: true)
    }

    private func setZone(_ zone: WindowEdgeSnapZone, on: Bool) {
        var disabled = disabledZones
        if on {
            disabled.remove(zone)
        } else {
            disabled.insert(zone)
        }
        disabledZonesStorage = WindowEdgeSnapZone.disabledZonesStorageValue(disabled)
    }
}

/// One drop area on the map. It draws where its placement puts the window and
/// opens the area's menu when clicked.
private struct WindowEdgeSnapAreaButton: View {
    let action: WindowLayoutAction
    let isOn: Bool
    let place: String
    let title: String
    let compact: Bool
    let menu: () -> [WindowEdgeSnapMenuEntry]

    @State private var hovered = false
    @State private var anchor = WindowEdgeSnapMenuAnchor()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 5 : 7, style: .continuous)
        Button {
            anchor.popUp(menu())
            // The open menu takes the pointer's moves, so the area would keep
            // its hover after the pointer left it to pick an item.
            hovered = false
        } label: {
            ZStack {
                shape
                    .fill(isOn
                        ? Color.accentColor.opacity(hovered ? 0.2 : 0.13)
                        : Color.primary.opacity(hovered ? 0.065 : 0.025))
                shape
                    .strokeBorder(isOn
                        ? Color.accentColor.opacity(hovered ? 0.65 : 0.42)
                        : Color.primary.opacity(hovered ? 0.2 : 0.09))
                WindowEdgeSnapPlacementGlyph(action: action, compact: compact)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.45))
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background(WindowEdgeSnapMenuAnchorView(anchor: anchor))
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.1)) { hovered = inside }
        }
        .help(title)
        .accessibilityLabel("\(place): \(title)")
        .accessibilityValue(isOn ? "1" : "0")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A small screen with the placement filled in, so every choice on the map
/// reads apart, the ones that share a symbol elsewhere included.
private struct WindowEdgeSnapPlacementGlyph: View {
    let action: WindowLayoutAction
    let compact: Bool

    var body: some View {
        let size = compact ? CGSize(width: 18, height: 12) : CGSize(width: 24, height: 16)
        let inset: CGFloat = compact ? 2 : 2.5
        let inner = CGSize(width: size.width - inset * 2, height: size.height - inset * 2)
        let placement = WindowEdgeSnapLayout.previewRect(for: action)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: compact ? 2 : 2.5, style: .continuous)
                .strokeBorder(lineWidth: 1)
                .opacity(0.55)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .frame(width: max(1.5, placement.width * inner.width),
                       height: max(1.5, placement.height * inner.height))
                .offset(x: inset + placement.minX * inner.width,
                        y: inset + placement.minY * inner.height)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

private enum WindowEdgeSnapMenuEntry {
    case item(String, checked: Bool, perform: () -> Void)
    case submenu(String, checked: Bool, [WindowEdgeSnapMenuEntry])
    case separator
}

/// Opens an area's menu right under the area. AppKit draws the menu, so the
/// area keeps its own drawing on every supported macOS.
private final class WindowEdgeSnapMenuAnchor: NSObject {
    weak var view: NSView?
    private var handlers: [() -> Void] = []

    func popUp(_ entries: [WindowEdgeSnapMenuEntry]) {
        guard let view else { return }
        handlers = []
        makeMenu(entries).popUp(positioning: nil, at: .zero, in: view)
    }

    private func makeMenu(_ entries: [WindowEdgeSnapMenuEntry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .item(let title, let checked, let perform):
                let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.tag = handlers.count
                item.state = checked ? .on : .off
                handlers.append(perform)
                menu.addItem(item)
            case .submenu(let title, let checked, let children):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.state = checked ? .on : .off
                item.submenu = makeMenu(children)
                menu.addItem(item)
            }
        }
        return menu
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard handlers.indices.contains(sender.tag) else { return }
        handlers[sender.tag]()
    }
}

private struct WindowEdgeSnapMenuAnchorView: NSViewRepresentable {
    let anchor: WindowEdgeSnapMenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

struct WindowGestureModifierPicker: View {
    @Binding var storageValue: String
    var title: String?
    var compact = false

    private struct ModifierChoice: Identifiable {
        let modifier: GlobalShortcutModifiers
        let symbol: String
        let name: String
        var id: String { name }
    }

    private let choices: [ModifierChoice] = [
        ModifierChoice(modifier: .control, symbol: "⌃", name: "Control"),
        ModifierChoice(modifier: .option, symbol: "⌥", name: "Option"),
        ModifierChoice(modifier: .command, symbol: "⌘", name: "Command"),
    ]

    var body: some View {
        HStack(spacing: compact ? 5 : 7) {
            if let title {
                Text(title)
                    .font(compact ? .system(size: 10, weight: .medium) : .body)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
            }
            ForEach(choices) { choice in
                let selected = modifiers.contains(choice.modifier)
                Button {
                    toggle(choice.modifier)
                } label: {
                    Text(choice.symbol)
                        .font(.system(size: compact ? 12 : 14, weight: .semibold, design: .rounded))
                        .frame(width: compact ? 25 : 30, height: compact ? 22 : 25)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(selected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.1),
                                        lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(selected && !canRemove(choice.modifier))
                .help(choice.name)
                .accessibilityLabel(choice.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var modifiers: GlobalShortcutModifiers {
        WindowGestureSupport.modifiers(from: storageValue)
    }

    private func toggle(_ modifier: GlobalShortcutModifiers) {
        var next = modifiers
        if next.contains(modifier) {
            next.remove(modifier)
        } else {
            next.insert(modifier)
        }
        // At least one deliberate modifier stays selected. Shift is reserved
        // for the resize variant and is shown in the action hint below.
        guard next.hasPrimaryModifier else { return }
        storageValue = WindowGestureSupport.storageValue(for: next)
    }

    private func canRemove(_ modifier: GlobalShortcutModifiers) -> Bool {
        var remaining = modifiers
        remaining.remove(modifier)
        return remaining.hasPrimaryModifier
    }
}

struct WindowGestureHints: View {
    let modifierStorage: String
    let moveText: String
    let resizeText: String
    var compact = false

    @ViewBuilder
    var body: some View {
        if compact {
            VStack(spacing: 4) {
                hint(moveText, isMove: true)
                hint(resizeText, isMove: false)
            }
        } else {
            HStack(spacing: 9) {
                hint(moveText, isMove: true)
                hint(resizeText, isMove: false)
            }
        }
    }

    private var chord: String {
        WindowGestureSupport.modifiers(from: modifierStorage).keyCaps.joined()
    }

    private var resizeChord: String {
        WindowGestureSupport.resizeModifiers(
            from: WindowGestureSupport.modifiers(from: modifierStorage)
        ).keyCaps.joined()
    }

    private func hint(_ text: String, isMove: Bool) -> some View {
        HStack(spacing: compact ? 3 : 5) {
            Text(isMove ? chord : resizeChord)
                .font(.system(size: compact ? 9.5 : 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Image(systemName: isMove
                    ? "arrow.up.and.down.and.arrow.left.and.right"
                    : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: compact ? 15 : 17, height: compact ? 15 : 17)
                .accessibilityHidden(true)
            Text(text)
                .font(compact ? .system(size: 9.5, weight: .medium) : .caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 4 : 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .accessibilityElement(children: .combine)
    }
}
