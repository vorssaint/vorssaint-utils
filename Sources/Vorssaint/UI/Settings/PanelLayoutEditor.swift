// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

/// Arranges the menu bar panel against a miniature of it: one row per
/// section with its icon, what it shows and a switch, dragged into the order
/// the panel's tabs follow. The miniature redraws from the same saved order
/// and visibility keys the live panel observes, so what it shows is what
/// the next click on the menu bar icon opens. Pointing at a row lights its
/// tab in the miniature, which is how an icon gets its name.
struct PanelLayoutEditor: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.panelShowFanControl) private var showFanControl = true
    @AppStorage(DefaultsKey.brightnessControlEnabled) private var brightnessEnabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var order: [PanelSectionID] = PanelLayout.order
    @State private var dragging: PanelSectionID?
    @State private var selected: PanelSectionID?
    @State private var hovered: PanelSectionID?
    /// Bumped whenever a section is shown or hidden so the miniature and the
    /// "can't hide the last one" guard recompute.
    @State private var visibilityChanges = 0

    private var text: GeneralSettingsStrings { FeatureStrings.generalSettings(l10n.language) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                miniature
                rows
                    .frame(minWidth: 300, idealWidth: 320, maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 16) {
                miniature
                rows
            }
        }
        .onAppear { order = PanelLayout.order }
        .onChange(of: showFanControl) { _, _ in order = PanelLayout.order }
    }

    /// The picture with its one-line caption under it.
    private var miniature: some View {
        VStack(alignment: .leading, spacing: 10) {
            MenuBarPanelMiniature(sections: visibleSections, active: previewSection) { id in
                selected = id
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: visibleSections)
            Text(text.panelReorderHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: MenuBarPanelMiniature.width)
    }

    private var rows: some View {
        let ids = editableOrder
        return VStack(spacing: 0) {
            ForEach(ids) { id in
                PanelSectionRow(id: id,
                                title: id.title(l10n.s),
                                description: id.description(text),
                                isActive: previewSection == id,
                                isHovered: hovered == id,
                                isDragging: dragging == id,
                                // Fan Control is governed by its own toggle on
                                // Monitor, so it has no separate show/hide here.
                                showsSwitch: id != .fanControl,
                                // Keep at least one section visible.
                                canHide: visibleSections.count > 1,
                                dragProvider: {
                                    dragging = id
                                    return NSItemProvider(object: id.rawValue as NSString)
                                },
                                onSelect: { selected = id },
                                onHover: { inside in
                                    if inside {
                                        hovered = id
                                    } else if hovered == id {
                                        hovered = nil
                                    }
                                },
                                onVisibilityChange: { visibilityChanges += 1 })
                    .onDrop(of: [UTType.text],
                            delegate: PanelOrderDropDelegate(target: id, order: $order, dragging: $dragging))
                if id != ids.last {
                    Divider().padding(.leading, 68)
                }
            }
        }
    }

    private var editableOrder: [PanelSectionID] {
        order.filter {
            $0.isAvailable
                && ($0 != .fanControl || showFanControl)
                && ($0 != .brightness || brightnessEnabled)
        }
    }

    /// The tabs the panel would show right now, in order.
    private var visibleSections: [PanelSectionID] {
        _ = visibilityChanges
        return editableOrder.filter(PanelLayout.isVisibleInPanel)
    }

    /// The tab the miniature opens: the row under the pointer, else the one
    /// last clicked, else the panel's own first tab. A hidden section has no
    /// tab to open, so it falls through.
    private var previewSection: PanelSectionID? {
        let visible = visibleSections
        return [hovered, selected].compactMap { $0 }.first { visible.contains($0) } ?? visible.first
    }
}

