// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Production presentation and consumer methods run against a controlled
/// playback reader. Its last reply deliberately survives stop, so cached music
/// cannot make the assertions pass merely because a test double cleared it.
enum NotchMusicVisibilityTests {
    enum ReviewDefaults { static var current: UserDefaults! }
    final class NotchMusicService {
        static var shared = NotchMusicService()
        struct Playback { var isPlaying: Bool }
        var playback: Playback?
        var running = false
        func start() { running = true }
        func stop() { running = false }
    }
    struct MonitorNeeds {
        var disk = false
        static let none = Self()
    }
    struct Metric { let monitorNeeds = MonitorNeeds.none }
    final class SystemMonitor {
        static let shared = SystemMonitor()
        func setNotchDetailNeeds(_ needs: MonitorNeeds) {}
        func setNotchVisible(_ visible: Bool) {}
    }
    final class CameraPreviewService {
        static let shared = CameraPreviewService()
        func hideEmbedded() {}
    }
    struct CaptureControls {
        struct Tool { let capturesAudio = false }
        let selectedTool = Tool()
        var onSelectionProgressChange: ((Bool) -> Void)?
    }
    enum NotchContentTransition { case none, dismiss }
    struct Host { func containsHover(_ point: CGPoint) -> Bool { false } }
    struct Panel {
        var acceptsKeyFocus = false
        var level = 0
        func resignKey() {}
    }
    enum NotchPanel { static let normalLevel = 0 }
    enum NSEvent { static let mouseLocation = CGPoint.zero }

