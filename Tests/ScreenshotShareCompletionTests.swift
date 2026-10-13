// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production completion handler with controlled upload and clipboard results.
/// No network request or native preview is created.
enum ScreenshotShareCompletionTests {
    typealias DispatchQueue = NotchScreenRefreshContract.DispatchQueue
    final class Model {
        var deletingShare = false
        var sharing = false
        var sharedRecord: ScreenshotShareRecord?
        var exported = false
        func exportImage() -> Export? { Export() }
        func markExported() { exported = true }
    }

    struct Export {
        let image = 1
        let scale = 1.0
    }

    enum ScreenshotRenderer {
        static var gate: RenderingGate?
        static func pngData(from image: Int, scale: Double) -> Data? {
            gate?.wait()
            return Data([1])
        }
    }

    final class RenderingGate: @unchecked Sendable {
        private let lock = NSLock()
        private var entered = false
        let resume = DispatchSemaphore(value: 0)
        var started: Bool { lock.withLock { entered } }
        func wait() {
            lock.withLock { entered = true }
            _ = resume.wait(timeout: .now() + 5)
        }
    }

    /// Scoped to the hosts, so the production defaults read never reaches
    /// the person's own preferences.
    enum SharingDefaults {
        static let standard = SharingDefaultsState()
    }

    final class SharingDefaultsState {
        var enabled = true
        func bool(forKey: String) -> Bool { enabled }
    }

    class EditorState {
        typealias UserDefaults = SharingDefaults
        let model = Model()
        let strings = ScreenshotFeatureStrings.enUS
        var window: Int? = 1
    }

    enum ScreenshotShareError: Error {
        case unavailable, invalidImage, invalidEndpoint, localStorage, invalidResponse, rejected
    }

    /// Runs the real service preflight and records the point at which it
    /// would reach the network. The fake transport always fails locally.
    @MainActor class CreationState {
        typealias UserDefaults = SharingDefaults
        final class Session {
            var uploads = 0
            func upload(for request: URLRequest, from data: Data) async throws -> (Data, URLResponse) {
                uploads += 1
                throw ScreenshotShareError.unavailable
            }
        }
        let session = Session()
        let endpoint = URL(string: "https://example.com")!
        let decoder = JSONDecoder()
        var removedRecordIDs = Set<String>()
        var records: [ScreenshotShareRecord] = []
        var writes = 0
        func loadRecords() throws -> [ScreenshotShareRecord] { [] }
        func saveRecords(_ records: [ScreenshotShareRecord]) throws { writes += 1 }
        func normalizedRecords(_ records: [ScreenshotShareRecord]) -> [ScreenshotShareRecord] { records }
        func deleteRemote(_ record: ScreenshotShareRecord) async throws {}
        func scheduleExpiryRefresh() {}
    }

    class State {
        typealias UserDefaults = SharingDefaults
        var systemSharing = false
        var pointerInside = false
        var onClose: () -> Void = {}
        var shareHandler: ((ScreenshotShareDuration, @escaping @MainActor (ScreenshotShareRecord?) -> Void) -> Void)?
        var closed = false
        let model = Model()
        var dismissWork: DispatchWorkItem?
        var baseDismissDuration: TimeInterval? = 12
        var autoDismissDuration: TimeInterval? = 12
        struct Animation {
            static func spring(response: Double, dampingFraction: Double) -> Animation { Animation() }
        }
        func withAnimation(_ animation: Animation, _ body: () -> Void) { body() }
        var completion: (@MainActor (ScreenshotShareRecord?) -> Void)?
        var copies: [ScreenshotShareRecord] = []
        var copySucceeds = true
        var showingLink = false

        func share(_ duration: ScreenshotShareDuration,
                   completion: @escaping @MainActor (ScreenshotShareRecord?) -> Void) {
            self.completion = completion
            shareHandler?(duration, completion)
        }
        func close() { closed = true; onClose() }
        @MainActor func copyLinkAndClose(_ record: ScreenshotShareRecord) -> Bool {
            copies.append(record)
            let copied = copySucceeds && ScreenshotShareService.shared.copy(record.url)
            if copied { close() }
            return copied
        }
        func resizePanel(showingLink: Bool) { self.showingLink = showingLink }
    }

