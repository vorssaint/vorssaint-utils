// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// The production poll, metadata/text reader and history mutations run against
/// a private pasteboard. App attribution, delivery timing and disk writes are
/// inert; these checks do not read or replace the user's clipboard.
enum ClipboardCaptureRestoreTests {
    class Fixture: ClipboardPreviewContract.Fixture {
        enum NSPasteboard { static let general = AppKit.NSPasteboard.withUniqueName() }
        final class Sources {
            static let shared = Sources()
            var excluded = false
            var bundleID = "com.example.editor"
            var lastRemote = false
            func setHistoryRunning(_ running: Bool) {}
            func sourceSinceLastCheck(declared: String?, remote: Bool,
                                      historyPanelIsKey: Bool, historyPanelClosing: Bool)
                -> (excluded: Bool, bundleID: String?, fromHistoryPanel: Bool) {
                lastRemote = remote
                return (excluded, bundleID, false)
            }
        }
        typealias ClipboardIgnoredApps = Sources
        enum ClipboardFileStore {
            struct Batch {
                let references: [ClipboardHistoryFileReference]
                func finish(keeping: Bool) {}
            }
            static func persist(_ files: [ClipboardCapturedFile],
                                previous: [ClipboardHistoryFileReference],
                                completion: @escaping (Batch) -> Void) {}
        }
        final class Lane {
            static let shared = Lane()
            var defersDelivery = false
            var pending: (() -> Void)?
            func async<T>(timeout: TimeInterval,
                          _ work: @escaping (_ isExpired: () -> Bool) -> T?,
                          then completion: @escaping (T?) -> Void,
                          didFinish: @escaping (T?) -> Void) {
                let value = work { false }
                let deliver = { didFinish(value); completion(value) }
                if defersDelivery { pending = deliver } else { deliver() }
            }
        }
        typealias GeneralPasteboardAccess = Lane
        var isRunning = true
        var lastChangeCount = 0
        var captureState = ClipboardHistoryCaptureState()
        var panel: NSPanel?
        var timer: Timer?
        var retentionTimer: Timer?
        static let pasteboardTimeout: TimeInterval = 5
        // Rich payload decoding is covered elsewhere; this fixture exercises
        // the production metadata and text path with images/files disabled.
        static func copiedFileURLs(from board: AppKit.NSPasteboard) -> [URL]? {
            guard let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  !urls.isEmpty else { return nil }
            return urls
        }
        static func copiedPNGImage(from board: AppKit.NSPasteboard)
            -> (data: Data, width: Int, height: Int)? { nil }
        static func webURLString(from board: AppKit.NSPasteboard) -> String? { nil }
        static func sha256Hex(_ data: Data) -> String { data.base64EncodedString() }
        func promoteFiles(_ paths: [String], resources: [ClipboardCapturedFile] = [], source: String?, keepsSource: Bool) {
            preconditionFailure("file capture is outside this text fixture")
        }
        func promoteImage(_ image: (data: Data, width: Int, height: Int), source: String?, keepsSource: Bool) {
            preconditionFailure("image capture is outside this text fixture")
        }
    }

