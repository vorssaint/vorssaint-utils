// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Exercises the production hover handler with a controlled clock and pointer.
/// No input is posted and the user's preferences are never read or changed.
enum NotchHoverTests {
    typealias DispatchQueue = NotchScreenRefreshContract.DispatchQueue
    final class NSEvent {
        typealias EventTypeMask = AppKit.NSEvent.EventTypeMask
        static var mouseLocation = CGPoint.zero
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
    enum UserDefaults {
        static var standard = Preferences()
        struct Preferences {
            var enabled = true, expands = true, hides = false
            var delay = NotchSupport.defaultHoverDelay
            func bool(forKey key: String) -> Bool {
                key == DefaultsKey.notchHideUntilHover ? hides : key == DefaultsKey.notchOpenOnHover ? enabled : expands
            }
            func double(forKey key: String) -> Double { delay }
        }
    }
    enum AssistiveKeyboard {
        static var active = false
        static func ownsCocoaPoint(_ point: CGPoint) -> Bool { active }
    }
    final class Host {
        var visible = true
        var rect = CGRect.zero
        var isConcealedForMissionControl = false
        var revealChecks = 0
        func blocksHoverReveal() -> Bool {
            revealChecks += 1
            return isConcealedForMissionControl
        }
        func containsHover(_ point: CGPoint) -> Bool {
            visible && !isConcealedForMissionControl && CGRect(origin: .zero, size: rect.size)
                .contains(CGPoint(x: point.x - rect.minX, y: rect.maxY - point.y))
        }
    }
    enum NotchContentTransition { case none, reveal, dismiss, replace }
    class State {
        var hiddenInFullscreen = false
        var showsSystemFeedback = true, routesNotices = true
        var running = true, suspended = false, inside = false
        var pinned = false, heldDrag = false, keepsWorkingSurface = false
        var expanded = false, peeking = false, dragPlaceholder = false, openedByHover = false
        var captureControls: Bool?, notice: NotchNotice?
        var noticeExpanded = false
        var noticeWork: DispatchWorkItem?
        var compactActivity: NotchCompactActivity?
        var hoverState = NotchHoverState()
        var hiddenHoverMonitors: [Any] = []
        var hoverWork: DispatchWorkItem?
        var captureHover: ((Bool) -> Void)?
        func updateCaptureControlsHover(wasInside: Bool) {}
        func updateCaptureControlsClickThrough() {}
        var windowHost: Host? = Host()
        var geometry = NotchGeometry(screen: CGRect(x: -1920, y: 900, width: 1920, height: 1080),
                                     safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 22, compactSideRoom: 64)
        var compactActivityGeometry: NotchGeometry { geometry.compactMusicGeometry }
        var surfaceSize: CGSize {
            if let notice {
                guard noticeExpanded else { return geometry.noticeSize(wingWidth: notice.preferredWingWidth) }
                return geometry.notificationPreviewSize(
                    contentHeight: notice.previewContentHeight(width: geometry.notificationPreviewContentWidth))
            }
            return expanded ? geometry.expanded : peeking ? geometry.peek : geometry.collapsed
        }
        var openings = 0, closures = 0, feedbacks = 0
        var requestedModule: NotchModule?
        func open(_ module: NotchModule? = nil, takeFocus: Bool) {
            requestedModule = module
            openings += 1; expanded = true; openedByHover = !takeFocus
            hoverState.open(); hoverWork?.cancel(); hoverWork = nil
            updateBounds()
        }
        func collapse() {
            closures += 1; expanded = false; peeking = false; openedByHover = false
            hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
            hoverWork?.cancel(); hoverWork = nil
            updateBounds()
        }
        func mutatePresentation(transitionContent: NotchContentTransition, _ change: () -> Void) { change(); updateBounds() }
        func provideHapticFeedback() { feedbacks += 1 }
        func updateBounds() { windowHost?.rect = geometry.frame(for: surfaceSize) }
    }

