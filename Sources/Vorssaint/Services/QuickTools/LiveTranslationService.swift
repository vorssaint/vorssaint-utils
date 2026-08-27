// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Translation
import Vision
import os.log

/// Temporary - diagnosing a large-area translation failure. Remove once
/// resolved.
let liveTranslationDiagLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                            category: "live-translation-diag")

/// Live Translation: captures a screen region on a loop, recognizes its
/// text, translates it, and publishes the result for the overlay to draw.
/// Needs macOS 15 for the Translation framework. Stays free of any SwiftUI
/// import itself - see AppleTranslationProvider for how the Apple path still
/// gets a working TranslationSession despite that.
@available(macOS 15.0, *)
final class LiveTranslationService: ObservableObject {
    static let shared = LiveTranslationService()

    enum Status: Equatable {
        case idle
        case running
        case paused
        case notInstalled
        case sessionNotReady
        case missingAPIKey
        case invalidAPIKeyOrQuota
        case serverError
        case timedOut
        case failed
        /// Google: the configured usage cap would be exceeded by this tick's
        /// text - the call is skipped entirely rather than made and then
        /// reported, so the persisted usage total never actually goes past
        /// the cap.
        case usageCapReached
    }

    @Published private(set) var lines: [LiveTranslationSupport.TranslatedLine] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var activeRegion: RecorderSupport.Region?
    @Published private(set) var lastCapturedImage: CGImage?
    /// A blurred copy of `lastCapturedImage`, kept alongside it so chip
    /// backgrounds (both live overlay and window-mode/copy-save renders)
    /// can crop a "blurry dark" patch of the real content behind each chip
    /// instead of drawing a flat box - computed once per tick here rather
    /// than per chip, since blurring is the expensive part and every chip
    /// shares the same source frame.
    @Published private(set) var blurredCapturedImage: CGImage?
    /// The language actually being translated *from* right now, resolved
    /// per paragraph group by `LiveTranslationSupport.classifyParagraphGroups`
    /// (or the person's pinned Settings override). The Apple session host waits
    /// for this to become non-nil before mounting - a session is never
    /// started with a nil/guessed source, since that's exactly what
    /// triggers Apple's own "pick a language" prompt. A region that needs
    /// translating but hasn't produced a confident source yet just keeps
    /// retrying next tick instead.
    @Published private(set) var detectedSourceLanguage: AppLanguage?

    /// Always serviced from inside the SwiftUI `.translationTask` that owns
    /// the TranslationSession. A prior design stashed a closure that
    /// captured `session` and called it from this Service's own Task -
    /// Apple's session is scoped to its owning task and crashes
    /// (EXC_BREAKPOINT in Translation's internals) if used after that task
    /// is no longer live, which happens any time the overlay closes, or the
    /// session rebuilds, while a translate call is in flight. Routing every
    /// call through a stream instead means `session.translate(...)` only
    /// ever runs inside the task that vended it, never across a task
    /// boundary.
    ///
    /// The stream itself is rebuilt on every `begin(region:)` - resizing the
    /// region, switching to a new one, or just starting a fresh session all
    /// go through `begin(region:)` - and the *previous* stream is finished
    /// first. A single stream reused across sessions briefly had two
    /// `.translationTask`s consuming it at once (the old one not yet
    /// cancelled by the time the new one mounted), which could hand a
    /// request to the session that was already on its way out - the
    /// symptom was translation silently stopping after a resize, or a new
    /// region briefly showing a translation left over from the last one.
    /// Finishing the old stream up front guarantees at most one consumer.
    private var appleRequestContinuation: AsyncStream<AppleTranslateRequest>.Continuation?
    /// Bumped every time `makeAppleRequestStream()` hands out a new
    /// continuation - `AsyncStream.Continuation` has no `Equatable`
    /// conformance, so this is what lets a retry (see
    /// `translateViaAppleSession`'s bridged path) tell "a fresh continuation
    /// has since replaced the stale one I already tried" apart from "the
    /// same stale one is still all that's there," instead of just checking
    /// non-nil again and re-observing the identical stale value.
    private var appleRequestContinuationGeneration = 0

    /// The macOS 26+ direct session for whichever translate call is
    /// currently in flight - built fresh per tick in `translateViaAppleSession`,
    /// not reused across ticks. Cancelling the enclosing Swift task alone
    /// doesn't stop work already handed to the translation daemon - without
    /// an explicit `.cancel()` on the session itself, every live tick whose
    /// batch outruns the capture interval would abandon a session that
    /// keeps working daemon-side, and they'd accumulate for the life of the
    /// process. A live-translation tick that outruns its own capture
    /// interval and gets superseded by the next one - or hits
    /// `translateAndPublish`'s own deadline - is exactly this feature's
    /// normal operating condition, not an edge case, so building fresh and
    /// cancelling explicitly matters here: kept set only for the duration
    /// of one in-flight call so
    /// `translateAndPublish`'s deadline-exceeded/error catch blocks can call
    /// `.cancel()` on it from the outside if that call gets abandoned before
    /// finishing - see those catch blocks' comments for why that has to
    /// happen there rather than inside this call's own catch (the abandoned
    /// call's `await` may simply never return once its task is cancelled).
    /// Reset to nil on every new session (`begin(region:)`/`stop()`).
    private var directAppleSession: TranslationSession?

    /// Caches only the async `LanguageAvailability().status()` *check
    /// result* for the currently active session's language pair - the
    /// session object itself is intentionally not cached here, see
    /// `directAppleSession`'s doc comment for why. Reset alongside it.
    private var installedDirectPair: (source: AppLanguage, target: AppLanguage)?

    /// Maps a source paragraph's own text to its translated result, for the
    /// life of the current live session - reset in `begin(region:)`. The
    /// per-tick dedupe hash (`joinedTextHash`) only skips a tick when
    /// *nothing at all* changed; the moment even one paragraph's OCR result
    /// jitters, every paragraph on the page got re-sent to the translator
    /// again, even the ones that were already translated and hadn't
    /// actually changed. This cache is what actually avoids that - a
    /// paragraph whose text has been seen before (whether from a prior tick,
    /// or a duplicate within the same tick - see `translateAndPublish`'s use
    /// of this) is served its cached result instantly, with no network/
    /// session call at all.
    private var translationCache: [String: String] = [:]

