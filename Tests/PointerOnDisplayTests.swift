// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The production checks of whether the pointer is on a display run against
/// stand-in screens, so the edges between displays are covered without a
/// second monitor. Nothing is warped, pressed or shown.
enum PointerOnDisplayContract {
    final class Screen {
        static var screens: [Screen] = []
        static var main: Screen?
        let displayID: CGDirectDisplayID
        let frame: NSRect
        var deviceDescription: [NSDeviceDescriptionKey: Any] {
            [NSDeviceDescriptionKey("NSScreenNumber"): NSNumber(value: displayID)]
        }
        init(_ displayID: CGDirectDisplayID, _ frame: NSRect) {
            self.displayID = displayID
            self.frame = frame
        }

        /// The display as CoreGraphics places it, measured down from the top
        /// of the primary display.
        static func bounds(of displayID: CGDirectDisplayID) -> CGRect {
            guard let frame = screens.first(where: { $0.displayID == displayID })?.frame,
                  let top = screens.first?.frame.maxY else { return .null }
            return CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
        }
    }
    enum Event { static var mouseLocation = NSPoint.zero }
    enum HopCalls { static var values: [String] = [] }

    /// `SpaceWindowBridge` over a fixed Space topology, with a Spaces shortcut
    /// whose presses are only counted.
    enum Bridge {
        enum SpaceDirection { case left, right }
        struct SpaceShortcut {}
        static var current: Topology?
        static var windowSpaces: [UInt64] = []
        static var presses = 0
        static func topology() -> Topology? { current }
        static func spaces(of windowID: CGWindowID) -> [UInt64] { windowSpaces }
        static func spaceShortcut(_ direction: SpaceDirection) -> SpaceShortcut? { SpaceShortcut() }
        static func pressSpaceShortcut(_ shortcut: SpaceShortcut) {
            presses += 1
            HopCalls.values.append("press")
        }
        static func frontWindow(_ windowID: CGWindowID, ownerPID: pid_t) {
            HopCalls.values.append("front:\(windowID):\(ownerPID)")
        }
    }

    /// `SpaceHop` starting and taking one step toward a window on a hidden
    /// Space, with an app and a pointer warp that only record what they did.
    final class Hop {
        typealias NSScreen = Screen
        typealias NSEvent = Event
        typealias SpaceWindowBridge = Bridge
        typealias NSRunningApplication = App
        typealias ActivationHandoff = Handoff
        typealias WindowActivator = Activator
        struct CGEvent {
            let location = CGPoint.zero
            init?(source: CGEventSource?) {}
        }
        final class App {
            static let current = App()
            var isHidden = false
            var unhides = 0
            func unhide() { unhides += 1 }
            var cooperativeActivationSucceeds = true
            var cooperativeOptions: [NSApplication.ActivationOptions] = []
            var fallbackOptions: [NSApplication.ActivationOptions] = []
            var receivedCurrentApp = false
            func activate(from: App, options: NSApplication.ActivationOptions) -> Bool {
                receivedCurrentApp = from === App.current
                cooperativeOptions.append(options)
                HopCalls.values.append("activate")
                return cooperativeActivationSucceeds
            }
            @discardableResult func activate(options: NSApplication.ActivationOptions) -> Bool {
                fallbackOptions.append(options)
                HopCalls.values.append("fallback")
                return true
            }
        }
        enum Handoff {
            static func yield(to app: App) { HopCalls.values.append("yield") }
        }
        enum Activator {
            static var raises = false
            static func raiseWindowOnHiddenSpace(windowID: CGWindowID, pid: pid_t) -> Bool {
                HopCalls.values.append("raise:\(windowID):\(pid)")
                return raises
            }
        }
        let app = App()
        let windowOwnerPID: pid_t = 1
        let windowID: CGWindowID = 1
        var cancelled = false
        var arrowPressesLeft = SpaceHopSupport.maximumArrowSteps
        var originalCursorLocation: CGPoint?
        var warpedCursorLocation: CGPoint?
        var warps: [CGPoint] = []
        var appIsAlreadyHere = false
        var focusCalls = 0
        var waits = 0
        var capturesTravel = false
        var travelCompletion: ((TravelOutcome) -> Void)?
        func windowSpaceIsVisible() -> Bool { false }
        func appHasWindowOnVisibleSpace() -> Bool {
            HopCalls.values.append("visible")
            return appIsAlreadyHere
        }
        func focusOnArrival() {
            focusCalls += 1
            HopCalls.values.append("focus")
        }
        func finish() {}
        func waitForTravel(from visibleBefore: Set<UInt64>, then completion: @escaping (TravelOutcome) -> Void) {
            waits += 1
            HopCalls.values.append("wait")
            if capturesTravel { travelCompletion = completion }
        }
        func completeTravel(_ outcome: TravelOutcome) {
            let completion = travelCompletion
            travelCompletion = nil
            completion?(outcome)
        }
        func CGDisplayBounds(_ display: CGDirectDisplayID) -> CGRect { Screen.bounds(of: display) }
        func CGWarpMouseCursorPosition(_ point: CGPoint) { warps.append(point) }
    }

