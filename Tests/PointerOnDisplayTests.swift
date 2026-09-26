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
        static func pressSpaceShortcut(_ shortcut: SpaceShortcut) { presses += 1 }
    }

    /// `SpaceHop` taking one step toward a window on a hidden Space, with a
    /// pointer warp that only records where it would go.
    final class Hop {
        typealias NSScreen = Screen
        typealias NSEvent = Event
        typealias SpaceWindowBridge = Bridge
        struct CGEvent {
            let location = CGPoint.zero
            init?(source: CGEventSource?) {}
        }
        let windowID: CGWindowID = 1
        var cancelled = false
        var arrowPressesLeft = SpaceHopSupport.maximumArrowSteps
        var originalCursorLocation: CGPoint?
        var warpedCursorLocation: CGPoint?
        var warps: [CGPoint] = []
        func windowSpaceIsVisible() -> Bool { false }
        func focusOnArrival() {}
        func finish() {}
        func waitForTravel(from visibleBefore: Set<UInt64>, then completion: @escaping (TravelOutcome) -> Void) {}
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
