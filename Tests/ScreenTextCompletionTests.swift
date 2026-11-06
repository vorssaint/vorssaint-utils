// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production OCR entry points and completion with controlled queues.
/// Vision, feature preferences and the clipboard are local fakes; no user data
/// or system pasteboard is touched.
enum ScreenTextCompletionTests {
    typealias CGImage = Int
    enum BarcodeDetector { typealias Reading = String }
    enum ScreenshotSelectionController {
        struct Capture { let image: CGImage }
    }

    final class Queue {
        var pending: [() -> Void] = []
        func async(execute work: @escaping () -> Void) { pending.append(work) }
        func drain() {
            let work = pending
            pending = []
            work.forEach { $0() }
        }
    }
    enum DispatchQueue {
        enum QoS { case userInitiated }
        static var main = Queue()
        static var background = Queue()
        static func global(qos: QoS) -> Queue { background }
    }
    enum AppFeature {
        case screenOCR
        static var available = true
        var isAvailable: Bool { Self.available }
    }
    struct UserDefaults {
        static let standard = Self()
        static var values: [String: Bool] = [:]
        func bool(forKey key: String) -> Bool { Self.values[key] ?? false }
    }
    struct L10n {
        static let shared = Self()
        struct Language { let rawValue = "en-US" }
        struct Strings { let ocrCopied = "copied"; let ocrNoText = "empty" }
        let language = Language()
        let s = Strings()
    }
    enum MediaSupport {
        static func recognitionLanguages(for language: String) -> [String] { [language] }
    }
    final class NSPasteboard {
        static let general = NSPasteboard()
        var changeCount = 0
        var value = "original"
        func write(_ value: String) { self.value = value; changeCount += 1 }
    }
    enum QuickToolHUD {
        static var messages: [String] = []
        static func show(icon: String, message: String) { messages.append(message) }
    }
    final class QRResultController {
        static let shared = QRResultController()
        var readings: [String] = []
        func show(reading: String) { readings.append(reading) }
    }
    class State {
        var recognitionGeneration = 0
        static var outcomes: [Int: ScreenTextService.Outcome] = [:]
        static var requests: [(image: Int, qr: Bool, joinLines: Bool, languages: [String])] = []
        /// Stands in for the area bound: maps an oversized capture to the
        /// smaller image Vision should read, and records every image bounded.
        static var scaledImages: [Int: Int] = [:]
        static var boundedImages: [Int] = []
        static func recognitionImage(_ image: Int) -> Int {
            boundedImages.append(image)
            return scaledImages[image] ?? image
        }
        static func outcome(for image: Int, detectQRCodes: Bool, removeLineBreaks: Bool,
                            fallbackLanguages: [String]) -> ScreenTextService.Outcome {
            requests.append((image, detectQRCodes, removeLineBreaks, fallbackLanguages))
            return outcomes[image] ?? .text("capture \(image)")
        }
        static func copyToPasteboard(_ value: String) { NSPasteboard.general.write(value) }
    }

    static func reset() {
        DispatchQueue.main = Queue()
        DispatchQueue.background = Queue()
        AppFeature.available = true
        UserDefaults.values = [DefaultsKey.screenOCRDetectQRCodes: true,
                               DefaultsKey.screenOCRRemoveLineBreaks: true]
        NSPasteboard.general.value = "original"
        NSPasteboard.general.changeCount = 0
        QuickToolHUD.messages = []
        QRResultController.shared.readings = []
        State.outcomes = [:]
        State.requests = []
        State.scaledImages = [:]
        State.boundedImages = []
    }

    static func finish() {
        DispatchQueue.background.drain()
        DispatchQueue.main.drain()
    }