    /// How many Apple-session translate calls are currently awaiting a reply
    /// from inside `LiveTranslationSessionHost`'s `.translationTask` - i.e.
    /// how many `session.translate(text)` calls are genuinely still
    /// suspended inside Apple's Translation framework right now, not merely
    /// how many `translateViaAppleSession` callers are still awaiting
    /// (cancelling `loopTask` resolves the latter promptly via
    /// `withTaskCancellationHandler`'s `onCancel`, but does *not* stop the
    /// SessionHost's own, separate task from still genuinely awaiting
    /// `session.translate()` underneath - see `translateViaAppleSession`'s
    /// doc comment for exactly where this increments/decrements).
    /// `teardownWhenSafe` waits for this to reach zero before deallocating
    /// the SwiftUI content that owns the live TranslationSession, since
    /// doing that while this is nonzero crashes the whole process
    /// (EXC_BREAKPOINT deep in Translation.framework internals - confirmed
    /// via a symbolicated crash report) rather than throwing a catchable
    /// error.
    private var inFlightAppleTranslateCount = 0

    /// Called once by LiveTranslationSessionHost when it mounts. Not
    /// `private` so that file can reach it.
    func makeAppleRequestStream() -> AsyncStream<AppleTranslateRequest> {
        appleRequestContinuation?.finish()
        return AsyncStream<AppleTranslateRequest> { continuation in
            self.appleRequestContinuation = continuation
            self.appleRequestContinuationGeneration += 1
        }
    }

    /// Owned directly, the same way ScreenRecorderService owns its
    /// RecorderIndicator: created on begin(), torn down on stop(). This file
    /// still imports no SwiftUI itself - the controller type lives in
    /// LiveTranslationOverlay.swift and is just a name in the same module.
    private var overlay: LiveTranslationOverlayController?

    private var generation = 0
    private var loopTask: Task<Void, Never>?
    private var lastImageFingerprint: Int?
    /// When Vision last actually ran (a real recognize call, not a tick the
    /// fingerprint skipped) - used to fire an occasional idle re-warm during
    /// a long run of skipped ticks. See the re-warm call site's own comment
    /// for why the fingerprint-skip fix that made those long idle gaps
    /// common in the first place also reopened this specific problem.
    private var lastVisionActivity: Date?
    /// Guards against firing more than one idle re-warm at a time - a
    /// second one starting while the first is still running would just be
    /// two callers competing for the same daemon load, not two independent
    /// warm-ups.
    private var isReWarming = false
    private var lastPrewarm: Date?
    private var isPausedFlag = false
    /// What was on screen right before pausing, restored instantly on
    /// resume rather than waiting for the next OCR tick to repopulate it.
    private var pausedLines: [LiveTranslationSupport.TranslatedLine] = []

    private init() {}

    var isActive: Bool { activeRegion != nil }

    func syncWithPreferences() {
        guard AppFeature.liveTranslation.isAvailable else {
            stop()
            return
        }
    }

    func suspend() {
        stop()
    }