    class State {
        var running = true
        var suspended = false
        var expanded = false
        var peeking = false
        var showingAppPanel = false
        var showingSections = false
        var selected: NotchModule = .controls
        var selectedMetric: Metric?
        var modules: [NotchModule] = []
        var captureControls: CaptureControls?
        var captureControlsCollapsed = false
        var captureSelectionInProgress = false
        var captureControlsWork: DispatchWorkItem?
        var captureControlsSubscription: Bool?
        var captureControlsCancel: (() -> Void)?
        var notice: NotchNotice?
        var dragPlaceholder = false
        var hasTimerActivity = false
        var hasDownloadActivity = false
        var notchNeedsMonitor = false
        var heldDrag = false
        var pinned = false
        var openedByHover = false
        var sectionQuery = ""
        var highlightedSection: NotchModule?
        var hoverState = NotchHoverState()
        var hoverWork: DispatchWorkItem?
        var windowHost: Host?
        var panel: Panel? = Panel()
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                     safeAreaTop: 32, cameraWidth: 180, compactSideRoom: 100)
        var expandedSize: CGSize { geometry.expanded }
        func syncMenuSpaceMonitoring() {}
        func removeCaptureControlsClickThrough() {}
        func refreshPresentation() {}
        func removeEventMonitors() {}
        func mutatePresentation(transitionContent: NotchContentTransition, _ change: () -> Void) { change() }
    }

    static func run(expect: (Bool, String) -> Void) {
        let domain = "com.vorssaint.tests.notch-music-visibility"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        ReviewDefaults.current = defaults
        defer {
            ReviewDefaults.current = nil
            NotchMusicService.shared = NotchMusicService()
            defaults.removePersistentDomain(forName: domain)
        }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        let service = Service()
        let reader = NotchMusicService.shared
        service.modules = NotchSupport.modules(in: defaults)

        for physical in [true, false] {
            service.geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                            safeAreaTop: physical ? 32 : 0, cameraWidth: physical ? 180 : 0,
                                            menuBarHeight: 32, compactSideRoom: 100)
            let closed = service.geometry.restingSize(showsContent: false)
            defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
            defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
            reader.playback = .init(isPlaying: true)
            service.syncVisibleConsumers()
            expect(reader.running && service.compactActivity == .music && service.surfaceSize.width > closed.width,
                   "enabled playback first appears beside both physical and simulated cameras")

            defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
            service.syncVisibleConsumers()
            expect(!reader.running && service.compactActivity == nil && service.idleContent == .none
                   && service.surfaceSize == closed,
                   "selecting Nothing retracts already visible music and stops its reader with cached playback still present")
            let reopened = Service()
            reopened.modules = service.modules
            reopened.geometry = service.geometry
            reopened.syncVisibleConsumers()
            expect(!reader.running && reopened.compactActivity == nil && reopened.surfaceSize == closed,
                   "a fresh island honors saved Nothing while playback metadata is still available")
            for automatic in [false, true] {
                defaults.set(automatic, forKey: DefaultsKey.notchShowPlayingMusic)
                for module in [NotchModule.music, .controls] {
                    service.selected = module
                    service.expanded = true
                    service.syncVisibleConsumers()
                    expect(reader.running && service.surfaceSize == service.expandedSize,
                           "Nothing still starts the music reader when its explicit controls open")
                    for playing in [true, false, true] {
                        reader.playback = .init(isPlaying: playing)
                        service.syncVisibleConsumers()
                        expect(reader.running && service.compactActivity == nil,
                               "playback updates keep manually opened controls usable without enabling automatic music")
                    }
                    service.collapse()
                    expect(!reader.running && !service.expanded && service.surfaceSize == closed,
                           "closing manually opened controls stops the reader and never leaves a music strip behind")
                }
            }

            defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
            defaults.set(false, forKey: DefaultsKey.notchShowPlayingMusic)
            service.syncVisibleConsumers()
            expect(!reader.running && service.idleContent == .none && service.compactActivity == nil
                   && service.surfaceSize == closed,
                   "disabled automatic music stops the reader even when resting content is Music")
            defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
            for playing in [true, false, true] {
                reader.playback = .init(isPlaying: playing)
                service.syncVisibleConsumers()
                expect(reader.running && (service.compactActivity == .music) == playing
                       && (service.surfaceSize == closed) == !playing,
                       "re-enabling music detects resume while paused playback occupies no wings")
            }
            defaults.set(true, forKey: DefaultsKey.notchOpenOnHover)
            defaults.set(true, forKey: DefaultsKey.notchHideUntilHover)
            service.syncVisibleConsumers()
            expect(!reader.running && service.hiddenUntilHover,
                   "hidden mode stops the resting music reader even with cached playing metadata")
            service.selected = .music
            service.expanded = true
            service.syncVisibleConsumers()
            expect(reader.running, "revealing hidden music controls starts their reader on demand")
            service.collapse()
            expect(!reader.running && service.hiddenUntilHover,
                   "closing hidden music controls releases their reader again")
            // The capture presenter sets this state and synchronizes consumers;
            // cancellation below executes the production teardown method.
            service.captureControls = CaptureControls()
            service.syncVisibleConsumers()
            expect(reader.running, "visible capture controls can retain enabled resting music")
            service.endCaptureControls()
            expect(service.captureControls == nil && service.hiddenUntilHover && !reader.running,
                   "canceling capture returns hidden mode to rest without retaining the music reader")
            service.endCaptureControls()
            expect(!reader.running, "a repeated capture cleanup cannot restart hidden music")
            defaults.set(false, forKey: DefaultsKey.notchHideUntilHover)
            service.syncVisibleConsumers()
            expect(reader.running, "returning to a visible mode resumes the resting music reader")
            service.captureControls = CaptureControls()
            service.syncVisibleConsumers()
            service.endCaptureControls()
            expect(reader.running, "ending capture in a visible mode preserves enabled resting music")
            defaults.set(NotchIdleContent.battery.rawValue, forKey: DefaultsKey.notchIdleContent)
            defaults.set(false, forKey: DefaultsKey.notchShowPlayingMusic)
            service.syncVisibleConsumers()
            expect(!reader.running && service.idleContent == .battery && service.compactActivity == nil
                   && service.surfaceSize == service.geometry.restingSize(showsContent: true),
                   "hiding music preserves the chosen battery indicator during active playback")
        }

        defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
        service.selected = .music
        service.expanded = true
        for surface in ["sections", "appPanel", "unrelated", "hiddenModule", "hiddenControl"] {
            service.showingSections = surface == "sections"
            service.showingAppPanel = surface == "appPanel"
            service.selected = surface == "unrelated" ? .files : surface == "hiddenControl" ? .controls : .music
            defaults.set(surface == "hiddenModule" ? "music" : "", forKey: DefaultsKey.notchHiddenModules)
            defaults.set(surface == "hiddenControl" ? "music" : "", forKey: DefaultsKey.notchHiddenControls)
            service.modules = NotchSupport.modules(in: defaults)
            service.syncVisibleConsumers()
            expect(!reader.running, "\(surface) cannot retain an invisible on-demand music reader")
        }
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set("", forKey: DefaultsKey.notchHiddenControls)
        service.modules = NotchSupport.modules(in: defaults)
        service.collapse()
        service.hasTimerActivity = true
        service.hasDownloadActivity = true
        expect(service.compactActivity == .timer, "Nothing for resting music preserves a running timer")
        service.hasTimerActivity = false
        expect(service.compactActivity == .downloads, "Nothing for resting music preserves active downloads")
        let notice = NotchNotice(event: .accessory, title: "Wireless Headphones", detail: "Connected", symbol: "headphones")
        service.notice = notice
        expect(service.surfaceSize == service.geometry.noticeSize(wingWidth: notice.preferredWingWidth)
               && service.surfaceSize.width > service.geometry.notice.width,
               "a device notice widens the actual presentation beyond the compact level indicator")
        service.notice = nil
        expect(service.surfaceSize == service.compactActivityGeometry.compactActivitySize,
               "dismissing a device notice restores the underlying activity's width")
    }
}
