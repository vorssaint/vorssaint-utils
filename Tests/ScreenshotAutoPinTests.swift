// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Run the production completion route with private preferences and record its
/// outputs. Captures and windows are doubles, so this never touches the desktop.
enum ScreenshotAutoPinTests {
    enum ScreenshotSelectionController {
        struct Capture {
            let image: Int
            let scale: CGFloat
        }
    }

    enum ScreenshotQuickPreviewController {
        enum Action: Hashable { case copy, save }
    }

    final class ScreenshotPinController {
        static let shared = ScreenshotPinController()
        var images: [Int] = []
        var scales: [CGFloat] = []
        func pin(image: Int, scale: CGFloat) {
            images.append(image)
            scales.append(scale)
        }
    }

    final class RecentCaptureService {
        static let shared = RecentCaptureService()
        var images: [Int] = []
        func recordScreenshot(_ capture: ScreenshotSelectionController.Capture) { images.append(capture.image) }
    }

    struct NotchService {
        enum Reaction { case flash }
        static let shared = Self()
        func reactMascot(_ reaction: Reaction, patience: Int) {}
    }

    final class Preview {
        var closed = false
        func close() { closed = true }
    }

    class State {
        let defaults: UserDefaults
        var preview: Preview? = Preview()
        let latestCaptureToken = UUID()
        var latest: [Int] = []
        var edited: [Int] = []
        var autoCopied: [Int] = []
        var copied: [Int] = []
        var saved: [Int] = []
        var shelved: [Int] = []
        var shelvedURL: URL?
        var previews: [Int] = []
        var completedActions: Set<ScreenshotQuickPreviewController.Action> = []
        var saveSucceeds = true
        var copySucceeds = true
        let saveURL = URL(fileURLWithPath: "/tmp/auto-pin-test.png")

        init(defaults: UserDefaults) { self.defaults = defaults }
        func beginLatestCapture(_ capture: ScreenshotSelectionController.Capture) { latest.append(capture.image) }
        func autoCopy(_ capture: ScreenshotSelectionController.Capture) { autoCopied.append(capture.image) }
        func openEditor(with capture: ScreenshotSelectionController.Capture) { edited.append(capture.image) }
        func autoShelve(_ capture: ScreenshotSelectionController.Capture, saved: URL?) {
            shelved.append(capture.image)
            shelvedURL = saved
        }
        func presentPreview(_ capture: ScreenshotSelectionController.Capture,
                            defaultAction: ScreenshotDefaultAction,
                            initialSaved: Service.SaveOutcome?,
                            completedActions: Set<ScreenshotQuickPreviewController.Action>,
                            dismissInterval: TimeInterval?, latestCapture: UUID?) {
            previews.append(capture.image)
            self.completedActions = completedActions
        }
        func copyDirect(_ capture: ScreenshotSelectionController.Capture) -> Bool {
            copied.append(capture.image)
            return copySucceeds
        }
        func saveDirect(_ capture: ScreenshotSelectionController.Capture) -> Service.SaveOutcome? {
            saved.append(capture.image)
            return saveSucceeds ? Service.SaveOutcome(url: saveURL, consumedNumber: nil) : nil
        }
        func saveAndCopyDirect(_ capture: ScreenshotSelectionController.Capture)
            -> (outcome: Service.SaveOutcome, copied: Bool)? {
            guard let outcome = saveDirect(capture) else { return nil }
            return (outcome, copyDirect(capture))
        }
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.screenshot-auto-pin.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let keys = [DefaultsKey.screenshotAutoPin, DefaultsKey.screenshotScrollingAutoPin]
        suite.expect(keys.allSatisfy { Defaults.registeredDefaults[$0] as? Bool == false },
                     "both auto-pin options ship off")
        suite.expect(keys.allSatisfy(SettingsBackupSupport.exportKeys().contains),
                     "both auto-pin options travel in settings backups")