    /// Absorbs Vision's real cold-load cost before the person actually
    /// starts a session - measured directly on this codebase's own timing
    /// diagnostics: tens of seconds the first time the system's shared
    /// recognition-model cache is cold, a small fraction of a second once
    /// it's loaded, and the cache going cold again on its own whenever the
    /// system decides to. Cooldown-guarded so switching tools repeatedly in
    /// the chooser doesn't repeat the cost.
    ///
    /// Two real bugs in the old version of this function, both confirmed via
    /// that same timing diagnostic rather than guessed: it only ever warmed
    /// `VNRecognizeTextRequest`, never `RecognizeDocumentsRequest` - the one
    /// the live loop actually uses on macOS 26+ - so it was warming a model
    /// the session wasn't even going to use; and its probe was a blank 1x1
    /// pixel, which lets Vision finish instantly without ever loading the
    /// recognition model at all (there's nothing to try recognizing), so
    /// even the warm-up it did do was a no-op - a blank image lets Vision
    /// finish without loading anything, which warms nothing.
    func prewarm() {
        if let lastPrewarm, Date().timeIntervalSince(lastPrewarm) < 300 { return }
        lastPrewarm = Date()
        Task.detached(priority: .utility) {
            guard let probe = Self.warmUpProbeImage() else { return }
            let start = Date()
#if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                _ = try? await RecognizeDocumentsRequest().perform(on: probe, orientation: nil)
            } else {
                _ = Self.recognizeLines(in: probe, fallbackLanguages: ["en-US"])
            }
#else
            _ = Self.recognizeLines(in: probe, fallbackLanguages: ["en-US"])
#endif
            liveTranslationDiagLog.notice("prewarm finished in \(Date().timeIntervalSince(start), privacy: .public)s")
        }
    }

    /// A small probe image with genuine, legible text drawn on it - Vision
    /// only actually loads its recognition model when there's real text to
    /// try recognizing; a blank or empty image lets the request return
    /// instantly without loading anything, warming nothing at all.
    private static func warmUpProbeImage() -> CGImage? {
        let width = 256
        let height = 64
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        ("Warm up 123" as NSString).draw(
            at: CGPoint(x: 8, y: 18),
            withAttributes: [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black])
        NSGraphicsContext.current = previous
        return context.makeImage()
    }

    func begin(region: RecorderSupport.Region) {
        generation += 1
        let generation = self.generation
        activeRegion = region
        lines = []
        lastCapturedImage = nil
        blurredCapturedImage = nil
        detectedSourceLanguage = nil
        directAppleSession = nil
        installedDirectPair = nil
        translationCache = [:]
        lastImageFingerprint = nil
        lastVisionActivity = nil
        isPausedFlag = false
        status = .running
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            await self?.runLoop(region: region, generation: generation)
        }
        let outgoing = overlay
        outgoing?.hide()
        overlay = LiveTranslationOverlayController()
        overlay?.show(region: region)
        teardownWhenSafe(outgoing)
    }

    func stop() {
        generation += 1
        loopTask?.cancel()
        loopTask = nil
        appleRequestContinuation?.finish()
        appleRequestContinuation = nil
        activeRegion = nil
        lines = []
        lastCapturedImage = nil
        blurredCapturedImage = nil
        status = .idle
        isPausedFlag = false
        pausedLines = []
        directAppleSession = nil
        installedDirectPair = nil
        translationCache = [:]
        let outgoing = overlay
        outgoing?.hide()
        overlay = nil
        teardownWhenSafe(outgoing)
    }

    /// Rebuilds just the visual overlay - used when toggling the in-place/
    /// window display mode - without restarting the translation loop or
    /// resetting published state the way `begin(region:)` does. Reuses the
    /// same crash-safe hide-then-deferred-teardown swap.
    func rebuildOverlay() {
        guard let region = activeRegion else { return }
        let outgoing = overlay
        outgoing?.hide()
        overlay = LiveTranslationOverlayController()
        overlay?.show(region: region)
        teardownWhenSafe(outgoing)
    }

    /// Clears the currently displayed translation the moment a resize drag
    /// starts - the existing chips were laid out for the pre-resize region,
    /// so leaving them on screen, stretched or misplaced, over a region
    /// that's actively changing size looks broken rather than just stale.
    /// `restartCapture` (fired once the drag actually ends,
    /// `LiveTranslationOverlayController.windowDidEndLiveResize`)
    /// republishes fresh content for the new size shortly after.
    func clearLinesForResize() {
        lines = []
    }

    func togglePause() {
        guard isActive else { return }
        isPausedFlag.toggle()
        status = isPausedFlag ? .paused : .running
        if isPausedFlag {
            // Pausing is meant to let the person read the real content
            // underneath again, not freeze a translated overlay in place.
            pausedLines = lines
            lines = []
        } else {
            lines = pausedLines
            pausedLines = []
        }
    }

    private func runLoop(region: RecorderSupport.Region, generation: Int) async {
        let defaults = UserDefaults.standard
        var lastHash: Int?

        while !Task.isCancelled, self.generation == generation {
            if isPausedFlag {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            let interval = LiveTranslationSupport.sanitizedInterval(
                defaults.double(forKey: DefaultsKey.liveTranslationInterval))

            // A stored snapshot on the controller now (see its own doc
            // comment), not a computed property re-reading `.windowNumber`
            // - no MainActor hop needed here anymore.
            let excludedWindowIDs = overlay?.windowIDs ?? []
            // Double optional: the outer layer is the deadline's own
            // "did it finish in time" signal, the inner one is whatever
            // captureDisplayRegion itself returned.
            let tickStart = Date()
            let capturedImage = await withDeadline(seconds: 4) {
                await ScreenshotCaptureEngine.captureDisplayRegion(
                    displayID: region.displayID, pixelRect: region.pixelRect,
                    includePointer: false, hideVorssaintWindows: true,
                    protectedWindowIDs: excludedWindowIDs)
            }
            let captureElapsed = Date().timeIntervalSince(tickStart)
            guard self.generation == generation else { return }
            guard let capturedImage else {
                liveTranslationDiagLog.notice("capture deadline (4s) exceeded for region \(region.pixelRect.width, privacy: .public)x\(region.pixelRect.height, privacy: .public)")
                await publish(status: .timedOut, generation: generation)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                continue
            }
            guard let image = capturedImage else {
                liveTranslationDiagLog.notice("captureDisplayRegion returned nil (inner)")
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                continue
            }

            // A cheap 16x16 downsampled fingerprint of the whole capture -
            // recognize (RecognizeDocumentsRequest's document-layout
            // analysis, not just plain OCR) measured at ~0.5-0.7s per tick
            // on a large, text-dense region, dwarfing capture+blur combined
            // (well under 0.1s) - see this function's diagnostic timing log
            // below. Most ticks of a page someone is actually reading are
            // visually identical to the tick before, so skipping the
            // expensive Vision pass entirely when the fingerprint matches is
            // pure savings: nothing downstream (groups/hash/translate) could
            // have changed either if the pixels didn't. The 16x16 downsample
            // is small enough to hash in microseconds regardless of the
            // capture's real resolution, and coarse enough to shrug off
            // imperceptible anti-aliasing/compression jitter between two
            // otherwise-identical captures - the exact jitter that used to
            // make the *old*, full-resolution `joinedTextHash` miss a match
            // it should have had.
            let fingerprint = Self.quickImageFingerprint(image)
            if fingerprint == lastImageFingerprint {
                // A long run of skipped ticks - exactly what the fingerprint
                // skip above is meant to produce on a page someone is just
                // reading - is also exactly the condition that lets the
                // shared model cache go cold on its own while the app sits
                // idle. Fixing the "recognizing on every tick regardless of
                // change" problem reopened this one - a real content change
                // after a long idle stretch would otherwise pay a cold-load
                // spike the skip logic itself made more likely, not less.
                // An occasional cheap re-warm during the idle stretch avoids
                // paying that spike on the content change that actually
                // matters.
#if compiler(>=6.2)
                if #available(macOS 26.0, *),
                   defaults.string(forKey: DefaultsKey.liveTranslationEngine) != "compatibility",
                   !isReWarming,
                   let lastVisionActivity, Date().timeIntervalSince(lastVisionActivity) > 15 {
                    isReWarming = true
                    self.lastVisionActivity = Date()
                    Task.detached(priority: .utility) { [weak self] in
                        guard let probe = Self.warmUpProbeImage() else { return }
                        _ = try? await RecognizeDocumentsRequest().perform(on: probe, orientation: nil)
                        self?.isReWarming = false
                    }
                }
#endif
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                continue
            }
            lastImageFingerprint = fingerprint
            lastVisionActivity = Date()

            // Blur off the main actor - it's real CoreImage work, and every
            // chip this tick shares the one result.
            let blurStart = Date()
            let blurred = ScreenshotRenderer.blurredBackdrop(image, factor: 0.8)
            let blurElapsed = Date().timeIntervalSince(blurStart)
            await MainActor.run {
                self.lastCapturedImage = image
                self.blurredCapturedImage = blurred
            }

            let fallbackLanguages = MediaSupport.recognitionLanguages(for: L10n.shared.language.rawValue)
            let recognizeStart = Date()
            // Vision's own document-layout API groups paragraphs natively
            // and far more reliably than the geometry heuristic below - see
            // recognizeDocumentGroups' doc comment - but it needs macOS 26,
            // so this heuristic path still covers this feature's actual
            // floor, macOS 15. On macOS 26+ the choice is also user-visible
            // (Settings' engine picker, `DefaultsKey.liveTranslationEngine`)
            // - "compatibility" opts back into the heuristic on a machine
            // that could use native, "native" (the default) is the only
            // value that ever actually matters on macOS 15-25, since the
            // native path plainly can't run there regardless of what's
            // stored.
            let usesNativeEngine = defaults.string(forKey: DefaultsKey.liveTranslationEngine) != "compatibility"
            let groups: [[LiveTranslationSupport.RecognizedLine]]
#if compiler(>=6.2)
            if #available(macOS 26.0, *), usesNativeEngine {
                groups = await withDeadline(seconds: 4) {
                    await Self.recognizeDocumentGroups(in: image, fallbackLanguages: fallbackLanguages)
                } ?? []
            } else {
                let recognized = await withDeadline(seconds: 4) {
                    Self.recognizeLines(in: image, fallbackLanguages: fallbackLanguages)
                } ?? []
                groups = LiveTranslationSupport.groupIntoParagraphs(recognized)
            }
#else
            do {
                let recognized = await withDeadline(seconds: 4) {
                    Self.recognizeLines(in: image, fallbackLanguages: fallbackLanguages)
                } ?? []
                groups = LiveTranslationSupport.groupIntoParagraphs(recognized)
            }
#endif
            guard self.generation == generation else { return }
            let recognizeElapsed = Date().timeIntervalSince(recognizeStart)
            liveTranslationDiagLog.notice("recognized \(groups.count, privacy: .public) groups (image \(image.width, privacy: .public)x\(image.height, privacy: .public)) - capture=\(captureElapsed, privacy: .public)s blur=\(blurElapsed, privacy: .public)s recognize=\(recognizeElapsed, privacy: .public)s tickTotal=\(Date().timeIntervalSince(tickStart), privacy: .public)s")

            let hash = LiveTranslationSupport.joinedTextHash(groups.flatMap { $0 })
            if hash != lastHash {
                lastHash = hash
                await translateAndPublish(groups, generation: generation)
            } else if !groups.isEmpty, status != .running, status != .paused {
                // Same text as last tick, but that attempt didn't succeed.
                // Retry rather than just flipping the status back to
                // "running": the dedupe above means this is the only
                // remaining chance to notice a fix (a language model
                // finished installing, a corrected API key) without
                // waiting for the on-screen text itself to change - and
                // silently resetting to .running here previously hid every
                // real failure a tick after it happened.
                await translateAndPublish(groups, generation: generation)
            }

            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    private func translateAndPublish(_ groups: [[LiveTranslationSupport.RecognizedLine]],
                                     generation: Int) async {
        guard !groups.isEmpty else {
            await publish(lines: [], status: .running, generation: generation)
            return
        }

        let defaults = UserDefaults.standard
        let target = LiveTranslationSupport.resolvedTargetLanguage(
            overrideRaw: defaults.string(forKey: DefaultsKey.liveTranslationTargetLanguage) ?? "",
            fallback: AppLanguage.systemDefault)
        let overrideSource = LiveTranslationSupport.resolvedSourceLanguage(
            overrideRaw: defaults.string(forKey: DefaultsKey.liveTranslationSourceLanguage) ?? "")

        // A pinned override skips classification entirely and applies to
        // every group, matching the existing override semantics. Otherwise,
        // split by what each group actually is - see
        // classifyParagraphGroups' doc comment for why a minority-language
        // group is excluded from translation but still shown as-is rather
        // than either mistranslated or silently dropped.
        let toTranslate: [[LiveTranslationSupport.RecognizedLine]]
        let passthroughGroups: [[LiveTranslationSupport.RecognizedLine]]
        let source: AppLanguage?
        if let overrideSource {
            toTranslate = groups
            passthroughGroups = []
            source = overrideSource
        } else {
            (toTranslate, passthroughGroups, source) = LiveTranslationSupport.classifyParagraphGroups(
                groups, target: target)
        }

        // Negative ids keep passthrough entries distinct from the positively-
        // indexed translated ones they're published alongside.
        let passthroughLines = passthroughGroups.enumerated().map { index, group in
            LiveTranslationSupport.TranslatedLine(
                id: -(index + 1),
                boundingBox: LiveTranslationSupport.unionBoundingBox(group),
                rowCount: group.count,
                original: LiveTranslationSupport.joinedParagraphText(group),
                translated: LiveTranslationSupport.joinedParagraphText(group))
        }

        guard !toTranslate.isEmpty else {
            await publish(lines: passthroughLines, status: .running, generation: generation)
            return
        }
        guard let source else {
            // Something needs translating but nothing in it could be
            // classified confidently yet. Not an error: wait for a clearer
            // OCR pass rather than starting a session on a guess, which is
            // what used to leave a session stuck after a resize landed on
            // sparse or ambiguous content. Passthrough content doesn't
            // depend on that, so it can still show.
            if !passthroughLines.isEmpty {
                await publish(lines: passthroughLines, status: .running, generation: generation)
            }
            return
        }
        await MainActor.run {
            if self.detectedSourceLanguage != source { self.detectedSourceLanguage = source }
        }

        let providerRaw = defaults.string(forKey: DefaultsKey.liveTranslationProvider) ?? "apple"
        let provider: TranslationProvider = providerRaw == "google"
            ? GoogleTranslationProvider()
            : AppleTranslationProvider(requestHandler: { [weak self] texts, source, target in
                guard let self else { throw TranslationProviderError.sessionNotReady }
                return try await self.translateViaAppleSession(texts: texts, source: source, target: target)
            })

        let texts = toTranslate.map(LiveTranslationSupport.joinedParagraphText)

        // Cache lookup - see translationCache's doc comment. Handles both
        // same-tick duplicate groups (the self-referential-Container bug
        // that could make one capture produce hundreds of near-identical
        // paragraphs) and cross-tick repeats (nearly all of a mostly-static
        // page, on every subsequent tick) with one mechanism: only text
        // that's genuinely new to this session gets sent to the provider at
        // all.
        var resultsByIndex: [Int: String] = [:]
        var uniqueTextIndices: [String: [Int]] = [:]
        for (index, text) in texts.enumerated() {
            if let cached = translationCache[text] {
                resultsByIndex[index] = cached
            } else {
                uniqueTextIndices[text, default: []].append(index)
            }
        }
        let uniqueTexts = Array(uniqueTextIndices.keys)
        liveTranslationDiagLog.notice("provider=\(providerRaw, privacy: .public) toTranslate=\(toTranslate.count, privacy: .public) cached=\(texts.count - uniqueTexts.count, privacy: .public) new=\(uniqueTexts.count, privacy: .public) passthrough=\(passthroughLines.count, privacy: .public) source=\(source.rawValue, privacy: .public) target=\(target.rawValue, privacy: .public)")

        func publishFromResults(_ resultsByIndex: [Int: String]) async {
            let translatedLines = toTranslate.indices.map { index -> LiveTranslationSupport.TranslatedLine in
                let group = toTranslate[index]
                return LiveTranslationSupport.TranslatedLine(
                    id: index,
                    boundingBox: LiveTranslationSupport.unionBoundingBox(group),
                    rowCount: group.count,
                    original: LiveTranslationSupport.joinedParagraphText(group),
                    translated: resultsByIndex[index] ?? "")
            }
            await publish(lines: translatedLines + passthroughLines, status: .running, generation: generation)
        }

        guard !uniqueTexts.isEmpty else {
            // Everything needed this tick was already cached - no network/
            // session call at all.
            await publishFromResults(resultsByIndex)
            return
        }

        // Gate *before* spending the network call, not just report after
        // one - this guarantees the persisted total never actually exceeds
        // a configured cap, rather than only noticing it did afterward.
        // Counted against the deduped set: repeated content the cache
        // already had an answer for was never going to be billed again.
        var googleCharacters = 0
        var googleWords = 0
        if providerRaw == "google" {
            // Google bills by Unicode code point, not by Swift's grapheme-
            // cluster String.count - unicodeScalars.count is what actually
            // matches the invoice for any text with combining marks, most
            // emoji, or other multi-scalar graphemes.
            googleCharacters = uniqueTexts.reduce(0) { $0 + $1.unicodeScalars.count }
            googleWords = uniqueTexts.reduce(0) { $0 + $1.split(separator: " ").count }
            if googleUsageWouldExceedCap(characters: googleCharacters) {
                await publish(status: .usageCapReached, generation: generation)
                return
            }
            // Recorded before the request goes out, not after it succeeds:
            // recording only on success left a window where two overlapping
            // ticks could each pass the gate above before either recorded,
            // letting the real total overshoot the cap. Reversed below only
            // for the one failure that provably never reached Google - a
            // missing key never leaves this process. A timeout or a real
            // HTTP response from Google's servers cannot be proven unbilled,
            // so those charges stand.
            await recordGoogleUsage(characters: googleCharacters, words: googleWords)
        }

        // A flat 6s was measured comfortably covering a normal-sized capture
        // (32 texts translated in ~0.5s via the batched Apple session path -
        // see batchTranslate) but left zero real margin against a genuinely
        // large one - scaling with the deduped count on top of that same
        // measured per-text cost, not just raising the flat floor, is what
        // actually leaves headroom at both ends of that range while still
        // shrinking on a tick that's mostly cache hits.
        let translateDeadline = max(6, Double(uniqueTexts.count) * 0.03 + 3)
        let translateStart = Date()
        do {
            let translatedTexts = try await withThrowingDeadline(seconds: translateDeadline) {
                try await provider.translate(texts: uniqueTexts, source: source, target: target)
            }
            liveTranslationDiagLog.notice("translate succeeded in \(Date().timeIntervalSince(translateStart), privacy: .public)s, \(translatedTexts.count, privacy: .public) results")
            guard self.generation == generation else { return }
            for (position, uniqueText) in uniqueTexts.enumerated() {
                let result = position < translatedTexts.count ? translatedTexts[position] : ""
                translationCache[uniqueText] = result
                for index in uniqueTextIndices[uniqueText] ?? [] {
                    resultsByIndex[index] = result
                }
            }
            await publishFromResults(resultsByIndex)
        } catch is DeadlineExceeded {
            liveTranslationDiagLog.notice("translate deadline (\(translateDeadline, privacy: .public)s) exceeded after \(Date().timeIntervalSince(translateStart), privacy: .public)s, texts=\(uniqueTexts.count, privacy: .public), totalChars=\(uniqueTexts.reduce(0) { $0 + $1.unicodeScalars.count }, privacy: .public)")
            // See directAppleSession's doc comment - this is the outer scope
            // that has to do the cancelling, since the abandoned call's own
            // await may never return to reach its own catch block.
            cancelAbandonedDirectSession()
            await publish(status: .timedOut, generation: generation)
        } catch TranslationProviderError.missingAPIKey {
            // The one failure that provably never reached Google: thrown by
            // GoogleTranslationProvider before it ever opens a connection, so
            // the reservation above was never earned.
            if providerRaw == "google" {
                await recordGoogleUsage(characters: -googleCharacters, words: -googleWords)
            }
            liveTranslationDiagLog.notice("translate failed with TranslationProviderError: missingAPIKey")
            await publish(status: Self.status(for: .missingAPIKey), generation: generation)
        } catch let error as TranslationProviderError {
            // .private, not .public: a network error's description can embed
            // the failing request (URL, headers), and this path carries the
            // Google provider's requests.
            liveTranslationDiagLog.notice("translate failed with TranslationProviderError: \(String(describing: error), privacy: .private)")
            await publish(status: Self.status(for: error), generation: generation)
        } catch {
            liveTranslationDiagLog.notice("translate failed with error: \(String(describing: error), privacy: .private)")
            cancelAbandonedDirectSession()
            await publish(status: .failed, generation: generation)
        }
    }

    /// Whether the macOS 26+ direct-session fast path is usable for this
    /// language pair - checked (and the result cached in `installedDirectPair`)
    /// once per pair per live session, only for the Apple provider. False
    /// everywhere else - older macOS, the person has explicitly switched
    /// back to the compatibility architecture in Settings
    /// (`DefaultsKey.liveTranslationEngine`, the same preference `runLoop`
    /// checks for the OCR engine choice - one user-visible toggle
    /// conceptually switches both halves of "the macOS 26 architecture" at
    /// once), or a pair that still needs downloading - in which case
    /// `translateViaAppleSession` falls back to the stream-bridged
    /// `LiveTranslationSessionHost` path exactly as before.
    /// `LanguageAvailability.status` only reports `.installed` for a pair
    /// the person already has on-device - the direct initializer has no
    /// download-consent UI of its own, so anything short of `.installed` is
    /// deliberately left to the bridged path, which does. Deliberately does
    /// *not* build or cache a `TranslationSession` itself - see
    /// `directAppleSession`'s doc comment for why a fresh one is built per
    /// call instead.
    private func directSessionIsAvailable(source: AppLanguage, target: AppLanguage) async -> Bool {
        guard #available(macOS 26.0, *),
              UserDefaults.standard.string(forKey: DefaultsKey.liveTranslationEngine) != "compatibility"
        else { return false }
        if let pair = installedDirectPair, pair.source == source, pair.target == target { return true }
        let sourceLanguage = Locale.Language(identifier: source.rawValue)
        let targetLanguage = Locale.Language(identifier: target.rawValue)
        let status = await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage)
        liveTranslationDiagLog.notice("LanguageAvailability.status = \(String(describing: status), privacy: .public) for \(source.rawValue, privacy: .public)->\(target.rawValue, privacy: .public)")
        guard status == .installed else { return false }
        installedDirectPair = (source, target)
        return true
    }

    /// `TranslationSession.cancel()` is itself macOS 26+ only, but the
    /// call sites that need it (`translateAndPublish`'s deadline-exceeded/
    /// generic catch blocks) run on this feature's macOS 15+ floor - wrapped
    /// here so those call sites don't each need their own `#available`
    /// check around a property that's already nil on older macOS anyway.
    private func cancelAbandonedDirectSession() {
#if compiler(>=6.2)
        guard #available(macOS 26.0, *) else { return }
        directAppleSession?.cancel()
        directAppleSession = nil
#endif
    }

    /// Google's usage cap is enforced against the *persisted* total, not an
    /// in-memory one, so it stays correct across app relaunches. A plain
    /// `UserDefaults` read is safe here without the `@MainActor` hop
    /// `recordGoogleUsage` uses below - `translateAndPublish` only ever
    /// runs sequentially on this service's own loop task, never
    /// concurrently with itself, so there's no concurrent writer this read
    /// could race.
    private func googleUsageWouldExceedCap(characters: Int) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: DefaultsKey.liveTranslationGoogleUsageCapEnabled) else { return false }
        let cap = Defaults.sanitizedGoogleUsageCap(
            defaults.integer(forKey: DefaultsKey.liveTranslationGoogleUsageCapCharacters))
        let current = defaults.integer(forKey: DefaultsKey.liveTranslationGoogleCharacterCount)
        return current + characters > cap
    }

    /// The one place the persisted usage totals are mutated - hopped to the
    /// main actor, unlike this feature's loop task in general, since this is
    /// a read-modify-write pair and `UserDefaults` itself doesn't make that
    /// atomic.
    @MainActor
    private func recordGoogleUsage(characters: Int, words: Int) {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: DefaultsKey.liveTranslationGoogleCharacterCount) + characters,
                     forKey: DefaultsKey.liveTranslationGoogleCharacterCount)
        defaults.set(defaults.integer(forKey: DefaultsKey.liveTranslationGoogleWordCount) + words,
                     forKey: DefaultsKey.liveTranslationGoogleWordCount)
    }

    /// Sends every text in `texts` as one batch via `TranslationSession.
    /// translations(from:)` rather than one sequential `session.translate(_:)`
    /// await per text - correlates each response back to its request
    /// position via `clientIdentifier` (each request's own index, as a
    /// string) rather than assuming response order matches request order,
    /// since nothing in `TranslationSession`'s own contract guarantees that.
    /// Shared between the macOS 26+ direct session path above and the
    /// SwiftUI `.translationTask`-bridged path (`LiveTranslationSessionHost`
    /// in LiveTranslationOverlay.swift) so both batch identically.
    static func batchTranslate(_ texts: [String], using session: TranslationSession) async throws -> [String] {
        guard !texts.isEmpty else { return [] }
        let requests = texts.indices.map { index in
            TranslationSession.Request(sourceText: texts[index], clientIdentifier: String(index))
        }
        let start = Date()
        do {
            let responses = try await session.translations(from: requests)
            liveTranslationDiagLog.notice("batchTranslate: \(requests.count, privacy: .public) requests -> \(responses.count, privacy: .public) responses in \(Date().timeIntervalSince(start), privacy: .public)s")
            var byIndex: [Int: String] = [:]
            for response in responses {
                guard let id = response.clientIdentifier, let index = Int(id) else { continue }
                byIndex[index] = response.targetText
            }
            return texts.indices.map { byIndex[$0] ?? "" }
        } catch {
            liveTranslationDiagLog.notice("batchTranslate: \(requests.count, privacy: .public) requests threw after \(Date().timeIntervalSince(start), privacy: .public)s: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private static func status(for error: TranslationProviderError) -> Status {
        switch error {
        case .notInstalled: return .notInstalled
        case .sessionNotReady: return .sessionNotReady
        case .missingAPIKey: return .missingAPIKey
        case .invalidAPIKeyOrQuota: return .invalidAPIKeyOrQuota
        case .serverError: return .serverError
        case .network: return .failed
        }
    }

    /// Yields a request onto `appleRequestStream` and suspends until
    /// whichever `.translationTask` is currently consuming it calls back
    /// with a result - see `appleRequestStream`'s doc comment for why this
    /// indirection exists instead of calling a captured session directly.
    ///
    /// `inFlightAppleTranslateCount` increments right before the request is
    /// actually handed to a consumer (skipped entirely if there's no
    /// consumer to hand it to) and decrements only when the SessionHost's
    /// own `reply` closure fires - i.e. when `session.translate()` has
    /// genuinely returned or thrown inside the SessionHost's own task - not
    /// merely when `box` resolves, since `onCancel` below resolves `box`
    /// (letting this function return promptly) without the underlying
    /// `session.translate()` call in the SessionHost's task having actually
    /// finished. Conflating the two was the original bug this counter fixes:
    /// cancelling `loopTask` would make this function return immediately
    /// while Translation's internals were still working on the real call.
    private func translateViaAppleSession(texts: [String], source: AppLanguage?, target: AppLanguage) async throws -> [String] {
        // The macOS 26+ direct session, when available, is preferred over
        // the stream-bridged path below - no SwiftUI view lifecycle
        // involved at all, so none of `inFlightAppleTranslateCount`'s
        // teardown-timing hazard applies to it. `batchTranslate` sends every
        // text as one batch rather than awaiting `translate(_:)` once per
        // text in a loop - a large captured region routinely produces many
        // more separate paragraph/list-item/table-cell groups than a small
        // one, and awaiting each one in turn easily blows the deadline
        // `translateAndPublish` puts around the whole call. A fresh session
        // is built for this call specifically (not reused across ticks) -
        // see `directAppleSession`'s doc comment for why.
#if compiler(>=6.2)
        if let source, #available(macOS 26.0, *), await directSessionIsAvailable(source: source, target: target) {
            let sourceLanguage = Locale.Language(identifier: source.rawValue)
            let targetLanguage = Locale.Language(identifier: target.rawValue)
            let session = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
            directAppleSession = session
            do {
                let results = try await Self.batchTranslate(texts, using: session)
                directAppleSession = nil
                return results
            } catch TranslationError.unsupportedLanguagePairing {
                directAppleSession = nil
                throw TranslationProviderError.notInstalled
            }
            // Any other error deliberately leaves `directAppleSession` set -
            // translateAndPublish's own deadline-exceeded/generic catch
            // blocks are what clear and `.cancel()` it in that case, not
            // here, since an abandoned call's `await` above may simply
            // never return once its enclosing task is cancelled.
        }
#endif

        // The SwiftUI-hosted bridged session mounts asynchronously -
        // `.onAppear` runs on SwiftUI's own next render pass, not
        // synchronously with `begin(region:)` - so a translate call landing
        // in the brief window before that happens would otherwise fail
        // outright with `sessionNotReady` and flash the status red, even
        // though the session is only ever a beat away from being ready. This
        // isn't rare: every `begin(region:)` - the first selection, or any
        // resize/move, each of which builds a brand new overlay and session
        // from scratch - hits it.
        //
        // A resize specifically can also hand back a continuation that's
        // non-nil but already finished: `begin(region:)` only *hides* the
        // outgoing overlay immediately, deferring its actual teardown
        // (`teardownWhenSafe`) until no Apple-session translate is in flight
        // - by design, to avoid the crash that deferred teardown itself
        // exists to prevent. That means the outgoing overlay's own
        // `SessionHost` can genuinely still be alive - its `.onAppear`
        // having already `finish()`-ed the previous stream - for a window
        // after the new one's `.onAppear` has run and reassigned
        // `appleRequestContinuation` to a fresh stream, and vice versa
        // depending on ordering; either way, a caller can observe a
        // continuation that was live a moment ago and is now stale.
        // Confirmed via diagnostic logging: `.yield()` returning `.terminated`
        // rather than `.enqueued`, immediately after a resize. Retrying -
        // wait for a *newer* continuation, try again - rather than failing
        // outright on the first stale read is what actually survives that
        // window; `appleRequestContinuationGeneration` is what lets a retry
        // tell "genuinely newer" apart from "the same stale one, re-read,"
        // since `AsyncStream.Continuation` itself has no `Equatable`
        // conformance to compare against directly.
        let deadline = Date().addingTimeInterval(2.0)
        var minGeneration = 0
        while true {
            guard let continuation = await waitForAppleRequestContinuation(minGeneration: minGeneration, deadline: deadline)
            else {
                liveTranslationDiagLog.notice("bridged fallback: no continuation available before deadline")
                throw TranslationProviderError.sessionNotReady
            }
            let box = ResumeOnce<[String]>()
            do {
                return try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { cont in
                        box.assign(cont)
                        inFlightAppleTranslateCount += 1
                        let request = AppleTranslateRequest(texts: texts) { [weak self] result in
                            self?.inFlightAppleTranslateCount -= 1
                            box.resume(with: result)
                        }
                        let yieldResult = continuation.yield(request)
                        if case .enqueued = yieldResult {} else {
                            inFlightAppleTranslateCount -= 1
                            box.resume(with: .failure(YieldTerminatedError()))
                        }
                    }
                } onCancel: {
                    box.resume(with: .failure(CancellationError()))
                }
            } catch is YieldTerminatedError {
                liveTranslationDiagLog.notice("bridged fallback: yield hit a stale continuation, retrying")
                minGeneration = appleRequestContinuationGeneration + 1
                guard Date() < deadline else { throw TranslationProviderError.sessionNotReady }
                continue
            }
        }
    }

    /// Polls for up to `deadline` for `appleRequestContinuation` to be both
    /// non-nil and at least `minGeneration` - see this call site's own
    /// comment for why a retry needs to wait for a genuinely newer
    /// continuation, not just any non-nil one, so it can't spin forever
    /// re-observing the exact same stale value. Checks `Task.isCancelled`
    /// each pass so a cancelled caller's wait exits immediately rather than
    /// busy-looping - `Task.sleep` itself only throws on cancellation, it
    /// doesn't shrink the remaining wait, and this loop's `try?` deliberately
    /// swallows that throw so the *cancellation check* is what ends the
    /// wait, not the sleep's own error.
    private func waitForAppleRequestContinuation(minGeneration: Int, deadline: Date) async
        -> AsyncStream<AppleTranslateRequest>.Continuation? {
        while !Task.isCancelled, Date() < deadline {
            if appleRequestContinuationGeneration >= minGeneration, let candidate = appleRequestContinuation {
                return candidate
            }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        return nil
    }

    /// Defers actually deallocating `controller`'s SwiftUI content
    /// (`teardown()`) until `inFlightAppleTranslateCount` reaches zero,
    /// bounded by a short timeout so a genuinely stuck call can't hang
    /// cleanup forever - past that, teardown proceeds anyway, accepting the
    /// now much narrower residual risk. `controller` is already `hide()`d by
    /// the caller before this runs, so the panel disappears immediately;
    /// only the actual deallocation (and the `.translationTask` cancellation
    /// that comes with it) is delayed.
    private func teardownWhenSafe(_ controller: LiveTranslationOverlayController?) {
        guard let controller else { return }
        Task { [weak self] in
            await self?.waitForInFlightAppleTranslation(timeoutSeconds: 2.5)
            controller.teardown()
        }
    }

    private func waitForInFlightAppleTranslation(timeoutSeconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while inFlightAppleTranslateCount > 0, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Runs on the full joined text (far more context than one OCR line),
    /// so it's far more reliable than per-string auto-detect. Skipped
    /// entirely once the person pins an explicit source in Settings.
    @MainActor
    private func publish(lines: [LiveTranslationSupport.TranslatedLine]? = nil,
                         status: Status, generation: Int) {
        guard self.generation == generation else { return }
        if let lines { self.lines = lines }
        self.status = status
    }

    /// A coarse visual fingerprint of `image` - draws it scaled down into a
    /// fixed-size 16x16 buffer and hashes those bytes, so the cost is
    /// constant regardless of the capture's real resolution (a fresh, tiny
    /// `CGContext` draw, not a full-resolution byte scan). Two captures of
    /// genuinely unchanged content hash the same even with the kind of
    /// single-pixel anti-aliasing/compression jitter between them that made
    /// `joinedTextHash` (computed from OCR results, at full text fidelity)
    /// occasionally miss a match it should have had - the averaging that
    /// comes from scaling 16x16 washes exactly that jitter out. Used to skip
    /// the expensive `RecognizeDocumentsRequest`/`VNRecognizeTextRequest`
    /// pass entirely on a tick where the screen hasn't visually changed at
    /// all, not just to skip re-translating.
    private static func quickImageFingerprint(_ image: CGImage) -> Int {
        let side = 16
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return 0 }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let buffer = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var hasher = Hasher()
        for offset in 0..<(side * side * 4) { hasher.combine(buffer[offset]) }
        return hasher.finalize()
    }

    private static func recognizeLines(in image: CGImage, fallbackLanguages: [String])
        -> [LiveTranslationSupport.RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        if !fallbackLanguages.isEmpty,
           let supported = try? request.supportedRecognitionLanguages() {
            let available = fallbackLanguages.filter { supported.contains($0) }
            if !available.isEmpty { request.recognitionLanguages = available }
        }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { observation -> LiveTranslationSupport.RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return LiveTranslationSupport.RecognizedLine(boundingBox: observation.boundingBox,
                                                          text: candidate.string)
        }
    }

    /// Vision's own document-layout API - hierarchical and structural,
    /// no geometry guessing - available from macOS 26
    /// (`RecognizeDocumentsRequest`, verified against this SDK's own
    /// Vision.swiftinterface, not guessed). Returns paragraphs, list items,
    /// and table cells each as their own group, in exactly the shape
    /// `LiveTranslationSupport.groupIntoParagraphs` produces from flat OCR
    /// lines on older systems, so nothing downstream (`classifyParagraphGroups`,
    /// `unionBoundingBox`, `joinedParagraphText`, `rowCount = group.count`)
    /// needs to change to consume it. `NormalizedRect.cgRect` is normalized
    /// with a lower-left origin, the same convention `VNRecognizeTextRequest`'s
    /// `observation.boundingBox` already uses, so it drops straight into
    /// `RecognizedLine.boundingBox` unconverted.
    ///
    /// Reads exactly one level of structure - `container.paragraphs`
    /// directly, plus each top-level list item's and table cell's own
    /// content, with no further recursion into whatever *those* contain.
    /// An earlier version of this function recursed into
    /// `List.Item.content`/`Table.Cell.content` (each its own nested
    /// `Container`) to also surface list/table text - but that recursion,
    /// not lists or tables themselves, is what a self-referential
    /// `Container` `RecognizeDocumentsRequest` can apparently hand back on
    /// some real-world captures turns into a real problem: first a
    /// stack-overflow crash (SIGBUS, "excessive recursion", confirmed via a
    /// live crash report), then - even after bounding the recursion - a
    /// capture that should have produced a few dozen paragraphs instead
    /// producing 1,570 near-duplicates, slow enough to translate that it
    /// blew the deadline around the whole batch. Reading one level
    /// (`item.itemString`/`cell.content.text`, `item.content.boundingRegion`/
    /// `cell.content.boundingRegion` - none of it a walk into a nested
    /// `Container`'s own `.lists`/`.tables`) still surfaces that content
    /// while making the self-referential-cycle class of bug structurally
    /// impossible: there's no recursive call left for a cycle to run away
    /// inside of.
#if compiler(>=6.2)
    @available(macOS 26.0, *)
    private static func recognizeDocumentGroups(in image: CGImage, fallbackLanguages: [String]) async
        -> [[LiveTranslationSupport.RecognizedLine]] {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        // Every downstream consumer takes a paragraph's/line's single
        // `.transcript` as final - there's no code path that ever looks at
        // an alternate candidate - so asking Vision for just one is pure
        // saved work, not an accuracy trade-off.
        request.textRecognitionOptions.maximumCandidateCount = 1
        // This feature only ever reads `.paragraphs`/`.lists`/`.tables` -
        // `.barcodes` is never touched anywhere in this codebase, so paying
        // for that detection pass on every tick is pure waste.
        request.barcodeDetectionOptions.enabled = false
        if !fallbackLanguages.isEmpty {
            let candidates = fallbackLanguages.map { Locale.Language(identifier: $0) }
            let supported = Set(request.supportedRecognitionLanguages.map(\.minimalIdentifier))
            let available = candidates.filter { supported.contains($0.minimalIdentifier) }
            if !available.isEmpty { request.textRecognitionOptions.recognitionLanguages = available }
        }
        guard let observations = try? await request.perform(on: image, orientation: nil) else { return [] }

        func lines(_ text: DocumentObservation.Container.Text) -> [LiveTranslationSupport.RecognizedLine] {
            text.lines.map { LiveTranslationSupport.RecognizedLine(boundingBox: $0.boundingBox.cgRect, text: $0.transcript) }
        }

        var groups: [[LiveTranslationSupport.RecognizedLine]] = []
        for observation in observations {
            let container = observation.document
            for paragraph in container.paragraphs {
                let paragraphLines = lines(paragraph)
                if !paragraphLines.isEmpty { groups.append(paragraphLines) }
            }
            for list in container.lists {
                for item in list.items {
                    let itemLines = lines(item.content.text)
                    if !itemLines.isEmpty {
                        groups.append(itemLines)
                    } else if !item.itemString.isEmpty {
                        groups.append([LiveTranslationSupport.RecognizedLine(
                            boundingBox: item.content.boundingRegion.boundingBox.cgRect, text: item.itemString)])
                    }
                }
            }
            for table in container.tables {
                for row in table.rows {
                    for cell in row {
                        let cellLines = lines(cell.content.text)
                        if !cellLines.isEmpty { groups.append(cellLines) }
                    }
                }
            }
        }
        return groups
    }
#endif
}

