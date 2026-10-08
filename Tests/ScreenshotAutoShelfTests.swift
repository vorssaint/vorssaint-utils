// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The capture service's own `autoShelve` and `unshelve`, run against a shelf
/// that records what it is handed. A capture goes as a copy prepared off the
/// main thread, from the saved file when there is one, and discarding the
/// capture takes it back, including a copy still on its way.
enum ScreenshotAutoShelfTests {
    enum ScreenshotSelectionController {
        typealias Capture = Int
    }

    enum AppFeature {
        case screenshot
        var isAvailable: Bool { true }
    }

    enum NSSound {
        static var beeps = 0
        static func beep() { beeps += 1 }
    }

    enum ScreenshotSupport {
        static var addsCaptures = true
        static func addsCapturesToShelf() -> Bool { addsCaptures }
        static func fileName(prefix: String, date: Date) -> String { "\(prefix).png" }
    }

    struct Export {
        let image: Int
        let scale: CGFloat
    }

    enum ScreenshotRenderer {
        static func pngData(from image: Int, scale: CGFloat) -> Data? { Data([UInt8(image)]) }
    }

    final class ShelfService {
        static let shared = ShelfService()
        var accepts = true
        var generated: [Data] = []
        var names: [String] = []
        var removed: [UUID] = []

        func shelveGeneratedFile(_ data: Data, named name: String) -> UUID? {
            guard accepts else { return nil }
            generated.append(data)
            names.append(name)
            return UUID()
        }

        func removeItem(_ id: UUID) { removed.append(id) }
    }

    @MainActor class State {
        let strings = ScreenshotFeatureStrings.enUS
        var latestCaptureToken = UUID()
        var autoShelfTask: Task<Void, Never>?
        var autoShelvedItem: (capture: UUID, item: UUID)?

        nonisolated static func flatten(_ capture: Int, downscaleTo1x: Bool) -> Export? {
            Export(image: capture, scale: 2)
        }

        func settle() async {
            await autoShelfTask?.value
        }
    }

    static func run(_ suite: TestSuite) {
        var finished = false
        Task { @MainActor in
            await checks(suite)
            finished = true
        }
        let deadline = Date().addingTimeInterval(10)
        while !finished && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        suite.expect(finished, "automatic shelf checks finish")
    }

    @MainActor static func checks(_ suite: TestSuite) async {
        let shelf = ShelfService.shared
        shelf.generated = []
        shelf.names = []
        shelf.removed = []
        shelf.accepts = true
        let service = Service()

        ScreenshotSupport.addsCaptures = false
        service.autoShelve(1, saved: nil)
        await service.settle()
        suite.expect(shelf.generated.isEmpty && service.autoShelfTask == nil && service.autoShelvedItem == nil,
                     "with the option off a capture never reaches the shelf")

        ScreenshotSupport.addsCaptures = true
        service.autoShelve(5, saved: nil)
        suite.expect(service.autoShelfTask != nil && shelf.generated.isEmpty,
                     "a capture is written for the shelf off the main thread")
        await service.settle()
        suite.expect(shelf.generated == [Data([5])]
                && service.autoShelvedItem?.capture == service.latestCaptureToken,
                     "the copy lands on the shelf once written, claimed by its capture")
        let landed = service.autoShelvedItem?.item
        service.unshelve(service.latestCaptureToken)
        suite.expect(landed != nil && shelf.removed == [landed!] && service.autoShelvedItem == nil,
                     "discarding that capture takes it off the shelf")

        service.latestCaptureToken = UUID()
        service.autoShelve(6, saved: nil)
        let pending = service.autoShelfTask
        service.unshelve(service.latestCaptureToken)
        await pending?.value
        suite.expect(shelf.generated == [Data([5])] && service.autoShelvedItem == nil,
                     "a capture discarded while its copy is still being written never reaches the shelf")

        let older = UUID()
        service.latestCaptureToken = older
        service.autoShelve(7, saved: nil)
        let superseded = service.autoShelfTask
        service.latestCaptureToken = UUID()
        service.autoShelve(8, saved: nil)
        await superseded?.value
        await service.settle()
        let removedBefore = shelf.removed
        service.unshelve(older)
        suite.expect(shelf.generated == [Data([5]), Data([8])]
                && shelf.removed == removedBefore && service.autoShelvedItem != nil,
                     "a newer capture cancels the older copy, and discarding the older one leaves the newer on the shelf")
        service.unshelve(nil)
        suite.expect(shelf.removed == removedBefore && service.autoShelvedItem != nil,
                     "a preview reopened from history takes nothing off the shelf")

        let savedFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorss-auto-shelf-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: savedFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: savedFolder) }
        let savedURL = savedFolder.appendingPathComponent("Bug-7.png")
        try? Data([42]).write(to: savedURL)
        service.latestCaptureToken = UUID()
        service.autoShelve(3, saved: savedURL)
        await service.settle()
        suite.expect(shelf.generated.last == Data([42]) && shelf.names.last == "Bug-7.png",
                     "a saved capture lends the shelf its bytes and name instead of being encoded again")

        shelf.accepts = false
        NSSound.beeps = 0
        service.latestCaptureToken = UUID()
        service.autoShelve(9, saved: nil)
        await service.settle()
        suite.expect(NSSound.beeps == 1 && service.autoShelvedItem == nil,
                     "a shelf that cannot take the capture beeps")
        shelf.accepts = true
    }
}
