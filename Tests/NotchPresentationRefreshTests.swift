// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Combine

/// The production refresh runs against a window double, without showing UI or
/// starting the island's hardware consumers. Mode changes model AppStorage:
/// they alter computed geometry without publishing a service property.
enum NotchPresentationRefreshContract {
    enum NotchContentTransition { case none }
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
        func orderOut(_ sender: Any?) { isVisible = false }
        func orderFrontRegardless() { isVisible = true }
    }
    final class Host {
        var targetSize: CGSize = .zero
        var frame: CGRect = .zero
        var onPresent: ((CGSize) -> Void)?
        func present(size: CGSize, geometry: NotchGeometry, animated: Bool,
                     transitionContent: NotchContentTransition, quickAccess: NotchQuickAccessConfiguration?) {
            onPresent?(size)
            targetSize = size
            frame = geometry.frame(for: size)
        }
        func setActivationArea(_ rect: CGRect, title: String, willPress: () -> Void, activate: () -> Void) {}
    }
    class State: ObservableObject {
        let objectWillChange = ObservableObjectPublisher()
        var mode = NotchTimerMode.timer
        var session = NotchTimerSession()
        var selected = NotchModule.timer
        var captureID: UUID?
        var captureContent: Bool?
        var captureContentHeight: CGFloat?
        var captureFallback: (() -> Void)?
        var captureClose: (() -> Void)?
        var captureHover: ((Bool) -> Void)?
        var pinned = false
        var showingSections = false
        var expanded = true
        var peeking = false, dragPlaceholder = false, compactActivityIsVisible = false
        let notice: Bool? = nil
        let captureControls: Bool? = nil
        var hoverWork: DispatchWorkItem?
        var hoverState = NotchHoverState()
        var panel: Panel? = Panel()
        var windowHost: Host? = Host()
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                     safeAreaTop: 32, cameraWidth: 210)
        var compactActivityGeometry: NotchGeometry { geometry.compactTimerGeometry(showsDownloads: false) }
        var surfaceSize: CGSize {
            if !expanded, compactActivityIsVisible { return compactActivityGeometry.compactActivitySize }
            if !expanded { return geometry.collapsed }
            return geometry.expandedSize(module: selected, capturePreviewHeight: captureContent == nil ? nil : captureContentHeight,
                                         timerHasSession: session.hasSession,
                                         timerShowsPomodoro: (session.hasSession ? session.mode : mode) == .pomodoro)
        }
        func toggle() { expanded.toggle() }
        func collapse() { expanded = false }
        var edgeClicksEnabled = false
        func syncScreenEdgeClicks() { edgeClicksEnabled = true }
        func removeScreenEdgeClickMonitors() { edgeClicksEnabled = false }
    }

    static func run(expect: (Bool, String) -> Void) {
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
        for mode in [NotchTimerMode.pomodoro, .timer, .pomodoro, .timer] {
            service.mode = mode
            service.refreshPresentation(animated: false)
            expect(contentSize == service.surfaceSize,
                   "switching Timer and Pomodoro updates the content height without reopening the island")
        }
        expect(mismatches == 0, "content is invalidated before the native window receives its new size")
        expect(invalidations == 4, "each mode change publishes its new presentation size")
        for _ in 0..<1000 { service.refreshPresentation() }
        expect(invalidations == 4, "unchanged presentations do not repeatedly invalidate SwiftUI layout")

        service.session.start(mode: .timer, minutes: 15, now: 0)
        service.refreshPresentation()
        let activeSize = contentSize
        let beforeModeChange = invalidations
        service.mode = .pomodoro
        service.refreshPresentation()
        expect(contentSize == activeSize && invalidations == beforeModeChange,
               "changing the saved setup mode preserves an active timer's layout")
        service.session.cancel()
        service.refreshPresentation()
        expect(contentSize == service.surfaceSize && contentSize.height > activeSize.height && mismatches == 0,
               "canceling returns to the newly selected setup with synchronized content and window sizes")

        let captureID = UUID()
        service.selected = .captures
        service.captureID = captureID
        service.captureContent = true
        service.captureContentHeight = 210
        service.refreshPresentation()
        let previewSize = contentSize
        service.updateCaptureHeight(id: captureID, height: 268)
        expect(contentSize.height == previewSize.height + 58 && service.windowHost?.targetSize == contentSize,
               "an embedded shared link expands both the capture content and its native window")
        service.updateCaptureHeight(id: captureID, height: 210)
        expect(contentSize == previewSize, "removing a shared link restores the original preview height")
        service.updateCaptureHeight(id: UUID(), height: 268)
        expect(contentSize == previewSize, "a replaced capture cannot resize its successor")
        service.selected = .timer
        service.refreshPresentation()
        let timerSize = contentSize
        service.updateCaptureHeight(id: captureID, height: 268)
        expect(contentSize == timerSize, "sharing completion in a hidden preview does not resize the visible timer")
        service.selected = .captures
        service.refreshPresentation()
        service.pinned = true
        service.removeCapture(id: captureID)
        expect(service.expanded && service.captureContentHeight == nil && service.captureContent == nil
               && contentSize == service.geometry.expandedSize(module: .captures)
               && service.windowHost?.targetSize == contentSize,
               "dismissing a pinned capture clears the preview size and restores the full recent-captures area")

        let simulated = Service()
        simulated.expanded = false
        simulated.panel?.isVisible = false
        simulated.geometry = NotchGeometry(screen: CGRect(x: -1440, y: 900, width: 1440, height: 900),
                                          safeAreaTop: 0, cameraWidth: 0)
        simulated.refreshPresentation(animated: false)
        expect(simulated.panel?.isVisible == false && !simulated.edgeClicksEnabled,
               "an unmeasured simulated cutout does not cover a menu or receive screen-edge clicks")
        simulated.applyMenuSpace(0)
        expect(simulated.panel?.isVisible == true && simulated.edgeClicksEnabled
               && simulated.windowHost?.frame == simulated.geometry.frame(for: simulated.surfaceSize),
               "a confirmed free center can show the simulated cutout without side room")
        let bareSize = simulated.surfaceSize
        let occupied = [CGRect(x: simulated.geometry.screen.midX - 15, y: simulated.geometry.screen.maxY - 24,
                               width: 90, height: 24)]
        let blocked = NotchMenuBarLayout.sideRoom(screen: simulated.geometry.screen, cameraWidth: simulated.geometry.cameraWidth,
                                                 barHeight: simulated.geometry.menuBarHeight, occupied: occupied)
        expect(blocked == nil, "a real center collision is distinct from zero-width free wings")
        simulated.applyMenuSpace(blocked)
        expect(simulated.surfaceSize == bareSize && simulated.panel?.isVisible == false && !simulated.edgeClicksEnabled,
               "a center collision hides even an unchanged bare simulated cutout")
        for active in [false, true] {
            simulated.compactActivityIsVisible = active
            simulated.applyMenuSpace(64)
            expect(simulated.panel?.isVisible == true && simulated.edgeClicksEnabled,
                   "free menu space restores idle and active simulated content")
            simulated.applyMenuSpace(nil)
            expect(simulated.panel?.isVisible == false && !simulated.edgeClicksEnabled,
                   "idle and active simulated content both release menus when clearance is lost")
            simulated.refreshPresentation(animated: false)
            expect(simulated.panel?.isVisible == false,
                   "a later refresh cannot redisplay compact activity over an occupied center")
        }
        simulated.expanded = true
        simulated.refreshPresentation()
        expect(simulated.panel?.isVisible == true && simulated.windowHost?.frame.maxY == simulated.geometry.screen.maxY,
               "explicitly opening tools remains available without a menu measurement")
        simulated.expanded = false
        simulated.refreshPresentation()
        expect(simulated.panel?.isVisible == false,
               "closing tools withdraws their simulated cutout if the center is still unverified")

        let physical = Service()
        physical.expanded = false
        physical.compactActivityIsVisible = true
        physical.refreshPresentation(animated: false)
        expect(physical.panel?.isVisible == true && physical.compactActivityGeometry.compactActivityUsesFooter,
               "an active timer on a physical camera keeps its footer without a menu measurement")
    }
}
