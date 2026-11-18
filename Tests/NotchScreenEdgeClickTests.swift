// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production routing and lifecycle with controlled event delivery, never posted input.
enum NotchScreenEdgeClickTests {
    final class Panel { var isVisible = true; var ignoresMouseEvents = false }
    final class Host {
        var acceptsPoint = true, isConcealedForMissionControl = false
        func containsDestination(_ point: CGPoint) -> Bool { acceptsPoint }
    }
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
    final class NotchNotificationService {
        enum ActionResult { case handedOff, unavailable, uncertain }
        static let shared = NotchNotificationService()
        var openingID: UUID?
        var requested: [UUID] = []
        var delaysResult = false
        var completion: ((ActionResult) -> Void)?
        func open(_ id: UUID, completion: @escaping (ActionResult) -> Void) {
            requested.append(id)
            if delaysResult { openingID = id; self.completion = completion }
            else { completion(.handedOff) }
        }
        func finish(_ result: ActionResult) {
            let pending = completion
            completion = nil
            openingID = nil
            pending?(result)
        }
    }
    class State {
        var running = true, suspended = false, expanded = false, peeking = false
        var captureControls: Bool?, notice: NotchNotice?, departingNotice: NotchNotice?
        var noticeExpanded = false
        var hiddenInFullscreen = false, routesNotices = true
        var dragPlaceholder = false, heldDrag = false, compactActivityIsVisible = false, keepsWorkingSurface = false
        var panel: Panel? = Panel()
        var windowHost: Host? = Host()
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                     safeAreaTop: 32, cameraWidth: 180)
        var compactActivityGeometry: NotchGeometry { geometry }
        var hoverEmphasized = false
        var bannerCapsuleWidth: CGFloat = 0
        var surfaceSize: CGSize {
            if let notice {
                return geometry.floats ? capsuleNoticeSize(notice) : geometry.noticeSize(wings: notice.wings(in: geometry))
            }
            let size = peeking ? geometry.expanded : compactActivityIsVisible ? geometry.compactActivitySize : geometry.collapsed
            return hoverEmphasized ? NotchHoverEmphasis.size(from: size, geometry: geometry) : size
        }
        var screenEdgeClickMonitors: [Any] = []
        var screenEdgePress: (area: CGRect, point: CGPoint, notice: NotchNotice?)?
        var hoverWork: DispatchWorkItem?
        var hoverState = NotchHoverState()
        var compactActivity: NotchCompactActivity?
        var openings = 0, countdownOpenings = 0
        var opened: NotchModule?
        func openCountdownEvent() { countdownOpenings += 1; expanded = true }
        func settleNotificationHover() {}
        func dismissNotice() { notice = nil; departingNotice = nil; noticeExpanded = false }
    }

    private static let track = NotchNotice(event: .track, title: "Song", detail: "Artist", symbol: "music.note")
    private static let volume = NotchNotice(event: .volume, title: "Volume", detail: "50%", symbol: "speaker.wave.2.fill")

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
            { $0.captureControls = true }, { $0.notice = track; $0.noticeExpanded = true },
            { $0.dragPlaceholder = true }, { $0.heldDrag = true }
        ] {
            let service = Service()
            service.syncScreenEdgeClicks()
            let point = CGPoint(x: service.geometry.screen.midX, y: service.geometry.screen.maxY)
            service.handleScreenEdgeClick(.leftMouseDown, at: point, isNotchWindow: false)
            disable(service)
            service.syncScreenEdgeClicks()
            service.handleScreenEdgeClick(.leftMouseUp, at: point, isNotchWindow: false)
            suite.expect(service.openings == 0 && service.screenEdgePress == nil
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
        service.geometry = NotchGeometry(screen: service.geometry.screen, safeAreaTop: 0, cameraWidth: 0, compactSideRoom: 0)
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
        countdown.removeScreenEdgeClickMonitors()
        // A capsule floats below the top edge; the menu bar above it still
        // opens it, and the capsule itself takes its own clicks.
        for (depth, opens) in [(CGFloat(0), true), (1.5, true), (2.5, true), (3.5, false)] {
            let capsule = Service()
            capsule.geometry = NotchGeometry(screen: capsule.geometry.screen, safeAreaTop: 0, cameraWidth: 0,
                                             compactSideRoom: 64, silhouette: .capsule)
            capsule.syncScreenEdgeClicks()
            let point = CGPoint(x: capsule.geometry.screen.midX, y: capsule.geometry.screen.maxY - depth)
            capsule.handleScreenEdgeClick(.leftMouseDown, at: point, isNotchWindow: false)
            capsule.handleScreenEdgeClick(.leftMouseUp, at: point, isNotchWindow: false)
            suite.expect(capsule.openings == (opens ? 1 : 0),
                         "a click \(depth) points below the top edge \(opens ? "opens" : "leaves") a floating capsule")
            capsule.removeScreenEdgeClickMonitors()
        }
        runNotices(suite)
        runBannerChanges(suite)
        runMenuClearance(suite)
        runChangingNotices(suite)
    }

    private static func runNotices(_ suite: TestSuite) {
        // The menu bar owns the top row, so a notice needs these clicks as much
        // as the resting island does, and each one opens where it leads.
        for (shown, module) in [(track, NotchModule.music), (volume, .controls)] {
            let service = Service()
            service.notice = shown
            service.syncScreenEdgeClicks()
            let top = CGPoint(x: service.geometry.screen.midX, y: service.geometry.screen.maxY)
            service.handleScreenEdgeClick(.leftMouseDown, at: top, isNotchWindow: false)
            service.handleScreenEdgeClick(.leftMouseUp, at: top, isNotchWindow: false)
            suite.expect(service.openings == 1 && service.opened == module && service.expanded,
                         "a top-edge click on a \(shown.event) notice opens its page")
            suite.expect(service.notice == nil, "a \(shown.event) notice that opened its page does not return after closing")
            suite.expect(service.screenEdgeClickMonitors.isEmpty, "opening from a notice removes the edge monitors")
        }
        let native = Service()
        native.notice = track
        native.syncScreenEdgeClicks()
        let nativeTop = CGPoint(x: native.geometry.screen.midX, y: native.geometry.screen.maxY)
        native.handleScreenEdgeClick(.leftMouseDown, at: nativeTop, isNotchWindow: true)
        native.handleScreenEdgeClick(.leftMouseUp, at: nativeTop, isNotchWindow: true)
        suite.expect(native.openings == 0, "a click the notice's own window receives is not handled twice")
        native.removeScreenEdgeClickMonitors()
        // The notice's button stays on screen while it closes.
        let closing = Service()
        closing.departingNotice = track
        closing.activateNotice(track)
        suite.expect(closing.openings == 1 && closing.opened == .music && closing.departingNotice == nil,
                     "a click on a closing notice opens its page")
        let stale = Service()
        stale.notice = volume
        stale.departingNotice = track
        stale.activateNotice(track)
        suite.expect(stale.openings == 0 && stale.notice == volume, "a superseded outgoing button leaves the new notice alone")
        // The normal activity is Calendar. Releasing this press must still select Music.
        for stillDeparting in [true, false] {
            let expiring = Service()
            expiring.compactActivity = .calendar
            expiring.notice = track
            expiring.syncScreenEdgeClicks()
            let top = CGPoint(x: expiring.geometry.screen.midX, y: expiring.geometry.screen.maxY)
            menuBarEvent(.leftMouseDown, at: top)
            expiring.notice = nil
            expiring.departingNotice = stillDeparting ? track : nil
            expiring.syncScreenEdgeClicks()
            menuBarEvent(.leftMouseUp, at: top)
            suite.expect(expiring.openings == 1 && expiring.opened == .music && expiring.countdownOpenings == 0,
                         "the press keeps Music through the outgoing animation and after expiry")
        }
        // A press lands on the resting island and a notice arrives before the release.
        let arriving = Service()
        arriving.syncScreenEdgeClicks()
        let arrivingTop = CGPoint(x: arriving.geometry.screen.midX, y: arriving.geometry.screen.maxY)
        arriving.handleScreenEdgeClick(.leftMouseDown, at: arrivingTop, isNotchWindow: false)
        arriving.notice = volume
        arriving.handleScreenEdgeClick(.leftMouseUp, at: arrivingTop, isNotchWindow: false)
        suite.expect(arriving.openings == 1 && arriving.opened == nil,
                     "a press on the resting island keeps its normal opening when a notice arrives")
        // The menu bar still gets the click, so the items under a notice's wings keep theirs alone.
        let winged = Service()
        winged.notice = track
        winged.syncScreenEdgeClicks()
        let wing = CGPoint(x: winged.geometry.screen.midX + 150, y: winged.geometry.screen.maxY)
        winged.handleScreenEdgeClick(.leftMouseDown, at: wing, isNotchWindow: false)
        winged.handleScreenEdgeClick(.leftMouseUp, at: wing, isNotchWindow: false)
        suite.expect(winged.screenEdgeClickArea?.width == winged.geometry.cameraWidth
                     && winged.screenEdgeClickArea?.midX == winged.geometry.screen.midX && winged.openings == 0,
                     "beside a camera a notice takes top-edge clicks over the camera only")
        winged.removeScreenEdgeClickMonitors()
        // A capsule leaves the menu bar above it to the island, end to end.
        let capsule = Service()
        capsule.geometry = NotchGeometry(screen: capsule.geometry.screen, safeAreaTop: 0, cameraWidth: 0,
                                         compactSideRoom: 160, silhouette: .capsule)
        capsule.notice = NotchNotice(event: .track, title: "A song with a long title", detail: "A long artist name", symbol: "music.note")
        capsule.syncScreenEdgeClicks()
        let end = CGPoint(x: capsule.geometry.screen.midX + capsule.surfaceSize.width / 2 - NotchCapsuleLayout.side(capsule.geometry) - 1,
                          y: capsule.geometry.screen.maxY)
        capsule.handleScreenEdgeClick(.leftMouseDown, at: end, isNotchWindow: false)
        capsule.handleScreenEdgeClick(.leftMouseUp, at: end, isNotchWindow: false)
        suite.expect(capsule.openings == 1 && capsule.opened == .music,
                     "a capsule's notice takes the menu bar's clicks along its whole width")
        // A banner opens what it announces rather than the island.
        let id = UUID()
        let banner = Service()
        banner.notice = NotchNotice(event: .systemNotification, title: "Mail", detail: "", symbol: "bell",
                                    notificationID: id)
        banner.syncScreenEdgeClicks()
        let bannerTop = CGPoint(x: banner.geometry.screen.midX, y: banner.geometry.screen.maxY)
        banner.handleScreenEdgeClick(.leftMouseDown, at: bannerTop, isNotchWindow: false)
        banner.handleScreenEdgeClick(.leftMouseUp, at: bannerTop, isNotchWindow: false)
        suite.expect(NotchNotificationService.shared.requested.last == id && banner.openings == 0,
                     "a top-edge click on a banner opens its notification, not the island")
        banner.removeScreenEdgeClickMonitors()
    }

    private static func menuBarEvent(_ type: NSEvent.EventType, at point: CGPoint) {
        for handler in Array(NSEvent.global.values) { handler(NSEvent(type, point: point)) }
    }

    private static func runBannerChanges(_ suite: TestSuite) {
        let notifications = NotchNotificationService.shared
        let first = NotchNotice(event: .systemNotification, title: "First", detail: "", symbol: "bell", notificationID: UUID())
        let nextID = UUID()
        let next = NotchNotice(event: .systemNotification, title: "Next", detail: "", symbol: "bell", notificationID: nextID)
        let service = Service()
        let top = CGPoint(x: service.geometry.screen.midX, y: service.geometry.screen.maxY)
        defer {
            service.removeScreenEdgeClickMonitors()
            notifications.delaysResult = false
            notifications.requested.removeAll()
        }
        notifications.requested.removeAll()
        service.syncScreenEdgeClicks()
        menuBarEvent(.leftMouseDown, at: top)
        service.notice = first
        service.syncScreenEdgeClicks()
        menuBarEvent(.leftMouseUp, at: top)
        suite.expect(service.notice == first && service.openings == 0 && notifications.requested.isEmpty,
                     "a banner arriving over a resting press keeps its message and its native action")
        for expires in [false, true] {
            service.notice = first
            service.syncScreenEdgeClicks()
            menuBarEvent(.leftMouseDown, at: top)
            service.notice = next
            service.syncScreenEdgeClicks()
            if expires { service.notice = nil; service.syncScreenEdgeClicks() }
            menuBarEvent(.leftMouseUp, at: top)
            suite.expect(notifications.requested.isEmpty && service.openings == 0,
                         "a replacement cancels the old press even if the replacement also expires")
        }
        // A fresh click on the replacement is valid. Its completion may come after another arrival.
        service.notice = next
        notifications.delaysResult = true
        service.syncScreenEdgeClicks()
        menuBarEvent(.leftMouseDown, at: top)
        menuBarEvent(.leftMouseUp, at: top)
        suite.expect(notifications.requested == [nextID] && service.openings == 0,
                     "a new press opens the replacement notification by its own id")
        service.notice = first
        notifications.finish(.unavailable)
        suite.expect(service.notice == first && service.openings == 0, "a late failure leaves the next banner visible")
        menuBarEvent(.leftMouseDown, at: top)
        menuBarEvent(.leftMouseUp, at: top)
        notifications.finish(.uncertain)
        suite.expect(service.opened == .notifications && service.notice == nil,
                     "a failed action for the banner still on screen opens the inbox")
    }

    private static func runMenuClearance(_ suite: TestSuite) {
        for silhouette in [NotchSilhouette.capsule, .notch] {
            let service = Service()
            let screen = service.geometry.screen
            service.geometry = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, silhouette: silhouette)
            service.notice = volume
            let top = CGPoint(x: screen.midX, y: screen.maxY)
            let menu = CGRect(x: top.x - 10, y: top.y - 24, width: 20, height: 24)
            let blocked = NotchMenuBarLayout.sideRoom(screen: screen, cameraWidth: service.geometry.cameraWidth,
                                                      barHeight: 24, occupied: [menu])
            service.syncScreenEdgeClicks()
            suite.expect(blocked == nil && service.screenEdgeClickMonitors.isEmpty,
                         "a notice without a verified center leaves the top row with the menu")
            service.applyMenuSpace(0)
            menuBarEvent(.leftMouseDown, at: top)
            service.applyMenuSpace(blocked)
            suite.expect(service.screenEdgeClickMonitors.isEmpty && service.screenEdgePress == nil,
                         "a menu taking the simulated center cancels the press")
            service.applyMenuSpace(0)
            menuBarEvent(.leftMouseUp, at: top)
            suite.expect(service.openings == 0, "restoring clearance never rearms an interrupted press")
            menuBarEvent(.leftMouseDown, at: top)
            menuBarEvent(.leftMouseUp, at: top)
            suite.expect(service.openings == 1 && service.opened == .controls,
                         "a verified center takes a new click even with zero free room beside it")
            service.removeScreenEdgeClickMonitors()
        }
    }

    private static func runChangingNotices(_ suite: TestSuite) {
        let meter = Service()
        let top = CGPoint(x: meter.geometry.screen.midX, y: meter.geometry.screen.maxY)
        let reading = NotchNotice(event: .volume, title: "Volume", detail: "50%", symbol: "speaker", level: 0.5)
        meter.notice = reading
        meter.syncScreenEdgeClicks()
        menuBarEvent(.leftMouseDown, at: top)
        meter.notice = NotchNotice(event: .volume, title: "Volume", detail: "60%", symbol: "speaker", level: 0.6)
        meter.syncScreenEdgeClicks()
        menuBarEvent(.leftMouseUp, at: top)
        suite.expect(meter.opened == .controls, "an updated level keeps the original control's click")

        let wing = Service()
        wing.geometry = NotchGeometry(screen: wing.geometry.screen, safeAreaTop: 32, cameraWidth: 180, compactSideRoom: 64)
        wing.syncScreenEdgeClicks()
        let beside = CGPoint(x: top.x + wing.geometry.cameraWidth / 2 + 8, y: top.y)
        menuBarEvent(.leftMouseDown, at: beside)
        wing.notice = volume
        wing.syncScreenEdgeClicks()
        menuBarEvent(.leftMouseUp, at: beside)
        suite.expect(wing.openings == 0 && wing.notice == volume, "a notice arriving under a resting wing leaves the release to the menu")
        menuBarEvent(.leftMouseDown, at: top)
        wing.notice = nil
        wing.routesNotices = false
        menuBarEvent(.leftMouseUp, at: top)
        suite.expect(wing.openings == 0, "turning the notice off during a press cancels its action")
        wing.removeScreenEdgeClickMonitors()

        for room in [CGFloat(0), 160] {
            let capsule = Service()
            capsule.geometry = NotchGeometry(screen: capsule.geometry.screen, safeAreaTop: 0, cameraWidth: 0,
                                             compactSideRoom: 160, silhouette: .capsule)
            capsule.notice = NotchNotice(event: .track, title: "A long track title that fills the capsule", detail: "Artist", symbol: "music.note")
            let point = CGPoint(x: top.x + capsule.geometry.cameraWidth / 2 + 8, y: top.y)
            capsule.syncScreenEdgeClicks()
            menuBarEvent(.leftMouseDown, at: point)
            suite.expect(capsule.screenEdgePress != nil, "the wide notice took the original press")
            capsule.notice = nil
            capsule.applyMenuSpace(room)
            capsule.windowHost?.acceptsPoint = false
            menuBarEvent(.leftMouseUp, at: point)
            suite.expect(capsule.opened == (room == 0 ? nil : .music),
                         "a capsule shrinking under a stationary press keeps its action only while the menu bar still has room")
            capsule.removeScreenEdgeClickMonitors()
        }
    }
}