private extension PanelSectionID {
    func description(_ text: GeneralSettingsStrings) -> String {
        switch self {
        case .keepAwake: return text.sectionKeepAwake
        case .brightness: return text.sectionDisplays
        case .mixer: return text.sectionMixer
        case .system: return text.sectionSystem
        case .network: return text.sectionNetwork
        case .disk: return text.sectionDisks
        case .power: return text.sectionPower
        case .fanControl: return text.sectionFanControl
        case .utilities: return text.sectionUtilities
        case .controls: return text.sectionControls
        case .toggles: return text.sectionToggles
        case .wallpaper: return FeatureStrings.wallpaper(L10n.shared.language).panelDescription
        }
    }
}

/// One section of the panel: drag handle, icon, name, what it shows, and the
/// switch backed by that section's own visibility key so the live panel
/// updates immediately.
private struct PanelSectionRow: View {
    let id: PanelSectionID
    let title: String
    let description: String
    let isActive: Bool
    let isHovered: Bool
    let isDragging: Bool
    let showsSwitch: Bool
    let canHide: Bool
    let dragProvider: () -> NSItemProvider
    let onSelect: () -> Void
    let onHover: (Bool) -> Void
    let onVisibilityChange: () -> Void
    @AppStorage private var shown: Bool

    init(id: PanelSectionID, title: String, description: String, isActive: Bool, isHovered: Bool,
         isDragging: Bool, showsSwitch: Bool, canHide: Bool, dragProvider: @escaping () -> NSItemProvider,
         onSelect: @escaping () -> Void, onHover: @escaping (Bool) -> Void,
         onVisibilityChange: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.description = description
        self.isActive = isActive
        self.isHovered = isHovered
        self.isDragging = isDragging
        self.showsSwitch = showsSwitch
        self.canHide = canHide
        self.dragProvider = dragProvider
        self.onSelect = onSelect
        self.onHover = onHover
        self.onVisibilityChange = onVisibilityChange
        _shown = AppStorage(wrappedValue: id.shownByDefault, id.visibilityKey)
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
                Image(systemName: id.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(shown ? Color.accentColor : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background((shown ? Color.accentColor : Color.secondary).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(shown ? .primary : .secondary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onDrag(dragProvider)
            if showsSwitch {
                Toggle(title, isOn: $shown)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(shown && !canHide)
                    .onChange(of: shown) { _, _ in onVisibilityChange() }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(rowFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .opacity(isDragging ? 0.45 : 1)
        .onHover(perform: onHover)
        .onTapGesture(perform: onSelect)
    }

    private var rowFill: Color {
        if isActive { return Color.accentColor.opacity(0.10) }
        return isHovered ? Color.primary.opacity(0.04) : Color.clear
    }
}

/// A small, faithful picture of the corner of the screen: the menu bar with
/// the app's icon, and the panel hanging from it with its tab strip in the
/// current order. Nothing in it is fake data; the open tab is a title over
/// placeholder lines.
private struct MenuBarPanelMiniature: View {
    let sections: [PanelSectionID]
    let active: PanelSectionID?
    let onSelect: (PanelSectionID) -> Void
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme

    static let width: CGFloat = 232
    private static let padding: CGFloat = 8
    private static let arrowHeight: CGFloat = 7
    /// The glyph's center measured from the right edge, so the popover's
    /// arrow points at it.
    private static let glyphCenterFromTrailing: CGFloat = 12 + 10

    var body: some View {
        VStack(spacing: 2) {
            menuBar
            panel
        }
        .frame(width: Self.width)
        .accessibilityElement(children: .contain)
    }

    private var menuBar: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "wifi")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.5))
            if PowerSampler.hasInternalBattery {
                Image(systemName: "battery.75")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            MenuBarGlyph()
                .frame(width: 20, height: 15)
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                // The item stays highlighted while its panel is open.
                .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(.horizontal, -3)
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    private var panel: some View {
        VStack(spacing: 8) {
            BrandMark(width: 32, tint: colorScheme == .light ? Color(white: 0.03) : .white)
                .frame(height: 18)
                .accessibilityHidden(true)
            tabStrip
            openTab
            footer
        }
        .padding(Self.padding)
        .padding(.top, Self.arrowHeight)
        .background {
            let bubble = PopoverBubble(cornerRadius: 12, arrowWidth: 14, arrowHeight: Self.arrowHeight,
                                       arrowCenterFromTrailing: Self.glyphCenterFromTrailing)
            // An opaque plate carries the shadow; the material above it is
            // what the real panel is made of.
            bubble.fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(colorScheme == .light ? 0.16 : 0.5), radius: 10, y: 5)
            bubble.fill(.regularMaterial)
            bubble.fill(PanelSurface.baseFill(for: colorScheme))
            bubble.stroke(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 1) {
            ForEach(sections) { id in
                let isActive = active == id
                Button {
                    onSelect(id)
                } label: {
                    Image(systemName: id.symbolName)
                        .font(.system(size: 9, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.86))
                .background(isActive ? activeFill : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .help(id.title(l10n.s))
                .accessibilityLabel(id.title(l10n.s))
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(3)
        .background(PanelSurface.cardFill(for: colorScheme),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
        }
    }

    private var activeFill: Color {
        colorScheme == .light ? Color.accentColor.opacity(0.13) : Color.accentColor.opacity(0.20)
    }

    private var openTab: some View {
        let inner = Self.width - 2 * Self.padding - 2 * 8
        return VStack(alignment: .leading, spacing: 7) {
            if let active {
                Text(active.title(l10n.s).uppercased())
                    .font(.system(size: 8, weight: .semibold))
                    .kerning(0.4)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            placeholderLine(width: inner)
            placeholderLine(width: inner * 0.62)
            placeholderLine(width: inner * 0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(PanelSurface.cardFill(for: colorScheme),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
        }
        .accessibilityHidden(true)
    }

    private func placeholderLine(width: CGFloat) -> some View {
        Capsule()
            .fill(PanelSurface.controlFill(for: colorScheme))
            .frame(width: width, height: 5)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            footerPill("gearshape")
            footerPill("power")
        }
        .accessibilityHidden(true)
    }

    private func footerPill(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .background(PanelSurface.cardFill(for: colorScheme),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
            }
    }
}

/// A popover balloon: rounded body with an arrow on the top edge.
private struct PopoverBubble: Shape {
    let cornerRadius: CGFloat
    let arrowWidth: CGFloat
    let arrowHeight: CGFloat
    let arrowCenterFromTrailing: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY + arrowHeight,
                          width: rect.width, height: rect.height - arrowHeight)
        let tipX = rect.maxX - arrowCenterFromTrailing
        var path = Path()
        path.move(to: CGPoint(x: body.minX + cornerRadius, y: body.minY))
        path.addLine(to: CGPoint(x: tipX - arrowWidth / 2, y: body.minY))
        path.addLine(to: CGPoint(x: tipX, y: rect.minY))
        path.addLine(to: CGPoint(x: tipX + arrowWidth / 2, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - cornerRadius, y: body.minY))
        path.addArc(center: CGPoint(x: body.maxX - cornerRadius, y: body.minY + cornerRadius),
                    radius: cornerRadius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - cornerRadius))
        path.addArc(center: CGPoint(x: body.maxX - cornerRadius, y: body.maxY - cornerRadius),
                    radius: cornerRadius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: body.minX + cornerRadius, y: body.maxY))
        path.addArc(center: CGPoint(x: body.minX + cornerRadius, y: body.maxY - cornerRadius),
                    radius: cornerRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + cornerRadius))
        path.addArc(center: CGPoint(x: body.minX + cornerRadius, y: body.minY + cornerRadius),
                    radius: cornerRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

private struct PanelOrderDropDelegate: DropDelegate {
    let target: PanelSectionID
    @Binding var order: [PanelSectionID]
    @Binding var dragging: PanelSectionID?

    func dropEntered(info: DropInfo) {
        guard let dragging,
              dragging != target,
              let from = order.firstIndex(of: dragging),
              let to = order.firstIndex(of: target) else { return }

        withAnimation(.easeInOut(duration: 0.12)) {
            order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        PanelLayout.setOrder(order)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        PanelLayout.setOrder(order)
        return true
    }
}
