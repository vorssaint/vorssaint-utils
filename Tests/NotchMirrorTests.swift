// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

/// With the island on every display, each other display shows a copy of
/// what it shows closed. The copies' bodies come from production; displays,
/// windows, Spaces and preferences are controlled boundaries.
enum NotchMirrorContract {
    final class NSScreen: Equatable {
        static var screens: [NSScreen] = []
        static var screensHaveSeparateSpaces = true
        static var withMenuBar: NSScreen? { screens.first }
        let notchDisplayID: CGDirectDisplayID
        let frame: CGRect
        let notched: Bool
        init(_ id: CGDirectDisplayID, _ frame: CGRect, notched: Bool = false) {
            notchDisplayID = id
            self.frame = frame
            self.notched = notched
        }
        static func == (left: NSScreen, right: NSScreen) -> Bool { left === right }
    }
    enum NotchContentTransition { case none, replace }
    final class Panel {
        var isVisible = false
        var sharingType = NSWindow.SharingType.readOnly
        var orders = 0
        var orderedBelow = 0
        var windowNumber = 1
        func orderFrontRegardless() { isVisible = true; orders += 1 }
        func order(_ place: NSWindow.OrderingMode, relativeTo otherWindow: Int) {
            isVisible = true
            orders += 1
            if place == .below { orderedBelow += 1 }
        }
    }
    final class Host {
        let panel = Panel()
        var presented: [(size: CGSize, geometry: NotchGeometry, animated: Bool, transition: NotchContentTransition)] = []
        var hides = 0, closes = 0
        var outline: (enabled: Bool, color: NSColor)?
        var activationRect = CGRect.zero
        var activate: (() -> Void)?
        var settling = false
        var settled: [() -> Void] = []
        func present(size: CGSize, geometry: NotchGeometry, animated: Bool, transitionContent: NotchContentTransition) {
            presented.append((size, geometry, animated, transitionContent))
        }
        func hide(animated: Bool) { hides += 1; panel.isVisible = false }
        func close() { closes += 1; panel.isVisible = false }
        func setOutline(enabled: Bool, color: NSColor) { outline = (enabled, color) }
        func setActivationArea(_ rect: CGRect, title: String, willPress: @escaping () -> Void, activate: @escaping () -> Void) {
            activationRect = rect
            self.activate = activate
        }
        func whenSettled(_ action: @escaping () -> Void) {
            if settling { settled.append(action) } else { action() }
        }
    }
    struct NotchMirror {
        let host: Host
        let model: NotchMirrorModel
    }
    enum SpaceWindowBridge {
        static var fullscreen: Set<CGDirectDisplayID> = []
        struct Topology {
            func isFullscreen(on id: CGDirectDisplayID, separateSpaces: Bool) -> Bool { SpaceWindowBridge.fullscreen.contains(id) }
        }
        static func topology() -> Topology? { Topology() }
    }
    enum NotchAppFullscreen {
        static var covered: Set<CGDirectDisplayID> = []
        static func coveredDisplays() -> Set<CGDirectDisplayID> { covered }
    }

    class State {
        var showsOnAllDisplays = true, running = true, suspended = false
        var windowHost: Host? = Host()
        var mirrorHeldForArrival: CGDirectDisplayID?
        var displayID: CGDirectDisplayID? = 1
        var mirrors: [CGDirectDisplayID: NotchMirror] = [:]
        var fullscreenDisplays: Set<CGDirectDisplayID> = []
        var compactActivity: NotchCompactActivity?
        var compactCompanion: NotchCompactActivity?
        var idleContent = NotchIdleContent.none
        var mascotVisible = false
        func mascotShows(on geometry: NotchGeometry) -> Bool {
            mascotVisible && (geometry.floats || geometry.restingWingWidth > 0)
        }
        var expanded = false, peeking = false, canFollowPointer = true
        var hidesUntilHover = false, hiddenShowsActivity = false, coversMenus = true, showsInCaptures = true
        var outlineEnabled = false, hidesInFullscreen = false
        let openTitle = "Open"
        var opened = 0, collapses = 0, countdownOpenings = 0
        var moves: [CGDirectDisplayID] = []
        var made: [Host] = []

