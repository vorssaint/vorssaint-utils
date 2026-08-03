// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Vision

/// Screen OCR: the user picks an area on the app's own capture surface, the
/// text in it is recognized offline with Vision and lands on the clipboard.
/// Needs Screen Recording, requested contextually on first use.
///
/// The picking and the capture both happen here rather than through the
/// system's capture command. A separate command is judged by macOS on its own
/// standing, which on recent versions can be refused even while this app is
/// allowed, and a refused command writes no file and says nothing: the tool
/// looked dead with no crosshair, no message and nothing to fix (issue #364).
final class ScreenTextService: ObservableObject {
    static let shared = ScreenTextService()

    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 13)
    private var session: ScreenshotSelectionController?

    private var captureStrings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(L10n.shared.language)
    }

    private init() {
        hotkey.onPress = { [weak self] in self?.capture() }
    }

    func syncWithPreferences() {
        guard AppFeature.screenOCR.isAvailable else {
            shortcutRegistrationFailed = false
            hotkey.unregister()
            cancelSession()
            return
        }
        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.screenOCRShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.screenOCRShortcut,
                                            fallback: .screenOCRDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut)
    }

    func suspend() {
        hotkey.unregister()
        cancelSession()
    }

    private func cancelSession() {
        session?.cancel()
        session = nil
    }

    func capture() {
        guard session == nil, !ScreenshotSelectionController.isSessionOnScreen else { return }
        guard Permissions.shared.screenRecording else {
            Permissions.shared.requestScreenRecording()
            return
        }
        // The screen is always photographed first here: text has to hold
        // still while it is being framed, and a still also keeps a menu or a
        // tooltip on screen instead of closing it under the pointer.
        let controller = ScreenshotSelectionController(freeze: true,
                                                       includePointer: false,
                                                       showLastRegion: false,
                                                       purpose: L10n.shared.s.ocrName)
        session = controller
        controller.begin { [weak self] outcome in
            guard let self else { return }
            self.session = nil
            switch outcome {
            case .captured(let capture):
                self.recognize(capture.image)
            case .region:
                // Only the recorder asks for geometry; this session never does.
                break
            case .scrollingRegion:
                break
            case .cancelled:
                break
            case .failed:
                QuickToolHUD.show(icon: "text.viewfinder", message: self.captureStrings.captureFailed)
            }
        }
    }

    /// What a captured region turned out to hold.
    enum Outcome: Equatable {
        case qr(BarcodeDetector.Reading)
        case text(String)
        case empty
    }

    private func recognize(_ image: CGImage) {
        let detectQRCodes = UserDefaults.standard.bool(forKey: DefaultsKey.screenOCRDetectQRCodes)
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Self.outcome(for: image, detectQRCodes: detectQRCodes)
            DispatchQueue.main.async {
                let strings = L10n.shared.s
                switch outcome {
                case .qr(let reading):
                    // Show what the code holds instead of copying it blindly;
                    // the panel offers copy and, for a link, open.
                    QRResultController.shared.show(reading: reading)
                case .text(let text):
                    Self.copyToPasteboard(text)
                    QuickToolHUD.show(icon: "text.viewfinder", message: strings.ocrCopied)
                case .empty:
                    QuickToolHUD.show(icon: "text.viewfinder", message: strings.ocrNoText)
                }
            }
        }
    }

    /// Decides what a captured region holds. A QR code wins over the text:
    /// it is the thing the user pointed at, and the scan is a fast pass that
    /// falls through to text recognition when no code is found. Pure enough
    /// to exercise directly on a known image.
    static func outcome(for image: CGImage, detectQRCodes: Bool) -> Outcome {
        if detectQRCodes, let reading = BarcodeDetector.read(image) {
            return .qr(reading)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])

        let lines = (request.results ?? []).compactMap { observation -> QuickToolsSupport.RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return QuickToolsSupport.RecognizedLine(text: candidate.string,
                                                    x: observation.boundingBox.minX,
                                                    y: observation.boundingBox.midY)
        }
        let text = QuickToolsSupport.joinedRecognizedText(lines)
        return text.isEmpty ? .empty : .text(text)
    }

    private static func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
