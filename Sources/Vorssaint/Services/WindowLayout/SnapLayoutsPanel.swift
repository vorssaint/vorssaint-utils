// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Owns the floating Snap Layouts panel on `WindowLayoutService`'s behalf.
/// Kept in its own file, as a plain helper object rather than a second
/// `ObservableObject` singleton, so `WindowLayoutService.swift` itself never
/// has to import SwiftUI just to host one panel — the same split
/// `DockPreviewService` draws between its tap-driven logic and its panel.
///
/// The panel ignores mouse events on purpose: the window drag that opens it
/// is already tracked by `WindowLayoutService`'s own CGEvent tap, so a click
/// on the panel must pass straight through rather than being captured by an
/// `NSHostingController` — hover and release both come from the tap
/// forwarding pointer locations into `updateHover(at:visibleFrame:)`.
final class SnapLayoutsPanel {
    private var panel: NSPanel?
    private let state = SnapLayoutsPanelState()
    private static let topInset: CGFloat = 6

    var isVisible: Bool { panel?.isVisible ?? false }

    /// The panel's current on-screen frame, or nil before it has ever been
    /// shown. `WindowLayoutService` uses this to decide whether the pointer
    /// is still reachable from an open panel.
    var frame: CGRect? { panel?.frame }

    /// Shows (or repositions) the panel centered at the top of `visibleFrame`
    /// with the given preset cards. Safe to call on every drag sample: the
    /// hosting controller and its SwiftUI tree are created once, and later
    /// calls only touch the panel's frame plus a couple of `@Published`
    /// fields, so 30 Hz sampling never re-renders more than the highlight.
    func show(visibleFrame: CGRect, presets: [SnapLayoutPreset]) {
        let panel = ensurePanel()
        if state.presets != presets {
            state.presets = presets
        }
        let size = SnapLayoutPresets.panelSize(for: presets)
        let frame = CGRect(x: visibleFrame.midX - size.width / 2,
                           y: visibleFrame.maxY - size.height - Self.topInset,
                           width: size.width,
                           height: size.height).integral
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        guard !panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        state.highlighted = nil
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    /// Highlights the cell under `point`, if any, and returns the preview
    /// target releasing there would apply — reusing the same
    /// `WindowEdgeSnapTarget` shape the classic edge-snap preview draws, so
    /// hovering a Snap Layouts cell shows that same live rectangle over the
    /// zone it targets. Returns nil, and clears any highlight, whenever
    /// `point` is not over a cell — including inside the panel's own
    /// padding — so a caller must always have its own fallback rather than
    /// treating nil as "still on the panel, do nothing".
    @discardableResult
    func updateHover(at point: CGPoint, visibleFrame: CGRect) -> WindowEdgeSnapTarget? {
        guard let panel, panel.isVisible else { return nil }
        let hit = SnapLayoutPresets.hit(at: point, presets: state.presets, panelFrame: panel.frame)
        if state.highlighted != hit?.cell {
            state.highlighted = hit?.cell
        }
        guard let hit else { return nil }
        let rect = WindowLayoutGeometry.rect(for: hit.action,
                                             current: visibleFrame,
                                             visibleFrame: visibleFrame,
                                             windowGap: WindowLayoutGaps.windowGap,
                                             screenGap: WindowLayoutGaps.screenGap)
        return WindowEdgeSnapTarget(action: hit.action, frame: rect.integral, visibleFrame: visibleFrame)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .transient, .ignoresCycle]
        panel.animationBehavior = .none
        panel.contentViewController = NSHostingController(rootView: SnapLayoutsPanelView(state: state))
        self.panel = panel
        return panel
    }
}

/// The hover/preset state the SwiftUI view reflects. The event tap callback
/// only ever writes scalar or array values here on the main thread — the
/// view itself never touches the drag.
final class SnapLayoutsPanelState: ObservableObject {
    @Published var presets: [SnapLayoutPreset] = []
    /// Keyed by cell, not by `WindowLayoutAction`: two different cards can
    /// share an action for different cells (wide-left thirds' `.rightThird`
    /// is not even-thirds' `.rightThird`), so keying on the action alone
    /// would light up a cell in every card that happens to share it.
    @Published var highlighted: SnapLayoutCellID?
}
