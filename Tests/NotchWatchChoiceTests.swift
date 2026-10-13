// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Production selection, preparation and stop methods with controllable
/// capture replies. No selector, capture, OCR or permission request runs.
enum NotchWatchChoiceTests {
    enum NotchWatchSupport {
        static var enabled = true
        static func isEnabled() -> Bool { enabled }
        static func windowCrop(for area: CGRect, windows: [(id: CGWindowID, bounds: CGRect)])
            -> (id: CGWindowID, crop: CGRect)? { nil }
    }

    enum RecorderSupport {
        struct Region {
            var windowID: CGWindowID?
            var displayID: CGDirectDisplayID = 1
            var anchorRect = CGRect(x: 10, y: 10, width: 100, height: 80)
            var pixelRect = CGRect(x: 20, y: 20, width: 200, height: 160)
        }
    }

    struct NotchWatchTarget {
        let windowID: CGWindowID?
        let displayID: CGDirectDisplayID
        let crop: CGRect
        let appName: String
        let processID: pid_t?
        let windowTitle: String?
    }

    final class NotchService {
        static let shared = NotchService()
        var protectedWindowIDs: Set<CGWindowID> = []
        var captureChromeWindowIDs: Set<CGWindowID> = []
        var opens = 0
        func open(_ module: NotchModule, feedback: Bool) { opens += 1 }
    }

    enum Permissions {
        static let shared = PermissionsState()
        final class PermissionsState { func requestScreenRecording() {} }
    }
    enum L10n {
        static let shared = Language()
        struct Language { let language = AppLanguage.enUS }
    }

    final class ScreenshotSelectionController {
        enum Mode { case geometry }
        enum Outcome { case region(RecorderSupport.Region), cancelled }
        static var isSessionOnScreen = false
        var completion: ((Outcome) -> Void)?
        var cancellations = 0

        init(freeze: Bool, includePointer: Bool, showLastRegion: Bool, hideVorssaintWindows: Bool,
             protectedWindowIDs: @escaping () -> Set<CGWindowID>, purpose: String, mode: Mode) {}
        func begin(_ completion: @escaping (Outcome) -> Void) { self.completion = completion }
        func cancel() { cancellations += 1; completion?(.cancelled) }
    }

    enum ScreenshotCaptureEngine {
        final class RegionCapture {}
        static var pending: [CheckedContinuation<RegionCapture?, Never>] = []
        static func pickableWindows(hideVorssaintWindows: Bool, protectedWindowIDs: Set<CGWindowID>)
            -> [(id: CGWindowID, bounds: CGRect)] { [] }
        static func prepareDisplayRegion(displayID: CGDirectDisplayID, pixelRect: CGRect, includePointer: Bool,
                                         hideVorssaintWindows: Bool, protectedWindowIDs: Set<CGWindowID>,
                                         keepsIslandOut: Bool) async -> RegionCapture? {
            await withCheckedContinuation { pending.append($0) }
        }
    }

    class Fixture {
        enum State { case idle, watching }
        struct WindowInfo {
            var bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
            var appName = "Example"
            var processID: pid_t? = 42
            var title: String? = "Window"
        }
        var choiceGeneration = UUID()
        var selection: ScreenshotSelectionController?
        var regionCapture: ScreenshotCaptureEngine.RegionCapture?
        var target: NotchWatchTarget?
        var state = State.idle
        var preview: Int?
        var text = "", headline = ""
        var startedAt: Date?
        var headlineLine: Int?
        var fingerprint: [UInt8]?
        var signature: String?
        var readAt: Date?
        var permissionMissing = false
        var starts = 0
        var loopStops = 0
        func CGPreflightScreenCaptureAccess() -> Bool { true }
        static func windowInfo(_ id: CGWindowID) -> WindowInfo? { WindowInfo() }
        func begin(_ target: NotchWatchTarget) { self.target = target; state = .watching; starts += 1 }
        func cancelLoop() { loopStops += 1 }
    }

