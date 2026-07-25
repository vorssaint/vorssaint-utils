// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The wheel itself: a glass disc with one chip per action, a highlight wedge
/// under the pointed slice and a hub that names the selection or leads back.
struct RadialMenuView: View {
    @ObservedObject private var service = RadialMenuService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var items: [RadialMenuItem] { service.stack.last ?? [] }

    var body: some View {
        ZStack {
            backplate
            if let index = service.highlightedIndex, items.indices.contains(index) {
                RadialWedgeShape(centerAngle: 2 * .pi * Double(index) / Double(items.count),
                                 sliceAngle: 2 * .pi / Double(items.count),
                                 innerRadius: RadialMenuLayout.deadZoneRadius,
                                 outerRadius: RadialMenuLayout.wheelDiameter / 2 - 4)
                    .fill(Color.accentColor.opacity(colorScheme == .light ? 0.16 : 0.24))
            }
            ring.id(service.stack.count)
            hub
        }
        .frame(width: RadialMenuLayout.panelSize, height: RadialMenuLayout.panelSize)
        // The whole panel is tappable; the service decides by distance, so a
        // click on the transparent corners dismisses instead of dying.
        .contentShape(Rectangle())
        .onTapGesture { service.activatePointer() }
        .scaleEffect(service.visible ? 1 : (reduceMotion ? 1 : 0.88))
        .opacity(service.visible ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.22, dampingFraction: 0.85),
                   value: service.visible)
        .accessibilityLabel(text.pageTitle)
    }

    private var backplate: some View {
        Circle()
            .fill(.regularMaterial)
            .overlay(Circle().fill(PanelSurface.baseFill(for: colorScheme)))
            .overlay(Circle().strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8))
            .frame(width: RadialMenuLayout.wheelDiameter, height: RadialMenuLayout.wheelDiameter)
            .shadow(color: .black.opacity(colorScheme == .light ? 0.18 : 0.5), radius: 18, y: 5)
    }

    private var ring: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let unit = RadialMenuGeometry.unitPosition(index: index, itemCount: items.count)
            RadialChipView(item: item,
                           name: item.displayName(text),
                           highlighted: service.highlightedIndex == index,
                           reduceMotion: reduceMotion)
                .offset(x: unit.dx * RadialMenuLayout.ringRadius,
                        y: -unit.dyUp * RadialMenuLayout.ringRadius)
                .accessibilityLabel(item.displayName(text))
        }
    }

    // No disc behind the hub: the label, the back hint and the brand mark sit
    // straight on the wheel's glass, quiet and centered.
    private var hub: some View {
        ZStack {
            if let index = service.highlightedIndex, items.indices.contains(index) {
                Text(items[index].displayName(text))
                    .font(.system(size: 11, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
            } else if let parent = service.trail.last {
                VStack(spacing: 3) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(parent.isEmpty ? text.kindSubmenu : parent)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .accessibilityLabel(text.backButton)
            } else {
                // Black on the light theme, white on the dark one: the owner
                // wants the mark clearly readable at the center.
                BrandMark(width: 34, tint: Color.primary)
            }
        }
        .frame(width: RadialMenuLayout.hubDiameter, height: RadialMenuLayout.hubDiameter)
    }
}

private struct RadialChipView: View {
    let item: RadialMenuItem
    let name: String
    let highlighted: Bool
    let reduceMotion: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(highlighted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(PanelSurface.controlFill(for: colorScheme)))
                .overlay(Circle().strokeBorder(PanelSurface.border(for: colorScheme),
                                               lineWidth: highlighted ? 0 : 0.7))
            icon
        }
        .frame(width: RadialMenuLayout.chipSize, height: RadialMenuLayout.chipSize)
        .scaleEffect(highlighted && !reduceMotion ? 1.12 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82), value: highlighted)
    }

    @ViewBuilder
    private var icon: some View {
        if item.usesFileIcon {
            Image(nsImage: RadialMenuIconStore.fileIcon(for: item.payload))
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
        } else {
            Image(systemName: item.effectiveSymbolName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
    }
}

/// A slice-shaped highlight between the hub and the wheel border.
struct RadialWedgeShape: Shape {
    let centerAngle: Double
    let sliceAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Screen angles: 0 at +x, growing clockwise (flipped y); our slice
        // angles run clockwise from 12 o'clock, so shift by a quarter turn.
        let start = Angle(radians: centerAngle - sliceAngle / 2 - .pi / 2)
        let end = Angle(radians: centerAngle + sliceAngle / 2 - .pi / 2)
        var path = Path()
        path.addArc(center: center, radius: innerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: outerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// Real icons and display names for slices that point at the disk, cached so
/// the wheel never touches the file system while the pointer is tracked (a
/// dead network mount would otherwise stall every highlight change).
/// Configurations are tiny (a wheel holds 12 items), so entries accumulate.
enum RadialMenuIconStore {
    private static var icons: [String: NSImage] = [:]
    private static var names: [String: String] = [:]

    static func fileIcon(for payload: String) -> NSImage {
        if let cached = icons[payload] { return cached }
        let path = (payload as NSString).expandingTildeInPath
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 34, height: 34)
        icons[payload] = icon
        return icon
    }

    static func fileName(for payload: String) -> String {
        if let cached = names[payload] { return cached }
        let path = (payload as NSString).expandingTildeInPath
        let name = FileManager.default.displayName(atPath: path)
        names[payload] = name
        return name
    }

    static func invalidate(_ payload: String) {
        icons.removeValue(forKey: payload)
        names.removeValue(forKey: payload)
    }
}

/// Name resolution shared by the wheel and the Settings editor: a custom name
/// wins, everything else derives from the target in the user's language.
extension RadialMenuItem {
    func displayName(_ text: RadialMenuFeatureStrings) -> String {
        if !name.isEmpty { return name }
        switch kind {
        case .app, .file:
            return RadialMenuIconStore.fileName(for: payload)
        case .url:
            let normalized = RadialMenuSupport.normalizedURL(payload) ?? payload
            return URL(string: normalized)?.host ?? payload
        case .shortcut:
            return GlobalShortcut(storageValue: payload)?.displayString ?? text.kindShortcut
        case .tool:
            guard let tool else { return text.kindTool }
            return tool.feature.hubTitle(L10n.shared.s, hub: FeatureStrings.hub(L10n.shared.language))
        case .windowLayout:
            guard let windowLayoutAction else {
                return FeatureStrings.windowLayout(L10n.shared.language).title
            }
            return windowLayoutAction.title(FeatureStrings.windowLayout(L10n.shared.language))
        case .media:
            switch mediaKey {
            case .playPause: return text.mediaPlayPause
            case .previousTrack: return text.mediaPrevious
            case .nextTrack: return text.mediaNext
            case nil: return text.kindMedia
            }
        case .submenu:
            return text.kindSubmenu
        }
    }

    var usesFileIcon: Bool {
        (kind == .app || kind == .file) && symbolName.isEmpty
    }
}