/// One unit of work for LiveTranslationSessionHost's `for await` loop: the
/// texts to translate, and a callback to report the results back through.
struct AppleTranslateRequest {
    let texts: [String]
    let reply: @Sendable (Result<[String], Error>) -> Void
}

/// Resumes a checked continuation exactly once no matter which side gets
/// there first: the async reply callback, or cancellation. `assign` and
/// `resume` can race (cancellation can fire before the continuation closure
/// finishes running), so a resume that arrives first is held until the
/// continuation is assigned, rather than requiring a strict ordering.
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pendingResult: Result<T, Error>?
    private var didResume = false

    func assign(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        if let pendingResult {
            didResume = true
            continuation.resume(with: pendingResult)
        } else {
            self.continuation = continuation
        }
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        if let continuation {
            didResume = true
            continuation.resume(with: result)
        } else {
            pendingResult = result
        }
    }
}

/// Races `operation` against a timeout, returning nil if the timeout wins.
private func withDeadline<T: Sendable>(seconds: TimeInterval,
                                       operation: @escaping @Sendable () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        defer { group.cancelAll() }
        return (await group.next() ?? nil)
    }
}

private struct DeadlineExceeded: Error {}

/// Internal signal only - caught and retried inside `translateViaAppleSession`
/// itself, never surfaces past it. See that function's own comment for why
/// a stale-but-non-nil `appleRequestContinuation` is a real, expected case
/// around a resize, not a genuine failure.
private struct YieldTerminatedError: Error {}

/// Throwing variant: the timeout side throws `DeadlineExceeded` instead of
/// returning nil, so a stalled translation call surfaces as a distinct,
/// visible status rather than a silent no-op tick.
private func withThrowingDeadline<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw DeadlineExceeded()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw DeadlineExceeded() }
        return result
    }
}
