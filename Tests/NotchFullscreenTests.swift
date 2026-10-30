// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Production Space selection and visibility transitions, with no desktop changes.
enum NotchFullscreenTests {
    enum UserDefaults {
        static let standard = Preferences()
        final class Preferences {
            var enabled = false
            var preciseVolume = false
            func bool(forKey key: String) -> Bool {
                switch key {
                case DefaultsKey.notchHideInFullscreen: return enabled
                case DefaultsKey.preciseVolumeRollerEnabled: return preciseVolume
                default: return false
                }
            }
        }
    }
    enum AppFeature {
        static let mixer = Feature()
        static let brightness = Feature()
        struct Feature { let isAvailable = true }
    }
    final class BrightnessService {
        static let shared = BrightnessService()
        var syncs = 0
        func syncWithPreferences() { syncs += 1 }
    }
    enum NotchSupport {
        enum Event { case volume }
        static func routes(_ event: Event) -> Bool { true }
    }
    enum SessionActivity {
        static let shared = Session()
        struct Session { let isActive = true }
    }
    static func AXIsProcessTrusted() -> Bool { true }
    enum NotchService { static var shared = Service() }
    class VolumeState {
        var running = false
        func start() { running = true }
        func stop() { running = false }
    }
    enum NSScreen { static var screensHaveSeparateSpaces = true }
    enum SpaceWindowBridge {
        static var value: Topology?
        static var reads = 0
        static func topology() -> Topology? { reads += 1; return value }
    }
    enum NotchAppFullscreen {
        static var covered: Set<CGDirectDisplayID> = []
        static func coveredDisplays() -> Set<CGDirectDisplayID> { covered }
    }
    class State {
        var running = true, suspended = false, hiddenInFullscreen = false
        var hoverEmphasized = false
        var panel: Bool? = true
        var windowHost: Host? = Host()
        struct Host { var isConcealedForMissionControl = false }
        var screenUpdate: (() -> Void)?
        var heldDrag = true, dragPlaceholder = true, noticeExpanded = true
        var hoverWork: DispatchWorkItem?, noticeWork: DispatchWorkItem?
        var notice: Bool? = true
        var collapses = 0, cancellations = 0, screenUpdates = 0, consumerSyncs = 0, refreshes = 0, departures = 0
        var hiddenByFullscreenSpace = false, revealingFromAppFullscreen = false
        var refreshAnimations: [Bool] = [], refreshReveals: [Bool] = []
        func cancelCaptureControls() { cancellations += 1 }
        func endDeparture() { departures += 1 }
        func collapse() { collapses += 1 }
        func updateScreen() { screenUpdates += 1; screenUpdate?() }
        func syncVisibleConsumers() { consumerSyncs += 1 }
        func refreshPresentation(animated: Bool) {
            refreshes += 1
            refreshAnimations.append(animated)
            refreshReveals.append(revealingFromAppFullscreen)
        }
        func updateFullscreenDisplays() {}
        func syncMirrors() {}
    }

