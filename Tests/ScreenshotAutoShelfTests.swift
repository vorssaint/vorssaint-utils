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
        static var available = true
        var isAvailable: Bool { Self.available }
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

    /// Hold the actual detached work so completion order is deterministic,
    /// including when a task is cancelled while its encoder is still busy.
    final class EncodingControl: @unchecked Sendable {
        private let condition = NSCondition()
        private var held: Set<Int> = []
        private var started: Set<Int> = []
        private var failed: Set<Int> = []

        func reset() {
            condition.lock()
            held.removeAll()
            started.removeAll()
            failed.removeAll()
            condition.broadcast()
            condition.unlock()
        }

        func hold(_ image: Int) {
            condition.lock()
            held.insert(image)
            condition.unlock()
        }

        func release(_ image: Int) {
            condition.lock()
            held.remove(image)
            condition.broadcast()
            condition.unlock()
        }

        func fail(_ image: Int) {
            condition.lock()
            failed.insert(image)
            condition.unlock()
        }

        func hasStarted(_ image: Int) -> Bool {
            condition.lock()
            defer { condition.unlock() }
            return started.contains(image)
        }

        func data(for image: Int) -> Data? {
            condition.lock()
            started.insert(image)
            while held.contains(image) { condition.wait() }
            let shouldFail = failed.contains(image)
            condition.unlock()
            return shouldFail ? nil : Data([UInt8(image)])
        }
    }

    enum ScreenshotRenderer {
        static let control = EncodingControl()
        static func pngData(from image: Int, scale: CGFloat) -> Data? { control.data(for: image) }
    }

    final class ShelfService {
        static let shared = ShelfService()
        var accepts = true
        var generated: [Data] = []
        var names: [String] = []
        var removed: [UUID] = []
        var items: [UUID: Data] = [:]

        func shelveGeneratedFile(_ data: Data, named name: String) -> UUID? {
            guard accepts else { return nil }
            generated.append(data)
            names.append(name)
            let id = UUID()
            items[id] = data
            return id
        }

        func removeItem(_ id: UUID) {
            removed.append(id)
            items[id] = nil
        }
    }

    @MainActor class State {
        let strings = ScreenshotFeatureStrings.enUS
        var latestCaptureToken = UUID()
        var autoShelfTasks: [UUID: Task<Void, Never>] = [:]
        var autoShelvedItem: (capture: UUID, item: UUID)?

        nonisolated static func flatten(_ capture: Int, downscaleTo1x: Bool) -> Export? {
            Export(image: capture, scale: 2)
        }

        func settle() async {
            for task in Array(autoShelfTasks.values) { await task.value }
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
        shelf.items = [:]
        shelf.accepts = true
        AppFeature.available = true
        ScreenshotRenderer.control.reset()
        let service = Service()

        ScreenshotSupport.addsCaptures = false
        service.autoShelve(1, saved: nil)
        await service.settle()
        suite.expect(shelf.generated.isEmpty && service.autoShelfTasks.isEmpty && service.autoShelvedItem == nil,
                     "with the option off a capture never reaches the shelf")

        ScreenshotSupport.addsCaptures = true
        service.autoShelve(5, saved: nil)
        suite.expect(!service.autoShelfTasks.isEmpty && shelf.generated.isEmpty,
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
        let pending = service.autoShelfTasks[service.latestCaptureToken]
        service.unshelve(service.latestCaptureToken)
        await pending?.value
        suite.expect(shelf.generated == [Data([5])] && service.autoShelvedItem == nil,
                     "a capture discarded while its copy is still being written never reaches the shelf")

        let control = ScreenshotRenderer.control
        control.hold(7)
        let older = UUID()
        service.latestCaptureToken = older
        service.autoShelve(7, saved: nil)
        let first = service.autoShelfTasks[older]
        suite.expect(await startedEncoding(7), "the first capture reaches its background encoder")
        let newer = UUID()
        service.latestCaptureToken = newer
        service.autoShelve(8, saved: nil)
        await service.autoShelfTasks[newer]?.value
        let newerItem = service.autoShelvedItem?.item
        suite.expect(shelf.generated.last == Data([8]) && service.autoShelfTasks[older] != nil,
                     "a fast second capture reaches the shelf without cancelling the slow first capture")
        control.release(7)
        await first?.value
        suite.expect(Array(shelf.generated.suffix(2)) == [Data([8]), Data([7])]
                && service.autoShelfTasks.isEmpty && service.autoShelvedItem?.item == newerItem,
                     "the earlier capture arrives too without replacing the latest preview's shelf identity")
        let removedBefore = shelf.removed
        service.unshelve(nil)
        suite.expect(shelf.removed == removedBefore && service.autoShelvedItem?.item == newerItem,
                     "a preview reopened from history takes nothing off the shelf")
        service.unshelve(newer)
        suite.expect(newerItem != nil && shelf.removed.last == newerItem
                && Set(shelf.items.values) == [Data([7])],
                     "discarding the newer preview removes only its own item after out-of-order delivery")

        control.hold(9)
        let discardedOlder = UUID()
        service.latestCaptureToken = discardedOlder
        service.autoShelve(9, saved: nil)
        let discardedTask = service.autoShelfTasks[discardedOlder]
        suite.expect(await startedEncoding(9), "the older capture is still being encoded at discard")
        service.latestCaptureToken = UUID()
        service.autoShelve(10, saved: nil)
        await service.autoShelfTasks[service.latestCaptureToken]?.value
        let keptItem = service.autoShelvedItem?.item
        service.unshelve(discardedOlder)
        control.release(9)
        await discardedTask?.value
        suite.expect(!shelf.generated.contains(Data([9]))
                && keptItem.flatMap { shelf.items[$0] } == Data([10])
                && service.autoShelvedItem?.item == keptItem && service.autoShelfTasks.isEmpty,
                     "discarding an older pending capture cannot cancel or remove the newer capture")

        control.hold(11)
        service.latestCaptureToken = UUID()
        service.autoShelve(11, saved: nil)
        let keptTask = service.autoShelfTasks[service.latestCaptureToken]
        suite.expect(await startedEncoding(11), "another older capture starts encoding")
        let discardedNewer = UUID()
        service.latestCaptureToken = discardedNewer
        service.autoShelve(12, saved: nil)
        let newerTask = service.autoShelfTasks[discardedNewer]
        service.unshelve(discardedNewer)
        control.release(11)
        await newerTask?.value
        await keptTask?.value
        suite.expect(!shelf.generated.contains(Data([12])) && shelf.generated.contains(Data([11]))
                && service.autoShelfTasks.isEmpty && service.autoShelvedItem == nil,
                     "discarding a newer pending capture preserves the older pending capture")

        let beforeCancellation = shelf.generated
        var cancelledTasks: [Task<Void, Never>] = []
        for capture in [13, 14] {
            if capture == 13 { control.hold(capture) }
            service.latestCaptureToken = UUID()
            service.autoShelve(capture, saved: nil)
            if let task = service.autoShelfTasks[service.latestCaptureToken] { cancelledTasks.append(task) }
            if capture == 13 {
                suite.expect(await startedEncoding(capture), "the first capture starts before feature teardown")
            }
        }
        AppFeature.available = false
        service.cancelAutoShelf()
        AppFeature.available = true
        service.latestCaptureToken = UUID()
        service.autoShelve(18, saved: nil)
        await service.autoShelfTasks[service.latestCaptureToken]?.value
        let restoredItem = service.autoShelvedItem?.item
        control.release(13)
        for task in cancelledTasks { await task.value }
        suite.expect(service.autoShelfTasks.isEmpty && shelf.generated == beforeCancellation + [Data([18])]
                && service.autoShelvedItem?.item == restoredItem,
                     "feature teardown cancels old work even after re-enabling, preserving a new capture and completed items")

        for capture in [15, 16] {
            control.hold(capture)
            service.latestCaptureToken = UUID()
            service.autoShelve(capture, saved: nil)
            suite.expect(await startedEncoding(capture), "capture starts before its availability changes")
            if capture == 15 { ScreenshotSupport.addsCaptures = false }
            else { AppFeature.available = false }
            control.release(capture)
            await service.settle()
            suite.expect(!shelf.generated.contains(Data([UInt8(capture)])) && service.autoShelfTasks.isEmpty,
                         "a pending capture cannot arrive after automatic shelving or the feature is switched off")
            ScreenshotSupport.addsCaptures = true
            AppFeature.available = true
        }

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

        let beforeFailure = shelf.generated
        control.fail(17)
        NSSound.beeps = 0
        service.latestCaptureToken = UUID()
        service.autoShelve(17, saved: nil)
        await service.settle()
        suite.expect(NSSound.beeps == 1 && shelf.generated == beforeFailure
                && service.autoShelfTasks.isEmpty && service.autoShelvedItem == nil,
                     "an encoding failure beeps and leaves no pending task or shelf item")

        shelf.accepts = false
        NSSound.beeps = 0
        service.latestCaptureToken = UUID()
        service.autoShelve(9, saved: nil)
        await service.settle()
        suite.expect(NSSound.beeps == 1 && service.autoShelvedItem == nil
                && service.autoShelfTasks.isEmpty && shelf.generated == beforeFailure,
                     "a shelf that cannot take the capture beeps without retaining a task or item")
        shelf.accepts = true
    }

    @MainActor private static func startedEncoding(_ capture: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while !ScreenshotRenderer.control.hasStarted(capture), Date() < deadline {
            await Task.yield()
        }
        return ScreenshotRenderer.control.hasStarted(capture)
    }
}
