// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// AppKit restricts its real receive method to a live drag destination callback.
/// This receiver supplies those callbacks on the requested queue; the transfer,
/// coordinated-reader copy boundary, filesystem and cancellation code are real.
enum ShelfFilePromiseTests {
    final class Receiver: NSFilePromiseReceiver {
        let names: [String]
        private(set) var destination: URL?
        private var reader: ((URL, Error?) -> Void)?
        private var queue: OperationQueue?
        var finishDuringReceive = false
        override var fileTypes: [String] { ["public.data"] }
        override var fileNames: [String] { destination == nil ? [] : names }
        init(_ names: [String]) { self.names = names; super.init() }
        required init?(pasteboardPropertyList: Any, ofType: NSPasteboard.PasteboardType) { return nil }
        override func receivePromisedFiles(atDestination destinationDir: URL,
                                           options: [AnyHashable: Any] = [:],
                                           operationQueue: OperationQueue,
                                           reader: @escaping (URL, Error?) -> Void) {
            destination = destinationDir
            queue = operationQueue
            self.reader = reader
            if finishDuringReceive { send(0); drain() }
        }
        func send(_ index: Int, text: String = "complete", error: Error? = nil, url: URL? = nil) {
            let destination = url ?? destination!.appendingPathComponent(names[index])
            queue!.addOperation { [reader] in
                if error == nil, url == nil { try! Data(text.utf8).write(to: destination) }
                reader?(destination, error)
            }
        }
        func drain() { queue?.waitUntilAllOperationsAreFinished() }
    }

    static func run(expect: @escaping (Bool, String) -> Void) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("vorss-promise-tests-\(UUID())")
        defer { try? fm.removeItem(at: root) }
        func fixture(_ name: String) -> (URL, URL) {
            let incoming = root.appendingPathComponent(name + "/incoming")
            let store = root.appendingPathComponent(name + "/store")
            return (incoming, store)
        }
        func pump() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        func settle(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(3)
            while !condition() && Date() < deadline { pump() }
            expect(condition(), "file promise completion arrives without a polling timer")
        }
        func entries(_ url: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        }
        do {
            let (incoming, store) = fixture("completion")
            var result: ShelfFilePromiseTransfer.Result?
            let transfer = ShelfFilePromiseTransfer(temporaryDirectory: incoming, storeDirectory: store) { result = $0 }!
            let receiver = Receiver(["  attachment.txt  "])
            transfer.receive([receiver])
            let partial = receiver.destination!.appendingPathComponent(receiver.names[0])
            try Data("first byte".utf8).write(to: partial)
            let pauseEnd = Date().addingTimeInterval(0.25)
            while Date() < pauseEnd { pump() }
            expect(result == nil && entries(store).isEmpty, "a paused, unfinished save never becomes a shelf file")
            receiver.send(0, text: "all bytes")
            settle { result != nil }
            expect(result?.failed == false && result?.urls.count == 1, "a confirmed complete file is delivered once")
            let saved = result!.urls[0]
            expect(saved.lastPathComponent == "  attachment.txt  ", "original spaces in the filename survive")
            expect(try String(contentsOf: saved, encoding: .utf8) == "all bytes", "the shelf copy contains the completed bytes")
            receiver.drain()
            expect(entries(incoming).isEmpty, "completed incoming files are removed")
            expect(ShelfPersistenceSupport.containsKeptFile(under: saved.deletingLastPathComponent().path,
                                                          keptPaths: [saved.path]), "startup keeps the parent of a stored attachment")
            expect(!ShelfPersistenceSupport.containsKeptFile(under: store.appendingPathComponent("other").path,
                                                           keptPaths: [saved.path]), "startup can remove an unreferenced sibling directory")
            let mode = try fm.attributesOfItem(atPath: saved.deletingLastPathComponent().path)[.posixPermissions] as! NSNumber
            expect(mode.intValue & 0o777 == 0o700, "stored attachments have an owner-only parent")
        } catch { expect(false, "file promise completion fixture failed: \(error)") }