    @MainActor final class ScreenshotShareService {
        static let shared = ScreenshotShareService()
        var revoked: [ScreenshotShareRecord] = []
        var records: [ScreenshotShareRecord] = []
        var copies: [URL] = []
        var clipboard = "new capture"
        var copySucceeds = true
        var uploadCompletion: CheckedContinuation<ScreenshotShareRecord, Error>?
        func createLink(pngData: Data, duration: ScreenshotShareDuration) async throws -> ScreenshotShareRecord {
            try await withCheckedThrowingContinuation { uploadCompletion = $0 }
        }
        func copy(_ url: URL) -> Bool {
            copies.append(url)
            if copySucceeds { clipboard = url.absoluteString }
            return copySucceeds
        }
        func delete(_ record: ScreenshotShareRecord) async throws { revoked.append(record) }
    }

    enum AppFeature {
        case screenshot
        static var available = true
        var isAvailable: Bool { Self.available }
    }

    enum ScreenshotLastCaptureStore {
        static var stored: Int? = 1
        static var isWithheld = false
        static func load() -> Int? { stored }
        static func save(_ capture: Int) { stored = capture; isWithheld = false }
        static func clear() { stored = nil; isWithheld = false }
        static func withhold() { isWithheld = true }
    }

    enum ScreenshotSelectionController {
        typealias Capture = Int
    }

    final class ScreenshotEditorController {
        let capture: Int
        var shown = false
        init(capture: Int) { self.capture = capture }
        func show() { shown = true }
    }

    enum WindowActivationPolicy {
        static var retained = 0
        static func retain() { retained += 1 }
        static func release() { retained -= 1 }
    }

    enum NSSound {
        static var beeps = 0
        static func beep() { beeps += 1 }
    }

    enum QuickToolHUD {
        static func show(icon: String, message: String) {}
    }

    typealias ScreenshotQuickPreviewController = Controller

    @MainActor class UploadState {
        let defaultsName = "vorss.tests.screenshot-shortcut.\(UUID().uuidString)"
        let defaults: UserDefaults
        let strings = ScreenshotFeatureStrings.enUS
        var uploadingCaptureID: UUID?
        var latestCaptureID = UUID()
        var latestCaptureToken = UUID()
        var latestCaptureWithheld = false
        var linkCopyRetry = ScreenshotLinkCopyRetry()
        var editors: [ScreenshotEditorController] = []
        var preview: ScreenshotQuickPreviewController?
        var completion: (@MainActor (ScreenshotShareRecord?) -> Void)?
        var uploads = 0
        var uploadedCaptures: [Int] = []

        init() {
            defaults = UserDefaults(suiteName: defaultsName)!
            defaults.set(true, forKey: DefaultsKey.screenshotUploadShortcutEnabled)
            defaults.set(true, forKey: DefaultsKey.screenshotSharingEnabled)
            ScreenshotLastCaptureStore.stored = 1
            ScreenshotLastCaptureStore.isWithheld = false
        }
        deinit {
            UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
        }
        func shareDirect(_ capture: Int, duration: ScreenshotShareDuration,
                         completion: @escaping @MainActor (ScreenshotShareRecord?) -> Void) {
            uploads += 1
            uploadedCaptures.append(capture)
            self.completion = completion
        }
        func showPreview(capture: Int = 1) -> ScreenshotQuickPreviewController {
            let controller = ScreenshotQuickPreviewController()
            controller.shareHandler = { [weak self] duration, completion in
                self?.shareDirect(capture, duration: duration, completion: completion)
            }
            controller.onClose = { [weak self] in self?.preview = nil }
            preview = controller
            return controller
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
        suite.expect(finished, "screenshot upload completion tests finish")
    }

