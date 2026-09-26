// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import Combine

/// The production refresh runs against a window double, without showing UI or
/// starting the island's hardware consumers. Mode changes model AppStorage:
/// they alter computed geometry without publishing a service property.
enum NotchPresentationRefreshContract {
    typealias DispatchQueue = NotchScreenRefreshContract.DispatchQueue
    enum NSEvent {
        static var mouseLocation = CGPoint.zero
        static var monitorRemovals = 0
        static func removeMonitor(_ token: Any) { monitorRemovals += 1 }
    }
    enum NSWorkspace {
        static var shared = Accessibility()
        struct Accessibility { var accessibilityDisplayShouldReduceMotion = false }
    }
    enum NotchPanel { static let normalLevel = 0 }
    final class CaptureOptions: ObservableObject {
        enum Tool { case screenshot, text }
        @Published var selectedTool: Tool = .screenshot
        var hasFocusedControl = false
        var onSelectionProgressChange: ((Bool) -> Void)?
    }
    enum UserDefaults {
        static var standard = Preferences()
        struct Preferences {
            var hides = false
            var outline = false
            func bool(forKey key: String) -> Bool {
                switch key {
                case DefaultsKey.notchHideUntilHover: return hides
                case DefaultsKey.notchOutlineEnabled: return outline
                default: return true
                }
            }
        }
    }
    enum NotchContentTransition { case none, reveal, depart, replace }
    struct NotchPlayback { let track: Int }
    struct NotchArtworkTint { let value: Int }
    final class NotchMusicService {
        static let shared = NotchMusicService()
        var playback: NotchPlayback?
        var artwork: NSImage?
        var artworkTint: NotchArtworkTint?
    }
    struct NotchCompactMusicSnapshot {
        let playback: NotchPlayback
        let artwork: NSImage?
        let tint: NotchArtworkTint?
        var track: Int { playback.track }
        init(track: Int) { playback = NotchPlayback(track: track); artwork = nil; tint = nil }
        init(playback: NotchPlayback, artwork: NSImage?, tint: NotchArtworkTint?, geometry: NotchGeometry) {
            self.playback = playback; self.artwork = artwork; self.tint = tint
        }
    }
    struct NotchQuickAccessConfiguration {
        let buttons: [Int] = []
        static func current() -> Self { Self() }
    }
    enum FeatureStrings {
        static func notch(_ language: Int) -> (collapse: String, open: String) { ("Close", "Open") }
    }
    enum L10n {
        static let shared = SelfValue()
        struct SelfValue { let language = 0 }
    }
    final class Panel {
        var isVisible = true
        var alphaValue: CGFloat = 1
        var ignoresMouseEvents = false, acceptsKeyFocus = true, acceptsMouseMovedEvents = false
        var attachedSheet: Bool?
        var level = 1, keyRequests = 0
        func makeKey() { keyRequests += 1 }
        func resignKey() {}
        func orderOut(_ sender: Any?) { isVisible = false }
        func orderFrontRegardless() { isVisible = true }
    }
    final class Host {
        let panel = Panel()
        var departsContent = false
        func finishDeparture() { departsContent = false }
        var concealedForMissionControl = false
        var isConcealedForMissionControl: Bool { concealedForMissionControl }
        var missionControlDidRestore: (() -> Void)?
        var missionControlAlpha: CGFloat = 1
        var missionControlMouseEvents = false
        var desktopReadings = 0
        var mouseEventsBeforeHide: Bool?
        var hidesWhenSettled = false
        var restoringFromMissionControl = false
        var fadeCompletion: (() -> Void)?
        func fadeMissionControl(to alpha: CGFloat, completion: (() -> Void)? = nil) {
            panel.alphaValue = alpha
            fadeCompletion = completion
        }
        func syncMissionControlMonitoring() {}
        var hideAnimations: [Bool] = []
        func hide(animated: Bool, transitionContent: NotchContentTransition = .none) {
            hideAnimations.append(animated)
            panel.orderOut(nil)
        }
        var targetSize: CGSize = .zero
        var frame: CGRect = .zero
        var animatingFrame: CGRect?
        var activationRect = CGRect.zero
        var activate: (() -> Void)?
        func containsHover(_ point: CGPoint) -> Bool { !concealedForMissionControl && frame.contains(point) }
        func contains(_ point: CGPoint) -> Bool { !concealedForMissionControl && (animatingFrame ?? frame).contains(point) }
        var onPresent: ((CGSize) -> Void)?
        var usesGlass = false
        var revealFromHidden = false
        var outlineEnabled = false
        var outlineColor = NSColor.white
        func setOutline(enabled: Bool, color: NSColor) {
            outlineEnabled = enabled
            outlineColor = color
        }
        func present(size: CGSize, geometry: NotchGeometry, animated: Bool,
                     transitionContent: NotchContentTransition, quickAccess: NotchQuickAccessConfiguration?,
                     revealFromHidden: Bool, usesGlass: Bool) {
            departsContent = transitionContent == .depart
            self.usesGlass = usesGlass
            self.revealFromHidden = revealFromHidden
            onPresent?(size)
            targetSize = size
            frame = geometry.frame(for: size)
        }
        func setActivationArea(_ rect: CGRect, title: String, willPress: @escaping () -> Void, activate: @escaping () -> Void) {
            activationRect = rect
            self.activate = activate
        }
    }
    class State: ObservableObject {
        var hiddenInFullscreen = false
        let objectWillChange = ObservableObjectPublisher()
        var running = true, suspended = false
        var mode = NotchTimerMode.timer
        var session = NotchTimerSession()
        var selected = NotchModule.timer
        var captureID: UUID?
        var captureActions: Bool?
        var captureContent: Bool?
        var captureContentHeight: CGFloat?
        var captureFallback: (() -> Void)?
        var captureClose: (() -> Void)?
        var captureHover: ((Bool) -> Void)?
        var captureClosesOnCollapse = false
        var pinned = false
        var showingSections = false
        var showingAppPanel = false
        var selectedMetric: Bool?
        var expanded = true
        var peeking = false, dragPlaceholder = false, compactActivityIsVisible = false
        var compactActivityOverride: NotchCompactActivity?
        var compactActivity: NotchCompactActivity? {
            get { compactActivityOverride ?? (compactActivityIsVisible ? .timer : nil) }
            set { compactActivityOverride = newValue }
        }
        var compactMusicIsVisible: Bool { compactActivityIsVisible && compactActivity == .music }
        var presentedMusic: NotchCompactMusicSnapshot?
        var departingMusic: NotchCompactMusicSnapshot?
        var musicDepartureWork: DispatchWorkItem?
        var noticeExpanded = false
        var notice: Bool?
        var captureControls: CaptureOptions?
        var captureControlsCollapsed = false, captureSelectionInProgress = false
        var inside = false, trackingMenu = false
        var captureControlsWork: DispatchWorkItem?
        var captureControlsSubscription: AnyCancellable?
        var captureControlsCancel: (() -> Void)?
        var captureControlsMonitors: [Any] = []
        func installCaptureControlsClickThrough() {
            if captureControlsMonitors.isEmpty { captureControlsMonitors = [1] }
        }
        func removeEventMonitors() {}
        func syncVisibleConsumers() {}
        var hoverWork: DispatchWorkItem?
        var hoverState = NotchHoverState()
        var windowHost: Host? = Host()
        var panel: Panel? { windowHost?.panel }
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                     safeAreaTop: 32, cameraWidth: 210)
        var expandedGeometry: NotchGeometry { geometry }
        var compactActivityGeometry: NotchGeometry { geometry.compactTimerGeometry(showsDownloads: false) }
        var surfaceSize: CGSize {
            if captureControls != nil { return captureControlsCollapsed ? geometry.collapsed : geometry.peek }
            if !expanded, compactActivityIsVisible { return compactActivityGeometry.compactActivitySize }
            if !expanded { return geometry.collapsed }
            return expandedGeometry.expandedSize(module: selected, capturePreviewHeight: captureContent == nil ? nil : captureContentHeight,
                                         timerHasSession: session.hasSession,
                                         timerMode: session.hasSession ? session.mode : mode)
        }
        func syncHiddenHoverMonitoring() {}
        func finishMusicDeparture() {
            musicDepartureWork?.cancel(); musicDepartureWork = nil
            departingMusic = nil
            windowHost?.finishDeparture()
        }
        func removeHiddenHoverMonitors() {}
        func toggle() { expanded.toggle() }
        func collapse() { expanded = false }
        var edgeClicksEnabled = false
        func syncScreenEdgeClicks() { edgeClicksEnabled = true }
        func removeScreenEdgeClickMonitors() { edgeClicksEnabled = false }
    }

    static func run(_ suite: TestSuite) {
        compactMusicDepartureChecks(suite)
        UserDefaults.standard.hides = false
        UserDefaults.standard.outline = false
        defer {
            UserDefaults.standard.hides = false
            UserDefaults.standard.outline = false
        }
        let outlined = Service()
        outlined.expanded = false
        UserDefaults.standard.outline = true
        outlined.refreshPresentation(animated: false)
        suite.expect(outlined.windowHost?.outlineEnabled == true && outlined.windowHost?.outlineColor == .white,
                     "the optional outline reaches the resting island")
        outlined.compactActivityIsVisible = true
        outlined.refreshPresentation(animated: false)
        suite.expect(outlined.windowHost?.outlineColor == .systemOrange,
                     "the compact timer tints the optional outline orange")
        UserDefaults.standard.outline = false
        outlined.refreshPresentation(animated: false)
        suite.expect(outlined.windowHost?.outlineEnabled == false,
                     "turning the outline off updates the existing island")
        let toolbar = Service()
        toolbar.geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                          safeAreaTop: 32, cameraWidth: 210, layout: .spacious)
        suite.expect(toolbar.expandedGeometry.headerCameraGap == 210,
                     "a standard wide page puts its header beside the camera")
        toolbar.selected = .captures
        toolbar.captureActions = true
        toolbar.captureContent = true
        toolbar.captureContentHeight = 150
        toolbar.refreshPresentation(animated: false)
        suite.expect(toolbar.expandedGeometry.headerCameraGap == 0
                     && toolbar.expandedGeometry.headerTopInset == 42
                     && toolbar.windowHost?.activationRect.height == 42,
                     "a capture toolbar keeps a full row below the camera without losing actions to the cutout")
        toolbar.showingSections = true
        suite.expect(toolbar.expandedGeometry.headerCameraGap == 210,
                     "leaving capture editing restores the compact header layout")
        captureControlsChecks(suite)
        let fullscreen = Service()
        fullscreen.pinned = true
        fullscreen.hiddenInFullscreen = true
        fullscreen.refreshPresentation()
        suite.expect(fullscreen.panel?.isVisible == false && !fullscreen.acceptsSystemFeedback
                     && !fullscreen.edgeClicksEnabled,
                     "fullscreen hides even a pinned island and stops routing feedback or edge clicks")
        fullscreen.hiddenInFullscreen = false
        fullscreen.refreshPresentation()
        suite.expect(fullscreen.panel?.isVisible == true && fullscreen.acceptsSystemFeedback,
                     "leaving fullscreen restores the island and feedback routing")
        let missionControl = Service()
        missionControl.windowHost?.concealedForMissionControl = true
        suite.expect(!missionControl.acceptsSystemFeedback && !missionControl.showsSystemFeedback,
                     "a concealed island leaves system feedback available to its other presenters")
        missionControl.windowHost?.concealedForMissionControl = false
        suite.expect(missionControl.acceptsSystemFeedback && missionControl.showsSystemFeedback,
                     "leaving Mission Control restores island feedback routing")

        let material = Service()
        material.expanded = false
        material.geometry = NotchGeometry(screen: material.geometry.screen, safeAreaTop: 38,
                                          cameraWidth: 210, compactSideRoom: 0)
        material.refreshPresentation(animated: false)
        suite.expect(!material.usesGlassSurface && material.windowHost?.usesGlass == false,
                     "compact presentation remains opaque regardless of camera or footer height")
        material.peeking = true
        material.refreshPresentation(animated: false)
        suite.expect(material.windowHost?.usesGlass == true, "peek requests the glass backdrop")
        material.peeking = false
        material.expanded = true
        material.refreshPresentation(animated: false)
        suite.expect(material.windowHost?.usesGlass == true, "expanded content requests the glass backdrop")
        material.expanded = false
        material.noticeExpanded = true
        material.refreshPresentation(animated: false)
        suite.expect(material.windowHost?.usesGlass == true, "expanded notification requests the glass backdrop")

        let closing = Service()
        closing.refreshPresentation(animated: false)
        let open = closing.windowHost?.frame ?? .zero
        for (point, stillOver) in [(CGPoint(x: open.midX, y: open.minY + 4), false), (CGPoint(x: open.midX, y: open.maxY - 1), true)] {
            closing.expanded = true
            closing.refreshPresentation(animated: false)
            NSEvent.mouseLocation = point
            closing.hoverState.close(pointerInside: closing.windowHost?.containsHover(point) == true)
            closing.expanded = false
            closing.refreshPresentation()
            suite.expect(closing.hoverState.suppressed == stillOver, stillOver
                ? "a pointer still over the closed island keeps it from reopening until it leaves"
                : "closing away from a pointer that has not moved lets its next approach open the island")
        }
        NSEvent.mouseLocation = .zero

        let service = Service()
        var contentSize = service.surfaceSize
        service.windowHost?.targetSize = contentSize
        var invalidations = 0
        let subscription = service.objectWillChange.sink {
            invalidations += 1
            contentSize = service.surfaceSize
        }
        defer { subscription.cancel() }
        var mismatches = 0
        service.windowHost?.onPresent = { size in
            if contentSize != size { mismatches += 1 }
        }
        // The timer and the stopwatch share one height, so only a change
        // that resizes the island may publish.
        var resizes = 0
        for mode in [NotchTimerMode.pomodoro, .timer, .stopwatch, .pomodoro, .stopwatch, .timer] {
            let before = service.surfaceSize
            service.mode = mode
            service.refreshPresentation(animated: false)
            if service.surfaceSize != before { resizes += 1 }
            suite.expect(contentSize == service.surfaceSize,
                   "switching Timer, Pomodoro and Stopwatch updates the content height without reopening the island")
        }
        suite.expect(mismatches == 0, "content is invalidated before the native window receives its new size")
        suite.expect(resizes == 4 && invalidations == resizes,
               "each mode change with a new size publishes it, and one keeping the size stays quiet")
        for _ in 0..<1000 { service.refreshPresentation() }
        suite.expect(invalidations == resizes, "unchanged presentations do not repeatedly invalidate SwiftUI layout")

        service.session.start(mode: .timer, minutes: 15, now: 0)
        service.refreshPresentation()
        let activeSize = contentSize
        let beforeModeChange = invalidations
        service.mode = .pomodoro
        service.refreshPresentation()
        suite.expect(contentSize == activeSize && invalidations == beforeModeChange,
               "changing the saved setup mode preserves an active timer's layout")
        service.session.cancel()
        service.refreshPresentation()
        suite.expect(contentSize == service.surfaceSize && contentSize.height > activeSize.height && mismatches == 0,
               "canceling returns to the newly selected setup with synchronized content and window sizes")

        let captureID = UUID()
        service.selected = .captures
        service.captureID = captureID
        service.captureContent = true
        service.captureContentHeight = 210
        service.refreshPresentation()
        let previewSize = contentSize
        service.updateCaptureHeight(id: captureID, height: 268)
        suite.expect(contentSize.height == previewSize.height + 58 && service.windowHost?.targetSize == contentSize,
               "an embedded shared link expands both the capture content and its native window")
        service.updateCaptureHeight(id: captureID, height: 210)
        suite.expect(contentSize == previewSize, "removing a shared link restores the original preview height")
        service.updateCaptureHeight(id: UUID(), height: 268)
        suite.expect(contentSize == previewSize, "a replaced capture cannot resize its successor")
        service.selected = .timer
        service.refreshPresentation()
        let timerSize = contentSize
        service.updateCaptureHeight(id: captureID, height: 268)
        suite.expect(contentSize == timerSize, "sharing completion in a hidden preview does not resize the visible timer")
        service.selected = .captures
        service.refreshPresentation()
        service.pinned = true
        service.removeCapture(id: captureID)
        suite.expect(service.expanded && service.captureContentHeight == nil && service.captureContent == nil
               && contentSize == service.geometry.expandedSize(module: .captures)
               && service.windowHost?.targetSize == contentSize,
               "dismissing a pinned capture clears the preview size and restores the full recent-captures area")

        let simulated = Service()
        simulated.expanded = false
        simulated.panel?.isVisible = false
        simulated.geometry = NotchGeometry(screen: CGRect(x: -1440, y: 900, width: 1440, height: 900),
                                          safeAreaTop: 0, cameraWidth: 0)
        simulated.refreshPresentation(animated: false)
        suite.expect(simulated.panel?.isVisible == false && !simulated.edgeClicksEnabled,
               "an unmeasured simulated cutout does not cover a menu or receive screen-edge clicks")
        simulated.applyMenuSpace(0)
        suite.expect(simulated.panel?.isVisible == true && simulated.edgeClicksEnabled
               && simulated.windowHost?.frame == simulated.geometry.frame(for: simulated.surfaceSize),
               "a confirmed free center can show the simulated cutout without side room")
        let bareSize = simulated.surfaceSize
        let occupied = [CGRect(x: simulated.geometry.screen.midX - 15, y: simulated.geometry.screen.maxY - 24,
                               width: 90, height: 24)]
        let blocked = NotchMenuBarLayout.sideRoom(screen: simulated.geometry.screen, cameraWidth: simulated.geometry.cameraWidth,
                                                 barHeight: simulated.geometry.menuBarHeight, occupied: occupied)
        suite.expect(blocked == nil, "a real center collision is distinct from zero-width free wings")
        simulated.applyMenuSpace(blocked)
        suite.expect(simulated.surfaceSize == bareSize && simulated.panel?.isVisible == false && !simulated.edgeClicksEnabled,
               "a center collision hides even an unchanged bare simulated cutout")
        for active in [false, true] {
            simulated.compactActivityIsVisible = active
            simulated.applyMenuSpace(64)
            suite.expect(simulated.panel?.isVisible == true && simulated.edgeClicksEnabled,
                   "free menu space restores idle and active simulated content")
            simulated.applyMenuSpace(nil)
            suite.expect(simulated.panel?.isVisible == false && !simulated.edgeClicksEnabled,
                   "idle and active simulated content both release menus when clearance is lost")
            simulated.refreshPresentation(animated: false)
            suite.expect(simulated.panel?.isVisible == false,
                   "a later refresh cannot redisplay compact activity over an occupied center")
        }
        simulated.expanded = true
        simulated.refreshPresentation()
        suite.expect(simulated.panel?.isVisible == true && simulated.windowHost?.frame.maxY == simulated.geometry.screen.maxY,
               "explicitly opening tools remains available without a menu measurement")
        suite.expect(simulated.windowHost?.revealFromHidden == false,
               "ordinary openings keep their existing presentation behavior")
        simulated.expanded = false
        simulated.refreshPresentation()
        suite.expect(simulated.windowHost?.hideAnimations.last == true,
               "closing an expanded island without safe menu space animates its withdrawal")
        suite.expect(simulated.panel?.isVisible == false,
               "closing tools withdraws their simulated cutout if the center is still unverified")

        UserDefaults.standard.hides = true
        for isPhysical in [false, true] {
            let hidden = Service()
            if !isPhysical { hidden.geometry = simulated.geometry }
            hidden.expanded = false
            hidden.compactActivityIsVisible = true
            hidden.notice = true
            hidden.refreshPresentation()
            suite.expect(hidden.panel?.isVisible == false && !hidden.edgeClicksEnabled && !hidden.showsSystemFeedback,
                   "hidden mode withdraws the entire window, including compact activity and an existing notice")
            suite.expect(hidden.windowHost?.hideAnimations.last == true,
                   "closing a hidden-until-hover island requests an animated withdrawal")
            hidden.refreshPresentation(animated: false)
            suite.expect(hidden.windowHost?.hideAnimations.last == false,
                   "a nonanimated refresh preserves immediate withdrawal")
            hidden.expanded = true
            hidden.refreshPresentation()
            suite.expect(hidden.panel?.isVisible == true && hidden.showsSystemFeedback, "explicit openings remain visible in hidden mode")
            suite.expect(hidden.windowHost?.revealFromHidden == true,
                   "opening a hidden island requests a reveal from the screen edge")
            hidden.expanded = false
            hidden.captureControls = CaptureOptions()
            hidden.refreshPresentation()
            suite.expect(hidden.panel?.isVisible == true, "capture controls remain visible until dismissed")
            suite.expect(hidden.windowHost?.revealFromHidden == false,
                   "capture controls keep their own presentation in hidden-until-hover mode")
            hidden.captureControls = nil
            hidden.dragPlaceholder = true
            hidden.refreshPresentation()
            suite.expect(hidden.panel?.isVisible == true, "an explicit file drag can still reveal its destination")
            hidden.dragPlaceholder = false
            hidden.refreshPresentation()
            suite.expect(hidden.panel?.isVisible == false, "ending the interaction hides the window again")
        }
        UserDefaults.standard.hides = false
        let physical = Service()
        physical.expanded = false
        physical.compactActivityIsVisible = true
        physical.refreshPresentation(animated: false)
        suite.expect(physical.panel?.isVisible == true && !physical.compactActivityGeometry.compactActivityUsesFooter
               && physical.compactActivityGeometry.compactActivityWingWidth == 0
               && physical.windowHost?.targetSize.height == physical.geometry.menuBarHeight,
               "an active timer on a physical camera retracts its wings and stays at menu-bar height without a menu measurement")
    }

    private static func compactMusicDepartureChecks(_ suite: TestSuite) {
        let changed = Service()
        changed.expanded = false
        changed.compactActivity = .music
        changed.compactActivityIsVisible = true
        let oldCover = NSImage(size: NSSize(width: 1, height: 1))
        let newCover = NSImage(size: NSSize(width: 2, height: 2))
        changed.rememberPresentedMusic(playback: NotchPlayback(track: 1), artwork: oldCover, tint: nil)
        changed.rememberPresentedMusic(playback: NotchPlayback(track: 2), artwork: oldCover, tint: nil)
        changed.rememberPresentedMusic(playback: NotchPlayback(track: 2), artwork: newCover,
                                       tint: NotchArtworkTint(value: 2))
        changed.compactActivity = nil
        changed.compactActivityIsVisible = false
        suite.expect(changed.compactMusicTransition(.none, animated: true) == .depart
                     && changed.departingMusic?.track == 2 && changed.departingMusic?.artwork === newCover
                     && changed.departingMusic?.tint?.value == 2,
                     "a track and cover changed during playback remain current through departure")

        let closing = Service()
        closing.expanded = false
        closing.presentedMusic = NotchCompactMusicSnapshot(track: 1)
        suite.expect(closing.compactMusicTransition(.none, animated: true) == .depart
                     && closing.departingMusic?.track == 1,
                     "closing the last playing source keeps its compact track for the departure")
        closing.compactActivity = .music
        closing.compactActivityIsVisible = true
        suite.expect(closing.compactMusicTransition(.none, animated: true) == .reveal
                     && closing.departingMusic == nil,
                     "new playback interrupts a departing track and reveals its replacement")

        let replacement = Service()
        replacement.expanded = false
        replacement.presentedMusic = NotchCompactMusicSnapshot(track: 2)
        replacement.compactActivity = .timer
        replacement.compactActivityIsVisible = true
        suite.expect(replacement.compactMusicTransition(.none, animated: true) == .replace,
                     "a compact timer replaces the disappearing music with a fade")

        let reduced = Service()
        reduced.expanded = false
        reduced.presentedMusic = NotchCompactMusicSnapshot(track: 3)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = true
        suite.expect(reduced.compactMusicTransition(.none, animated: true) == .none
                     && reduced.departingMusic == nil,
                     "Reduce Motion removes the music strip immediately")
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = false
    }
}