        do {
            let (incoming, store) = fixture("same-names")
            var result: ShelfFilePromiseTransfer.Result?
            let transfer = ShelfFilePromiseTransfer(temporaryDirectory: incoming, storeDirectory: store) { result = $0 }!
            let receiver = Receiver(["same.txt", "same.txt", "last.txt"])
            transfer.receive([receiver])
            receiver.send(0, text: "first")
            receiver.drain(); pump()
            expect(result == nil, "one advertised file type does not truncate a legacy batch")
            receiver.send(1, text: "second")
            receiver.send(2, text: "third")
            settle { result != nil }
            let urls = result!.urls
            expect(urls.count == 3 && Set(urls).count == 3, "repeated names have separate destinations without a crash")
            expect(try urls.map { try String(contentsOf: $0, encoding: .utf8) } == ["first", "second", "third"],
                   "each same-name callback is copied inside its reader before the source replaces it")
            receiver.drain()
            expect(entries(incoming).isEmpty, "multi-file incoming directory is cleaned after all callbacks")
        } catch { expect(false, "duplicate-name fixture failed: \(error)") }

        let (incoming, store) = fixture("cancel")
        var cancelledResults = 0
        let transfer = ShelfFilePromiseTransfer(temporaryDirectory: incoming, storeDirectory: store) { _ in cancelledResults += 1 }!
        let receiver = Receiver(["one.txt", "two.txt"])
        transfer.receive([receiver])
        receiver.send(0)
        receiver.drain()
        transfer.cancel()
        receiver.send(1)
        receiver.drain(); pump()
        expect(cancelledResults == 0, "cancellation never publishes a partial or late delivery")
        expect(entries(store).isEmpty && entries(incoming).isEmpty, "cancellation removes copies and eventual incoming files")

        let (queuedIncoming, queuedStore) = fixture("cancel-queued")
        var queuedResults = 0
        let queuedTransfer = ShelfFilePromiseTransfer(temporaryDirectory: queuedIncoming, storeDirectory: queuedStore) { _ in queuedResults += 1 }!
        let queuedReceiver = Receiver(["queued.txt"])
        queuedTransfer.receive([queuedReceiver])
        queuedReceiver.send(0)
        queuedReceiver.drain()
        queuedTransfer.cancel(); pump(); queuedReceiver.drain()
        expect(queuedResults == 0 && entries(queuedStore).isEmpty, "cancel wins over an already queued main-thread completion")

        let (errorIncoming, errorStore) = fixture("errors")
        var failed: ShelfFilePromiseTransfer.Result?
        let failedTransfer = ShelfFilePromiseTransfer(temporaryDirectory: errorIncoming, storeDirectory: errorStore) { failed = $0 }!
        let failedReceiver = Receiver(["good.txt", "failed.txt"])
        failedTransfer.receive([failedReceiver])
        failedReceiver.send(0)
        failedReceiver.send(1, error: CocoaError(.fileWriteUnknown), url: root)
        settle { failed != nil }
        expect(failed!.failed && failed!.urls.count == 1, "a failed native callback preserves successful files and reports failure")
        expect(fm.fileExists(atPath: root.path), "the URL accompanying an error is ignored")
        failedReceiver.drain()

        do {
            let outside = root.appendingPathComponent("outside.txt")
            try Data("keep me".utf8).write(to: outside)
            let (unsafeIncoming, unsafeStore) = fixture("outside")
            var unsafe: ShelfFilePromiseTransfer.Result?
            let transfer = ShelfFilePromiseTransfer(temporaryDirectory: unsafeIncoming, storeDirectory: unsafeStore) { unsafe = $0 }!
            let receiver = Receiver(["unsafe.txt"])
            transfer.receive([receiver])
            receiver.send(0, url: outside)
            settle { unsafe != nil }
            expect(unsafe!.failed && unsafe!.urls.isEmpty, "a promised URL outside its private destination is rejected")
            ShelfFilePromiseTransfer.discard([outside, store], in: store)
            expect(try String(contentsOf: outside, encoding: .utf8) == "keep me", "cleanup never deletes a caller-supplied outside path")
            receiver.drain()
        } catch { expect(false, "path containment fixture failed: \(error)") }

        let (batchIncoming, batchStore) = fixture("reverse-order")
        var batch: ShelfFilePromiseTransfer.Result?
        let batchTransfer = ShelfFilePromiseTransfer(temporaryDirectory: batchIncoming, storeDirectory: batchStore) { batch = $0 }!
        let batchReceiver = Receiver(["first.txt", "second.txt"])
        batchTransfer.receive([batchReceiver])
        batchReceiver.send(1); batchReceiver.send(0)
        settle { batch != nil }
        expect(batch!.urls.map(\.lastPathComponent) == ["first.txt", "second.txt"], "source order survives out-of-order completion")
        batchReceiver.drain()

