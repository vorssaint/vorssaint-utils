// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived from Glance (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.
//
//  Rolling-window driver for the liveness cues. Takes `LivenessFrame`, not
//  `FaceRecognitionResult`, keeping this file's dependency graph shallow enough
//  to compile standalone in `tools/liveness_selftest.swift`.

import Foundation

@MainActor
final class LivenessAnalyzer {
    private let windowDuration: TimeInterval

    /// Read fresh on every `observe()`, not captured at init, so a mid-scan Settings change takes effect immediately.
    var modeProvider: () -> LivenessMode = { .light }
    var tuningProvider: () -> LivenessTuning = { .default }
    /// Face Lab can switch individual cues off to isolate one; the unlock
    /// path leaves this at "all enabled."
    var enabledCuesProvider: () -> Set<LivenessCue> = { Set(LivenessCue.allCases) }

    private var frames: [LivenessFrame] = []
    private var evaluator = LivenessEvaluator()
    private(set) var lastSnapshot = LivenessSnapshot.empty
    /// Kept for Face Lab's diagnostics panel (excess ratio, coherence, pair
    /// counts, yaw range) — the numbers behind the flat-vs-3D cue's level.
    private(set) var lastGeometry = GeometryLivenessResult.empty

    init(windowDuration: TimeInterval = 2.0) {
        self.windowDuration = windowDuration
    }

    func reset() {
        frames.removeAll()
        evaluator.reset()
        lastSnapshot = .empty
        lastGeometry = .empty
    }

    /// Call once per frame with a detected face, regardless of whether it matched an identity,
    /// so liveness stays an independent gate. The window is time-pruned (~2s) but the evaluator's
    /// fire counts are not — they accumulate across the whole scan, so a spoof tell can't be waited out.
    @discardableResult
    func observe(_ frame: LivenessFrame) -> LivenessSnapshot {
        frames.append(frame)
        frames.removeAll { frame.timestamp.timeIntervalSince($0.timestamp) > windowDuration }

        evaluator.mode = modeProvider()
        evaluator.tuning = tuningProvider()
        evaluator.enabledCues = enabledCuesProvider()

        let geometry = GeometryLiveness.evaluate(frames)
        lastGeometry = geometry

        let readings = LivenessCues.readings(window: frames, geometry: geometry)
        let snapshot = evaluator.observe(readings)
        lastSnapshot = snapshot
        return snapshot
    }
}