    static func run(_ suite: TestSuite) {
        let board = Fixture.NSPasteboard.general
        let transient = "org.nspasteboard.TransientType"
        defer {
            board.releaseGlobally()
            Fixture.UserDefaults.standard.skipSensitive = false
            Fixture.UserDefaults.standard.includeImagesFiles = false
            Fixture.Lane.shared.pending = nil
            Fixture.Lane.shared.defersDelivery = false
        }
        func start() -> Service {
            board.clearContents()
            Fixture.Sources.shared.excluded = false
            Fixture.Sources.shared.bundleID = "com.example.editor"
            Fixture.UserDefaults.standard.skipSensitive = false
            let service = Service()
            service.captureIfChanged()
            return service
        }
        func copy(_ text: String, to service: Service, mark: String? = nil) {
            board.clearContents()
            board.setString(text, forType: .string)
            if let mark { board.setString("1", forType: AppKit.NSPasteboard.PasteboardType(mark)) }
            service.captureIfChanged()
        }
        let ordinary = start()
        var ordinaryNotices: [String] = []
        let ordinarySubscription = ordinary.capturedEntry.sink { ordinaryNotices.append($0.text) }
        defer { ordinarySubscription.cancel() }
        copy("A", to: ordinary)
        copy("B", to: ordinary)
        let b = ordinary.entries.first { $0.text == "B" }!
        copy("A", to: ordinary)
        suite.expect(ordinary.entries.map(\.text) == ["A", "B"]
                     && ordinary.entries.contains { $0.id == b.id },
                     "ordinary A-B-A copies keep the intermediate history entry")
        suite.expect(ordinaryNotices == ["A", "B", "A"],
                     "ordinary repeated copies keep their copy notices")

        for mark in [transient, "org.nspasteboard.AutoGeneratedType"] {
            let service = start()
            var notices = 0
            let subscription = service.capturedEntry.sink { _ in notices += 1 }
            defer { subscription.cancel() }
            copy("A", to: service)
            let original = service.latestPasteboardEntry!
            Fixture.Sources.shared.bundleID = "com.example.dictation"
            copy("Temporary text", to: service, mark: mark)
            let deadline = service.pendingRestore?.at
            suite.expect(service.entries.map(\.text) == ["A"] && service.latestPasteboardEntry == nil,
                         "marked temporary text is neither stored nor previewed")
            service.captureIfChanged()
            copy("More temporary text", to: service, mark: mark)
            suite.expect(deadline != nil && service.pendingRestore?.at == deadline,
                         "successive marked writes keep the original restore deadline")
            copy("A", to: service)
            suite.expect(service.latestPasteboardEntry?.id == original.id
                         && service.latestPasteboardEntry?.sourceBundleID == original.sourceBundleID
                         && notices == 1 && service.pendingRestore == nil,
                         "a marked temporary write restores the saved entry without another notice")
        }

        for excluded in [false, true] {
            let service = start()
            var notices = 0
            let subscription = service.capturedEntry.sink { _ in notices += 1 }
            defer { subscription.cancel() }
            copy("A", to: service)
            Fixture.Sources.shared.excluded = excluded
            copy("Hidden text", to: service,
                 mark: excluded ? nil : "org.nspasteboard.ConcealedType")
            Fixture.Sources.shared.excluded = false
            copy("A", to: service)
            suite.expect(service.entries.map(\.text) == ["A"] && notices == 2,
                         "an ignored or concealed write does not prove a temporary restore")
        }

        let credential = "export GITHUB_TOKEN=exampleCredential"
        for precedingWrite in ["repeated", "ordinary", "transient"] {
            let service = start()
            copy(credential, to: service)
            switch precedingWrite {
            case "repeated":
                // Two writes between polls are still ordinary copies.
                board.clearContents()
                board.setString(credential, forType: .string)
            case "ordinary":
                copy("Ordinary text", to: service)
            default:
                copy("Temporary text", to: service, mark: transient)
            }
            Fixture.UserDefaults.standard.skipSensitive = true
            copy(credential, to: service)
            suite.expect(service.latestPasteboardEntry == nil
                         && service.entries.count == (precedingWrite == "ordinary" ? 2 : 1),
                         "the sensitive filter blocks a re-copy after a \(precedingWrite) write without removing history")
        }

        for boundary in ["expired", "stopped", "server restarted"] {
            let service = start()
            var notices = 0
            let subscription = service.capturedEntry.sink { _ in notices += 1 }
            defer { subscription.cancel() }
            copy("A", to: service)
            copy("Temporary text", to: service, mark: transient)
            switch boundary {
            case "expired":
                service.pendingRestore?.at = Date().addingTimeInterval(-ClipboardHistoryPasteRestore.window - 1)
            case "stopped":
                service.stop()
                suite.expect(service.pendingRestore == nil, "stopping history clears its pending restore")
                service.isRunning = true
                service.captureState.restart()
                service.captureIfChanged()
            default:
                service.lastChangeCount = Int.max
            }
            copy("A", to: service)
            suite.expect(notices == 2 && service.latestPasteboardEntry?.text == "A",
                         "a restore after history \(boundary) is handled as a fresh copy")
        }

        let stopped = start()
        copy("A", to: stopped)
        Fixture.Lane.shared.defersDelivery = true
        copy("Late copy", to: stopped)
        stopped.stop()
        Fixture.Lane.shared.pending?()
        suite.expect(stopped.entries.map(\.text) == ["A"] && stopped.latestPasteboardEntry == nil,
                     "a delayed capture cannot restore or record content after history stops")
        Fixture.Lane.shared.defersDelivery = false
        Fixture.Lane.shared.pending = nil
        baselineFiles(suite, board: board)
    }

    private static func baselineFiles(_ suite: TestSuite, board: AppKit.NSPasteboard) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("baseline-\(UUID()).pdf")
        defer {
            try? FileManager.default.removeItem(at: url)
            Fixture.UserDefaults.standard.includeImagesFiles = false
            Fixture.Sources.shared.excluded = false
        }
        do {
            try Data("%PDF-1.4\noriginal copy\n".utf8).write(to: url)
            var original = ClipboardHistoryEntry(text: "", copiedAt: .distantPast, pinnedAt: .distantPast,
                                                 kind: .files, filePaths: [url.path])
            original.sourceBundleID = "com.tencent.xinWeChat"
            let other = ClipboardHistoryEntry(text: "another saved entry")
            Fixture.UserDefaults.standard.includeImagesFiles = true
            for excluded in [false, true] {
                board.clearContents()
                board.writeObjects([url as NSURL])
                board.setString("com.example.current", forType: .source)
                if excluded { board.setString("1", forType: .remoteClipboard) }
                Fixture.Sources.shared.excluded = excluded
                let service = Service()
                service.setEntries([other, original])
                var notices = 0
                let subscription = service.capturedEntry.sink { _ in notices += 1 }
                service.captureIfChanged()
                let repaired = service.entries[1]
                suite.expect(service.entries.map(\.id) == [other.id, original.id]
                             && repaired.copiedAt == original.copiedAt && repaired.pinnedAt == original.pinnedAt
                             && repaired.sourceBundleID == original.sourceBundleID && notices == 0,
                             "baseline file access repair preserves history identity, order, timing, source and notices")
                suite.expect(excluded ? repaired.fileReferences.isEmpty : repaired.fileReferences.first?.bookmark != nil,
                             "baseline repairs access only after the current source passes exclusions")
                suite.expect(Fixture.Sources.shared.lastRemote == excluded,
                             "baseline file admission checks remote clipboard metadata before retaining contents")
                subscription.cancel()
            }
        } catch { suite.expect(false, "baseline file fixture: \(error)") }
    }

}
