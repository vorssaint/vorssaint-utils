// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production clipboard-import routing against a private pasteboard. The
/// general pasteboard is never read or replaced: the extracted service reads
/// `ClipboardImportTests.pasteboard` instead, and every snapshot is written
/// into a fresh unique board the way production does.
enum ClipboardImportTests {
    static let pasteboard = NSPasteboard(name: NSPasteboard.Name("VorssaintClipboardImportTests-" + UUID().uuidString))

    enum AppFeature {
        static var shelf = Feature()
        struct Feature { var isAvailable = true }
    }

    enum UserDefaults {
        static var standard = Store()
        struct Store {
            var shelfEnabled = true
            func bool(forKey key: String) -> Bool { shelfEnabled }
        }
    }

    final class ShelfService {
        static var shared = ShelfService()
        var accepts = true
        var acceptsCount = 0
        var lastString: String?
        func accept(pasteboard: NSPasteboard) -> Bool {
            acceptsCount += 1
            lastString = pasteboard.string(forType: .string)
            return accepts
        }
    }

    /// Keep the pasteboard lane on main so the run-loop assertions share its
    /// type cache, mirroring the production serialization contract.
    final class GeneralPasteboardAccess {
        static let shared = GeneralPasteboardAccess()
        func async<T>(_ work: @escaping () -> T, then completion: @escaping (T) -> Void) {
            DispatchQueue.main.async {
                completion(work())
            }
        }
    }

    enum ClipboardImportOutcome: Equatable {
        case imported
        case failed(ClipboardImportFailure)
    }

    enum ClipboardImportFailure: Equatable {
        case empty
        case incompatible
    }

    enum ClipboardSnapshot {
        case compatible(NSPasteboard)
        case empty
        case incompatible
    }

