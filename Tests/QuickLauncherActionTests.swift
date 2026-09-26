// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Carbon.HIToolbox

/// The generated members are the real tile model, activation method and icon
/// methods. Only their environment is replaced: no windows, taps or capture.
enum QuickLauncherContract {
    static var events: [String] = []
    static var cameraInNotch = false
    enum ReviewDefaults { static var current: UserDefaults! }
    enum QuickLauncherService { static let columns = 3 }
    struct NSEvent {
        struct ModifierFlags: OptionSet {
            let rawValue: Int
            static let command = Self(rawValue: 1)
            static let control = Self(rawValue: 2)
            static let option = Self(rawValue: 4)
            static let shift = Self(rawValue: 8)
        }
        let keyCode: UInt16
        var modifierFlags: ModifierFlags = []
    }

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
        func showInNotchIfEnabled() -> Bool {
            guard name == "camera", cameraInNotch else { return false }
            events.append("camera.notch")
            return true
        }
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
        let domain = "com.vorssaint.tests.quick-launcher-presentation"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        ReviewDefaults.current = defaults
        defer {
            ReviewDefaults.current = nil
            defaults.removePersistentDomain(forName: domain)
        }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        cameraInNotch = false
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
        events.removeAll()
        DispatchQueue.main.jobs.removeAll()
        cameraInNotch = true
        Launcher().run(.cameraPreview)
        suite.expect(events == ["camera.notch", "hide"] && DispatchQueue.main.jobs.isEmpty,
                     "an embedded camera switches the notch before hiding the launcher, without a close-and-reopen delay")
        cameraInNotch = false
        var tile = Tile()
        suite.expect(tile.display(.screenRecorder) == ("record.circle", false),
                     "an idle recording tile offers recording")
        tile.recorder.isRecording = true
        suite.expect(tile.display(.screenRecorder) == ("stop.circle", true),
                     "an active recording tile offers stopping and shows its active state")
        suite.expect(QuickLauncherItem.allCases.allSatisfy { !tile.display($0).0.isEmpty },
                     "every tile has an icon")
        presentationContracts(suite)
    }

    private static func presentationContracts(_ suite: TestSuite) {
        let launcher = Launcher()
        let oldPresentation = launcher.presentationID
        launcher.isEditing = true
        launcher.editingOptionsItem = .clipboard
        launcher.prepareForPresentation()
        suite.expect(launcher.presentationID != oldPresentation && !launcher.isEditing
                     && launcher.editingOptionsItem == nil && launcher.selectedIndex == 0,
                     "a new presentation resets edit controls and selects its first available tile")
        events.removeAll()
        let enter = NSEvent(keyCode: UInt16(kVK_Return))
        suite.expect(launcher.handlePanelKey(enter) == nil && events == ["keepAwake.toggle"],
                     "Return activates the first item immediately after presentation")
        for item in [QuickLauncherItem.urlCleaner, .homebrew, .uninstaller, .media] {
            launcher.activeUtility = item
            launcher.prepareForPresentation()
            suite.expect(launcher.activeUtility == item,
                         "reopening preserves the working utility while its feature remains installed")
            ReviewDefaults.current.set(false, forKey: item.feature.availabilityKey)
            launcher.editingOptionsItem = item
            launcher.refreshAvailability()
            suite.expect(launcher.activeUtility == nil && launcher.editingOptionsItem == nil,
                         "removing a feature clears both its hosted utility and its edit options")
            launcher.activeUtility = item
            launcher.prepareForPresentation()
            suite.expect(launcher.activeUtility == nil,
                         "a utility removed while the island was closed cannot return on reopening")
            events.removeAll()
            launcher.run(item)
            suite.expect(launcher.activeUtility == nil && events.isEmpty,
                         "a stale tile action cannot activate a removed feature")
            ReviewDefaults.current.set(true, forKey: item.feature.availabilityKey)
        }
        launcher.candidates = []
        launcher.prepareForPresentation()
        events.removeAll()
        suite.expect(launcher.selectedIndex == nil && launcher.handlePanelKey(enter) == nil && events.isEmpty,
                     "an empty launcher has no imaginary initial action")
    }
}
