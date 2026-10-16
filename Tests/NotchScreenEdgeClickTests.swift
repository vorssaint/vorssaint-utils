// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production routing and lifecycle with controlled event delivery, never posted input.
enum NotchScreenEdgeClickTests {
    final class Panel { var isVisible = true; var ignoresMouseEvents = false }
    final class Host { var acceptsPoint = true; func containsDestination(_ point: CGPoint) -> Bool { acceptsPoint } }
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
        var hoverEmphasized = false
        var surfaceSize: CGSize {
            let size = peeking ? geometry.expanded : compactActivityIsVisible ? geometry.compactActivitySize : geometry.collapsed
            return hoverEmphasized ? NotchHoverEmphasis.size(from: size, geometry: geometry) : size
        }
        var screenEdgeClickMonitors: [Any] = []
        var screenEdgePressArea: CGRect?
        var hoverWork: DispatchWorkItem?
        var hoverState = NotchHoverState()
        var compactActivity: NotchCompactActivity?
        var openings = 0, countdownOpenings = 0
        func openCountdownEvent() { countdownOpenings += 1; expanded = true }
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
                send(.leftMouseDown, top); send(.leftMouseDragged, CGPoint(x: screen.minX, y: screen.maxY)); send(.leftMouseUp, top)
                send(.leftMouseDown, top); send(.leftMouseUp, CGPoint(x: screen.minX, y: screen.maxY))
                suite.expect(service.openings == 0, "dragging off the island or releasing outside cancels an edge click")
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
        let steady = Service()
        steady.syncScreenEdgeClicks()
        let edge = CGPoint(x: steady.geometry.screen.midX, y: steady.geometry.screen.maxY)
        steady.handleScreenEdgeClick(.leftMouseDown, at: edge, isNotchWindow: false)
        steady.handleScreenEdgeClick(.leftMouseDragged, at: edge, isNotchWindow: false)
        steady.handleScreenEdgeClick(.leftMouseDragged, at: CGPoint(x: edge.x + 3, y: edge.y - 2), isNotchWindow: false)
        steady.handleScreenEdgeClick(.leftMouseUp, at: edge, isNotchWindow: false)
        suite.expect(steady.openings == 1,
               "the drag a press at the screen's edge reports, within the island, keeps the click")
        steady.removeScreenEdgeClickMonitors()
        let late = Service()
        late.geometry = NotchGeometry(screen: late.geometry.screen, safeAreaTop: 32, cameraWidth: 180, compactSideRoom: 64)
        late.syncScreenEdgeClicks()
        guard let resting = late.screenEdgeClickArea else { suite.expect(false, "a resting island takes edge clicks"); return }
        let centre = CGPoint(x: resting.midX, y: resting.maxY)
        late.handleScreenEdgeClick(.leftMouseDown, at: centre, isNotchWindow: false)
        // The entry is reported after the press, so the pulse lands before the release.
        late.hoverEmphasized = true
        guard let pulsed = late.screenEdgeClickArea else { suite.expect(false, "a pulsing island takes edge clicks"); return }
        // Released where only the grown island reaches.
        late.handleScreenEdgeClick(.leftMouseUp, at: CGPoint(x: pulsed.maxX - 4, y: pulsed.maxY), isNotchWindow: false)
        suite.expect(pulsed.maxX - 4 > resting.maxX && late.openings == 1,
                     "a click the hover pulse grows under still opens the island")
        late.removeScreenEdgeClickMonitors()
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
        let countdown = Service()
        countdown.compactActivity = .calendar
        countdown.syncScreenEdgeClicks()
        let countdownPoint = CGPoint(x: countdown.geometry.screen.midX, y: countdown.geometry.screen.maxY)
        countdown.handleScreenEdgeClick(.leftMouseDown, at: countdownPoint, isNotchWindow: false)
        countdown.handleScreenEdgeClick(.leftMouseUp, at: countdownPoint, isNotchWindow: false)
        suite.expect(countdown.countdownOpenings == 1 && countdown.openings == 0,
                     "clicking the top edge over an event countdown opens on its event")
        // A capsule floats below the top edge; the menu bar above it still
        // opens it, and the capsule itself takes its own clicks.
        for (depth, opens) in [(CGFloat(0), true), (1.5, true), (2.5, true), (3.5, false)] {
            let capsule = Service()
            capsule.geometry = NotchGeometry(screen: capsule.geometry.screen, safeAreaTop: 0, cameraWidth: 0,
                                             silhouette: .capsule)
            capsule.syncScreenEdgeClicks()
            let point = CGPoint(x: capsule.geometry.screen.midX, y: capsule.geometry.screen.maxY - depth)
            capsule.handleScreenEdgeClick(.leftMouseDown, at: point, isNotchWindow: false)
            capsule.handleScreenEdgeClick(.leftMouseUp, at: point, isNotchWindow: false)
            suite.expect(capsule.openings == (opens ? 1 : 0),
                         "a click \(depth) points below the top edge \(opens ? "opens" : "leaves") a floating capsule")
            capsule.removeScreenEdgeClickMonitors()
        }
    }
}
