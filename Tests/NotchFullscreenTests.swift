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
        struct Feature { let isAvailable = true }
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
    class State {
        var running = true, suspended = false, hiddenInFullscreen = false
        var panel: Bool? = true
        var screenUpdate: (() -> Void)?
        var heldDrag = true, dragPlaceholder = true, noticeExpanded = true
        var hoverWork: DispatchWorkItem?, noticeWork: DispatchWorkItem?
        var notice: Bool? = true
        var collapses = 0, cancellations = 0, screenUpdates = 0, consumerSyncs = 0, refreshes = 0
        func cancelCaptureControls() { cancellations += 1 }
        func collapse() { collapses += 1 }
        func updateScreen() { screenUpdates += 1; screenUpdate?() }
        func syncVisibleConsumers() { consumerSyncs += 1 }
        func refreshPresentation(animated: Bool) { refreshes += 1 }
    }

    static func run(_ suite: TestSuite) {
        defer {
            UserDefaults.standard.enabled = false
            UserDefaults.standard.preciseVolume = false
            NSScreen.screensHaveSeparateSpaces = true
            SpaceWindowBridge.value = nil
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
        service.hoverWork = DispatchWorkItem {}
        service.noticeWork = DispatchWorkItem {}
        let hover = service.hoverWork!, notice = service.noticeWork!
        service.updateFullscreenVisibility(displayID: 2)
        suite.expect(service.hiddenInFullscreen && service.collapses == 1 && service.cancellations == 1
                     && !service.heldDrag && !service.dragPlaceholder && service.notice == nil
                     && hover.isCancelled && notice.isCancelled,
                     "entering fullscreen clears pending reveals, banners, drags and capture controls")
        service.updateFullscreenVisibility(displayID: 2)
        suite.expect(service.collapses == 1, "unchanged fullscreen state does not repeat dismissal")
        service.updateFullscreenVisibility(displayID: 1)
        suite.expect(!service.hiddenInFullscreen, "moving to a desktop display restores eligibility")
        service.updateFullscreenVisibility(displayID: 2)
        UserDefaults.standard.enabled = false
        service.updateFullscreenVisibility(displayID: 2)
        suite.expect(!service.hiddenInFullscreen, "disabling the option restores eligibility in fullscreen")
        UserDefaults.standard.enabled = true
        SpaceWindowBridge.value = nil
        service.updateFullscreenVisibility(displayID: 2)
        suite.expect(!service.hiddenInFullscreen, "unavailable Space queries leave the island reachable")
        service.fullscreenEnvironmentDidChange()
        suite.expect(service.screenUpdates == 1 && service.consumerSyncs == 1 && service.refreshes == 1,
                     "Space changes reevaluate the display, consumers and presentation together")
        service.suspended = true
        service.fullscreenEnvironmentDidChange()
        suite.expect(service.refreshes == 1, "Space changes cannot reveal a locked or sleeping session")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchHideInFullscreen] as? Bool == false
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchHideInFullscreen),
                     "fullscreen hiding is opt-in and included in settings backup")
        volumeLifecycleChecks(topology, suite)
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
