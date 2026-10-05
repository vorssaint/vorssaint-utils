// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Production hover and placement methods against a panel double. No native
/// windows, Dock changes or synthetic input are used.
enum DockPreviewPositionTests {
    struct App { let processIdentifier: Int32 }
    struct DockHit {
        let app: App
        let iconFrame: CGRect
        let preferences: DockPreviewPreferences
    }
    enum Zone {
        case panel, openingPath, ownIcon, otherIcon(DockHit), outside
    }
    final class View { func layoutSubtreeIfNeeded() {} }
    final class Controller { let view = View() }
    final class Panel {
        var frame = CGRect.zero
        var isVisible = false
        var placements = 0
        var contentViewController: Controller? = Controller()
        func setFrame(_ frame: CGRect, display: Bool, animate: Bool) {
            self.frame = frame
            placements += 1
        }
        func orderFrontRegardless() { isVisible = true }
    }
    final class Service {
        typealias DockHit = DockPreviewPositionTests.DockHit
        typealias Zone = DockPreviewPositionTests.Zone
        var panel: Panel? = Panel()
        var isVisible: Bool { panel?.isVisible == true }
        var isPinned = false
        var isDraggingWindow = false
        var hasEnteredPanel = false
        var activePanelFrame: CGRect?
        var activeCorridor: HoverCorridor?
        var activeIconFrame: CGRect?
        var activeDockPreferences: DockPreviewPreferences?
        var currentSessionPID: Int32? = 20
        var orientation: DockPreviewOrientation = .bottom
        var windows = [1, 2, 3]
        var pendingHover: DockHit?
        var pendingHide = false
        var lastAXMousePoint: CGPoint?
        var lastAppKitMousePoint: CGPoint?
        var screenVisibleFrame = CGRect.zero
        var visibilityWatchRequests = 0
        var revealedDockHit: DockHit?
        func ensurePanel() -> Panel { panel! }
        func visibleFrameForScreen(containing rect: CGRect) -> CGRect { screenVisibleFrame }
        func appKitPoint(fromAX point: CGPoint) -> CGPoint { point }
        func cancelPendingHide() { pendingHide = false }
        func cancelPendingHover() { pendingHover = nil }
        func scheduleHideIfStillOutside() { pendingHide = true }
        func scheduleHover(_ hit: DockHit, delay: TimeInterval? = nil) { pendingHover = hit }
        func isNearDock(_ point: CGPoint) -> Bool { true }
        func dockHit(at point: CGPoint) -> DockHit? {
            guard let hit = revealedDockHit, hit.iconFrame.contains(point) else { return nil }
            return hit
        }
        // A spy for the old hover dependency: entering the panel must no longer
        // request a watcher that moves it when the Dock disappears.
        func startDockVisibilityTimerIfNeeded() { visibilityWatchRequests += 1 }
    }

    static func run(_ suite: TestSuite) {
        let screen = CGRect(x: -1440, y: 120, width: 1440, height: 900)
        let icons: [(DockPreviewOrientation, CGRect)] = [
            (.bottom, CGRect(x: -780, y: 120, width: 80, height: 80)),
            (.left, CGRect(x: -1440, y: 500, width: 80, height: 80)),
            (.right, CGRect(x: -80, y: 500, width: 80, height: 80)),
        ]
        let configurations: [(Bool, CGFloat)] = [(true, 72), (true, 96), (false, 72), (false, 96)]
        for (orientation, icon) in icons {
            for (autohide, dockThickness) in configurations {
                let service = Service()
                service.screenVisibleFrame = screen
                // Model a visible Dock's work area, then let it expand when
                // auto-hide removes the Dock while the pointer is on the panel.
                switch orientation {
                case .bottom:
                    service.screenVisibleFrame.origin.y += dockThickness
                    service.screenVisibleFrame.size.height -= dockThickness
                case .left:
                    service.screenVisibleFrame.origin.x += dockThickness
                    service.screenVisibleFrame.size.width -= dockThickness
                case .right:
                    service.screenVisibleFrame.size.width -= dockThickness
                }
                let hit = DockHit(app: App(processIdentifier: 20), iconFrame: icon,
                                  preferences: DockPreviewPreferences(
                                    orientation: orientation, autohide: autohide,
                                    tileSize: 80, magnification: false, magnifiedTileSize: 128))
                service.showPanel(for: hit, itemCount: service.windows.count)
                service.revealedDockHit = hit
                let openingFrame = service.panel!.frame
                let point = CGPoint(x: openingFrame.midX, y: openingFrame.midY)
                service.pendingHide = true
                service.pendingHover = hit
                service.handleMouseMoved(point)
                if autohide {
                    service.revealedDockHit = nil
                    service.screenVisibleFrame = screen
                }
                service.handleMouseMoved(CGPoint(x: point.x + 30, y: point.y + 30))
                suite.expect(service.hasEnteredPanel && !service.pendingHide && service.pendingHover == nil,
                             "entering and moving within the preview cancels dismissal and app switching")
                suite.expect(service.visibilityWatchRequests == 0,
                             "a hovered \(orientation) preview never follows the Dock when it hides")
                suite.expect(service.panel!.frame == openingFrame && service.panel!.placements == 1,
                             "hovering keeps the \(orientation) preview at its opening position")

                service.windows = [1]
                service.resizePanelForCurrentWindows()
                let resizedFrame = service.panel!.frame
                let keepsDockFacingEdge: Bool
                switch orientation {
                case .bottom: keepsDockFacingEdge = resizedFrame.minY == openingFrame.minY
                case .left: keepsDockFacingEdge = resizedFrame.minX == openingFrame.minX
                case .right: keepsDockFacingEdge = resizedFrame.maxX == openingFrame.maxX
                }
                suite.expect(resizedFrame.size != openingFrame.size && keepsDockFacingEdge
                             && service.activePanelFrame == resizedFrame,
                             "closing a window resizes the \(orientation) preview at its opening anchor")

                service.handleMouseMoved(CGPoint(x: screen.midX, y: screen.maxY))
                suite.expect(service.pendingHide,
                             "leaving a stationary preview still schedules its dismissal")
                service.handleMouseMoved(CGPoint(x: resizedFrame.midX, y: resizedFrame.midY))
                suite.expect(!service.pendingHide,
                             "returning to a stationary preview cancels dismissal")
            }
        }
    }
}
