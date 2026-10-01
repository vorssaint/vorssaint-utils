// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Rapid Serial Visual Presentation: one chunk of text at a time, flashed at
/// a fixed screen position for exactly as long as its own word count,
/// punctuation and length call for. A reader who never has to move their
/// eyes to find the next word can take text in faster than they can scan a
/// normal paragraph — that is the whole premise, and it is also why the
/// driver below is a chain of single-shot timers rather than one repeating
/// timer: every chunk owns a duration that can differ from its neighbors',
/// so no fixed interval could ever be correct for all of them.
///
/// Owns playback state only. This class is compiled into the test
/// executable on its own, separate from the rest of the feature, so it may
/// depend on nothing beyond `FastReaderEngine`'s types, Foundation and
/// Combine — never `FastReaderService`, a view, `Notifier` or
/// `FeatureStrings`. Presentation and permission concerns live in the
/// service instead. Main thread only, like the rest of the app's
/// UI-adjacent state.
final class FastReaderSession: ObservableObject {
    static let shared = FastReaderSession()

    @Published private(set) var chunks: [ReaderChunk] = []
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isFinished = false
    @Published private(set) var wordsPerMinute = ReaderOptions.default.wordsPerMinute

    private var options = ReaderOptions.default

    /// How much reading is left from each index onwards, in units that do not
    /// depend on the speed. A chunk's duration is `60 / wpm` times its word
    /// count times its pause multipliers, so multiplying a duration back by
    /// the speed it was measured at leaves something the speed cancels out of.
    /// Storing the suffix sums once means the time left is a lookup rather
    /// than a walk over every chunk still to come, on every step, and it
    /// survives a speed change without being rebuilt.
    private var remainingWeights: [TimeInterval] = []
    private var timer: Timer?

    /// `shared` is the app's one reader; the tests build sessions of their
    /// own to exercise the state machine without a window, so the
    /// initializer stays accessible rather than private.
    init() {}

    var currentChunk: ReaderChunk? {
        chunks.indices.contains(index) ? chunks[index] : nil
    }

    /// How far the current chunk sits into the whole selection, as a
    /// fraction from just past the start to fully read. Zero for an empty
    /// session rather than dividing by zero.
    var progress: Double {
        guard !chunks.isEmpty else { return 0 }
        return Double(index + 1) / Double(chunks.count)
    }

    /// Tokenizes and chunks the whole text up front, so scrubbing and
    /// stepping are instant array lookups rather than re-running the engine.
    /// Always opens paused at the first chunk — playback is a separate,
    /// deliberate call the service only makes once whatever surface shows
    /// the controls is actually on screen.
    func load(_ text: String, options: ReaderOptions) {
        cancelTimer()
        self.options = options
        wordsPerMinute = options.wordsPerMinute
        chunks = FastReaderEngine.chunk(FastReaderEngine.tokenize(text), size: options.chunkSize)
        index = 0
        isPlaying = false
        // A single chunk has nowhere left to advance to, so the session
        // opens already at the end rather than claiming to be mid-playback
        // of something with no more steps.
        isFinished = chunks.count <= 1 && !chunks.isEmpty
        rebuildRemainingWeights()
    }

    /// Suffix sums of every chunk's speed-independent weight, with a trailing
    /// zero so the index after the last chunk reads as nothing left.
    private func rebuildRemainingWeights() {
        var sums = [TimeInterval](repeating: 0, count: chunks.count + 1)
        var measured = options
        measured.wordsPerMinute = FastReaderEngine.wordsPerMinuteRange.lowerBound
        let speed = TimeInterval(measured.wordsPerMinute)
        for i in stride(from: chunks.count - 1, through: 0, by: -1) {
            sums[i] = sums[i + 1] + FastReaderEngine.duration(for: chunks[i], options: measured) * speed
        }
        remainingWeights = sums
    }

    /// Seconds of reading left at the current speed, counting the chunk on
    /// screen. Zero once there is nothing left to read.
    var remainingSeconds: TimeInterval {
        guard remainingWeights.indices.contains(index) else { return 0 }
        // The published speed is clamped everywhere it is set, but dividing by
        // it is the one place a bad value would become an infinity rather than
        // a wrong number, so it is clamped here too.
        let speed = min(max(wordsPerMinute, FastReaderEngine.wordsPerMinuteRange.lowerBound),
                        FastReaderEngine.wordsPerMinuteRange.upperBound)
        return remainingWeights[index] / TimeInterval(speed)
    }

    func play() {
        guard !chunks.isEmpty, !isFinished else { return }
        isPlaying = true
        scheduleStep()
    }

    func pause() {
        cancelTimer()
        isPlaying = false
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func stepBackward() {
        cancelTimer()
        isPlaying = false
        setIndex(index - 1)
    }

    func stepForward() {
        cancelTimer()
        isPlaying = false
        setIndex(index + 1)
    }

    func seek(to newIndex: Int) {
        cancelTimer()
        isPlaying = false
        setIndex(newIndex)
    }

    func restart() {
        cancelTimer()
        isPlaying = false
        setIndex(0)
    }

    /// Clamped into the engine's supported range and never moves `index`:
    /// changing your mind about the speed mid-sentence should not also lose
    /// your place in it. A step already waiting is rescheduled from the new
    /// speed instead of being left to fire on the old one.
    func setWordsPerMinute(_ value: Int) {
        let range = FastReaderEngine.wordsPerMinuteRange
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        wordsPerMinute = clamped
        options.wordsPerMinute = clamped
        if isPlaying {
            cancelTimer()
            scheduleStep()
        }
    }

    func teardown() {
        remainingWeights = []
        cancelTimer()
        chunks = []
        index = 0
        isPlaying = false
        isFinished = false
    }

    // MARK: - Driver

    /// One single-shot timer for the chunk that is current right now. On
    /// fire, `advance()` either moves on and schedules the next chunk's own
    /// timer, or stops at the end — there is never a repeating timer to
    /// desynchronize from a duration that just changed.
    private func scheduleStep() {
        guard let chunk = currentChunk else { return }
        let duration = FastReaderEngine.duration(for: chunk, options: options)
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.advance()
        }
    }

    private func advance() {
        guard index + 1 < chunks.count else {
            isPlaying = false
            isFinished = true
            return
        }
        index += 1
        scheduleStep()
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Shared clamp-and-recompute for every way the index changes by hand:
    /// stepping, seeking and restarting all land here so `isFinished` can
    /// never drift from where `index` actually points.
    private func setIndex(_ newIndex: Int) {
        guard !chunks.isEmpty else {
            index = 0
            isFinished = false
            return
        }
        index = min(max(newIndex, 0), chunks.count - 1)
        isFinished = index == chunks.count - 1
    }
}