        /// A built-in display with a camera housing, or an external one with a capsule.
        func baseGeometry(for screen: NSScreen) -> NotchGeometry {
            NotchGeometry(screen: screen.frame, safeAreaTop: screen.notched ? 32 : 0,
                          cameraWidth: screen.notched ? 185 : 0, menuBarHeight: screen.notched ? 32 : 24,
                          silhouette: .capsule)
        }
        /// Each activity's capsule a fixed width wider than the bare one, so sizes are traceable.
        func capsuleStripSize(for activity: NotchCompactActivity, companion: NotchCompactActivity?,
                              geometry: NotchGeometry?) -> CGSize {
            let geometry = geometry!
            return CGSize(width: geometry.restingSize(showsContent: false).width + 40, height: geometry.stripHeight)
        }
        func compactGeometry(for activity: NotchCompactActivity?, companion: NotchCompactActivity?,
                             base: NotchGeometry?) -> NotchGeometry {
            base!.compactTimerGeometry(showsDownloads: false, wing: 60)
        }
        func makeMirror(geometry: NotchGeometry, size: CGSize) -> NotchMirror {
            let host = Host()
            made.append(host)
            return NotchMirror(host: host, model: NotchMirrorModel(geometry: geometry, size: size))
        }
        func collapse() { collapses += 1; expanded = false; peeking = false }
        func open() { opened += 1; expanded = true }
        func openCountdownEvent() { countdownOpenings += 1; expanded = true }
        func move(to screen: NSScreen) { displayID = screen.notchDisplayID; moves.append(screen.notchDisplayID) }
    }