    /// One display's capture overlay deciding whether its guide shows.
    final class Overlay {
        typealias NSEvent = Event
        struct Options { let controlsInNotch: Bool }
        final class Controller {
            var currentPointerLocation: CGPoint?
            var selectionInProgress = false
        }
        final class Panel {
            let screenFrame: CGRect
            init(_ screenFrame: CGRect) { self.screenFrame = screenFrame }
        }
        final class Guide { var isHidden = false }
        let screenCaptureOptions: Options? = nil
        let controller: Controller? = Controller()
        let panel: Panel?
        let guideHost = Guide()
        let isCapturePending = false
        let displayID: CGDirectDisplayID
        init(_ screen: Screen) {
            panel = Panel(screen.frame)
            displayID = screen.displayID
        }
    }

    /// `DockPreviewService` deciding whether the pointer is close enough to
    /// the Dock to be worth an Accessibility hit test.
    final class Dock {
        typealias NSScreen = Screen
        let cachedPreferences: DockPreviewPreferences?
        init(_ orientation: DockPreviewOrientation) {
            cachedPreferences = DockPreviewPreferences(orientation: orientation, autohide: false, tileSize: 64,
                                                       magnification: false, magnifiedTileSize: 128)
        }
    }

    static func run(_ suite: TestSuite) {
        // A display on the right of the primary and one stacked above it.
        // AppKit reports a display's top row at frame.maxY and its bottom row
        // just above frame.minY. The key window, and so `main`, stays on the
        // primary.
        let primary = Screen(1, NSRect(x: 0, y: 0, width: 1440, height: 900))
        let right = Screen(2, NSRect(x: 1440, y: 0, width: 1920, height: 1080))
        let above = Screen(3, NSRect(x: 0, y: 900, width: 1440, height: 900))
        Screen.screens = [primary, right, above]
        Screen.main = primary
        // Each display shows its first Space; the selected window waits on the
        // second Space of its display.
        Bridge.current = Bridge.Topology(displays: Screen.screens.map {
            let first = UInt64($0.displayID) * 10
            return .init(displayID: $0.displayID, spaces: [first, first + 1],
                         fullscreenSpaces: [], currentSpace: first)
        })
        let edges: [(NSPoint, Screen, String)] = [
            (NSPoint(x: 2000, y: 1080), right, "a pointer on the top row of a secondary display"),
            (NSPoint(x: 700, y: 900), primary, "a pointer on the top row of a display with another above it"),
            (NSPoint(x: 700, y: 1800), above, "a pointer on the top row of the upper display"),
            (NSPoint(x: 700, y: 901), above, "a pointer on the bottom row of the upper display"),
            (NSPoint(x: 700, y: 1), primary, "a pointer on the bottom row of a display"),
            (NSPoint(x: 1440, y: 500), right, "a pointer on the first column of a display on the right"),
            (NSPoint(x: 2000, y: 500), right, "a pointer inside a display"),
        ]
        for (pointer, under, place) in edges {
            Event.mouseLocation = pointer
            // The Spaces shortcut acts on the display under the pointer, so a
            // hop brings the pointer to the window's display only from another.
            for target in Screen.screens {
                Bridge.windowSpaces = [UInt64(target.displayID) * 10 + 1]
                Bridge.presses = 0
                let hop = Hop()
                hop.stepWithSpaceShortcut()
                let bounds = Screen.bounds(of: target.displayID)
                let expected = target === under ? [] : [CGPoint(x: bounds.midX, y: bounds.midY)]
                let behavior = target === under
                    ? "leaves \(place) where it is when the window is on that display"
                    : "brings \(place) to the window's display \(target.displayID)"
                suite.expect(hop.warps == expected && Bridge.presses == 1,
                             "a Space hop \(behavior), found warps \(hop.warps) and \(Bridge.presses) presses")
            }
            // The capture guide follows the pointer to its display and no other.
            let overlays = Screen.screens.map(Overlay.init)
            overlays.forEach { $0.refreshGuideVisibility() }
            let shown = overlays.filter { !$0.guideHost.isHidden }.map(\.displayID)
            suite.expect(shown == [under.displayID],
                         "the capture guide shows only on display \(under.displayID) for \(place), found \(shown)")
        }
        // Issue #1503: unhiding an app that is not hidden raises every one of
        // its windows, so a hop shows its app again only when it was hidden.
        let visibleHop = Hop()
        visibleHop.start()
        let hiddenHop = Hop()
        hiddenHop.app.isHidden = true
        hiddenHop.start()
        suite.expect(visibleHop.app.unhides == 0 && hiddenHop.app.unhides == 1,
                     "a Space hop unhides its app only when the app is hidden")

        // The extracted production start must try the exact window before
        // deciding whether to replay a shortcut. Fronting a hidden window
        // through the window server can cancel the native travel.
        Bridge.windowSpaces = [11]
        Event.mouseLocation = NSPoint(x: 700, y: 500)
        for raises in [false, true] {
            for here in [false, true] {
                for acceptsActivation in [false, true] {
                    HopCalls.values = []
                    Bridge.presses = 0
                    Hop.Activator.raises = raises
                    let hop = Hop()
                    hop.appIsAlreadyHere = here
                    hop.app.cooperativeActivationSucceeds = acceptsActivation
                    hop.start()
                    let movesImmediately = !raises && here
                    let options: NSApplication.ActivationOptions = here || raises ? [] : [.activateAllWindows]
                    var expectedCalls = ["visible", "raise:1:1"]
                    if movesImmediately { expectedCalls.append("front:1:1") }
                    expectedCalls += ["yield", "activate"]
                    if !acceptsActivation { expectedCalls.append("fallback") }
                    if movesImmediately { expectedCalls.append("press") }
                    expectedCalls.append("wait")
                    let state = "raise=\(raises), app visible=\(here), activation accepted=\(acceptsActivation)"
                    suite.expect(HopCalls.values == expectedCalls,
                                 "Space hop ordering for \(state), found \(HopCalls.values)")
                    suite.expect(hop.app.receivedCurrentApp
                                 && hop.app.cooperativeOptions == [options]
                                 && hop.app.fallbackOptions == (acceptsActivation ? [] : [options]),
                                 "Space hop keeps the same cooperative and fallback options for \(state)")
                    suite.expect(Bridge.presses == (movesImmediately ? 1 : 0)
                                 && hop.waits == 1 && hop.focusCalls == 0,
                                 "Space hop waits for native travel or its first shortcut for \(state)")
                }
            }
        }

        let outcomes: [(Hop.TravelOutcome, String, Bool)] = [
            (.arrived, "arrival", true),
            (.stalled, "stalled travel", false),
            (.landedShort, "travel to an intermediate Space", false),
        ]
        for (outcome, name, arrives) in outcomes {
            Bridge.presses = 0
            Hop.Activator.raises = true
            let hop = Hop()
            hop.appIsAlreadyHere = true
            hop.capturesTravel = true
            hop.start()
            HopCalls.values = []
            hop.completeTravel(outcome)
            suite.expect(hop.focusCalls == (arrives ? 1 : 0)
                         && Bridge.presses == (arrives ? 0 : 1)
                         && hop.waits == (arrives ? 1 : 2)
                         && HopCalls.values == (arrives ? ["focus"] : ["press", "wait"]),
                         "Space hop handles \(name) by focusing the target or trying one shortcut")
            hop.travelCompletion = nil
        }
        for outcome in [Hop.TravelOutcome.stalled, .landedShort] {
            Bridge.presses = 0
            let hop = Hop()
            hop.capturesTravel = true
            hop.start()
            hop.cancelled = true
            HopCalls.values = []
            hop.completeTravel(outcome)
            suite.expect(Bridge.presses == 0 && hop.waits == 1
                         && hop.arrowPressesLeft == SpaceHopSupport.maximumArrowSteps
                         && hop.warps.isEmpty && HopCalls.values.isEmpty,
                         "a cancelled hop cannot replay a shortcut after unsuccessful native travel")
        }
        let cancelledHop = Hop()
        cancelledHop.cancelled = true
        Bridge.presses = 0
        cancelledHop.stepWithSpaceShortcut()
        suite.expect(Bridge.presses == 0 && cancelledHop.waits == 0
                     && cancelledHop.arrowPressesLeft == SpaceHopSupport.maximumArrowSteps
                     && cancelledHop.warps.isEmpty,
                     "a hop cancelled before its first step does not press or move the pointer")
        Hop.Activator.raises = false
        HopCalls.values = []

        // With 64-point icons the Dock's strip is 160 points deep, measured
        // from the edge of the display the pointer is on.
        let dock: [(NSPoint, DockPreviewOrientation, Bool, String)] = [
            (NSPoint(x: 700, y: 900), .bottom, false, "a pointer on the top row of a display with another above it"),
            (NSPoint(x: 2000, y: 1080), .right, false, "a pointer on the top row of a display on the right"),
            (NSPoint(x: 3300, y: 1080), .right, true, "a pointer on the top row of a display on the right, by its right edge"),
            (NSPoint(x: 700, y: 901), .bottom, true, "a pointer on the bottom row of the upper display"),
            (NSPoint(x: 700, y: 1), .bottom, true, "a pointer on the bottom row of a display"),
            (NSPoint(x: 1440, y: 500), .left, true, "a pointer on the first column of a display on the right"),
        ]
        for (pointer, orientation, near, place) in dock {
            let found = Dock(orientation).isNearDock(pointer)
            suite.expect(found == near,
                         "\(place) is \(near ? "inside" : "outside") the strip of a Dock on the \(orientation) edge of that display, found \(found)")
        }
        Screen.screens = []
        Screen.main = nil
        Bridge.current = nil
        Bridge.windowSpaces = []
        Event.mouseLocation = .zero
    }
}
