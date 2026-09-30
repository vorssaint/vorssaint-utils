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
    final class NSWorkspace {
        static let shared = NSWorkspace()
        var accessibilityDisplayShouldReduceMotion = false
    }
    final class Host {
        var visible = true
        var rect = CGRect.zero
        /// The floating controls' hover rects on screen, margin included.
        var controls: [CGRect] = []
        var departsContent = true
        func finishDeparture() { departsContent = false }
        var isConcealedForMissionControl = false
        var revealChecks = 0
        func blocksHoverReveal() -> Bool {
            revealChecks += 1
            return isConcealedForMissionControl
        }
        func containsHover(_ point: CGPoint) -> Bool {
            visible && !isConcealedForMissionControl && (CGRect(origin: .zero, size: rect.size)
                .contains(CGPoint(x: point.x - rect.minX, y: rect.maxY - point.y)) || controls.contains { $0.contains(point) })
        }
    }
    enum NotchContentTransition { case none, reveal, dismiss, depart, replace }
    enum NotchMusicService {
        static let shared = Reader()
        final class Reader { var playback: NotchPlayback? }
    }
    /// The strip's track by title; the real snapshot also holds its cover and geometry.
    struct NotchCompactMusicSnapshot: Equatable { let title: String }
    class State {
        func schedulePointerFollow() {}
        var hiddenInFullscreen = false
        var fullscreenCompact: Bool { hiddenInFullscreen && !expanded && !peeking }
        var showsSystemFeedback = true, routesNotices = true
        var running = true, suspended = false, inside = false, hoverEmphasized = false
        var pinned = false, heldDrag = false, keepsWorkingSurface = false
        var expanded = false, peeking = false, dragPlaceholder = false, openedByHover = false
        var captureControls: Bool?, notice: NotchNotice?
        var noticeExpanded = false
        var noticeWork: DispatchWorkItem?
        var departingNotice: NotchNotice?
        var departureWork: DispatchWorkItem?
        var trackWork: DispatchWorkItem?
        var presentedMusic: NotchCompactMusicSnapshot?
        var heldMusic: NotchCompactMusicSnapshot?
        var compactActivity: NotchCompactActivity?
        var compactActivities: [NotchCompactActivity] = []
        var activityPickerMenuOpen = false
        var hoverState = NotchHoverState()
        var hiddenHoverMonitors: [Any] = []
        var hoverExitMonitors: [Any] = []
        var hoverWork: DispatchWorkItem?
        var captureHover: ((Bool) -> Void)?
        func updateCaptureControlsHover(wasInside: Bool) {}
        func updateCaptureControlsClickThrough() {}
        var childWindowFrames: [CGRect] = []
        func pointerOverChildWindow(_ point: CGPoint) -> Bool { childWindowFrames.contains { $0.contains(point) } }
        var windowHost: Host? = Host()
        var geometry = NotchGeometry(screen: CGRect(x: -1920, y: 900, width: 1920, height: 1080),
                                     safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 22, compactSideRoom: 64)
        var compactActivityGeometry: NotchGeometry { geometry.compactMusicGeometry }
        var surfaceSize: CGSize {
            if fullscreenCompact { return geometry.restingSize(showsContent: false) }
            if let notice {
                guard noticeExpanded else { return geometry.noticeSize(wingWidth: notice.preferredWingWidth) }
                return geometry.notificationPreviewSize(
                    contentHeight: notice.previewContentHeight(width: geometry.notificationPreviewContentWidth))
            }
            if expanded { return geometry.expanded }
            if peeking { return geometry.peek }
            let resting = compactActivity == nil ? geometry.collapsed : compactActivityGeometry.compactActivitySize
            return hoverEmphasized ? NotchHoverEmphasis.size(from: resting, geometry: geometry) : resting
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
        func refreshPresentation() { updateBounds() }
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
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = false
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
            for reduced in [false, true] {
                let picker = fixture(physical: physical)
                picker.compactActivity = .agents
                picker.compactActivities = [.agents, .music]
                NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = reduced
                picker.hover(true)
                suite.expect(picker.showsCompactActivityPicker && picker.hoverWork == nil,
                             "hover exposes named choices without an automatic opening deadline, including Reduce Motion")
                DispatchQueue.main.advance(2)
                suite.expect(picker.openings == 0, "the activity chooser stays available while the person decides")
                picker.activityPickerMenuOpen = true
                leave(picker)
                suite.expect(picker.showsCompactActivityPicker, "moving into the combination menu keeps its picker visible")
                picker.activityPickerMenuOpen = false
                leave(picker)
                suite.expect(!picker.showsCompactActivityPicker, "leaving hides the activity chooser")
                picker.expanded = true
                picker.inside = true
                suite.expect(!picker.showsCompactActivityPicker, "the chooser does not cover an open page")
                picker.expanded = false
                picker.captureControls = true
                suite.expect(!picker.showsCompactActivityPicker, "capture controls retain priority")
                picker.captureControls = nil
                picker.notice = volume
                suite.expect(!picker.showsCompactActivityPicker, "system notices retain priority")
                picker.notice = nil
                picker.hiddenInFullscreen = true
                suite.expect(!picker.showsCompactActivityPicker, "full-screen content hiding retains priority")
            }
        }
        for physical in [false, true] {
            let clickOnly = fixture(physical: physical)
            UserDefaults.standard.enabled = false
            let resting = clickOnly.surfaceSize
            clickOnly.hover(true)
            let emphasized = clickOnly.surfaceSize
            suite.expect(emphasized.height == resting.height + 5 && emphasized.width >= resting.width
                         && emphasized.width <= resting.width + 20 && clickOnly.hoverWork == nil,
                         "click-only islands pulse within available menu space without scheduling an opening")
            leave(clickOnly)
            suite.expect(clickOnly.surfaceSize == resting,
                         "leaving restores the resting island size")
        }
        let hiddenPulse = fixture()
        UserDefaults.standard.hides = true
        hiddenPulse.windowHost?.visible = false
        let hiddenResting = hiddenPulse.surfaceSize
        hiddenPulse.hover(true)
        suite.expect(hiddenPulse.surfaceSize == hiddenResting,
                     "an invisible island does not pulse before its hover reveal")
        let reducedMotion = fixture()
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = true
        let reducedResting = reducedMotion.surfaceSize
        reducedMotion.hover(true)
        suite.expect(reducedMotion.surfaceSize == reducedResting,
                     "Reduce Motion leaves the resting island still on hover")
        let compactPulse = fixture(physical: true)
        compactPulse.compactActivity = .music
        compactPulse.updateBounds()
        let compactResting = compactPulse.surfaceSize
        compactPulse.hover(true)
        suite.expect(compactPulse.surfaceSize.height == compactResting.height + 5,
                     "a visible compact activity responds to hover without replacing its content")
        leave(compactPulse)
        suite.expect(compactPulse.surfaceSize == compactResting,
                     "the compact activity returns to its original size on exit")
        let fullscreen = fixture(physical: true)
        fullscreen.hiddenInFullscreen = true
        fullscreen.compactActivity = .music
        UserDefaults.standard.hides = true
        UserDefaults.standard.expands = false
        fullscreen.updateBounds()
        let blackSize = fullscreen.surfaceSize
        fullscreen.hover(true)
        suite.expect(blackSize == fullscreen.geometry.restingSize(showsContent: false)
                     && !fullscreen.hoverEmphasized && fullscreen.hoverWork != nil,
                     "fullscreen keeps the cutout black but schedules configured hover access even with cached music")
        DispatchQueue.main.advance(0.26)
        suite.expect(fullscreen.peeking && fullscreen.openings == 0,
                     "hover preview remains available from the black fullscreen cutout")
        let simulatedFullscreen = fixture()
        simulatedFullscreen.hiddenInFullscreen = true
        simulatedFullscreen.hover(true)
        DispatchQueue.main.advance(0.26)
        suite.expect(simulatedFullscreen.hoverWork == nil && !simulatedFullscreen.peeking
                     && simulatedFullscreen.openings == 0,
                     "a simulated cutout hidden in full screen does not open on hover")
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

        // AppKit's last exit can come while the pointer is still in the margin
        // around the floating controls. Leaving from there over transparent
        // pixels or out of the window reports nothing more to the island.
        func openWithPointerInMargin() -> Service {
            let service = fixture()
            service.hover(true)
            DispatchQueue.main.advance(0.26)
            let island = service.windowHost!.rect
            service.windowHost?.controls = [CGRect(x: island.midX - 38, y: island.minY - 72, width: 76, height: 88)]
            NSEvent.mouseLocation = CGPoint(x: island.midX, y: island.minY - 60)
            service.hover(false)
            return service
        }
        func follow(to point: CGPoint, local: Bool = false) {
            NSEvent.mouseLocation = point
            let event = NSEvent()
            if local {
                for handler in Array(NSEvent.local.values) {
                    suite.expect(handler(event) === event, "following the pointer never consumes its local event")
                }
            } else { for handler in Array(NSEvent.global.values) { handler(event) } }
        }
        let margin = openWithPointerInMargin()
        let island = margin.windowHost!.rect
        suite.expect(margin.expanded && margin.inside && margin.hoverWork == nil
                     && NSEvent.global.count == 1 && NSEvent.local.count == 1,
                     "an exit reported in the controls' margin keeps the island open and follows the pointer")
        follow(to: CGPoint(x: island.midX + 20, y: island.minY - 30), local: true)
        DispatchQueue.main.advance(0.5)
        suite.expect(margin.expanded && margin.closures == 0, "slow travel through the margin keeps the island open")
        follow(to: CGPoint(x: island.midX, y: island.minY - 400))
        DispatchQueue.main.advance(0.10)
        follow(to: CGPoint(x: island.midX - 20, y: island.minY - 50))
        DispatchQueue.main.advance(0.20)
        suite.expect(margin.expanded && margin.closures == 0,
                     "slipping back into the margin unreported cancels the pending close")
        follow(to: CGPoint(x: island.midX, y: island.minY - 400))
        DispatchQueue.main.advance(0.19)
        suite.expect(margin.closures == 1, "leaving from the margin with no further report still closes the island")
        follow(to: CGPoint(x: island.midX, y: island.minY - 420))
        suite.expect(NSEvent.global.isEmpty && NSEvent.local.isEmpty, "the closed island stops following the pointer")

        let reported = openWithPointerInMargin()
        reported.hover(true)
        suite.expect(NSEvent.global.isEmpty && NSEvent.local.isEmpty && reported.expanded,
                     "an entry AppKit reports hands hover back to its tracking")
        let stopped = openWithPointerInMargin()
        stopped.running = false
        follow(to: CGPoint(x: island.midX, y: island.minY - 400))
        suite.expect(NSEvent.global.isEmpty && NSEvent.local.isEmpty && stopped.closures == 0,
                     "stopping the island releases the pointer observers")
        // Pinning, a drag from the shelf, or a menu or dialog keeps the island
        // and ends the watch. A menu that closes with the pointer still in the
        // margin starts it again.
        for protect: (Service) -> Void in [{ $0.pinned = true }, { $0.heldDrag = true }, { $0.keepsWorkingSurface = true }] {
            let held = openWithPointerInMargin()
            protect(held)
            follow(to: CGPoint(x: island.midX, y: island.minY - 400))
            DispatchQueue.main.advance(1)
            suite.expect(held.expanded && held.closures == 0 && NSEvent.global.isEmpty && NSEvent.local.isEmpty,
                         "pinning, a shelf drag, a menu or a dialog keeps the island and stops following the pointer")
        }
        let menu = openWithPointerInMargin()
        menu.keepsWorkingSurface = true
        follow(to: CGPoint(x: island.midX + 20, y: island.minY - 30))
        menu.keepsWorkingSurface = false
        menu.hover(false)
        suite.expect(NSEvent.global.count == 1 && NSEvent.local.count == 1,
                     "a menu that closes with the pointer in the margin follows the pointer again")
        follow(to: CGPoint(x: island.midX, y: island.minY - 400))
        DispatchQueue.main.advance(0.19)
        follow(to: CGPoint(x: island.midX, y: island.minY - 420))
        suite.expect(menu.closures == 1 && NSEvent.global.isEmpty && NSEvent.local.isEmpty,
                     "leaving after the menu closes the island and releases the pointer observers")
        let clickOpened = fixture()
        clickOpened.open(takeFocus: true)
        clickOpened.windowHost?.controls = [CGRect(x: island.midX - 38, y: island.minY - 72, width: 76, height: 88)]
        NSEvent.mouseLocation = CGPoint(x: island.midX, y: island.minY - 60)
        clickOpened.hover(false)
        suite.expect(NSEvent.global.isEmpty && NSEvent.local.isEmpty,
                     "an island opened by a click, which leaving does not close, never follows the pointer")
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

        let popover = fixture()
        popover.open(nil, takeFocus: false)
        popover.childWindowFrames = [CGRect(x: popover.geometry.screen.minX, y: popover.geometry.screen.minY,
                                            width: 240, height: 200)]
        leave(popover)
        DispatchQueue.main.advance(1)
        expect(popover.closures == 0 && popover.inside,
               "moving into a popover hanging from the island keeps a hover-opened panel")
        notificationContracts(fixture: fixture, leave: leave, expect: expect)
        trackNoticeContracts(fixture: fixture, expect: expect)
    }

    /// A new song's notice waits for playback to settle, and the compact
    /// strip keeps the song it showed until the notice covers it.
    private static func trackNoticeContracts(fixture: (Bool) -> Service, expect: (Bool, String) -> Void) {
        func song(_ title: String, playing: Bool = true) -> NotchPlayback {
            NotchPlayback(track: RadialNowPlayingSnapshot(title: title, artist: "Artist", album: nil, artworkData: nil,
                                                          appBundleIdentifier: "org.example.player", appPID: 42),
                          isPlaying: playing, elapsed: 0, duration: 200, rate: 1, sampledAt: Date(), canSeek: false)
        }
        defer { NotchMusicService.shared.playback = nil }
        let skipped = fixture(false)
        skipped.presentedMusic = NotchCompactMusicSnapshot(title: "Old")
        NotchMusicService.shared.playback = song("New")
        skipped.scheduleTrackNotice()
        expect(skipped.heldMusic?.title == "Old" && skipped.notice == nil,
               "a new song leaves the strip on the song it showed while the notice waits")
        DispatchQueue.main.advance(0.3)
        skipped.presentedMusic = NotchCompactMusicSnapshot(title: "New")
        NotchMusicService.shared.playback = song("Newer")
        skipped.scheduleTrackNotice()
        DispatchQueue.main.advance(0.49)
        expect(skipped.heldMusic?.title == "Old" && skipped.notice == nil,
               "skipping again restarts the wait and keeps the song still on screen")
        DispatchQueue.main.advance(0.02)
        expect(skipped.notice?.event == .track && skipped.notice?.title == "Newer" && skipped.heldMusic == nil,
               "the notice shows where playback settled and releases the strip behind it")
        for block: (Service) -> Void in [{ $0.expanded = true },
                                         { _ in NotchMusicService.shared.playback = song("New", playing: false) }] {
            let blocked = fixture(false)
            blocked.presentedMusic = NotchCompactMusicSnapshot(title: "Old")
            NotchMusicService.shared.playback = song("New")
            blocked.scheduleTrackNotice()
            block(blocked)
            DispatchQueue.main.advance(0.5)
            expect(blocked.notice == nil && blocked.heldMusic == nil,
                   "a notice that cannot show releases the strip to the current song")
        }
        let hidden = fixture(false)
        NotchMusicService.shared.playback = song("New")
        hidden.scheduleTrackNotice()
        expect(hidden.heldMusic == nil, "nothing is held when the strip was not on screen")
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

        // A burst keeps the banner's width, so the island does not resize
        // with each message and a banner held near its end stays in reach.
        let wide = banner(String(repeating: "A long message in a busy chat ", count: 8))
        let burst = fixture(false)
        leave(burst)
        expect(burst.show(wide) && burst.show(banner("ok")), "precondition: a burst replaces the banner")
        expect(burst.surfaceSize == burst.geometry.noticeSize(wingWidth: wide.preferredWingWidth),
               "a message replacing a banner still on screen keeps its width")
        DispatchQueue.main.advance(3.1)
        let alone = banner("ok")
        expect(burst.notice == nil && burst.show(alone) && alone.preferredWingWidth < wide.preferredWingWidth
               && burst.surfaceSize == burst.geometry.noticeSize(wingWidth: alone.preferredWingWidth),
               "the next message on its own takes only the width it needs")
        let held = fixture(false)
        leave(held)
        expect(held.show(wide), "precondition: a wide banner is shown")
        let frame = held.geometry.frame(for: held.surfaceSize)
        NSEvent.mouseLocation = CGPoint(x: frame.maxX - 4, y: frame.midY)
        held.hover(true)
        expect(held.show(banner("ok")) && held.windowHost?.containsHover(NSEvent.mouseLocation) == true
               && held.noticeWork == nil,
               "a message arriving over a banner held near its end stays under the pointer")
    }
}
