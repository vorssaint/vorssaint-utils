// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Run both capture entry points with an isolated preference suite and clock.
enum ScreenshotCountdownTests {
    class ChooserState {
        var countdown: DispatchWorkItem?
        var countdownTools: [ScreenCaptureTool]?
        var countdownRemaining = 0
        var selection: Bool?
        var selections: [ScreenCaptureTool] = []
        func beginSelection(tools: [ScreenCaptureTool], selected: ScreenCaptureTool, showsCaptureMenu: Bool) {
            selections.append(selected)
        }
    }
    class ScreenshotState {
        var directCaptureTask: Bool?
        var hasActiveCapture: Bool { directCaptureTask != nil }
        var captures = 0
        func beginFullScreenCapture() { captures += 1 }
        func finishScrollingCaptureIfActive() -> Bool { false }
    }
    enum ScreenshotSelectionController { static let isSessionOnScreen = false }
    final class ScreenRecorderService {
        static let shared = ScreenRecorderService()
        let hasActiveCapture = false
        func stopOrCancelActiveCapture() -> Bool { false }
        func prepareForSelection() -> Bool { true }
    }
    final class Permissions {
        static let shared = Permissions()
        let screenRecording = true
        func requestScreenRecording() {}
    }
    final class ColorSamplerService {
        static let shared = ColorSamplerService()
        func pickNative() {}
    }
    enum QuickToolHUD {
        static var ticks: [Int] = []
        static func showCountdown(_ remaining: Int) { ticks.append(remaining) }
    }
    final class Clock {
        static let main = Clock()
        var pending: [DispatchWorkItem] = []
        func asyncAfter(deadline: DispatchTime, execute work: DispatchWorkItem) { pending.append(work) }
        func advance() {
            let due = pending
            pending.removeAll()
            for work in due { work.perform() }
        }
    }

    static let suiteName = "com.vorssaint.tests.scrolling-countdown." + UUID().uuidString
    static let defaults = UserDefaults(suiteName: suiteName)!

    static func run(_ suite: TestSuite) {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let chooser = ScreenCaptureService.shared, screenshot = ScreenshotService.shared
        defaults.set(3, forKey: DefaultsKey.screenshotDelay)
        defaults.set(false, forKey: DefaultsKey.screenshotScrollingShowCaptureMenuOnShortcut)
        chooser.selections = []
        screenshot.captures = 0
        QuickToolHUD.ticks = []
        screenshot.captureFullScreen()
        screenshot.captureScrolling()
        Clock.main.advance()
        chooser.capture(initial: .scrolling, fromShortcut: true)
        screenshot.captureFullScreen()
        Clock.main.advance()
        suite.expect(QuickToolHUD.ticks == [3, 3] && chooser.countdown == nil
                     && chooser.selections.isEmpty && screenshot.captures == 0,
                     "full-screen and scrolling actions cancel each other's countdown in either order")
        screenshot.captureScrolling()
        for _ in 0..<3 { Clock.main.advance() }
        screenshot.captureFullScreen()
        for _ in 0..<3 { Clock.main.advance() }
        suite.expect(chooser.selections == [.scrolling] && screenshot.captures == 1
                     && chooser.countdown == nil && Clock.main.pending.isEmpty,
                     "each completed countdown runs exactly the requested capture and releases the next one")
    }
}
