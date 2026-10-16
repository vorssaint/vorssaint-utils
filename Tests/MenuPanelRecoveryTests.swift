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
        static var pointerVisibleFrame: CGRect { screens.first?.visibleFrame ?? .zero }
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
        var ignoresMouseEvents = false
        var contentView: View? = View()
        init(_ frame: CGRect) { self.frame = frame }
        func convertToScreen(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: frame.minX, dy: frame.minY) }
        func frameRect(forContentRect rect: CGRect) -> CGRect {
            CGRect(origin: rect.origin, size: CGSize(width: rect.width, height: rect.height + 28))
        }
        func setFrame(_ rect: CGRect, display: Bool) {
            frame = rect
            screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }
            NotificationCenter.default.post(name: Self.didMoveNotification, window: self)
        }
        func animator() -> NSWindow { self }
        func makeKey() {}
        func close() {}
    }
    typealias NSPanel = NSWindow
    /// Applies the change at once and holds the completion until the test ends the fade.
    final class NSAnimationContext {
        static var completions: [() -> Void] = []
        var duration = 0.0
        static func runAnimationGroup(_ changes: (NSAnimationContext) -> Void,
                                      completionHandler: (() -> Void)? = nil) {
            changes(NSAnimationContext())
            if let completionHandler { completions.append(completionHandler) }
        }
        static func finish() { let pending = completions; completions = []; pending.forEach { $0() } }
    }
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
        var measuredScreen: NSScreen?
        // The animated close keeps the panel on screen until it finishes.
        func performClose(_ sender: Any?) {}
        /// AppKit sends willClose and didClose inside a close without animation.
        var closeNotifies: (() -> Void)?
        func close() { isShown = false; closeNotifies?() }
        func show(relativeTo: CGRect, of button: NSStatusBarButton, preferredEdge: NSRectEdge) {
            attempts += 1
            measuredScreen = PanelInteractionState.shared.anchorScreen
            guard !fails, let window = button.window else { return }
            contentViewController?.view.window = NSWindow(CGRect(x: window.frame.midX - 166, y: 530, width: 332, height: 500))
            isShown = true
        }
    }
    final class Center {
        var observers: [(NSObject, Any?, (Notification) -> Void)] = []
        var additions = 0
        func addObserver(forName: Notification.Name, object: Any?, queue: OperationQueue?,
                         using body: @escaping (Notification) -> Void) -> NSObjectProtocol {
            additions += 1
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
        var keyWindow: NSWindow?
        var modalWindow: NSWindow?
        func activate(ignoringOtherApps: Bool) { NSWorkspace.shared.frontmostApplication = NSRunningApplication.current }
    }
    final class NSRunningApplication {
        static let current = NSRunningApplication(pid: 100)
        let processIdentifier: pid_t
        var isTerminated = false
        var activations = 0
        init(pid: pid_t) { processIdentifier = pid }
        func activate(from: NSRunningApplication, options: [Int]) -> Bool {
            activations += 1
            NSWorkspace.shared.frontmostApplication = self
            return true
        }
        @discardableResult
        func activate(options: [Int]) -> Bool { activate(from: .current, options: options) }
    }
    final class NSWorkspace {
        static var shared = NSWorkspace()
        static let activeSpaceDidChangeNotification = Notification.Name("activeSpaceChanged")
        static let didActivateApplicationNotification = Notification.Name("appActivated")
        static let applicationUserInfoKey = "application"
        let notificationCenter = Center()
        var frontmostApplication: NSRunningApplication?
    }
    enum ActivationHandoff { static func yield(to source: NSRunningApplication) {} }
    static var NSApp = Application()
    final class StatusController {
        var held = false
        let button: NSStatusBarButton? = NSStatusBarButton()
        func setMicBadgeHeld(_ value: Bool) { held = value }
    }
    typealias MetricDetailKind = String
    struct MenuBarMetric { let detailKind: String }
    enum Module { case system }
    enum NotchSupport {
        static func routesAppPanel() -> Bool { false }
        static func modules() -> [Module] { [] }
    }
    final class NotchService {
        static let shared = NotchService()
        var acceptsSystemFeedback = false
        func showMetric(_ metric: String, toggle: Bool) {}
    }
    final class MenuPanelFocus {
        static var shared = MenuPanelFocus()
        var activeMetric: String? = "network"
        var request: String?
        func focus(_ metric: String) { activeMetric = metric; request = metric }
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
        static func panelActivationSource<App>(after change: PanelActivationChange<App>, current: App?,
                                               isOwnApp: (App) -> Bool) -> App? {
            PanelRecoveryPolicy.panelActivationSource(after: change, current: current, isOwnApp: isOwnApp)
        }
        static func shouldReturnActivation(to sourcePID: pid_t?, ownPID: pid_t, frontmostPID: pid_t?,
                                           ownWindowIsKey: Bool, closeReason: PanelCloseReason?) -> Bool {
            PanelRecoveryPolicy.shouldReturnActivation(to: sourcePID, ownPID: ownPID, frontmostPID: frontmostPID,
                                                       ownWindowIsKey: ownWindowIsKey, closeReason: closeReason)
        }
        static func anchorDriftX(clickX: Double, reportedMidX: Double, buttonWidth: Double) -> Double? {
            PanelRecoveryPolicy.anchorDriftX(clickX: clickX, reportedMidX: reportedMidX, buttonWidth: buttonWidth)
        }
        static func isTrustworthyStatusFrame(_ frame: CGRect,
                                             screenFrames: [CGRect] = NSScreen.screens.map(\.frame)) -> Bool {
            PanelRecoveryPolicy.isTrustworthyStatusFrame(frame, screenFrames: screenFrames)
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
        var popoverCloseFadeSerial = 0
        var popoverIsFadingOut = false
        weak var fadingPopoverWindow: NSWindow?
        var popoverIsReopening = false
        var metricAnchorSwitchSerial = 0
        var scheduledReanchors = 0
        func scheduleMetricAnchorSwitch(to metric: String, anchoredTo button: NSStatusBarButton) {
            scheduledReanchors += 1
        }
        var popoverCloseIsAppRequested = false
        var popoverIsSwitchingAnchor = false
        var settingsWindow: NSWindow?
        var isTerminating = false
        var popoverLastFrame: CGRect?
        var popoverLastWindowNumber: Int?
        var popoverForeignReopenAt = Date.distantPast
        var lastStatusClick: (point: NSPoint, at: Date)?
        static let statusClickFreshness: TimeInterval = 0.5
        static let statusClickEventTypes: Set<NSEvent.EventType> = [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        ]
        var popoverPositioningPanel: NSPanel?
        var popoverDriftObservers: [NSObjectProtocol] = []
        var monitors = false
        func removePopoverDismissMonitor() { monitors = false }
        func installPopoverDismissMonitor() { monitors = true }
        var popoverCloseReason: PanelCloseReason?
        var popoverCloseCompletions: [() -> Void] = []
        var panelActivationSource: NSRunningApplication?
        var panelActivationObservers: [NSObjectProtocol] = []
        var activationTracking: Bool { !panelActivationObservers.isEmpty }
        var activationTrackingStarts: Int { NSWorkspace.shared.notificationCenter.additions / 2 }
        var switchesDesktop = false
        func handbackWouldSwitchDesktop(to pid: pid_t) -> Bool { switchesDesktop }
        func closePopover() { popover.isShown = false }
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
        func setup(corrected: Bool = false, present: Bool = true) -> Host {
            DispatchQueue.main = Queue(); NotificationCenter.default = Center(); NSAnimationContext.completions = []
            NSScreen.screens = [NSScreen()]; NSApp = Application(); NSWorkspace.shared = NSWorkspace()
            MenuPanelFocus.shared = MenuPanelFocus(); SystemMonitor.shared = SystemMonitor()
            ProcessUsageService.shared = ProcessUsageService(); PanelInteractionState.shared = PanelInteractionState()
            let host = Host()
            if corrected {
                host.statusController.button!.window!.frame.origin.x = 1482
                host.lastStatusClick = (CGPoint(x: 700, y: 1065), Date())
            }
            if present { host.showPopover(animate: false, activate: false) }
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
        // A close Vorssaint asks for itself, which marks it app requested.
        func requestClose(_ host: Host, _ reason: PanelCloseReason) {
            host.closePopoverNow(animated: false, reason: reason, completion: nil)
            host.popoverWillClose(Notification(name: Notification.Name("willClose")))
            host.popoverDidClose(Notification(name: Notification.Name("closed")))
        }
        func trackingSetup() -> (Host, NSRunningApplication) {
            let host = setup(present: false)
            let source = NSRunningApplication(pid: 777)
            NSWorkspace.shared.frontmostApplication = source
            host.showPopover(animate: false)
            return (host, source)
        }
        func notifyCloses(_ host: Host) {
            host.popover.closeNotifies = { [unowned host] in
                host.popoverWillClose(Notification(name: Notification.Name("willClose")))
                host.popoverDidClose(Notification(name: Notification.Name("closed")))
            }
        }
        for corrected in [false, true] {
            let host = setup(corrected: corrected)
            expect(host.popoverLastFrame?.midX == 700, "recovery remembers the final visible position, including initial correction")
            host.lastStatusClick = (CGPoint(x: 700, y: 1065), Date().addingTimeInterval(-5))
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
        for origin in [CGPoint.zero, CGPoint(x: 1920, y: 0), CGPoint(x: -1366, y: 0),
                       CGPoint(x: 0, y: 1080), CGPoint(x: 0, y: -1024)] {
            let host = setup(present: false)
            let clickedScreen = NSScreen()
            clickedScreen.displayID = 2
            clickedScreen.frame = CGRect(origin: origin, size: CGSize(width: 1366, height: 1024))
            clickedScreen.visibleFrame = CGRect(origin: origin, size: CGSize(width: 1366, height: 1000))
            if origin == .zero {
                // Sidecar is the primary display, with the Mac to its right.
                NSScreen.screens[0].frame.origin.x = 1366
                NSScreen.screens[0].visibleFrame.origin.x = 1366
                host.statusController.button!.window!.frame.origin.x += 1366
                NSScreen.screens.insert(clickedScreen, at: 0)
            } else {
                NSScreen.screens.append(clickedScreen)
            }
            // The reported status frame stays on the Mac. The click is on the
            // iPad's top row, including the shared boundary in a vertical layout.
            let point = CGPoint(x: origin.x + 700, y: clickedScreen.frame.maxY)
            host.lastStatusClick = (point, Date())
            host.showPopover(animate: false, activate: false)
            expect(host.popover.measuredScreen === clickedScreen,
                   "panel height uses the clicked display before presentation at \(origin)")
            expect(host.popoverAnchor?.screen === clickedScreen
                   && host.popoverAnchor?.overridesSoundFrame == true,
                   "click overrides a valid status frame on another display at \(origin)")
            let frame = host.popover.contentViewController!.view.window!.frame
            expect(clickedScreen.visibleFrame.contains(frame) && frame.midX == point.x
                   && frame.maxY == clickedScreen.visibleFrame.maxY,
                   "panel opens below the clicked menu bar at \(origin)")

            host.lastStatusClick = (point, Date().addingTimeInterval(-5))
            close(host)
            expect(host.popover.measuredScreen === clickedScreen
                   && host.popoverLastFrame == frame,
                   "recovery retains the clicked display after the opening click expires at \(origin)")
            DispatchQueue.main.drain()
        }
        do {
            let host = setup(present: false)
            let other = NSScreen()
            other.displayID = 2
            other.frame.origin.x = 1920
            NSScreen.screens.append(other)
            host.lastStatusClick = (CGPoint(x: 2600, y: 1065), Date().addingTimeInterval(-1))
            host.showPopover(animate: false, activate: false)
            expect(host.popoverAnchor?.screen === NSScreen.screens[0]
                   && host.popoverAnchor?.overridesSoundFrame == false,
                   "an expired click cannot move a later presentation to another display")
        }
        do {
            let host = setup()
            host.popover.isShown = false
            host.endPopoverDriftCorrection()
            host.statusController.button!.window!.frame.origin.y = 1100
            host.lastStatusClick = (CGPoint(x: 1100, y: 1065), Date())
            host.showPopover(animate: false, activate: false)
            expect(host.popoverLastFrame?.midX == 1100,
                   "a new physical click takes priority over a remembered anchor")
        }
        do {
            let host = setup(present: false)
            let screen = NSScreen()
            screen.displayID = 2
            screen.frame.origin.x = 1920
            screen.visibleFrame.origin.x = 1920
            NSScreen.screens.append(screen)
            host.statusController.button!.window!.frame.origin.x += 1920
            host.showPopover(animate: false, activate: false)
            let panel = host.popover.contentViewController!.view.window!
            panel.setFrame(CGRect(x: 3200, y: 530, width: 332, height: 500), display: false)
            let settings = NSWindow(CGRect(x: 100, y: 100, width: 800, height: 700))
            host.positionSettingsWindow(settings, force: false)
            expect(screen.visibleFrame.contains(settings.frame) && !settings.frame.intersects(panel.frame),
                   "reopened Settings moves from the Mac to the panel's display")
            let placed = settings.frame
            host.positionSettingsWindow(settings, force: false)
            expect(settings.frame == placed, "Settings keeps its position on the requested display")
            host.popover.isShown = false
            let freshSettings = NSWindow(CGRect(x: 100, y: 100, width: 800, height: 700))
            host.positionSettingsWindow(freshSettings, force: true, on: screen)
            expect(screen.visibleFrame.contains(freshSettings.frame),
                   "new Settings uses the invocation display even without an open panel")
            screen.isStillAttached = false
            NSScreen.screens.removeLast()
            freshSettings.screen = NSScreen.screens.first
            host.positionSettingsWindow(freshSettings, force: false, on: screen)
            expect(NSScreen.screens[0].visibleFrame.contains(freshSettings.frame),
                   "Settings stays reachable if the requested display disconnects before placement")
        }
        for invalidEvent in [nil, event(.keyDown), event(age: 1), event(age: -1)] {
            let host = setup(present: false)
            host.lastStatusClick = (CGPoint(x: 1100, y: 1065), Date())
            NSApp.currentEvent = invalidEvent
            host.captureStatusClick()
            expect(host.lastStatusClick == nil,
                   "keyboard, accessibility and stale events clear the previous status click")
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
        for reason in [PanelCloseReason.escape, .statusItem, .outsideClick, .action] {
            let (host, source) = trackingSetup()
            requestClose(host, reason)
            DispatchQueue.main.drain()
            expect(!host.popover.isShown && !host.activationTracking
                       && source.activations == (reason.dismissesWithoutTakeover ? 1 : 0),
                   "a \(reason) close ends activation tracking and respects its handback policy")
        }
        do {
            let (host, source) = trackingSetup()
            host.closePopoverNow(animated: true, reason: .escape, completion: nil)
            host.closePopoverNow(animated: true, reason: .action, completion: nil)
            host.closePopoverNow(animated: true, reason: .statusItem, completion: nil)
            close(host)
            DispatchQueue.main.drain()
            expect(source.activations == 0 && !host.activationTracking,
                   "an action joining a dismissal keeps activation where it goes")
        }
        do {
            let host = setup()
            notifyCloses(host)
            let window = host.popover.contentViewController!.view.window!
            host.closePopoverNow(animated: true, reason: .statusItem, completion: nil)
            expect(host.popover.isShown && host.popoverIsClosing && window.alphaValue == 0 && window.ignoresMouseEvents,
                   "an animated close fades the panel out and stops it taking clicks")
            NSAnimationContext.finish()
            expect(!host.popover.isShown && !host.popoverIsClosing && SystemMonitor.shared.needs == .none,
                   "the panel closes and releases sampling as soon as its fade ends")
            expect(window.alphaValue == 1 && !window.ignoresMouseEvents,
                   "the closed panel's window is ready to be shown again")
            host.showPopover(animate: false, activate: false)
            expect(host.popover.isShown && host.popover.attempts == 2,
                   "a click right after the panel closed opens it again")
        }
        do {
            let host = setup()
            notifyCloses(host)
            let window = host.popover.contentViewController!.view.window!
            host.closePopoverNow(animated: true, reason: .statusItem, completion: nil)
            host.showPopover(animate: false, activate: false)
            expect(host.popover.isShown && host.popover.attempts == 2 && !host.popoverIsClosing,
                   "a click while the panel fades out opens it again")
            expect(ProcessUsageService.shared.releases == 0 && window.alphaValue == 1 && !window.ignoresMouseEvents,
                   "an interrupted close restores its window without releasing the presentation's resources")
            NSAnimationContext.finish()
            expect(host.popover.isShown && host.popover.attempts == 2 && ProcessUsageService.shared.releases == 0,
                   "the interrupted fade never closes the reopened panel")
        }
        for interruptFade in [false, true] {
            let host = setup(present: interruptFade)
            notifyCloses(host)
            if interruptFade {
                host.closePopoverNow(animated: true, reason: .statusItem, completion: nil)
            }
            host.showMetricPanel(for: MenuBarMetric(detailKind: "cpu"), anchoredTo: host.statusController.button!)
            expect(MenuPanelFocus.shared.request == "cpu" && MenuPanelFocus.shared.activeMetric == "cpu",
                   "opening a metric keeps its view request and toggle identity with interrupted fade \(interruptFade)")
            host.showMetricPanel(for: MenuBarMetric(detailKind: "cpu"), anchoredTo: host.statusController.button!)
            expect(!host.popover.isShown && host.scheduledReanchors == 0,
                   "the next click on the same metric closes it with interrupted fade \(interruptFade)")
            NSAnimationContext.finish()
            expect(!host.popover.isShown && MenuPanelFocus.shared.activeMetric == nil,
                   "the metric stays closed when the old fade finishes")
        }
        for interruptFade in [false, true] {
            let (host, source) = trackingSetup()
            notifyCloses(host)
            var completions = 0
            host.closePopoverNow(animated: true, reason: .statusItem, completion: { completions += 1 })
            if interruptFade {
                host.showPopover(animate: false)
                expect(host.panelActivationSource === source && host.activationTrackingStarts == 1,
                       "reopening during the fade preserves the existing activation source and observers")
                DispatchQueue.main.drain()
                expect(source.activations == 0, "an interrupted close does not hand activation away from the reopened panel")
                host.closePopoverNow(animated: false, reason: .statusItem, completion: nil)
            }
            NSAnimationContext.finish()
            DispatchQueue.main.drain()
            expect(completions == 1 && source.activations == 1 && !host.activationTracking,
                   "the final dismissal completes once and returns activation with interrupted fade \(interruptFade)")
        }
        do {
            let (host, source) = trackingSetup()
            notifyCloses(host)
            host.closePopoverNow(animated: true, reason: .statusItem, completion: nil)
            let nextSource = NSRunningApplication(pid: 888)
            NSWorkspace.shared.frontmostApplication = nextSource
            host.updatePanelActivationSource(.appActivated(nextSource))
            host.showPopover(animate: false)
            expect(host.panelActivationSource === nextSource, "reopening keeps an app change observed during the fade")
            host.closePopoverNow(animated: false, reason: .escape, completion: nil)
            DispatchQueue.main.drain()
            expect(source.activations == 0 && nextSource.activations == 1,
                   "the final close returns to the newly observed app, not the original one")
        }
        do {
            let (host, source) = trackingSetup()
            notifyCloses(host)
            host.closePopoverNow(animated: true, reason: .statusItem, completion: nil)
            host.updatePanelActivationSource(.activeSpaceChanged)
            host.showPopover(animate: false)
            expect(host.panelActivationSource == nil, "reopening does not restore a source cleared by a Space change")
            host.closePopoverNow(animated: false, reason: .escape, completion: nil)
            DispatchQueue.main.drain()
            expect(source.activations == 0, "the final close leaves activation alone after a Space change")
        }
        do {
            let host = setup()
            notifyCloses(host)
            let source = NSRunningApplication(pid: 777)
            NSWorkspace.shared.frontmostApplication = source
            host.closePopoverNow(animated: true, reason: .statusItem, completion: nil)
            host.showPopover(animate: false)
            expect(host.activationTrackingStarts == 1 && host.panelActivationSource === source,
                   "a reopen that activates a previously inactive panel starts activation tracking")
        }
        do {
            let (host, source) = trackingSetup()
            notifyCloses(host)
            host.closePopoverNow(animated: true, reason: .statusItem, completion: nil)
            host.popover.fails = true
            host.showPopover(animate: false)
            NSAnimationContext.finish()
            DispatchQueue.main.drain()
            expect(!host.popover.isShown && !host.popoverIsReopening && !host.activationTracking
                       && !host.monitors && !host.statusController.held
                       && MenuPanelFocus.shared.activeMetric == nil && ProcessUsageService.shared.releases == 1,
                   "a failed fade reopen releases resources, metric focus, monitors and activation observers")
            expect(source.activations == 1, "a failed fade reopen finishes the original dismissal's handback")
        }
        for blocked in ["terminated", "own window", "other app", "other desktop"] {
            let (host, source) = trackingSetup()
            notifyCloses(host)
            host.closePopoverNow(animated: true, reason: .statusItem, completion: nil)
            host.showPopover(animate: false)
            host.closePopoverNow(animated: false, reason: .escape, completion: nil)
            switch blocked {
            case "terminated": source.isTerminated = true
            case "own window": NSApp.keyWindow = NSWindow(.zero)
            case "other app": NSWorkspace.shared.frontmostApplication = NSRunningApplication(pid: 888)
            default: host.switchesDesktop = true
            }
            DispatchQueue.main.drain()
            expect(source.activations == 0, "an interrupted reopen still respects the \(blocked) handback guard")
        }
        do {
            let (host, source) = trackingSetup()
            NSApp.currentEvent = event(age: 1)
            close(host)
            DispatchQueue.main.drain()
            expect(!host.popover.isShown && source.activations == 0,
                   "a close Vorssaint did not ask for does not hand activation back")
        }
        do {
            let host = setup()
            expect(host.activationTrackingStarts == 0, "a panel shown without activating remembers no app")
            requestClose(host, .escape)
            host.showPopover(animate: false)
            expect(host.activationTrackingStarts == 1 && host.activationTracking,
                   "a click that activates the panel starts following the app in front")
            requestClose(host, .escape)
            expect(!host.activationTracking, "closing the panel stops following activation")
        }
        do {
            let (host, source) = trackingSetup()
            close(host)
            expect(host.popover.isShown && source.activations == 0 && host.activationTracking,
                   "a panel reopened in place after a foreign close keeps activation and its tracking")
            DispatchQueue.main.drain()
            requestClose(host, .escape); DispatchQueue.main.drain()
            expect(source.activations == 1 && !host.activationTracking,
                   "the close after a recovery still hands activation back")
        }
        do {
            let (host, _) = trackingSetup()
            host.popover.fails = true
            close(host); DispatchQueue.main.drain()
            expect(!host.popover.isShown && !host.activationTracking,
                   "a recovery that fails to reopen stops following activation")
        }
        do {
            let (host, source) = trackingSetup()
            host.popoverIsSwitchingAnchor = true; requestClose(host, .statusItem)
            DispatchQueue.main.drain()
            expect(source.activations == 0 && host.activationTracking,
                   "moving the panel between metric anchors keeps activation and its tracking")
        }
    }
}
