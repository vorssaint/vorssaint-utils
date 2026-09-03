// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// An interactive visual radial menu canvas in Settings. Displays the real
/// wheel layout with exact angles and colors, supports drag-to-reorder,
/// click-to-edit, hover previews, and submenu drilldown.
struct RadialMenuVisualCanvas: View {
    let items: [RadialMenuItem]
    let profileColor: Color
    let text: RadialMenuFeatureStrings
    let openSubmenu: RadialMenuItem?
    let onSelect: (RadialMenuItem) -> Void
    let onReorder: (RadialMenuItem, RadialMenuItem) -> Void
    let onRemove: (RadialMenuItem) -> Void
    let onOpenSubmenu: ((RadialMenuItem) -> Void)?
    let onBack: (() -> Void)?
    let onAdd: () -> Void
    let onReset: () -> Void

    @State private var hoveredIndex: Int?
    @State private var draggingIndex: Int?
    @State private var dragPosition: CGPoint = .zero
    @State private var targetIndex: Int?
    @State private var showingResetConfirm = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let canvasHeight: CGFloat = 330
    private let wheelDiameter: CGFloat = 250
    private let ringRadius: CGFloat = 92
    private let chipSize: CGFloat = 44
    private let hubDiameter: CGFloat = 68
    private let deadZoneRadius: CGFloat = 36

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            canvasArea
        }
        .frame(height: canvasHeight)
        .frame(maxWidth: .infinity)
        .background(stageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .light ? 0.12 : 0.14), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(colorScheme == .light ? 0.08 : 0.28), radius: 10, y: 4)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            if let openSubmenu {
                Button {
                    onBack?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 11, weight: .bold))
                        Text(openSubmenu.displayName(text))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(profileColor)
                }
                .buttonStyle(.plain)
                .help(text.backButton)
            } else {
                Text(text.pageTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.uppercase)
            }

            Spacer()

            Button(text.resetActionsButton) {
                showingResetConfirm = true
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.white.opacity(0.7))
            .confirmationDialog(
                text.resetActionsConfirm,
                isPresented: $showingResetConfirm,
                titleVisibility: .visible
            ) {
                Button(text.resetActionsConfirm, role: .destructive) {
                    onReset()
                }
            } message: {
                Text(text.resetActionsConfirmMessage)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    // MARK: - Stage Background

    private var stageBackground: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.11)

            RadialGradient(
                colors: [profileColor.opacity(0.15), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 150
            )

            Theme.spaceGradient.opacity(0.4)
        }
    }

    // MARK: - Canvas Area

    private var canvasArea: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                wheelBackplate
                dividers(center: center)
                activeWedgeHighlight
                chipsRing(center: center)
                centerHub
                floatingDraggedChip
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .coordinateSpace(name: "RadialCanvas")
        }
    }

    // MARK: - Wheel Backplate

    private var wheelBackplate: some View {
        Circle()
            .fill(Color.black.opacity(0.42))
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            )
            .frame(width: wheelDiameter, height: wheelDiameter)
            .shadow(color: .black.opacity(0.4), radius: 14, y: 4)
    }

    // MARK: - Dividers

    @ViewBuilder
    private func dividers(center: CGPoint) -> some View {
        let count = items.count
        if count > 1 {
            RadialCanvasDividers(sliceCount: count,
                                 innerRadius: deadZoneRadius,
                                 outerRadius: wheelDiameter / 2 - 2)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
                .frame(width: wheelDiameter, height: wheelDiameter)
        }
    }

    // MARK: - Active Wedge Highlight

    @ViewBuilder
    private var activeWedgeHighlight: some View {
        let count = items.count
        let activeIdx = targetIndex ?? hoveredIndex
        if let activeIdx, count > 0, items.indices.contains(activeIdx) {
            RadialWedgeShape(
                centerAngle: 2 * .pi * Double(activeIdx) / Double(count),
                sliceAngle: 2 * .pi / Double(count),
                innerRadius: deadZoneRadius,
                outerRadius: wheelDiameter / 2 - 2
            )
            .fill(profileColor.opacity(targetIndex != nil ? 0.32 : 0.22))
            .frame(width: wheelDiameter, height: wheelDiameter)
            .animation(.easeInOut(duration: 0.12), value: activeIdx)
        }
    }

    // MARK: - Chips Ring

    @ViewBuilder
    private func chipsRing(center: CGPoint) -> some View {
        let count = items.count
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let unit = RadialMenuGeometry.unitPosition(index: index, itemCount: count)
            let isDragged = draggingIndex == index
            let isTarget = targetIndex == index
            let isHovered = hoveredIndex == index

            RadialCanvasChip(
                item: item,
                text: text,
                isHighlighted: isTarget || isHovered,
                profileColor: profileColor
            )
            .opacity(isDragged ? 0.25 : 1)
            .scaleEffect(isHovered && !isDragged ? 1.08 : 1)
            .offset(x: unit.dx * ringRadius, y: -unit.dyUp * ringRadius)
            .onHover { inside in
                guard draggingIndex == nil else { return }
                if inside {
                    hoveredIndex = index
                } else if hoveredIndex == index {
                    hoveredIndex = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("RadialCanvas"))
                    .onChanged { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        if distance > 6 {
                            draggingIndex = index
                            dragPosition = value.location

                            let dx = value.location.x - center.x
                            let dyUp = center.y - value.location.y
                            let angle = RadialMenuGeometry.angle(dx: dx, dyUp: dyUp)
                            if let slot = RadialMenuGeometry.index(forAngle: angle, itemCount: count) {
                                targetIndex = slot
                            }
                        }
                    }
                    .onEnded { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        if distance <= 6 {
                            onSelect(item)
                        } else if let from = draggingIndex, let to = targetIndex, from != to,
                                  items.indices.contains(from), items.indices.contains(to) {
                            let source = items[from]
                            let dest = items[to]
                            withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
                                onReorder(source, dest)
                            }
                        }
                        draggingIndex = nil
                        targetIndex = nil
                    }
            )
            .contextMenu {
                Button(text.pageTitle) {
                    onSelect(item)
                }
                if item.kind == .submenu {
                    Button(text.editActionsButton) {
                        onOpenSubmenu?(item)
                    }
                }
                Divider()
                Button(text.deleteButton, role: .destructive) {
                    onRemove(item)
                }
            }
            .accessibilityLabel(item.displayName(text))
        }
    }

    // MARK: - Center Hub

    private var centerHub: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)

            hubContent
        }
        .frame(width: hubDiameter, height: hubDiameter)
        .contentShape(Circle())
        .onTapGesture {
            if openSubmenu != nil {
                onBack?()
            } else if items.isEmpty {
                onAdd()
            }
        }
    }

    @ViewBuilder
    private var hubContent: some View {
        if let target = targetIndex, items.indices.contains(target) {
            VStack(spacing: 2) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(profileColor)
                Text(items[target].displayName(text))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
        } else if let index = hoveredIndex, items.indices.contains(index) {
            let item = items[index]
            VStack(spacing: 1) {
                Text(item.displayName(text))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(kindLabel(for: item))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 6)
        } else if openSubmenu != nil {
            VStack(spacing: 3) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(profileColor)
                Text(text.backButton)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        } else if items.isEmpty {
            VStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(profileColor)
                Text(text.addButton)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        } else {
            BrandMark(width: 28, tint: Color.white.opacity(0.85))
        }
    }

    // MARK: - Floating Dragged Chip

    @ViewBuilder
    private var floatingDraggedChip: some View {
        if let dragIdx = draggingIndex, items.indices.contains(dragIdx) {
            let item = items[dragIdx]
            RadialCanvasChip(
                item: item,
                text: text,
                isHighlighted: true,
                profileColor: profileColor
            )
            .scaleEffect(1.15)
            .shadow(color: profileColor.opacity(0.6), radius: 10, y: 4)
            .position(dragPosition)
            .allowsHitTesting(false)
        }
    }

    private func kindLabel(for item: RadialMenuItem) -> String {
        switch item.kind {
        case .app: return text.kindApp
        case .file: return text.kindFile
        case .url: return text.kindURL
        case .shortcut: return text.kindShortcut
        case .tool: return text.kindTool
        case .quickToggle: return FeatureStrings.quickToggles(L10n.shared.language).pageTitle
        case .windowLayout: return FeatureStrings.windowLayout(L10n.shared.language).title
        case .media: return text.kindMedia
        case .submenu: return text.kindSubmenu
        }
    }
}

