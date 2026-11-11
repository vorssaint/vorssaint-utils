// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox

/// The production lookups of the display under the pointer run against
/// stand-in screens, so the edges between displays are checked without a
/// second monitor. Nothing is captured, moved, warped or shown.
enum PointerDisplayLookupContract {
    final class Screen {
        typealias NSScreen = Screen
        typealias NSEvent = Event
        static var screens: [Screen] = []
        static var main: Screen?
        let displayID: CGDirectDisplayID
        let frame: NSRect
        let visibleFrame: NSRect
        let backingScaleFactor: CGFloat
        var deviceDescription: [NSDeviceDescriptionKey: Any] {
            [NSDeviceDescriptionKey("NSScreenNumber"): NSNumber(value: displayID)]
        }
        init(_ displayID: CGDirectDisplayID, _ frame: NSRect, scale: CGFloat) {
            self.displayID = displayID
            self.frame = frame
            visibleFrame = NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - 25)
            backingScaleFactor = scale
        }
    }
    enum Event { static var mouseLocation = NSPoint.zero }

    /// `SpaceWindowBridge` over a fixed Space topology.
    enum Bridge {
        typealias NSScreen = Screen
        static var current: Topology?
        static func topology() -> Topology? { current }
    }

    /// `WindowLayoutService` with an indicator panel that only keeps its frame.
    final class Layout {
        typealias NSScreen = Screen
        typealias NSPanel = Panel
        typealias OverlayPanel = Panel
        final class Panel {
            var frame = CGRect.zero
            var backgroundColor = NSColor.clear
            var isOpaque = false
            var hasShadow = true
            var ignoresMouseEvents = true
            var hidesOnDeactivate = false
            var isReleasedWhenClosed = false
            var level = NSWindow.Level.statusBar
            var collectionBehavior: NSWindow.CollectionBehavior = []
            var animationBehavior = NSWindow.AnimationBehavior.none
            var contentView: AnyObject?
            var alphaValue: CGFloat = 0
            init(contentRect: CGRect, styleMask: NSWindow.StyleMask,
                 backing: NSWindow.BackingStoreType, defer flag: Bool) {}
            func setFrame(_ frame: CGRect, display: Bool) { self.frame = frame }
            func orderFrontRegardless() {}
            func animator() -> Panel { self }
        }
        final class WindowDirectionalIndicatorView { init(frame: CGRect) {} }
        var directionalIndicatorPanel: Panel? = Panel(contentRect: .zero, styleMask: [],
                                                      backing: .buffered, defer: false)
        func updateDirectionalIndicator(action: WindowDirectionalAction?) {}
    }

    /// `QuitProtectionHUD` with a panel that only keeps its origin.
    final class HUD {
        typealias NSScreen = Screen
        typealias NSEvent = Event
        final class Panel {
            var origin: CGPoint?
            func setFrameOrigin(_ point: CGPoint) { origin = point }
        }
        var panel: Panel? = Panel()
        let size = CGSize(width: 300, height: 48)
    }

    /// `DockPreviewService` dropping a dragged window, with an activator that
    /// records where the window's top-left corner was sent.
    final class Dock {
        typealias NSScreen = Screen
        typealias NSEvent = Event
        struct SwitcherItem {
            let windowID: CGWindowID?
            let frame: CGRect
        }
        final class DockPreviewDragGhost {
            static let shared = DockPreviewDragGhost()
            func end() {}
        }
        enum WindowActivator {
            static var origins: [CGPoint] = []
            static func place(_ item: SwitcherItem, origin: CGPoint, pointer: CGPoint) -> Bool {
                origins.append(origin)
                return false
            }
            static func activate(_ item: SwitcherItem, handoffSourcePID: pid_t? = nil) {}
            static func focusPlacedWindow(_ item: SwitcherItem) {}
        }
        var isDraggingWindow = true
        func endSession() {}
        func axPoint(fromAppKit point: CGPoint) -> CGPoint { point }
    }

    static func run(_ suite: TestSuite) {
        var finished = false
        Task { @MainActor in
            await checks(suite)
            finished = true
        }
        let deadline = Date().addingTimeInterval(10)
        while !finished && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        suite.expect(finished, "the pointer display lookups finish without a display")
    }

    /// The display each production lookup settles on for one pointer position.
    @MainActor static func displays(under pointer: NSPoint) async -> [(String, CGDirectDisplayID?)] {
        func display(holding rect: CGRect) -> CGDirectDisplayID? {
            Screen.screens.first { $0.visibleFrame.contains(rect) }?.displayID
        }
        Event.mouseLocation = pointer
        let layout = Layout()
        layout.showDirectionalIndicator(at: pointer, action: nil)
        let hud = HUD()
        hud.positionPanel(on: nil)
        Dock.WindowActivator.origins = []
        let window = CGSize(width: 400, height: 300)
        Dock().endWindowDrag(Dock.SwitcherItem(windowID: 1, frame: CGRect(origin: .zero, size: window)))
        return [
            ("the Space a dropped window joins", Bridge.visibleSpace(near: pointer).map { CGDirectDisplayID($0 / 10) }),
            ("the directional layout indicator", layout.directionalIndicatorPanel.flatMap { display(holding: $0.frame) }),
            ("the quit confirmation", hud.panel?.origin.flatMap { display(holding: CGRect(origin: $0, size: hud.size)) }),
            ("a window dropped from a Dock preview", Dock.WindowActivator.origins.first.flatMap {
                display(holding: CGRect(x: $0.x, y: $0.y - window.height, width: window.width, height: window.height))
            }),
        ]
    }

    @MainActor static func checks(_ suite: TestSuite) async {
        // A Retina primary with a display on its right and one stacked above.
        // AppKit reports a display's top row at frame.maxY and its bottom row
        // just above frame.minY. The key window, and so `main`, stays on the
        // primary.
        let primary = Screen(1, NSRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
        let right = Screen(2, NSRect(x: 1440, y: 0, width: 1920, height: 1080), scale: 1)
        let above = Screen(3, NSRect(x: 0, y: 900, width: 1440, height: 900), scale: 1)
        Screen.screens = [primary, right, above]
        Screen.main = primary
        Bridge.current = Bridge.Topology(displays: Screen.screens.map {
            .init(displayID: $0.displayID, spaces: [], fullscreenSpaces: [],
                  currentSpace: UInt64($0.displayID) * 10)
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
        let outside = (NSPoint(x: 5000, y: 5000), primary, "a pointer outside every display")
        for (pointer, expected, place) in edges + [outside] {
            for (lookup, found) in await displays(under: pointer) {
                suite.expect(found == expected.displayID,
                             "\(lookup) follows \(place) to display \(expected.displayID), found \(found.map(String.init) ?? "none")")
            }
        }
        Screen.screens = []
        Screen.main = nil
        Bridge.current = nil
        Event.mouseLocation = .zero
    }
}