        let (largeIncoming, largeStore) = fixture("over-capacity")
        var oversized = false
        let largeTransfer = ShelfFilePromiseTransfer(temporaryDirectory: largeIncoming, storeDirectory: largeStore,
                                                     maximumFiles: 1) { _ in oversized = true }!
        let largeReceiver = Receiver(["one.txt", "two.txt"])
        expect(!largeTransfer.receive([largeReceiver]), "actual legacy names are checked against capacity before accepting")
        largeReceiver.send(0); largeReceiver.send(1); largeReceiver.drain(); pump()
        expect(!oversized && entries(largeIncoming).isEmpty && entries(largeStore).isEmpty,
               "over-capacity receipts are cleaned without adding files")

        do {
            let (partialIncoming, partialStore) = fixture("partial-error")
            var partialFailure: ShelfFilePromiseTransfer.Result?
            let transfer = ShelfFilePromiseTransfer(temporaryDirectory: partialIncoming, storeDirectory: partialStore) { partialFailure = $0 }!
            let receiver = Receiver(["partial.txt"])
            transfer.receive([receiver])
            let partial = receiver.destination!.appendingPathComponent("partial.txt")
            try Data("incomplete".utf8).write(to: partial)
            receiver.send(0, error: CocoaError(.fileWriteUnknown), url: partial)
            settle { partialFailure != nil }
            expect(partialFailure!.failed && partialFailure!.urls.isEmpty, "even an existing partial file is ignored when AppKit reports failure")
            receiver.drain()

            let (directoryIncoming, directoryStore) = fixture("directory")
            var directoryResult: ShelfFilePromiseTransfer.Result?
            let directoryTransfer = ShelfFilePromiseTransfer(temporaryDirectory: directoryIncoming, storeDirectory: directoryStore) { directoryResult = $0 }!
            let directoryReceiver = Receiver(["folder"])
            directoryTransfer.receive([directoryReceiver])
            let directory = directoryReceiver.destination!.appendingPathComponent("folder")
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("nested".utf8).write(to: directory.appendingPathComponent("child.txt"))
            directoryReceiver.send(0, url: directory)
            settle { directoryResult != nil }
            expect(try String(contentsOf: directoryResult!.urls[0].appendingPathComponent("child.txt"), encoding: .utf8) == "nested",
                   "a completed promised directory is copied with its contents")
            directoryReceiver.drain()

            let (linkIncoming, linkStore) = fixture("symbolic-link")
            var linkResult: ShelfFilePromiseTransfer.Result?
            let linkTransfer = ShelfFilePromiseTransfer(temporaryDirectory: linkIncoming, storeDirectory: linkStore) { linkResult = $0 }!
            let linkReceiver = Receiver(["link"])
            linkTransfer.receive([linkReceiver])
            let link = linkReceiver.destination!.appendingPathComponent("link")
            try fm.createSymbolicLink(at: link, withDestinationURL: root)
            linkReceiver.send(0, url: link)
            settle { linkResult != nil }
            expect(linkResult!.failed && linkResult!.urls.isEmpty && fm.fileExists(atPath: root.path),
                   "a promised symlink cannot redirect copying or cleanup outside the incoming directory")
            linkReceiver.drain()
        } catch { expect(false, "failed-file and directory fixtures failed: \(error)") }

        let (earlyIncoming, earlyStore) = fixture("early-callback")
        var earlyResult: ShelfFilePromiseTransfer.Result?
        let earlyTransfer = ShelfFilePromiseTransfer(temporaryDirectory: earlyIncoming, storeDirectory: earlyStore) { earlyResult = $0 }!
        let earlyReceiver = Receiver(["early.txt"])
        earlyReceiver.finishDuringReceive = true
        earlyTransfer.receive([earlyReceiver])
        settle { earlyResult != nil }
        expect(earlyResult!.urls.count == 1 && !earlyResult!.failed,
               "a reader that finishes before receive returns cannot outrun initialization")
        earlyReceiver.drain()

        for language in AppLanguage.allCases {
            let strings = Mirror(reflecting: ShelfPromiseDeliveryStrings.localized(language)).children
                .compactMap { $0.value as? String }
            expect(!strings.isEmpty && strings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "file promise messages are complete in \(language.rawValue)")
        }
    }
}
