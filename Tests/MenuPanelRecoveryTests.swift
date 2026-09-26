// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

private typealias PanelRecoveryPolicy = StatusItemAnchorSupport

/// Current production close, show and geometry methods against controlled windows.
/// Native event objects are data only; nothing is posted and no window is created.
enum MenuPanelRecoveryTests {
    final class Queue {
        var jobs: [() -> Void] = []
        func async(execute work: @escaping () -> Void) { jobs.append(work) }
        func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
    }
    enum DispatchQueue { static var main = Queue() }
    final class NSScreen {
        static var screens = [NSScreen()]
        static var withMenuBar: NSScreen? { screens.first }
        var frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        var visibleFrame = CGRect(x: 0, y: 0, width: 1920, height: 1050)
        var isStillAttached = true
        var displayID = 1
    }
    final class NSWindow {
        static let didMoveNotification = Notification.Name("move")
        static let didResizeNotification = Notification.Name("resize")
        var frame: CGRect
        var screen: NSScreen? = NSScreen.screens.first
        var windowNumber = 71
        var alphaValue = 1.0
        var contentView: View? = View()
        init(_ frame: CGRect) { self.frame = frame }
        func convertToScreen(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: frame.minX, dy: frame.minY) }
        func setFrame(_ rect: CGRect, display: Bool) {
            frame = rect
            NotificationCenter.default.post(name: Self.didMoveNotification, window: self)
        }
        func makeKey() {}
        func close() {}
    }
    typealias NSPanel = NSWindow
    final class View {
        var window: NSWindow?
        func layoutSubtreeIfNeeded() {}
    }
    final class Controller { let view = View() }
    final class NSStatusBarButton {
        var window: NSWindow? = NSWindow(CGRect(x: 682, y: 1050, width: 36, height: 30))
        var bounds = CGRect(x: 0, y: 0, width: 36, height: 30)
        func convert(_ rect: CGRect, to: Any?) -> CGRect { rect }
    }
    final class Popover {
        var animates = true
        var isShown = false
        var contentViewController: Controller? = Controller()
        var fails = false
        var attempts = 0
        func show(relativeTo: CGRect, of button: NSStatusBarButton, preferredEdge: NSRectEdge) {
            attempts += 1
            guard !fails, let window = button.window else { return }
            contentViewController?.view.window = NSWindow(CGRect(x: window.frame.midX - 166, y: 530, width: 332, height: 500))
            isShown = true
        }
    }
    final class Center {
        var observers: [(NSObject, Any?, (Notification) -> Void)] = []
        func addObserver(forName: Notification.Name, object: Any?, queue: OperationQueue?,
                         using body: @escaping (Notification) -> Void) -> NSObjectProtocol {
            let token = NSObject(); observers.append((token, object, body)); return token
        }
        func removeObserver(_ token: NSObjectProtocol) { observers.removeAll { $0.0 === token } }
        func post(name: Notification.Name, window: NSWindow) {
            for (_, object, body) in observers where object as? NSWindow === window {
                body(Notification(name: name, object: window))
            }
        }
    }
    enum NotificationCenter { static var `default` = Center() }
    final class Application {
        var currentEvent: NSEvent?
        func activate(ignoringOtherApps: Bool) {}
    }
    static var NSApp = Application()
    final class StatusController {
        var held = false
        let button: NSStatusBarButton? = NSStatusBarButton()
        func setMicBadgeHeld(_ value: Bool) { held = value }
    }
    final class MenuPanelFocus {
        static var shared = MenuPanelFocus()
        var activeMetric: String? = "network"
        var switching = false
        var popoverIsVisible = false
        func setSwitchingMetricAnchor(_ value: Bool) { switching = value }
        func setPopoverVisible(_ value: Bool) { popoverIsVisible = value }
        func clearMetricFocus() { activeMetric = nil }
    }
    enum Needs { case none, network }
    final class SystemMonitor {
        static var shared = SystemMonitor()
        var needs: Needs = .network
        func setMenuPanelNeeds(_ value: Needs) { needs = value }
    }
    final class ProcessUsageService {
        static var shared = ProcessUsageService()
        var releases = 0
        func stopNetworkMonitoring() { releases += 1 }
        func clearCachedRows() {}
    }
    enum ResponsibleProcess { static func clearIconCache() {} }
    final class PanelInteractionState {
        static var shared = PanelInteractionState()
        var viewKeepsPopoverOpen = false
        var isPresentingPopoverModal = false
        var anchorScreen: NSScreen?
        var preventsPopoverDismissal: Bool {
            viewKeepsPopoverOpen || isPresentingPopoverModal
        }
    }
    enum StatusItemAnchorSupport {
        static func anchorDriftX(clickX: Double, reportedMidX: Double, buttonWidth: Double) -> Double? {
            PanelRecoveryPolicy.anchorDriftX(clickX: clickX, reportedMidX: reportedMidX, buttonWidth: buttonWidth)
        }
        static func isTrustworthyStatusFrame(_ frame: CGRect) -> Bool {
            PanelRecoveryPolicy.isTrustworthyStatusFrame(frame, screenFrames: NSScreen.screens.map(\.frame))
        }
        static func pinnedPanelFrame(size: CGSize, anchorMidX: CGFloat, anchorTop: CGFloat, visibleFrame: CGRect) -> CGRect {
            PanelRecoveryPolicy.pinnedPanelFrame(size: size, anchorMidX: anchorMidX, anchorTop: anchorTop, visibleFrame: visibleFrame)
        }
        static func shouldReopenPanel(closedByApp: Bool, lastFrame: CGRect?, panelWindowNumber: Int?,
                                      event: NSEvent?, secondsSinceLastReopen: TimeInterval) -> Bool {
            PanelRecoveryPolicy.shouldReopenPanel(closedByApp: closedByApp, lastFrame: lastFrame,
                panelWindowNumber: panelWindowNumber, event: event, secondsSinceLastReopen: secondsSinceLastReopen)
        }
    }
    class Fixture {
        let popover = Popover()
        let statusController = StatusController()
        var popoverIsClosing = false
        var popoverCloseIsAppRequested = false
        var popoverIsSwitchingAnchor = false
        var settingsWindow: NSWindow?
        var isTerminating = false
        var popoverLastFrame: CGRect?
        var popoverLastWindowNumber: Int?
        var popoverForeignReopenAt = Date.distantPast
        var popoverClosedAt = Date.distantPast
        var lastStatusClick: (x: CGFloat, at: Date)?
        static let statusClickFreshness: TimeInterval = 0.5
        var popoverPositioningPanel: NSPanel?
        var popoverDriftObservers: [NSObjectProtocol] = []
        var monitors = false
        func removePopoverDismissMonitor() { monitors = false }
        func installPopoverDismissMonitor() { monitors = true }
        func runPopoverCloseCompletions() {}
        func statusScreen(for button: NSStatusBarButton) -> NSScreen? { button.window?.screen }
        func configurePopoverWindow(_ window: NSWindow) {}
        func animatePopoverOpen(_ window: NSWindow) {}
        @discardableResult func useStablePopoverPositioningViewIfNeeded(_ window: NSWindow) -> Bool { false }
    }

    static func event(_ type: NSEvent.EventType = .leftMouseDown, window: Int = 71,
                      location: CGPoint = CGPoint(x: 100, y: 100), age: TimeInterval = 0) -> NSEvent? {
        let timestamp = ProcessInfo.processInfo.systemUptime - age
        if type == .keyDown || type == .keyUp || type == .flagsChanged {
            return NSEvent.keyEvent(with: type, location: location, modifierFlags: [], timestamp: timestamp,
                windowNumber: window, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)
        }
        return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: timestamp,
            windowNumber: window, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)
    }

    static func run(_ expect: (Bool, String) -> Void) {
        func setup(corrected: Bool = false) -> Host {
            DispatchQueue.main = Queue(); NotificationCenter.default = Center()
            NSScreen.screens = [NSScreen()]; NSApp = Application()
            MenuPanelFocus.shared = MenuPanelFocus(); SystemMonitor.shared = SystemMonitor()
            ProcessUsageService.shared = ProcessUsageService(); PanelInteractionState.shared = PanelInteractionState()
            let host = Host()
            if corrected {
                host.statusController.button!.window!.frame.origin.x = 1482
                host.lastStatusClick = (700, Date())
            }
            host.showPopover(animate: false, activate: false)
            expect(MenuPanelFocus.shared.popoverIsVisible == host.popover.isShown,
                   "panel presentation follows the actual show result")
            NSApp.currentEvent = event()
            return host
        }
        func close(_ host: Host) {
            host.popover.isShown = false
            host.popoverWillClose(Notification(name: Notification.Name("willClose")))
            host.popoverDidClose(Notification(name: Notification.Name("closed")))
        }
        for corrected in [false, true] {
            let host = setup(corrected: corrected)
            expect(host.popoverLastFrame?.midX == 700, "recovery remembers the final visible position, including initial correction")
            host.lastStatusClick = (700, Date().addingTimeInterval(-5))
            close(host)
            expect(host.popover.isShown && host.popoverLastFrame?.midX == 700,
                   "fresh panel click recovers at its existing anchor even after the opening click expires")
            expect(MenuPanelFocus.shared.popoverIsVisible,
                   "panel content stays active after a successful anchor recovery")
            expect(MenuPanelFocus.shared.activeMetric == "network" && SystemMonitor.shared.needs == .network,
                   "recovery preserves metric focus and sampling")
            DispatchQueue.main.drain()
            expect(!host.popoverIsSwitchingAnchor && host.monitors, "recovery ends switching and keeps dismissal monitors")
            close(host); DispatchQueue.main.drain()
            expect(!host.popover.isShown && SystemMonitor.shared.needs == .none && !host.statusController.held,
                   "immediate second close stays closed and releases resources")
            expect(!MenuPanelFocus.shared.popoverIsVisible,
                   "closed panel content stops observing live section updates")
        }
        for kind in ["requested", "missing event", "other window", "old click", "future click", "outside",
                     "movement", "escape", "key release", "modifier", "no frame", "no window number",
                     "missing button", "missing window", "screen detached", "terminating", "switching"] {
            let host = setup()
            switch kind {
            case "requested": host.popoverCloseIsAppRequested = true
            case "missing event": NSApp.currentEvent = nil
            case "other window": NSApp.currentEvent = event(window: 72)
            case "old click": NSApp.currentEvent = event(age: 1)
            case "future click": NSApp.currentEvent = event(age: -1)
            case "outside": NSApp.currentEvent = event(location: CGPoint(x: -1, y: 10))
            case "movement": NSApp.currentEvent = event(.mouseMoved)
            case "escape": NSApp.currentEvent = event(.keyDown)
            case "key release": NSApp.currentEvent = event(.keyUp)
            case "modifier": NSApp.currentEvent = event(.flagsChanged)
            case "no frame": host.popoverLastFrame = nil
            case "no window number": host.popoverLastWindowNumber = nil
            case "missing button": host.popoverAnchor = nil
            case "missing window": host.statusController.button!.window = nil
            case "screen detached": NSScreen.screens[0].isStillAttached = false
            case "terminating": host.isTerminating = true
            default: host.popoverIsSwitchingAnchor = true
            }
            close(host); DispatchQueue.main.drain()
            expect(!host.popover.isShown && host.popover.attempts == 1, "no automatic reopen for \(kind)")
        }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp] {
            let host = setup(); NSApp.currentEvent = event(type); close(host)
            expect(host.popover.isShown, "fresh click phase \(type.rawValue) targets the panel")
            DispatchQueue.main.drain()
        }
        do {
            let host = setup(); host.popover.fails = true; close(host); DispatchQueue.main.drain()
            expect(!host.popover.isShown && !host.monitors && SystemMonitor.shared.needs == .none
                   && !host.statusController.held && host.popoverDriftObservers.isEmpty,
                   "failed presentation releases observers, sampling and held status badge")
            expect(!MenuPanelFocus.shared.popoverIsVisible,
                   "failed presentation leaves panel content inactive")
        }
        do {
            let host = setup(); close(host); close(host); DispatchQueue.main.drain()
            expect(host.popover.attempts == 2 && !host.popover.isShown && SystemMonitor.shared.needs == .none,
                   "a close before recovery completion releases resources without recursion")
        }
        do {
            let host = setup()
            let window = host.popover.contentViewController!.view.window!
            window.setFrame(CGRect(x: 600, y: 400, width: 332, height: 650), display: false)
            expect(host.popoverLastFrame == window.frame, "later movement refreshes the recovery frame")
            host.popoverCloseIsAppRequested = true; close(host)
            expect(NotificationCenter.default.observers.isEmpty, "normal close leaves no geometry observer")
        }
        do {
            let host = setup()
            host.popoverWillClose(Notification(name: Notification.Name("willClose")))
            expect(host.popoverIsClosing && !host.popoverCloseIsAppRequested,
                   "popoverWillClose marks closing in progress without marking app requested")
            host.popover.isShown = false
            host.popoverDidClose(Notification(name: Notification.Name("didClose")))
            expect(host.popover.isShown && !host.popoverIsClosing && !host.popoverCloseIsAppRequested,
                   "system willClose followed by didClose allows panel recovery and clears closing flags")
        }
        do {
            let host = setup()
            host.popoverCloseIsAppRequested = true
            host.popoverWillClose(Notification(name: Notification.Name("willClose")))
            expect(host.popoverIsClosing && host.popoverCloseIsAppRequested,
                   "app-requested close preserves app-requested flag through willClose")
            host.popover.isShown = false
            host.popoverDidClose(Notification(name: Notification.Name("didClose")))
            expect(!host.popover.isShown && !host.popoverIsClosing && !host.popoverCloseIsAppRequested,
                   "app-requested willClose followed by didClose stays closed without recovery")
        }
        do {
            let host = setup()
            let sideSettings = NSWindow(CGRect(x: 50, y: 100, width: 400, height: 400))
            sideSettings.windowNumber = 88
            host.settingsWindow = sideSettings
            let sideEvent = event(window: 88)!
            expect(!host.shouldDismissPopover(forLocalEvent: sideEvent),
                   "side-by-side Settings window does not dismiss the live preview panel")

            let overlappingSettings = NSWindow(CGRect(x: 500, y: 500, width: 400, height: 400))
            overlappingSettings.windowNumber = 89
            host.settingsWindow = overlappingSettings
            let overlapEvent = event(window: 89)!
            expect(host.shouldDismissPopover(forLocalEvent: overlapEvent),
                   "overlapping Settings window dismisses the panel")

            PanelInteractionState.shared.viewKeepsPopoverOpen = true
            expect(!host.shouldDismissPopover(forLocalEvent: overlapEvent),
                   "dismissal protection keeps panel open even when Settings window overlaps")
            PanelInteractionState.shared.viewKeepsPopoverOpen = false

            PanelInteractionState.shared.isPresentingPopoverModal = true
            expect(!host.shouldDismissPopover(forLocalEvent: overlapEvent),
                   "modal presentation keeps panel open even when Settings window overlaps")
            PanelInteractionState.shared.isPresentingPopoverModal = false

            let popoverEvent = event(window: 71)!
            expect(!host.shouldDismissPopover(forLocalEvent: popoverEvent),
                   "interaction with the panel itself does not dismiss the popover")

            let unrelatedEvent = event(window: 99)!
            expect(!host.shouldDismissPopover(forLocalEvent: unrelatedEvent),
                   "interaction with unrelated window does not dismiss the popover")
        }
    }
}
