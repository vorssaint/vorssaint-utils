// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The generated members are the real tile model, activation method and icon
/// methods. Only their environment is replaced: no windows, taps or capture.
enum QuickLauncherContract {
    static var events: [String] = []

    struct State {
        var isActive = false
        var isMuted = false
        var isRecording = false
    }

    struct Deadline {
        let delay: Double
        static func now() -> Deadline { Deadline(delay: 0) }
        static func + (lhs: Deadline, rhs: Double) -> Deadline { Deadline(delay: lhs.delay + rhs) }
    }

    final class Queue {
        var jobs: [(Deadline, () -> Void)] = []
        func asyncAfter(deadline: Deadline, execute: @escaping () -> Void) {
            jobs.append((deadline, execute))
        }
        func drain() {
            let pending = jobs
            jobs.removeAll()
            pending.forEach { $0.1() }
        }
    }

    enum DispatchQueue { static let main = Queue() }
    struct Spy {
        let name: String
        func toggle() { events.append(name + ".toggle") }
        func capture() { events.append(name + ".capture") }
        func pick() { events.append(name + ".pick") }
        func show() { events.append(name + ".show") }
        func showHistoryWindow() { events.append(name + ".showHistoryWindow") }
        func activate() { events.append(name + ".activate") }
    }
    enum KeepAwakeManager { static let shared = Spy(name: "keepAwake") }
    enum MicMuteService { static let shared = Spy(name: "micMute") }
    enum ScreenTextService { static let shared = Spy(name: "screenOCR") }
    enum ScreenshotService { static let shared = Spy(name: "screenshot") }
    enum ScreenRecorderService { static let shared = Spy(name: "recorder") }
    enum ColorSamplerService { static let shared = Spy(name: "colorPicker") }
    enum CameraPreviewService { static let shared = Spy(name: "camera") }
    enum ScratchpadService { static let shared = Spy(name: "scratchpad") }
    enum ClipboardHistoryService { static let shared = Spy(name: "clipboard") }
    enum CleaningModeManager { static let shared = Spy(name: "cleaning") }

    static func run(_ suite: TestSuite) {
        let cases: [(QuickLauncherItem, AppFeature, String?, Double?)] = [
            (.keepAwake, .keepAwake, "keepAwake.toggle", nil),
            (.micMute, .micMute, "micMute.toggle", nil),
            (.screenOCR, .screenOCR, "screenOCR.capture", 0.15),
            (.screenshot, .screenshot, "screenshot.capture", 0.15),
            (.screenRecorder, .screenRecorder, "recorder.toggle", 0.15),
            (.colorPicker, .colorPicker, "colorPicker.pick", 0.15),
            (.cameraPreview, .cameraPreview, "camera.show", 0.15),
            (.scratchpad, .scratchpad, "scratchpad.show", 0.15),
            (.clipboard, .clipboardHistory, "clipboard.showHistoryWindow", 0.1),
            (.cleaning, .cleaningMode, "cleaning.activate", 0.1),
            (.windowLayout, .windowLayout, nil, nil),
            (.homebrew, .homebrew, nil, nil),
            (.media, .mediaTools, nil, nil),
            (.urlCleaner, .urlCleaner, nil, nil),
            (.uninstaller, .uninstaller, nil, nil),
            (.cleaner, .cleaner, nil, nil),
            (.toggles, .quickToggles, nil, nil),
        ]
        suite.expect(Set(cases.map { $0.0 }) == Set(QuickLauncherItem.allCases),
                     "every launcher tile has an activation contract")
        for (item, feature, action, delay) in cases {
            events.removeAll()
            DispatchQueue.main.jobs.removeAll()
            let launcher = Launcher()
            launcher.run(item)
            suite.expect(item.feature == feature, "\(item) follows its own feature switch")
            if let delay, let action {
                suite.expect(events == ["hide"] && launcher.activeUtility == nil,
                             "\(item) dismisses the launcher before any external action")
                suite.expect(DispatchQueue.main.jobs.count == 1
                             && DispatchQueue.main.jobs.first?.0.delay == delay,
                             "\(item) schedules exactly one action after dismissal")
                DispatchQueue.main.drain()
                suite.expect(events == ["hide", action], "\(item) executes the intended action exactly once")
            } else if let action {
                suite.expect(events == [action] && DispatchQueue.main.jobs.isEmpty
                             && launcher.activeUtility == nil,
                             "\(item) toggles immediately without dismissing or opening a utility")
            } else {
                suite.expect(events.isEmpty && DispatchQueue.main.jobs.isEmpty
                             && launcher.activeUtility == item,
                             "\(item) opens its utility inside the launcher")
            }
            events.removeAll()
            launcher.isEditing = true
            launcher.activeUtility = nil
            launcher.run(item)
            DispatchQueue.main.drain()
            suite.expect(events.isEmpty && launcher.activeUtility == nil,
                         "editing \(item) never activates it")
        }
        var tile = Tile()
        suite.expect(tile.display(.screenRecorder) == ("record.circle", false),
                     "an idle recording tile offers recording")
        tile.recorder.isRecording = true
        suite.expect(tile.display(.screenRecorder) == ("stop.circle", true),
                     "an active recording tile offers stopping and shows its active state")
        suite.expect(QuickLauncherItem.allCases.allSatisfy { !tile.display($0).0.isEmpty },
                     "every tile has an icon")
    }
}