    static func run(_ suite: TestSuite) {
        func expect(_ condition: Bool, _ message: String) {
            suite.expect(condition, message)
        }
        let volume = NotchNotice(event: .volume, title: "Volume", detail: "50%", symbol: "speaker.wave.2.fill", level: 0.5)
        func fixture(physical: Bool = false) -> Service {
            DispatchQueue.main = NotchScreenRefreshContract.Scheduler()
            UserDefaults.standard = UserDefaults.Preferences()
            AssistiveKeyboard.active = false
            let service = Service()
            if physical {
                service.geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                                 safeAreaTop: 32, cameraWidth: 180, compactSideRoom: 64)
            }
            service.updateBounds()
            NSEvent.mouseLocation = CGPoint(x: service.geometry.screen.midX, y: service.geometry.screen.maxY)
            return service
        }
        func leave(_ service: Service) {
            NSEvent.mouseLocation = CGPoint(x: service.geometry.screen.minX, y: service.geometry.screen.minY)
            service.hover(false)
        }
        for physical in [false, true] {
            let service = fixture(physical: physical)
            service.hover(true)
            let initial = service.hoverWork
            DispatchQueue.main.advance(0.20)
            suite.expect(service.openings == 0, "passing briefly over either display's island does not open it")
            service.hover(false) // A tracking exit while the pointer is still inside.
            suite.expect(service.hoverWork === initial, "duplicate tracking events preserve the original opening deadline")
            DispatchQueue.main.advance(0.06)
            suite.expect(service.openings == 1 && service.openedByHover && service.hoverWork == nil,
                   "a deliberate hover opens after the default 250 ms on both physical and simulated cutouts")
            leave(service)
            let closing = service.hoverWork
            DispatchQueue.main.advance(0.10)
            service.hover(false)
            suite.expect(service.hoverWork === closing, "overlapping exit events do not postpone closing")
            DispatchQueue.main.advance(0.09)
            suite.expect(service.closures == 1 && service.hoverWork == nil,
                   "leaving either display's expanded island closes it within 190 ms")
        }
        for physical in [false, true] {
            for local in [false, true] {
                let hidden = fixture(physical: physical)
                UserDefaults.standard.hides = true
                hidden.windowHost?.visible = false
                hidden.notice = volume // A notice already present when the preference changes.
                hidden.syncHiddenHoverMonitoring()
                for _ in 0..<100 { hidden.syncHiddenHoverMonitoring() }
                suite.expect(NSEvent.global.count == 1 && NSEvent.local.count == 1,
                       "hidden mode keeps one pair of native movement observers")
                func move(to point: CGPoint) {
                    NSEvent.mouseLocation = point
                    let event = NSEvent()
                    if local {
                        for handler in Array(NSEvent.local.values) {
                            suite.expect(handler(event) === event, "hidden hover never consumes the original local event")
                        }
                    } else { for handler in Array(NSEvent.global.values) { handler(event) } }
                }
                let top = CGPoint(x: hidden.geometry.screen.midX, y: hidden.geometry.screen.maxY)
                move(to: top)
                DispatchQueue.main.advance(0.20)
                suite.expect(hidden.openings == 0, "a hidden island honors the saved activation delay")
                move(to: CGPoint(x: hidden.geometry.screen.minX, y: hidden.geometry.screen.minY))
                DispatchQueue.main.advance(0.20)
                suite.expect(hidden.openings == 0, "leaving the invisible region cancels pending activation")
                move(to: top)
                DispatchQueue.main.advance(0.26)
                suite.expect(hidden.openings == 1 && hidden.openedByHover,
                       "local and global movement reveal either display without a visible window or menu measurement")
                hidden.windowHost?.visible = true
                hidden.syncHiddenHoverMonitoring()
                suite.expect(NSEvent.global.isEmpty && NSEvent.local.isEmpty,
                       "revealing hands hover back to native window tracking")
                leave(hidden)
                DispatchQueue.main.advance(0.20)
                suite.expect(hidden.closures == 1 && hidden.hiddenUntilHover,
                       "leaving returns the revealed island to its hidden state")
                hidden.syncHiddenHoverMonitoring()
                hidden.running = false
                hidden.syncHiddenHoverMonitoring()
                suite.expect(NSEvent.global.isEmpty && NSEvent.local.isEmpty,
                       "stopping releases both hidden hover observers")
            }
        }
        for expands in [false, true] {
            let hidden = fixture()
            UserDefaults.standard.hides = true
            UserDefaults.standard.expands = expands
            hidden.windowHost?.visible = false
            hidden.windowHost?.isConcealedForMissionControl = true
            hidden.hover(true)
            suite.expect(!hidden.inside && hidden.hoverWork == nil,
                         "Mission Control cannot start a hidden island's hover deadline")
            hidden.windowHost?.isConcealedForMissionControl = false
            hidden.hover(true)
            suite.expect(hidden.inside && hidden.hoverWork != nil,
                         "leaving Mission Control allows a fresh hidden hover deadline")
            hidden.windowHost?.isConcealedForMissionControl = true
            DispatchQueue.main.advance(0.26)
            suite.expect(hidden.openings == 0 && !hidden.peeking && hidden.windowHost?.revealChecks == 1,
                         "Mission Control starting during the hover delay blocks expansion and preview")

            let visible = fixture()
            UserDefaults.standard.expands = expands
            visible.hover(true)
            suite.expect(visible.inside && visible.hoverWork != nil,
                         "a visible island has a pending hover deadline before Mission Control")
            visible.windowHost?.isConcealedForMissionControl = true
            DispatchQueue.main.advance(0.26)
            suite.expect(visible.openings == 0 && !visible.peeking && visible.windowHost?.revealChecks == 1,
                         "Mission Control blocks a pending visible hover without a mouse-exit event")
            visible.windowHost?.isConcealedForMissionControl = false
            visible.missionControlDidRestore()
            suite.expect(visible.hoverWork != nil,
                         "restoring Mission Control restarts a hover deadline when the pointer stayed over the island")
            DispatchQueue.main.advance(0.26)
            suite.expect(expands ? visible.openings == 1 : visible.peeking,
                         "the restored hover opens the island after its normal delay")
        }
        let capturePreview = fixture()
        capturePreview.expanded = true
        capturePreview.updateBounds()
        var previewHovered: Bool?
        capturePreview.captureHover = { previewHovered = $0 }
        capturePreview.windowHost?.isConcealedForMissionControl = true
        capturePreview.windowHost?.isConcealedForMissionControl = false
        capturePreview.missionControlDidRestore()
        suite.expect(previewHovered == true,
                     "restoring with the pointer over a capture preview keeps its auto-dismiss paused")

