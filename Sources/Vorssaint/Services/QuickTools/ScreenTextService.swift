// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Vision

/// Screen OCR: the user selects an area with the system's own crosshair
/// (the `screencapture` selection UI, Esc cancels), the text in it is
/// recognized offline with Vision and lands on the clipboard. Needs Screen
/// Recording so window contents are actually visible in the capture.
final class ScreenTextService: ObservableObject {
    static let shared = ScreenTextService()

    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 13)
    private var captureInFlight = false

    private init() {
        hotkey.onPress = { [weak self] in self?.capture() }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.screenOCR.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.screenOCRShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.screenOCRShortcut,
                                            fallback: .screenOCRDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut)
    }

    func suspend() {
        hotkey.unregister()
    }

    func capture() {
        guard !captureInFlight else { return }
        captureInFlight = true

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-ocr-\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i interactive selection, -x no sound, -o no window shadow.
        process.arguments = ["-i", "-x", "-o", file.path]
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.captureInFlight = false
                self?.recognize(at: file)
            }
        }
        do {
            try process.run()
        } catch {
            captureInFlight = false
        }
    }

    /// What a captured region turned out to hold.
    enum Outcome: Equatable {
        case qr(BarcodeDetector.Reading)
        case text(String)
        case empty
    }

    private func recognize(at file: URL) {
        // Esc during selection leaves no file; that is a silent cancel.
        guard FileManager.default.fileExists(atPath: file.path) else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                DispatchQueue.main.async {
                    QuickToolHUD.show(icon: "text.viewfinder", message: L10n.shared.s.ocrNoText)
                }
                return
            }

            let outcome = Self.outcome(for: image,
                                       detectQRCodes: UserDefaults.standard.bool(
                                        forKey: DefaultsKey.screenOCRDetectQRCodes))
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
