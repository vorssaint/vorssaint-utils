// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production startup and cancellation methods with controlled writer
/// completions. No capture, permissions, windows or recording folders are used.
enum RecorderPreparationTests {
    enum AppFeature {
        case screenRecorder
        static var available = true
        var isAvailable: Bool { Self.available }
    }
    struct UserDefaults {
        static let standard = Self()
        func integer(forKey key: String) -> Int { 30 }
        func bool(forKey key: String) -> Bool { false }
    }
    struct Permissions {
        static let shared = Self()
        enum Grant { case granted }
        let microphone = Grant.granted
        let screenRecording = true
        let accessibility = true
        func requestScreenRecording() {}
        func requestAccessibility() {}
    }
    enum QuickToolHUD {
        static var messages = 0
        static func show(icon: String, message: String) { messages += 1 }
    }
    final class Indicator {
        var hidden = false
        func hide() { hidden = true }
    }
    final class RecorderTakeStore {
        struct Take: Equatable {
            let videoURL: URL
        }
        static let shared = RecorderTakeStore()
        var made: [Take] = []
        var deleted: [Take] = []
        func makeTake() -> Take? {
            let take = Take(videoURL: URL(fileURLWithPath: "/fixture/\(UUID()).mov"))
            made.append(take)
            return take
        }
        func delete(_ take: Take) { deleted.append(take) }
        func freeBytes() -> Int64 { 10_000_000_000 }
    }
    final class RecorderWriter {
        static var replies: [(RecorderWriter?) -> Void] = []
        var cancelled = false
        static func prepare(url: URL, pixelSize: CGSize, frameRate: Int,
                            capturesSystemAudio: Bool, capturesMicrophone: Bool,
                            pauseClock: RecorderPauseClock,
                            completion: @escaping (RecorderWriter?) -> Void) {
            replies.append(completion)
        }
        func cancel() { cancelled = true }
    }
    final class RecorderSession {
        let writer: RecorderWriter
        init(take: RecorderTakeStore.Take, region: RecorderSupport.Region,
             writer: RecorderWriter, pauseClock: RecorderPauseClock,
             capturesSystemAudio: Bool, capturesMicrophone: Bool) {
            self.writer = writer
        }
    }
    class Fixture {
        var session: RecorderSession?
        var indicator: Indicator? = Indicator()
        var isRecording = false
        var isFinishing = false
        var isAwaitingMicrophone = false
        var isPreparingRecording = false
        var countdown: DispatchWorkItem?
        var pendingStartGeneration = 1
        var starts = 0
        struct Strings { let recordFailed = "failed" }
        let strings = Strings()
        func startPreparedRecording(_ session: RecorderSession, frameRate: Int,
                                    capturesSystemAudio: Bool, generation: Int) {
            self.session = session
            starts += 1
        }
        func stop() {}
        func reportNoSpace() {}
    }

    static func run(_ suite: TestSuite) {
        let region = RecorderSupport.Region(displayID: 1, windowID: nil,
            pixelRect: CGRect(x: 0, y: 0, width: 64, height: 64), anchorRect: .zero, scale: 1)
        func reset() {
            AppFeature.available = true
            RecorderWriter.replies = []
            RecorderTakeStore.shared.made = []
            RecorderTakeStore.shared.deleted = []
            QuickToolHUD.messages = 0
        }
        defer { reset() }

        reset()
        let accepted = Service()
        accepted.beginRecording(region: region, generation: 1)
        suite.expect(accepted.hasActiveCapture && !accepted.prepareForSelection()
                     && accepted.session == nil && accepted.starts == 0,
                     "writer preparation reserves capture without starting it or admitting a second selection")
        let writer = RecorderWriter()
        RecorderWriter.replies.removeFirst()(writer)
        suite.expect(accepted.starts == 1 && accepted.session?.writer === writer
                     && !accepted.isPreparingRecording && RecorderTakeStore.shared.deleted.isEmpty,
                     "an authorized prepared writer starts exactly one recording")

        reset()
        let cancelled = Service()
        let guide = cancelled.indicator!
        cancelled.beginRecording(region: region, generation: 1)
        suite.expect(cancelled.stopOrCancelActiveCapture() && !cancelled.hasActiveCapture
                     && guide.hidden && cancelled.prepareForSelection(),
                     "the capture toggle cancels preparation and releases its guide and admission")
        let abandoned = RecorderWriter()
        RecorderWriter.replies.removeFirst()(abandoned)
        suite.expect(cancelled.starts == 0 && abandoned.cancelled
                     && RecorderTakeStore.shared.deleted == RecorderTakeStore.shared.made,
                     "a writer completed after cancellation is discarded with its take")

        reset()
        let replaced = Service()
        replaced.beginRecording(region: region, generation: 1)
        replaced.invalidatePendingStart()
        replaced.beginRecording(region: region, generation: replaced.pendingStartGeneration)
        let stale = RecorderWriter()
        RecorderWriter.replies.removeFirst()(stale)
        suite.expect(replaced.isPreparingRecording && replaced.starts == 0 && stale.cancelled,
                     "an old completion does not clear the newer preparation")
        RecorderWriter.replies.removeFirst()(RecorderWriter())
        suite.expect(replaced.starts == 1 && RecorderTakeStore.shared.deleted.count == 1,
                     "the newer request still starts after an older writer is discarded")

        reset()
        let disabled = Service()
        disabled.beginRecording(region: region, generation: 1)
        AppFeature.available = false
        let unavailable = RecorderWriter()
        RecorderWriter.replies.removeFirst()(unavailable)
        suite.expect(disabled.starts == 0 && unavailable.cancelled
                     && RecorderTakeStore.shared.deleted.count == 1,
                     "a disabled feature cannot start after encoder preparation completes")

        reset()
        let failed = Service()
        failed.beginRecording(region: region, generation: 1)
        RecorderWriter.replies.removeFirst()(nil)
        suite.expect(!failed.hasActiveCapture && failed.starts == 0 && failed.indicator == nil
                     && RecorderTakeStore.shared.deleted.count == 1 && QuickToolHUD.messages == 1,
                     "failed preparation releases its take and UI and reports failure once")
    }
}