    private static func pump(until condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: 3)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
    }

    private static func snapshotKind(_ value: ClipboardSnapshot?) -> String {
        switch value {
        case .empty: return "empty"
        case .incompatible: return "incompatible"
        case .compatible: return "compatible"
        case nil: return "nil"
        }
    }

    static func run(_ suite: TestSuite) {
        defer { pasteboard.releaseGlobally() }
        func reset() {
            AppFeature.shelf.isAvailable = true
            UserDefaults.standard.shelfEnabled = true
            ShelfService.shared = ShelfService()
            pasteboard.clearContents()
        }

        // Snapshot classification: nothing, unreadable content, and content
        // the shelf can keep all map to distinct outcomes.
        reset()
        var snapshot: ClipboardSnapshot?
        ClipboardImportService.shared.fetchSnapshot { snapshot = $0 }
        pump { snapshot != nil }
        suite.expect(snapshotKind(snapshot) == "empty",
               "a cleared general pasteboard reports an empty snapshot")

        reset()
        let unknown = NSPasteboardItem()
        unknown.setData(Data([1]), forType: NSPasteboard.PasteboardType("com.example.mystery"))
        pasteboard.writeObjects([unknown])
        snapshot = nil
        ClipboardImportService.shared.fetchSnapshot { snapshot = $0 }
        pump { snapshot != nil }
        suite.expect(snapshotKind(snapshot) == "incompatible",
               "content the shelf cannot hold reports an incompatible snapshot")

        reset()
        let promised = NSPasteboardItem()
        promised.setData(Data([1]), forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"))
        pasteboard.writeObjects([promised])
        snapshot = nil
        ClipboardImportService.shared.fetchSnapshot { snapshot = $0 }
        pump { snapshot != nil }
        suite.expect(snapshotKind(snapshot) == "incompatible",
               "a file promise alone is skipped and therefore not a compatible snapshot")

        reset()
        pasteboard.setString("hello", forType: .string)
        snapshot = nil
        ClipboardImportService.shared.fetchSnapshot { snapshot = $0 }
        pump { snapshot != nil }
        if case let .compatible(board) = snapshot {
            suite.expect(board.string(forType: .string) == "hello",
                   "a text clipboard is cloned into a fresh board for the shelf")
            board.releaseGlobally()
        } else {
            suite.expect(false, "text clipboard should produce a compatible snapshot")
        }

        reset()
        let mixed = NSPasteboardItem()
        mixed.setString("hello", forType: .string)
        mixed.setData(Data([1]), forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"))
        pasteboard.writeObjects([mixed])
        snapshot = nil
        ClipboardImportService.shared.fetchSnapshot { snapshot = $0 }
        pump { snapshot != nil }
        if case let .compatible(board) = snapshot {
            let promiseType = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
            suite.expect(board.string(forType: .string) == "hello"
                   && !(board.types ?? []).contains(promiseType),
                   "a snapshot keeps droppable content but never clones a file promise")
            board.releaseGlobally()
        } else {
            suite.expect(false, "mixed clipboard should still produce a compatible snapshot")
        }

        // Image materialization turns a decoded clipboard picture into a
        // readable PNG file, and refuses anything that is not an image.
        reset()
        suite.expect(ClipboardImportService.materializedImageURL(from: pasteboard) == nil,
               "an empty pasteboard materializes no image")
        pasteboard.setString("hello", forType: .string)
        suite.expect(ClipboardImportService.materializedImageURL(from: pasteboard) == nil,
               "a text pasteboard is not an image")

        reset()
        if let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) {
            let sourceImage = NSImage(size: NSSize(width: 16, height: 16))
            sourceImage.addRepresentation(bitmap)
            if let tiff = sourceImage.tiffRepresentation {
                let imageItem = NSPasteboardItem()
                imageItem.setData(tiff, forType: .tiff)
                pasteboard.writeObjects([imageItem])
                if let url = ClipboardImportService.materializedImageURL(from: pasteboard) {
                    let data = try? Data(contentsOf: url)
                    let rep = data.flatMap { NSBitmapImageRep(data: $0) }
                    suite.expect(rep?.pixelsWide == 16 && rep?.pixelsHigh == 16,
                           "a clipboard image materializes to a readable PNG")
                    try? FileManager.default.removeItem(at: url)
                } else {
                    suite.expect(false, "a clipboard image should materialize to a PNG URL")
                }
            } else {
                suite.expect(false, "test image produced no TIFF data")
            }
        } else {
            suite.expect(false, "test image could not be rendered")
        }

        // Shelf routing: feature and preference gates run before any read,
        // then the snapshot outcome and the shelf's own admission decide the
        // result.
        reset()
        AppFeature.shelf.isAvailable = false
        var outcome: ClipboardImportOutcome?
        ClipboardImportService.shared.pasteIntoCurrentShelf { outcome = $0 }
        pump { outcome != nil }
        suite.expect(outcome == .failed(.incompatible) && ShelfService.shared.acceptsCount == 0,
               "an unavailable shelf rejects the paste before reading the clipboard")

        reset()
        UserDefaults.standard.shelfEnabled = false
        outcome = nil
        ClipboardImportService.shared.pasteIntoCurrentShelf { outcome = $0 }
        pump { outcome != nil }
        suite.expect(outcome == .failed(.incompatible) && ShelfService.shared.acceptsCount == 0,
               "a shelf disabled in preferences rejects the paste")

        reset()
        outcome = nil
        ClipboardImportService.shared.pasteIntoCurrentShelf { outcome = $0 }
        pump { outcome != nil }
        suite.expect(outcome == .failed(.empty),
               "an empty clipboard reports empty to the caller")

        reset()
        pasteboard.writeObjects([unknown])
        outcome = nil
        ClipboardImportService.shared.pasteIntoCurrentShelf { outcome = $0 }
        pump { outcome != nil }
        suite.expect(outcome == .failed(.incompatible) && ShelfService.shared.acceptsCount == 0,
               "an incompatible clipboard is rejected without touching the shelf")

        reset()
        pasteboard.setString("hello", forType: .string)
        ShelfService.shared.accepts = true
        outcome = nil
        ClipboardImportService.shared.pasteIntoCurrentShelf { outcome = $0 }
        pump { outcome != nil }
        suite.expect(outcome == .imported && ShelfService.shared.acceptsCount == 1
               && ShelfService.shared.lastString == "hello",
               "a compatible clipboard imports through the shelf")

        reset()
        pasteboard.setString("hello", forType: .string)
        ShelfService.shared.accepts = false
        outcome = nil
        ClipboardImportService.shared.pasteIntoCurrentShelf { outcome = $0 }
        pump { outcome != nil }
        suite.expect(outcome == .failed(.incompatible) && ShelfService.shared.acceptsCount == 1,
               "a shelf that refuses the snapshot surfaces an incompatible result")
    }
}
