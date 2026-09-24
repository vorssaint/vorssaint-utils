// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Execute the production copy paths with isolated files and preferences.
/// Rendering and clipboard delivery are doubles; no screen or user clipboard is touched.
enum ScreenshotCopyNameTests {
    static let domain = "com.vorssaint.tests.screenshot-copy-name"
    static let defaults = Foundation.UserDefaults(suiteName: domain)!
    static var root = Foundation.FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenshotCopyName-\(UUID().uuidString)")
    static var copyDirectory: URL? { root.appendingPathComponent("copies") }
    static var copiedURL: URL?
    static var acceptsCopy = true

    enum UserDefaults { static var standard: Foundation.UserDefaults { defaults } }
    enum Bundle { static let main = BundleValue() }
    struct BundleValue { let bundleIdentifier: String? = "test-copy" }
    struct FileManager {
        static let `default` = FileManager()
        func urls(for directory: Foundation.FileManager.SearchPathDirectory,
                  in domain: Foundation.FileManager.SearchPathDomainMask) -> [URL] { [root] }
        func removeItem(at url: URL) throws { try Foundation.FileManager.default.removeItem(at: url) }
    }
    enum NSPasteboard {
        static let general = Pasteboard()
        final class Pasteboard { var changeCount = 0 }
    }
    enum NSSound { static func beep() {} }
    enum AppFeature { static let screenshot = Feature() }
    struct Feature { var isAvailable = true }
    enum ScreenshotSelectionController { struct Capture {} }
    enum ScreenshotRenderer {
        struct Export { let image = 0; let scale = 1.0 }
        static func pngData(from image: Int, scale: Double) -> Data? { Data([1, 2, 3]) }
    }
    typealias ScreenshotEditorController = Editor
    class EditorState {
        struct ClipboardPayload: Sendable { let png: Data? }
        static func clipboardPayload(from export: ScreenshotRenderer.Export,
                                     png: Data? = Data([1, 2, 3])) -> ClipboardPayload {
            ClipboardPayload(png: png)
        }
        static func copyFile(_ url: URL, payload: ClipboardPayload? = nil) -> Bool {
            copiedURL = acceptsCopy ? url : nil
            return acceptsCopy
        }
    }
    class State {
        let strings = Strings()
        struct Strings { let fileNamePrefix = "Screenshot" }
        var autoCopyTask: Task<Void, Never>?
        var autoCopyGeneration = 0
        static func flatten(_ capture: ScreenshotSelectionController.Capture,
                            downscaleTo1x: Bool) -> ScreenshotRenderer.Export? { .init() }
    }

    static func run(_ suite: TestSuite) {
        defaults.removePersistentDomain(forName: domain)
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? Foundation.FileManager.default.removeItem(at: root)
            copiedURL = nil
            acceptsCopy = true
        }
        defaults.set("Obsidian-%year-%mo-%d", forKey: DefaultsKey.screenshotFileNamePattern)
        defaults.set(7, forKey: DefaultsKey.screenshotFileNumberNext)

        func copy(automatic: Bool, cancel: Bool = false) {
            copiedURL = nil
            if automatic {
                let service = Service()
                service.autoCopy(.init())
                if cancel { service.autoCopyTask?.cancel() }
                var finished = false
                let task = service.autoCopyTask
                Task { @MainActor in
                    await task?.value
                    finished = true
                }
                let deadline = Date().addingTimeInterval(5)
                while !finished && Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.005))
                }
                suite.expect(finished, "automatic copy finishes")
                withExtendedLifetime(service) {}
            } else {
                let ok = Editor.copyImage(.init(), fileNamePrefix: "Screenshot")
                suite.expect(ok == acceptsCopy, "manual copy reports clipboard delivery")
            }
        }

        for automatic in [false, true] {
            copy(automatic: automatic)
            suite.expect(copiedURL?.lastPathComponent.hasPrefix("Obsidian-") == true,
                         "\(automatic ? "automatic" : "manual") copy uses the configured file name")
            suite.expect(copiedURL.flatMap { try? Data(contentsOf: $0) } == Data([1, 2, 3]),
                         "the configured name points to the copied image payload")
            suite.expect(defaults.integer(forKey: DefaultsKey.screenshotFileNumberNext) == 7,
                         "date-only copies do not consume the number sequence")
        }

        defaults.set("Shot-%###", forKey: DefaultsKey.screenshotFileNamePattern)
        for (index, automatic) in [false, true].enumerated() {
            copy(automatic: automatic)
            suite.expect(copiedURL?.lastPathComponent == "Shot-00\(7 + index).png",
                         "manual and automatic copies expand padded numbers")
            suite.expect(defaults.integer(forKey: DefaultsKey.screenshotFileNumberNext) == 8 + index,
                         "a successful copy consumes exactly one number")
        }
        acceptsCopy = false
        for automatic in [false, true] {
            copy(automatic: automatic)
            suite.expect(copiedURL == nil
                         && defaults.integer(forKey: DefaultsKey.screenshotFileNumberNext) == 9,
                         "failed clipboard delivery returns the reserved number")
        }
        acceptsCopy = true
        copy(automatic: true, cancel: true)
        suite.expect(copiedURL == nil
                     && defaults.integer(forKey: DefaultsKey.screenshotFileNumberNext) == 9,
                     "cancelling automatic copy returns its unused number")

        let first = ScreenshotSupport.nextFileName(prefix: "Screenshot", defaults: defaults)
        let second = ScreenshotSupport.nextFileName(prefix: "Screenshot", defaults: defaults)
        ScreenshotSupport.rewindNumberSequence(toReuse: first.consumedNumber!, defaults: defaults)
        suite.expect(second.name == "Shot-010.png"
                     && defaults.integer(forKey: DefaultsKey.screenshotFileNumberNext) == 11,
                     "an older failure cannot rewind a later output's reservation")

        defaults.set("Same name", forKey: DefaultsKey.screenshotFileNamePattern)
        for automatic in [false, true] {
            copy(automatic: automatic)
            let firstURL = copiedURL
            copy(automatic: automatic)
            suite.expect(firstURL?.lastPathComponent == "Same name.png"
                         && copiedURL?.lastPathComponent == "Same name 2.png"
                         && firstURL.flatMap { try? Data(contentsOf: $0) } == Data([1, 2, 3]),
                         "repeated names preserve the earlier clipboard file")
        }

        defaults.set(" \n ", forKey: DefaultsKey.screenshotFileNamePattern)
        for automatic in [false, true] {
            copy(automatic: automatic)
            suite.expect(copiedURL?.lastPathComponent.hasPrefix("Screenshot ") == true,
                         "a blank pattern retains the localized default name")
        }
        let fixedDate = Calendar(identifier: .gregorian).date(from:
            DateComponents(year: 2026, month: 9, day: 25, hour: 10, minute: 30, second: 45))!
        defaults.set("  %year-%mo-%d_%h:%mi:%s/笔记  ", forKey: DefaultsKey.screenshotFileNamePattern)
        suite.expect(ScreenshotSupport.nextFileName(prefix: "Screenshot", date: fixedDate,
                                                   defaults: defaults).name
                     == "2026-09-25_10-30-45-笔记.png",
                     "copy and save naming expands date tokens and sanitizes separators")
    }
}