        let departed = fixture()
        departed.hover(true)
        DispatchQueue.main.advance(0.26)
        suite.expect(departed.expanded && departed.openedByHover,
                     "the island is open from hover before Mission Control")
        departed.windowHost?.isConcealedForMissionControl = true
        NSEvent.mouseLocation = CGPoint(x: departed.geometry.screen.minX, y: departed.geometry.screen.minY)
        departed.windowHost?.isConcealedForMissionControl = false
        departed.missionControlDidRestore()
        suite.expect(!departed.inside && departed.hoverWork != nil,
                     "restoration notices that the pointer left while Mission Control owned input")
        DispatchQueue.main.advance(0.19)
        suite.expect(departed.closures == 1,
                     "the hover-open island closes after its normal pointer exit delay")
        for disable: (Service) -> Void in [
            { $0.suspended = true }, { $0.windowHost = nil },
            { _ in UserDefaults.standard.hides = false }, { _ in UserDefaults.standard.enabled = false }
        ] {
            let hidden = fixture()
            UserDefaults.standard.hides = true
            hidden.syncHiddenHoverMonitoring()
            disable(hidden)
            hidden.syncHiddenHoverMonitoring()
            suite.expect(NSEvent.global.isEmpty && NSEvent.local.isEmpty,
                   "suspension, missing display and preference changes release hidden hover observers")
        }
        let passing = fixture()
        passing.hover(true)
        DispatchQueue.main.advance(0.20)
        leave(passing)
        DispatchQueue.main.advance(1)
        suite.expect(passing.openings == 0, "leaving before the opening deadline cancels expansion")

