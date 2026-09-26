// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production routing and lifecycle with controlled event delivery, never posted input.
enum NotchScreenEdgeClickTests {
    final class Panel { var isVisible = true; var ignoresMouseEvents = false }
    final class Host { var acceptsPoint = true; func contains(_ point: CGPoint) -> Bool { acceptsPoint } }
    enum NSScreen {
        static var withMenuBar: Screen? = Screen()
        struct Screen { let frame = CGRect(x: 0, y: 0, width: 1470, height: 956) }
    }
    final class NSEvent {
        typealias EventType = AppKit.NSEvent.EventType
        typealias EventTypeMask = AppKit.NSEvent.EventTypeMask
        struct CGEvent { let location: CGPoint }
        let type: EventType
        let cgEvent: CGEvent?
        let window: Panel?
        init(_ type: EventType, point: CGPoint, window: Panel? = nil) {
            self.type = type
            cgEvent = CGEvent(location: CGPoint(x: point.x, y: 956 - point.y))
            self.window = window
        }
        static var global: [Int: (NSEvent) -> Void] = [:]
        static var local: [Int: (NSEvent) -> NSEvent?] = [:]
        static var nextID = 0
        static func addGlobalMonitorForEvents(matching: EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any? {
            nextID += 1; global[nextID] = handler; return nextID
        }
        static func addLocalMonitorForEvents(matching: EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
            nextID += 1; local[nextID] = handler; return nextID
        }
        static func removeMonitor(_ token: Any) { global[token as! Int] = nil; local[token as! Int] = nil }
    }
    class State {
        var running = true, suspended = false, expanded = false, peeking = false
        var captureControls: Bool?, notice: Bool?
        var dragPlaceholder = false, heldDrag = false, compactActivityIsVisible = false, keepsWorkingSurface = false
        var panel: Panel? = Panel()
        var windowHost: Host? = Host()
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                     safeAreaTop: 32, cameraWidth: 180)
        var compactActivityGeometry: NotchGeometry { geometry }
        var surfaceSize: CGSize { peeking ? geometry.expanded : compactActivityIsVisible ? geometry.compactActivitySize : geometry.collapsed }
        var screenEdgeClickMonitors: [Any] = []
        var screenEdgePressArea: CGRect?
        var hoverWork: DispatchWorkItem?
        var hoverState = NotchHoverState()
        var openings = 0
    }

    static func run(_ suite: TestSuite) {
        for screen in [CGRect(x: 0, y: 0, width: 1470, height: 956),
                       CGRect(x: -1920, y: 956, width: 1920, height: 1080)] {
            for localDelivery in [false, true] {
                let service = Service()
                service.geometry = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 180)
                service.syncScreenEdgeClicks()
                for _ in 0..<100 { service.syncScreenEdgeClicks() }
                suite.expect(NSEvent.global.count == 1 && NSEvent.local.count == 1, "refreshes keep exactly one pair of edge-click monitors")
                let top = CGPoint(x: screen.midX, y: screen.maxY)
                func send(_ type: NSEvent.EventType, _ point: CGPoint, window: Panel? = nil) {
                    let event = NSEvent(type, point: point, window: window)
                    if localDelivery {
                        for handler in Array(NSEvent.local.values) {
                            suite.expect(handler(event) === event, "local observation preserves normal event delivery")
                        }
                    } else { for handler in Array(NSEvent.global.values) { handler(event) } }
                }
                send(.leftMouseUp, top)
                send(.leftMouseDown, CGPoint(x: screen.minX, y: screen.maxY)); send(.leftMouseUp, top)
                send(.leftMouseDown, CGPoint(x: top.x, y: top.y - 2)); send(.leftMouseUp, top)
                send(.leftMouseDown, CGPoint(x: top.x, y: top.y + 0.5)); send(.leftMouseUp, top)
                send(.leftMouseDown, top, window: service.panel); send(.leftMouseUp, top)
                suite.expect(service.openings == 0, "release-only, nearby menus, lower clicks and native notch clicks never cause duplicate opening")
                send(.leftMouseDown, top); send(.leftMouseDragged, top); send(.leftMouseUp, top)
                send(.leftMouseDown, top); send(.leftMouseUp, CGPoint(x: screen.minX, y: screen.maxY))
                suite.expect(service.openings == 0, "dragging or releasing outside cancels an edge click")
                service.windowHost?.acceptsPoint = false
                send(.leftMouseDown, top); send(.leftMouseUp, top)
                service.windowHost?.acceptsPoint = true
                service.keepsWorkingSurface = true
                send(.leftMouseDown, top); send(.leftMouseUp, top)
                service.keepsWorkingSurface = false
                suite.expect(service.openings == 0, "transparent corners and an active menu or modal preserve their own interactions")
                let pendingHover = DispatchWorkItem {}
                service.hoverWork = pendingHover
                send(.leftMouseDown, top)
                suite.expect(service.openings == 0 && pendingHover.isCancelled && service.hoverState.suppressed,
                       "pressing the edge cancels hover and waits for release")
                send(.leftMouseUp, CGPoint(x: top.x, y: top.y - 0.5))
                suite.expect(service.openings == 1 && NSEvent.global.isEmpty && NSEvent.local.isEmpty,
                       "a menu-bar click opens exactly once on either display, then removes both monitors")
                service.removeScreenEdgeClickMonitors()
            }
        }
        for disable in [
            { (s: Service) in s.running = false }, { $0.suspended = true }, { $0.expanded = true },
            { $0.panel?.isVisible = false }, { $0.panel?.ignoresMouseEvents = true },
            { $0.captureControls = true }, { $0.notice = true }, { $0.dragPlaceholder = true }, { $0.heldDrag = true }
        ] {
            let service = Service()
            service.syncScreenEdgeClicks()
            let point = CGPoint(x: service.geometry.screen.midX, y: service.geometry.screen.maxY)
            service.handleScreenEdgeClick(.leftMouseDown, at: point, isNotchWindow: false)
            disable(service)
            service.syncScreenEdgeClicks()
            service.handleScreenEdgeClick(.leftMouseUp, at: point, isNotchWindow: false)
            suite.expect(service.openings == 0 && service.screenEdgePressArea == nil
                   && NSEvent.global.isEmpty && NSEvent.local.isEmpty,
                   "leaving an eligible presentation cancels the press and removes every monitor")
        }
        let service = Service()
        service.geometry = NotchGeometry(screen: service.geometry.screen, safeAreaTop: 0, cameraWidth: 0)
        service.compactActivityIsVisible = true
        service.syncScreenEdgeClicks()
        suite.expect(service.screenEdgeClickArea?.width == service.geometry.cameraWidth
               && service.screenEdgeClickArea?.maxY == service.geometry.screen.maxY,
               "the simulated camera retains the same screen-edge activation area as a physical cutout")
        let point = CGPoint(x: service.geometry.screen.midX, y: service.geometry.screen.maxY)
        service.handleScreenEdgeClick(.leftMouseDown, at: point, isNotchWindow: false)
        service.handleScreenEdgeClick(.leftMouseUp, at: point, isNotchWindow: false)
        suite.expect(service.openings == 1 && service.screenEdgeClickMonitors.isEmpty,
               "clicking the top edge opens a simulated notch exactly once and stops its closed-state monitors")
    }
}