    static func run(_ suite: TestSuite) {
        var finished = false
        Task { @MainActor in await checks(suite); finished = true }
        let deadline = Date().addingTimeInterval(10)
        while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        suite.expect(finished, "watch choice lifecycle checks finish")
    }

    @MainActor private static func checks(_ suite: TestSuite) async {
        let notch = NotchService.shared
        NotchWatchSupport.enabled = true
        notch.opens = 0
        defer {
            NotchWatchSupport.enabled = true
            let pending = ScreenshotCaptureEngine.pending
            ScreenshotCaptureEngine.pending = []
            pending.forEach { $0.resume(returning: nil) }
            notch.opens = 0
        }
        func waitFor(_ predicate: () -> Bool) async -> Bool {
            for _ in 0..<500 {
                if predicate() { return true }
                try? await Task.sleep(for: .milliseconds(1))
            }
            return predicate()
        }

        let stopped = Service()
        stopped.chooseArea()
        let selector = stopped.selection!
        let late = selector.completion!
        stopped.stop()
        late(.region(.init(windowID: 1)))
        await Task.yield()
        suite.expect(selector.cancellations == 1 && stopped.selection == nil && stopped.starts == 0
                        && stopped.target == nil && notch.opens == 0,
                     "stopping closes the selector and rejects its late result")

        let preparing = Service()
        let preparation = Task { await preparing.watch(.init(), choice: preparing.choiceGeneration) }
        guard await waitFor({ ScreenshotCaptureEngine.pending.count == 1 }) else {
            suite.expect(false, "the display preparation suspends for its reply"); return
        }
        preparing.stop()
        ScreenshotCaptureEngine.pending.removeFirst().resume(returning: .init())
        await preparation.value
        suite.expect(preparing.starts == 0 && preparing.target == nil && preparing.regionCapture == nil && notch.opens == 0,
                     "a display prepared after stop cannot restart watching or reopen the island")

        let disabled = Service()
        let disabledPreparation = Task { await disabled.watch(.init(), choice: disabled.choiceGeneration) }
        guard await waitFor({ ScreenshotCaptureEngine.pending.count == 1 }) else {
            suite.expect(false, "disabled fixture reaches capture preparation"); return
        }
        NotchWatchSupport.enabled = false
        ScreenshotCaptureEngine.pending.removeFirst().resume(returning: .init())
        await disabledPreparation.value
        suite.expect(disabled.starts == 0 && disabled.regionCapture == nil && notch.opens == 0,
                     "disabling Watch rejects preparation even before preference synchronization calls stop")
        NotchWatchSupport.enabled = true

        let replaced = Service()
        let replacedPreparation = Task { await replaced.watch(.init(), choice: replaced.choiceGeneration) }
        guard await waitFor({ ScreenshotCaptureEngine.pending.count == 1 }) else {
            suite.expect(false, "replacement fixture reaches capture preparation"); return
        }
        replaced.chooseArea()
        replaced.selection?.completion?(.region(.init(windowID: 2)))
        let selected = await waitFor { replaced.target?.windowID == 2 }
        suite.expect(selected && replaced.starts == 1 && notch.opens == 1,
                     "a newer selected window starts normally while an older display preparation waits")
        ScreenshotCaptureEngine.pending.removeFirst().resume(returning: .init())
        await replacedPreparation.value
        suite.expect(replaced.target?.windowID == 2 && replaced.starts == 1 && replaced.regionCapture == nil
                        && notch.opens == 1,
                     "an old display preparation cannot replace the newer window")

        let valid = Service()
        let validPreparation = Task { await valid.watch(.init(), choice: valid.choiceGeneration) }
        guard await waitFor({ ScreenshotCaptureEngine.pending.count == 1 }) else {
            suite.expect(false, "valid fixture reaches capture preparation"); return
        }
        ScreenshotCaptureEngine.pending.removeFirst().resume(returning: .init())
        await validPreparation.value
        suite.expect(valid.starts == 1 && valid.regionCapture != nil && valid.target?.windowID == nil && notch.opens == 2,
                     "the current enabled display choice starts watching and opens the island once")
    }
}
