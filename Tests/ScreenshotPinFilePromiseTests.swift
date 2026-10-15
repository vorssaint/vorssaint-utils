// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO

enum ScreenshotPinFilePromiseTests {
    @MainActor static func run(_ suite: TestSuite, image: CGImage) {
        weak var releasedPin: ScreenshotPinWindow?
        let provider: NSFilePromiseProvider = autoreleasepool {
            let pin = ScreenshotPinWindow(image: image, scale: 2)
            releasedPin = pin
            let provider = ScreenshotPinFilePromise.make(image: pin.image, scale: pin.captureScale, fileName: "Original.png")
            pin.closePin()
            return provider
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        suite.expect(releasedPin == nil, "the file promise does not retain a closed pin")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("Original.png")
            var completed = false
            var failure: Error?
            provider.delegate?.filePromiseProvider(provider, writePromiseTo: url) { error in
                completed = true
                failure = error
            }
            suite.expect(completed && failure == nil, "native file promise completes a real PNG export")
            let decoded = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            suite.expect(decoded?.width == 400 && decoded?.height == 200,
                         "promised PNG keeps full original pixels regardless of pin display size")
            let originalData = try Data(contentsOf: url)
            provider.delegate?.filePromiseProvider(provider, writePromiseTo: url) { error in failure = error }
            let retainedData = try Data(contentsOf: url)
            suite.expect(failure != nil && retainedData == originalData,
                         "a promised file never overwrites an existing destination file")
            completed = false
            provider.delegate?.filePromiseProvider(provider, writePromiseTo: folder.appendingPathComponent("missing/file.png")) { error in
                completed = true
                failure = error
            }
            suite.expect(completed && failure != nil, "promise write errors are delivered to the destination")
        } catch { suite.expect(false, "file promise fixture failed: \(error)") }
    }
}
