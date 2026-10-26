// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum ScratchpadClipboardTests {
    final class Collector { func stop() {} }
    final class Service {
        var store: ScratchpadStore
        var document: ScratchpadDocument?
        let ioQueue = DispatchQueue(label: "ScratchpadClipboardTests.store")
        var pendingSave: DispatchWorkItem?
        var hasLoaded = true
        var saveFailed = false
        var clipboardCollectionTarget: UUID?
        var clipboardCollector: Collector? = Collector()
        var collectionPreviousPin = false
        var isPinned = true
        var selectedPadID: UUID?
        var text = ""
        var isReplacingText = false
        var isCollectingClipboard: Bool { clipboardCollectionTarget != nil }
        init(store: ScratchpadStore, document: ScratchpadDocument) {
            self.store = store
            self.document = document
            clipboardCollectionTarget = document.selectedID
        }
        func publishNotes(_ document: ScratchpadDocument) {}
        func focusText() {}
    }

    static func run(_ suite: TestSuite) {
        persistence(suite)
        capture(suite)
    }

    private static func persistence(_ suite: TestSuite) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "com.vorssaint.tests.scratchpad-clipboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: domain) }
        do {
            var store = ScratchpadStore(directoryURL: directory, defaults: defaults)
            var initial = try store.load(defaultName: "Notes", retention: .never, now: Date())
            let first = initial.selectedID
            initial.updateSelectedText("Keep this note", modifiedAt: Date())
            initial = initial.addingPad(defaultName: "Second")!
            let second = initial.selectedID
            initial = initial.selecting(first)!
            for trash in [false, true] {
                _ = store.save(initial)
                let service = Service(store: store, document: initial)
                if trash { service.changeDocument { $0.trash(first, now: Date(), defaultName: "Notes") } }
                else { service.selectPad(second) }
                var reopened = service.store
                let disk = try reopened.load(defaultName: "Notes", retention: .never, now: Date())
                suite.expect(disk == service.document && !service.isCollectingClipboard,
                             "stopping collection during \(trash ? "Trash" : "selection") preserves the committed document on disk")
            }
        } catch { suite.expect(false, "collection persistence fixture: \(error)") }
    }

    private static func capture(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.scratchpad-collector.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.set(["test.ignored"], forKey: DefaultsKey.clipboardHistoryIgnoredApps)
        defaults.set(true, forKey: DefaultsKey.clipboardHistoryFilterSensitiveText)
        let board = NSPasteboard.withUniqueName()
        var deadline: (() -> Void)?
        let lane = GeneralPasteboardAccess(label: domain, scheduleDeadline: { _, action in
            deadline = action
            return {}
        })
        var reads = 0
        let collector = ScratchpadClipboardCollector(pasteboard: { reads += 1; return board },
                                                     access: lane, defaults: defaults)
        func wait(_ condition: () -> Bool) {
            let end = Date().addingTimeInterval(2)
            while !condition(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            suite.expect(condition(), "the isolated pasteboard operation completes")
        }
        func drain() {
            var done = false
            lane.async({ true }, then: { _ in done = true })
            wait { done }
        }
        func write(_ text: String, marker: String? = nil, source: String? = nil) {
            var done = false
            lane.async({
                board.clearContents()
                if let marker { board.setData(Data(), forType: .init(marker)) }
                if let source { board.setString(source, forType: .source) }
                board.setString(text, forType: .string)
            }, then: { _ in done = true })
            wait { done }
        }
        var received: [String] = []
        var allow = true
        var ownUI = false
        func start() {
            collector.start(ownUIActive: { ownUI }, receive: {
                if allow { received.append($0) }
                return allow
            })
        }
        defer {
            collector.stop()
            lane.async { board.releaseGlobally() }
            drain()
            defaults.removePersistentDomain(forName: domain)
        }
        collector.poll()
        drain()
        suite.expect(reads == 0, "inactive collection performs no pasteboard reads")
        write("Already on the clipboard")
        start()
        drain()
        suite.expect(received.isEmpty, "start establishes a baseline without collecting existing text")
        write(" first 🙂 ")
        collector.poll(); drain()
        suite.expect(received == [" first 🙂 "], "new text is delivered without altering whitespace or Unicode")
        write(" first 🙂 ")
        collector.poll(); drain()
        suite.expect(received.count == 1, "consecutive copies of identical text are not duplicated")
        for marker in [ClipboardHistorySensitiveText.concealedPasteboardType,
                       "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
                       NSPasteboard.PasteboardType.fileURL.rawValue, NSPasteboard.PasteboardType.png.rawValue] {
            write("Do not capture \(marker)", marker: marker)
            collector.poll(); drain()
        }
        write("Ignored app", source: "test.ignored")
        collector.poll(); drain()
        write("password=secret-value")
        collector.poll(); drain()
        suite.expect(received.count == 1, "concealed, temporary, rich-content, ignored-app and sensitive copies are excluded")
        ownUI = true
        write("Copied in our own editor")
        collector.poll(); drain()
        ownUI = false
        collector.poll(); drain()
        suite.expect(received.count == 1, "copies from the app's own UI are excluded")
        allow = false
        write("After composition")
        collector.poll(); drain()
        allow = true
        collector.poll(); drain()
        suite.expect(received.last == "After composition", "declined delivery is retried without consuming the copy")

        write("Late old session")
        let readsBefore = reads
        let release = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        lane.async { entered.signal(); release.wait() }
        suite.expect(entered.wait(timeout: .now() + 2) == .success, "the test read lane is blocked")
        collector.poll()
        deadline?()
        for _ in 0..<20 { collector.stop(); start(); collector.poll() }
        release.signal()
        drain()
        suite.expect(reads <= readsBefore + 1, "repeated restarts never queue a second blocked read")
        let before = received.count
        collector.poll(); drain()
        suite.expect(received.count == before, "expired work and stop/restart cannot deliver an old copy into the new session")
        write("New session")
        collector.poll(); drain()
        suite.expect(received.last == "New session", "a restarted collector establishes a fresh baseline and accepts later copies")
        write("Pending at stop")
        let releasePending = DispatchSemaphore(value: 0)
        let enteredPending = DispatchSemaphore(value: 0)
        lane.async { enteredPending.signal(); releasePending.wait() }
        suite.expect(enteredPending.wait(timeout: .now() + 2) == .success, "the pending delivery is held")
        collector.poll()
        collector.stop()
        let count = received.count
        releasePending.signal()
        drain()
        suite.expect(received.count == count, "a read already queued at stop cannot append afterwards")
        write("After stop")
        collector.poll(); drain()
        suite.expect(received.count == count, "stopping prevents further delivery")
    }
}