    static func run(_ suite: TestSuite) {
        defer { reset() }
        reset()
        let normal = ScreenTextService()
        normal.copyText(from: 42)
        suite.expect(NSPasteboard.general.value == "original" && State.requests.isEmpty,
                     "preview OCR does not block or copy before background recognition")
        finish()
        suite.expect(NSPasteboard.general.value == "capture 42" && QuickToolHUD.messages == ["copied"],
                     "an unchanged clipboard receives the recognized text and success feedback")
        suite.expect(State.requests.count == 1 && State.requests[0].image == 42
                     && !State.requests[0].qr && State.requests[0].joinLines
                     && State.requests[0].languages == ["en-US"],
                     "preview OCR uses the captured image and language/line preferences, bypassing QR")

        reset()
        State.scaledImages[60] = 24
        let oversized = ScreenTextService()
        oversized.copyText(from: 60)
        suite.expect(State.boundedImages.isEmpty,
                     "an oversized capture is not scaled on the main thread")
        finish()
        suite.expect(State.boundedImages == [60] && State.requests.map { $0.image } == [24]
                     && NSPasteboard.general.value == "capture 24",
                     "an oversized capture is scaled to the recognition bound before Vision reads it")

        for duringRecognition in [true, false] {
            reset()
            let service = ScreenTextService()
            service.copyText(from: 1)
            if !duringRecognition { DispatchQueue.background.drain() }
            NSPasteboard.general.write("newer user copy")
            finish()
            suite.expect(NSPasteboard.general.value == "newer user copy" && QuickToolHUD.messages.isEmpty,
                         "OCR preserves a newer copy made before or after recognition finishes")
        }

        reset()
        AppFeature.available = false
        let disabled = ScreenTextService()
        disabled.copyText(from: 1)
        disabled.receiveUnifiedCapture(.init(image: 2))
        suite.expect(DispatchQueue.background.pending.isEmpty,
                     "disabled OCR cannot start from the preview or unified capture")

        for resync in [false, true] {
            reset()
            let service = ScreenTextService()
            service.copyText(from: 1)
            DispatchQueue.background.drain()
            AppFeature.available = false
            if resync {
                service.syncWithPreferences()
                AppFeature.available = true
            }
            finish()
            suite.expect(NSPasteboard.general.value == "original" && QuickToolHUD.messages.isEmpty,
                         "turning OCR off suppresses pending results, including after reinstall")
        }

        reset()
        let suspended = ScreenTextService()
        suspended.copyText(from: 1)
        suspended.suspend()
        finish()
        suite.expect(NSPasteboard.general.value == "original" && QuickToolHUD.messages.isEmpty,
                     "suspending OCR suppresses a pending preview result")

        for newestFirst in [false, true] {
            reset()
            let latest = ScreenTextService()
            latest.copyText(from: 1)
            latest.copyText(from: 2)
            if newestFirst { DispatchQueue.background.pending.reverse() }
            finish()
            suite.expect(NSPasteboard.general.value == "capture 2" && QuickToolHUD.messages == ["copied"],
                         "only the latest OCR request copies, with newestFirst=\(newestFirst)")
        }

        for detectQR in [false, true] {
            for joinLines in [false, true] {
                for preview in [false, true] {
                    reset()
                    UserDefaults.values = [DefaultsKey.screenOCRDetectQRCodes: detectQR,
                                           DefaultsKey.screenOCRRemoveLineBreaks: joinLines]
                    let service = ScreenTextService()
                    if preview { service.copyText(from: 7) }
                    else { service.receiveUnifiedCapture(.init(image: 7)) }
                    finish()
                    suite.expect(State.requests.count == 1
                                 && State.requests[0].qr == (preview ? false : detectQR)
                                 && State.requests[0].joinLines == joinLines,
                                 "OCR respects QR=\(detectQR), joinLines=\(joinLines), preview=\(preview)")
                    suite.expect(NSPasteboard.general.value == "capture 7",
                                 "both entry points still copy text with each preference combination")
                }
            }
        }

        reset()
        State.outcomes[1] = .empty
        let empty = ScreenTextService()
        empty.copyText(from: 1)
        finish()
        suite.expect(NSPasteboard.general.value == "original" && QuickToolHUD.messages == ["empty"],
                     "no text leaves the clipboard intact and reports the empty result")

        reset()
        State.outcomes[1] = .qr("https://example.com")
        let unified = ScreenTextService()
        unified.receiveUnifiedCapture(.init(image: 1))
        finish()
        suite.expect(State.requests.first?.qr == true
                     && QRResultController.shared.readings == ["https://example.com"]
                     && NSPasteboard.general.value == "original",
                     "unified OCR still honors QR detection and presents its result without copying")
    }
}
