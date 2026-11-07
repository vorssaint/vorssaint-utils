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
        var expandedGeometry: NotchGeometry { geometry }
        var hoverEmphasized = false
        var surfaceSize: CGSize {
            if expanded { return geometry.expanded }
            let size = peeking ? geometry.expanded : compactActivityIsVisible ? geometry.compactActivitySize : geometry.collapsed
            return hoverEmphasized ? NotchHoverEmphasis.size(from: size, geometry: geometry) : size
        }
        var screenEdgeClickMonitors: [Any] = []
        var screenEdgePressArea: CGRect?
        var screenEdgePressOpen = false
        var screenEdgeScrollMonitors: [Any] = []
        var inside = false
        var hoverWork: DispatchWorkItem?
        var hoverState = NotchHoverState()
        var compactActivity: NotchCompactActivity?
        var openings = 0, countdownOpenings = 0, closings = 0, gestures = 0
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
                suite.expect(service.openings == 1 && NSEvent.global.count == 1 && NSEvent.local.count == 1,
                       "a menu-bar click opens exactly once on either display and keeps watching to close")
                send(.leftMouseDown, top); send(.leftMouseUp, top)
                suite.expect(service.closings == 1 && service.openings == 1 && !service.expanded,
                       "a menu-bar click over the camera closes the open island exactly once on either display")
                service.removeScreenEdgeClickMonitors()
            }
        }
        for disable in [
            { (s: Service) in s.running = false }, { $0.suspended = true },
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
               "clicking the top edge opens a simulated notch exactly once, and with no camera to close from stops its monitors")
        let countdown = Service()
        countdown.compactActivity = .calendar
        countdown.syncScreenEdgeClicks()
        let countdownPoint = CGPoint(x: countdown.geometry.screen.midX, y: countdown.geometry.screen.maxY)
        countdown.handleScreenEdgeClick(.leftMouseDown, at: countdownPoint, isNotchWindow: false)
        countdown.handleScreenEdgeClick(.leftMouseUp, at: countdownPoint, isNotchWindow: false)
        suite.expect(countdown.countdownOpenings == 1 && countdown.openings == 0,
                     "clicking the top edge over an event countdown opens on its event")
        countdown.removeScreenEdgeClickMonitors()
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
        runOpenIsland(suite)
        runScrolls(suite)
    }

    private static func runOpenIsland(_ suite: TestSuite) {
        let open = Service()
        open.expanded = true
        open.syncScreenEdgeClicks()
        let top = CGPoint(x: open.geometry.screen.midX, y: open.geometry.screen.maxY)
        suite.expect(open.screenEdgeClickArea?.width == open.geometry.cameraWidth
                     && open.screenEdgeClickArea?.midX == open.geometry.screen.midX,
                     "the open island takes top-edge clicks over the camera only")
        // The menu bar still gets the click, so its items beside the camera keep theirs alone.
        let beside = CGPoint(x: top.x + open.geometry.cameraWidth, y: top.y)
        open.handleScreenEdgeClick(.leftMouseDown, at: beside, isNotchWindow: false)
        open.handleScreenEdgeClick(.leftMouseUp, at: beside, isNotchWindow: false)
        open.handleScreenEdgeClick(.leftMouseDown, at: top, isNotchWindow: true)
        open.handleScreenEdgeClick(.leftMouseUp, at: top, isNotchWindow: true)
        suite.expect(open.closings == 0 && open.expanded,
                     "menu items beside the camera and clicks the island's own window receives do not close it from here")
        open.keepsWorkingSurface = true
        open.handleScreenEdgeClick(.leftMouseDown, at: top, isNotchWindow: false)
        open.handleScreenEdgeClick(.leftMouseUp, at: top, isNotchWindow: false)
        open.keepsWorkingSurface = false
        suite.expect(open.closings == 0, "a modal or menu in the open island keeps it open")
        // A volume key can raise a notice under the open island.
        open.notice = true
        suite.expect(open.screenEdgeClickArea != nil, "a notice waiting behind the open island does not end its top-edge clicks")
        open.notice = nil
        open.handleScreenEdgeClick(.leftMouseDown, at: top, isNotchWindow: false)
        open.handleScreenEdgeClick(.leftMouseUp, at: top, isNotchWindow: false)
        suite.expect(open.closings == 1 && !open.expanded, "a top-edge click over the camera closes the open island")
        open.removeScreenEdgeClickMonitors()
        // Opening or closing another way during the press ends the click.
        let opened = Service()
        opened.syncScreenEdgeClicks()
        opened.handleScreenEdgeClick(.leftMouseDown, at: top, isNotchWindow: false)
        opened.expanded = true
        opened.syncScreenEdgeClicks()
        opened.handleScreenEdgeClick(.leftMouseUp, at: top, isNotchWindow: false)
        suite.expect(opened.expanded && opened.closings == 0 && opened.openings == 0,
                     "an island that opens during a press is not closed by its release")
        opened.removeScreenEdgeClickMonitors()
        let closed = Service()
        closed.expanded = true
        closed.syncScreenEdgeClicks()
        closed.handleScreenEdgeClick(.leftMouseDown, at: top, isNotchWindow: false)
        closed.expanded = false
        closed.syncScreenEdgeClicks()
        closed.handleScreenEdgeClick(.leftMouseUp, at: top, isNotchWindow: false)
        suite.expect(!closed.expanded && closed.openings == 0, "an island that closes during a press is not reopened by its release")
        closed.removeScreenEdgeClickMonitors()
        // With no camera, an open island has nothing here to toggle from.
        for silhouette in [NotchSilhouette.capsule, nil] {
            let plain = Service()
            plain.geometry = silhouette.map {
                NotchGeometry(screen: plain.geometry.screen, safeAreaTop: 0, cameraWidth: 0, silhouette: $0)
            } ?? NotchGeometry(screen: plain.geometry.screen, safeAreaTop: 0, cameraWidth: 0)
            plain.expanded = true
            suite.expect(plain.screenEdgeClickArea == nil, "an open island without a camera takes no top-edge clicks")
        }
    }

    private static func runScrolls(_ suite: TestSuite) {
        let service = Service()
        service.syncScreenEdgeScrolls()
        suite.expect(service.screenEdgeScrollMonitors.isEmpty, "scrolling elsewhere costs nothing while the pointer is off the island")
        service.inside = true
        for _ in 0..<100 { service.syncScreenEdgeScrolls() }
        suite.expect(NSEvent.global.count == 1 && NSEvent.local.count == 1,
                     "the pointer on the island keeps exactly one pair of scroll monitors")
        let top = CGPoint(x: service.geometry.screen.midX, y: service.geometry.screen.maxY)
        func send(_ point: CGPoint, window: Panel? = nil) {
            for handler in Array(NSEvent.global.values) { handler(NSEvent(.scrollWheel, point: point, window: window)) }
        }
        send(top)
        suite.expect(service.gestures == 1, "a swipe in the menu bar's row reaches the gesture")
        for handler in Array(NSEvent.local.values) {
            let event = NSEvent(.scrollWheel, point: top)
            suite.expect(handler(event) === event, "local observation preserves normal scroll delivery")
        }
        suite.expect(service.gestures == 2, "a swipe the app itself receives in that row reaches the gesture")
        send(CGPoint(x: top.x, y: top.y - 2))
        send(top, window: service.panel)
        suite.expect(service.gestures == 2, "a swipe below that row, or one the panel receives, is left to the panel")
        service.panel?.ignoresMouseEvents = true
        send(top)
        service.panel?.ignoresMouseEvents = false
        service.panel?.isVisible = false
        send(top)
        service.panel?.isVisible = true
        suite.expect(service.gestures == 2, "a hidden or click-through island ignores swipes in that row")
        // The island can live on a display that does not hold the menu bar's origin.
        let elsewhere = Service()
        elsewhere.geometry = NotchGeometry(screen: CGRect(x: -1920, y: 956, width: 1920, height: 1080), safeAreaTop: 32, cameraWidth: 180)
        elsewhere.handleScreenEdgeScroll(NSEvent(.scrollWheel, point: CGPoint(x: -960, y: 2036)))
        suite.expect(elsewhere.gestures == 1, "the row is found on a display above the main one")
        // The menu bar a capsule leaves above itself is the island's.
        for (depth, reaches) in [(CGFloat(2.5), true), (3.5, false)] {
            let capsule = Service()
            capsule.geometry = NotchGeometry(screen: capsule.geometry.screen, safeAreaTop: 0, cameraWidth: 0, silhouette: .capsule)
            capsule.handleScreenEdgeScroll(NSEvent(.scrollWheel, point: CGPoint(x: top.x, y: top.y - depth)))
            suite.expect((capsule.gestures == 1) == reaches, "a swipe \(depth) points below the top edge \(reaches ? "reaches" : "leaves") a capsule")
        }
        service.inside = false
        service.syncScreenEdgeScrolls()
        suite.expect(NSEvent.global.isEmpty && NSEvent.local.isEmpty, "the pointer leaving the island removes the scroll monitors")
        service.inside = true
        service.syncScreenEdgeScrolls()
        service.suspended = true
        service.syncScreenEdgeScrolls()
        suite.expect(NSEvent.global.isEmpty && NSEvent.local.isEmpty, "a suspended island removes the scroll monitors")
    }
}