        let reentering = fixture()
        reentering.hover(true)
        DispatchQueue.main.advance(0.20)
        leave(reentering)
        DispatchQueue.main.advance(0.02)
        NSEvent.mouseLocation = CGPoint(x: reentering.geometry.screen.midX, y: reentering.geometry.screen.maxY)
        reentering.hover(true)
        DispatchQueue.main.advance(0.20)
        suite.expect(reentering.openings == 0, "separate short passes cannot accumulate time toward opening")
        DispatchQueue.main.advance(0.06)
        suite.expect(reentering.openings == 1, "reentering requires a fresh uninterrupted activation delay")

        for delay in [0.10, 0.25, 0.65, 1.0] {
            for expands in [false, true] {
                let custom = fixture()
                UserDefaults.standard.delay = delay
                UserDefaults.standard.expands = expands
                custom.hover(true)
                DispatchQueue.main.advance(delay - 0.01)
                suite.expect(custom.openings == 0 && !custom.peeking, "hover waits for the full configured delay in both opening modes")
                DispatchQueue.main.advance(0.02)
                suite.expect(expands ? custom.openings == 1 : custom.peeking,
                       "both expansion and preview honor the selected activation time")
            }
        }

        let adjusted = fixture()
        adjusted.hover(true)
        leave(adjusted)
        UserDefaults.standard.delay = 0.65
        NSEvent.mouseLocation = CGPoint(x: adjusted.geometry.screen.midX, y: adjusted.geometry.screen.maxY)
        adjusted.hover(true)
        DispatchQueue.main.advance(0.30)
        suite.expect(adjusted.openings == 0, "a changed activation time applies on the next entry without restarting")
        DispatchQueue.main.advance(0.36)
        suite.expect(adjusted.openings == 1, "the updated activation time completes normally")

        let active = fixture()
        active.compactActivity = .music
        active.hover(true)
        DispatchQueue.main.advance(0.26)
        expect(active.openings == 1 && active.requestedModule == nil,
               "hover opens without naming a page, so the island's own reopening rule decides")

        let returning = fixture()
        returning.hover(true)
        DispatchQueue.main.advance(0.26)
        leave(returning)
        DispatchQueue.main.advance(0.10)
        NSEvent.mouseLocation = CGPoint(x: returning.geometry.screen.midX, y: returning.geometry.screen.maxY)
        returning.hover(true)
        DispatchQueue.main.advance(1)
        suite.expect(returning.openings == 1 && returning.closures == 0,
               "returning before the closing deadline cancels closing without reopening")

        let preview = fixture()
        UserDefaults.standard.expands = false
        preview.hover(true)
        DispatchQueue.main.advance(0.26)
        suite.expect(preview.peeking && preview.openings == 0 && preview.feedbacks == 1 && preview.hoverWork == nil,
               "preview-only mode responds promptly without expanding the panel")
        leave(preview)
        DispatchQueue.main.advance(0.13)
        suite.expect(preview.closures == 1, "a preview closes within 130 ms of leaving")

        for protect: (Service) -> Void in [
            { $0.pinned = true }, { $0.heldDrag = true }, { $0.keepsWorkingSurface = true },
            { $0.captureControls = true }, { $0.hoverState.close(pointerInside: true) },
            { $0.notice = volume }, { $0.dragPlaceholder = true }, { $0.suspended = true }, { $0.running = false },
            { _ in UserDefaults.standard.enabled = false }
        ] {
            let protected = fixture()
            protected.hover(true)
            protect(protected)
            DispatchQueue.main.advance(1)
            suite.expect(protected.openings == 0 && protected.hoverWork == nil,
                   "a pending hover rechecks eligibility before opening")
        }
        for protect: (Service) -> Void in [
            { $0.pinned = true }, { $0.heldDrag = true }, { $0.keepsWorkingSurface = true },
            { $0.captureControls = true }, { $0.suspended = true }, { $0.running = false }
        ] {
            let protected = fixture()
            protected.open(nil, takeFocus: false)
            leave(protected)
            protect(protected)
            DispatchQueue.main.advance(1)
            suite.expect(protected.closures == 0 && protected.hoverWork == nil,
                   "a pending departure cannot interrupt pinning, dragging, capture, a menu or suspension")
        }
        let clicked = fixture()
        clicked.open(nil, takeFocus: true)
        leave(clicked)
        DispatchQueue.main.advance(1)
        suite.expect(clicked.closures == 0, "a panel opened by click stays open when the pointer leaves")