// MARK: - Radial Canvas Chip

private struct RadialCanvasChip: View {
    let item: RadialMenuItem
    let text: RadialMenuFeatureStrings
    let isHighlighted: Bool
    let profileColor: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    isHighlighted
                    ? AnyShapeStyle(profileColor)
                    : AnyShapeStyle(Color(red: 0.18, green: 0.19, blue: 0.22))
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            isHighlighted ? Color.white.opacity(0.5) : Color.white.opacity(0.18),
                            lineWidth: isHighlighted ? 1.4 : 0.8
                        )
                )
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)

            chipIcon
        }
        .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private var chipIcon: some View {
        if item.mediaKey == .nowPlaying {
            Image(systemName: "music.note")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.9)))
        } else if item.symbolName.isEmpty, let customImage = RadialMenuIconStore.customIcon(for: item) {
            Image(nsImage: customImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
        } else if item.usesFileIcon {
            Image(nsImage: RadialMenuIconStore.fileIcon(for: item.payload))
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
        } else {
            Image(systemName: item.effectiveSymbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.9)))
        }
    }
}

// MARK: - Radial Dividers Shape

private struct RadialCanvasDividers: Shape {
    let sliceCount: Int
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        guard sliceCount > 1 else { return Path() }
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let step = 2 * .pi / Double(sliceCount)
        for i in 0..<sliceCount {
            let angle = step * (Double(i) + 0.5) - .pi / 2
            let x1 = center.x + innerRadius * CGFloat(cos(angle))
            let y1 = center.y + innerRadius * CGFloat(sin(angle))
            let x2 = center.x + outerRadius * CGFloat(cos(angle))
            let y2 = center.y + outerRadius * CGFloat(sin(angle))
            path.move(to: CGPoint(x: x1, y: y1))
            path.addLine(to: CGPoint(x: x2, y: y2))
        }
        return path
    }
}
