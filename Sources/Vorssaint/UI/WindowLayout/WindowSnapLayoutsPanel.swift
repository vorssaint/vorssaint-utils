// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// What the picker shows: its layout, and what the dragged window is over.
final class WindowSnapLayoutsModel: ObservableObject {
    @Published var geometry: WindowSnapLayoutsGeometry?
    @Published var hovered: WindowSnapLayoutsHit?
    @Published var open = false
    @Published var strings = WindowSnapLayoutsStrings.localized(.enUS)
    /// The island's size at rest on this display, which the picker grows out of.
    @Published var collapsed = CGSize(width: 200, height: 32)
}

/// The island grown into a snap-layout picker while a window is dragged. It
/// never takes the mouse: the drag belongs to the window's app, so the
/// window layout service tests the pointer against the same geometry.
final class WindowSnapLayoutsPanel {
    static let shared = WindowSnapLayoutsPanel()

    let model = WindowSnapLayoutsModel()
    private var panel: NSPanel?
    private var closeGeneration = 0

    private var screen: NSScreen?

    private init() {
        // A desktop reached while the window is held is marked at once.
        WindowSpaceCarry.shared.onArrival = { [weak self] in self?.refreshSpaces() }
    }

    var isShowing: Bool { model.open }

    /// Opens the picker on the display that holds `point`, an AppKit point.
    func show(near point: CGPoint) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main
        else { return }
        self.screen = screen
        let geometry = Self.geometry(on: screen)
        closeGeneration += 1
        model.strings = WindowSnapLayoutsStrings.localized(L10n.shared.language)
        model.geometry = geometry
        model.hovered = nil
        model.collapsed = Self.restingIsland(on: screen)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // Room past the picker's own edges, so the island's spring can swing out without being cut.
        let picker = geometry.panel
        panel.setFrame(CGRect(x: picker.minX - Self.swing, y: picker.minY - Self.swing,
                              width: picker.width + 2 * Self.swing, height: picker.height + Self.swing), display: false)
        panel.orderFrontRegardless()
        // The surface itself runs the island's springs; this only says it should be open.
        model.open = true
    }

    /// The hit under `point`, shown as lit. Nil while the picker is closed.
    @discardableResult
    func update(pointer point: CGPoint) -> WindowSnapLayoutsHit? {
        guard model.open, let geometry = model.geometry else { return nil }
        let hit = geometry.hit(at: point)
        if hit != model.hovered {
            withAnimation(.easeOut(duration: 0.1)) { model.hovered = hit }
        }
        return hit
    }

    /// The desktops again, after one changed under the held window.
    func refreshSpaces() {
        guard model.open, let screen else { return }
        model.geometry = Self.geometry(on: screen)
    }

    private static func geometry(on screen: NSScreen) -> WindowSnapLayoutsGeometry {
        let topInset = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY, 24)
        return WindowSnapLayoutsSupport.geometry(screen: screen.frame, topInset: topInset, spaces: spaces(on: screen))
    }

    func hide() {
        WindowSpaceCarry.shared.cancel()
        guard model.open else { return }
        model.open = false
        model.hovered = nil
        closeGeneration += 1
        let generation = closeGeneration
        // The content fades, then the island shrinks back into the camera, as it does when it closes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 + NotchMotion.shrinkingWidth.duration + 0.1) { [weak self] in
            guard let self, generation == self.closeGeneration else { return }
            self.panel?.orderOut(nil)
        }
    }

    /// Past the picker on each side and below, for the spring's overshoot.
    static let swing: CGFloat = 28

    /// The island at rest: the camera's footprint on a notched display, a small pill elsewhere.
    private static func restingIsland(on screen: NSScreen) -> CGSize {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return CGSize(width: max(120, right.minX - left.maxX), height: top)
        }
        return CGSize(width: 200, height: max(24, screen.frame.maxY - screen.visibleFrame.maxY))
    }

    private static func spaces(on screen: NSScreen) -> [WindowSnapLayoutsSpace] {
        guard let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              let topology = SpaceWindowBridge.topology() else { return [] }
        let display = topology.displays.first { $0.displayID == number } ?? topology.displays.first
        guard let display else { return [] }
        return WindowSnapLayoutsSupport.spaces(ordered: display.spaces, fullscreen: display.fullscreenSpaces,
                                               current: display.currentSpace)
    }

    private func makePanel() -> NSPanel {
        let panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Above the island itself, which it grows out of.
        panel.level = NSWindow.Level(rawValue: NotchPanel.normalLevel.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none
        let host = NSHostingView(rootView: WindowSnapLayoutsView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}

/// The island itself, grown into the picker: its own shape, black, opening
/// from the camera on the island's springs, with its tiles and highlights.
private struct WindowSnapLayoutsView: View {
    @ObservedObject var model: WindowSnapLayoutsModel

    var body: some View {
        if let geometry = model.geometry {
            // The island's outline curves out into the screen edge at its top corners; its
            // body sits inside those shoulders, so the shape is wider than the picker by them.
            let shoulder = NotchLayout.shoulder(height: geometry.panel.height)
            NotchMorphSurface(open: model.open, collapsed: model.collapsed,
                              expanded: CGSize(width: geometry.panel.width + 2 * shoulder, height: geometry.panel.height)) {
                content(geometry)
            }
            // The window is wider than the picker by the spring's room on each side.
            .frame(width: geometry.panel.width + 2 * WindowSnapLayoutsPanel.swing,
                   height: geometry.panel.height + WindowSnapLayoutsPanel.swing, alignment: .top)
            .environment(\.colorScheme, .dark)
        }
    }

    private func content(_ geometry: WindowSnapLayoutsGeometry) -> some View {
        let origin = CGPoint(x: geometry.panel.minX, y: geometry.panel.maxY)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(geometry.cards.enumerated()), id: \.offset) { _, card in
                cardView(card, origin: origin)
            }
            ForEach(Array(geometry.chips.enumerated()), id: \.offset) { _, chip in
                chipView(chip, origin: origin)
            }
        }
        .frame(width: geometry.panel.width, height: geometry.panel.height, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// AppKit points, y up, into the picker's own coordinates, y down.
    private func local(_ rect: CGRect, origin: CGPoint) -> CGRect {
        CGRect(x: rect.minX - origin.x, y: origin.y - rect.maxY, width: rect.width, height: rect.height)
    }

    private func cardView(_ card: WindowSnapLayoutsGeometry.Card, origin: CGPoint) -> some View {
        let frame = local(card.frame, origin: origin)
        let lit = { (action: WindowLayoutAction) in model.hovered == .zone(layout: card.layout.id, action: action) }
        let cardLit = card.zones.contains { lit($0.action) }
        return ZStack(alignment: .topLeading) {
            // The island's tile: white over black, a little brighter while the window is over it.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(cardLit ? 0.12 : 0.06))
                .frame(width: frame.width, height: frame.height)
            ForEach(Array(card.zones.enumerated()), id: \.offset) { _, zone in
                let rect = local(zone.frame, origin: CGPoint(x: card.frame.minX, y: card.frame.maxY))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(lit(zone.action) ? 0.92 : 0.2))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .scaleEffect(cardLit ? 1.04 : 1)
        .animation(.spring(duration: 0.24, bounce: 0.2), value: cardLit)
        .offset(x: frame.minX, y: frame.minY)
    }

    private func chipView(_ chip: WindowSnapLayoutsGeometry.Chip, origin: CGPoint) -> some View {
        let frame = local(chip.frame, origin: origin)
        let lit = model.hovered == .space(chip.space.id)
        return Text(model.strings.desktop(chip.space.number))
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(lit ? .black : .white.opacity(chip.space.current ? 0.35 : 0.85))
            .frame(width: frame.width, height: frame.height)
            .background(Capsule().fill(.white.opacity(lit ? 0.92 : chip.space.current ? 0.04 : 0.1)))
            .overlay(Capsule().strokeBorder(.white.opacity(chip.space.current ? 0.14 : 0), lineWidth: 0.75))
            .animation(.easeOut(duration: 0.12), value: lit)
            .offset(x: frame.minX, y: frame.minY)
    }
}