        let keyboard = fixture()
        keyboard.open(nil, takeFocus: false)
        leave(keyboard)
        AssistiveKeyboard.active = true
        DispatchQueue.main.advance(1)
        expect(keyboard.closures == 0, "moving to the Accessibility Keyboard preserves the working panel")
        notificationContracts(fixture: fixture, leave: leave, expect: expect)
    }

    /// A mirrored banner arrives with its own dismissal pending, as `show`
    /// leaves it when the pointer is elsewhere.
    private static func notificationContracts(fixture: (Bool) -> Service, leave: (Service) -> Void,
                                              expect: (Bool, String) -> Void) {
        let volume = NotchNotice(event: .volume, title: "Volume", detail: "50%", symbol: "speaker.wave.2.fill", level: 0.5)
        func banner(_ body: String = "Hello") -> NotchNotice {
            NotchNotice(event: .systemNotification, title: "Alex", detail: body, symbol: "bell.fill",
                        notification: NotchNotificationContent(app: "Chat", title: "Alex", subtitle: "", body: body),
                        notificationID: UUID())
        }
        func arrive(_ service: Service, _ notice: NotchNotice = banner()) {
            service.notice = notice
            service.scheduleNoticeDismissal(after: notice.event.duration)
            service.updateBounds()
        }
        for physical in [false, true] {
            let service = fixture(physical)
            arrive(service)
            service.hover(true)
            expect(service.noticeWork == nil && service.notice != nil,
                   "a banner under the pointer waits there like a native one instead of timing out")
            DispatchQueue.main.advance(0.20)
            expect(!service.noticeExpanded && service.openings == 0, "the preview honors the activation delay")
            DispatchQueue.main.advance(0.06)
            expect(service.noticeExpanded && service.openings == 0 && service.feedbacks == 1 && service.hoverWork == nil,
                   "a deliberate hover opens the whole message in place rather than the island's page")
            expect(service.surfaceSize.width == service.geometry.notificationPreviewWidth
                   && service.surfaceSize.height > service.geometry.notice.height,
                   "the held preview grows into a card sized for its message")
            DispatchQueue.main.advance(5)
            expect(service.noticeExpanded && service.notice != nil, "an opened preview stays as long as the pointer does")
            service.hover(true) // A tracking re-entry after the resize.
            expect(service.hoverWork == nil && service.noticeWork == nil, "re-entry over an open preview schedules nothing")
            leave(service)
            DispatchQueue.main.advance(0.10)
            expect(service.notice != nil, "leaving gives the same short grace an expanded island gets")
            DispatchQueue.main.advance(0.09)
            expect(service.notice == nil && !service.noticeExpanded && service.closures == 0,
                   "leaving an opened preview closes it without touching the island's page")
        }

        let pass = fixture(false)
        arrive(pass)
        pass.hover(true)
        DispatchQueue.main.advance(0.10)
        leave(pass)
        DispatchQueue.main.advance(0.20)
        expect(!pass.noticeExpanded && pass.notice != nil && pass.noticeWork != nil,
               "a quick pass neither opens the preview nor drops the banner")
        DispatchQueue.main.advance(2.9)
        expect(pass.notice != nil, "after a pass the banner gets its full time again")
        DispatchQueue.main.advance(0.2)
        expect(pass.notice == nil, "the restarted banner still ends on its own")

        let clickOnly = fixture(false)
        UserDefaults.standard.enabled = false
        arrive(clickOnly)
        clickOnly.hover(true)
        DispatchQueue.main.advance(2)
        expect(clickOnly.noticeWork == nil && clickOnly.notice != nil && !clickOnly.noticeExpanded && clickOnly.hoverWork == nil,
               "click-only opening still holds the banner under the pointer without opening it")
        leave(clickOnly)
        DispatchQueue.main.advance(0.2)
        expect(clickOnly.notice != nil && clickOnly.noticeWork != nil, "the resumed banner counts from the moment the pointer left")
        DispatchQueue.main.advance(2.9)
        expect(clickOnly.notice != nil, "the resumed banner keeps its full duration")
        DispatchQueue.main.advance(0.2)
        expect(clickOnly.notice == nil, "a held banner resumes its timer once the pointer leaves")

        let preview = fixture(false)
        UserDefaults.standard.expands = false
        arrive(preview)
        preview.hover(true)
        DispatchQueue.main.advance(0.26)
        expect(preview.noticeExpanded && !preview.peeking,
               "hover-preview mode opens the message itself instead of the page strip")

        let suppressed = fixture(false)
        arrive(suppressed)
        suppressed.hoverState.close(pointerInside: true)
        suppressed.hover(true)
        DispatchQueue.main.advance(1)
        expect(!suppressed.noticeExpanded && suppressed.notice != nil && suppressed.noticeWork == nil,
               "a hover suppressed by a click still holds the banner but does not open it")

        let behind = fixture(false)
        behind.open(nil, takeFocus: true)
        arrive(behind)
        behind.hover(true)
        expect(behind.noticeWork != nil && !behind.noticeExpanded,
               "a banner hidden behind the open island keeps its own timer")

        for protect: (Service) -> Void in [{ $0.keepsWorkingSurface = true }, { _ in AssistiveKeyboard.active = true }] {
            let held = fixture(false)
            arrive(held)
            held.hover(true)
            DispatchQueue.main.advance(0.26)
            expect(held.noticeExpanded, "precondition: the preview is open")
            protect(held)
            leave(held)
            DispatchQueue.main.advance(0.2)
            expect(held.notice == nil && held.closures == 0,
                   "a dialog, menu or the Accessibility Keyboard keeps the island, never a banner the pointer left")
            AssistiveKeyboard.active = false
        }

        let hidden = fixture(false)
        UserDefaults.standard.hides = true
        hidden.windowHost?.visible = false
        arrive(hidden)
        hidden.hover(true)
        DispatchQueue.main.advance(0.26)
        expect(hidden.noticeWork != nil && !hidden.noticeExpanded && hidden.openings == 1,
               "hidden mode reveals the island as usual instead of holding a banner it cannot show")

        // Notification replacement and preference changes run the production handlers.
        let exitRace = fixture(false)
        arrive(exitRace)
        exitRace.hover(true)
        DispatchQueue.main.advance(0.26)
        leave(exitRace)
        DispatchQueue.main.advance(0.05)
        let fresh = banner("Fresh message after exit")
        expect(exitRace.show(fresh), "a new notification is accepted after exit")
        DispatchQueue.main.advance(0.14)
        expect(exitRace.notice?.notificationID == fresh.notificationID,
               "new notification must survive the previous preview exit deadline")
        expect(!exitRace.noticeExpanded && exitRace.noticeWork != nil,
               "a new message outside the pointer starts as a timed banner")
        DispatchQueue.main.advance(2.9)
        expect(exitRace.notice == nil, "the replacement closes after its own full display time")

        let whileInside = fixture(false)
        arrive(whileInside)
        whileInside.hover(true)
        DispatchQueue.main.advance(0.26)
        let freshInside = banner("Fresh message while inside")
        expect(whileInside.show(freshInside), "a new notification is accepted inside")
        DispatchQueue.main.advance(5)
        expect(whileInside.notice?.notificationID == freshInside.notificationID && whileInside.noticeExpanded,
               "replacing a held notification inside keeps the new message readable")
        leave(whileInside)
        DispatchQueue.main.advance(0.2)
        expect(whileInside.notice == nil, "leaving the replacement closes its preview")

        let preferenceChange = fixture(false)
        arrive(preferenceChange)
        preferenceChange.hover(true)
        DispatchQueue.main.advance(0.26)
        UserDefaults.standard.hides = true
        preferenceChange.syncNoticeWithPreferences()
        preferenceChange.windowHost?.visible = false
        leave(preferenceChange)
        DispatchQueue.main.advance(10)
        expect(preferenceChange.notice == nil || preferenceChange.noticeWork != nil,
               "enabling hidden mode must release the held notification after pointer exit")
        UserDefaults.standard.hides = false
        preferenceChange.updateBounds()
        expect(!preferenceChange.noticeExpanded,
               "returning from hidden mode must not resurrect a preview with the pointer elsewhere")

        for expandedPreview in [false, true] {
            let disabled = fixture(false)
            arrive(disabled)
            disabled.hover(true)
            if expandedPreview { DispatchQueue.main.advance(0.26) }
            disabled.routesNotices = false
            disabled.syncNoticeWithPreferences()
            DispatchQueue.main.advance(5)
            expect(disabled.notice == nil && disabled.hoverWork == nil && !disabled.noticeExpanded,
                   "disabling notification routing clears both a pending and an open preview")
        }
        let unchanged = fixture(false)
        arrive(unchanged)
        unchanged.hover(true)
        DispatchQueue.main.advance(0.26)
        unchanged.syncNoticeWithPreferences()
        expect(unchanged.noticeExpanded && unchanged.notice != nil,
               "an unrelated preference sync preserves a readable notification")

        let closingPeek = fixture(false)
        closingPeek.peeking = true
        arrive(closingPeek, volume)
        leave(closingPeek)
        closingPeek.routesNotices = false
        closingPeek.syncNoticeWithPreferences()
        DispatchQueue.main.advance(0.2)
        expect(closingPeek.closures == 1 && !closingPeek.peeking,
               "disabling feedback preserves the island's already scheduled pointer-exit close")

        let replaced = fixture(false)
        arrive(replaced)
        replaced.hover(true)
        DispatchQueue.main.advance(0.26)
        expect(replaced.noticeExpanded, "precondition: the preview is open")
        replaced.notice = volume
        replaced.noticeExpanded = false
        replaced.scheduleNoticeDismissal(after: volume.event.duration)
        leave(replaced)
        DispatchQueue.main.advance(0.2)
        expect(replaced.notice != nil && replaced.noticeWork != nil,
               "leaving after a different notice took over never touches that notice")

        let overPeek = fixture(false)
        UserDefaults.standard.expands = false
        overPeek.hover(true)
        DispatchQueue.main.advance(0.26)
        expect(overPeek.peeking, "precondition: the peek strip is open")
        expect(overPeek.show(banner("While peeking")), "a message is accepted over the peek strip")
        DispatchQueue.main.advance(0.26)
        expect(overPeek.noticeExpanded && !overPeek.peeking, "a message arriving over the peek strip opens as a preview in its place")
        leave(overPeek)
        DispatchQueue.main.advance(0.2)
        expect(overPeek.notice == nil && !overPeek.peeking && overPeek.closures == 0
               && overPeek.surfaceSize == overPeek.geometry.collapsed,
               "closing that preview returns the island to rest without a stale peek strip")

        let pendingOpen = fixture(false)
        pendingOpen.hover(true)
        DispatchQueue.main.advance(0.10)
        expect(pendingOpen.show(banner("Before the island opens")), "a message is accepted while an opening is pending")
        DispatchQueue.main.advance(0.20)
        expect(pendingOpen.openings == 0 && !pendingOpen.noticeExpanded, "the pending opening yields to the banner and the preview waits its own delay")
        DispatchQueue.main.advance(0.06)
        expect(pendingOpen.openings == 0 && pendingOpen.noticeExpanded, "the banner then opens as a preview instead of the island")

        let interrupted = fixture(false)
        arrive(interrupted)
        interrupted.hover(true)
        DispatchQueue.main.advance(0.26)
        expect(interrupted.show(volume) && interrupted.notice?.event == .volume && !interrupted.noticeExpanded,
               "volume feedback takes the place of an open preview as a plain notice")
        DispatchQueue.main.advance(1.7)
        expect(interrupted.notice == nil && interrupted.hoverWork == nil, "that feedback ends on its own and leaves nothing pending")
        leave(interrupted)
        DispatchQueue.main.advance(0.2)
        expect(interrupted.closures == 0 && interrupted.notice == nil, "leaving afterwards has nothing left to close")
    }
}