    static func run(_ suite: TestSuite) {
        defer {
            UserDefaults.standard.enabled = false
            UserDefaults.standard.preciseVolume = false
            NSScreen.screensHaveSeparateSpaces = true
            SpaceWindowBridge.value = nil
            NotchAppFullscreen.covered = []
            NotchService.shared = Service()
            PreciseVolumeRollerService.shared.stop()
        }
        let topology = Topology(displays: [
            .init(displayID: 1, spaces: [10, 11], fullscreenSpaces: [11], currentSpace: 10),
            .init(displayID: 2, spaces: [20, 21], fullscreenSpaces: [21], currentSpace: 21)
        ])
        suite.expect(!topology.isFullscreen(on: 1, separateSpaces: true)
                     && topology.isFullscreen(on: 2, separateSpaces: true),
                     "fullscreen on another monitor does not hide the island's desktop")
        suite.expect(topology.isFullscreen(on: 1, separateSpaces: false),
                     "a shared fullscreen Space applies to all monitors")
        suite.expect(!topology.isFullscreen(on: 99, separateSpaces: true),
                     "an unknown monitor is not mistaken for another monitor's fullscreen Space")
        let unknown = Topology(displays: [
            .init(displayID: nil, spaces: [10, 11], fullscreenSpaces: [11], currentSpace: 11)
        ])
        suite.expect(unknown.isFullscreen(on: 1, separateSpaces: false)
                     && !unknown.isFullscreen(on: 1, separateSpaces: true),
                     "a shared Space can omit its display UUID")

        let service = Service()
        SpaceWindowBridge.value = topology
        SpaceWindowBridge.reads = 0
        service.updateFullscreenVisibility(displayID: 2)
        suite.expect(!service.hiddenInFullscreen && SpaceWindowBridge.reads == 0,
                     "the opt-in preference avoids Space queries while disabled")
        UserDefaults.standard.enabled = true
        service.hoverEmphasized = true
        service.hoverWork = DispatchWorkItem {}
        service.noticeWork = DispatchWorkItem {}
        let hover = service.hoverWork!, notice = service.noticeWork!
        let brightnessSyncs = BrightnessService.shared.syncs
        service.updateFullscreenVisibility(displayID: 2)
        suite.expect(service.hiddenInFullscreen && service.collapses == 1 && service.cancellations == 1
                     && !service.heldDrag && !service.dragPlaceholder && service.notice == nil
                     && !service.hoverEmphasized && hover.isCancelled && notice.isCancelled && service.departures == 1,
                     "entering fullscreen clears hover emphasis, pending reveals, banners, departing notices, drags and capture controls")
        suite.expect(BrightnessService.shared.syncs == brightnessSyncs + 1,
                     "entering fullscreen hands the brightness keys back to the system")
        service.updateFullscreenVisibility(displayID: 2)
        suite.expect(service.collapses == 1 && BrightnessService.shared.syncs == brightnessSyncs + 1,
                     "unchanged fullscreen state does not repeat dismissal or key routing")
        service.updateFullscreenVisibility(displayID: 1)
        suite.expect(!service.hiddenInFullscreen && !service.hoverEmphasized
                     && BrightnessService.shared.syncs == brightnessSyncs + 2,
                     "returning to a desktop restores eligibility without retaining the old hover emphasis")
        service.updateFullscreenVisibility(displayID: 2)
        UserDefaults.standard.enabled = false
        service.updateFullscreenVisibility(displayID: 2)
        suite.expect(!service.hiddenInFullscreen, "disabling the option restores eligibility in fullscreen")
        UserDefaults.standard.enabled = true
        SpaceWindowBridge.value = nil
        service.updateFullscreenVisibility(displayID: 2)
        suite.expect(!service.hiddenInFullscreen, "unavailable Space queries leave the island reachable")
        service.fullscreenEnvironmentDidChange()
        suite.expect(service.screenUpdates == 1 && service.consumerSyncs == 0 && service.refreshes == 0,
                     "an unchanged fullscreen state leaves consumers and a transition on screen alone")
        service.screenUpdate = { [weak service] in service?.hiddenInFullscreen = true }
        service.fullscreenEnvironmentDidChange()
        suite.expect(service.screenUpdates == 2 && service.consumerSyncs == 1 && service.refreshes == 1,
                     "a fullscreen change reevaluates the display, consumers and presentation together")
        service.screenUpdate = nil
        service.suspended = true
        service.fullscreenEnvironmentDidChange()
        suite.expect(service.screenUpdates == 2, "Space changes cannot reveal a locked or sleeping session")
        UserDefaults.standard.enabled = false
        let idle = Service()
        idle.fullscreenEnvironmentDidChange()
        suite.expect(idle.screenUpdates == 0 && idle.consumerSyncs == 0 && idle.refreshes == 0,
                     "with the option off, app and Space changes do no fullscreen work")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchHideInFullscreen] as? Bool == false
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchHideInFullscreen),
                     "fullscreen hiding is opt-in and included in settings backup")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchHoverInFullscreen] as? Bool == false
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchHoverInFullscreen),
                     "fullscreen hover is a separate opt-in included in settings backup")
        appFullscreenChecks(topology, suite)
        fullscreenMotionChecks(topology, suite)
        appFullscreenWindowChecks(suite)
        volumeLifecycleChecks(topology, suite)
    }

    private static func appFullscreenChecks(_ topology: Topology, _ suite: TestSuite) {
        UserDefaults.standard.enabled = true
        SpaceWindowBridge.value = topology
        let service = Service()
        NotchAppFullscreen.covered = [1]
        service.updateFullscreenVisibility(displayID: 1)
        suite.expect(service.hiddenInFullscreen && service.collapses == 1,
                     "a game's own full screen on a desktop Space hides the island like a full-screen Space")
        NotchAppFullscreen.covered = []
        service.updateFullscreenVisibility(displayID: 1)
        suite.expect(!service.hiddenInFullscreen, "leaving a game's own full screen brings the island back")
        NotchAppFullscreen.covered = [2]
        service.updateFullscreenVisibility(displayID: 1)
        suite.expect(!service.hiddenInFullscreen,
                     "a game in full screen on another display leaves the island's display alone")
        UserDefaults.standard.enabled = false
        NotchAppFullscreen.covered = [1]
        service.updateFullscreenVisibility(displayID: 1)
        suite.expect(!service.hiddenInFullscreen, "a game's own full screen keeps the island while the option is off")
        NotchAppFullscreen.covered = []
    }

    /// An app's own full screen eases the island away and back; a full-screen
    /// Space already slides the screen, so the island follows it at once.
    private static func fullscreenMotionChecks(_ topology: Topology, _ suite: TestSuite) {
        defer {
            UserDefaults.standard.enabled = false
            SpaceWindowBridge.value = nil
            NotchAppFullscreen.covered = []
        }
        UserDefaults.standard.enabled = true
        SpaceWindowBridge.value = topology
        let service = Service()
        func change(space: Bool = false, app: Bool = false, on display: CGDirectDisplayID = 1) {
            SpaceWindowBridge.value = Topology(displays: [
                .init(displayID: 1, spaces: [10, 11], fullscreenSpaces: [11], currentSpace: space ? 11 : 10)
            ])
            NotchAppFullscreen.covered = app ? [display] : []
            service.screenUpdate = { [unowned service] in service.updateFullscreenVisibility(displayID: display) }
            service.fullscreenEnvironmentDidChange()
        }
        change(app: true)
        suite.expect(service.hiddenInFullscreen && service.refreshAnimations == [true],
                     "an app's own full screen hides the island with the usual animation")
        change()
        suite.expect(!service.hiddenInFullscreen && service.refreshAnimations == [true, true]
                     && service.refreshReveals == [false, true],
                     "leaving an app's own full screen reveals the island with the usual animation")
        change(space: true)
        suite.expect(service.hiddenInFullscreen && service.refreshAnimations.last == false
                     && service.refreshReveals.last == false,
                     "entering a full-screen Space hides the island at once")
        change()
        suite.expect(!service.hiddenInFullscreen && service.refreshAnimations.last == false
                     && service.refreshReveals.last == false,
                     "leaving a full-screen Space shows the island at once")
        change(app: true)
        change(space: true, app: true)
        change(app: true)
        change()
        suite.expect(service.refreshAnimations.suffix(2) == [true, true],
                     "an app's full screen keeps its animation after a Space came and went over it")
        change(app: true)
        change(space: true, app: true)
        change(space: true)
        change()
        suite.expect(service.refreshAnimations.suffix(1) == [false] && service.refreshReveals.suffix(1) == [false],
                     "full screen last held by a Space ends at once, whatever began it")
    }

    /// Window lists recorded from GLFW full screen (Minecraft) and ordinary
    /// desktop windows on a 14-inch notched display.
    private static func appFullscreenWindowChecks(_ suite: TestSuite) {
        typealias Real = VorssaintTests.NotchAppFullscreen
        let built = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let external = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let displays: [CGDirectDisplayID: CGRect] = [1: built, 2: external]
        func window(_ bounds: CGRect, pid: pid_t = 42, layer: Int = 25, alpha: Double = 1,
                    number: CGWindowID = 1) -> Real.WindowInfo {
            Real.WindowInfo(number: number, ownerPID: pid, layer: layer, alpha: alpha, bounds: bounds)
        }
        func covered(_ windows: [Real.WindowInfo], front: pid_t? = 42,
                     menuBarHidden: Bool = false) -> Set<CGDirectDisplayID> {
            Real.coveredDisplays(windows: windows, frontmostPID: front, ownPID: 7, displays: displays,
                                 menuBarHidden: menuBarHidden, confirmed: []).displays
        }
        suite.expect(covered([window(built)]) == [1],
                     "a raised borderless window over the whole display is an app's own full screen")
        suite.expect(covered([window(external)]) == [2], "a game on a second display covers only that display")
        suite.expect(covered([window(CGRect(x: 0.5, y: -0.4, width: 1511.2, height: 982.6))]) == [1],
                     "a point of rounding on an edge still covers the display")
        suite.expect(covered([window(built)], front: 99).isEmpty,
                     "a raised window of an app with no level 0 window there does not hide the island")
        suite.expect(covered([window(built, layer: 0), window(built, layer: 0, number: 2)], front: 99) == [],
                     "a level 0 window never confirmed does not hide the island from the background")
        suite.expect(covered([window(built), window(built, layer: 0, number: 2)], front: 99) == [1],
                     "an app in front on a display with a raised window covers it from the background")
        suite.expect(covered([window(built, pid: 99, layer: 0, number: 2), window(built)], front: 99).isEmpty,
                     "a raised window under another app's normal window does not hide the island")
        suite.expect(covered([window(built)], front: nil).isEmpty, "no frontmost app hides nothing")
        suite.expect(covered([window(built, pid: 7)], front: 7).isEmpty, "the island's own windows never count")
        suite.expect(covered([window(built, layer: 0)]).isEmpty,
                     "a normal window filling the display under an auto-hidden menu bar keeps the island")
        // VLC 3 own full screen on a 3440x1440 display: video window at level 0
        // over the whole display, menu bar hidden by the app.
        let ultrawide = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let vlc = [window(ultrawide, layer: 0, number: 10),
                   window(CGRect(x: 1478, y: 1300, width: 483, height: 84), layer: 8, number: 11)]
        suite.expect(Real.coveredDisplays(windows: vlc, frontmostPID: 42, ownPID: 7, displays: [3: ultrawide],
                                          menuBarHidden: true, confirmed: []).displays == [3],
                     "a level 0 window filling the display covers it when the app hides the menu bar")
        suite.expect(Real.coveredDisplays(windows: vlc, frontmostPID: 42, ownPID: 7, displays: [3: ultrawide],
                                          menuBarHidden: false, confirmed: []).displays.isEmpty,
                     "the same window keeps the island when the menu bar stays visible")
        multiDisplayChecks(suite)
        suite.expect(covered([window(CGRect(x: 0, y: 33, width: 1512, height: 949), layer: 0)],
                             menuBarHidden: true).isEmpty,
                     "a level 0 window below the menu bar is not full screen even with the menu bar hidden")
        suite.expect(covered([window(built, layer: 0, alpha: 0)], menuBarHidden: true).isEmpty,
                     "an invisible level 0 window is not full screen with the menu bar hidden")
        suite.expect(covered([window(CGRect(x: 0, y: 33, width: 1512, height: 949), layer: 3)]).isEmpty,
                     "a raised window below the menu bar is not full screen")
        suite.expect(covered([window(built, alpha: 0)]).isEmpty, "an invisible overlay is not full screen")
        suite.expect(!Real.covers(built, .zero), "an empty display frame is never covered")
    }

    /// Measured with VLC in its own full screen on display A and an app
    /// clicked on display B. Lists run front to back, in CG coordinates.
    private static func multiDisplayChecks(_ suite: TestSuite) {
        typealias Real = VorssaintTests.NotchAppFullscreen
        let a = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let b = CGRect(x: 3440, y: 193, width: 1800, height: 1169)
        let displays: [CGDirectDisplayID: CGRect] = [1: a, 2: b]
        let (vlcPID, otherPID, dockPID, serverPID): (pid_t, pid_t, pid_t, pid_t) = (42, 50, 60, 70)
        func w(_ number: CGWindowID, _ pid: pid_t, _ layer: Int, _ bounds: CGRect,
               alpha: Double = 1) -> Real.WindowInfo {
            Real.WindowInfo(number: number, ownerPID: pid, layer: layer, alpha: alpha, bounds: bounds)
        }
        let controls = w(11, vlcPID, 8, CGRect(x: 1478, y: 1300, width: 483, height: 84), alpha: 0)
        let video = w(10, vlcPID, 0, a)
        let menuBar = w(20, serverPID, 24, CGRect(x: 3440, y: 193, width: 1800, height: 24))
        let dock = w(21, dockPID, 20, a)
        let appOnB = w(30, otherPID, 0, CGRect(x: 3500, y: 250, width: 1200, height: 800))
        func read(_ windows: [Real.WindowInfo], front: pid_t, hidden: Bool, confirmed: Set<CGWindowID>)
            -> (displays: Set<CGDirectDisplayID>, confirmed: Set<CGWindowID>) {
            Real.coveredDisplays(windows: windows, frontmostPID: front, ownPID: 7, displays: displays,
                                 menuBarHidden: hidden, confirmed: confirmed)
        }
        let first = read([controls, video], front: vlcPID, hidden: true, confirmed: [])
        suite.expect(first.displays == [1] && first.confirmed == [10],
                     "VLC frontmost with the menu bar hidden covers its display and is confirmed")
        let focusB = [menuBar, dock, appOnB, video, controls]
        let moved = read(focusB, front: otherPID, hidden: false, confirmed: first.confirmed)
        suite.expect(moved.displays == [1] && moved.confirmed == [10],
                     "focus on another display keeps the confirmed full-screen window covered")
        suite.expect(read(focusB, front: otherPID, hidden: false, confirmed: []).displays.isEmpty,
                     "a level 0 window never confirmed keeps the island once focus moves")
        let clicked = read([w(40, otherPID, 0, CGRect(x: 200, y: 100, width: 1000, height: 700)), dock, video],
                           front: otherPID, hidden: false, confirmed: [10])
        suite.expect(clicked.displays.isEmpty && clicked.confirmed.isEmpty,
                     "a normal window clicked above the full-screen window shows the island and drops it")
        let left = read([menuBar, appOnB, w(10, vlcPID, 0, CGRect(x: 600, y: 200, width: 1200, height: 700))],
                        front: vlcPID, hidden: false, confirmed: [10])
        suite.expect(left.displays.isEmpty && left.confirmed.isEmpty,
                     "leaving full screen uncovers the display and forgets the window")
        suite.expect(read([dock, appOnB], front: otherPID, hidden: false, confirmed: []).displays.isEmpty
                     && read([menuBar, dock, appOnB], front: otherPID, hidden: false, confirmed: []).displays.isEmpty,
                     "the Dock's full-display level 20 window alone never covers")
        suite.expect(read([video], front: 7, hidden: false, confirmed: [10]).displays == [1],
                     "the island's own focus does not uncover a confirmed full-screen window")
    }

    private static func volumeLifecycleChecks(_ topology: Topology, _ suite: TestSuite) {
        // Run the production volume eligibility and fullscreen callbacks with
        // an inert tap. No hardware keys, permissions or desktop Spaces change.
        UserDefaults.standard.enabled = true
        SpaceWindowBridge.value = topology
        for preciseVolume in [false, true] {
            UserDefaults.standard.preciseVolume = preciseVolume
            let service = Service()
            NotchService.shared = service
            let volume = PreciseVolumeRollerService.shared
            var displayID: CGDirectDisplayID = 2
            service.screenUpdate = { [weak service] in service?.updateFullscreenVisibility(displayID: displayID) }
            service.updateScreen()
            volume.syncWithPreferences()
            suite.expect(service.hiddenInFullscreen && volume.running == preciseVolume,
                         "fullscreen startup keeps the tap only when the precise volume roller needs it")
            displayID = 1
            service.fullscreenEnvironmentDidChange()
            suite.expect(!service.hiddenInFullscreen && service.acceptsSystemFeedback && volume.running,
                         "returning to the desktop restores the volume tap without a preference change")
            displayID = 2
            service.fullscreenEnvironmentDidChange()
            suite.expect(service.hiddenInFullscreen && volume.running == preciseVolume,
                         "entering fullscreen releases the notch tap but preserves the precise volume roller")
        }
    }
}
