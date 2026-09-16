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
        func containsHover(_ point: CGPoint) -> Bool {
            visible && CGRect(origin: .zero, size: rect.size)
                .contains(CGPoint(x: point.x - rect.minX, y: rect.maxY - point.y))
        }
    }
    enum Transition { case reveal }
    class State {
        var running = true, suspended = false, inside = false
        var pinned = false, heldDrag = false, keepsWorkingSurface = false
        var expanded = false, peeking = false, dragPlaceholder = false, openedByHover = false
        var captureControls: Bool?, notice: Bool?
        var compactActivity: NotchCompactActivity?
        var hoverState = NotchHoverState()
        var hiddenHoverMonitors: [Any] = []
        var hoverWork: DispatchWorkItem?
        var captureHover: ((Bool) -> Void)?
        func updateCaptureControlsHover(wasInside: Bool) {}
        var windowHost: Host? = Host()
        var geometry = NotchGeometry(screen: CGRect(x: -1920, y: 900, width: 1920, height: 1080),
                                     safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 22, compactSideRoom: 64)
        var compactActivityGeometry: NotchGeometry { geometry.compactMusicGeometry }
        var surfaceSize: CGSize { expanded ? geometry.expanded : peeking ? geometry.peek : geometry.collapsed }
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
        func mutatePresentation(transitionContent: Transition, _ change: () -> Void) { change(); updateBounds() }
        func provideHapticFeedback() { feedbacks += 1 }
        func updateBounds() { windowHost?.rect = geometry.frame(for: surfaceSize) }
    }

    static func run(expect: (Bool, String) -> Void) {
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
            expect(service.openings == 0, "passing briefly over either display's island does not open it")
            service.hover(false) // A tracking exit while the pointer is still inside.
            expect(service.hoverWork === initial, "duplicate tracking events preserve the original opening deadline")
            DispatchQueue.main.advance(0.06)
            expect(service.openings == 1 && service.openedByHover && service.hoverWork == nil,
                   "a deliberate hover opens after the default 250 ms on both physical and simulated cutouts")
            leave(service)
            let closing = service.hoverWork
            DispatchQueue.main.advance(0.10)
            service.hover(false)
            expect(service.hoverWork === closing, "overlapping exit events do not postpone closing")
            DispatchQueue.main.advance(0.09)
            expect(service.closures == 1 && service.hoverWork == nil,
                   "leaving either display's expanded island closes it within 190 ms")
        }
        for physical in [false, true] {
            for local in [false, true] {
                let hidden = fixture(physical: physical)
                UserDefaults.standard.hides = true
                hidden.windowHost?.visible = false
                hidden.notice = true // A notice already present when the preference changes.
                hidden.syncHiddenHoverMonitoring()
                for _ in 0..<100 { hidden.syncHiddenHoverMonitoring() }
                expect(NSEvent.global.count == 1 && NSEvent.local.count == 1,
                       "hidden mode keeps one pair of native movement observers")
                func move(to point: CGPoint) {
                    NSEvent.mouseLocation = point
                    let event = NSEvent()
                    if local {
                        for handler in Array(NSEvent.local.values) {
                            expect(handler(event) === event, "hidden hover never consumes the original local event")
                        }
                    } else { for handler in Array(NSEvent.global.values) { handler(event) } }
                }
                let top = CGPoint(x: hidden.geometry.screen.midX, y: hidden.geometry.screen.maxY)
                move(to: top)
                DispatchQueue.main.advance(0.20)
                expect(hidden.openings == 0, "a hidden island honors the saved activation delay")
                move(to: CGPoint(x: hidden.geometry.screen.minX, y: hidden.geometry.screen.minY))
                DispatchQueue.main.advance(0.20)
                expect(hidden.openings == 0, "leaving the invisible region cancels pending activation")
                move(to: top)
                DispatchQueue.main.advance(0.26)
                expect(hidden.openings == 1 && hidden.openedByHover,
                       "local and global movement reveal either display without a visible window or menu measurement")
                hidden.windowHost?.visible = true
                hidden.syncHiddenHoverMonitoring()
                expect(NSEvent.global.isEmpty && NSEvent.local.isEmpty,
                       "revealing hands hover back to native window tracking")
                leave(hidden)
                DispatchQueue.main.advance(0.20)
                expect(hidden.closures == 1 && hidden.hiddenUntilHover,
                       "leaving returns the revealed island to its hidden state")
                hidden.syncHiddenHoverMonitoring()
                hidden.running = false
                hidden.syncHiddenHoverMonitoring()
                expect(NSEvent.global.isEmpty && NSEvent.local.isEmpty,
                       "stopping releases both hidden hover observers")
            }
        }
        for disable: (Service) -> Void in [
            { $0.suspended = true }, { $0.windowHost = nil },
            { _ in UserDefaults.standard.hides = false }, { _ in UserDefaults.standard.enabled = false }
        ] {
            let hidden = fixture()
            UserDefaults.standard.hides = true
            hidden.syncHiddenHoverMonitoring()
            disable(hidden)
            hidden.syncHiddenHoverMonitoring()
            expect(NSEvent.global.isEmpty && NSEvent.local.isEmpty,
                   "suspension, missing display and preference changes release hidden hover observers")
        }
        let passing = fixture()
        passing.hover(true)
        DispatchQueue.main.advance(0.20)
        leave(passing)
        DispatchQueue.main.advance(1)
        expect(passing.openings == 0, "leaving before the opening deadline cancels expansion")

        let reentering = fixture()
        reentering.hover(true)
        DispatchQueue.main.advance(0.20)
        leave(reentering)
        DispatchQueue.main.advance(0.02)
        NSEvent.mouseLocation = CGPoint(x: reentering.geometry.screen.midX, y: reentering.geometry.screen.maxY)
        reentering.hover(true)
        DispatchQueue.main.advance(0.20)
        expect(reentering.openings == 0, "separate short passes cannot accumulate time toward opening")
        DispatchQueue.main.advance(0.06)
        expect(reentering.openings == 1, "reentering requires a fresh uninterrupted activation delay")

        for delay in [0.10, 0.25, 0.65, 1.0] {
            for expands in [false, true] {
                let custom = fixture()
                UserDefaults.standard.delay = delay
                UserDefaults.standard.expands = expands
                custom.hover(true)
                DispatchQueue.main.advance(delay - 0.01)
                expect(custom.openings == 0 && !custom.peeking, "hover waits for the full configured delay in both opening modes")
                DispatchQueue.main.advance(0.02)
                expect(expands ? custom.openings == 1 : custom.peeking,
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
        expect(adjusted.openings == 0, "a changed activation time applies on the next entry without restarting")
        DispatchQueue.main.advance(0.36)
        expect(adjusted.openings == 1, "the updated activation time completes normally")

        let active = fixture()
        active.compactActivity = .music
        active.hover(true)
        DispatchQueue.main.advance(0.26)
        expect(active.openings == 1 && active.requestedModule == nil,
               "hover uses the saved reopening behavior instead of overriding it with compact music")

        let returning = fixture()
        returning.hover(true)
        DispatchQueue.main.advance(0.26)
        leave(returning)
        DispatchQueue.main.advance(0.10)
        NSEvent.mouseLocation = CGPoint(x: returning.geometry.screen.midX, y: returning.geometry.screen.maxY)
        returning.hover(true)
        DispatchQueue.main.advance(1)
        expect(returning.openings == 1 && returning.closures == 0,
               "returning before the closing deadline cancels closing without reopening")

        let preview = fixture()
        UserDefaults.standard.expands = false
        preview.hover(true)
        DispatchQueue.main.advance(0.26)
        expect(preview.peeking && preview.openings == 0 && preview.feedbacks == 1 && preview.hoverWork == nil,
               "preview-only mode responds promptly without expanding the panel")
        leave(preview)
        DispatchQueue.main.advance(0.13)
        expect(preview.closures == 1, "a preview closes within 130 ms of leaving")

        for protect: (Service) -> Void in [
            { $0.pinned = true }, { $0.heldDrag = true }, { $0.keepsWorkingSurface = true },
            { $0.captureControls = true }, { $0.hoverState.close(pointerInside: true) },
            { $0.notice = true }, { $0.dragPlaceholder = true }, { $0.suspended = true }, { $0.running = false },
            { _ in UserDefaults.standard.enabled = false }
        ] {
            let protected = fixture()
            protected.hover(true)
            protect(protected)
            DispatchQueue.main.advance(1)
            expect(protected.openings == 0 && protected.hoverWork == nil,
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
            expect(protected.closures == 0 && protected.hoverWork == nil,
                   "a pending departure cannot interrupt pinning, dragging, capture, a menu or suspension")
        }
        let clicked = fixture()
        clicked.open(nil, takeFocus: true)
        leave(clicked)
        DispatchQueue.main.advance(1)
        expect(clicked.closures == 0, "a panel opened by click stays open when the pointer leaves")

        let keyboard = fixture()
        keyboard.open(nil, takeFocus: false)
        leave(keyboard)
        AssistiveKeyboard.active = true
        DispatchQueue.main.advance(1)
        expect(keyboard.closures == 0, "moving to the Accessibility Keyboard preserves the working panel")
    }
}