    @MainActor static func checks(_ suite: TestSuite) async {
        let record = ScreenshotShareRecord(id: "test", endpoint: URL(string: "https://example.com")!,
                                          expiresAt: Date().addingTimeInterval(3_600), deleteToken: "test")
        let service = ScreenshotShareService.shared
        AppFeature.available = true
        SharingDefaults.standard.enabled = true
        service.revoked = []
        let open = Controller()
        open.performShare(.oneHour)
        open.completion?(record)
        suite.expect(open.copies == [record] && open.closed,
                     "upload completion copies and closes before returning, without a deferred handoff")
        for _ in 0..<20 { await Task.yield() }
        suite.expect(service.revoked.isEmpty, "a delivered link stays active")

        let closingAfterCallback = Controller()
        closingAfterCallback.performShare(.oneHour)
        closingAfterCallback.completion?(record)
        closingAfterCallback.closed = true
        for _ in 0..<20 { await Task.yield() }
        suite.expect(closingAfterCallback.copies == [record] || service.revoked == [record],
                     "closing immediately after the callback cannot leave a link neither delivered nor revoked")
        service.revoked = []

        let closed = Controller()
        closed.performShare(.oneHour)
        closed.closed = true
        closed.completion?(record)
        for _ in 0..<20 { await Task.yield() }
        suite.expect(service.revoked == [record] && closed.copies.isEmpty,
                     "closing before upload completion revokes the link without copying it")

        service.revoked = []
        var released: Controller? = Controller()
        released?.performShare(.oneHour)
        let completion = released?.completion
        released = nil
        completion?(record)
        for _ in 0..<20 { await Task.yield() }
        suite.expect(service.revoked == [record], "releasing the preview also revokes an undelivered link")

        for scenario in ["links off", "feature off"] {
            service.revoked = []
            let preview = Controller()
            preview.performShare(.oneHour)
            if scenario == "links off" { SharingDefaults.standard.enabled = false }
            if scenario == "feature off" { AppFeature.available = false }
            preview.completion?(record)
            for _ in 0..<20 { await Task.yield() }
            suite.expect(service.revoked == [record] && preview.copies.isEmpty && !preview.model.sharing,
                         "preview revokes an undelivered link after \(scenario)")
            SharingDefaults.standard.enabled = true
            AppFeature.available = true
        }

        for scenario in ["open", "closed", "links off", "feature off"] {
            service.revoked = []
            let editor = Editor()
            var completed = false
            var delivered: ScreenshotShareRecord?
            editor.share(duration: .oneHour) { result in
                completed = true
                delivered = result
            }
            let uploadDeadline = Date().addingTimeInterval(2)
            while service.uploadCompletion == nil && Date() < uploadDeadline { await Task.yield() }
            suite.expect(service.uploadCompletion != nil, "editor starts its controlled upload")
            if scenario == "closed" { editor.window = nil }
            if scenario == "links off" { SharingDefaults.standard.enabled = false }
            if scenario == "feature off" { AppFeature.available = false }
            service.uploadCompletion?.resume(returning: record)
            service.uploadCompletion = nil
            let completionDeadline = Date().addingTimeInterval(2)
            while !completed && Date() < completionDeadline { await Task.yield() }
            suite.expect(completed, "editor handles its upload response after \(scenario)")
            if scenario == "open" {
                suite.expect(delivered == record && editor.model.exported && service.revoked.isEmpty,
                             "an open editor delivers its requested export")
            } else {
                suite.expect(delivered == nil && !editor.model.exported && service.revoked == [record],
                             "editor revokes its undelivered export after \(scenario)")
            }
            SharingDefaults.standard.enabled = true
            AppFeature.available = true
        }

        for scenario in ["closed", "links off", "feature off"] {
            let gate = RenderingGate()
            ScreenshotRenderer.gate = gate
            let editor = Editor()
            var completed = false
            var delivered: ScreenshotShareRecord?
            editor.share(duration: .oneHour) { result in completed = true; delivered = result }
            let renderDeadline = Date().addingTimeInterval(2)
            while !gate.started && Date() < renderDeadline { await Task.yield() }
            suite.expect(gate.started, "editor starts rendering before \(scenario)")
            if scenario == "closed" { editor.window = nil }
            if scenario == "links off" { SharingDefaults.standard.enabled = false }
            if scenario == "feature off" { AppFeature.available = false }
            gate.resume.signal()
            let completionDeadline = Date().addingTimeInterval(2)
            while !completed && service.uploadCompletion == nil && Date() < completionDeadline {
                await Task.yield()
            }
            suite.expect(completed && delivered == nil && service.uploadCompletion == nil,
                         "editor does not transmit when \(scenario) during PNG preparation")
            // Settle the fake request on an unfixed candidate too, so the
            // regression fails without leaking a checked continuation.
            if let completion = service.uploadCompletion {
                service.uploadCompletion = nil
                completion.resume(throwing: ScreenshotShareError.unavailable)
                for _ in 0..<20 { await Task.yield() }
            }
            ScreenshotRenderer.gate = nil
            SharingDefaults.standard.enabled = true
            AppFeature.available = true
        }

        for scenario in ["enabled", "links off", "feature off"] {
            let gate = CreationGate()
            SharingDefaults.standard.enabled = scenario != "links off"
            AppFeature.available = scenario != "feature off"
            let png = Data([137, 80, 78, 71, 13, 10, 26, 10])
            _ = try? await gate.createLink(pngData: png, duration: .oneHour)
            suite.expect(gate.session.uploads == (scenario == "enabled" ? 1 : 0)
                         && gate.writes == (scenario == "enabled" ? 1 : 0),
                         "service checks \(scenario) before persistence or any upload")
        }
        SharingDefaults.standard.enabled = true
        AppFeature.available = true

        let failedCopy = Controller()
        failedCopy.copySucceeds = false
        failedCopy.performShare(.oneHour)
        failedCopy.completion?(record)
        suite.expect(!failedCopy.closed && failedCopy.model.sharedRecord == record
                     && failedCopy.showingLink && failedCopy.dismissWork != nil,
                     "clipboard failure retains the existing link and copy controls in the preview")

        for scenario in ["open", "closed", "released", "replaced", "standalone", "standalone replaced",
                         "history opened", "owner released", "feature off", "links off",
                         "editor opened", "editor closed", "capture discarded"] {
            service.revoked = []
            service.copies = []
            service.clipboard = "new capture"
            var uploader: Uploader? = Uploader()
            var preview: ScreenshotQuickPreviewController? = ["standalone", "standalone replaced", "history opened",
                                                                  "feature off", "links off", "editor opened",
                                                                  "editor closed", "capture discarded"].contains(scenario)
                ? nil : uploader!.showPreview()
            uploader!.uploadLastCapture()
            uploader!.uploadLastCapture()
            suite.expect(uploader!.uploads == 1, "pending shortcut upload ignores duplicate presses")
            let completion = uploader!.completion
            if ["closed", "released", "replaced"].contains(scenario) { preview?.close() }
            if scenario == "released" { preview = nil }
            if scenario == "replaced" {
                uploader!.beginLatestCapture(2)
                _ = uploader!.showPreview()
            }
            if scenario == "standalone replaced" {
                uploader!.beginLatestCapture(2)
                _ = uploader!.showPreview()
            }
            if scenario == "history opened" { _ = uploader!.showPreview(capture: 2) }
            if ["editor opened", "editor closed"].contains(scenario) {
                uploader!.openEditor(with: 1)
                if scenario == "editor closed" { uploader!.editorDidClose(uploader!.editors[0]) }
            }
            if scenario == "capture discarded" {
                uploader!.discardLatestCapture(uploader!.latestCaptureToken)
            }
            if scenario == "feature off" { uploader!.invalidateLatestCaptureUploads() }
            if scenario == "links off" {
                uploader!.defaults.set(false, forKey: DefaultsKey.screenshotSharingEnabled)
                uploader!.syncLatestCapture(with: uploader!.defaults)
            }
            if scenario == "owner released" { preview = nil; uploader = nil }
            completion?(record)
            for _ in 0..<20 { await Task.yield() }
            if ["open", "standalone", "history opened"].contains(scenario) {
                suite.expect(service.copies == [record.url] && service.revoked.isEmpty,
                             "\(scenario) shortcut upload delivers its link")
                if scenario == "open" {
                    suite.expect(preview?.closed == true, "successful shortcut copy closes its preview")
                }
            } else {
                suite.expect(service.copies.isEmpty && service.clipboard == "new capture"
                             && service.revoked == [record],
                             "\(scenario) shortcut upload should revoke and preserve clipboard; "
                             + "copies=\(service.copies.count), revoked=\(service.revoked.count), "
                             + "clipboard=\(service.clipboard)")
            }
            if scenario == "history opened" {
                suite.expect(uploader?.preview?.closed == false, "standalone upload leaves a later history preview open")
            }
            if let uploader {
                suite.expect(uploader.uploadingCaptureID == nil, "completion clears pending shortcut upload")
            }
        }
        service.revoked = []
        service.copies = []
        service.records = [record]
        service.copySucceeds = false
        let retry = Uploader()
        let retryPreview = retry.showPreview()
        retry.uploadLastCapture()
        retry.completion?(record)
        suite.expect(!retryPreview.closed, "failed shortcut copy keeps its preview open")
        service.copySucceeds = true
        retry.uploadLastCapture()
        for _ in 0..<20 { await Task.yield() }
        suite.expect(retry.uploads == 1 && service.copies == [record.url, record.url]
                     && retryPreview.closed, "shortcut retries a failed copy without another upload")
        service.copies = []
        service.copySucceeds = false
        let teardownRetry = Uploader()
        teardownRetry.uploadLastCapture()
        teardownRetry.completion?(record)
        teardownRetry.invalidateLatestCaptureUploads()
        service.copySucceeds = true
        teardownRetry.uploadLastCapture()
        suite.expect(teardownRetry.uploads == 2 && service.copies == [record.url],
                     "feature teardown drops a pending copy retry instead of copying the old link")
        service.copies = []
        service.copySucceeds = false
        let standaloneRetry = Uploader()
        standaloneRetry.uploadLastCapture()
        standaloneRetry.completion?(record)
        service.copySucceeds = true
        standaloneRetry.uploadLastCapture()
        suite.expect(standaloneRetry.uploads == 1 && service.copies == [record.url, record.url],
                     "standalone shortcut retries copying its existing link without uploading again")
        for duration in [3.0, 12.0] {
            DispatchQueue.main = NotchScreenRefreshContract.Scheduler()
            let history = Uploader()
            let historyPreview = history.showPreview(capture: 2)
            historyPreview.autoDismissDuration = duration
            historyPreview.scheduleAutoDismiss()
            history.uploadLastCapture()
            DispatchQueue.main.advance(duration + 1)
            suite.expect(!historyPreview.closed && historyPreview.model.sharing,
                         "shortcut upload keeps preview open past its dismissal deadline")
            suite.expect(history.uploadedCaptures == [2], "shortcut uploads the visible history capture")
            history.completion?(record)
            suite.expect(historyPreview.closed, "history upload copies and closes its own preview")
        }
        DispatchQueue.main = NotchScreenRefreshContract.Scheduler()
        let deleting = Uploader()
        let deletingPreview = deleting.showPreview()
        deletingPreview.model.sharedRecord = record
        deletingPreview.model.deletingShare = true
        service.copies = []
        deleting.uploadLastCapture()
        for _ in 0..<20 { await Task.yield() }
        suite.expect(service.copies.isEmpty && deleting.uploads == 0,
                     "shortcut cannot copy or upload while the preview deletes its link")
        service.records = []
        let failedUpload = Uploader()
        failedUpload.uploadLastCapture()
        failedUpload.completion?(nil)
        suite.expect(failedUpload.uploadingCaptureID == nil, "failed upload clears pending shortcut state")

        service.records = [record]
        service.copies = []
        let editing = Uploader()
        editing.openEditor(with: 1)
        editing.openEditor(with: 2)
        suite.expect(editing.editors.allSatisfy { $0.shown }, "editors are tracked when shown")
        NSSound.beeps = 0
        editing.linkCopyRetry.remember(record, for: editing.latestCaptureID)
        editing.uploadLastCapture()
        suite.expect(editing.uploads == 0 && service.copies.isEmpty,
                     "shortcut never uploads or copies the stored original while its editor is open")

        suite.expect(NSSound.beeps == 1, "blocked cached-link press beeps")
        editing.linkCopyRetry.clear()
        editing.uploadLastCapture()
        suite.expect(editing.uploads == 0 && NSSound.beeps == 2,
                     "clipboard or history editor blocks the raw upload with feedback")
        let firstEditor = editing.editors[0]
        editing.editorDidClose(firstEditor)
        editing.editorDidClose(firstEditor)
        suite.expect(editing.editors.count == 1, "duplicate close preserves the remaining editor")
        editing.beginLatestCapture(3)
        editing.uploadLastCapture()
        suite.expect(editing.uploads == 0 && NSSound.beeps == 3,
                     "remaining editor blocks upload even after a newer capture")
        editing.editorDidClose(editing.editors[0])
        editing.uploadLastCapture()
        suite.expect(editing.uploads == 1 && editing.uploadedCaptures == [3] && NSSound.beeps == 3,
                     "a capture taken after those editors opened uploads once the last one closes")

        // What an editor exported is no longer the stored original, so that
        // original stays back after the editor closes, and so does a
        // discarded capture, until a newer capture arrives.
        let edited = Uploader()
        edited.beginLatestCapture(4)
        edited.openEditor(with: 4)
        edited.editorDidClose(edited.editors[0])
        NSSound.beeps = 0
        edited.uploadLastCapture()
        suite.expect(edited.uploads == 0 && NSSound.beeps == 1,
                     "a capture that went through an editor is not published as its stored original after the editor closes")
        edited.beginLatestCapture(5)
        edited.uploadLastCapture()
        suite.expect(edited.uploads == 1 && edited.uploadedCaptures == [5],
                     "a newer capture can be uploaded again")
        let discarded = Uploader()
        discarded.beginLatestCapture(6)
        discarded.discardLatestCapture(UUID())
        discarded.discardLatestCapture(nil)
        discarded.uploadLastCapture()
        suite.expect(discarded.uploads == 1,
                     "discarding an older capture or one reopened from history leaves the latest one shareable")
        let discardedLatest = Uploader()
        discardedLatest.beginLatestCapture(7)
        discardedLatest.discardLatestCapture(discardedLatest.latestCaptureToken)
        NSSound.beeps = 0
        discardedLatest.uploadLastCapture()
        suite.expect(discardedLatest.uploads == 0 && NSSound.beeps == 1,
                     "a discarded latest capture is not published")
        suite.expect(ScreenshotLastCaptureStore.isWithheld,
                     "a discarded latest capture stays withheld in the store for the next launch")
        // Turning the shortcut off renews the upload claim, not the capture's
        // identity, so the preview's later Discard still holds it back.
        let switchedOff = Uploader()
        switchedOff.beginLatestCapture(12)
        let shown = switchedOff.latestCaptureToken
        switchedOff.invalidateLatestCaptureUploads()
        switchedOff.discardLatestCapture(shown)
        NSSound.beeps = 0
        switchedOff.uploadLastCapture()
        suite.expect(switchedOff.uploads == 0 && NSSound.beeps == 1,
                     "a capture discarded after the shortcut was switched off is not published once it is back on")
        // A relaunch starts with nothing in memory; what the store kept back
        // is still not published, and a newer capture lifts it.
        let relaunched = Uploader()
        ScreenshotLastCaptureStore.stored = 13
        ScreenshotLastCaptureStore.withhold()
        NSSound.beeps = 0
        relaunched.uploadLastCapture()
        suite.expect(relaunched.uploads == 0 && NSSound.beeps == 1,
                     "a capture withheld before a relaunch is not published after it")
        relaunched.beginLatestCapture(14)
        relaunched.uploadLastCapture()
        suite.expect(relaunched.uploads == 1 && relaunched.uploadedCaptures == [14],
                     "a capture taken after the relaunch uploads")

        // The capture is kept for whichever shortcut uses it, and only then.
        let retention = Uploader()
        ScreenshotLastCaptureStore.stored = nil
        retention.beginLatestCapture(8)
        retention.syncLatestCapture(with: retention.defaults)
        suite.expect(ScreenshotLastCaptureStore.stored == 8,
                     "the upload shortcut alone keeps the latest capture for itself")
        retention.defaults.set(false, forKey: DefaultsKey.screenshotUploadShortcutEnabled)
        retention.syncLatestCapture(with: retention.defaults)
        retention.beginLatestCapture(9)
        suite.expect(ScreenshotLastCaptureStore.stored == nil,
                     "with neither shortcut on the latest capture is cleared and no longer kept")
        retention.defaults.set(true, forKey: DefaultsKey.screenshotLastCaptureShortcutEnabled)
        retention.beginLatestCapture(10)
        retention.syncLatestCapture(with: retention.defaults)
        suite.expect(ScreenshotLastCaptureStore.stored == 10,
                     "edit latest screenshot alone still keeps the latest capture")

        let stale = Uploader()
        stale.uploadLastCapture()
        stale.beginLatestCapture(11)
        stale.uploadLastCapture()
        suite.expect(stale.uploads == 2 && stale.uploadedCaptures == [1, 11],
                     "a press for a newer capture starts its own upload while an older one is still pending")
        ScreenshotLastCaptureStore.stored = 1

        let editingWithHistory = Uploader()
        editingWithHistory.openEditor(with: 1)
        _ = editingWithHistory.showPreview(capture: 2)
        editingWithHistory.uploadLastCapture()
        suite.expect(editingWithHistory.uploadedCaptures == [2],
                     "an open history preview still uploads its own visible capture")
    }
}