    static func run(_ suite: TestSuite) {
        defer {
            NSScreen.screens = []
            NSScreen.screensHaveSeparateSpaces = true
            SpaceWindowBridge.fullscreen = []
            NotchAppFullscreen.covered = []
        }
        let builtIn = NSScreen(1, CGRect(x: 0, y: 0, width: 1470, height: 956), notched: true)
        let external = NSScreen(2, CGRect(x: 1470, y: -86, width: 1920, height: 1080))
        NSScreen.screens = [builtIn, external]
        NSScreen.screensHaveSeparateSpaces = false

        let service = Service()
        service.syncMirrors()
        let capsule = service.mirrors[2]
        suite.expect(service.mirrors.count == 1 && service.mirrors[1] == nil && capsule?.model.shown == true
                     && capsule?.host.presented.count == 1 && capsule?.host.presented.first?.animated == false
                     && capsule?.host.panel.isVisible == true && capsule?.model.activity == nil,
                     "every display but the island's own shows a copy, at once")
        let external2 = service.baseGeometry(for: external)
        suite.expect(capsule?.model.geometry.floats == true && capsule?.model.geometry.screen == external.frame
                     && capsule?.model.size == external2.restingSize(showsContent: false)
                     && capsule?.host.activationRect == CGRect(origin: .zero, size: capsule?.model.size ?? .zero),
                     "a copy draws its own display's island, a capsule at rest there, and all of it takes a click")
        service.syncMirrors()
        suite.expect(capsule?.host.presented.count == 1 && service.made.count == 1,
                     "an island that changes nothing a copy shows leaves the copy as it is")

        service.outlineEnabled = true
        service.compactActivity = .timer
        service.syncMirrors()
        suite.expect(capsule?.host.presented.count == 2 && capsule?.host.presented.last?.transition == .replace
                     && capsule?.host.presented.last?.animated == true
                     && capsule?.model.size.width == external2.restingSize(showsContent: false).width + 40
                     && capsule?.host.outline?.enabled == true && capsule?.host.outline?.color == .systemOrange,
                     "a timer starting reshapes each copy as the island does, in the timer's outline")

        let trading = Service()
        trading.syncMirrors()
        let kept = trading.mirrors[2]
        trading.windowHost?.panel.isVisible = true
        trading.mirrorHeldForArrival = 2
        trading.displayID = 2
        trading.syncMirrors()
        let underneath = trading.mirrors[1]
        suite.expect(kept?.model.shown == true && kept?.host.hides == 0
                     && underneath?.model.shown == true && underneath?.host.panel.orderedBelow == 1,
                     "while the island moves, the copy it is joining stays up and the one it leaves sits underneath")
        trading.mirrorHeldForArrival = nil
        trading.syncMirrors()
        suite.expect(kept?.model.shown == false && kept?.host.hides == 1 && underneath?.model.shown == true,
                     "the copy steps aside once the island has arrived on its display")
        arrivalVisibilityContracts(suite)

        // The island follows the pointer to the external display.
        service.displayID = 2
        service.syncMirrors()
        let notch = service.mirrors[1]
        var builtInBase = service.baseGeometry(for: builtIn)
        builtInBase.compactSideRoom = NotchMenuBarLayout.sideRoom(screen: builtInBase.screen, cameraWidth: builtInBase.cameraWidth,
                                                                  barHeight: builtInBase.menuBarHeight, occupied: [])
        let strip = service.compactGeometry(for: .timer, companion: nil, base: builtInBase)
        suite.expect(capsule?.model.shown == false && capsule?.host.hides == 1 && capsule?.host.panel.isVisible == false
                     && notch?.model.shown == true && notch?.model.geometry.isNotched == true
                     && notch?.model.strip == strip && notch?.model.size == strip.compactActivitySize
                     && notch?.host.presented.last?.animated == false,
                     "the copy steps aside where the island arrives and one appears where it left, drawn for the camera")
        suite.expect(notch?.model.geometry.compactSideRoom == builtInBase.compactSideRoom,
                     "an island that may cover menus gives its copy the room of an empty bar")

        service.hidesUntilHover = true
        service.syncMirrors()
        suite.expect(notch?.model.shown == false && notch?.host.hides == 1,
                     "an island hidden until the pointer reaches it hides its copies too")
        service.hidesUntilHover = false
        service.syncMirrors()
        suite.expect(notch?.model.shown == true, "a copy returns with the island at rest")

        service.hidesInFullscreen = true
        SpaceWindowBridge.fullscreen = [1]
        service.updateFullscreenDisplays()
        service.syncMirrors()
        suite.expect(service.fullscreenDisplays == [1] && notch?.model.shown == false && notch?.host.hides == 2,
                     "a copy leaves a display in full screen when the island hides there")
        service.hidesInFullscreen = false
        service.updateFullscreenDisplays()
        suite.expect(service.fullscreenDisplays.isEmpty, "only the choice to hide in full screen reads Spaces")
        service.syncMirrors()
        suite.expect(notch?.model.shown == true && notch?.host.presented.last?.animated == false,
                     "leaving full screen shows the copy again at once")

        // Set to show activity, a hidden island's copies draw the activity it
        // shows, and go with it once nothing runs.
        service.hidesUntilHover = true
        service.syncMirrors()
        service.hiddenShowsActivity = true
        service.syncMirrors()
        suite.expect(notch?.model.shown == true && notch?.model.activity == .timer && notch?.host.panel.isVisible == true,
                     "copies of a hidden island set to show activity draw the activity it shows")
        service.compactActivity = nil
        service.syncMirrors()
        suite.expect(notch?.model.shown == false, "the copies of a hidden island go once its activity ends")
        service.compactActivity = .timer
        service.hiddenShowsActivity = false
        service.hidesUntilHover = false
        service.syncMirrors()

        // Displays with their own menu bars and menus the island must not cover.
        NSScreen.screensHaveSeparateSpaces = true
        service.coversMenus = false
        service.displayID = 1
        service.syncMirrors()
        suite.expect(service.mirrors[2]?.model.shown == false,
                     "a capsule never covers menus it cannot measure on another display")
        service.displayID = 2
        service.syncMirrors()
        suite.expect(service.mirrors[1]?.model.shown == true && service.mirrors[1]?.model.geometry.compactSideRoom == nil,
                     "a copy on a camera keeps the camera covered without wings")
        service.coversMenus = true
        NSScreen.screensHaveSeparateSpaces = false

        // The companion rests in each copy too, beside that display's camera.
        service.displayID = 2
        service.compactActivity = nil
        service.mascotVisible = true
        service.syncMirrors()
        suite.expect(service.mirrors[1]?.model.size == service.mirrors[1]?.model.geometry.collapsed
                     && (service.mirrors[1]?.model.size.width ?? 0) > builtInBase.cameraWidth,
                     "a copy beside a camera opens its wings for the resting companion")
        service.mascotVisible = false
        service.syncMirrors()

        // A click on a copy brings the island there, open, closing it where it was.
        service.displayID = 2
        service.expanded = true
        service.syncMirrors()
        service.mirrors[1]?.host.activate?()
        suite.expect(service.collapses == 1 && service.moves == [1] && service.displayID == 1 && service.opened == 1,
                     "clicking a copy closes the island, moves it to that display and opens it there")
        let opened = service.opened
        service.canFollowPointer = false
        service.mirrors[2]?.host.activate?()
        service.canFollowPointer = true
        suite.expect(service.opened == opened, "a notice or a drag keeps the island where it is")
        service.compactActivity = .calendar
        service.mirrors[2]?.host.activate?()
        service.compactActivity = nil
        suite.expect(service.countdownOpenings == 1 && service.opened == opened,
                     "clicking a copy of an event countdown opens on its event")

        // Unplugging a display closes its copy; leaving the choice closes them all.
        service.displayID = 1
        service.syncMirrors()
        let unplugged = service.mirrors[2]?.host
        NSScreen.screens = [builtIn]
        service.syncMirrors()
        suite.expect(service.mirrors[2] == nil && unplugged?.closes == 1, "a display that goes away takes its copy along")
        NSScreen.screens = [builtIn, external]
        service.syncMirrors()
        let hosts = service.mirrors.values.map(\.host)
        service.showsOnAllDisplays = false
        service.syncMirrors()
        suite.expect(service.mirrors.isEmpty && !hosts.isEmpty && hosts.allSatisfy { $0.closes == 1 },
                     "choosing one display closes every copy")
        service.showsOnAllDisplays = true
        service.showsInCaptures = false
        service.syncMirrors()
        suite.expect(!service.mirrors.isEmpty && service.mirrors.values.allSatisfy { $0.host.panel.sharingType == .none },
                     "copies stay out of screenshots with the island")
        service.running = false
        service.syncMirrors()
        suite.expect(service.mirrors.isEmpty, "a stopped island leaves no copies")

        let model = NotchMirrorModel(geometry: external2, size: CGSize(width: 100, height: 24))
        suite.expect(!model.update(geometry: external2, strip: external2, size: CGSize(width: 100, height: 24), activity: nil)
                     && model.update(geometry: external2, strip: external2, size: CGSize(width: 120, height: 24), activity: nil)
                     && model.update(geometry: external2, strip: external2, size: CGSize(width: 120, height: 24), activity: .music)
                     && model.activity == .music,
                     "a copy is only redrawn when what it shows changes")
    }

