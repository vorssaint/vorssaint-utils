// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The notification and permission lifecycle bodies come from production;
/// clock, scheduling, permission and menu reads are controlled boundaries.
enum NotchScreenRefreshContract {
    struct Deadline {
        let seconds: Double
        static func now() -> Self { Self(seconds: DispatchQueue.main.now) }
        static func + (left: Self, right: Double) -> Self { Self(seconds: left.seconds + right) }
    }
    final class Scheduler {
        var now: Double = 0
        var jobs: [(Deadline, DispatchWorkItem)] = []
        var pending: Int { jobs.filter { !$0.1.isCancelled }.count }
        func async(execute work: DispatchWorkItem) { jobs.append((.now(), work)) }
        func asyncAfter(deadline: Deadline, execute work: DispatchWorkItem) { jobs.append((deadline, work)) }
        func advance(_ seconds: Double) {
            now += seconds
            while let index = jobs.firstIndex(where: { $0.0.seconds <= now }) {
                let work = jobs.remove(at: index).1
                if !work.isCancelled { work.perform() }
            }
        }
    }
    enum DispatchQueue { static var main = Scheduler() }
    final class Timer {
        var tolerance: Double = 0
        var invalidated = false
        init(timeInterval: Double, repeats: Bool, block: @escaping (Timer) -> Void) {}
        func invalidate() { invalidated = true }
    }
    enum RunLoop {
        static let main = Loop()
        final class Loop {
            enum Mode { case common }
            func add(_ timer: Timer, forMode: Mode) {}
        }
    }
    struct RunningApplication { let bundleIdentifier: String? }
    enum NSWorkspace {
        static let shared = Workspace()
        final class Workspace { var frontmostApplication: RunningApplication? }
    }
    enum Bundle {
        static let main = RunningApplication(bundleIdentifier: "com.vorssaint.tests.notch")
    }
    enum ClipboardHistoryService {
        static let shared = History()
        final class History {
            var remembered = 0
            func rememberPasteTarget() { remembered += 1 }
        }
    }
    final class Panel {
        var resignations = 0
        func resignKey() { resignations += 1 }
    }
    enum NSEvent {
        static var mouseLocation = CGPoint.zero
        struct EventTypeMask: OptionSet {
            let rawValue: UInt64
            static let mouseMoved = EventTypeMask(rawValue: 1 << 5)
            static let leftMouseDragged = EventTypeMask(rawValue: 1 << 6)
        }
        final class Event {}
        static var globalHandlers: [(Event) -> Void] = []
        static var localHandlers: [(Event) -> Event?] = []
        static var removed = 0
        static func addGlobalMonitorForEvents(matching mask: EventTypeMask, handler: @escaping (Event) -> Void) -> Any? {
            globalHandlers.append(handler)
            return globalHandlers.count
        }
        static func addLocalMonitorForEvents(matching mask: EventTypeMask, handler: @escaping (Event) -> Event?) -> Any? {
            localHandlers.append(handler)
            return -localHandlers.count
        }
        static func removeMonitor(_ monitor: Any) { removed += 1 }
        static func reset() { globalHandlers = []; localHandlers = []; removed = 0 }
    }
    /// Displays side by side; the one the pointer is on is found by frame.
    final class NSScreen {
        static var screens: [NSScreen] = []
        static var withMouse: NSScreen? { screens.first { $0.frame.contains(NSEvent.mouseLocation) } }
        let notchDisplayID: CGDirectDisplayID
        let frame: CGRect
        init(_ id: CGDirectDisplayID, _ frame: CGRect) { notchDisplayID = id; self.frame = frame }
    }
    final class Host {
        var rect = CGRect.zero
        var isConcealedForMissionControl = false
        var settledCalls = 0
        var isVisible = false
        var relocationPending = false
        var hidesOnArrival = false
        var orderOuts = 0, orderFronts = 0, hides = 0
        var didOrderOut: (() -> Void)?
        var didOrderFront: (() -> Void)?
        func containsHover(_ point: CGPoint) -> Bool { rect.contains(point) }
        func whenSettled(_ body: @escaping () -> Void) { settledCalls += 1; body() }
        func canRelocateOnScreen() -> Bool { isVisible || relocationPending }
        func orderOutForRelocation() -> Bool {
            guard canRelocateOnScreen() else { return false }
            orderOuts += 1
            relocationPending = true
            isVisible = false
            didOrderOut?()
            return true
        }
        func orderFrontForRelocation() {
            guard relocationPending else { return }
            guard !hidesOnArrival else { cancelRelocation(); return }
            relocationPending = false
            isVisible = true
            orderFronts += 1
            didOrderFront?()
        }
        func hide(animated: Bool) {
            hides += 1
            hidesOnArrival = true
            isVisible = false
        }
        func cancelRelocation() { relocationPending = false }
    }
    class State {
        var hiddenInFullscreen = false
        func fullscreenEnvironmentDidChange() {}
        var running = true
        var suspended = false
        var expanded = false
        var hiddenUntilHover = false
        /// Hidden until hover and set to show activity, as Settings has it.
        var hiddenShowsActivity = false
        var captureControls: Bool?
        var idleContent = NotchIdleContent.music
        var compactActivity: Bool?
        var mascotWantsRoom = false
        var accessibilityGranted = true
        var coversMenus = false
        var menuSpaceTimer: Timer?
        var menuSpaceGeneration = 0
        var screenRefreshWork: DispatchWorkItem?
        var preferenceSyncWork: DispatchWorkItem?
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                     safeAreaTop: 32, cameraWidth: 210, compactSideRoom: 64)
        var panel: Panel? = Panel()
        var windowHost: Host? = Host()
        var modules: [NotchModule] = [.controls]
        var pinned = false
        var keepsWorkingSurface = false
        var openedByHover = false
        var clickedSinceOpening = false
        var preferenceSyncs = 0
        var reads = 0
        var appliedRooms: [CGFloat?] = []
        var presentations = 0
        var presentedDisplays: [CGDirectDisplayID?] = []
        var presentationHook: (() -> Void)?
        var collapses = 0
        func syncWithPreferences() { preferenceSyncs += 1 }
        func readMenuSpace() { reads += 1 }
        func applyMenuSpace(_ room: CGFloat?) {
            appliedRooms.append(room)
            geometry.compactSideRoom = room
        }
        func refreshPresentation(animated: Bool) {
            presentations += 1
            presentedDisplays.append(displayID)
            presentationHook?()
        }
        func collapse() { collapses += 1 }
        var displayHasMenuBar = true
        static let pointerFollowDelay: TimeInterval = 0.2
        var followsPointer = false
        var pointerMonitors: [Any] = []
        var pointerFollowWork: DispatchWorkItem?
        var displayID: CGDirectDisplayID?
        var peeking = false
        var notice: Bool?
        var heldDrag = false
        var heldMusic: Bool?
        var choosingFileDropDestination = false
        var screenUpdates = 0
        var consumerSyncs = 0
        var mirrorHeldForArrival: CGDirectDisplayID?
        var relocationTicket = 0
        var mirrorSyncs = 0, edgeClickSyncs = 0
        var waveHolds: [CGDirectDisplayID] = []
        var waveMatches = 0, waveKeeps = 0, waveReleases = 0
        var screenUpdateHook: (() -> Void)?
        var mirrorSyncHook: (() -> Void)?
        var waveMatchHook: (() -> Void)?
        func syncMirrors() { mirrorSyncs += 1; mirrorSyncHook?() }
        func syncScreenEdgeClicks() { edgeClickSyncs += 1 }
        func holdMusicWave(on id: CGDirectDisplayID) { waveHolds.append(id) }
        func matchMusicWave() { waveMatches += 1; waveMatchHook?() }
        func keepMusicWave() { waveKeeps += 1 }
        func releaseMusicWave() { waveReleases += 1 }
        func NSMouseInRect(_ point: CGPoint, _ rect: CGRect, _ flipped: Bool) -> Bool { rect.contains(point) }
        /// The island takes the display its identifier names, as updateScreen does.
        func updateScreen() {
            screenUpdates += 1
            screenUpdateHook?()
            if let screen = NSScreen.screens.first(where: { $0.notchDisplayID == displayID }) {
                geometry = NotchGeometry(screen: screen.frame, safeAreaTop: 0, cameraWidth: 0)
            }
        }
        func syncVisibleConsumers() { consumerSyncs += 1 }
    }

    static func run(_ suite: TestSuite) {
        DispatchQueue.main = Scheduler()
        NSWorkspace.shared.frontmostApplication = nil
        ClipboardHistoryService.shared.remembered = 0
        defer {
            NSWorkspace.shared.frontmostApplication = nil
            ClipboardHistoryService.shared.remembered = 0
        }
        let service = Service()
        let preferences = Service()
        for _ in 0..<100 { preferences.schedulePreferenceSync() }
        suite.expect(DispatchQueue.main.pending == 1 && preferences.preferenceSyncs == 0,
                     "a preference burst defers one island sync until drawing has finished")
        DispatchQueue.main.advance(0)
        suite.expect(preferences.preferenceSyncs == 1 && preferences.preferenceSyncWork == nil,
                     "the deferred sync consumes the entire preference burst once")
        preferences.schedulePreferenceSync()
        DispatchQueue.main.advance(0)
        suite.expect(preferences.preferenceSyncs == 2, "later preference changes still synchronize the island")
        preferences.schedulePreferenceSync()
        preferences.running = false
        DispatchQueue.main.advance(0)
        preferences.schedulePreferenceSync()
        suite.expect(preferences.preferenceSyncs == 2 && DispatchQueue.main.pending == 0,
                     "pending and later preference notifications cannot restart a stopped island")
        preferences.running = true
        preferences.suspended = true
        preferences.schedulePreferenceSync()
        DispatchQueue.main.advance(0)
        suite.expect(preferences.preferenceSyncs == 3,
                     "suspended islands still apply preference changes that stop disabled services")
        let initialSize = service.geometry.compactMusicGeometry.compactActivitySize
        var pendingPeak = 0
        var geometryChanged = false
        for _ in 0..<120 {
            service.screenParametersDidChange()
            pendingPeak = max(pendingPeak, DispatchQueue.main.pending)
            DispatchQueue.main.advance(1.0 / 60)
            geometryChanged = geometryChanged || service.geometry.compactMusicGeometry.compactActivitySize != initialSize
        }
        suite.expect(service.preferenceSyncs == 0 && pendingPeak == 1,
               "a two-second screen-parameter burst retains one pending refresh instead of resynchronizing each event")
        suite.expect(!geometryChanged && !service.geometry.compactMusicGeometry.compactActivityUsesFooter,
               "brightness-only notifications preserve measured music wings and never move music below the camera")
        DispatchQueue.main.advance(0.11)
        suite.expect(service.preferenceSyncs == 1 && service.reads == 1 && service.screenRefreshWork == nil,
               "the settled screen configuration triggers one synchronization and menu measurement")
        suite.expect(service.geometry.compactSideRoom == 64,
               "refreshing menu space retains the last valid measurement until its replacement arrives")
        service.screenParametersDidChange()
        DispatchQueue.main.advance(0.11)
        suite.expect(service.preferenceSyncs == 2, "a later independent screen change is still processed")

        service.screenParametersDidChange()
        service.suspended = true
        DispatchQueue.main.advance(0.11)
        suite.expect(service.preferenceSyncs == 2 && service.screenRefreshWork == nil,
               "a queued display update cannot resynchronize the island after suspension")
        service.suspended = false
        service.screenParametersDidChange()
        service.running = false
        DispatchQueue.main.advance(0.11)
        service.screenParametersDidChange()
        suite.expect(service.preferenceSyncs == 2 && DispatchQueue.main.pending == 0,
               "stopping the island makes queued and later screen notifications inert")

        let fullscreen = Service()
        fullscreen.syncMenuSpaceMonitoring()
        let fullscreenTimer = fullscreen.menuSpaceTimer
        fullscreen.hiddenInFullscreen = true
        fullscreen.syncMenuSpaceMonitoring()
        suite.expect(fullscreen.menuSpaceTimer == nil && fullscreenTimer?.invalidated == true,
                     "fullscreen hiding stops menu polling")
        fullscreen.hiddenInFullscreen = false
        fullscreen.syncMenuSpaceMonitoring()
        suite.expect(fullscreen.menuSpaceTimer != nil, "leaving fullscreen restores menu monitoring")

        // A bare camera measures nothing, unless the companion wants its wings.
        let companion = Service()
        companion.idleContent = .none
        companion.syncMenuSpaceMonitoring()
        suite.expect(companion.menuSpaceTimer == nil, "a bare notch with nothing to show reads no menus")
        companion.mascotWantsRoom = true
        companion.syncMenuSpaceMonitoring()
        suite.expect(companion.menuSpaceTimer != nil,
                     "the companion measures the menus, so it rests beside the camera only where its wings fit")
        companion.hiddenInFullscreen = true
        companion.syncMenuSpaceMonitoring()

        let virtual = Service()
        virtual.geometry.compactSideRoom = nil
        virtual.accessibilityGranted = false
        virtual.syncMenuSpaceMonitoring()
        suite.expect(virtual.menuSpaceTimer == nil && virtual.reads == 0,
               "missing Accessibility does not leave a timer polling unavailable menu geometry")
        virtual.accessibilityGranted = true
        virtual.syncMenuSpaceMonitoring()
        var timer = virtual.menuSpaceTimer
        suite.expect(timer != nil && virtual.reads == 1,
               "granting Accessibility starts the existing menu reader without restarting the app")
        virtual.hiddenUntilHover = true
        virtual.syncMenuSpaceMonitoring()
        suite.expect(virtual.menuSpaceTimer == nil && timer?.invalidated == true,
               "hidden mode stops menu polling while no window occupies the menu bar")
        virtual.hiddenUntilHover = false
        virtual.syncMenuSpaceMonitoring()
        timer = virtual.menuSpaceTimer
        virtual.geometry.compactSideRoom = 64
        virtual.accessibilityGranted = false
        virtual.syncMenuSpaceMonitoring()
        suite.expect(virtual.menuSpaceTimer == nil && timer?.invalidated == true
               && virtual.geometry.compactSideRoom == nil && virtual.presentations == 1,
               "revoking Accessibility stops polling and withdraws stale menu-space geometry")
        virtual.accessibilityGranted = true
        virtual.running = false
        virtual.syncMenuSpaceMonitoring()
        suite.expect(virtual.menuSpaceTimer == nil && virtual.reads == 2,
               "permission alone cannot start menu polling for a disabled island")

        // Set to show activity, a hidden island keeps measuring, so an
        // activity bringing it into view finds the room it needs.
        let waiting = Service()
        waiting.hiddenUntilHover = true
        waiting.hiddenShowsActivity = true
        waiting.syncMenuSpaceMonitoring()
        suite.expect(waiting.menuSpaceTimer != nil && waiting.reads == 1,
               "a hidden island set to show activity keeps measuring the menus for an activity to come")
        waiting.hiddenShowsActivity = false
        waiting.syncMenuSpaceMonitoring()
        suite.expect(waiting.menuSpaceTimer == nil, "a hidden island not set to show activity stops measuring")

        let simulated = Service()
        simulated.geometry = NotchGeometry(screen: simulated.geometry.screen, safeAreaTop: 0, cameraWidth: 0)
        simulated.accessibilityGranted = false
        simulated.syncMenuSpaceMonitoring()
        suite.expect(simulated.menuSpaceTimer == nil && simulated.reads == 0,
               "a simulated camera does not poll menus without Accessibility")
        simulated.accessibilityGranted = true
        for _ in 0..<100 { simulated.syncMenuSpaceMonitoring() }
        let simulatedTimer = simulated.menuSpaceTimer
        suite.expect(simulatedTimer != nil && simulated.reads == 1,
               "available menu access starts one reader for a simulated camera's compact indicators")
        simulated.geometry.compactSideRoom = 64
        simulated.accessibilityGranted = false
        simulated.syncMenuSpaceMonitoring()
        suite.expect(simulated.menuSpaceTimer == nil && simulatedTimer?.invalidated == true
               && simulated.geometry.compactSideRoom == nil,
               "revoking access removes measured simulated wings and stops their reader")
        simulated.accessibilityGranted = true
        simulated.idleContent = .none
        simulated.syncMenuSpaceMonitoring()
        suite.expect(simulated.menuSpaceTimer != nil && simulated.reads == 2,
               "a bare simulated cutout still checks that its center does not cover menus")
        simulated.compactActivity = true
        simulated.syncMenuSpaceMonitoring()
        suite.expect(simulated.menuSpaceTimer != nil && simulated.reads == 2,
               "starting compact activity reuses the simulated notch's existing menu reader")

        simulated.geometry.compactSideRoom = 64
        let beforeChange = simulated.menuSpaceGeneration
        let beforePresentation = simulated.presentations
        let beforeReads = simulated.reads
        NSWorkspace.shared.frontmostApplication = RunningApplication(bundleIdentifier: "com.example.terminal")
        simulated.applicationDidActivate()
        suite.expect(simulated.geometry.compactSideRoom == 64 && simulated.menuSpaceGeneration > beforeChange
               && simulated.presentations == beforePresentation && simulated.reads == beforeReads + 1,
               "switching apps keeps the simulated cutout on screen and starts the read that decides whether it stays")
        suite.expect(simulated.panel?.resignations == 1 && simulated.collapses == 0,
               "another app taking focus releases the island's key status without collapsing a closed island")
        simulated.syncMenuSpaceMonitoring()
        suite.expect(simulated.geometry.compactSideRoom == 64 && simulated.reads == beforeReads + 1,
               "a preference sync during the pending read neither withdraws the cutout nor starts another read")
        simulated.expanded = true
        simulated.modules = [.controls, .clipboard]
        simulated.applicationDidActivate()
        suite.expect(simulated.collapses == 1 && ClipboardHistoryService.shared.remembered == 1
               && simulated.reads == beforeReads + 2,
               "an open island still remembers the paste target and collapses when another app activates")
        NSWorkspace.shared.frontmostApplication = Bundle.main
        simulated.applicationDidActivate()
        suite.expect(simulated.collapses == 1 && simulated.panel?.resignations == 2 && simulated.reads == beforeReads + 3,
               "this app activating re-reads the menus without giving up its own island")
        simulated.suspended = true
        simulated.applicationDidActivate()
        suite.expect(simulated.reads == beforeReads + 3, "a suspended island ignores activations")
        simulated.suspended = false

        let hovered = Service()
        hovered.expanded = true
        hovered.openedByHover = true
        hovered.windowHost?.rect = hovered.geometry.frame(for: hovered.geometry.expanded)
        let onIsland = CGPoint(x: hovered.geometry.screen.midX, y: hovered.geometry.screen.maxY - 1)
        NSEvent.mouseLocation = onIsland
        NSWorkspace.shared.frontmostApplication = RunningApplication(bundleIdentifier: "com.example.editor")
        hovered.applicationDidActivate()
        suite.expect(hovered.collapses == 0 && hovered.panel?.resignations == 1,
               "an island hover opened stays under the pointer when reaching it makes the app beneath active, "
               + "such as a full-screen app on a display without focus")
        hovered.clickedSinceOpening = true
        hovered.applicationDidActivate()
        suite.expect(hovered.collapses == 1,
               "after a click inside, which may be what opened the other app, the island still closes as it comes forward")
        hovered.clickedSinceOpening = false
        NSEvent.mouseLocation = CGPoint(x: hovered.geometry.screen.minX, y: hovered.geometry.screen.minY)
        hovered.applicationDidActivate()
        suite.expect(hovered.collapses == 2, "an island hover opened closes when another app activates away from the pointer")
        hovered.openedByHover = false
        NSEvent.mouseLocation = onIsland
        hovered.applicationDidActivate()
        suite.expect(hovered.collapses == 3,
               "an island opened by a click or shortcut still closes when another app activates under the pointer")

        let covering = Service()
        covering.geometry.compactSideRoom = nil
        covering.accessibilityGranted = false
        covering.coversMenus = true
        covering.syncMenuSpaceMonitoring()
        let emptyBar = NotchMenuBarLayout.sideRoom(screen: covering.geometry.screen, cameraWidth: covering.geometry.cameraWidth,
                                                   barHeight: covering.geometry.menuBarHeight, occupied: [])
        suite.expect(covering.menuSpaceTimer == nil && covering.reads == 0 && covering.appliedRooms == [emptyBar]
               && covering.geometry.compactTimerGeometry(showsDownloads: false).compactActivityWingWidth > 0,
               "an island allowed to cover the menus keeps an empty bar's room, so its timer has wings, "
               + "without Accessibility or a menu reader")
        covering.accessibilityGranted = true
        covering.syncMenuSpaceMonitoring()
        suite.expect(covering.menuSpaceTimer == nil && covering.reads == 0 && covering.geometry.compactSideRoom == emptyBar,
               "granting Accessibility starts no reader for menus the island may cover")
        covering.running = false
        let applied = covering.appliedRooms.count
        covering.syncMenuSpaceMonitoring()
        suite.expect(covering.appliedRooms.count == applied, "a stopped island applies no room")
        covering.running = true
        covering.coversMenus = false
        covering.syncMenuSpaceMonitoring()
        suite.expect(covering.menuSpaceTimer != nil && covering.reads == 1,
               "giving way to the menus again resumes the existing reader")

        let idleSimulated = Service()
        idleSimulated.geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                               safeAreaTop: 0, cameraWidth: 0)
        idleSimulated.idleContent = .none
        idleSimulated.accessibilityGranted = false
        idleSimulated.coversMenus = true
        idleSimulated.syncMenuSpaceMonitoring()
        let idleEmptyBar = NotchMenuBarLayout.sideRoom(screen: idleSimulated.geometry.screen,
                                                      cameraWidth: idleSimulated.geometry.cameraWidth,
                                                      barHeight: idleSimulated.geometry.menuBarHeight, occupied: [])
        suite.expect(idleSimulated.menuSpaceTimer == nil && idleSimulated.appliedRooms == [idleEmptyBar]
               && idleSimulated.geometry.compactSideRoom == idleEmptyBar,
               "an external display keeps the idle island visible when menu coverage is enabled")
        idleSimulated.compactActivity = true
        idleSimulated.syncMenuSpaceMonitoring()
        suite.expect(idleSimulated.geometry.compactSideRoom.map { $0 > 0 } == true,
               "compact activity on a simulated cutout covers the menus")

        let roomsBeforeFocusChange = idleSimulated.appliedRooms
        NSWorkspace.shared.frontmostApplication = Bundle.main
        idleSimulated.applicationDidActivate()
        NSWorkspace.shared.frontmostApplication = RunningApplication(bundleIdentifier: "com.example.editor")
        idleSimulated.applicationDidActivate()
        suite.expect(idleSimulated.menuSpaceTimer == nil && idleSimulated.appliedRooms == roomsBeforeFocusChange
               && idleSimulated.geometry.compactSideRoom == idleEmptyBar,
               "the external island remains visible when focus moves between Settings and another app")
        let readsBeforePolicyChange = idleSimulated.reads
        idleSimulated.accessibilityGranted = true
        idleSimulated.coversMenus = false
        idleSimulated.syncMenuSpaceMonitoring()
        suite.expect(idleSimulated.menuSpaceTimer != nil && idleSimulated.reads == readsBeforePolicyChange + 1,
               "turning off menu coverage restores the measured-space policy")

        let physical = Service()
        physical.idleContent = .none
        physical.syncMenuSpaceMonitoring()
        suite.expect(physical.menuSpaceTimer == nil && physical.reads == 0,
               "an empty physical camera does not need a menu reader")
        NSWorkspace.shared.frontmostApplication = RunningApplication(bundleIdentifier: "com.example.terminal")
        physical.applicationDidActivate()
        suite.expect(physical.geometry.compactSideRoom == 64 && physical.presentations == 0,
               "the physical camera retains its existing presentation during app changes")

        let noMenuBar = Service()
        noMenuBar.geometry.compactSideRoom = nil
        noMenuBar.displayHasMenuBar = false
        noMenuBar.syncMenuSpaceMonitoring()
        suite.expect(noMenuBar.menuSpaceTimer == nil && noMenuBar.reads == 0 && noMenuBar.geometry.compactSideRoom != nil,
               "a display without a menu bar keeps the island at rest with nothing to measure or cover")
        pointerFollowContracts(suite)
        relocationContracts(suite)

        let source = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Notch/NotchService.swift",
                                  encoding: .utf8)) ?? ""
        let code = source.components(separatedBy: "\n")
            .map { line in line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? line }
            .joined(separator: "\n")
        guard let start = code.range(of: "func readMenuSpace()"),
              let end = code.range(of: "func applyMenuSpace(", range: start.upperBound..<code.endIndex) else {
            suite.expect(false, "the menu reader and the method that applies its result are still found")
            return
        }
        let reader = code[start.lowerBound..<end.lowerBound]
        suite.expect(reader.contains("menuBarOwningApplication") && !reader.contains("frontmostApplication"),
               "the menu read measures the application whose menus are on the bar: an accessory app with focus "
               + "leaves the previous app's menus displayed, and its own menu geometry is never laid out")
    }

    /// Following the pointer runs the shipped monitors, wait and move against
    /// two displays side by side; only the displays and the clock are doubles.
    private static func pointerFollowContracts(_ suite: TestSuite) {
        DispatchQueue.main = Scheduler()
        NSEvent.reset()
        defer { NSEvent.reset(); NSScreen.screens = []; NSEvent.mouseLocation = .zero }
        let builtIn = NSScreen(1, CGRect(x: 0, y: 0, width: 1470, height: 956))
        let external = NSScreen(2, CGRect(x: 1470, y: 0, width: 1920, height: 1080))
        func island() -> Service {
            let service = Service()
            service.geometry = NotchGeometry(screen: builtIn.frame, safeAreaTop: 32, cameraWidth: 179)
            service.displayID = 1
            return service
        }
        NSScreen.screens = [builtIn]
        let single = island()
        single.followsPointer = true
        single.syncPointerFollowing()
        suite.expect(single.pointerMonitors.isEmpty, "one display gives the pointer nothing to follow, so nothing is watched")
        NSScreen.screens = [builtIn, external]
        let off = island()
        off.syncPointerFollowing()
        suite.expect(off.pointerMonitors.isEmpty, "the other display choices watch no pointer movement")

        let service = island()
        service.followsPointer = true
        service.syncPointerFollowing()
        service.syncPointerFollowing()
        suite.expect(service.pointerMonitors.count == 2 && NSEvent.globalHandlers.count == 1 && NSEvent.localHandlers.count == 1,
                     "following the pointer watches movement once, in other apps and in its own windows")
        NSEvent.mouseLocation = CGPoint(x: 700, y: 500)
        NSEvent.globalHandlers.first?(NSEvent.Event())
        suite.expect(DispatchQueue.main.pending == 0, "moving on the island's own display schedules nothing")
        NSEvent.mouseLocation = CGPoint(x: 2000, y: 500)
        for _ in 0..<5 { NSEvent.globalHandlers.first?(NSEvent.Event()) }
        suite.expect(DispatchQueue.main.pending == 1, "a burst of moves on another display waits once")
        DispatchQueue.main.advance(0.1)
        NSEvent.mouseLocation = CGPoint(x: 700, y: 500)
        _ = NSEvent.localHandlers.first?(NSEvent.Event())
        DispatchQueue.main.advance(0.2)
        suite.expect(service.displayID == 1 && service.screenUpdates == 0,
                     "a pointer back on the island's display before the wait ends leaves the island where it is")
        NSEvent.mouseLocation = CGPoint(x: 2000, y: 500)
        NSEvent.globalHandlers.first?(NSEvent.Event())
        DispatchQueue.main.advance(0.19)
        suite.expect(service.displayID == 1, "the island waits a moment before it follows")
        DispatchQueue.main.advance(0.02)
        suite.expect(service.displayID == 2 && service.screenUpdates == 1 && service.geometry.screen == external.frame
                     && service.presentations == 1 && service.consumerSyncs == 1,
                     "a pointer resting on another display brings the closed island there")
        NSEvent.globalHandlers.first?(NSEvent.Event())
        suite.expect(DispatchQueue.main.pending == 0, "on its new display the island schedules nothing more")

        let blockers: [(String, (Service) -> Void)] = [
            ("open", { $0.expanded = true }), ("peeking", { $0.peeking = true }), ("showing a notice", { $0.notice = true }),
            ("showing capture controls", { $0.captureControls = true }), ("holding a drag", { $0.heldDrag = true }),
            ("choosing where a file drops", { $0.choosingFileDropDestination = true }),
            ("keeping a working surface", { $0.keepsWorkingSurface = true }),
            ("holding a song for its notice", { $0.heldMusic = true }),
        ]
        for (name, block) in blockers {
            let held = island()
            held.followsPointer = true
            block(held)
            NSEvent.mouseLocation = CGPoint(x: 2000, y: 500)
            held.schedulePointerFollow()
            DispatchQueue.main.advance(1)
            suite.expect(held.displayID == 1 && held.screenUpdates == 0, "an island \(name) stays on its display")
        }
        let concealed = island()
        concealed.followsPointer = true
        concealed.windowHost?.isConcealedForMissionControl = true
        concealed.schedulePointerFollow()
        DispatchQueue.main.advance(1)
        suite.expect(concealed.displayID == 1, "the island waits for Mission Control to end before it moves")
        concealed.windowHost?.isConcealedForMissionControl = false
        concealed.schedulePointerFollow()
        DispatchQueue.main.advance(1)
        suite.expect(concealed.displayID == 2, "once Mission Control ends, the island follows the pointer")

        let stopping = island()
        stopping.followsPointer = true
        stopping.syncPointerFollowing()
        stopping.schedulePointerFollow()
        let removedBefore = NSEvent.removed
        stopping.suspended = true
        stopping.syncPointerFollowing()
        DispatchQueue.main.advance(1)
        suite.expect(stopping.pointerMonitors.isEmpty && NSEvent.removed == removedBefore + 2
                     && stopping.pointerFollowWork == nil && stopping.displayID == 1,
                     "suspending the island removes its pointer monitors and drops a pending move")
    }

    /// Executes the shipped move and cancellation bodies. Display selection,
    /// presentation and native window operations remain controlled boundaries;
    /// these checks cover callback ownership, not AppKit drawing or interaction.
    private static func relocationContracts(_ suite: TestSuite) {
        DispatchQueue.main = Scheduler()
        defer { DispatchQueue.main = Scheduler(); NSScreen.screens = [] }
        let first = NSScreen(1, CGRect(x: 0, y: 0, width: 1470, height: 956))
        let second = NSScreen(2, CGRect(x: 1470, y: 0, width: 1920, height: 1080))
        let third = NSScreen(3, CGRect(x: 3390, y: 0, width: 1920, height: 1080))
        NSScreen.screens = [first, second, third]
        func island(visible: Bool = true) -> Service {
            let service = Service()
            service.displayID = 1
            service.geometry = NotchGeometry(screen: first.frame, safeAreaTop: 32, cameraWidth: 179)
            service.windowHost?.isVisible = visible
            return service
        }

        let moving = island()
        let movingHost = moving.windowHost!
        var heldDuringLayout = false
        var heldDuringReveal = false
        moving.waveMatchHook = { [weak moving] in heldDuringLayout = moving?.mirrorHeldForArrival == 3 }
        movingHost.didOrderFront = { [weak moving] in heldDuringReveal = moving?.mirrorHeldForArrival == 3 }
        moving.move(to: second)
        suite.expect(!movingHost.isVisible && movingHost.relocationPending && movingHost.orderFronts == 0
                     && moving.mirrorHeldForArrival == 2 && moving.waveHolds == [1],
                     "a visible island leaves before its frame moves and keeps the destination copy until arrival")
        moving.move(to: third)
        suite.expect(moving.mirrorHeldForArrival == 3 && moving.presentedDisplays == [2, 3]
                     && movingHost.orderFronts == 0 && moving.waveHolds == [1, 2],
                     "a second move takes over an arrival that has not yet returned to the screen")
        DispatchQueue.main.advance(0)
        suite.expect(moving.displayID == 3 && moving.geometry.screen == third.frame
                     && movingHost.isVisible && !movingHost.relocationPending && movingHost.orderFronts == 1
                     && moving.mirrorHeldForArrival == nil && moving.waveMatches == 1 && moving.waveKeeps == 1
                     && moving.waveReleases == 1 && moving.mirrorSyncs == 3 && moving.edgeClickSyncs == 1,
                     "only the newest arrival reveals the island, releases its copies and restores edge clicks")
        suite.expect(heldDuringLayout && heldDuringReveal,
                     "layout keeps the arrival gate until native reveal, so a nested refresh cannot show an undrawn island")

        let hidden = island(visible: false)
        hidden.move(to: second)
        suite.expect(hidden.displayID == 2 && hidden.presentations == 1 && hidden.mirrorHeldForArrival == nil
                     && hidden.windowHost?.orderOuts == 0 && hidden.windowHost?.orderFronts == 0
                     && hidden.waveReleases == 1 && DispatchQueue.main.pending == 0,
                     "an already hidden island uses ordinary presentation without creating an arrival")

        let selected = island()
        selected.screenUpdateHook = { [weak selected] in selected?.displayID = 3 }
        selected.move(to: second)
        suite.expect(selected.mirrorHeldForArrival == 3 && selected.presentedDisplays == [3],
                     "a display choice made during screen update replaces the requested arrival destination")
        DispatchQueue.main.advance(0)
        suite.expect(selected.windowHost?.orderFronts == 1 && selected.mirrorHeldForArrival == nil
                     && selected.geometry.screen == third.frame,
                     "the island returns on the screen that was actually selected")

        let redirected = island()
        redirected.move(to: second)
        redirected.displayID = 3
        redirected.updateScreen()
        DispatchQueue.main.advance(0)
        suite.expect(redirected.presentedDisplays == [2, 3] && redirected.geometry.screen == third.frame
                     && redirected.windowHost?.orderFronts == 1 && redirected.mirrorHeldForArrival == nil,
                     "a preference change before arrival refreshes the new display instead of leaving the island out")

        let unplugged = island()
        unplugged.move(to: second)
        NSScreen.screens = [first, third]
        unplugged.screenUpdateHook = { [weak unplugged] in unplugged?.displayID = 1 }
        DispatchQueue.main.advance(0)
        suite.expect(unplugged.screenUpdates == 2 && unplugged.consumerSyncs == 2
                     && unplugged.presentedDisplays == [2, 1] && unplugged.geometry.screen == first.frame
                     && unplugged.windowHost?.orderFronts == 1 && unplugged.mirrorHeldForArrival == nil,
                     "an unplugged destination is reselected before the debounced screen notification arrives")
        NSScreen.screens = [first, second, third]

        for suspended in [false, true] {
            let unavailable = island()
            let host = unavailable.windowHost!
            unavailable.move(to: second)
            if suspended { unavailable.suspended = true } else { unavailable.running = false }
            DispatchQueue.main.advance(0)
            suite.expect(host.hides == 1 && !host.isVisible && !host.relocationPending && host.orderFronts == 0
                         && unavailable.mirrorHeldForArrival == nil && unavailable.waveMatches == 0
                         && unavailable.waveReleases == 1 && unavailable.edgeClickSyncs == 0,
                         "an arrival queued before \(suspended ? "suspension" : "stop") hides without reviving the island")
        }

        let cancelled = island()
        let oldHost = cancelled.windowHost!
        cancelled.move(to: second)
        cancelled.cancelRelocation()
        oldHost.hide(animated: false)
        oldHost.cancelRelocation()
        let replacement = Host()
        replacement.isVisible = true
        cancelled.windowHost = replacement
        DispatchQueue.main.advance(0)
        suite.expect(cancelled.mirrorHeldForArrival == nil && oldHost.orderFronts == 0 && replacement.isVisible
                     && replacement.orderFronts == 0 && cancelled.waveMatches == 0 && cancelled.waveReleases == 1,
                     "cancelling before teardown makes the old arrival inert even after presentation has restarted")

        let replaced = island()
        let replacedHost = replaced.windowHost!
        replaced.move(to: second)
        let unrelated = Host()
        unrelated.relocationPending = true
        replaced.windowHost = unrelated
        DispatchQueue.main.advance(0)
        suite.expect(replacedHost.orderFronts == 0 && unrelated.orderFronts == 0 && unrelated.relocationPending
                     && replaced.waveMatches == 0 && replaced.edgeClickSyncs == 0,
                     "host identity prevents a delayed arrival from revealing a replacement window")

        let interrupted = island()
        let interruptedHost = interrupted.windowHost!
        interruptedHost.didOrderOut = { [weak interrupted] in interrupted?.cancelRelocation() }
        interrupted.move(to: second)
        suite.expect(interrupted.screenUpdates == 0 && interrupted.presentations == 0
                     && interrupted.mirrorHeldForArrival == nil && DispatchQueue.main.pending == 0,
                     "cancellation during native order-out stops the move before it updates the screen")

        let withdrawn = island()
        let withdrawnHost = withdrawn.windowHost!
        withdrawn.screenUpdateHook = { [weak withdrawn] in
            withdrawn?.cancelRelocation()
            withdrawn?.windowHost = nil
        }
        withdrawn.move(to: second)
        suite.expect(withdrawn.presentations == 0 && withdrawn.consumerSyncs == 0
                     && withdrawnHost.orderFronts == 0 && withdrawn.mirrorHeldForArrival == nil
                     && DispatchQueue.main.pending == 0,
                     "teardown during screen selection prevents presentation or a callback for the discarded host")

        let matching = island()
        let matchingHost = matching.windowHost!
        matching.waveMatchHook = { [weak matching] in
            matching?.waveMatchHook = nil
            matching?.move(to: third)
        }
        matching.move(to: second)
        DispatchQueue.main.advance(0)
        suite.expect(matching.displayID == 3 && matching.presentedDisplays == [2, 3]
                     && matchingHost.orderFronts == 1 && matchingHost.isVisible
                     && matching.mirrorHeldForArrival == nil && matching.waveMatches == 2
                     && matching.waveKeeps == 1 && matching.waveReleases == 1 && matching.edgeClickSyncs == 1,
                     "a move reentered while copying bars owns the only reveal and release that follow")

        let mirroring = island()
        let mirroringHost = mirroring.windowHost!
        mirroring.mirrorSyncHook = { [weak mirroring] in
            guard let mirroring, mirroring.mirrorSyncs == 2 else { return }
            mirroring.mirrorSyncHook = nil
            mirroring.move(to: third)
        }
        mirroring.move(to: second)
        DispatchQueue.main.advance(0)
        suite.expect(mirroring.displayID == 3 && mirroringHost.orderFronts == 2 && mirroringHost.isVisible
                     && mirroring.mirrorHeldForArrival == nil && mirroring.waveReleases == 1
                     && mirroring.edgeClickSyncs == 1,
                     "a move reentered while retiring a copy keeps its hold until its own arrival finishes")

        let revealed = island()
        let revealedHost = revealed.windowHost!
        revealedHost.didOrderFront = { [weak revealed, weak revealedHost] in
            revealedHost?.didOrderFront = nil
            revealed?.move(to: third)
        }
        revealed.move(to: second)
        DispatchQueue.main.advance(0)
        suite.expect(revealed.displayID == 3 && revealedHost.orderFronts == 2 && revealedHost.isVisible
                     && revealed.mirrorHeldForArrival == nil && revealed.waveReleases == 1
                     && revealed.waveKeeps == 1 && revealed.edgeClickSyncs == 1,
                     "a native reveal that starts another move cannot finish the newer move's mirror handoff")

        let fullscreen = island()
        let fullscreenHost = fullscreen.windowHost!
        fullscreen.presentationHook = { [weak fullscreenHost] in fullscreenHost?.hide(animated: false) }
        fullscreen.move(to: second)
        DispatchQueue.main.advance(0)
        suite.expect(fullscreenHost.hides == 1 && fullscreenHost.orderFronts == 0 && !fullscreenHost.isVisible
                     && !fullscreenHost.relocationPending && fullscreen.mirrorHeldForArrival == nil
                     && fullscreen.waveReleases == 1,
                     "a presentation that hides on its destination stays hidden when the queued arrival runs")
    }
}
