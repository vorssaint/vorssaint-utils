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
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(geometry.panel, display: false)
        panel.orderFrontRegardless()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { model.open = true }
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
        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
            model.open = false
            model.hovered = nil
        }
        closeGeneration += 1
        let generation = closeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, generation == self.closeGeneration else { return }
            self.panel?.orderOut(nil)
        }
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

/// Black like the island, flush with the top of the screen, rounded below.
private struct WindowSnapLayoutsView: View {
    @ObservedObject var model: WindowSnapLayoutsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if let geometry = model.geometry {
                let origin = CGPoint(x: geometry.panel.minX, y: geometry.panel.maxY)
                ZStack(alignment: .topLeading) {
                    UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26, style: .continuous)
                        .fill(Color.black)
                    ForEach(Array(geometry.cards.enumerated()), id: \.offset) { _, card in
                        cardView(card, origin: origin)
                    }
                    ForEach(Array(geometry.chips.enumerated()), id: \.offset) { _, chip in
                        chipView(chip, origin: origin)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                // Grows out of the camera housing: narrow and short at first, then the whole picker.
                .scaleEffect(x: model.open ? 1 : 0.32, y: model.open ? 1 : 0.2, anchor: .top)
                .opacity(model.open ? 1 : (reduceMotion ? 0 : 0.2))
            }
        }
    }

    /// AppKit points, y up, into the panel's own coordinates, y down.
    private func local(_ rect: CGRect, origin: CGPoint) -> CGRect {
        CGRect(x: rect.minX - origin.x, y: origin.y - rect.maxY, width: rect.width, height: rect.height)
    }

    private func cardView(_ card: WindowSnapLayoutsGeometry.Card, origin: CGPoint) -> some View {
        let frame = local(card.frame, origin: origin)
        let lit = { (action: WindowLayoutAction) in model.hovered == .zone(layout: card.layout.id, action: action) }
        let cardLit = card.zones.contains { lit($0.action) }
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(cardLit ? 0.12 : 0.06))
                .frame(width: frame.width, height: frame.height)
            ForEach(Array(card.zones.enumerated()), id: \.offset) { _, zone in
                let rect = local(zone.frame, origin: CGPoint(x: card.frame.minX, y: card.frame.maxY))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(lit(zone.action) ? Color.accentColor : Color.white.opacity(0.22))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .scaleEffect(cardLit ? 1.04 : 1)
        .offset(x: frame.minX, y: frame.minY)
    }

    private func chipView(_ chip: WindowSnapLayoutsGeometry.Chip, origin: CGPoint) -> some View {
        let frame = local(chip.frame, origin: origin)
        let lit = model.hovered == .space(chip.space.id)
        return Text(model.strings.desktop(chip.space.number))
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(chip.space.current ? Color.white.opacity(0.35) : Color.white.opacity(lit ? 1 : 0.8))
            .frame(width: frame.width, height: frame.height)
            .background(Capsule().fill(lit ? Color.accentColor : Color.white.opacity(chip.space.current ? 0.04 : 0.1)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(chip.space.current ? 0.12 : 0), lineWidth: 1))
            .offset(x: frame.minX, y: frame.minY)
    }
}
