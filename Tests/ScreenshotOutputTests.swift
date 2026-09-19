// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

final class ScreenshotOutputContract {
    enum ScreenshotSelectionController { typealias Capture = Int }
    struct SaveOutcome { let url: URL; let consumedNumber: Int? }
    enum ScreenshotRenderer {
        struct Export { let image: Int; let scale: Double }
        static var lastScale: Double?
        static func pngData(from image: Int, scale: Double) -> Data? {
            lastScale = scale
            return Data([1, 2, 3])
        }
    }
    enum ScreenshotEditorController {
        static var copied = true
        static var lastScale: Double?
        static func clipboardPayload(from export: ScreenshotRenderer.Export, png: Data) -> Int {
            lastScale = export.scale
            return export.image
        }
        static func copyFile(_ url: URL, payload: Int) -> Bool { copied }
    }
    enum QuickToolHUD { static func show(icon: String, message: String) {} }
    enum NSSound { static func beep() {} }
    struct Strings {
        let savedAndCopiedHUDFormat = "%@"
        let savedHUDFormat = "%@"
    }
    var preview: Int?
    var editors: [Int] = []
    var pendingRecoveryPreviews: [Int] = []
    var scheduled = false
    enum Action { case none }
    func presentPreview(_ capture: Int, defaultAction: Action) { preview = capture }
    func scheduleRecoveryPreview() { scheduled = true }
    let strings = Strings()
    static var destination = URL(fileURLWithPath: "/dev/null/capture.png")
    static var rewound: [Int] = []
    var fallbackCopies = 0
    var fallbackSucceeds = true
    var exportScale = 2.0
    func flatten(_ capture: Int) -> ScreenshotRenderer.Export? {
        ScreenshotRenderer.Export(image: capture, scale: exportScale)
    }
    func copyDirect(_ capture: Int) -> Bool {
        fallbackCopies += 1
        return fallbackSucceeds
    }
    static func saveDestination(strings: Strings) -> (URL, Int?) { (destination, 7) }
    static func rewindNumberSequence(toReuse number: Int) { rewound.append(number) }

    static func run(expect: (Bool, String) -> Void) {
        let service = ScreenshotOutputContract()
        service.preview = 2
        service.recoverFailedCapture(1)
        expect(service.scheduled && service.preview == 2,
               "a delayed failure schedules recovery without replacing the newer history preview")
        service.showNextRecoveryPreview()
        expect(service.preview == 2 && service.pendingRecoveryPreviews == [1],
               "the failed capture waits while a newer preview is visible")
        service.preview = nil
        service.editors = [3]
        service.showNextRecoveryPreview()
        expect(service.preview == nil && service.pendingRecoveryPreviews == [1],
               "recovery also waits while an editor is open")
        service.editors = []
        service.showNextRecoveryPreview()
        expect(service.preview == 1 && service.pendingRecoveryPreviews.isEmpty,
               "the original failed capture remains recoverable after the newer capture closes")
        service.preview = nil
        service.showNextRecoveryPreview()
        expect(service.preview == nil, "recovery is delivered only once")
        destination = URL(fileURLWithPath: "/dev/null/capture.png")
        rewound = []
        let failedSave = service.saveAndCopyDirect(1)
        expect(failedSave?.copied == true && service.fallbackCopies == 1,
               "an unwritable save destination still copies the capture independently")
        expect(failedSave?.outcome == nil, "failed saving never claims that a file was saved")
        expect(rewound == [7], "a failed save restores the consumed filename number")
        service.fallbackSucceeds = false
        expect(service.saveAndCopyDirect(1)?.copied == false,
               "failure of both outputs remains recoverable")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            destination = folder.appendingPathComponent("capture.png")
            ScreenshotEditorController.copied = true
            expect(service.saveAndCopyDirect(1)?.copied == true,
                   "a successful save still copies the saved file")
            expect(ScreenshotRenderer.lastScale == 2 && ScreenshotEditorController.lastScale == 2,
                   "save and clipboard export both preserve Retina scale")
            service.exportScale = 1
            _ = service.saveAndCopyDirect(1)
            expect(ScreenshotRenderer.lastScale == 1 && ScreenshotEditorController.lastScale == 1,
                   "save and clipboard export both preserve downscaled 1x output")
            ScreenshotEditorController.copied = false
            expect(service.saveAndCopyDirect(1)?.copied == false,
                   "a failed clipboard write does not claim copy success")
        } catch {
            expect(false, "screenshot output fixture creation failed")
        }
    }
}
