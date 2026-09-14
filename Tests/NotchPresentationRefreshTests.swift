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
        var onPresent: ((CGSize) -> Void)?
        func present(size: CGSize, geometry: NotchGeometry, animated: Bool,
                     transitionContent: NotchContentTransition, quickAccess: NotchQuickAccessConfiguration?) {
            onPresent?(size)
            targetSize = size
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
        let peeking = false, dragPlaceholder = false, compactActivityIsVisible = false
        let notice: Bool? = nil
        let captureControls: Bool? = nil
        var hoverWork: DispatchWorkItem?
        var hoverState = NotchHoverState()
        var panel: Panel? = Panel()
        var windowHost: Host? = Host()
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                     safeAreaTop: 32, cameraWidth: 210)
        var presentationGeometry: NotchGeometry { geometry }
        var compactActivityGeometry: NotchGeometry { geometry }
        var surfaceSize: CGSize {
            if !expanded { return geometry.collapsed }
            return geometry.expandedSize(module: selected, capturePreviewHeight: captureContent == nil ? nil : captureContentHeight,
                                         timerHasSession: session.hasSession,
                                         timerShowsPomodoro: (session.hasSession ? session.mode : mode) == .pomodoro)
        }
        func toggle() { expanded.toggle() }
        func collapse() { expanded = false }
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
    }
}