    /// A pending arrival may retain an eligible copy, but cannot overrule the
    /// same visibility policy that ordinarily removes that display's island.
    private static func arrivalVisibilityContracts(_ suite: TestSuite) {
        let separateSpaces = NSScreen.screensHaveSeparateSpaces
        defer {
            NSScreen.screensHaveSeparateSpaces = separateSpaces
            SpaceWindowBridge.fullscreen = []
            NotchAppFullscreen.covered = []
        }
        func arriving(activity: NotchCompactActivity? = nil) -> Service {
            let service = Service()
            service.compactActivity = activity
            service.syncMirrors()
            service.displayID = 2
            service.mirrorHeldForArrival = 2
            return service
        }

        let allowed = arriving()
        let allowedCopy = allowed.mirrors[2]!
        allowed.syncMirrors()
        suite.expect(allowedCopy.model.shown && allowedCopy.host.panel.isVisible
                     && allowedCopy.host.presented.count == 1 && allowedCopy.host.hides == 0,
                     "holding an eligible arrival leaves its already drawn copy untouched")

        for appFullscreen in [false, true] {
            let fullscreen = arriving()
            let copy = fullscreen.mirrors[2]!
            fullscreen.hidesInFullscreen = true
            if appFullscreen { NotchAppFullscreen.covered = [2] }
            else { SpaceWindowBridge.fullscreen = [2] }
            fullscreen.updateFullscreenDisplays()
            fullscreen.syncMirrors()
            suite.expect(fullscreen.fullscreenDisplays.contains(2) && !copy.model.shown
                         && !copy.host.panel.isVisible && copy.host.hides == 1,
                         "a held arrival still hides for \(appFullscreen ? "an application's" : "a Space's") full screen")
            SpaceWindowBridge.fullscreen = []
            NotchAppFullscreen.covered = []
        }

        let hidden = arriving()
        let hiddenCopy = hidden.mirrors[2]!
        hidden.hidesUntilHover = true
        hidden.syncMirrors()
        suite.expect(!hiddenCopy.model.shown && !hiddenCopy.host.panel.isVisible && hiddenCopy.host.hides == 1,
                     "hide-until-hover removes a held copy when it has no activity to keep visible")

        let active = arriving(activity: .music)
        let activeCopy = active.mirrors[2]!
        active.hidesUntilHover = true
        active.hiddenShowsActivity = true
        active.syncMirrors()
        suite.expect(activeCopy.model.shown && activeCopy.host.panel.isVisible && activeCopy.host.hides == 0,
                     "hide-until-hover still permits a held copy of an activity configured to remain visible")
        active.compactActivity = nil
        active.syncMirrors()
        suite.expect(!activeCopy.model.shown && activeCopy.host.hides == 1,
                     "an activity ending removes its held copy even before the live island arrives")

        let noRoom = arriving()
        let coveredMenus = noRoom.mirrors[2]!
        NSScreen.screensHaveSeparateSpaces = true
        noRoom.coversMenus = false
        noRoom.syncMirrors()
        suite.expect(!coveredMenus.model.shown && !coveredMenus.host.panel.isVisible && coveredMenus.host.hides == 1,
                     "a held capsule gives way when its display gains menus the island cannot cover")

        let camera = Service()
        camera.displayID = 2
        camera.coversMenus = false
        camera.syncMirrors()
        let cameraCopy = camera.mirrors[1]!
        camera.displayID = 1
        camera.mirrorHeldForArrival = 1
        camera.syncMirrors()
        suite.expect(cameraCopy.model.shown && cameraCopy.model.geometry.compactSideRoom == nil
                     && cameraCopy.host.hides == 0,
                     "a held physical camera remains covered even when the menus leave no room for wings")
    }
}