        for regular in [false, true] {
            for scrolling in [false, true] {
                for kind: ScreenshotSupport.CaptureKind in [.standard, .scrolling] {
                    for action in ScreenshotDefaultAction.allCases {
                        for autoCopy in [false, true] {
                            defaults.set(regular, forKey: keys[0])
                            defaults.set(scrolling, forKey: keys[1])
                            defaults.set(action.rawValue, forKey: DefaultsKey.screenshotDefaultAction)
                            defaults.set(autoCopy, forKey: DefaultsKey.screenshotCopyToClipboard)
                            defaults.set(true, forKey: DefaultsKey.screenshotPreviewEnabled)
                            ScreenshotPinController.shared.images = []
                            ScreenshotPinController.shared.scales = []
                            RecentCaptureService.shared.images = []
                            let service = Service(defaults: defaults)
                            service.route(.init(image: 42, scale: 2), kind: kind)
                            let pins = kind == .scrolling ? scrolling : regular
                            let edits = action == .edit && !pins
                            suite.expect(ScreenshotPinController.shared.images == (pins ? [42] : [])
                                    && ScreenshotPinController.shared.scales == (pins ? [2] : [])
                                    && service.edited == (edits ? [42] : [])
                                    && service.previews == (pins || edits ? [] : [42]),
                                         "\(kind), regular=\(regular), scrolling=\(scrolling), \(action): only the chosen capture kind auto-pins and skips editor/preview")
                            suite.expect(service.autoCopied == (autoCopy ? [42] : [])
                                    && service.copied == (action.copiesToClipboard ? [42] : [])
                                    && service.saved == (action == .save || action == .saveAndCopy ? [42] : [])
                                    && service.shelved == (edits ? [] : [42]),
                                         "auto-pin preserves independent clipboard, output and shelf actions")
                            suite.expect(service.latest == [42] && RecentCaptureService.shared.images == [42]
                                    && service.preview?.closed == true,
                                         "auto-pinned captures still replace the latest capture, record history and dismiss the old preview")
                        }
                    }
                }
            }
        }

        defaults.set(true, forKey: DefaultsKey.screenshotAutoPin)
        defaults.set(false, forKey: DefaultsKey.screenshotPreviewEnabled)
        for action: ScreenshotDefaultAction in [.save, .copy, .saveAndCopy] {
            for saveSucceeds in [false, true] {
                for copySucceeds in [false, true] {
                    defaults.set(action.rawValue, forKey: DefaultsKey.screenshotDefaultAction)
                    let service = Service(defaults: defaults)
                    service.saveSucceeds = saveSucceeds
                    service.copySucceeds = copySucceeds
                    service.route(.init(image: 7, scale: 1))
                    let succeeded = action == .save ? saveSucceeds
                        : action == .copy ? copySucceeds : saveSucceeds && copySucceeds
                    suite.expect(service.previews == (succeeded ? [] : [7]) && service.edited.isEmpty,
                                 "auto-pin keeps failed or partial \(action) output recoverable even with confirmations off")
                    suite.expect(service.shelvedURL == (action != .copy && saveSucceeds ? service.saveURL : nil),
                                 "auto-pin passes the saved file to the shelf when available")
                }
            }
        }

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.screenshot(language)
            suite.expect(!strings.autoPinToggle.isEmpty && !strings.autoPinCaption.isEmpty,
                         "\(language) has auto-pin labels and instructions")
            suite.expect(SettingsSearchSupport.scrollingScreenshotItem(language: language).keywords
                .contains(strings.autoPinToggle), "\(language) can find scrolling auto-pin in Settings")
        }
    }
}

/// Exercise the real scroll view without creating or showing a pinned window.
enum ScreenshotPinZoomTests {
    final class ScreenshotPinWindow {}
    final class PinContentView: NSView {
        init(image: CGImage, window: ScreenshotPinWindow) { super.init(frame: .zero) }
        @available(*, unavailable) required init?(coder: NSCoder) { nil }
    }

    static func run(_ suite: TestSuite) {
        let image = ScreenshotCanvasSupportTests.image(width: 300, height: 20_000)
        let view = PinScrollView(image: image, scale: 2,
                                 frame: CGRect(x: 0, y: 0, width: 200, height: 500),
                                 window: ScreenshotPinWindow())
        view.layoutSubtreeIfNeeded()
        let fullSize = CGSize(width: 150, height: 10_000)
        suite.expect(view.documentView?.frame.size == fullSize
                && view.magnification == view.minMagnification
                && fullSize.height * view.magnification <= view.contentSize.height + 1,
                     "a long pin starts fitted while retaining the full image dimensions")
        view.frame.size = CGSize(width: 250, height: 700)
        view.layoutSubtreeIfNeeded()
        suite.expect(abs(view.magnification - 0.07) < 0.001,
                     "resizing a fitted pin keeps the full capture fitted")
        view.magnification = 1
        view.contentView.scroll(to: CGPoint(x: 0, y: 8_000))
        view.reflectScrolledClipView(view.contentView)
        suite.expect(view.magnification == 1 && view.documentView?.frame.size == fullSize
                && view.documentVisibleRect.minY > 7_000,
                     "zooming a long pin permits panning to content far below the initial viewport")
        view.frame.size = CGSize(width: 300, height: 600)
        view.layoutSubtreeIfNeeded()
        suite.expect(view.magnification == 1,
                     "resizing a zoomed pin preserves the chosen magnification")
    }
}
