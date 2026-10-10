// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production routing and lifecycle with controlled event delivery, never posted input.
enum NotchScreenEdgeScrollTests {
    final class Panel { var isVisible = true; var ignoresMouseEvents = false }
    enum NSScreen {
        static var withMenuBar: Screen? = Screen()
        struct Screen { let frame = CGRect(x: 0, y: 0, width: 1470, height: 956) }
    }
    final class NSEvent {
        typealias EventTypeMask = AppKit.NSEvent.EventTypeMask
        struct CGEvent { let location: CGPoint }
        let cgEvent: CGEvent?
        init(scrollAt point: CGPoint) { cgEvent = CGEvent(location: CGPoint(x: point.x, y: 956 - point.y)) }
        static var global: [Int: (NSEvent) -> Void] = [:]
        static var nextID = 0
        static func addGlobalMonitorForEvents(matching: EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any? {
            nextID += 1; global[nextID] = handler; return nextID
        }
        static func removeMonitor(_ token: Any) { global[token as! Int] = nil }
    }
    class State {
        var running = true, suspended = false, gesturesEnabled = true
        var panel: Panel? = Panel()
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                     safeAreaTop: 32, cameraWidth: 180)
        var screenEdgeScrollMonitors: [Any] = []
        var gesturePoints: [CGPoint?] = []
        @discardableResult func handleGesture(_ event: NSEvent, at screenPoint: CGPoint? = nil) -> Bool {
            gesturePoints.append(screenPoint)
            return true
        }
    }

    static func run(_ suite: TestSuite) {
        for screen in [CGRect(x: 0, y: 0, width: 1470, height: 956),
                       CGRect(x: -1920, y: 956, width: 1920, height: 1080)] {
            let service = Service()
            service.geometry = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 180)
            service.syncScreenEdgeScrolls()
            service.syncScreenEdgeScrolls()
            suite.expect(NSEvent.global.count == 1,
                         "refreshes keep exactly one global edge-scroll monitor")
            func scroll(_ point: CGPoint) { for handler in Array(NSEvent.global.values) { handler(NSEvent(scrollAt: point)) } }
            scroll(CGPoint(x: screen.midX, y: screen.maxY))
            scroll(CGPoint(x: screen.midX, y: screen.maxY - 0.75))
            suite.expect(service.gesturePoints == [CGPoint(x: screen.midX, y: screen.maxY - 0.5),
                                                   CGPoint(x: screen.midX, y: screen.maxY - 0.75)],
                         "a scroll on the screen's first row reaches the island at least half a point inside it")
            service.gesturePoints.removeAll()
            scroll(CGPoint(x: screen.midX, y: screen.maxY - 1))
            scroll(CGPoint(x: screen.midX, y: screen.maxY - 12))
            scroll(CGPoint(x: screen.maxX, y: screen.maxY))
            scroll(CGPoint(x: screen.minX - 1, y: screen.maxY))
            suite.expect(service.gesturePoints.isEmpty,
                         "scrolls below the first row or beside the island's display stay with their window")
            service.gesturePoints.removeAll()
            service.removeScreenEdgeScrollMonitors()
        }

        // Moving the island from a physical notch to a non-notched display
        // disables forwarding, regardless of its simulated silhouette.
        for silhouette in [NotchSilhouette.capsule, .notch] {
            let simulated = Service()
            simulated.syncScreenEdgeScrolls()
            let handlers = Array(NSEvent.global.values)
            simulated.geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                               safeAreaTop: 0, cameraWidth: 0, silhouette: silhouette)
            let screen = simulated.geometry.screen
            for handler in handlers {
                handler(NSEvent(scrollAt: CGPoint(x: screen.midX, y: screen.maxY)))
                handler(NSEvent(scrollAt: CGPoint(x: screen.midX, y: screen.maxY - 2)))
            }
            suite.expect(simulated.gesturePoints.isEmpty,
                         "a stale monitor never forwards top-edge scrolls on a non-notched display")
            simulated.syncScreenEdgeScrolls()
            suite.expect(NSEvent.global.isEmpty && simulated.screenEdgeScrollMonitors.isEmpty,
                         "non-notched displays remove the physical notch's edge-scroll monitor")
            simulated.syncScreenEdgeScrolls()
            suite.expect(NSEvent.global.isEmpty,
                         "simulated notches and capsules never install an edge-scroll monitor")
        }

        let service = Service()
        service.gesturesEnabled = false
        service.syncScreenEdgeScrolls()
        suite.expect(NSEvent.global.isEmpty, "edge scrolls are not observed while island gestures are off")
        service.gesturesEnabled = true
        service.syncScreenEdgeScrolls()
        service.gesturesEnabled = false
        for handler in Array(NSEvent.global.values) {
            handler(NSEvent(scrollAt: CGPoint(x: service.geometry.screen.midX, y: service.geometry.screen.maxY)))
        }
        suite.expect(service.gesturePoints.isEmpty, "a monitor that outlives the preference hands nothing to the island")
        service.removeScreenEdgeScrollMonitors()
        suite.expect(NSEvent.global.isEmpty, "removal leaves no edge-scroll monitor behind")

        let hides: [(Service) -> Void] = [{ $0.panel?.isVisible = false }, { $0.panel?.ignoresMouseEvents = true },
                                          { $0.suspended = true }, { $0.running = false }]
        for hide in hides {
            let hidden = Service()
            hidden.syncScreenEdgeScrolls()
            hide(hidden)
            hidden.syncScreenEdgeScrolls()
            suite.expect(NSEvent.global.isEmpty && hidden.screenEdgeScrollMonitors.isEmpty,
                         "an island that cannot take a scroll removes its edge-scroll monitor")
        }
    }
}
